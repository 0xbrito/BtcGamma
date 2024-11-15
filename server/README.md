# BTC Gamma Server

Backend API for bridging Lightning Network deposits to HyperEVM and the BTC Gamma vault.

## Setup

1. Install dependencies:

```bash
npm install
```

2. Configure environment:

```bash
cp env.example .env
# Edit .env with your settings
```

3. Create data directory:

```bash
mkdir -p data
```

4. Run server:

```bash
npm start
```

## Development

Run with auto-reload:

```bash
npm run dev
```

## Architecture

### Services

- **LightningService**: Handles Lightning node communication (LND)
- **BridgeService**: Manages LSAT minting and DEX swaps on HyperEVM
- **VaultService**: Interacts with BtcGammaStrategy vault contract
- **DatabaseService**: SQLite for deposit tracking

### Flow

1. Create Lightning invoice
2. Monitor payment
3. Mint LSAT tokens on HyperEVM
4. Swap LSAT to uBTC
5. Deposit uBTC to vault
6. Track shares for user

## API Endpoints

See main README-CLIENT.md for full API documentation.
