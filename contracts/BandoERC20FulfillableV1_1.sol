pragma solidity 0.8.28;

import { BandoERC20FulfillableV1 } from "./BandoERC20FulfillableV1.sol";

contract BandoERC20FulfillableV1_1 is BandoERC20FulfillableV1 {

    function version() external pure returns (string memory) {
        return "1.1";
    }
   
}
