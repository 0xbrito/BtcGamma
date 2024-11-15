#!/bin/bash

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "${BLUE}📝 Deploying BTC Gamma Contracts${NC}"
echo ""

# Check if .env exists in root (for Foundry)
if [ ! -f ".env" ]; then
    echo "${RED}✗ .env file not found in root${NC}"
    echo "${YELLOW}Create .env with:${NC}"
    echo "  PRIVATE_KEY=your_private_key"
    echo "  HYPEREVM_RPC_URL=https://rpc.hyperliquid.xyz"
    echo "  UBTC_ADDRESS=0x..."
    echo "  USDXL_ADDRESS=0x..."
    echo "  HYPURRFI_POOL=0x..."
    echo "  SWAP_ROUTER=0x..."
    exit 1
fi

# Source .env
source .env

# Check if private key is set
if [ -z "$PRIVATE_KEY" ]; then
    echo "${RED}✗ PRIVATE_KEY not set in .env${NC}"
    exit 1
fi

echo "${BLUE}Deploying to HyperEVM...${NC}"
echo ""

# Deploy contracts
forge script script/Deploy.s.sol \
    --rpc-url ${HYPEREVM_RPC_URL:-https://rpc.hyperliquid.xyz} \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    -vvvv

if [ $? -eq 0 ]; then
    echo ""
    echo "${GREEN}✅ Contracts deployed successfully!${NC}"
    echo ""
    echo "${YELLOW}Next steps:${NC}"
    echo "1. Copy the contract addresses from the output above"
    echo "2. Update client/app.js CONFIG object"
    echo "3. Update server/.env with contract addresses"
    echo "4. Restart server and client"
else
    echo ""
    echo "${RED}✗ Deployment failed${NC}"
    exit 1
fi

