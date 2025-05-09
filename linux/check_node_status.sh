#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Bitcoin Node Status Checker
# This script provides a simple way to check the status of your Bitcoin node
# Supports both standard Bitcoin Core and SV2 Template Provider

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m' # No Color

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

# Check for jq
if ! command -v jq &> /dev/null; then
    print_warning "jq not installed; JSON parsing will use grep/awk"
fi

# Detect node type
detect_node_type() {
    print_header "Detecting Bitcoin Node Type"
    
    # Check for standard bitcoind
    if command -v bitcoind &> /dev/null; then
        print_info "Bitcoin Core is installed"
        BITCOIN_CORE_INSTALLED=true
    else
        print_warning "Bitcoin Core is not installed or not in PATH"
        BITCOIN_CORE_INSTALLED=false
    fi
    
    # Check for SV2 Template Provider
    if bitcoind -help 2>/dev/null | grep -q "sv2"; then
        print_info "SV2 Template Provider support detected"
        SV2_SUPPORT=true
    else
        SV2_SUPPORT=false
    fi
    
    # Check if standard bitcoind service is running
    if systemctl is-active --quiet bitcoind 2>/dev/null; then
        print_info "Bitcoin Core service is running"
        BITCOIN_CORE_RUNNING=true
    else
        BITCOIN_CORE_RUNNING=false
    fi
    
    # Check if SV2 bitcoind service is running
    if systemctl is-active --quiet bitcoind-sv2 2>/dev/null; then
        print_info "Bitcoin SV2 Template Provider service is running"
        SV2_RUNNING=true
    else
        SV2_RUNNING=false
    fi
    
    # Determine which node to check
    if [ "$SV2_RUNNING" = true ]; then
        print_info "Will check SV2 Template Provider status"
        NODE_TYPE="sv2"
        SERVICE_NAME="bitcoind-sv2"
    elif [ "$BITCOIN_CORE_RUNNING" = true ]; then
        print_info "Will check standard Bitcoin Core status"
        NODE_TYPE="core"
        SERVICE_NAME="bitcoind"
    else
        if [ "$BITCOIN_CORE_INSTALLED" = true ]; then
            print_warning "Bitcoin Core service is not running"
            echo "You can start it with: sudo systemctl start bitcoind"
        fi
        
        if [ "$SV2_SUPPORT" = true ]; then
            print_warning "Bitcoin SV2 service is not running"
            echo "You can start it with: sudo systemctl start bitcoind-sv2"
        fi
        
        exit 1
    fi
}

# Get the home directory of the actual user
get_user_home() {
    if [ -n "$SUDO_USER" ]; then
        ACTUAL_USER=$SUDO_USER
        USER_HOME=$(eval echo ~$ACTUAL_USER)
    else
        ACTUAL_USER=$(whoami)
        USER_HOME=$(eval echo ~$ACTUAL_USER)
    fi
}

# Check for bitcoin.conf and get RPC credentials
setup_rpc_connection() {
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
            trap 'rm -f "$TEMP_CONF"' EXIT
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
}

# Wait for RPC to be ready
wait_for_rpc() {
    print_info "Waiting for Bitcoin RPC interface to be ready..."
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
}

# Get blockchain info
check_blockchain_info() {
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
    if [ "$BLOCKS" -eq "$HEADERS" ] && (( $(echo "$SYNC_PERCENTAGE > 99.99" | bc -l) )); then
        print_info "Node is fully synced!"
    else
        BLOCKS_REMAINING=$((HEADERS - BLOCKS))
        print_warning "Node is still syncing. $BLOCKS_REMAINING blocks remaining."
    fi
}

# Get network info
check_network_info() {
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
}

# Get memory pool information
check_mempool_info() {
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
}

# Get node uptime
check_node_uptime() {
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
}

