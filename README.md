# ⚡ BTC Gamma - Lightning to Leveraged BTC Yield

A complete system for depositing Lightning Network sats into a leveraged Bitcoin yield strategy on HyperEVM.

## 🎯 Overview

BTC Gamma allows users to:

1. **Pay with Lightning** - Use any WebLN wallet (Alby, Zeus, etc.)
2. **Bridge to HyperEVM** - Automatic conversion to LSAT tokens
3. **Swap to uBTC** - Decentralized exchange swap
4. **Earn Leveraged Yield** - Deposits into ERC4626 vault with leverage strategy

### Key Features

- ⚡ **Instant Lightning Deposits** - Pay with any Lightning wallet
- 🔐 **Secure Bridging** - Cryptographic proof of Lightning payment
- 🔄 **Automatic Swaps** - LSAT → uBTC via DEX
- 📈 **Leveraged Strategy** - Up to 3x leverage on BTC
- 💎 **ERC4626 Vault** - Standard tokenized vault shares
- 📊 **Real-time Tracking** - Monitor deposits and yields

## 🔄 Architecture Flow

```mermaid
sequenceDiagram
    participant User as 👤 User
    participant WebLN as ⚡ WebLN Wallet
    participant Client as 🌐 Web Client
    participant Backend as 🔧 Backend API
    participant LN as ⚡ Lightning Network
    participant HyperEVM as 🔗 HyperEVM
    participant LSAT as 🪙 LSAT Token<br/>(0x2000...00c5)
    participant DEX as 🔄 DEX
    participant uBTC as ₿ uBTC<br/>(0x2000...00c6)
    participant Vault as 🏦 BtcGammaStrategy

    Note over User,Vault: Step 1: Lightning Payment
    User->>Client: Enter amount & click deposit
    Client->>Backend: POST /api/create-invoice
    Backend->>Backend: Generate HyperEVM address<br/>from Lightning identifier
    Backend->>LN: Create invoice (via NWC/LND)
    LN-->>Backend: Invoice details
    Backend->>Backend: Store deposit record<br/>(payment_hash → hyperevm_address)
    Backend-->>Client: Return invoice
    Client->>WebLN: Request payment
    WebLN->>LN: Pay invoice
    LN-->>WebLN: Payment sent
    WebLN-->>Client: Payment complete

    Note over User,Vault: Step 2: Bridge to HyperEVM
    Client->>Backend: POST /api/verify-payment
    Backend->>LN: Verify payment & preimage
    Backend-->>Client: ✓ Verified
    Client->>Backend: POST /api/bridge-to-hyperevm
    Backend->>Backend: Get user wallet from DB<br/>(by payment_hash)
    Backend->>HyperEVM: Sign & send mint tx
    HyperEVM->>LSAT: mint(userAddress, amount)
    LSAT-->>HyperEVM: LSAT tokens minted
    HyperEVM-->>Backend: Tx confirmed
    Backend-->>Client: ✓ Bridged

    Note over User,Vault: Step 3: Swap to uBTC
    Client->>Backend: POST /api/swap-to-ubtc
    Backend->>Backend: Get deposit details
    Backend->>HyperEVM: Approve LSAT for DEX
    Backend->>DEX: swapExactTokensForTokens<br/>(LSAT → uBTC)
    DEX->>LSAT: transferFrom(user, pool)
    DEX->>uBTC: transfer(user, amount)
    uBTC-->>HyperEVM: uBTC received
    HyperEVM-->>Backend: Swap complete
    Backend-->>Client: ✓ Swapped

    Note over User,Vault: Step 4: Deposit to Vault
    Client->>Backend: POST /api/deposit-to-vault
    Backend->>Backend: Get deposit details
    Backend->>HyperEVM: Approve uBTC for Vault
    Backend->>Vault: deposit(amount, receiver)
    Vault->>uBTC: transferFrom(user, vault)
    Vault->>Vault: Execute leverage loop:<br/>1. Supply uBTC to HypurrFi<br/>2. Borrow USDXL<br/>3. Swap USDXL → uBTC<br/>4. Repeat (2-3x leverage)
    Vault->>Vault: Mint vault shares
    Vault-->>HyperEVM: Shares minted
    HyperEVM-->>Backend: Deposit complete
    Backend-->>Client: ✓ Deposited (shares amount)
    Client-->>User: 🎉 Success! Earning yield

    Note over User,Vault: User's funds are now earning<br/>leveraged BTC yield on HyperEVM!
```

### Contract Addresses (HyperEVM Mainnet)

