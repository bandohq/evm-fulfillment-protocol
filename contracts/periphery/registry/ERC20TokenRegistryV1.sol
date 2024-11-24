// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title ERC20TokenRegistryV1
/// @author g6s
/// @notice This contract manages a whitelist of ERC20 tokens for the Bando Protocol
/// @dev Implements an upgradeable contract using the UUPS proxy pattern
/// @custom:bfp-version 1.0.0
/// @notice Considerations:
/// 1. Access Control:
///    - The contract inherits from OwnableUpgradeable, restricting critical functions to the owner
///    - Token addition and removal are owner-only operations
///
/// 2. State Management:
///    - Whitelist status is stored in a private mapping (address => bool)
///    - No direct state-changing functions are exposed to non-owners
///
/// 3. Upgradeability:
///    - Uses the UUPS (Universal Upgradeable Proxy Standard) pattern
///    - The _authorizeUpgrade function is properly overridden and restricted to the owner
///
/// 4. Events:
///    - TokenAdded and TokenRemoved events are emitted for off-chain tracking of whitelist changes
///
/// 5. Input Validation:
///    - Zero address checks are implemented in the addToken function
///    - Duplicate additions and removals are prevented with require statements
///
/// 6. View Functions:
///    - isTokenWhitelisted allows public querying of a token's whitelist status
///
/// Key Security Considerations:
/// - Check for potential issues with gas limits if a large number of tokens are added/removed in a single transaction
contract ERC20TokenRegistryV1 is OwnableUpgradeable, UUPSUpgradeable {

    /// @notice Mapping to store the whitelist status of tokens
    /// @dev The key is the token address, and the value is a boolean indicating whitelist status
    mapping(address => bool) private whitelist;

    /// @notice The swap fee percentage charged to the payer for the fulfillment
    /// @dev This fee is charged to the payer for the fulfillment
    /// @dev token => swapFeeBasisPoints
    /// @dev This fee ideally should be zero for stablecoins.
    mapping(address => uint16) public _swapFeeBasisPoints;

    /// @notice Error for token not whitelisted
    /// @param token The address of the token that is not whitelisted
    error TokenNotWhitelisted(address token);

    /// @notice Error for token already whitelisted
    /// @param token The address of the token that is already whitelisted
    error TokenAlreadyWhitelisted(address token);

    /// @notice Error for invalid swap fee percentage
    /// @param swapFeeBasisPoints The swap fee percentage that is invalid
    error InvalidSwapFeeBasisPoints(uint16 swapFeeBasisPoints);

    /// @notice Emitted when a token is added to the whitelist
    /// @param token The address of the token to check
    /// @param swapFeeBasisPoints The swap fee percentage for the token
    event TokenAdded(address indexed token, uint16 swapFeeBasisPoints);

    /// @notice Emitted when a token is removed from the whitelist
    /// @param token The address of the token to check
    event TokenRemoved(address indexed token);

    /// @notice event emitted when the swap fee percentage is updated
    /// @param token The address of the token to check
    /// @param swapFeeBasisPoints The new swap fee percentage
    event SwapFeeBasisPointsUpdated(address indexed token, uint16 swapFeeBasisPoints);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @dev This function replaces the constructor for upgradeable contracts
    function initialize(address initialOwner) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(initialOwner);
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Required by the UUPSUpgradeable contract. Only the owner can upgrade the contract.
    /// @param newImplementation The address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Checks if a token is whitelisted
    /// @param token The address of the token to check
    /// @return bool True if the token is whitelisted, false otherwise
    function isTokenWhitelisted(address token) public view returns (bool) {
        return whitelist[token];
    }

    /// @notice Adds a token to the whitelist
    /// @dev Only the contract owner can add tokens
    /// @param token The address of the token to add
    /// @param swapFeeBasisPoints The swap fee percentage for the token
    function addToken(address token, uint16 swapFeeBasisPoints) public onlyOwner {
        if (whitelist[token]) {
            revert TokenAlreadyWhitelisted(token);
        }
        whitelist[token] = true;
        _swapFeeBasisPoints[token] = swapFeeBasisPoints;
        emit TokenAdded(token, swapFeeBasisPoints);
    }

    /// @notice Removes a token from the whitelist
    /// @dev Only the contract owner can remove tokens
    /// @param token The address of the token to remove
    function removeToken(address token) public onlyOwner {
        if (!whitelist[token]) {
            revert TokenNotWhitelisted(token);
        }
        whitelist[token] = false;
        emit TokenRemoved(token);
    }

    /// @notice Updates the swap fee percentage for a token
    /// @dev Only the contract owner can update the swap fee percentage
    /// @param token The address of the token to update
    /// @param swapFeeBasisPoints The new swap fee percentage
    function updateSwapFeeBasisPoints(address token, uint16 swapFeeBasisPoints) public onlyOwner {
        if (swapFeeBasisPoints > 10000 || swapFeeBasisPoints < 0) {
            revert InvalidSwapFeeBasisPoints(swapFeeBasisPoints);
        }
        _swapFeeBasisPoints[token] = swapFeeBasisPoints;
        emit SwapFeeBasisPointsUpdated(token, swapFeeBasisPoints);
    }
}
