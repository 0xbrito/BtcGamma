import { ethers } from "ethers";

// ERC4626 Vault ABI (BtcGammaStrategy)
const VAULT_ABI = [
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function convertToShares(uint256 assets) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",
  "function maxDeposit(address) view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256)",
  "function mint(uint256 shares, address receiver) returns (uint256)",
  "function withdraw(uint256 assets, address receiver, address owner) returns (uint256)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
];

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
];

export class VaultService {
  constructor(config) {
    this.config = config;
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
    this.wallet = new ethers.Wallet(config.privateKey, this.provider);

    this.vault = new ethers.Contract(
      config.vaultAddress,
      VAULT_ABI,
      this.wallet
    );

    console.log("✓ Vault service initialized");
    console.log(`  Vault: ${config.vaultAddress}`);
  }

  async deposit(userAddress, ubtcAmount) {
    try {
      // Get uBTC token address from vault
      const ubtcAddress = await this.vault.asset();
      const ubtc = new ethers.Contract(ubtcAddress, ERC20_ABI, this.wallet);

      // Convert amount to proper units (uBTC has 8 decimals)
      const amountWei = ethers.parseUnits(ubtcAmount.toString(), 8);

      // Check allowance
      const allowance = await ubtc.allowance(
        userAddress,
        this.config.vaultAddress
      );

      if (allowance < amountWei) {
        // Approve vault to spend uBTC
        const approveTx = await ubtc.approve(
          this.config.vaultAddress,
          ethers.MaxUint256
        );
        await approveTx.wait();
        console.log("Approved vault to spend uBTC");
      }

      // Calculate expected shares
      const expectedShares = await this.vault.convertToShares(amountWei);

      // Deposit to vault
      // Note: In production with non-custodial, user would sign this transaction
      const depositTx = await this.vault.deposit(amountWei, userAddress);
      await depositTx.wait();

      const shares = ethers.formatUnits(expectedShares, 18);

      console.log(`Deposited ${ubtcAmount} uBTC to vault`);
      console.log(`Received ${shares} shares`);
      console.log(`TX: ${depositTx.hash}`);

      return {
        shares: parseFloat(shares),
        tx: depositTx,
      };
    } catch (error) {
      console.error("Error depositing to vault:", error);
      throw error;
    }
  }

  async withdraw(userAddress, shares) {
    try {
      const sharesWei = ethers.parseUnits(shares.toString(), 18);

      // Calculate expected assets
      const expectedAssets = await this.vault.convertToAssets(sharesWei);

      // Redeem shares
      const redeemTx = await this.vault.redeem(
        sharesWei,
        userAddress,
        userAddress
      );
      await redeemTx.wait();

      const assets = ethers.formatUnits(expectedAssets, 8);

      console.log(`Redeemed ${shares} shares`);
      console.log(`Received ${assets} uBTC`);
      console.log(`TX: ${redeemTx.hash}`);

      return {
        assets: parseFloat(assets),
        tx: redeemTx,
      };
    } catch (error) {
      console.error("Error withdrawing from vault:", error);
      throw error;
    }
  }

  async getShares(userAddress) {
    try {
      const shares = await this.vault.balanceOf(userAddress);
      return ethers.formatUnits(shares, 18);
    } catch (error) {
      console.error("Error getting shares:", error);
      return "0";
    }
  }

  async getShareValue(shares) {
    try {
      if (parseFloat(shares) === 0) return 0;

      const sharesWei = ethers.parseUnits(shares.toString(), 18);
      const assets = await this.vault.convertToAssets(sharesWei);
      const ubtcAmount = ethers.formatUnits(assets, 8);

      // Convert to USD (approximate BTC price)
      // In production, use oracle or price feed
      const btcPrice = 95000; // USD
      const value = parseFloat(ubtcAmount) * btcPrice;

      return value;
    } catch (error) {
      console.error("Error getting share value:", error);
      return 0;
    }
  }

  async getTotalAssets() {
    try {
      const assets = await this.vault.totalAssets();
      return ethers.formatUnits(assets, 8);
    } catch (error) {
      console.error("Error getting total assets:", error);
      return "0";
    }
  }

  async getTotalSupply() {
    try {
      const supply = await this.vault.totalSupply();
      return ethers.formatUnits(supply, 18);
    } catch (error) {
      console.error("Error getting total supply:", error);
      return "0";
    }
  }

  async getVaultStats() {
    try {
      const totalAssets = await this.getTotalAssets();
      const totalSupply = await this.getTotalSupply();
      const pricePerShare = parseFloat(totalAssets) / parseFloat(totalSupply);

      return {
        totalAssets,
        totalSupply,
        pricePerShare: pricePerShare || 0,
      };
    } catch (error) {
      console.error("Error getting vault stats:", error);
      return {
        totalAssets: "0",
        totalSupply: "0",
        pricePerShare: 0,
      };
    }
  }
}
