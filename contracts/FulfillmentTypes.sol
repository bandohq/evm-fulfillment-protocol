// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;
    
/// @notice Enum with states for fulfillment results
enum FulFillmentResultState {
    FAILED,
    SUCCESS,
    PENDING
}

/// @notice The fulfiller will accept FulfillmentResults submitted to it,
/// and if valid, will persist them on-chain as FulfillmentRecords
/// @dev This struct represents a record of a fulfillment
struct FulFillmentRecord {
    /// @notice Auto-incremental ID generated in contract
    uint256 id;
    /// @notice Identifier required to route the payment to the user's destination
    string serviceRef;
    /// @notice Address of the fulfiller
    address fulfiller;
    /// @notice ID coming from the fulfiller as proof
    string externalID;
    /// @notice Address of the payer
    address payer;
    /// @notice Amount in wei
    uint256 weiAmount;
    /// @notice Fee amount charged in wei
    uint256 feeAmount;
    /// @notice Fiat amount to be charged for the fulfillable
    uint256 fiatAmount;
    /// @notice Time at which the fulfillment was submitted
    uint256 entryTime;
    /// @notice The fulfillment external receipt URI
    string receiptURI;
    /// @notice Status of the fulfillment
    FulFillmentResultState status;
}

/// @notice A fulfiller will submit a fulfillment result in this format
/// @dev This struct represents the result of a fulfillment
struct FulFillmentResult {
    /// @notice ID of the fulfillment record
    uint256 id;
    /// @notice ID coming from the fulfiller as proof
    string externalID;
    /// @notice The fulfillment external receipt URI
    string receiptURI;
    /// @notice Status of the fulfillment
    FulFillmentResultState status;   
}

/// @notice The fulfiller will accept FulfillmentResults submitted to it,
/// and if valid, will persist them on-chain as FulfillmentRecords
/// @dev This struct represents a record of an ERC20 fulfillment
struct ERC20FulFillmentRecord {
    /// @notice Auto-incremental ID generated in contract
    uint256 id;
    /// @notice Identifier required to route the payment to the user's destination
    string serviceRef;
    /// @notice Address of the fulfiller
    address fulfiller;
    /// @notice Address of the ERC20 token to be used for the payment
    address token;
    /// @notice ID coming from the fulfiller as proof
    string externalID;
    /// @notice Address of the payer
    address payer;
    /// @notice Amount of tokens
    uint256 tokenAmount;
    /// @notice Fee amount charged in tokens
    uint256 feeAmount;
    /// @notice Fiat amount to be charged for the fulfillable
    uint256 fiatAmount;
    /// @notice Time at which the fulfillment was submitted
    uint256 entryTime;
    /// @notice The fulfillment external receipt URI
    string receiptURI;
    /// @notice Status of the fulfillment
    FulFillmentResultState status;
}

/// @notice Anybody can submit a fulfillment request through a router
/// @dev This struct represents an ERC20 fulfillment request
struct ERC20FulFillmentRequest {
    /// @notice Address of the payer
    address payer;
    /// @notice Fiat amount to be charged for the fulfillable
    uint256 fiatAmount;
    /// @notice Identifier required to route the payment to the user's destination
    string serviceRef;
    /// @notice Address of the ERC20 token to be used for the payment
    address token;
    /// @notice Amount of tokens
    uint256 tokenAmount;
}

/// @notice Anybody can submit a fulfillment request through a router
/// @dev This struct represents a fulfillment request
struct FulFillmentRequest {
    /// @notice Address of the payer
    address payer;
    /// @notice Amount in wei
    uint256 weiAmount;
    /// @notice Fiat amount to be charged for the fulfillable
    uint256 fiatAmount;
    /// @notice Identifier required to route the payment to the user's destination
    string serviceRef;
}
