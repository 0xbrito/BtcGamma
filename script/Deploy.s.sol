// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {BtcGammaStrategy} from "../src/BtcGammaStrategy.sol";
import {LSATToken} from "../contracts/LSATToken.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // HyperEVM addresses (update these with actual addresses)
        address ubtc = vm.envOr("UBTC_ADDRESS", address(0x1234567890123456789012345678901234567890));
        address usdxl = vm.envOr("USDXL_ADDRESS", address(0x2234567890123456789012345678901234567890));
        address hypurrfiPool = vm.envOr("HYPURRFI_POOL", address(0x3234567890123456789012345678901234567890));
        address swapRouter = vm.envOr("SWAP_ROUTER", address(0x4234567890123456789012345678901234567890));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy LSAT token
        console.log("Deploying LSAT Token...");
        LSATToken lsat = new LSATToken();
        console.log("LSAT Token deployed at:", address(lsat));

        // Deploy BtcGammaStrategy
        console.log("\nDeploying BtcGammaStrategy...");
        BtcGammaStrategy strategy = new BtcGammaStrategy(ubtc, usdxl, hypurrfiPool, swapRouter);
        console.log("BtcGammaStrategy deployed at:", address(strategy));

        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("LSAT Token:", address(lsat));
        console.log("BtcGammaStrategy:", address(strategy));
        console.log("uBTC:", ubtc);
        console.log("USDXL:", usdxl);
        console.log("HypurrFi Pool:", hypurrfiPool);
        console.log("Swap Router:", swapRouter);

        console.log("\n=== Update your configuration files ===");
        console.log("Client (client/app.js):");
        console.log("  VAULT_ADDRESS:", address(strategy));
        console.log("  LSAT_ADDRESS:", address(lsat));
        console.log("  UBTC_ADDRESS:", ubtc);

        console.log("\nServer (server/.env):");
        console.log("  VAULT_CONTRACT_ADDRESS=", address(strategy));
        console.log("  LSAT_TOKEN_ADDRESS=", address(lsat));
        console.log("  UBTC_TOKEN_ADDRESS=", ubtc);
        console.log("  DEX_ROUTER_ADDRESS=", swapRouter);

        vm.stopBroadcast();
    }
}
