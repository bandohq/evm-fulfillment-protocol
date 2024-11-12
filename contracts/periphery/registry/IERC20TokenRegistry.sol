// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

/// @title IERC20TokenRegistry
/// @author Bando
/// @notice Interface for ERC20 token registry
/// @dev This contract is used to whitelist ERC20 tokens
interface IERC20TokenRegistry {
    /// @notice Checks if a token is whitelisted.
    /// @param token The address of the token to check.
    /// @return bool Returns true if the token is whitelisted, false otherwise.
    function isTokenWhitelisted(address token) external view returns (bool);

    /// @notice Adds a token to the whitelist.
    /// @param token The address of the token to add.
    function addToken(address token) external;

    /// @notice Removes a token from the whitelist.
    /// @param token The address of the token to remove.
    function removeToken(address token) external;
}
