// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ScriptBase } from "./utils/ScriptBase.sol";
import {console} from "forge-std/console.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BandoFulfillmentManagerV1} from 'bando/BandoFulfillmentManagerV1.sol';
import {BandoFulfillmentManagerProxy} from 'bando/proxy/BandoFulfillmentManagerProxy.sol';

contract DeployBandoFulfillmentManager is ScriptBase {

    constructor() ScriptBase("BandoFulfillmentManager") {}

    function run() public returns (
        address deployed,
        address implementation,
        bool isProxy,
        bytes memory proxyConstructorArgs
    ) {
        address deployer = msg.sender;
        console.log("Deployer:", deployer);
        isProxy = true;
        vm.startBroadcast();

        // 1. Deploy implementation using CREATE2
        bytes memory implementationBytecode = type(BandoFulfillmentManagerV1).creationCode;
        implementation = Create2.deploy(0, salt, implementationBytecode);
        console.log("Implementation deployed at:", implementation);
        // 2. Prepare initialization data
        bytes memory initData = abi.encodeCall(
          BandoFulfillmentManagerV1.initialize,
          ()
        );
        console.log("Init data length:", initData.length);

        // 3. Deploy proxy using CREATE2
        proxyConstructorArgs = abi.encode(
            implementation,
            initData
        );
        bytes memory proxyBytecode = abi.encodePacked(
            type(BandoFulfillmentManagerProxy).creationCode,
            proxyConstructorArgs
        );
        
        bytes32 proxySalt = keccak256(abi.encodePacked(salt, "proxy"));
        deployed = Create2.deploy(0, proxySalt, proxyBytecode);
        console.log("Proxy deployed at:", deployed);
        // 4. Verify initialization
        BandoFulfillmentManagerV1 proxyContract = BandoFulfillmentManagerV1(deployed);
        address owner = proxyContract.owner();
        console.log("Owner after initialization:", owner);
        require(owner == deployer, "Initialization failed: wrong owner");

        vm.stopBroadcast();
    }
}
