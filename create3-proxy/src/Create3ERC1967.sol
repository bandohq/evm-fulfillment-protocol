// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "solmate/src/utils/CREATE3.sol";

/// @title Create3ERC1967
/// @author g6s
/// @notice A library for deploying ERC1967 proxies using the CREATE3 pattern
library Create3ERC1967 {

    /// @notice Deploys an ERC1967 proxy using the CREATE3 pattern
    /// @param salt A unique value to determine the contract's address
    /// @param creationCode The bytecode of the implementation contract
    /// @param initializerData The data to be passed to the initializer function
    /// @return proxy The address of the deployed proxy contract
    function deploy(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory initializerData
    ) public returns (address proxy) {
        //deploy the implementation
        address implementation = _deployImplementation(salt, creationCode);

        // Generate the initialization code for the ERC1967Proxy
        bytes memory initCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initializerData)
        );

        proxy = CREATE3.deploy(salt, initCode, 0);
    }

    /// @notice Deploys the implementation contract using CREATE3
    /// @dev This is an internal function used by deployProxy
    /// @param salt A unique value to determine the contract's address
    /// @param creationCode The bytecode of the implementation contract
    /// @return impl The address of the deployed implementation contract
    function _deployImplementation(bytes32 salt, bytes memory creationCode) internal returns (address impl) {
        impl = CREATE3.deploy(salt, creationCode, 0);
    }
}