# Check SV2 specific information
check_sv2_info() {
    if [ "$NODE_TYPE" = "sv2" ]; then
        print_header "SV2 Template Provider Information"
        
        # Check if sv2 is enabled in the config
        if grep -q "sv2=1" "$BITCOIN_CONF"; then
            print_info "SV2 is enabled in configuration"
            
            # Get SV2 port from config
            SV2_PORT=$(grep -oP "(?<=sv2port=).*" "$BITCOIN_CONF" 2>/dev/null)
            if [ -n "$SV2_PORT" ]; then
                echo "SV2 Port: $SV2_PORT"
            else
                echo "SV2 Port: 8442 (default)"
                SV2_PORT=8442
            fi
            
            # Get SV2 bind address from config
            SV2_BIND=$(grep -oP "(?<=sv2bind=).*" "$BITCOIN_CONF" 2>/dev/null)
            if [ -n "$SV2_BIND" ]; then
                echo "SV2 Bind Address: $SV2_BIND"
            else
                echo "SV2 Bind Address: 0.0.0.0 (default)"
            fi
            
            # Check if SV2 port is open
            if command -v nc &> /dev/null; then
                if nc -z 127.0.0.1 "$SV2_PORT" &>/dev/null; then
                    print_info "SV2 port $SV2_PORT is open and accepting connections"
                else
                    print_warning "SV2 port $SV2_PORT is not responding"
                fi
            fi
            
            # Check for SV2 environment variables
            SV2_ENV_FILE="$USER_HOME/.sv2_environment"
            if [ -f "$SV2_ENV_FILE" ]; then
                print_info "SV2 environment file found at $SV2_ENV_FILE"
                
                # Source the environment file to get variables
                source "$SV2_ENV_FILE"
                
                if [ -n "$TOKEN" ]; then
                    echo "SV2 Token is configured"
                else
                    print_warning "SV2 Token is not configured"
                fi
                
                if [ -n "$TP_ADDRESS" ]; then
                    echo "Template Provider Address: $TP_ADDRESS"
                else
                    print_warning "Template Provider Address is not configured"
                fi
            else
                print_warning "SV2 environment file not found"
            fi
            
            # Try to get SV2 debug information from the log
            if [ -f "/var/log/syslog" ]; then
                SV2_LOG_ENTRIES=$(grep -i "sv2" /var/log/syslog | tail -n 5)
                if [ -n "$SV2_LOG_ENTRIES" ]; then
                    print_info "Recent SV2 log entries:"
                    echo "$SV2_LOG_ENTRIES"
                fi
            fi
        else
            print_warning "SV2 is not enabled in bitcoin.conf"
        fi
    fi
}

# Check system resources
check_system_resources() {
    print_header "System Resources"
    # Check disk space
    BITCOIN_DATA_DIR="$USER_HOME/.bitcoin"
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
}

# Print summary
print_summary() {
    print_header "Summary"
    if [ "$BLOCKS" -eq "$HEADERS" ] && (( $(echo "$SYNC_PERCENTAGE > 99.99" | bc -l) )); then
        print_info "Your Bitcoin node is fully synced and operational!"
    else
        print_warning "Your Bitcoin node is still syncing. Please be patient."
    fi

    if [ "$CONNECTIONS" -lt 8 ]; then
        print_warning "You have few connections ($CONNECTIONS). Check your network configuration."
    else
        print_info "You have a healthy number of connections ($CONNECTIONS)."
    fi
    
    if [ "$NODE_TYPE" = "sv2" ]; then
        print_info "You are running a Bitcoin SV2 Template Provider node."
        print_info "This node can be used for mining with SV2 compatible miners."
    fi
}

# Main function
main() {
    # Detect node type first
    detect_node_type
    
    # Get user home directory
    get_user_home
    
    # Setup RPC connection
    setup_rpc_connection
    
    # Wait for RPC to be ready
    wait_for_rpc
    
    # Check blockchain info
    check_blockchain_info
    
    # Check network info
    check_network_info
    
    # Check mempool info
    check_mempool_info
    
    # Check node uptime
    check_node_uptime
    
    # Check SV2 specific info if applicable
    check_sv2_info
    
    # Check system resources
    check_system_resources
    
    # Print summary
    print_summary
    
    # Clean up the temporary file when done
    if [ -n "$TEMP_CONF" ] && [ -f "$TEMP_CONF" ]; then
        rm -f "$TEMP_CONF"
    fi

    echo ""
    echo "For more detailed information, use: bitcoin-cli help"
}

# Run the main function
main