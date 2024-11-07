// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20TokenRegistryProxy} from "../../contracts/proxy/ERC20TokenRegistryProxy.sol";
import {ERC20TokenRegistry} from "../../contracts/periphery/registry/ERC20TokenRegistry.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ScriptBase} from "./utils/ScriptBase.sol";

contract DeployERC20TokenRegistry is ScriptBase {

  constructor() ScriptBase("ERC20TokenRegistry") {}

  function run() public returns (
        address deployed,
        address implementation,
        bool isProxy,
        bytes memory proxyConstructorArgs
    ) {
        address deployer = msg.sender;
        isProxy = true;
        vm.startBroadcast();

        // 1. Deploy implementation using CREATE2
        bytes memory implementationBytecode = type(ERC20TokenRegistry).creationCode;
        implementation = Create2.deploy(0, salt, implementationBytecode);
        // 2. Prepare initialization data
        bytes memory initData = abi.encodeCall(
          ERC20TokenRegistry.initialize,
          (deployer)
        );
        // 3. Deploy proxy using CREATE2
        proxyConstructorArgs = abi.encode(
            implementation,
            initData
        );
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC20TokenRegistryProxy).creationCode,
            proxyConstructorArgs
        );
        
        bytes32 proxySalt = keccak256(abi.encodePacked(salt, "proxy"));
        deployed = Create2.deploy(0, proxySalt, proxyBytecode);
        // 4. Verify initialization
        ERC20TokenRegistry proxyContract = ERC20TokenRegistry(deployed);
        address owner = proxyContract.owner();
        require(owner == deployer, "Initialization failed: wrong owner");

        vm.stopBroadcast();
  }
}