// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626, ERC20} from "@solady-tokens/ERC4626.sol";
import {SafeTransferLib} from "@solady-utils/SafeTransferLib.sol";
import {IHypurrFiPool, ReserveData} from "./interfaces/IHypurrFiPool.sol";
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

    event Rebalanced(uint256 oldHF, uint256 newHF, uint256 debtRepaid);
    event UnderwaterPosition(uint256 collateral, uint256 debt);

    constructor(address _ubtc, address _usdxl, address _hypurrfiPool, address _swapRouter) {
        UBTC = _ubtc;
        USDXL = _usdxl;
        HYPURRFI_POOL = _hypurrfiPool;
        SWAP_ROUTER = _swapRouter;
    }

    function maxApproveIntegrations() external {
        UBTC.safeApprove(HYPURRFI_POOL, type(uint256).max);
        UBTC.safeApprove(SWAP_ROUTER, type(uint256).max);
        USDXL.safeApprove(SWAP_ROUTER, type(uint256).max);
        USDXL.safeApprove(HYPURRFI_POOL, type(uint256).max);
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
        (uint256 totalCollateralBase, uint256 totalDebtBase,,, uint256 currentLTV, uint256 healthFactor) =
            IHypurrFiPool(HYPURRFI_POOL).getUserAccountData(address(this));

        if (totalCollateralBase <= totalDebtBase) {
            emit UnderwaterPosition(totalCollateralBase, totalDebtBase);
            return;
        }

        uint256 safeHF = (minHealthFactor * 115) / 100;
        if (healthFactor >= safeHF && currentLTV <= (maxLTV * 95) / 100) {
            return;
        }

        uint256 initialHF = healthFactor;

        ReserveData memory reserveData = IHypurrFiPool(HYPURRFI_POOL).getReserveData(UBTC);
        uint256 hyTokenBalance = ERC20(reserveData.aTokenAddress).balanceOf(address(this));

        // Withdraw 10% of hyToken balance
        uint256 withdrawAmount = hyTokenBalance / 10;

        IHypurrFiPool(HYPURRFI_POOL).withdraw(UBTC, withdrawAmount, address(this));

        uint256 amountReceived = _swap(UBTC, USDXL, withdrawAmount);

        IHypurrFiPool(HYPURRFI_POOL).repay(USDXL, amountReceived, 2, address(this));

        (,,,,, uint256 finalHF) = IHypurrFiPool(HYPURRFI_POOL).getUserAccountData(address(this));
        emit Rebalanced(initialHF, finalHF, amountReceived);
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

            supplyAmount = _swap(USDXL, UBTC, borrowAmount);

            unchecked {
                ++i;
            }
        }

        // Supply remaining uBTC from last swap
        if (supplyAmount > 0) {
            IHypurrFiPool(HYPURRFI_POOL).supply(UBTC, supplyAmount, address(this), 0);
        }
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        if (amountIn == 0) return 0;

        uint256 balanceBefore = ERC20(tokenOut).balanceOf(address(this));

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 3000,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        ISwapRouter(SWAP_ROUTER).exactInputSingle(params);

        uint256 balanceAfter = ERC20(tokenOut).balanceOf(address(this));
        uint256 received = balanceAfter - balanceBefore;
        require(received > 0, "Swap failed");

        return received;
    }
}

