// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHypurrFiPool, ReserveData, ReserveConfigurationMap} from "../../src/interfaces/IHypurrFiPool.sol";
import {ERC20} from "@solady-tokens/ERC20.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockHyToken} from "./MockHyToken.sol";

contract MockHypurrFiPool is IHypurrFiPool {
    mapping(address => uint256) public supplied;
    mapping(address => uint256) public borrowed;
    mapping(address => bool) public collateralEnabled;
    mapping(address => address) public hyTokens; // asset => hyToken

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external override {
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        supplied[onBehalfOf] += amount;
        collateralEnabled[onBehalfOf] = true;

        // Mint hyTokens to user (1:1)
        address hyToken = hyTokens[asset];
        if (hyToken != address(0)) {
            MockHyToken(hyToken).mint(onBehalfOf, amount);
        }
    }

    function borrow(address asset, uint256 amount, uint256, uint16, address onBehalfOf) external override {
        borrowed[onBehalfOf] += amount;
        MockERC20(asset).mint(msg.sender, amount);
    }

    function repay(address asset, uint256 amount, uint256, address onBehalfOf) external override returns (uint256) {
        uint256 repayAmount = amount > borrowed[onBehalfOf] ? borrowed[onBehalfOf] : amount;
        ERC20(asset).transferFrom(msg.sender, address(this), repayAmount);
        borrowed[onBehalfOf] -= repayAmount;
        return repayAmount;
    }

    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        uint256 withdrawAmount = amount > supplied[msg.sender] ? supplied[msg.sender] : amount;
        supplied[msg.sender] -= withdrawAmount;

        // Mint underlying asset to recipient
        MockERC20(asset).mint(to, withdrawAmount);
        return withdrawAmount;
    }

    function getUserAccountData(address user)
        external
        view
        override
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
        totalDebtBase = borrowed[user] * 1e12; // Convert from 6 decimals to 18

        uint256 maxBorrowCapacity = (totalCollateralBase * 7500) / 10000;
        availableBorrowsBase = maxBorrowCapacity > totalDebtBase ? maxBorrowCapacity - totalDebtBase : 0;

        availableBorrowsBase = availableBorrowsBase / 1e12;

        currentLiquidationThreshold = 8000; // 80%

        ltv = totalCollateralBase > 0 ? (totalDebtBase * 10000) / totalCollateralBase : 0;

        healthFactor = totalDebtBase > 0 ? (totalCollateralBase * 1e18) / totalDebtBase : type(uint256).max;
    }

    function getReserveData(address asset) external view override returns (ReserveData memory) {
        ReserveData memory data;
        data.aTokenAddress = hyTokens[asset];
        return data;
    }

    function setHyToken(address asset, address hyToken) external {
        hyTokens[asset] = hyToken;
    }

    function setUserUseReserveAsCollateral(address, bool useAsCollateral) external override {
        collateralEnabled[msg.sender] = useAsCollateral;
    }

    // (Test helper) simulate price shock by reducing collateral value
    function simulatePriceShock(address user, uint256 percentDrop) external {
        require(percentDrop <= 100, "Invalid percent");
        uint256 reduction = (supplied[user] * percentDrop) / 100;
        supplied[user] -= reduction;
    }
}
