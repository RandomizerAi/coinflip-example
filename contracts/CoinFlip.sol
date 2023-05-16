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

    // Returns the fee paid by and refunded to the client
    function getFeeStats(uint256 id) external returns (uint256[2] memory);
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
    event Refund(address indexed player, uint256 amount);

    // Mappings to store game data and refundable amounts
    mapping(uint256 => CoinFlipGame) coinFlipGames;
    mapping(address => uint256[]) userToGames;
    mapping(address => uint256[]) userToRefundable;
    mapping(uint256 => uint256) flipToDeposit;

    // Variables to store owner details and refund amount
    address public owner;
    address public proposedOwner;
    uint256 public refundAmount;

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
        // Initialize the refund amount
        refundAmount = 0;
        // Iterate over the refundable games for the player
        for (uint i = 0; i < userToRefundable[msg.sender].length; i++) {
            uint256 refundId = userToRefundable[msg.sender][i];
            // Retrieve the fee stats for the game
            uint256[2] memory feeStats = randomizer.getFeeStats(refundId);
            // If the fee paid is less than the deposit, add the difference to the refund amount
            if (feeStats[0] < flipToDeposit[refundId]) {
                refundAmount += flipToDeposit[refundId] - feeStats[0];
            }
        }
        // If the refund amount is greater than zero, refund the amount to the player
        if (refundAmount > 0) {
            randomizer.clientWithdrawTo(msg.sender, refundAmount);
            emit Refund(msg.sender, refundAmount);
            // Clear the list of refundable games for the player
            delete userToRefundable[msg.sender];
        }
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
        userToRefundable[game.player].push(_id);
        // Emit the FlipResult event
        emit FlipResult(game.player, _id, seed, game.prediction, headsOrTails);
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
