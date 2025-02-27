// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ScriptBase } from "../deploy/utils/ScriptBase.sol";
import {console} from "forge-std/console.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BandoFulfillableV1_2} from 'bando/BandoFulfillableV1_2.sol';

contract DeployBandoFulfillableV1_2 is ScriptBase {

    constructor() ScriptBase("BandoFulfillable_V1_2") {}

    function run() public returns (address deployed) {
        address deployer = msg.sender;
        console.log("Deployer:", deployer);
        vm.startBroadcast();
        // 1. Deploy implementation using CREATE2
        bytes memory implementationBytecode = type(BandoFulfillableV1_2).creationCode;
        deployed = Create2.deploy(0, salt, implementationBytecode);
        console.log("Implementation deployed at:", deployed);
        vm.stopBroadcast();
    }
}
