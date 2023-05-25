// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// Interface for the Randomizer VRF contract
interface IRandomizer {
    // Makes a Randomizer VRF callback request with a callback gas limit
    function request(uint256 callbackGasLimit) external returns (uint256);

    // Estimates the VRF fee given a callback gas limit
    function estimateFee(uint256 callbackGasLimit) external returns (uint256);

    // Deposits ETH to Randomizer for the client contract
    function clientDeposit(address client) external payable;

    // Withdraws deposited ETH from the client contract to the destination address
    function clientWithdrawTo(address to, uint256 amount) external;

    function getFeeStats(
        uint256 request
    ) external view returns (uint256[2] memory);

    // Gets the amount of ETH deposited and reserved for the client contract
    function clientBalanceOf(
        address _client
    ) external view returns (uint256 deposit, uint256 reserved);

    // Returns the request data
    function getRequest(
        uint256 request
    )
        external
        view
        returns (
            bytes32 result,
            bytes32 dataHash,
            uint256 ethPaid,
            uint256 ethRefunded,
            bytes10[2] memory vrfHashes
        );
}

// Main contract
contract CoinFlip {
    // Struct to hold the details of a coinflip game
    struct CoinFlipGame {
        address player;
        bool prediction;
        bool result;
        uint256 seed;
    }

    // Events to be emitted
    event Flip(address indexed player, uint256 indexed id, bool prediction);
    event FlipResult(
        address indexed player,
        uint256 indexed id,
        uint256 seed,
        bool prediction,
        bool result
    );
    event OwnerUpdated(address indexed user, address indexed newOwner);
    event Refund(address indexed player, uint256 amount, uint256 refundedGame);

    // Mappings to store game data and refundable amounts
    mapping(uint256 => CoinFlipGame) coinFlipGames;
    mapping(address => uint256[]) userToGames;
    mapping(address => uint256) userToLastCallback;
    mapping(uint256 => uint256) flipToDeposit;

    // Variables to store owner details
    address public owner;
    address public proposedOwner;

    // Reentrancy guard
    uint8 private reentrancyLock = 1;

    // Instance of the Randomizer VRF contract
    IRandomizer private randomizer;

    // Constructor to initialize the Randomizer VRF contract and set the owner
    constructor(address _randomizer) {
        randomizer = IRandomizer(_randomizer);
        owner = msg.sender;
        emit OwnerUpdated(address(0), owner);
    }

    // Modifier to prevent reentrant calls
    modifier reentrancyGuard() {
        require(reentrancyLock == 1, "Reentrant call");
        reentrancyLock = 2;
        _;
        reentrancyLock = 1;
    }

    // Function to initiate a coin flip game
    // We also refund any excess fees paid by the player in previous games
    function flip(bool prediction) external payable reentrancyGuard {
        // Ensure that the fee for the Randomizer VRF is covered
        // We add 25% as a buffer. Any excess will be refunded in future game callbacks.

        // IMPORTANT GAS LIMIT NOTES:
        // 1. We should make sure that our callback function's gas limit is predictable so the function can't run out of gas.
        // 2. If needed, we should calculate the callback gas limit dynamically based on expected for-loop iterations etc.
        // 3. Gas limit should also be updateable in production in case gas consumption for opcodes change in EVM.
        require(
            msg.value >= randomizer.estimateFee(100000),
            "Insufficient VRF fee"
        );
        // Deposit the fee to the Randomizer VRF
        randomizer.clientDeposit{value: msg.value}(address(this));
        // Request random bytes from the Randomizer VRF
        uint256 id = IRandomizer(randomizer).request(100000);
        // Store the game details
        userToGames[msg.sender].push(id);
        coinFlipGames[id] = CoinFlipGame(msg.sender, prediction, false, 0);
        // Store the deposit amount
        flipToDeposit[id] = msg.value;
        // Emit the Flip event
        emit Flip(msg.sender, id, prediction);
    }

    // Callback function to be called by the Randomizer VRF when the random bytes are ready
    function randomizerCallback(
        uint256 _id,
        bytes32 _value
    ) external reentrancyGuard {
        // Ensure that only the Randomizer VRF can call this function
        require(
            msg.sender == address(randomizer),
            "Only the randomizer contract can call this function"
        );
        // Retrieve the game details
        CoinFlipGame memory game = coinFlipGames[_id];
        // Convert the random bytes to a uint256
        uint256 seed = uint256(_value);
        game.seed = seed;
        // Determine the result of the coin flip
        bool headsOrTails = (seed % 2 == 0);
        game.result = headsOrTails;
        // Store the updated game details
        coinFlipGames[_id] = game;
        // Add the game id to the list of refundable games for the player
        _refund(game.player);
        // Store the new callback id for the player
        userToLastCallback[game.player] = _id;
        // Emit the FlipResult event
        emit FlipResult(game.player, _id, seed, game.prediction, headsOrTails);
    }

    // Function to refund all the completed games' excess deposits to a player
    function refund() external reentrancyGuard {
        require(_refund(msg.sender), "ZERO_REFUNDABLE");
    }

    // Function to refund all the completed games' excess deposits to a player
    // NOTE: The contract should have a small buffer of ETH to ensure there is always enough to refund
    function _refund(address player) private returns (bool) {
        uint256 refundableId = userToLastCallback[player];
        if (refundableId > 0) {
            uint256[2] memory feeStats = randomizer.getFeeStats(refundableId);
            if (flipToDeposit[refundableId] > feeStats[0]) {
                // Refund 90% of the excess deposit back to the player
                // We keep the rest as a buffer
                uint256 refundAmount = ((flipToDeposit[refundableId] -
                    feeStats[0]) * 9) / 10;

                // Check if the refundAmount is available
                // ethReserved is the amount currently reserved for pending requests
                (uint256 ethDeposit, uint256 ethReserved) = randomizer
                    .clientBalanceOf(address(this));
                if (refundAmount <= ethDeposit - ethReserved) {
                    // Refund the excess deposit to the player
                    randomizer.clientWithdrawTo(player, refundAmount);
                    emit Refund(player, refundAmount, refundableId);
                    delete userToLastCallback[player];
                    return true;
                }
            }
        }
        return false;
    }

    // Function to retrieve the details of a game
    function getGame(uint256 _id) external view returns (CoinFlipGame memory) {
        return coinFlipGames[_id];
    }

    // Function to retrieve the game ids for a player
    function getPlayerGameIds(
        address _player
    ) external view returns (uint256[] memory) {
        return userToGames[_player];
    }

    // Function to preview the result of a game
    function previewResult(bytes32 _value) external pure returns (bool) {
        bool headsOrTails = (uint256(_value) % 2 == 0);
        return headsOrTails;
    }

    // Function to allow the owner to withdraw their deposited Randomizer VRF funds
    function randomizerWithdraw(address _randomizer, uint256 amount) external {
        require(msg.sender == owner);
        IRandomizer(_randomizer).clientWithdrawTo(msg.sender, amount);
    }

    // Function to propose a new owner
    function proposeNewOwner(address _newOwner) external {
        // Ensure that only the current owner can propose a new owner
        require(msg.sender == owner);
        proposedOwner = _newOwner;
    }

    // Function to accept the proposed owner
    function acceptNewOwner(address _newOwner) external {
        // Ensure that only the proposed owner can accept the ownership
        require(msg.sender == proposedOwner && msg.sender == _newOwner);
        owner = proposedOwner;
        proposedOwner = address(0);
        // Emit the OwnerUpdated event
        emit OwnerUpdated(address(0), owner);
    }
}
