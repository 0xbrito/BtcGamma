// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@solady-tokens/ERC20.sol";

/// @notice Mock hyToken that tracks supplied balance
contract MockHyToken is ERC20 {
    function name() public pure override returns (string memory) {
        return "Mock HyToken";
    }

    function symbol() public pure override returns (string memory) {
        return "hyMOCK";
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
