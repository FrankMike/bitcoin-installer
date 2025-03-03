#!/bin/bash

# Bitcoin Node Status Checker
# This script provides a simple way to check the status of your Bitcoin node

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display messages
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_info() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

# Check if bitcoind is installed
if ! command -v bitcoind &> /dev/null; then
    print_error "Bitcoin Core is not installed or not in PATH"
    exit 1
fi

# Check if bitcoin-cli is installed
if ! command -v bitcoin-cli &> /dev/null; then
    print_error "bitcoin-cli is not installed or not in PATH"
    exit 1
fi

# Check if bitcoind service is running
print_header "Bitcoin Core Service Status"
if systemctl is-active --quiet bitcoind; then
    print_info "Bitcoin Core service is running"
else
    print_warning "Bitcoin Core service is not running"
    echo "You can start it with: sudo systemctl start bitcoind"
    exit 1
fi

# Get the home directory of the actual user
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER=$SUDO_USER
    USER_HOME=$(eval echo ~$ACTUAL_USER)
else
    ACTUAL_USER=$(whoami)
    USER_HOME=$(eval echo ~$ACTUAL_USER)
fi

# Check for bitcoin.conf and get RPC credentials
BITCOIN_CONF="$USER_HOME/.bitcoin/bitcoin.conf"
if [ -f "$BITCOIN_CONF" ]; then
    print_info "Found Bitcoin configuration at $BITCOIN_CONF"
    
    # Extract RPC credentials
    RPC_USER=$(grep -oP "(?<=rpcuser=).*" "$BITCOIN_CONF" 2>/dev/null)
    RPC_PASSWORD=$(grep -oP "(?<=rpcpassword=).*" "$BITCOIN_CONF" 2>/dev/null)
    
    # Set environment variables for bitcoin-cli
    if [ -n "$RPC_USER" ] && [ -n "$RPC_PASSWORD" ]; then
        export BITCOIND_RPCUSER="$RPC_USER"
        export BITCOIND_RPCPASSWORD="$RPC_PASSWORD"
        print_info "RPC credentials found and set"
        
        # Create a temporary bitcoin.conf for bitcoin-cli
        TEMP_CONF=$(mktemp)
        cat > "$TEMP_CONF" << EOF
rpcuser=$RPC_USER
rpcpassword=$RPC_PASSWORD
rpcconnect=127.0.0.1
EOF
        BITCOIN_CLI_OPTS="-conf=$TEMP_CONF"
        print_info "Created temporary configuration for bitcoin-cli"
    else
        print_warning "RPC credentials not found in bitcoin.conf"
        BITCOIN_CLI_OPTS=""
    fi
else
    print_warning "Bitcoin configuration file not found at $BITCOIN_CONF"
    BITCOIN_CLI_OPTS=""
fi

# Wait for RPC to be ready
print_info "Waiting for Bitcoin Core RPC interface to be ready..."
MAX_ATTEMPTS=30
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    if bitcoin-cli $BITCOIN_CLI_OPTS getblockchaininfo &>/dev/null; then
        print_info "RPC interface is ready"
        break
    else
        echo -n "."
        sleep 2
        ATTEMPT=$((ATTEMPT + 1))
    fi
done

if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
    print_error "Timed out waiting for RPC interface. Check your Bitcoin Core configuration."
    print_info "You can try running this command manually to debug: bitcoin-cli getblockchaininfo"
    print_info "If you're running as a different user, make sure you have the correct permissions."
    exit 1
fi

# Get blockchain info
print_header "Blockchain Information"
if ! BLOCKCHAIN_INFO=$(bitcoin-cli $BITCOIN_CLI_OPTS getblockchaininfo 2>/dev/null); then
    print_error "Failed to get blockchain information. Check if the node is fully started."
    print_info "Try running: bitcoin-cli -rpcwait getblockchaininfo"
    exit 1
fi

# Extract and display relevant information
BLOCKS=$(echo "$BLOCKCHAIN_INFO" | grep -o '"blocks": [0-9]*' | awk '{print $2}' | tr -d ',')
HEADERS=$(echo "$BLOCKCHAIN_INFO" | grep -o '"headers": [0-9]*' | awk '{print $2}' | tr -d ',')
VERIFICATION_PROGRESS=$(echo "$BLOCKCHAIN_INFO" | grep -o '"verificationprogress": [0-9.]*' | awk '{print $2}' | tr -d ',')
CHAIN=$(echo "$BLOCKCHAIN_INFO" | grep -o '"chain": "[^"]*"' | awk '{print $2}' | tr -d '"')
SIZE_ON_DISK=$(echo "$BLOCKCHAIN_INFO" | grep -o '"size_on_disk": [0-9]*' | awk '{print $2}' | tr -d ',')
PRUNED=$(echo "$BLOCKCHAIN_INFO" | grep -o '"pruned": [a-z]*' | awk '{print $2}' | tr -d ',')

# Convert size_on_disk from bytes to GB
SIZE_ON_DISK_GB=$(echo "scale=2; $SIZE_ON_DISK / 1024 / 1024 / 1024" | bc)

