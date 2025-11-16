import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import { LightningService } from "./services/lightning.js";
import { BridgeService } from "./services/bridge.js";
import { VaultService } from "./services/vault.js";
import { DatabaseService } from "./services/database.js";

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Initialize services
const db = new DatabaseService(
  process.env.DATABASE_PATH || "./data/deposits.db"
);
const lightning = new LightningService({
  nwcUrl: process.env.NWC_URL,
  macaroon: process.env.LND_MACAROON,
  socket: process.env.LND_SOCKET,
  certPath: process.env.LND_CERT_PATH,
});
const bridge = new BridgeService({
  rpcUrl: process.env.HYPEREVM_RPC_URL,
  privateKey: process.env.HYPEREVM_PRIVATE_KEY,
  lsatAddress: process.env.LSAT_TOKEN_ADDRESS,
  ubtcAddress: process.env.UBTC_TOKEN_ADDRESS,
  dexRouter: process.env.DEX_ROUTER_ADDRESS,
});
const vault = new VaultService({
  rpcUrl: process.env.HYPEREVM_RPC_URL,
  privateKey: process.env.HYPEREVM_PRIVATE_KEY,
  vaultAddress: process.env.VAULT_CONTRACT_ADDRESS,
});

// Initialize database
await db.init();

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "ok", timestamp: Date.now() });
});

// Create Lightning invoice
app.post("/api/create-invoice", async (req, res) => {
  try {
    const { amount, memo, lightning_address } = req.body;

    if (!amount || amount < parseInt(process.env.MIN_DEPOSIT_SATS || "1000")) {
      return res.status(400).json({
        error: "Invalid amount",
        min: process.env.MIN_DEPOSIT_SATS,
      });
    }

    // Create Lightning invoice
    const invoice = await lightning.createInvoice({
      tokens: amount,
      description: memo || "BTC Gamma Strategy Deposit",
    });

    // Try to get Lightning identifier (for mapping to HyperEVM address)
    // Priority: lightning_address from client > NWC wallet pubkey > NWC lud16 > NWC connection URL
    let lightningIdentifier = lightning_address;

    if (!lightningIdentifier && lightning.mode === "nwc") {
      // For NWC, use a stable identifier that represents the WALLET, not the payment
      try {
        const info = await lightning.nwc.getInfo();
        // Try to get a stable wallet identifier
        lightningIdentifier = info.pubkey || info.lud16 || process.env.NWC_URL;
      } catch (e) {
        // Use NWC connection URL as the identifier (same wallet = same URL)
        lightningIdentifier = process.env.NWC_URL;
      }
    } else if (!lightningIdentifier && lightning.mode === "lnd") {
      // For LND, could use node pubkey
      lightningIdentifier = "lnd_node"; // Would be node's pubkey in production
    } else if (!lightningIdentifier) {
      // Only fallback to payment_hash for mock mode or if all else fails
      lightningIdentifier = invoice.id;
    }

    console.log(
      `Lightning identifier: ${lightningIdentifier.substring(0, 40)}...`
    );

    // Get or create HyperEVM address for this Lightning wallet
    const { address: hyperevmAddress } = await bridge.getOrCreateUserWallet(
      lightningIdentifier,
      db
    );

    // Store invoice in database WITH mapped hyperevm_address
    await db.createDeposit({
      paymentHash: invoice.id,
      amount,
      invoice: invoice.request,
      status: "pending",
      hyperevmAddress: hyperevmAddress,
    });

    res.json({
      invoice: invoice.request,
      payment_hash: invoice.id,
      amount,
      expires_at: invoice.expires_at,
      hyperevm_address: hyperevmAddress, // Return address so client can track
    });
  } catch (error) {
    console.error("Error creating invoice:", error);
    res.status(500).json({ error: error.message });
  }
});

// Verify Lightning payment
app.post("/api/verify-payment", async (req, res) => {
  try {
    const { payment_hash, preimage } = req.body;

    // Get stored deposit to retrieve amount
    const deposit = await db.getDeposit(payment_hash);
    if (!deposit) {
      return res.status(400).json({ error: "Invoice not found" });
    }

    // Verify preimage matches payment hash
    const isValid = lightning.verifyPreimage(payment_hash, preimage);

    if (!isValid) {
      return res.status(400).json({ error: "Invalid preimage" });
    }

    // For NWC and mock mode, preimage verification is sufficient
    // For LND, we can also check the invoice status
    if (lightning.mode === "lnd") {
      const invoice = await lightning.getInvoice({ id: payment_hash });
      if (!invoice.is_confirmed) {
        return res.status(400).json({ error: "Payment not confirmed by node" });
      }
    }

    // Update database
    await db.updateDeposit(payment_hash, {
      status: "paid",
      preimage,
      paidAt: new Date(),
    });

    res.json({
      verified: true,
      amount: deposit.amount,
    });
  } catch (error) {
    console.error("Error verifying payment:", error);
    res.status(500).json({ error: error.message });
  }
});

