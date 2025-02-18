// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";
contract TestNativeSwapAggregator {
    function swapNative(address stableToken, uint256 amount) external payable {
        console.log("swapNative", stableToken, amount);
        require(msg.value == amount, "Invalid amount");
        // Transfer the stable token to the sender
        // double the amount to mock the swap
        IERC20(stableToken).transfer(msg.sender, amount * 2);
        console.log("Transferred stable token to sender");
    }
}