# Calculate sync percentage
SYNC_PERCENTAGE=$(echo "scale=2; $VERIFICATION_PROGRESS * 100" | bc)

echo "Chain: $CHAIN"
echo "Current Block: $BLOCKS"
echo "Headers: $HEADERS"
echo "Sync Progress: ${SYNC_PERCENTAGE}%"
echo "Blockchain Size: ${SIZE_ON_DISK_GB} GB"
echo "Pruned: $PRUNED"

# Check if fully synced
if [ "$BLOCKS" -eq "$HEADERS" ] && [ "$SYNC_PERCENTAGE" = "100.00" ]; then
    print_info "Node is fully synced!"
else
    BLOCKS_REMAINING=$((HEADERS - BLOCKS))
    print_warning "Node is still syncing. $BLOCKS_REMAINING blocks remaining."
fi

# Get network info
print_header "Network Information"
if ! NETWORK_INFO=$(bitcoin-cli $BITCOIN_CLI_OPTS getnetworkinfo 2>/dev/null); then
    print_error "Failed to get network information"
    exit 1
fi

# Extract and display relevant information
VERSION=$(echo "$NETWORK_INFO" | grep -o '"version": [0-9]*' | awk '{print $2}' | tr -d ',')
SUBVERSION=$(echo "$NETWORK_INFO" | grep -o '"subversion": "[^"]*"' | awk '{print $2}' | tr -d '"')
CONNECTIONS=$(echo "$NETWORK_INFO" | grep -o '"connections": [0-9]*' | awk '{print $2}' | tr -d ',')
NETWORKS=$(echo "$NETWORK_INFO" | grep -o '"networks": \[.*\]' | grep -o '"name": "[^"]*"' | awk '{print $2}' | tr -d '"' | tr '\n' ', ' | sed 's/,$//')

echo "Version: $VERSION"
echo "User Agent: $SUBVERSION"
echo "Connections: $CONNECTIONS"
echo "Networks: $NETWORKS"

# Get memory pool information
print_header "Memory Pool Information"
if ! MEMPOOL_INFO=$(bitcoin-cli $BITCOIN_CLI_OPTS getmempoolinfo 2>/dev/null); then
    print_error "Failed to get mempool information"
    exit 1
fi

# Extract and display relevant information
MEMPOOL_TRANSACTIONS=$(echo "$MEMPOOL_INFO" | grep -o '"size": [0-9]*' | awk '{print $2}' | tr -d ',')
MEMPOOL_SIZE=$(echo "$MEMPOOL_INFO" | grep -o '"bytes": [0-9]*' | awk '{print $2}' | tr -d ',')
MEMPOOL_SIZE_MB=$(echo "scale=2; $MEMPOOL_SIZE / 1024 / 1024" | bc)

echo "Transactions in mempool: $MEMPOOL_TRANSACTIONS"
echo "Mempool size: ${MEMPOOL_SIZE_MB} MB"

# Get node uptime
print_header "Node Uptime"
UPTIME=$(bitcoin-cli $BITCOIN_CLI_OPTS uptime 2>/dev/null)
if [ -n "$UPTIME" ]; then
    # Convert seconds to days, hours, minutes
    DAYS=$((UPTIME / 86400))
    HOURS=$(((UPTIME % 86400) / 3600))
    MINUTES=$(((UPTIME % 3600) / 60))
    
    echo "Node has been running for: $DAYS days, $HOURS hours, $MINUTES minutes"
else
    print_error "Failed to get node uptime"
fi

# Get the home directory of the current user
USER_HOME=$(eval echo ~$USER)
BITCOIN_DATA_DIR="$USER_HOME/.bitcoin"

# Check system resources
print_header "System Resources"
# Check disk space
DISK_USAGE=$(df -h "$BITCOIN_DATA_DIR" | awk 'NR==2 {print $5}')
DISK_AVAIL=$(df -h "$BITCOIN_DATA_DIR" | awk 'NR==2 {print $4}')

echo "Disk usage: $DISK_USAGE (Available: $DISK_AVAIL)"

# Check memory usage
if command -v free &> /dev/null; then
    MEM_USAGE=$(free -m | awk 'NR==2 {printf "%.1f%%", $3*100/$2}')
    echo "Memory usage: $MEM_USAGE"
fi

# Check CPU load
if [ -f /proc/loadavg ]; then
    CPU_LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    echo "CPU load (1, 5, 15 min): $CPU_LOAD"
fi

print_header "Summary"
if [ "$BLOCKS" -eq "$HEADERS" ] && [ "$SYNC_PERCENTAGE" = "100.00" ]; then
    print_info "Your Bitcoin node is fully synced and operational!"
else
    print_warning "Your Bitcoin node is still syncing. Please be patient."
fi

if [ "$CONNECTIONS" -lt 8 ]; then
    print_warning "You have few connections ($CONNECTIONS). Check your network configuration."
else
    print_info "You have a healthy number of connections ($CONNECTIONS)."
fi

# Clean up the temporary file when done
if [ -n "$TEMP_CONF" ] && [ -f "$TEMP_CONF" ]; then
    rm -f "$TEMP_CONF"
fi

echo ""
echo "For more detailed information, use: bitcoin-cli help" 