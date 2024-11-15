// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@solady-tokens/ERC20.sol";
import {Ownable} from "@solady-auth/Ownable.sol";

/**
 * @title LSATToken
 * @notice Lightning Satoshi Token - Represents Lightning sats bridged to HyperEVM
 * @dev Simple ERC20 with minting capability for bridge operator
 */
contract LSATToken is ERC20, Ownable {
    /// @notice Emitted when tokens are bridged from Lightning
    event Bridged(address indexed to, uint256 amount, bytes32 indexed lightningPaymentHash);

    /// @notice Emitted when tokens are burned to withdraw to Lightning
    event Unbridged(address indexed from, uint256 amount, string lightningInvoice);

    /// @notice Bridge operator who can mint tokens
    address public bridge;

    /// @notice Mapping of Lightning payment hashes to prevent double-spending
    mapping(bytes32 => bool) public processedPayments;

    constructor() {
        _initializeOwner(msg.sender);
        bridge = msg.sender;
    }

    function name() public pure override returns (string memory) {
        return "Lightning Satoshi Token";
    }

    function symbol() public pure override returns (string memory) {
        return "LSAT";
    }

    function decimals() public pure override returns (uint8) {
        return 18; // Standard ERC20 decimals
    }

    /**
     * @notice Set the bridge operator address
     * @param _bridge New bridge operator address
     */
    function setBridge(address _bridge) external onlyOwner {
        require(_bridge != address(0), "Invalid bridge address");
        bridge = _bridge;
    }

    /**
     * @notice Mint LSAT tokens when Lightning payment is confirmed
     * @param to Recipient address on HyperEVM
     * @param amount Amount of LSAT to mint (in wei)
     * @param lightningPaymentHash Hash of the Lightning payment for verification
     */
    function mint(address to, uint256 amount, bytes32 lightningPaymentHash) external {
        require(msg.sender == bridge, "Only bridge can mint");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be positive");
        require(!processedPayments[lightningPaymentHash], "Payment already processed");

        processedPayments[lightningPaymentHash] = true;
        _mint(to, amount);

        emit Bridged(to, amount, lightningPaymentHash);
    }

    /**
     * @notice Burn LSAT tokens to withdraw to Lightning
     * @param amount Amount of LSAT to burn
     * @param lightningInvoice Lightning invoice to pay out to
     */
    function burn(uint256 amount, string calldata lightningInvoice) external {
        require(amount > 0, "Amount must be positive");
        require(bytes(lightningInvoice).length > 0, "Invalid invoice");

        _burn(msg.sender, amount);

        emit Unbridged(msg.sender, amount, lightningInvoice);
        // Bridge operator listens for Unbridged event and pays Lightning invoice
    }

    /**
     * @notice Emergency withdrawal by owner
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            ERC20(token).transfer(to, amount);
        }
    }
}
