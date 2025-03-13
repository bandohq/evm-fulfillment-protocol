// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ScriptBase } from "../deploy/utils/ScriptBase.sol";
import {console} from "forge-std/console.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BandoRouterV1_1} from 'bando/BandoRouterV1_1.sol';

contract DeployBandoRouterV1_1 is ScriptBase {

    constructor() ScriptBase("BandoRouter_V1_1") {}

    function run() public returns (address deployed) {
        address deployer = msg.sender;
        console.log("Deployer:", deployer);
        vm.startBroadcast();
        // 1. Deploy implementation using CREATE2
        bytes memory implementationBytecode = type(BandoRouterV1_1).creationCode;
        deployed = Create2.deploy(0, salt, implementationBytecode);
        console.log("Implementation deployed at:", deployed);
        vm.stopBroadcast();
    }
}
