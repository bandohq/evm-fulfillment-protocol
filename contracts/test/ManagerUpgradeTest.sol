// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "../BandoFulfillmentManagerV1.sol";

/**
 * Test upgrade on manager
 */
contract ManagerUpgradeTest is BandoFulfillmentManagerV1 {

    function isUpgrade() public view onlyOwner returns (bool) {
        return true;
    }
}
