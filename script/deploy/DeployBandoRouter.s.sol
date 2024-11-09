// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployProxyBase} from "./utils/DeployProxyBase.sol";
import {BandoRouterV1} from "bando/BandoRouterV1.sol";
import {BandoRouterProxy} from "bando/proxy/BandoRouterProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract DeployBandoRouterV1 is DeployProxyBase {
  constructor() DeployProxyBase("BandoRouterV1") {}

  function run() public returns (
    address deployed,
    address implementation,
    bool isProxy,
    bytes memory proxyConstructorArgs
  ) {
    address deployer = msg.sender;
    isProxy = true;
    bytes memory bytecode = type(BandoRouterV1).creationCode;
    bytes memory initData = abi.encodeCall(BandoRouterV1.initialize, (deployer));
    bytes memory proxycode = type(BandoRouterProxy).creationCode;
    (deployed, proxyConstructorArgs, implementation) = deploy(initData, bytecode, proxycode);
  }
}