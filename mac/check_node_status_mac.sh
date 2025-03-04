#!/bin/bash

# Bitcoin Node Status Checker for macOS
# This script provides a simple way to check the status of your Bitcoin node on macOS

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

# Check if bitcoind is running
print_header "Bitcoin Core Service Status"
if pgrep -x "bitcoind" > /dev/null; then
    print_info "Bitcoin Core is running"
else
    print_warning "Bitcoin Core is not running"
    echo "You can start it with: launchctl start org.bitcoin.bitcoind"
    exit 1
fi

# Get blockchain info
print_header "Blockchain Information"
if ! BLOCKCHAIN_INFO=$(bitcoin-cli getblockchaininfo 2>/dev/null); then
    print_error "Failed to get blockchain information. Check if the node is fully started."
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
if [ "$BLOCKS" -eq "$HEADERS" ] && (( $(echo "$SYNC_PERCENTAGE > 99.99" | bc -l) )); then
    print_info "Node is fully synced!"
else
    BLOCKS_REMAINING=$((HEADERS - BLOCKS))
    print_warning "Node is still syncing. $BLOCKS_REMAINING blocks remaining."
fi

# Get network info
print_header "Network Information"
if ! NETWORK_INFO=$(bitcoin-cli getnetworkinfo 2>/dev/null); then
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
if ! MEMPOOL_INFO=$(bitcoin-cli getmempoolinfo 2>/dev/null); then
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
UPTIME=$(bitcoin-cli uptime 2>/dev/null)
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
BITCOIN_DATA_DIR="$USER_HOME/Library/Application Support/Bitcoin"

# Check system resources
print_header "System Resources"

# Check disk space
DISK_USAGE=$(df -h "$BITCOIN_DATA_DIR" | awk 'NR==2 {print $5}')
DISK_AVAIL=$(df -h "$BITCOIN_DATA_DIR" | awk 'NR==2 {print $4}')

echo "Disk usage: $DISK_USAGE (Available: $DISK_AVAIL)"

# Check memory usage
TOTAL_MEM=$(sysctl -n hw.memsize)
TOTAL_MEM_GB=$(echo "scale=2; $TOTAL_MEM / 1024 / 1024 / 1024" | bc)
VM_STATS=$(vm_stat)
PAGE_SIZE=$(sysctl -n hw.pagesize)
FREE_PAGES=$(echo "$VM_STATS" | grep "Pages free" | awk '{print $3}' | tr -d '.')
FREE_MEM=$(echo "scale=2; $FREE_PAGES * $PAGE_SIZE / 1024 / 1024 / 1024" | bc)
USED_MEM=$(echo "scale=2; $TOTAL_MEM_GB - $FREE_MEM" | bc)
MEM_USAGE_PERCENT=$(echo "scale=2; ($USED_MEM / $TOTAL_MEM_GB) * 100" | bc)

echo "Memory usage: ${MEM_USAGE_PERCENT}% (Used: ${USED_MEM} GB, Free: ${FREE_MEM} GB, Total: ${TOTAL_MEM_GB} GB)"

# Check CPU load
CPU_LOAD=$(sysctl -n vm.loadavg | awk '{print $2, $3, $4}')
echo "CPU load (1, 5, 15 min): $CPU_LOAD"

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

echo ""
echo "For more detailed information, use: bitcoin-cli help" 