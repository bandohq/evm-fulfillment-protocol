// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "./FulfillmentTypes.sol";

/**
* @dev Interface for bando fulfillment protocol ERC20 support escrow.
* This interface is intented to be implemented by any contract that wants to be a fulfillable.
* It is the same a the BandoFulfillable interface but for ERC20 transfers.
* A fulfillable is a contract that can accept fulfillments from a router.
* The router will route fulfillments to the fulfillable based on the serviceID.
*/
interface IBandoERC20Fulfillable {
    function depositERC20(uint256 serviceID, ERC20FulFillmentRequest memory request) external;

    function registerFulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) external returns (bool);

    function recordsOf(address payer) external view returns (uint256[] memory);

    function record(uint256 id) external view returns (ERC20FulFillmentRecord memory);

    function withdrawERC20Refund(uint256 serviceID, address token, address refundee) external returns (bool);
}
