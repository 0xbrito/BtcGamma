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
    uint256 public minHealthFactor = 1.2e18;
    uint256 public loopCount = 3;

    // Tracking
    uint256 public totalUBTCSupplied;
    uint256 public totalUSDXLBorrowed;

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

        for (uint256 i = 0; i < loopCount; i++) {
            UBTC.safeApprove(HYPURRFI_POOL, supplyAmount);
            IHypurrFiPool(HYPURRFI_POOL).supply(UBTC, supplyAmount, address(this), 0);
            totalUBTCSupplied += supplyAmount;

            uint256 borrowAmount = (supplyAmount * targetLTV) / 1e18;

            IHypurrFiPool(HYPURRFI_POOL).borrow(USDXL, borrowAmount, 2, 0, address(this));
            totalUSDXLBorrowed += borrowAmount;

            // TODO: swap USDXL to USDT0 (in Balancer) for better uBTC price

            supplyAmount = _swapStablesToUBTC(borrowAmount);

            // Safety check: ensure we're not exceeding max LTV
            (,,,, uint256 currentLTV,) = IHypurrFiPool(HYPURRFI_POOL).getUserAccountData(address(this));
            if (currentLTV >= maxLTV) {
                break;
            }
        }

        // supply remaining uBTC from last swap
        if (supplyAmount > 0) {
            UBTC.safeApprove(HYPURRFI_POOL, supplyAmount);
            IHypurrFiPool(HYPURRFI_POOL).supply(UBTC, supplyAmount, address(this), 0);
            totalUBTCSupplied += supplyAmount;
        }
    }

    function _swapStablesToUBTC(uint256 stableAmount) internal virtual returns (uint256) {
        USDXL.safeApprove(SWAP_ROUTER, stableAmount);

        uint256 minOut = (stableAmount * 99) / 100;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: USDXL,
            tokenOut: UBTC,
            fee: 3000, // 0.3%
            recipient: address(this),
            amountIn: stableAmount,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
        return amountOut;
    }
}

