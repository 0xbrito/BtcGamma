// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {BtcGammaStrategy} from "../src/BtcGammaStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockHypurrFiPool} from "./mocks/MockHypurrFiPool.sol";
import {MockDEX} from "./mocks/MockDEX.sol";
import {MockHyToken} from "./mocks/MockHyToken.sol";

contract WithdrawTest is Test {
    BtcGammaStrategy public strategy;
    MockERC20 public ubtc;
    MockERC20 public usdxl;
    MockHypurrFiPool public pool;
    MockDEX public dex;
    MockHyToken public hyUBTC;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        ubtc = new MockERC20("Unit Bitcoin", "UBTC", 18);
        usdxl = new MockERC20("USDXL Stablecoin", "USDXL", 6);
        pool = new MockHypurrFiPool();
        dex = new MockDEX();
        hyUBTC = new MockHyToken();

        pool.setHyToken(address(ubtc), address(hyUBTC));

        strategy = new BtcGammaStrategy(address(ubtc), address(usdxl), address(pool), address(dex));
        strategy.maxApproveIntegrations();

        ubtc.mint(address(pool), 1000 ether);

        // Setup: Alice deposits
        ubtc.mint(alice, 100 ether);
        vm.startPrank(alice);
        ubtc.approve(address(strategy), 50 ether);
        strategy.deposit(50 ether, alice);
        vm.stopPrank();

        // Setup: Bob deposits
        ubtc.mint(bob, 100 ether);
        vm.startPrank(bob);
        ubtc.approve(address(strategy), 30 ether);
        strategy.deposit(30 ether, bob);
        vm.stopPrank();
    }

    function testWithdrawPartialPosition() public {
        uint256 withdrawAmount = 10 ether;
        uint256 sharesBefore = strategy.balanceOf(alice);
        uint256 ubtcBefore = ubtc.balanceOf(alice);

        vm.prank(alice);
        strategy.withdraw(withdrawAmount, alice, alice);

        uint256 sharesAfter = strategy.balanceOf(alice);
        uint256 ubtcAfter = ubtc.balanceOf(alice);

        assertLt(sharesAfter, sharesBefore, "Shares should decrease");
        assertEq(ubtcAfter - ubtcBefore, withdrawAmount, "Should receive requested uBTC");
    }

    function testWithdrawReducesDebt() public {
        uint256 debtBefore = pool.borrowed(address(strategy));

        vm.prank(alice);
        strategy.withdraw(10 ether, alice, alice);

        uint256 debtAfter = pool.borrowed(address(strategy));

        assertLt(debtAfter, debtBefore, "Debt should decrease after withdrawal");
    }

    function testWithdrawReducesCollateral() public {
        uint256 suppliedBefore = pool.supplied(address(strategy));

        vm.prank(alice);
        strategy.withdraw(10 ether, alice, alice);

        uint256 suppliedAfter = pool.supplied(address(strategy));

        assertLt(suppliedAfter, suppliedBefore, "Collateral should decrease");
    }

    function testWithdrawMaintainsHealthFactor() public {
        vm.prank(alice);
        strategy.withdraw(10 ether, alice, alice);

        (,,,,, uint256 healthFactor) = pool.getUserAccountData(address(strategy));

        assertGe(healthFactor, strategy.minHealthFactor(), "HF should remain healthy after withdraw");
    }

    function testWithdrawDoesNotAffectOtherUsers() public {
        uint256 bobSharesBefore = strategy.balanceOf(bob);

        vm.prank(alice);
        strategy.withdraw(10 ether, alice, alice);

        uint256 bobSharesAfter = strategy.balanceOf(bob);

        assertEq(bobSharesAfter, bobSharesBefore, "Bob's shares should not change");
    }

    function testCannotWithdrawMoreThanOwned() public {
        uint256 aliceShares = strategy.balanceOf(alice);
        uint256 maxWithdraw = strategy.maxWithdraw(alice);

        vm.prank(alice);
        vm.expectRevert();
        strategy.withdraw(maxWithdraw + 1 ether, alice, alice);
    }

    function testMultipleWithdrawals() public {
        vm.startPrank(alice);

        strategy.withdraw(5 ether, alice, alice);
        uint256 sharesAfter1 = strategy.balanceOf(alice);

        strategy.withdraw(5 ether, alice, alice);
        uint256 sharesAfter2 = strategy.balanceOf(alice);

        vm.stopPrank();

        assertLt(sharesAfter2, sharesAfter1, "Shares should keep decreasing");
        assertGt(ubtc.balanceOf(alice), 10 ether, "Should have received all withdrawn uBTC");
    }
}

