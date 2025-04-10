// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { DSTest } from "ds-test/test.sol";

contract ScriptBase is Script, DSTest {
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;
    string internal root;
    string internal network;
    string internal fileSuffix;
    bytes32 internal salt;

    constructor(string memory contractName) {
        string memory saltPrefix = vm.envString("DEPLOYSALT");
        salt = keccak256(abi.encodePacked(saltPrefix, contractName));
        deployerPrivateKey = uint256(vm.envBytes32("SOL_PRIVATE_KEY"));
        deployerAddress = vm.addr(deployerPrivateKey);
        root = vm.projectRoot();
        network = vm.envString("NETWORK");
        fileSuffix = vm.envString("FILE_SUFFIX");
    }
}
