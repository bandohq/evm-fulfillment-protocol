// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ScriptBase } from "./utils/ScriptBase.sol";
import {console} from "forge-std/console.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BandoRouterV1} from 'bando/BandoRouterV1.sol';
import {BandoRouterProxy} from 'bando/proxy/BandoRouterProxy.sol';

contract DeployBandoRouter is ScriptBase {
    // Deployment record file path
    string private deploymentRecordPath;

    constructor() ScriptBase("BandoRouter") {
        // Set the deployment record path based on the network
        deploymentRecordPath = string.concat(root, "/deployments/", network, ".json");
    }

    function run() public returns (
        address deployed,
        address implementation,
        bool isProxy,
        bytes memory proxyConstructorArgs
    ) {
        address deployer = msg.sender;
        console.log("Deployer:", deployer);
        isProxy = true;
        
        // Set transaction parameters for Scroll
        uint256 gasPrice = 1000000000; // 1 gwei
        vm.fee(gasPrice);
        
        // Try to load existing deployment addresses from file
        string memory json = "";
        try vm.readFile(deploymentRecordPath) returns (string memory content) {
            json = content;
            console.log("Found existing deployment record at", deploymentRecordPath);
        } catch {
            console.log("No existing deployment record found, will create new one");
        }

        // Check if we have existing deployment addresses
        bool hasExistingDeployment = bytes(json).length > 0;
        
        // Prepare bytecode for potential deployment
        bytes memory implementationBytecode = type(BandoRouterV1).creationCode;
        bytes memory initData = abi.encodeCall(
          BandoRouterV1.initialize,
          (deployer)
        );
        
        vm.startBroadcast();

        // 1. Deploy or retrieve implementation
        if (hasExistingDeployment) {
            // Try to parse implementation address from JSON
            if (!vm.keyExists(json, ".BandoRouter")) {
                console.log("No implementation address found in record, deploying new one");
                implementation = Create2.deploy(0, salt, implementationBytecode);
                console.log("Implementation deployed at:", implementation);
            } else {
                bytes memory implAddrBytes = vm.parseJson(json, ".BandoRouter");
                // Check if implementation address is valid
                // raise if json is 0x
                implementation = abi.decode(implAddrBytes, (address));
                console.log("Found existing implementation at:", implementation);
                // Verify implementation has code
                uint256 implCodeSize;
                assembly {
                    implCodeSize := extcodesize(implementation)
                }
                console.log("Implementation code size:", implCodeSize);
                if (implCodeSize == 0) {
                    console.log("WARNING: Implementation address has no code, deploying new one");
                    implementation = Create2.deploy(0, salt, implementationBytecode);
                    console.log("Implementation deployed at:", implementation);
                }
            }
        } else {
            // No existing deployment, create new one
            implementation = Create2.deploy(0, salt, implementationBytecode);
            console.log("Implementation deployed at:", implementation);
        }

        // 2. Deploy or retrieve proxy
        proxyConstructorArgs = abi.encode(
            implementation,
            initData
        );
        bytes memory proxyBytecode = abi.encodePacked(
            type(BandoRouterProxy).creationCode,
            proxyConstructorArgs
        );
        bytes32 proxySalt = keccak256(abi.encodePacked(salt, "proxy"));
        
        if (hasExistingDeployment) {
            // Try to parse proxy address from JSON
            if (!vm.keyExists(json, ".BandoRouterProxy")) {
                console.log("No proxy address found in record, deploying new one");
                deployed = Create2.deploy(0, proxySalt, proxyBytecode);
                console.log("Proxy deployed at:", deployed);
            } else {
                bytes memory proxyAddrBytes = vm.parseJson(json, ".BandoRouterProxy");
                // Check if proxy address is valid
                // raise if json is 0x
                //console.log("Found existing proxy address:", proxyAddrBytes);
                deployed = abi.decode(proxyAddrBytes, (address));
                console.log("Found existing proxy at:", deployed);
                
                // Verify proxy has code
                uint256 proxyCodeSize;
                assembly {
                    proxyCodeSize := extcodesize(deployed)
                }
                console.log("Proxy code size:", proxyCodeSize);
                if (proxyCodeSize == 0) {
                    console.log("WARNING: Proxy address has no code, deploying new one");
                    deployed = Create2.deploy(0, proxySalt, proxyBytecode);
                    console.log("Proxy deployed at:", deployed);
                }
            }
        } else {
            // No existing deployment, create new one
            deployed = Create2.deploy(0, proxySalt, proxyBytecode);
            console.log("Proxy deployed at:", deployed);
        }

        // 3. Verify initialization (safe to call even if already initialized)
        BandoRouterV1 proxyContract = BandoRouterV1(deployed);
        address owner = proxyContract.owner();
        console.log("Owner after initialization:", owner);
        require(owner == deployer, "Initialization failed: wrong owner");

        vm.stopBroadcast();
    }
}
