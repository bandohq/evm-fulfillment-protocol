// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../BandoRouterV1_1.sol";

/**
 * Test upgrade on router
 */
contract RouterUpgradeTesterV1_1 is BandoRouterV1_1 {

    function isUpgrade() public view onlyOwner returns (bool) {
        return true;
    }
}
