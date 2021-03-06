pragma solidity ^0.4.24;

import "chainlink/contracts/ChainlinkClient.sol";
import "chainlink/contracts/vendor/SafeMath.sol";
import "chainlink/contracts/vendor/Ownable.sol";


/**
 * @title An example Chainlink contract with aggregation
 * @notice Requesters can use this contract as a framework for creating
 * requests to multiple Chainlink nodes and running aggregation
 * as the contract receives answers.
 */
contract ExecutorPublicPriceAggregator is ChainlinkClient, Ownable {
    using SafeMath for uint256;

    struct Answer {
        uint256 minimumResponses;
        uint256 maxResponses;
        uint256 transactionID;
        uint256[] responses;
    }

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        bool executed;
    }

    uint256 public currentAnswer;
    uint256 public latestCompletedAnswer;
    uint256 public updatedHeight;
    uint256 public paymentAmount;
    uint256 public minimumResponses;
    bytes32[] public jobIds;
    address[] public oracles;
    Transaction[] public transactions;

    uint256 public answerCounter = 1;
    mapping(address => bool) public blacklistedRequesters;
    mapping(bytes32 => uint256) public requestAnswers;
    mapping(uint256 => Answer) public answers;
    mapping(address => uint256) public requestTokens;

    uint256 constant public MAX_ORACLE_COUNT = 45;

    event ResponseReceived(uint256 indexed response, uint256 indexed answerId, address indexed sender);
    event AnswerUpdated(uint256 indexed current, uint256 indexed answerId);
    event Execution(uint indexed transactionId, uint256 indexed answerId);
    event ExecutionFailure(uint indexed transactionId, uint256 indexed answerId);

    /**
    * @notice Deploy with the address of the LINK token and arrays of matching
    * length containing the addresses of the oracles and their corresponding
    * Job IDs.
    * @dev Sets the LinkToken address for the network, addresses of the oracles,
    * and jobIds in storage.
    * @param _link The address of the LINK token
    * @param _paymentAmount the amount of LINK to be sent to each oracle for each request
    * @param _minimumResponses the minimum number of responses
    * before an answer will be calculated
    * @param _oracles An array of oracle addresses
    * @param _jobIds An array of Job IDs
    */
    constructor(
        address _link,
        uint256 _paymentAmount,
        uint256 _minimumResponses,
        address[] _oracles,
        bytes32[] _jobIds
    )
        public
        Ownable()
    {
        setChainlinkToken(_link);
        updateRequestDetails(
            _paymentAmount,
            _minimumResponses,
            _oracles,
            _jobIds
        );
        transactions.push(
            Transaction(address(0), 0, "", true)
        );
    }

    /**
    * @notice Creates a Chainlink request for each oracle in the oracles array.
    * @dev This example does not include request parameters. Reference any documentation
    * associated with the Job IDs used to determine the required parameters per-request.
    */
    function requestRateUpdate()
        external
        ensureAuthorizedRequester()
        ensurePayment()
    {
        _requestRate();
        answers[answerCounter].minimumResponses = minimumResponses;
        answers[answerCounter].maxResponses = oracles.length;
        answerCounter = answerCounter.add(1);
    }

    function requestRateUpdateWithTransaction(
        address _destination,
        uint _value,
        bytes _data
    )
        external
        payable
        ensureAuthorizedRequester()
        ensurePayment()
        ensureValue(_value)
    {
        _requestRate();
        answers[answerCounter].minimumResponses = minimumResponses;
        answers[answerCounter].maxResponses = oracles.length;
        answers[answerCounter].transactionID = transactions.push(Transaction(_destination, _value, _data, false)) - 1;
        answerCounter = answerCounter.add(1);
    }

    /**
    * @notice Called by the owner to permission other addresses to generate new
    * requests to oracles.
    * @param _requester the address whose permissions are being set
    * @param _blacklisted boolean that determines whether the requester is
    * blacklisted or not
    */
    function setAuthorization(address _requester, bool _blacklisted)
        external
        onlyOwner()
    {
        blacklistedRequesters[_requester] = _blacklisted;
    }

    /**
    * @notice Cancels an outstanding Chainlink request.
    * The oracle contract requires the request ID and additional metadata to
    * validate the cancellation. Only old answers can be cancelled.
    * @param _requestId is the identifier for the chainlink request being cancelled
    * @param _payment is the amount of LINK paid to the oracle for the request
    * @param _expiration is the time when the request expires
    */
    function cancelRequest(
        bytes32 _requestId,
        uint256 _payment,
        uint256 _expiration
    )
        external
        ensureAuthorizedRequester()
    {
        uint256 answerId = requestAnswers[_requestId];
        require(answerId < latestCompletedAnswer, "Cannot modify an in-progress answer");

        cancelChainlinkRequest(
            _requestId,
            _payment,
            this.chainlinkCallback.selector,
            _expiration
        );

        delete requestAnswers[_requestId];
        answers[answerId].responses.push(0);
        deleteAnswer(answerId);
    }

    /**
    * @notice Receives the answer from the Chainlink node.
    * @dev This function can only be called by the oracle that received the request.
    * @param _clRequestId The Chainlink request ID associated with the answer
    * @param _response The answer provided by the Chainlink node
    */
    function chainlinkCallback(bytes32 _clRequestId, uint256 _response)
        external
    {
        validateChainlinkCallback(_clRequestId);

        uint256 answerId = requestAnswers[_clRequestId];
        delete requestAnswers[_clRequestId];

        answers[answerId].responses.push(_response);
        emit ResponseReceived(_response, answerId, msg.sender);
        updateLatestAnswer(answerId);
        deleteAnswer(answerId);
    }

    /**
    * @notice Called by the owner to kill the contract. This transfers all LINK
    * balance and ETH balance (if there is any) to the owner.
    */
    function destroy()
        external
        onlyOwner()
    {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        transferLINK(owner, link.balanceOf(address(this)));
        selfdestruct(owner);
    }

    /**
    * @notice Updates the arrays of oracles and jobIds with new values,
    * overwriting the old values.
    * @dev Arrays are validated to be equal length.
    * @param _paymentAmount the amount of LINK to be sent to each oracle for each request
    * @param _minimumResponses the minimum number of responses
    * before an answer will be calculated
    * @param _oracles An array of oracle addresses
    * @param _jobIds An array of Job IDs
    */
    function updateRequestDetails(
        uint256 _paymentAmount,
        uint256 _minimumResponses,
        address[] _oracles,
        bytes32[] _jobIds
    )
        public
        onlyOwner()
        validateAnswerRequirements(_minimumResponses, _oracles, _jobIds)
    {
        paymentAmount = _paymentAmount;
        minimumResponses = _minimumResponses;
        jobIds = _jobIds;
        oracles = _oracles;
    }

    /**
    * @notice Allows the owner of the contract to withdraw any LINK balance
    * available on the contract.
    * @dev The contract will need to have a LINK balance in order to create requests.
    * @param _recipient The address to receive the LINK tokens
    * @param _amount The amount of LINK to send from the contract
    */
    function transferLINK(address _recipient, uint256 _amount)
        public
        onlyOwner()
    {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(_recipient, _amount), "LINK transfer failed");
    }

    function calculateRequestFee()
        public
        view
        returns (uint256 _linkFee)
    {
        _linkFee = paymentAmount * oracles.length;
    }

    function _requestRate()
        private
    {
        Chainlink.Request memory request;
        bytes32 requestId;

        for (uint i = 0; i < oracles.length; i++) {
            request = buildChainlinkRequest(jobIds[i], this, this.chainlinkCallback.selector);
            requestId = sendChainlinkRequestTo(oracles[i], request, paymentAmount);
            requestAnswers[requestId] = answerCounter;
        }
    }

    /**
    * @dev Performs aggregation of the answers received from the Chainlink nodes.
    * Assumes that at least half the oracles are honest and so can't contol the
    * middle of the ordered responses.
    * @param _answerId The answer ID associated with the group of requests
    */
    function updateLatestAnswer(uint256 _answerId)
        private
        ensureMinResponsesReceived(_answerId)
        ensureOnlyLatestAnswer(_answerId)
    {
        uint256 responseLength = answers[_answerId].responses.length;
        uint256 middleIndex = responseLength.div(2);
        if (responseLength % 2 == 0) {
            uint256 median1 = quickselect(answers[_answerId].responses, middleIndex);
            uint256 median2 = quickselect(answers[_answerId].responses, middleIndex.add(1)); // quickselect is 1 indexed
            currentAnswer = median1.add(median2) / 2; // signed integers are not supported by SafeMath
        } else {
            currentAnswer = quickselect(answers[_answerId].responses, middleIndex.add(1)); // quickselect is 1 indexed
        }
        latestCompletedAnswer = _answerId;
        updatedHeight = block.number;
        emit AnswerUpdated(currentAnswer, _answerId);

        uint256 _id = answers[_answerId].transactionID;
        if (_id > 0 && transactions[_id].executed == false) {
            Transaction storage txn = transactions[_id];
            txn.executed = true;
            if (externalCall(txn.destination, txn.value, txn.data.length, txn.data))
                emit Execution(_id, _answerId);
            else {
                emit ExecutionFailure(_id, _answerId);
                txn.executed = false;
            }
        }
    }

    /**
    * @dev Returns the kth value of the ordered array
    * See: http://www.cs.yale.edu/homes/aspnes/pinewiki/QuickSelect.html
    * @param _a The list of elements to pull from
    * @param _k The index, 1 based, of the elements you want to pull from when ordered
    */
    function quickselect(uint256[] memory _a, uint256 _k)
        private
        pure
        returns (uint256)
    {
        uint256[] memory a = _a;
        uint256 k = _k;
        uint256 aLen = a.length;
        uint256[] memory a1 = new uint256[](aLen);
        uint256[] memory a2 = new uint256[](aLen);
        uint256 a1Len;
        uint256 a2Len;
        uint256 pivot;
        uint256 i;

        while (true) {
            pivot = a[aLen.div(2)];
            a1Len = 0;
            a2Len = 0;
            for (i = 0; i < aLen; i++) {
                if (a[i] < pivot) {
                    a1[a1Len] = a[i];
                    a1Len++;
                } else if (a[i] > pivot) {
                    a2[a2Len] = a[i];
                    a2Len++;
                }
            }
            if (k <= a1Len) {
                aLen = a1Len;
                (a, a1) = swap(a, a1);
            } else if (k > (aLen.sub(a2Len))) {
                k = k.sub(aLen.sub(a2Len));
                aLen = a2Len;
                (a, a2) = swap(a, a2);
            } else {
                return pivot;
            }
        }
    }

    /**
    * @dev Swaps the pointers to two uint256 arrays in memory
    * @param _a The pointer to the first in memory array
    * @param _b The pointer to the second in memory array
    */
    function swap(uint256[] memory _a, uint256[] memory _b)
        private
        pure
        returns(uint256[] memory, uint256[] memory)
    {
        return (_b, _a);
    }

    /**
    * @dev Cleans up the answer record if all responses have been received.
    * @param _answerId The identifier of the answer to be deleted
    */
    function deleteAnswer(uint256 _answerId)
        private
        ensureAllResponsesReceived(_answerId)
    {
        delete answers[_answerId];
    }

    // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function externalCall(address destination, uint value, uint dataLength, bytes data)
        internal
        returns (bool)
    {
        bool result;
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                sub(gas, 34710),   // 34710 is the value that solidity is currently emitting
                                    // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                                    // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
                destination,
                value,
                d,
                dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0                  // Output is ignored, therefore the output size is zero
            )
        }
        return result;
    }

    /**
    * @dev Prevents taking an action if the minimum number of responses has not
    * been received for an answer.
    * @param _answerId The the identifier of the answer that keeps track of the responses.
    */
    modifier ensureMinResponsesReceived(uint256 _answerId) {
        if (answers[_answerId].responses.length >= answers[_answerId].minimumResponses) {
            _;
        }
    }

    /**
    * @dev Prevents taking an action if not all responses are received for an answer.
    * @param _answerId The the identifier of the answer that keeps track of the responses.
    */
    modifier ensureAllResponsesReceived(uint256 _answerId) {
        if (answers[_answerId].responses.length == answers[_answerId].maxResponses) {
            _;
        }
    }

    /**
    * @dev Prevents taking an action if a newer answer has been recorded.
    * @param _answerId The current answer's identifier.
    * Answer IDs are in ascending order.
    */
    modifier ensureOnlyLatestAnswer(uint256 _answerId) {
        if (latestCompletedAnswer <= _answerId) {
            _;
        }
    }

    /**
    * @dev Ensures corresponding number of oracles and jobs.
    * @param _oracles The list of oracles.
    * @param _jobIds The list of jobs.
    */
    modifier validateAnswerRequirements(
        uint256 _minimumResponses,
        address[] _oracles,
        bytes32[] _jobIds
    ) {
        require(_oracles.length <= MAX_ORACLE_COUNT, "cannot have more than 45 oracles");
        require(_oracles.length >= _minimumResponses, "must have at least as many oracles as responses");
        require(_oracles.length == _jobIds.length, "must have exactly as many oracles as job IDs");
        _;
    }

    /**
    * @dev Reverts if `msg.sender` is blacklisted to make requests.
    */
    modifier ensureAuthorizedRequester() {
        require(
            !blacklistedRequesters[msg.sender] || msg.sender == owner,
            "Not an authorized address for creating requests"
        );
        _;
    }

    modifier ensurePayment() {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transferFrom(msg.sender, address(this), oracles.length * paymentAmount),
            "LINK transferFrom failed"
        );
        _;
    }

    modifier ensureValue(uint256 _value) {
        require(
            msg.value >= _value,
            "Insufficient value amount sent for callback transaction"
        );
        _;
    }
}
