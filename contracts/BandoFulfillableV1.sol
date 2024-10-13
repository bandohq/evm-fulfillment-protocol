// SPDX-License-Identifier: MIT

pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./IBandoFulfillable.sol";
import "./periphery/registry/FulfillableRegistry.sol";

/// Inspired in:
/// OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)
/// @title BandoFulfillableV1
/// @dev Base escrow contract, holds funds designated for a beneficiary until they
/// withdraw them or a refund is emitted.
///
/// Intended usage: 
/// This contract (and derived escrow contracts) should only be
/// interacted through the router or manager contracts. 
/// The contract that uses the escrow as its payment method 
/// should provide public methods redirecting to the escrow's deposit and withdraw.
contract BandoFulfillableV1 is
    IBandoFulfillable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable {
    using Address for address payable;
    using Math for uint256;

    /**********************/
    /* EVENT DECLARATIONS */
    /**********************/

    event DepositReceived(FulFillmentRecord record);
    event RefundWithdrawn(address indexed payee, uint256 weiAmount);
    event RefundAuthorized(address indexed payee, uint256 weiAmount);
    event FeeUpdated(uint256 serviceID, uint256 amount);

    /*****************************/
    /* STATE VARIABLES           */
    /*****************************/

    //Auto-incrementable id storage
    uint256 private _fulfillmentIdCount;

    // All fulfillment records keyed by their ids
    mapping(uint256 => FulFillmentRecord) private _fulfillmentRecords;

    // Deposits mapped to subject addresses
    mapping(address => uint256[]) private _fulfillmentRecordsForSubject;

    // Total deposits registered
    uint256 private _fulfillmentRecordCount;

    // The protocol manager address
    address public _manager;

    /// @dev The protocol router address
    address public _router;

    /// @dev The address of the fulfillable registry. Used to fetch service details.
    address public _fulfillableRegistry;

    /// @dev The registry contract instance.
    FulfillableRegistry private _registryContract;

    /// @dev The releaseable pool to be withdrawn by the beneficiaries in wei.
    /// serviceID => releaseablePoolAmount
    mapping (uint256 => uint256) public _releaseablePool;

    /// Mapping to store native coin refunds and deposit amounts
    /// @dev serviceID => userAddress => depositedAmount
    mapping(
        uint256 => mapping(address => uint256)
    ) public _deposits;

    /// @dev serviceID => userAddress => refundableAmount
    mapping(
        uint256 => mapping(address => uint256)
    ) public _authorized_refunds;

    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /*****************************/
    /* FULFILLABLE ESCROW LOGIC  */
    /*****************************/

    function initialize() public virtual initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _fulfillmentIdCount = 1;
    }

    /**
     * @dev Sets the protocol manager address.
     * @param manager_ The address of the protocol manager.
     */
    function setManager(address manager_) public onlyOwner {
        require(manager_ != address(0), "Manager cannot be the zero address");
        _manager = manager_;
    }

    /**
     * @dev Sets the protocol router address.
     * @param router_ The address of the protocol router.
     */
    function setRouter(address router_) public onlyOwner {
        require(router_ != address(0), "Router cannot be the zero address");
        _router = router_;
    }

    /**
     * @dev Sets the fulfillable registry address.
     * @param fulfillableRegistry_ The address of the fulfillable registry.
     */
    function setFulfillableRegistry(address fulfillableRegistry_) public onlyOwner {
        require(fulfillableRegistry_ != address(0), "Fulfillable registry cannot be the zero address");
        _fulfillableRegistry = fulfillableRegistry_;
        _registryContract = FulfillableRegistry(fulfillableRegistry_);
    }
    /**
     * @dev Retrieves the total deposits for a given payer and service ID.
     * @param payer The address of the payer.
     * @param serviceID The ID of the service.
     * @return amount The total amount of deposits for the given payer and service ID.
     */
    function getDepositsFor(address payer, uint256 serviceID) public view returns (uint256 amount) {
        amount = _deposits[serviceID][payer];
    }

    /**
     * @dev Sets the total deposits for a given payer and service ID.
     * @param payer The address of the payer.
     * @param serviceID The ID of the service.
     * @param amount The amount of deposits to set.
     */
    function setDepositsFor(address payer, uint256 serviceID, uint256 amount) internal {
        _deposits[serviceID][payer] = amount;
    }

    /**
     * @dev Retrieves the total refunds authorized for a given payer and service ID.
     * @param payer The address of the payer.
     * @param serviceID The ID of the service.
     * @return amount The total amount of refunds authorized for the given payer and service ID.
     */
    function getRefundsFor(address payer, uint256 serviceID) public view returns (uint256 amount) {
        amount = _authorized_refunds[serviceID][payer];
    }

    /**
     * @dev Sets the total refunds authorized for a given payer and service ID.
     * @param payer The address of the payer.
     * @param serviceID The ID of the service.
     * @param amount The amount of refunds to set.
     */
    function setRefundsFor(address payer, uint256 serviceID, uint256 amount) internal {
        _authorized_refunds[serviceID][payer] = amount;
    }

    /**
     * recordsOf
     * @dev Returns the fulfillment records for a given payer.
     * @param payer the address of the payer
     */
    function recordsOf(address payer) public view returns (uint256[] memory) {
        return _fulfillmentRecordsForSubject[payer];
    }

    /**
     * @dev Returns the fulfillment record for a given id.
     * @param id the id of the record
     */
    function record(uint256 id) public view returns (FulFillmentRecord memory) {
        return _fulfillmentRecords[id];
    }

    /**
     * @dev Stores the sent amount as credit to be claimed.
     * @param fulfillmentRequest The fulfillment record to be stored.
     *
     */
    function deposit(
        uint256 serviceID,
        FulFillmentRequest memory fulfillmentRequest
    ) public payable virtual nonReentrant {
        require(_router == msg.sender, "Caller is not the router");
        Service memory service = _registryContract.getService(serviceID);
        uint256 amount = msg.value;
        uint256 depositsAmount = getDepositsFor(
            fulfillmentRequest.payer,
            serviceID
        );
        (bool success, uint256 result) = amount.tryAdd(depositsAmount);
        require(success, "Overflow while adding deposits");
        setDepositsFor(
            fulfillmentRequest.payer,
            serviceID,
            result
        );
        // create a FulfillmentRecord
        FulFillmentRecord memory fulfillmentRecord = FulFillmentRecord({
            id: _fulfillmentIdCount,
            serviceRef: fulfillmentRequest.serviceRef,
            externalID: "",
            fulfiller: service.fulfiller,
            entryTime: block.timestamp,
            payer: fulfillmentRequest.payer,
            weiAmount: fulfillmentRequest.weiAmount,
            feeAmount: service.feeAmount,
            fiatAmount: fulfillmentRequest.fiatAmount,
            receiptURI: "",
            status: FulFillmentResultState.PENDING
        });
        _fulfillmentIdCount += 1;
        _fulfillmentRecordCount += 1;
        _fulfillmentRecords[fulfillmentRecord.id] = fulfillmentRecord;
        _fulfillmentRecordsForSubject[fulfillmentRecord.payer].push(
            fulfillmentRecord.id
        );
        emit DepositReceived(fulfillmentRecord);
    }

    /**
     * @dev Refund accumulated balance for a refundee, forwarding all gas to the
     * recipient.
     *
     * WARNING: Forwarding all gas opens the door to reentrancy vulnerabilities.
     * Make sure you trust the recipient, or are either following the
     * checks-effects-interactions pattern or using {ReentrancyGuard}.
     *
     * @param refundee The address whose funds will be withdrawn and transferred to.
     */
    function withdrawRefund(
        uint256 serviceID,
        address payable refundee
    ) public virtual nonReentrant returns (bool) {
        require(_manager == msg.sender, "Caller is not the manager");
        uint256 authorized_refunds = getRefundsFor(
            refundee,
            serviceID
        );
        require(authorized_refunds > 0, "Address is not allowed any refunds");
        setRefundsFor(refundee, serviceID, 0);
        _withdrawRefund(refundee, authorized_refunds);
        return true;
    }

    /**
     * @dev internal function to withraw.
     * Should only be called when previously authorized.
     *
     * Will emit a RefundWithdrawn event on success.
     *
     * @param refundee The address to send the value to.
     */
    function _withdrawRefund(
        address payable refundee,
        uint256 amount
    ) internal {
        refundee.sendValue(amount);
        emit RefundWithdrawn(refundee, amount);
    }

    /**
     * @dev Allows for refunds to take place.
     *
     * @param refundee the record to be
     * @param weiAmount the amount to be authorized.
     */
    function _authorizeRefund(
        uint256 serviceID,
        address refundee,
        uint256 weiAmount
    ) internal {
        uint256 authorized_refunds = getRefundsFor(
            refundee,
            serviceID
        );
        uint256 deposits = getDepositsFor(
            refundee,
            serviceID
        );
        (bool asuccess, uint256 addResult) = authorized_refunds.tryAdd(
            weiAmount
        );
        require(asuccess, "Overflow while adding authorized refunds");
        uint256 total_refunds = addResult;
        require(
            deposits >= weiAmount,
            "Amount is bigger than the total in escrow"
        );
        require(
            deposits >= total_refunds,
            "Total refunds would be bigger than the total in escrow"
        );
        (bool ssuccess, uint256 subResult) = deposits.trySub(weiAmount);
        require(ssuccess, "Overflow while substracting deposits");
        setDepositsFor(refundee, serviceID, subResult);
        setRefundsFor(refundee, serviceID, total_refunds);
        emit RefundAuthorized(refundee, weiAmount);
    }

    /**
     * @dev The fulfiller registers a fulfillment.
     *
     * We need to verify the amount of the fulfillment is actually available to release.
     * Then we can enrich the result with an auto-incremental unique ID.
     * and the timestamp when the record get inserted.
     *
     * If the fulfillment has failed:
     * - a refund will be authorized for a later withdrawal.
     *
     * If these verifications pass:
     * - add the amount fulfilled to the release pool.
     * - substract the amount from the payer's deposits.
     * - update the FulFillmentRecord to the blockchain.
     *
     * @param fulfillment the fulfillment result attached to it.
     */
    function registerFulfillment(
        uint256 serviceID,
        FulFillmentResult memory fulfillment
    ) public virtual nonReentrant returns (bool) {
        require(_manager == msg.sender, "Caller is not the manager");
        require(
            _fulfillmentRecords[fulfillment.id].id > 0,
            "Fulfillment record does not exist"
        );
        require(
            _fulfillmentRecords[fulfillment.id].status ==
                FulFillmentResultState.PENDING,
            "Fulfillment already registered"
        );
        Service memory service = _registryContract.getService(serviceID);
        address payer = _fulfillmentRecords[fulfillment.id].payer;
        uint256 deposits = getDepositsFor(payer, serviceID);
        (bool ffsuccess, uint256 total_amount) = _fulfillmentRecords[
            fulfillment.id
        ].weiAmount.tryAdd(service.feeAmount);
        require(ffsuccess, "Overflow while adding fulfillment amount and fee");
        require(
            deposits >= total_amount,
            "There is not enough balance to be released"
        );
        if (fulfillment.status == FulFillmentResultState.FAILED) {
            _authorizeRefund(serviceID, payer, total_amount);
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
        } else if (fulfillment.status != FulFillmentResultState.SUCCESS) {
            revert("Unexpected status");
        } else {
            (bool rlsuccess, uint256 releaseResult) = _releaseablePool[serviceID].tryAdd(total_amount);
            require(rlsuccess, "Overflow while adding to releaseable pool");
            (bool dsuccess, uint256 subResult) = deposits.trySub(total_amount);
            require(dsuccess, "Overflow while substracting from deposits");
            _releaseablePool[serviceID] = releaseResult;
            setDepositsFor(payer, serviceID, subResult);
            _fulfillmentRecords[fulfillment.id].receiptURI = fulfillment
                .receiptURI;
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
            _fulfillmentRecords[fulfillment.id].externalID = fulfillment
                .externalID;
        }
        return true;
    }

    /**
     * @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
     * Only the fulfiller of the service can withdraw the releaseable pool.
     */
    function beneficiaryWithdraw(uint256 serviceID) public virtual nonReentrant {
        require(_manager == msg.sender, "Caller is not the manager");
        Service memory service = _registryContract.getService(serviceID);
        require(_releaseablePool[serviceID] > 0, "There is no balance to release.");
        uint256 amount = _releaseablePool[serviceID];
        _releaseablePool[serviceID] = 0;
        service.beneficiary.sendValue(amount);
    }
}
