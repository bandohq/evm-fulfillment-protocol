// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title ERC20TokenRegistryProxy
/// @notice A proxy contract for the ERC20TokenRegistry contract
contract ERC20TokenRegistryProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory data)
      ERC1967Proxy(implementation, data)
    {}
}
