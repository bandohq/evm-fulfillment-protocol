// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title BandoERC20FulfillableProxy
/// @notice Proxy contract for BandoERC20Fulfillable
contract BandoERC20FulfillableProxy is ERC1967Proxy {
    constructor(address _logic, bytes memory _data)
      ERC1967Proxy(_logic, _data)
    {}
}