// Bridge Lightning deposit to HyperEVM
app.post("/api/bridge-to-hyperevm", async (req, res) => {
  try {
    const { payment_hash } = req.body;

    if (!payment_hash) {
      return res.status(400).json({ error: "payment_hash required" });
    }

    // Get the deposit to verify it was paid
    const deposit = await db.getDeposit(payment_hash);
    if (!deposit) {
      return res.status(400).json({ error: "Deposit not found" });
    }

    if (deposit.status !== "paid") {
      return res.status(400).json({ error: "Payment not confirmed" });
    }

    // Get existing HyperEVM address (already mapped during invoice creation)
    const hyperevmAddress = deposit.hyperevm_address;

    if (!hyperevmAddress) {
      return res
        .status(500)
        .json({ error: "HyperEVM address not found for this deposit" });
    }

    // Calculate LSAT amount (1:1 ratio for now, adjust as needed)
    const lsatAmount =
      deposit.amount * parseInt(process.env.SATS_TO_LSAT_RATIO || "1");

    // Mint LSAT tokens to user's address
    const tx = await bridge.mintLSAT(hyperevmAddress, lsatAmount);

    // Wait for confirmation
    await tx.wait();

    // Update database with mapping
    await db.updateDeposit(payment_hash, {
      hyperevmAddress: address,
      lsatAmount,
      bridgeTxHash: tx.hash,
      status: "bridged",
    });

    res.json({
      hyperevmAddress: hyperevmAddress,
      lsatAmount,
      txHash: tx.hash,
    });
  } catch (error) {
    console.error("Error bridging to HyperEVM:", error);
    res.status(500).json({ error: error.message });
  }
});

// Swap LSAT to uBTC
app.post("/api/swap-to-ubtc", async (req, res) => {
  try {
    const { payment_hash } = req.body;

    if (!payment_hash) {
      return res.status(400).json({ error: "payment_hash required" });
    }

    // Get the deposit
    const deposit = await db.getDeposit(payment_hash);
    if (!deposit || deposit.status !== "bridged") {
      return res.status(400).json({ error: "Deposit not bridged yet" });
    }

    // Execute swap on DEX
    const { ubtcAmount, tx } = await bridge.swapLSATToUBTC(
      deposit.hyperevm_address,
      deposit.lsat_amount
    );

    // Wait for confirmation
    await tx.wait();

    // Update database
    await db.updateDeposit(payment_hash, {
      ubtcAmount,
      swapTxHash: tx.hash,
      status: "swapped",
    });

    res.json({
      ubtcAmount,
      txHash: tx.hash,
    });
  } catch (error) {
    console.error("Error swapping to uBTC:", error);
    res.status(500).json({ error: error.message });
  }
});

// Deposit uBTC to vault
app.post("/api/deposit-to-vault", async (req, res) => {
  try {
    const { payment_hash } = req.body;

    if (!payment_hash) {
      return res.status(400).json({ error: "payment_hash required" });
    }

    // Get the deposit
    const deposit = await db.getDeposit(payment_hash);
    if (!deposit || deposit.status !== "swapped") {
      return res.status(400).json({ error: "Deposit not swapped yet" });
    }

    // Deposit to BtcGammaStrategy vault
    const { shares, tx } = await vault.deposit(
      deposit.hyperevm_address,
      deposit.ubtc_amount
    );

    // Wait for confirmation
    await tx.wait();

    // Update database
    await db.updateDeposit(payment_hash, {
      vaultShares: shares,
      depositTxHash: tx.hash,
      status: "completed",
      completedAt: new Date(),
    });

    res.json({
      shares,
      txHash: tx.hash,
      hyperevmAddress: deposit.hyperevm_address,
    });
  } catch (error) {
    console.error("Error depositing to vault:", error);
    res.status(500).json({ error: error.message });
  }
});

// Get transaction status
app.get("/api/tx-status/:txHash", async (req, res) => {
  try {
    const { txHash } = req.params;
    const status = await bridge.getTransactionStatus(txHash);

    res.json({ status });
  } catch (error) {
    console.error("Error getting transaction status:", error);
    res.status(500).json({ error: error.message });
  }
});

// Get user balance
app.get("/api/user-balance/:address", async (req, res) => {
  try {
    const { address } = req.params;

    // Get user's vault shares
    const shares = await vault.getShares(address);

    // Get total value in USD
    const value = await vault.getShareValue(shares);

    res.json({ shares, value });
  } catch (error) {
    console.error("Error getting user balance:", error);
    res.status(500).json({ error: error.message });
  }
});

// Get deposit history
app.get("/api/deposits/:address", async (req, res) => {
  try {
    const { address } = req.params;
    const deposits = await db.getDepositsByAddress(address);

    res.json({ deposits });
  } catch (error) {
    console.error("Error getting deposits:", error);
    res.status(500).json({ error: error.message });
  }
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 BTC Gamma Server running on port ${PORT}`);
  console.log(`⚡ Lightning node: ${process.env.LND_SOCKET}`);
  console.log(`🔗 HyperEVM RPC: ${process.env.HYPEREVM_RPC_URL}`);
});

// Graceful shutdown
process.on("SIGTERM", async () => {
  console.log("SIGTERM received, shutting down gracefully...");
  await db.close();
  process.exit(0);
});
