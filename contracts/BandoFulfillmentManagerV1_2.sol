// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "./BandoFulfillmentManagerV1.sol";

contract BandoFulfillmentManagerV1_2 is BandoFulfillmentManagerV1 {

    function isUpgrade() public view onlyOwner returns (bool) {
        return true;
    }
}
