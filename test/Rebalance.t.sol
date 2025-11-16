// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {BtcGammaStrategy} from "../src/BtcGammaStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockHypurrFiPool} from "./mocks/MockHypurrFiPool.sol";
import {MockDEX} from "./mocks/MockDEX.sol";
import {MockHyToken} from "./mocks/MockHyToken.sol";

contract RebalanceTest is Test {
    BtcGammaStrategy public strategy;
    MockERC20 public ubtc;
    MockERC20 public usdxl;
    MockHypurrFiPool public pool;
    MockDEX public dex;
    MockHyToken public hyUBTC;

    address public alice = makeAddr("alice");
    address public keeper = makeAddr("keeper");

    event UnderwaterPosition(uint256 collateral, uint256 debt);
    event Rebalanced(uint256 oldHF, uint256 newHF, uint256 debtRepaid);

    function setUp() public {
        ubtc = new MockERC20("Unit Bitcoin", "UBTC", 18);
        usdxl = new MockERC20("USDXL Stablecoin", "USDXL", 6);
        pool = new MockHypurrFiPool();
        dex = new MockDEX();
        hyUBTC = new MockHyToken();

        pool.setHyToken(address(ubtc), address(hyUBTC));

        strategy = new BtcGammaStrategy(address(ubtc), address(usdxl), address(pool), address(dex));
        strategy.maxApproveIntegrations();

        // Setup initial position
        ubtc.mint(alice, 100 ether);
        vm.startPrank(alice);
        ubtc.approve(address(strategy), 10 ether);
        strategy.deposit(10 ether, alice);
        vm.stopPrank();
    }

    function testRebalanceImprovesHealthFactor() public {
        (,,,,, uint256 hfBefore) = pool.getUserAccountData(address(strategy));

        // Mock: simulate price drop by adjusting pool's collateral/debt tracking
        pool.simulatePriceShock(address(strategy), 27); // 20% collateral value drop

        (,,,,, uint256 hfAfterShock) = pool.getUserAccountData(address(strategy));
        require(hfAfterShock < strategy.minHealthFactor(), "Setup: HF should be unhealthy");

        strategy.rebalance();

        (,,,,, uint256 hfAfterRebalance) = pool.getUserAccountData(address(strategy));

        assertGt(hfAfterRebalance, hfAfterShock, "HF should improve after rebalance");
        assertGe(hfAfterRebalance, strategy.minHealthFactor(), "HF should be above minimum");
    }

    function testRebalanceReducesDebt() public {
        uint256 debtBefore = pool.borrowed(address(strategy));

        pool.simulatePriceShock(address(strategy), 27);

        strategy.rebalance();

        uint256 debtAfter = pool.borrowed(address(strategy));

        assertLt(debtAfter, debtBefore, "Debt should decrease after rebalance");
    }

    function testRebalanceWithdrawsCollateral() public {
        uint256 suppliedBefore = pool.supplied(address(strategy));

        pool.simulatePriceShock(address(strategy), 27);

        strategy.rebalance();

        uint256 suppliedAfter = pool.supplied(address(strategy));

        assertLt(suppliedAfter, suppliedBefore, "Should withdraw some collateral");
    }

    function testRebalanceWhenHealthyDoesNothing() public {
        (,,,,, uint256 hfBefore) = pool.getUserAccountData(address(strategy));
        uint256 debtBefore = pool.borrowed(address(strategy));

        strategy.rebalance();

        (,,,,, uint256 hfAfter) = pool.getUserAccountData(address(strategy));
        uint256 debtAfter = pool.borrowed(address(strategy));

        assertApproxEqAbs(hfAfter, hfBefore, 0.01e18, "HF should not change when healthy");
        assertApproxEqAbs(debtAfter, debtBefore, 1e6, "Debt should not change when healthy");
    }

    function testRebalanceWhenAlreadyHealthyIsNoOp() public {
        (,,,,, uint256 hfBefore) = pool.getUserAccountData(address(strategy));
        require(hfBefore >= strategy.minHealthFactor(), "Setup: should start healthy");

        uint256 debtBefore = pool.borrowed(address(strategy));

        strategy.rebalance();

        uint256 debtAfter = pool.borrowed(address(strategy));

        assertApproxEqAbs(debtAfter, debtBefore, 1e6, "Debt should not change when healthy");
    }

    function testRebalanceEmitsEventWhenUnderwater() public {
        // Simulate catastrophic price drop
        pool.simulatePriceShock(address(strategy), 80); // 80% collateral drop

        (uint256 collateral, uint256 debt,,,,) = pool.getUserAccountData(address(strategy));
        require(debt >= collateral, "Setup: should be underwater");

        // Should emit UnderwaterPosition event instead of reverting
        vm.expectEmit(false, false, false, true);
        emit UnderwaterPosition(collateral, debt);
        strategy.rebalance();
    }

    function testRebalanceMaintainsUserShares() public {
        uint256 sharesBefore = strategy.balanceOf(alice);

        pool.simulatePriceShock(address(strategy), 27);
        strategy.rebalance();

        uint256 sharesAfter = strategy.balanceOf(alice);

        assertEq(sharesAfter, sharesBefore, "User shares should not change during rebalance");
    }
}
