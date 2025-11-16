// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626, ERC20} from "@solady-tokens/ERC4626.sol";
import {SafeTransferLib} from "@solady-utils/SafeTransferLib.sol";
import {IHypurrFiPool} from "./interfaces/IHypurrFiPool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";

contract BtcGammaStrategy is ERC4626 {
    using SafeTransferLib for address;

    address public immutable UBTC;
    address public immutable USDXL;
    address public immutable HYPURRFI_POOL;
    address public immutable SWAP_ROUTER;

    // Strategy parameters
    uint256 public targetLTV = 0.6e18; // 60%
    uint256 public maxLTV = 0.7e18; // 70%
    uint256 public minHealthFactor = 1.05e18;
    uint256 public loopCount = 3;

    constructor(address _ubtc, address _usdxl, address _hypurrfiPool, address _swapRouter) {
        UBTC = _ubtc;
        USDXL = _usdxl;
        HYPURRFI_POOL = _hypurrfiPool;
        SWAP_ROUTER = _swapRouter;
    }

    ///////////////////////////////////////////////////////////////
    ///////// External read
    ///////////////////////////////////////////////////////////////

    function name() public pure override returns (string memory) {
        return "BtcGamma Strategy";
    }

    function symbol() public pure override returns (string memory) {
        return "btcGAMMA";
    }

    function asset() public view override returns (address) {
        return UBTC;
    }

    function totalAssets() public view override returns (uint256) {
        // Get actual collateral and debt values from HypurrFi (oracle-priced in base currency)
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) =
            IHypurrFiPool(HYPURRFI_POOL).getUserAccountData(address(this));

        // Net asset value = collateral - debt (both in same base currency units)
        return totalCollateralBase > totalDebtBase ? totalCollateralBase - totalDebtBase : 0;
    }

    ////////////////////////////////////////////////////////////////
    ///////// External write
    ////////////////////////////////////////////////////////////////

    function rebalance() external {
        // TODO: check health factor and rebalance if needed
    }

    ////////////////////////////////////////////////////////////////
    ///////// Internal
    ////////////////////////////////////////////////////////////////

    function _deposit(address by, address to, uint256 assets, uint256 shares) internal override {
        super._deposit(by, to, assets, shares);
        _executeLeverageLoop(assets);
    }

    function _executeLeverageLoop(uint256 initialAmount) internal {
        uint256 supplyAmount = initialAmount;
        uint256 loops = loopCount;

        UBTC.safeApprove(HYPURRFI_POOL, type(uint256).max);
        USDXL.safeApprove(SWAP_ROUTER, type(uint256).max);

        for (uint256 i; i < loops;) {
            IHypurrFiPool(HYPURRFI_POOL).supply(UBTC, supplyAmount, address(this), 0);

            (,, uint256 availableBorrowsBase,, uint256 currentLTV, uint256 healthFactor) =
                IHypurrFiPool(HYPURRFI_POOL).getUserAccountData(address(this));

            uint256 borrowAmount = (availableBorrowsBase * targetLTV) / 1e18;

            if (currentLTV >= maxLTV || borrowAmount == 0 || healthFactor <= minHealthFactor) {
                break;
            }

            IHypurrFiPool(HYPURRFI_POOL).borrow(USDXL, borrowAmount, 2, 0, address(this));

            // TODO: swap USDXL to USDT0 (in Balancer) for better uBTC price

            supplyAmount = _swapStablesToUBTC(borrowAmount);

            unchecked {
                ++i;
            }
        }

        // Supply remaining uBTC from last swap
        if (supplyAmount > 0) {
            IHypurrFiPool(HYPURRFI_POOL).supply(UBTC, supplyAmount, address(this), 0);
        }

        UBTC.safeApprove(HYPURRFI_POOL, 0);
        USDXL.safeApprove(SWAP_ROUTER, 0);
    }

    function _swapStablesToUBTC(uint256 stableAmount) internal returns (uint256) {
        if (stableAmount == 0) return 0;

        uint256 ubtcBefore = ERC20(UBTC).balanceOf(address(this));

        uint256 expectedOut = stableAmount / 95000;

        // 2% slippage tolerance
        uint256 minOut = (expectedOut * 98) / 100;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: USDXL,
            tokenOut: UBTC,
            fee: 3000, // 0.3%
            recipient: address(this),
            amountIn: stableAmount,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });

        ISwapRouter(SWAP_ROUTER).exactInputSingle(params);

        uint256 ubtcAfter = ERC20(UBTC).balanceOf(address(this));
        uint256 received = ubtcAfter - ubtcBefore;
        require(received > 0, "Swap failed");
        require(received >= minOut, "Swap slippage too high");

        return received;
    }
}

