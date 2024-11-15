#!/bin/bash

echo "🚀 Setting up BTC Gamma Lightning Client"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "${YELLOW}⚠ Node.js not found. Please install Node.js v18 or newer${NC}"
    exit 1
fi

NODE_VERSION=$(node -v)
echo "${GREEN}✓ Node.js version: $NODE_VERSION${NC}"

# Setup client
echo ""
echo "${BLUE}📦 Setting up client...${NC}"
cd client
if [ ! -d "node_modules" ]; then
    npm install
    echo "${GREEN}✓ Client dependencies installed${NC}"
else
    echo "${GREEN}✓ Client dependencies already installed${NC}"
fi
cd ..

# Setup server
echo ""
echo "${BLUE}📦 Setting up server...${NC}"
cd server

if [ ! -d "node_modules" ]; then
    npm install
    echo "${GREEN}✓ Server dependencies installed${NC}"
else
    echo "${GREEN}✓ Server dependencies already installed${NC}"
fi

# Create .env if it doesn't exist
if [ ! -f ".env" ]; then
    cp env.example .env
    echo "${YELLOW}⚠ Created .env file from env.example${NC}"
    echo "${YELLOW}⚠ Please edit server/.env with your configuration${NC}"
else
    echo "${GREEN}✓ .env file already exists${NC}"
fi

# Create data directory
if [ ! -d "data" ]; then
    mkdir -p data
    echo "${GREEN}✓ Created data directory${NC}"
else
    echo "${GREEN}✓ Data directory already exists${NC}"
fi

cd ..

echo ""
echo "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "${BLUE}Next steps:${NC}"
echo "1. Configure server/.env with your Lightning node and HyperEVM settings"
echo "2. Deploy contracts: forge script script/Deploy.s.sol --broadcast"
echo "3. Update client/app.js with deployed contract addresses"
echo "4. Start server: cd server && npm start"
echo "5. Start client: cd client && npm run dev"
echo ""
echo "${BLUE}Documentation:${NC}"
echo "See README-CLIENT.md for full instructions"

