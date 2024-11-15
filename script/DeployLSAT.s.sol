// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LSATToken} from "../contracts/LSATToken.sol";

contract DeployLSATScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy LSAT token
        LSATToken lsat = new LSATToken();

        console.log("LSAT Token deployed at:", address(lsat));
        console.log("Name:", lsat.name());
        console.log("Symbol:", lsat.symbol());
        console.log("Decimals:", lsat.decimals());
        console.log("Owner:", lsat.owner());
        console.log("Bridge:", lsat.bridge());

        vm.stopBroadcast();
    }
}
