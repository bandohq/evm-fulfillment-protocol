// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestSwapAggregator {
    //Simulate a "swap" by transferring fromToken in and toToken out

    function swapTokens(
        address fromToken,
        address toToken,
        uint256 amount
    ) external returns (bool) {
        // contract calling this should have approved 'amount' of fromToken
        IERC20(fromToken).transferFrom(msg.sender, address(this), amount);

        // For simpler testing, let's assume we have unlimited toToken
        // so we just mint or assume this aggregator has infinite toToken
        IERC20(toToken).transfer(msg.sender, amount * 2); 
        // e.g. 2x for demonstration purposes
        return true;
    }
}
