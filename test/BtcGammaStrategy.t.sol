// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {BtcGammaStrategy} from "../src/BtcGammaStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockHypurrFiPool} from "./mocks/MockHypurrFiPool.sol";
import {MockDEX} from "./mocks/MockDEX.sol";
import {MockHyToken} from "./mocks/MockHyToken.sol";

contract BtcGammaStrategyTest is Test {
    BtcGammaStrategy public strategy;
    MockERC20 public ubtc;
    MockERC20 public usdxl;
    MockHypurrFiPool public pool;
    MockDEX public dex;
    MockHyToken public hyUBTC;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 100 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        ubtc = new MockERC20("Unit Bitcoin", "UBTC", 18);
        usdxl = new MockERC20("USDXL Stablecoin", "USDXL", 6);
        pool = new MockHypurrFiPool();
        dex = new MockDEX();
        hyUBTC = new MockHyToken();

        pool.setHyToken(address(ubtc), address(hyUBTC));

        strategy = new BtcGammaStrategy(address(ubtc), address(usdxl), address(pool), address(dex));

        ubtc.mint(alice, INITIAL_BALANCE);
        ubtc.mint(bob, INITIAL_BALANCE);
    }

    function testReturnName() public {
        assertEq(strategy.name(), "BtcGamma Strategy");
    }

    function testReturnSymbol() public {
        assertEq(strategy.symbol(), "btcGAMMA");
    }

    function testAsset() public {
        assertEq(strategy.asset(), address(ubtc));
    }

    function testDeposit() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);

        uint256 sharesBefore = strategy.balanceOf(alice);
        uint256 shares = strategy.deposit(depositAmount, alice);
        uint256 sharesAfter = strategy.balanceOf(alice);

        assertGt(shares, 0, "Should mint shares");
        assertEq(sharesAfter - sharesBefore, shares, "Share balance should increase");
        assertEq(strategy.totalSupply(), shares, "Total supply should match minted shares");
        vm.stopPrank();
    }

    function testDepositExecutesLeverage() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(strategy.totalUSDXLBorrowed(), 0, "Should have borrowed USDXL");
        assertGt(pool.supplied(address(strategy)), 0, "Should have supplied to pool");
        assertGt(strategy.totalAssets(), 0, "Should have net asset value");
    }

    function testDepositMultipleUsers() public {
        uint256 aliceDeposit = 10 ether;
        uint256 bobDeposit = 20 ether;

        // Alice deposits
        vm.startPrank(alice);
        ubtc.approve(address(strategy), aliceDeposit);
        uint256 aliceShares = strategy.deposit(aliceDeposit, alice);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        ubtc.approve(address(strategy), bobDeposit);
        uint256 bobShares = strategy.deposit(bobDeposit, bob);
        vm.stopPrank();

        assertGt(aliceShares, 0, "Alice should have shares");
        assertGt(bobShares, 0, "Bob should have shares");
        assertEq(strategy.balanceOf(alice), aliceShares, "Alice share balance correct");
        assertEq(strategy.balanceOf(bob), bobShares, "Bob share balance correct");
        assertEq(strategy.totalSupply(), aliceShares + bobShares, "Total supply should be sum of shares");
    }

    // function testDepositZeroAmount() public {
    //     vm.startPrank(alice);
    //     ubtc.approve(address(strategy), 0);

    //     vm.expectRevert();
    //     strategy.deposit(0, alice);
    //     vm.stopPrank();
    // }

    function testDepositWithoutApproval() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        vm.expectRevert();
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();
    }

    function testDepositToAnotherAddress() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        uint256 shares = strategy.deposit(depositAmount, bob);
        vm.stopPrank();

        assertEq(strategy.balanceOf(bob), shares, "Bob should receive shares");
        assertEq(strategy.balanceOf(alice), 0, "Alice should have no shares");
    }

    function testFuzzDeposit(uint256 amount) public {
        amount = bound(amount, 1 ether, INITIAL_BALANCE);

        vm.startPrank(alice);
        ubtc.approve(address(strategy), amount);
        uint256 shares = strategy.deposit(amount, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Should mint shares");
        assertEq(strategy.balanceOf(alice), shares, "Share balance should match");
    }

    function testDepositSuppliesCollateralToPool() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(pool.supplied(address(strategy)), 0, "Should have supplied collateral to pool");
        assertGt(strategy.totalUBTCSupplied(), 0, "totalUBTCSupplied should be updated");

        assertEq(ubtc.balanceOf(address(strategy)), 0, "Strategy should not hold idle uBTC");
    }

    function testDepositBorrowsStables() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(strategy.totalUSDXLBorrowed(), 0, "Should have borrowed stables");
        assertGt(pool.borrowed(address(strategy)), 0, "Pool should track borrowed amount");
    }

    function testDepositExecutesMultipleLoops() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(strategy.totalUBTCSupplied(), depositAmount, "Should have leveraged position");

        assertEq(ubtc.balanceOf(address(strategy)), 0, "All uBTC should be supplied");
    }

    function testDepositRespectsTargetLTV() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (,,,, uint256 currentLTV,) = pool.getUserAccountData(address(strategy));

        assertLe(currentLTV, strategy.maxLTV(), "LTV must not exceed max");
        assertGt(currentLTV, 0, "LTV should be > 0 after leverage");
    }

    function testDepositMaintainsSafeHealthFactor() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (,,,,, uint256 healthFactor) = pool.getUserAccountData(address(strategy));
        uint256 minHF = strategy.minHealthFactor();

        assertGe(healthFactor, minHF, "Health factor should be above minimum");
    }

    function testDepositIncreasesTotalAssets() public {
        uint256 depositAmount = 10 ether;

        uint256 assetsBefore = strategy.totalAssets();

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 assetsAfter = strategy.totalAssets();

        assertGt(assetsAfter, assetsBefore, "Total assets should increase");
    }

    function testDepositWithMaxLeverageDoesNotExceedMaxLTV() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        (,,,, uint256 currentLTV,) = pool.getUserAccountData(address(strategy));

        assertLe(currentLTV, strategy.maxLTV(), "Should not exceed max LTV");
    }

    function testConsecutiveDepositsCompoundLeverage() public {
        uint256 firstDeposit = 10 ether;
        uint256 secondDeposit = 5 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), firstDeposit);
        strategy.deposit(firstDeposit, alice);

        uint256 suppliedAfterFirst = strategy.totalUBTCSupplied();

        ubtc.approve(address(strategy), secondDeposit);
        strategy.deposit(secondDeposit, alice);
        vm.stopPrank();

        uint256 suppliedAfterSecond = strategy.totalUBTCSupplied();

        assertGt(suppliedAfterSecond - suppliedAfterFirst, secondDeposit, "Should leverage second deposit");
    }
}
