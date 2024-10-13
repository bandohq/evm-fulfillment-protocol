// SPDX-License-Identifier: MIT
// Inspired in:
// OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)

pragma solidity >=0.8.20 <0.9.0;
    
/**
* enum with states for fulfillment results.
*/
enum FulFillmentResultState {
    FAILED,
    SUCCESS,
    PENDING
}

/**
* @dev The fulfiller will accept FulfillmentResults submitted to it,
* and if valid, will persist them on-chain as FulfillmentRecords
*/
struct FulFillmentRecord {
    uint256 id; // auto-incremental, generated in contract
    string serviceRef; // identifier required to route the payment to the user's destination
    address fulfiller;
    string externalID; // id coming from the fulfiller as proof.
    address payer; // address of payer
    uint256 weiAmount; // amount in wei
    uint256 feeAmount; // feeAmount charged in wei
    uint256 fiatAmount; // fiat amount to be charged for the fufillable
    uint256 entryTime; // time at which the fulfillment was submitted
    string receiptURI; // the fulfillment external receipt uri.
    FulFillmentResultState status;
}

/**
* @dev A fulfiller will submit a fulfillment result in this format.
*/
struct FulFillmentResult {
    uint256 id; // id of the fulfillment record.
    string externalID; // id coming from the fulfiller as proof.
    string receiptURI; // the fulfillment external receipt uri. 
    FulFillmentResultState status;   
}

/**
* @dev The fulfiller will accept FulfillmentResults submitted to it,
* and if valid, will persist them on-chain as FulfillmentRecords
*/
struct ERC20FulFillmentRecord {
    uint256 id; // auto-incremental, generated in contract
    string serviceRef; // identifier required to route the payment to the user's destination
    address fulfiller;
    address token; // address of the ERC20 token to be used for the payment
    string externalID; // id coming from the fulfiller as proof.
    address payer; // address of payer
    uint256 tokenAmount; // amount
    uint256 feeAmount; // feeAmount charged in N token
    uint256 fiatAmount; // fiat amount to be charged for the fufillable
    uint256 entryTime; // time at which the fulfillment was submitted
    string receiptURI; // the fulfillment external receipt uri.
    FulFillmentResultState status;
}

/**
* @dev Anybody can submit a fulfillment request through a router.
*/
struct ERC20FulFillmentRequest {
    address payer; // address of payer
    uint256 fiatAmount; // fiat amount to be charged for the fufillable
    string serviceRef; // identifier required to route the payment to the user's destination
    address token; // address of the ERC20 token to be used for the payment
    uint256 tokenAmount; // amount in wei
}

/**
* @dev Anybody can submit a fulfillment request through a router.
*/
struct FulFillmentRequest {
    address payer; // address of payer
    uint256 weiAmount; // amount in wei
    uint256 fiatAmount; // fiat amount to be charged for the fufillable
    string serviceRef; // identifier required to route the payment to the user's destination
}
