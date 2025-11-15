// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "@solady-tokens/ERC4626.sol";
import {ERC20} from "@solady-tokens/ERC20.sol";

contract BtcGammaStrategy is ERC4626 {
    address public immutable UBTC;

    constructor(address _ubtc) {
        UBTC = _ubtc;
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
}
