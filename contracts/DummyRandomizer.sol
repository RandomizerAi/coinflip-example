// SPDX-License-Identifier: MIT
// Dummy contract to simulate the Randomizer VRF contract for testing

pragma solidity ^0.8.19;

contract DummyRandomizer {
    // Struct to hold the details of a request
    struct SRequest {
        bytes32 result;
        uint256 callbackGasLimit;
        uint256 ethPaid;
        address client;
    }

    // Events to be emitted
    event Request(uint256 indexed id);
    event Result(uint256 indexed id, bytes32 result);
    event CallbackFailed(uint256 indexed id, bytes data);

    // Mapping to store request data
    mapping(uint256 => SRequest) public requests;

    mapping(address => uint256) public clientToDeposit;

    // Counter for request ids
    uint256 public requestCounter;

    // Function to make a Randomizer VRF callback request with a callback gas limit
    function request(uint256 callbackGasLimit) external returns (uint256) {
        uint256 fee = estimateFee(callbackGasLimit);
        require(
            clientToDeposit[msg.sender] >= fee,
            "Randomizer: insufficient funds"
        );
        requestCounter++;
        requests[requestCounter] = SRequest(0, callbackGasLimit, 0, msg.sender);
        emit Request(requestCounter);
        return requestCounter;
    }

    function request(
        uint256 callbackGasLimit,
        uint256 confirmations
    ) external returns (uint256) {
        uint256 fee = estimateFee(callbackGasLimit);
        require(
            clientToDeposit[msg.sender] >= fee,
            "Randomizer: insufficient funds"
        );
        requestCounter++;
        requests[requestCounter] = SRequest(
            0,
            callbackGasLimit,
            fee,
            msg.sender
        );
        emit Request(requestCounter);
        return requestCounter;
    }

    // Function to estimate the VRF fee given a callback gas limit and confirmations
    function estimateFee(
        uint256 callbackGasLimit,
        uint256 confirmations
    ) public view returns (uint256) {
        // This is a dummy implementation, adjust as needed
        return callbackGasLimit * _maxGasPriceAfterConfirmations(confirmations);
    }

    // Function to estimate the VRF fee given a callback gas limit and 1 confirmation
    function estimateFee(
        uint256 callbackGasLimit
    ) public view returns (uint256) {
        // This is a dummy implementation, adjust as needed
        return callbackGasLimit * _maxGasPriceAfterConfirmations(1);
    }

    // Function to deposit ETH to Randomizer for the client contract
    function clientDeposit(address client) external payable {
        clientToDeposit[client] += msg.value;
    }

    // Function to withdraw deposited ETH from the client contract to the destination address
    function clientWithdrawTo(address to, uint256 amount) external {
        require(
            clientToDeposit[msg.sender] >= amount,
            "Randomizer: insufficient funds"
        );
        clientToDeposit[msg.sender] -= amount;
        payable(to).transfer(amount);
    }

    // Function to return the fee paid by and refunded to the client
    function getFeeStats(uint256 id) external view returns (uint256[2] memory) {
        return [requests[id].ethPaid, 0];
    }

    function getRequest(
        uint256 _request
    )
        external
        view
        returns (
            bytes32 result,
            bytes32 dataHash,
            uint256 ethPaid,
            uint256 ethRefunded,
            bytes10[2] memory vrfHashes
        )
    {
        // This is a dummy implementation, adjust as needed
        SRequest memory req = requests[_request];
        return (
            req.result,
            bytes32(blockhash(block.number - 1)),
            req.ethPaid,
            0,
            [bytes10(0), bytes10(0)]
        );
    }

    // Function to submit a random result
    function submitRandom(uint256 id, bytes32 value) external {
        uint256 startGas = gasleft() + 25000;
        // Get the request details
        SRequest memory _request = requests[id];
        // Call the client contract's randomizerCallback function with the specified gas limit
        (bool success, bytes memory data) = _request.client.call{
            gas: _request.callbackGasLimit
        }(
            abi.encodeWithSignature(
                "randomizerCallback(uint256,bytes32)",
                id,
                value
            )
        );

        if (!success) emit CallbackFailed(id, data);

        // Calculate the fee paid
        uint256 gasUsed = startGas - gasleft();
        uint256 ethPaid = gasUsed * tx.gasprice;

        // Save the fee paid to the request
        requests[id].ethPaid = ethPaid;
        requests[id].result = value;

        // Emit the Result event
        emit Result(id, value);
    }

    function _maxGasPriceAfterConfirmations(
        uint256 _confirmations
    ) internal view returns (uint256 maxGasPrice) {
        uint256 maxFee = block.basefee + (block.basefee / 4) + 1;
        maxGasPrice = tx.gasprice < maxFee ? tx.gasprice : maxFee;
        // maxFee goes up by 12.5% per confirmation, calculate the max fee for the number of confirmations
        if (_confirmations > 1) {
            uint256 i = 0;
            do {
                maxGasPrice += (maxGasPrice / 8) + 1;
                unchecked {
                    ++i;
                }
            } while (i < _confirmations);
        }
    }
}
