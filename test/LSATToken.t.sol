// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LSATToken} from "../contracts/LSATToken.sol";

contract LSATTokenTest is Test {
    LSATToken public lsat;
    address public owner;
    address public bridge;
    address public user;

    function setUp() public {
        owner = address(this);
        bridge = makeAddr("bridge");
        user = makeAddr("user");

        lsat = new LSATToken();
        lsat.setBridge(bridge);
    }

    function test_Deployment() public view {
        assertEq(lsat.name(), "Lightning Satoshi Token");
        assertEq(lsat.symbol(), "LSAT");
        assertEq(lsat.decimals(), 18);
        assertEq(lsat.owner(), owner);
        assertEq(lsat.bridge(), bridge);
    }

    function test_SetBridge() public {
        address newBridge = makeAddr("newBridge");
        lsat.setBridge(newBridge);
        assertEq(lsat.bridge(), newBridge);
    }

    function test_Mint() public {
        uint256 amount = 21000 * 1e18;
        bytes32 paymentHash = keccak256("payment1");

        vm.prank(bridge);
        lsat.mint(user, amount, paymentHash);

        assertEq(lsat.balanceOf(user), amount);
        assertTrue(lsat.processedPayments(paymentHash));
    }

    function testFail_MintTwice() public {
        uint256 amount = 21000 * 1e18;
        bytes32 paymentHash = keccak256("payment1");

        vm.startPrank(bridge);
        lsat.mint(user, amount, paymentHash);
        lsat.mint(user, amount, paymentHash); // Should fail
        vm.stopPrank();
    }

    function testFail_MintUnauthorized() public {
        uint256 amount = 21000 * 1e18;
        bytes32 paymentHash = keccak256("payment1");

        vm.prank(user);
        lsat.mint(user, amount, paymentHash); // Should fail
    }

    function test_Burn() public {
        uint256 amount = 21000 * 1e18;
        bytes32 paymentHash = keccak256("payment1");
        string memory invoice = "lnbc210000n1...";

        // Mint first
        vm.prank(bridge);
        lsat.mint(user, amount, paymentHash);

        // Burn
        vm.prank(user);
        lsat.burn(amount, invoice);

        assertEq(lsat.balanceOf(user), 0);
    }

    function testFuzz_Mint(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);
        bytes32 paymentHash = keccak256(abi.encodePacked(amount));

        vm.prank(bridge);
        lsat.mint(user, amount, paymentHash);

        assertEq(lsat.balanceOf(user), amount);
    }
}
