#!/bin/bash

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "${BLUE}🚀 Starting BTC Gamma Development Environment${NC}"
echo ""

# Check if setup has been run
if [ ! -d "client/node_modules" ] || [ ! -d "server/node_modules" ]; then
    echo "${YELLOW}⚠ Dependencies not installed. Running setup...${NC}"
    ./scripts/setup.sh
    echo ""
fi

# Check if .env exists
if [ ! -f "server/.env" ]; then
    echo "${YELLOW}⚠ server/.env not found. Please configure it first.${NC}"
    echo "Run: cp server/env.example server/.env"
    echo "Then edit server/.env with your configuration"
    exit 1
fi

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "${YELLOW}Shutting down...${NC}"
    kill $SERVER_PID 2>/dev/null
    kill $CLIENT_PID 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start server
echo "${BLUE}Starting server...${NC}"
cd server
npm start &
SERVER_PID=$!
cd ..

# Wait a bit for server to start
sleep 3

# Start client
echo "${BLUE}Starting client...${NC}"
cd client
npm run dev &
CLIENT_PID=$!
cd ..

echo ""
echo "${GREEN}✅ Development environment running${NC}"
echo ""
echo "${BLUE}Services:${NC}"
echo "  Client: http://localhost:5173"
echo "  Server: http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop all services"
echo ""

# Wait for processes
wait $SERVER_PID $CLIENT_PID

