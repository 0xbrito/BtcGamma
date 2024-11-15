/**
 * Configuration for BTC Gamma Lightning Client
 * Update these values after deploying contracts
 */

export const CONFIG = {
  // Backend API
  API_URL: import.meta.env.VITE_API_URL || "http://localhost:3000",

  // HyperEVM
  HYPEREVM_RPC:
    import.meta.env.VITE_HYPEREVM_RPC || "https://rpc.hyperliquid.xyz",
  CHAIN_ID: 998, // HyperEVM chain ID

  // Contract Addresses (update after deployment)
  VAULT_ADDRESS: import.meta.env.VITE_VAULT_ADDRESS || "0x...",
  LSAT_ADDRESS: import.meta.env.VITE_LSAT_ADDRESS || "0x...",
  UBTC_ADDRESS: import.meta.env.VITE_UBTC_ADDRESS || "0x...",

  // Limits
  MIN_DEPOSIT_SATS: 1000,
  MAX_DEPOSIT_SATS: 10000000, // 0.1 BTC

  // Timeouts
  TRANSACTION_TIMEOUT: 60000, // 60 seconds
  POLL_INTERVAL: 2000, // 2 seconds
};

export default CONFIG;
