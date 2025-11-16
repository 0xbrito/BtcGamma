import { ethers } from "ethers";
import crypto from "crypto";

// Simple ERC20 ABI for LSAT token
const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
];

// Mock LSAT minter ABI (you'll need to deploy actual contract)
const LSAT_MINTER_ABI = [
  "function mint(address to, uint256 amount) returns (bool)",
  "function burn(address from, uint256 amount) returns (bool)",
];

// Uniswap V3 Router ABI (simplified)
const SWAP_ROUTER_ABI = [
  "function exactInputSingle((address,address,uint24,address,uint256,uint256,uint160)) external payable returns (uint256)",
];

export class BridgeService {
  constructor(config) {
    this.config = config;
    this.mockMode = config.mockMode || false;

    if (this.mockMode) {
      console.log("✓ Bridge service initialized (MOCK MODE)");
      console.log(`  Mock wallet for demo`);
      this.wallet = { address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" };
    } else {
      this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
      this.wallet = new ethers.Wallet(config.privateKey, this.provider);

      // Initialize contracts
      this.lsatToken = new ethers.Contract(
        config.lsatAddress,
        ERC20_ABI,
        this.wallet
      );

      this.ubtcToken = new ethers.Contract(
        config.ubtcAddress,
        ERC20_ABI,
        this.wallet
      );

      this.dexRouter = new ethers.Contract(
        config.dexRouter,
        SWAP_ROUTER_ABI,
        this.wallet
      );

      console.log("✓ Bridge service initialized");
      console.log(`  Wallet: ${this.wallet.address}`);
    }

    // User wallet storage (in production, use proper key management)
    this.userWallets = new Map();
  }

  async getOrCreateUserWallet(lightningIdentifier, db) {
    // Map Lightning wallet identity to a SINGLE HyperEVM address
    // Same Lightning wallet → Same HyperEVM address across all deposits
    // In production, you'd want:
    // 1. Non-custodial: user signs with their own wallet
    // 2. Or proper key management with HSM/KMS

    // Check memory cache first
    if (this.userWallets.has(lightningIdentifier)) {
      return this.userWallets.get(lightningIdentifier);
    }

    // Check database for existing user wallet
    const existingWallet = await db.getUserWallet(lightningIdentifier);
    if (existingWallet) {
      console.log(
        `✓ Found existing wallet for ${lightningIdentifier.substring(
          0,
          20
        )}...: ${existingWallet.hyperevm_address}`
      );

      const walletData = {
        address: existingWallet.hyperevm_address,
        privateKey: null, // Would decrypt from DB in production
        lightningIdentifier: lightningIdentifier,
      };

      this.userWallets.set(lightningIdentifier, walletData);

      // Update last deposit time
      await db.updateUserWalletLastDeposit(lightningIdentifier);

      return walletData;
    }

    // Create deterministic wallet from Lightning identifier
    // This ensures same Lightning wallet always gets same address
    const seed = crypto
      .createHash("sha256")
      .update(lightningIdentifier)
      .digest("hex");
    const privateKey = "0x" + seed;
    const userWallet = new ethers.Wallet(privateKey);

    const walletData = {
      address: userWallet.address,
      privateKey: userWallet.privateKey,
      lightningIdentifier: lightningIdentifier,
    };

    // Store in database
    await db.createUserWallet({
      lightningIdentifier: lightningIdentifier,
      hyperevmAddress: userWallet.address,
      encryptedPrivateKey: null, // TODO: Encrypt in production
    });

    this.userWallets.set(lightningIdentifier, walletData);

    console.log(
      `✓ Created NEW wallet ${
        userWallet.address
      } for ${lightningIdentifier.substring(0, 20)}...`
    );

    return walletData;
  }

  async mintLSAT(toAddress, amount) {
    try {
      if (this.mockMode) {
        // Mock transaction for demo
        console.log(`[MOCK] Minted ${amount} LSAT to ${toAddress}`);
        return {
          hash: "0x" + crypto.randomBytes(32).toString("hex"),
          wait: async () => ({ status: 1 }),
        };
      }

      // Convert sats to proper LSAT amount (assuming 18 decimals)
      const amountWei = ethers.parseUnits(amount.toString(), 18);

      // In production, this would call a bridge contract that:
      // 1. Verifies Lightning payment proof
      // 2. Mints equivalent LSAT tokens

      // For now, we'll simulate by transferring from our wallet
      const tx = await this.lsatToken.transfer(toAddress, amountWei);

      console.log(`Minted ${amount} LSAT to ${toAddress}`);
      console.log(`TX: ${tx.hash}`);

      return tx;
    } catch (error) {
      console.error("Error minting LSAT:", error);
      throw error;
    }
  }

  async swapLSATToUBTC(fromAddress, lsatAmount) {
    try {
      if (this.mockMode) {
        // Mock swap for demo
        console.log(`[MOCK] Swapped ${lsatAmount} LSAT to uBTC for ${fromAddress}`);
        return {
          hash: "0x" + crypto.randomBytes(32).toString("hex"),
          wait: async () => ({ status: 1 }),
          amountOut: lsatAmount, // 1:1 for demo
        };
      }

      // In production, this would:
      // 1. Use the user's wallet/signature
      // 2. Execute the swap through proper DEX

      const amountIn = ethers.parseUnits(lsatAmount.toString(), 18);

      // Approve DEX to spend LSAT
      const approveTx = await this.lsatToken.approve(
        this.config.dexRouter,
        amountIn
      );
      await approveTx.wait();

      // Execute swap (simplified)
      // In production, calculate proper slippage and price
      const params = {
        tokenIn: this.config.lsatAddress,
        tokenOut: this.config.ubtcAddress,
        fee: 3000, // 0.3%
        recipient: fromAddress,
        amountIn: amountIn,
        amountOutMinimum: 0, // Calculate proper minimum
        sqrtPriceLimitX96: 0,
      };

      const swapTx = await this.dexRouter.exactInputSingle(params);
      await swapTx.wait();

      // Get uBTC received
      const ubtcBalance = await this.ubtcToken.balanceOf(fromAddress);
      const ubtcAmount = ethers.formatUnits(ubtcBalance, 8); // uBTC has 8 decimals

      console.log(`Swapped ${lsatAmount} LSAT to ${ubtcAmount} uBTC`);
      console.log(`TX: ${swapTx.hash}`);

      return {
        ubtcAmount: parseFloat(ubtcAmount),
        tx: swapTx,
      };
    } catch (error) {
      console.error("Error swapping LSAT to uBTC:", error);
      throw error;
    }
  }

  async getTransactionStatus(txHash) {
    try {
      const receipt = await this.provider.getTransactionReceipt(txHash);

      if (!receipt) {
        return "pending";
      }

      return receipt.status === 1 ? "confirmed" : "failed";
    } catch (error) {
      console.error("Error getting transaction status:", error);
      return "unknown";
    }
  }

  async getBalance(address, token) {
    try {
      const contract = token === "lsat" ? this.lsatToken : this.ubtcToken;
      const balance = await contract.balanceOf(address);

      return ethers.formatUnits(balance, token === "lsat" ? 18 : 8);
    } catch (error) {
      console.error("Error getting balance:", error);
      throw error;
    }
  }
}
