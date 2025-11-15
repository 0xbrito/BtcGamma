// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626, ERC20} from "@solady-tokens/ERC4626.sol";

contract BtcGammaStrategy is ERC4626 {
    address public immutable UBTC;
    address public immutable USDXL;

    address public immutable HYPURRFI_POOL;

    constructor(address _ubtc, address _usdxl, address _hypurrfiPool) {
        UBTC = _ubtc;
        USDXL = _usdxl;
        HYPURRFI_POOL = _hypurrfiPool;
    }

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
        return ERC20(UBTC).balanceOf(address(this));
    }

    function _deposit(address by, address to, uint256 assets, uint256 shares) internal virtual override {
        super._deposit(by, to, assets, shares);
        _executeLeverageLoop(assets);
    }

    function _executeLeverageLoop(uint256 initialAmount) internal {
        // TODO: implement leverage loop
        // 1. Supply uBTC to HypurrFi
        // 2. Borrow stablecoins
        // 3. Swap stables -> uBTC
        // 4. Repeat loopCount times
    }

    function rebalance() external {
        // TODO: check health factor and rebalance if needed
    }
}

