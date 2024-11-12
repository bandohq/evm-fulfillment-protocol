// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "../BandoRouterV1.sol";

/**
 * Test upgrade on router
 */
contract RouterUpgradeTester is BandoRouterV1 {

    function isUpgrade() public view onlyOwner returns (bool) {
        return true;
    }
}
