// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {ERC4626} from "@solady-tokens/ERC4626.sol";

contract BtcGammaStrategy is ERC4626 {
    constructor() public {}

    function _convertToShares(
        uint256 assets
    ) internal pure override returns (uint256) {
        return assets;
    }
}
