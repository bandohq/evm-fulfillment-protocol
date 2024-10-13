// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./IBandoERC20Fulfillable.sol";
import "./IBandoFulfillable.sol";
import "./periphery/registry/IFulfillableRegistry.sol";
import "./FulfillmentTypes.sol";
import "./libraries/FulfillmentRequestLib.sol";


/**
 * ----- BandoERC20RouterV1 -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * 
 * The contract will validate the request and transfer the payment to the fulfillable contract.
 * -----------------------
 */
contract BandoRouterV1 is
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable {

    using Address for address payable;
    using Math for uint256;

    address public _fulfillableRegistry;
    address public _tokenRegistry;
    address payable public _escrow;
    address payable public _erc20Escrow;

    event ERC20ServiceRequested(uint256 serviceID, ERC20FulFillmentRequest request);
    event ServiceRequested(uint256 serviceID, FulFillmentRequest request);
    event RefValidationFailed(uint256 serviceID, string serviceRef);

    /**
     * @dev Constructor.
     */
    function initialize() public virtual initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev required for UUPS upgrades
     **/
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /**
     * @dev Sets the fulfillable registry address.
     * @param fulfillableRegistry_ The address of the fulfillable registry.
     */
    function setFulfillableRegistry(address fulfillableRegistry_) public onlyOwner {
        require(fulfillableRegistry_ != address(0), "Fulfillable registry cannot be the zero address");
        _fulfillableRegistry = fulfillableRegistry_;
    }

    /**
     * @dev Sets the token registry address.
     * @param tokenRegistry_ The address of the token registry.
     */
    function setTokenRegistry(address tokenRegistry_) public onlyOwner {
        require(tokenRegistry_ != address(0), "Token registry cannot be the zero address");
        _tokenRegistry = tokenRegistry_;
    }

    /**
     * @dev Sets the escrow address.
     * @param escrow_ The address of the escrow.
     */
    function setEscrow(address payable escrow_) public onlyOwner {
        require(escrow_ != address(0), "Escrow cannot be the zero address");
        _escrow = escrow_;
    }

    /**
     * @dev Sets the ERC20 escrow address.
     * @param erc20Escrow_ The address of the ERC20 escrow.
     */
    function setERC20Escrow(address payable erc20Escrow_) public onlyOwner {
        require(erc20Escrow_ != address(0), "ERC20 escrow cannot be the zero address");
        _erc20Escrow = erc20Escrow_;
    }

    /**
     * requestERC20Service
     * @return true if amount was transferred to the escrow.
     * Pre-conditions:
     * 
     * - verified identifier
     * - valid fulfillable id
     * - valid IIdentifierValidator contract
     * - positive amount
     * - positive fiat amount in precision 2
     * - enough balance on the sender account
     * 
     * 
     * Post-conditions:
     * - payment due is transferred to escrow contract until fulfillment
     */
    function requestERC20Service(
        uint256 serviceID, 
        ERC20FulFillmentRequest memory request
    ) public payable whenNotPaused nonReentrant returns (bool) {
        FulfillmentRequestLib.validateRequest(serviceID, request, _fulfillableRegistry);
        IBandoERC20Fulfillable(_erc20Escrow).depositERC20(serviceID, request);
        emit ERC20ServiceRequested(serviceID, request);
        return true;
    }

    /**
     * requestService
     * @return true if amount was transferred to the escrow.
     * Pre-conditions:
     * 
     * - verified identifier
     * - valid fulfillable id
     * - valid IIdentifierValidator contract
     * - positive amount
     * - positive fiat amount in precision 2
     * - enough balance on the sender account
     * 
     * 
     * Post-conditions:
     * - payment due is transferred to escrow contract until fulfillment
     */
    function requestService(
        uint256 serviceID,
        FulFillmentRequest memory request
    ) public payable whenNotPaused nonReentrant returns (bool) {
        //Validate request
        FulfillmentRequestLib.validateRequest(serviceID, request, _fulfillableRegistry);
        // Call the deposit function on the fulfillable contract
        IBandoFulfillable(_escrow).deposit{value: request.weiAmount}(serviceID, request);
        emit ServiceRequested(serviceID, request);
        return true;
    }
    
}
