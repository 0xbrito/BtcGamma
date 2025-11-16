// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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
