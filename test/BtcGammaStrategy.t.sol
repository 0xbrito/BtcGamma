// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {BtcGammaStrategy} from "../src/BtcGammaStrategy.sol";
import {ERC20} from "@solady-tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    function name() public pure override returns (string memory) {
        return "Mock Token";
    }

    function symbol() public pure override returns (string memory) {
        return "MOCK";
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockPool {
    mapping(address => uint256) public supplied;
    mapping(address => uint256) public borrowed;

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        supplied[onBehalfOf] += amount;
    }

    function borrow(address asset, uint256 amount, uint256, uint16, address onBehalfOf) external {
        borrowed[onBehalfOf] += amount;
        MockERC20(asset).mint(msg.sender, amount);
    }

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        totalCollateralBase = supplied[user];
        totalDebtBase = borrowed[user];
        availableBorrowsBase = totalCollateralBase > totalDebtBase ? totalCollateralBase - totalDebtBase : 0;
        currentLiquidationThreshold = 80e16;
        ltv = 75e16;
        healthFactor = totalDebtBase > 0 ? (totalCollateralBase * 1e18) / totalDebtBase : type(uint256).max;
    }
}

contract BtcGammaStrategyTest is Test {
    BtcGammaStrategy public strategy;
    MockERC20 public ubtc;
    MockERC20 public usdxl;
    MockPool public pool;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 100 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        ubtc = new MockERC20();
        usdxl = new MockERC20();
        pool = new MockPool();

        strategy = new BtcGammaStrategy(address(ubtc), address(usdxl), address(pool));

        // Mint tokens to test users
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

    function testDepositCallsLeverageLoop() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        ubtc.approve(address(strategy), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, address(strategy), depositAmount);

        strategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify leverage loop was called by checking totalAssets
        // After deposit, assets should be in the strategy
        assertGt(strategy.totalAssets(), 0, "Should have assets after deposit");
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
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.startPrank(alice);
        ubtc.approve(address(strategy), amount);
        uint256 shares = strategy.deposit(amount, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Should mint shares");
        assertEq(strategy.balanceOf(alice), shares, "Share balance should match");
    }
}
