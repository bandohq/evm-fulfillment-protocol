// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import './utils/DeployUUPSScriptBase.sol';
import {FulfillableRegistry} from 'bando/periphery/registry/FulfillableRegistry.sol';
import { stdJson } from "forge-std/Script.sol";

contract DeployFulfillableRegistry is DeployUUPSScriptBase {
    using stdJson for string;

    constructor() DeployUUPSScriptBase('FulfillableRegistry') {}

    function run() public returns (FulfillableRegistry deployed) {
        deployed = FulfillableRegistry(deploy(
            type(FulfillableRegistry).creationCode,
            abi.encodeWithSelector(FulfillableRegistry.initialize.selector)
        ));
    }
}
