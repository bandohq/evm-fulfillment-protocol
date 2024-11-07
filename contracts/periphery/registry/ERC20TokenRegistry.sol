// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title ERC20TokenRegistry
/// @notice A contract for managing a whitelist of ERC20 tokens
/// @dev This contract is upgradeable and uses the UUPS proxy pattern
/// @title ERC20TokenRegistry
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
contract ERC20TokenRegistry is OwnableUpgradeable, UUPSUpgradeable {
    /* 
     * Mapping to store the whitelist status of tokens
     * The key is the token address, and the value is a boolean indicating whitelist status
     */
    mapping(address => bool) private whitelist;

    /// @notice Emitted when a token is added to the whitelist
    /// @param token The address of the token to check
    event TokenAdded(address indexed token);

    /// @notice Emitted when a token is removed from the whitelist
    /// @param token The address of the token to check
    event TokenRemoved(address indexed token);

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
    function addToken(address token) public onlyOwner {
        require(token != address(0), "ERC20TokenRegistry: Token address cannot be zero");
        require(!whitelist[token], "ERC20TokenRegistry: Token already whitelisted");
        whitelist[token] = true;
        emit TokenAdded(token);
    }

    /// @notice Removes a token from the whitelist
    /// @dev Only the contract owner can remove tokens
    /// @param token The address of the token to remove
    function removeToken(address token) public onlyOwner {
        require(whitelist[token], "ERC20TokenRegistry: Token not whitelisted");
        whitelist[token] = false;
        emit TokenRemoved(token);
    }
}
