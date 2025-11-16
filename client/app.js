import {
  LightningAddress,
  Invoice,
} from "https://esm.sh/@getalby/lightning-tools@5.0.0";
import { ethers } from "https://esm.sh/ethers@6.9.0";
import CONFIG from "./config.js";

// Global state
let webln = null;
let provider = null;
let signer = null;
let userAddress = null;

// Helper: Delay function for demo visualization
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Initialize on page load
window.addEventListener("DOMContentLoaded", async () => {
  updateConversions();
  checkWebLNAvailability();

  // Auto-connect if WebLN is available
  if (typeof window.webln !== "undefined") {
    await connectWebLN();
  }
});

// Check if WebLN is available
function checkWebLNAvailability() {
  const status = document.getElementById("weblnStatus");
  if (typeof window.webln !== "undefined") {
    status.textContent = "WebLN Available";
    status.className = "status-badge";
  } else {
    status.textContent = "WebLN Not Available - Install Alby or similar";
    status.className = "status-badge disconnected";
  }
}

// Connect to WebLN
window.connectWebLN = async function () {
  const connectBtn = document.getElementById("connectBtn");
  const depositBtn = document.getElementById("depositBtn");
  const status = document.getElementById("weblnStatus");

  try {
    if (!window.webln) {
      throw new Error(
        "WebLN not available. Please install Alby or another WebLN wallet."
      );
    }

    await window.webln.enable();
    webln = window.webln;

    status.textContent = "⚡ WebLN Connected";
    status.className = "status-badge connected";
    connectBtn.style.display = "none";
    depositBtn.disabled = false;

    // Get wallet info if available
    try {
      const info = await webln.getInfo();
      console.log("Connected to:", info);
    } catch (e) {
      console.log("Could not get wallet info");
    }
  } catch (error) {
    console.error("Failed to connect WebLN:", error);
    showError(error.message);
  }
};

// Update BTC and USD conversions
document
  .getElementById("satAmount")
  ?.addEventListener("input", updateConversions);

function updateConversions() {
  const satAmount = parseInt(document.getElementById("satAmount").value) || 0;
  const btcAmount = (satAmount / 100000000).toFixed(8);
  const usdAmount = (satAmount * 0.0005).toFixed(2); // Approximate

  document.getElementById("btcEquivalent").textContent = btcAmount;
  document.getElementById("usdEquivalent").textContent = usdAmount;
}

// Main deposit flow
window.initiateDeposit = async function () {
  const satAmount = parseInt(document.getElementById("satAmount").value);

  if (!satAmount || satAmount < CONFIG.MIN_DEPOSIT_SATS) {
    showError(`Please enter at least ${CONFIG.MIN_DEPOSIT_SATS} sats`);
    return;
  }

  if (!webln) {
    showError("Please connect WebLN first");
    return;
  }

  try {
    showLoading("Initiating deposit...");
    hideMessages();

    // Step 1: Pay Lightning Invoice and get payment hash
    const { payment_hash } = await executeStep1(satAmount);
    await delay(2000); // 2 second delay for demo visualization

    // Step 2: Bridge to HyperEVM (pass payment_hash)
    await executeStep2(payment_hash);
    await delay(2000); // 2 second delay for demo visualization

    // Step 3: Swap to uBTC (pass payment_hash)
    await executeStep3(payment_hash);
    await delay(2000); // 2 second delay for demo visualization

    // Step 4: Deposit to Vault (pass payment_hash)
    await executeStep4(payment_hash);

    showSuccess("Deposit completed successfully!");
    updateUserBalance();
  } catch (error) {
    console.error("Deposit failed:", error);
    showError(error.message);
    resetSteps();
  } finally {
    hideLoading();
  }
};

// Step 1: Lightning Payment
async function executeStep1(satAmount) {
  updateStepStatus(1, "active");
  showLoading("⚡ Creating Lightning invoice...");

  // Request invoice from backend
  const response = await fetch(`${CONFIG.API_URL}/api/create-invoice`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      amount: satAmount,
      memo: "BTC Gamma Strategy Deposit",
    }),
  });

  const { invoice, payment_hash, hyperevm_address, amount } =
    await response.json();

  // Show HyperEVM address
  if (hyperevm_address) {
    document.getElementById("hyperevmAddress").textContent = hyperevm_address;
    document.getElementById("addressCard").style.display = "block";
    // Store for later use
    window.currentHyperEvmAddress = hyperevm_address;
    window.currentDepositAmount = amount;
  }

  showLoading("⚡ Please pay the Lightning invoice...");

  // Pay with WebLN
  const payment = await webln.sendPayment(invoice);

  if (!payment.preimage) {
    throw new Error("Payment failed - no preimage received");
  }

  // Verify payment with backend
  await fetch(`${CONFIG.API_URL}/api/verify-payment`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      payment_hash,
      preimage: payment.preimage,
    }),
  });

  updateStepStatus(1, "completed");
  return { payment, payment_hash };
}

