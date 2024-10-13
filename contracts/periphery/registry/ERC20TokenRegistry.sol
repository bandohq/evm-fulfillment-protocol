// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title ERC20TokenRegistry
/// @notice A contract for managing a whitelist of ERC20 tokens
/// @dev This contract is upgradeable and uses the UUPS proxy pattern
contract ERC20TokenRegistry is OwnableUpgradeable, UUPSUpgradeable {
    /* 
     * Mapping to store the whitelist status of tokens
     * The key is the token address, and the value is a boolean indicating whitelist status
     */
    mapping(address => bool) private whitelist;

    /* Events for token addition and removal */
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    /// @notice Initializes the contract
    /// @dev This function replaces the constructor for upgradeable contracts
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
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
