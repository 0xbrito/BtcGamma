// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@solady-tokens/ERC20.sol";
import {MockERC20} from "./MockERC20.sol";
import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";

/// @notice Mock DEX implementing HyperSwap V3 interface for testing
contract MockDEX is ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        // Transfer input tokens from caller
        ERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Determine swap direction by checking decimals
        uint8 inputDecimals = ERC20(params.tokenIn).decimals();
        uint8 outputDecimals = ERC20(params.tokenOut).decimals();

        if (inputDecimals == 6 && outputDecimals == 18) {
            // USDXL (6 decimals) -> uBTC (18 decimals): $1 -> $95k
            amountOut = (params.amountIn * 1e18) / (95000 * 1e6);
        } else if (inputDecimals == 18 && outputDecimals == 6) {
            // uBTC (18 decimals) -> USDXL (6 decimals): $95k -> $1
            amountOut = (params.amountIn * 95000 * 1e6) / 1e18;
        } else {
            revert("Unsupported swap pair");
        }

        require(amountOut > 0, "Amount too small");
        require(amountOut >= params.amountOutMinimum, "Insufficient output amount");

        MockERC20(params.tokenOut).mint(params.recipient, amountOut);

        return amountOut;
    }
}