// Step 2: Bridge to HyperEVM
async function executeStep2(paymentHash) {
  updateStepStatus(2, "active");
  showLoading(
    "🌉 Bridging to HyperEVM...<br><small style='margin-top: 8px; display: block; color: #666;'>Minting LSAT tokens (1:1 ratio)</small>"
  );

  // Request backend to create LSAT tokens on HyperEVM
  const response = await fetch(`${CONFIG.API_URL}/api/bridge-to-hyperevm`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      payment_hash: paymentHash,
    }),
  });

  const { hyperevmAddress, lsatAmount, txHash } = await response.json();
  userAddress = hyperevmAddress;

  // Wait for confirmation
  await waitForTransaction(txHash);

  updateStepStatus(2, "completed");
  return { hyperevmAddress, lsatAmount };
}

// Step 3: Swap to uBTC
async function executeStep3(paymentHash) {
  updateStepStatus(3, "active");
  showLoading(
    '🔄 Swapping LSAT → uBTC on DEX... <br><small style="margin-top: 8px; display: block;"><a href="https://hypurrscan.io/address/0x20000000000000000000000000000000000000c5" target="_blank" style="color: #667eea; text-decoration: underline;">📊 View LSAT Token on HypurrScan ↗</a></small>'
  );

  // Backend swaps LSAT to uBTC using DEX
  const response = await fetch(`${CONFIG.API_URL}/api/swap-to-ubtc`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      payment_hash: paymentHash,
    }),
  });

  const { ubtcAmount, txHash } = await response.json();

  await waitForTransaction(txHash);

  updateStepStatus(3, "completed");
  return ubtcAmount;
}

// Step 4: Deposit to Vault
async function executeStep4(paymentHash) {
  updateStepStatus(4, "active");
  showLoading(
    "🏦 Depositing to BtcGammaStrategy Vault...<br><small style='margin-top: 8px; display: block; color: #666;'>Executing leverage loop for enhanced yield</small>"
  );

  // Final deposit into BtcGammaStrategy vault
  const response = await fetch(`${CONFIG.API_URL}/api/deposit-to-vault`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      payment_hash: paymentHash,
    }),
  });

  const { shares, txHash, hyperevmAddress } = await response.json();
  userAddress = hyperevmAddress; // Store for balance lookups

  await waitForTransaction(txHash);

  // Show vault summary
  if (window.currentDepositAmount && shares) {
    document.getElementById("totalDeposited").textContent =
      window.currentDepositAmount;
    document.getElementById("vaultShares").textContent = shares.toFixed(2);
    document.getElementById("vaultSummary").style.display = "block";
  }

  updateStepStatus(4, "completed");
  return shares;
}

// Helper: Wait for transaction confirmation
async function waitForTransaction(txHash) {
  let attempts = 0;
  const maxAttempts = 30;

  while (attempts < maxAttempts) {
    const response = await fetch(`${CONFIG.API_URL}/api/tx-status/${txHash}`);
    const { status } = await response.json();

    if (status === "confirmed") {
      return true;
    } else if (status === "failed") {
      throw new Error("Transaction failed");
    }

    await new Promise((resolve) => setTimeout(resolve, 2000));
    attempts++;
  }

  throw new Error("Transaction timeout");
}

// Update user balance
async function updateUserBalance() {
  try {
    if (!userAddress) return;

    const response = await fetch(
      `${CONFIG.API_URL}/api/user-balance/${userAddress}`
    );
    const { shares, value } = await response.json();

    document.getElementById("userShares").textContent =
      parseFloat(shares).toFixed(4);
    document.getElementById("totalValue").textContent =
      "$" + parseFloat(value).toFixed(2);
  } catch (error) {
    console.error("Failed to update balance:", error);
  }
}

// UI Helper Functions
function updateStepStatus(stepNumber, status) {
  const step = document.getElementById(`step${stepNumber}`);
  step.className = `step ${status}`;
}

function resetSteps() {
  for (let i = 1; i <= 4; i++) {
    updateStepStatus(i, "");
  }
}

function showLoading(text) {
  document.getElementById("loading").classList.add("show");
  document.getElementById("loadingText").innerHTML = text;
  document.getElementById("depositBtn").disabled = true;
}

function hideLoading() {
  document.getElementById("loading").classList.remove("show");
  document.getElementById("depositBtn").disabled = false;
}

function showSuccess(text) {
  const msg = document.getElementById("successMessage");
  document.getElementById("successText").textContent = text;
  msg.classList.add("show");
  setTimeout(() => msg.classList.remove("show"), 5000);
}

function showError(text) {
  const msg = document.getElementById("errorMessage");
  document.getElementById("errorText").textContent = text;
  msg.classList.add("show");
  setTimeout(() => msg.classList.remove("show"), 5000);
}

function hideMessages() {
  document.getElementById("successMessage").classList.remove("show");
  document.getElementById("errorMessage").classList.remove("show");
}

// Auto-update balance every 30 seconds
setInterval(updateUserBalance, 30000);
