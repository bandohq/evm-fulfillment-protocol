// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ScriptBase} from "./ScriptBase.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @title DeployProxyBase
/// @notice Base contract for deploying proxy contracts
contract DeployProxyBase is ScriptBase {
  constructor(string memory name) ScriptBase(name) {}

  /// @notice Deploy a proxy contract using CREATE2
  /// @param implementation The implementation contract address
  /// @param initData The initialization data for the implementation
  /// @return deployed The address of the deployed proxy contract
  function _deployProxy(address implementation, bytes memory initData, bytes memory proxycode) internal returns (
    address deployed,
    bytes memory proxyConstructorArgs
  ) {
    proxyConstructorArgs = abi.encode(implementation, initData);
    bytes memory bytecode = abi.encodePacked(proxycode, proxyConstructorArgs);
    bytes32 salt = keccak256(abi.encodePacked(salt, "proxy"));
    deployed = Create2.deploy(0, salt, bytecode);
  }

  /// @notice Deploy an implementation contract using CREATE2
  /// @param bytecode The bytecode of the implementation contract
  /// @return deployed The address of the deployed implementation contract
  function _deployImplementation(bytes memory bytecode) internal returns (address deployed) {
    deployed = Create2.deploy(0, salt, bytecode);
  }

  /// @notice Deploy a proxy contract using CREATE2
  /// @param initData The initialization data for the implementation
  /// @param implBytecode The bytecode of the implementation contract
  /// @param proxycode The creation code of the proxy contract
  /// @return deployed The address of the deployed proxy contract
  /// @return proxyConstructorArgs The constructor arguments for the proxy contract
  /// @return implementation The address of the deployed implementation contract
  function deploy(bytes memory initData, bytes memory implBytecode, bytes memory proxycode) internal returns (
    address deployed,
    bytes memory proxyConstructorArgs,
    address implementation
  ) {
    vm.startBroadcast();
    implementation = _deployImplementation(implBytecode);
    (deployed, proxyConstructorArgs) = _deployProxy(implementation, initData, proxycode);
    vm.stopBroadcast();
  }
}
