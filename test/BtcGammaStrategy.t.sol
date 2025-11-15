// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {BtcGammaStrategy} from "../src/BtcGammaStrategy.sol";

contract BtcGammaStrategyTest is Test {
    BtcGammaStrategy public strategy;

    function setUp() public {
        strategy = new BtcGammaStrategy();
    }
}
