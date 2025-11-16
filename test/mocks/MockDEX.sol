// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@solady-tokens/ERC20.sol";
import {MockERC20} from "./MockERC20.sol";
import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";

/// @notice Mock DEX implementing HyperSwap V3 interface for testing
contract MockDEX is ISwapRouter {
    /// @notice Swaps exact amount of input token for output token (1:1 for testing)
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        // Transfer input tokens from caller
        ERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        
        // For testing: 1:1 swap (in production this would use AMM pricing)
        amountOut = params.amountIn;
        require(amountOut >= params.amountOutMinimum, "Insufficient output amount");
        
        // Mint output tokens to recipient (only works with MockERC20)
        MockERC20(params.tokenOut).mint(params.recipient, amountOut);
        
        return amountOut;
    }

    /// @notice Not implemented for testing
    function exactInput(ExactInputParams calldata) external payable override returns (uint256) {
        revert("Not implemented");
    }
}