- **LSAT Token**: [`0x20000000000000000000000000000000000000c5`](https://hypurrscan.io/address/0x20000000000000000000000000000000000000c5)
- **uBTC Token**: `0x20000000000000000000000000000000000000c6`
- **BtcGammaStrategy Vault**: TBD
- **DEX Router**: `0x20000000000000000000000000000000000000c7`

## 🏗️ Project Structure

```
BtcGamma/
├── client/              # Web frontend (Vanilla JS + WebLN)
│   ├── index.html      # UI interface
│   ├── app.js          # WebLN integration & flow logic
│   ├── config.js       # Configuration
│   └── package.json    # Dependencies
│
├── server/             # Backend API (Express + Node.js)
│   ├── index.js        # API server
│   ├── services/       # Core services
│   │   ├── lightning.js    # LND integration
│   │   ├── bridge.js       # HyperEVM bridge
│   │   ├── vault.js        # Vault interactions
│   │   └── database.js     # SQLite storage
│   └── package.json
│
├── src/                # Smart contracts
│   └── BtcGammaStrategy.sol    # ERC4626 vault
│
├── contracts/          # Additional contracts
│   └── LSATToken.sol   # Lightning SAT token (ERC20)
│
├── script/             # Deployment scripts
│   ├── Deploy.s.sol    # Deploy all contracts
│   └── DeployLSAT.s.sol
│
├── test/               # Tests
│   ├── BtcGammaStrategy.t.sol
│   └── LSATToken.t.sol
│
└── scripts/            # Utility scripts
    ├── setup.sh        # Initial setup
    ├── start-dev.sh    # Start dev environment
    └── deploy-contracts.sh
```

## 🚀 Quick Start

### Prerequisites

- Node.js v18+
- Foundry (Solidity toolkit)
- Lightning wallet with WebLN (e.g., Alby)
- (Optional) Lightning node for receiving payments

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd BtcGamma

# Run automated setup
chmod +x scripts/*.sh
./scripts/setup.sh

# Configure environment
cp .env.example .env
# Edit .env with your private key

# Deploy contracts
forge script script/Deploy.s.sol --broadcast

# Update config files with deployed addresses
# Edit: client/config.js and server/.env

# Start development environment
./scripts/start-dev.sh
```

Visit `http://localhost:5173` to use the app!

## 📖 Documentation

- **[SETUP.md](./SETUP.md)** - Detailed setup instructions
- **[README-CLIENT.md](./README-CLIENT.md)** - Client documentation & API reference
- **[server/README.md](./server/README.md)** - Server documentation

## 💡 How It Works

### The Flow

```
┌─────────┐
│  User   │ Enters amount in sats
└────┬────┘
     │
     ▼
┌─────────────────────────────────────┐
│  1. Lightning Payment               │
│  • Backend creates invoice          │
│  • User pays with WebLN wallet      │
│  • Payment verified on Lightning    │
└────┬────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│  2. Bridge to HyperEVM              │
│  • Verify Lightning payment proof   │
│  • Mint LSAT tokens (1:1 ratio)     │
│  • Assign to user's address         │
└────┬────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│  3. Swap LSAT → uBTC                │
│  • Execute DEX swap                 │
│  • Apply slippage protection        │
│  • Receive uBTC                     │
└────┬────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│  4. Deposit to Vault                │
│  • Approve uBTC                     │
│  • Deposit to BtcGammaStrategy      │
│  • Execute leverage loop            │
│  • Receive vault shares             │
└────┬────────────────────────────────┘
     │
     ▼
┌─────────┐
│  Earn   │ Leveraged BTC yield
│  Yield  │
└─────────┘
```

### Smart Contracts

#### BtcGammaStrategy (ERC4626 Vault)

Leveraged yield strategy that:

- Accepts uBTC deposits
- Supplies to HypurrFi lending pool
- Borrows USDXL stablecoins
- Swaps USDXL for more uBTC
- Loops up to 3x leverage
- Returns vault shares to depositors

**Key Features:**

- Target LTV: 60%
- Max LTV: 70%
- Min Health Factor: 1.05
- Loop Count: 3

#### LSATToken (ERC20)

Bridge token representing Lightning sats on HyperEVM:

- 1 LSAT = 1 Lightning satoshi
- Minted when Lightning payment confirmed
- Burned when withdrawing to Lightning
- Bridge operator controls minting

## 🔧 Configuration

### Environment Variables

#### Root `.env` (for Foundry/contracts)

```bash
PRIVATE_KEY=your_deployer_private_key
HYPEREVM_RPC_URL=https://rpc.hyperliquid.xyz
UBTC_ADDRESS=0x...
USDXL_ADDRESS=0x...
HYPURRFI_POOL=0x...
SWAP_ROUTER=0x...
```

#### `server/.env` (for backend API)

```bash
# Server
PORT=3000

# Lightning Node
LND_MACAROON=your_admin_macaroon_hex
LND_SOCKET=localhost:10009
LND_CERT_PATH=/path/to/tls.cert

# HyperEVM
HYPEREVM_RPC_URL=https://rpc.hyperliquid.xyz
HYPEREVM_PRIVATE_KEY=your_private_key

# Contracts
VAULT_CONTRACT_ADDRESS=0x...
LSAT_TOKEN_ADDRESS=0x...
UBTC_TOKEN_ADDRESS=0x...
DEX_ROUTER_ADDRESS=0x...
```

#### `client/config.js`

```javascript
export const CONFIG = {
  API_URL: "http://localhost:3000",
  HYPEREVM_RPC: "https://rpc.hyperliquid.xyz",
  VAULT_ADDRESS: "0x...",
  LSAT_ADDRESS: "0x...",
  UBTC_ADDRESS: "0x...",
};
```

## 🧪 Testing

### Smart Contract Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_Deposit -vvv

# Gas report
forge test --gas-report
```

### Integration Testing

```bash
# Start local development environment
./scripts/start-dev.sh

# In browser, test:
# 1. Connect WebLN wallet
# 2. Small deposit (1000 sats)
# 3. Verify all 4 steps complete
# 4. Check vault shares updated
```

## 📊 Monitoring

### Check Deposits

```bash
# View recent deposits
sqlite3 server/data/deposits.db "SELECT * FROM deposits ORDER BY created_at DESC LIMIT 10"

# Check totals
curl http://localhost:3000/api/user-balance/0x...
```

### Monitor Vault

```bash
# Get vault stats via cast
cast call $VAULT_ADDRESS "totalAssets()(uint256)"
cast call $VAULT_ADDRESS "totalSupply()(uint256)"
```

## 🔒 Security

### Current Implementation (Development)

⚠️ This is a **proof-of-concept** with custodial wallet management.

The server currently:

- Holds user private keys
- Signs transactions on behalf of users
- Suitable for **development/testing only**

### Production Recommendations

For production deployment:

1. **Non-Custodial Flow**

   - Users connect their own wallets (MetaMask, WalletConnect)
   - Users sign their own transactions
   - Backend only coordinates

2. **L402 Protocol**

   - Implement proper L402/LSAT authentication
   - Cryptographic proof of Lightning payment
   - No stored payment proofs

3. **Key Management**

   - Use HSM or cloud KMS
   - Encrypt keys at rest
   - Implement withdrawal authentication

4. **Security Audit**
   - Audit smart contracts
   - Penetration testing
   - Bug bounty program

## 🛠️ Development

### Running Locally

```bash
# Terminal 1: Start server
cd server
npm run dev

# Terminal 2: Start client
cd client
npm run dev

# Terminal 3: Start local blockchain (optional)
anvil
```

### Mock Mode (No Lightning Node)

The server can run without a Lightning node for development:

- Don't configure `LND_MACAROON` in `.env`
- Server will create mock invoices
- Use mock preimage from console logs

### Adding Features

1. **New API Endpoint**: Add to `server/index.js`
2. **New Service**: Create in `server/services/`
3. **Smart Contract**: Add to `src/` or `contracts/`
4. **UI Component**: Modify `client/index.html` and `client/app.js`

## 📈 Roadmap

- [ ] Non-custodial wallet integration
- [ ] L402 authentication protocol
- [ ] Withdrawal functionality
- [ ] Multi-chain support
- [ ] Advanced strategies (different risk levels)
- [ ] Analytics dashboard
- [ ] Mobile app
- [ ] Limit orders for swaps
- [ ] Auto-rebalancing

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

UNLICENSED - For demonstration purposes

## 🙏 Acknowledgments

Built with:

- [@getalby/lightning-tools](https://github.com/getAlby/js-lightning-tools)
- [ethers.js](https://ethers.org/)
- [Foundry](https://getfoundry.sh/)
- [ln-service](https://github.com/alexbosworth/ln-service)
- [Solady](https://github.com/Vectorized/solady)

Inspired by:

- Lightning Network
- ERC4626 Tokenized Vaults
- L402 Protocol
- DeFi leverage strategies

## 📞 Support

- GitHub Issues: For bug reports and feature requests
- Documentation: See SETUP.md and README-CLIENT.md
- Community: [Discord/Telegram link]

---

**⚠️ Disclaimer**: This is experimental software. Use at your own risk. Not audited. Not financial advice.
