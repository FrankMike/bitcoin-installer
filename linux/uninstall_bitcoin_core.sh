#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Bitcoin Core Uninstallation Script
# This script stops Bitcoin Core service and uninstalls the software

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to display messages
print_message() {
    echo -e "${GREEN}[+] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_error() {
    echo -e "${RED}[-] $1${NC}"
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script as root or with sudo"
    exit 1
fi

# Get the actual user who ran the script with sudo
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER=$SUDO_USER
else
    ACTUAL_USER=$(whoami)
fi

# Get the home directory of the actual user
USER_HOME=$(eval echo ~$ACTUAL_USER)
BITCOIN_DATA_DIR="$USER_HOME/.bitcoin"

print_message "Starting Bitcoin Core uninstallation process..."

# Function to stop Bitcoin Core service
stop_bitcoin_service() {
    print_message "Stopping Bitcoin Core service..."
    
    if command -v systemctl &> /dev/null; then
        if systemctl is-active --quiet bitcoind; then
            systemctl stop bitcoind
            print_message "Bitcoin Core service stopped"
        else
            print_warning "Bitcoin Core service is not running"
        fi
        if systemctl is-enabled --quiet bitcoind; then
            systemctl disable bitcoind
            print_message "Bitcoin Core service disabled"
        fi
    elif command -v service &> /dev/null; then
        service bitcoind stop && print_message "Init service bitcoind stopped" || print_warning "Failed to stop init service"
    else
        print_warning "No service manager detected; please stop bitcoind manually"
    fi
    # Clean up service scripts
    if [ -f "/etc/systemd/system/bitcoind.service" ]; then
        rm -f "/etc/systemd/system/bitcoind.service"
        systemctl daemon-reload
        print_message "Systemd service file removed"
    fi
    if [ -f "/etc/init.d/bitcoind" ]; then
        rm -f "/etc/init.d/bitcoind"
        print_message "Init.d script removed"
    fi
}

# Function to uninstall Bitcoin Core binaries
uninstall_bitcoin_binaries() {
    print_message "Uninstalling Bitcoin Core binaries..."
    
    # List of Bitcoin Core binaries to remove
    BITCOIN_BINARIES=("bitcoind" "bitcoin-cli" "bitcoin-qt" "bitcoin-tx" "bitcoin-wallet" "bitcoin-util")
    
    for binary in "${BITCOIN_BINARIES[@]}"; do
        if [ -f "/usr/local/bin/$binary" ]; then
            rm -f "/usr/local/bin/$binary"
            print_message "Removed $binary"
        fi
    done
    
    print_message "Bitcoin Core binaries uninstalled"
}

# Function to remove blockchain data
remove_blockchain_data() {
    if [ -d "$BITCOIN_DATA_DIR" ]; then
        print_warning "This will delete all Bitcoin Core data including the blockchain, wallet files, and configuration."
        print_warning "This action CANNOT be undone. Make sure you have backups of any important wallet files."
        
        read -p "Are you sure you want to delete all Bitcoin Core data? (yes/no): " CONFIRM
        
        if [[ "$CONFIRM" == "yes" ]]; then
            print_message "Removing Bitcoin Core data directory..."
            rm -rf "$BITCOIN_DATA_DIR"
            print_message "Bitcoin Core data directory removed"
        else
            print_message "Keeping Bitcoin Core data directory"
        fi
    else
        print_warning "Bitcoin Core data directory not found at $BITCOIN_DATA_DIR"
    fi
}

# Usage/help and flags
print_usage() {
    echo "Usage: $(basename "$0") [--yes|-y] [--help|-h]"
    echo "  -y, --yes    skip interactive confirmations"
    echo "  -h, --help   display this help and exit"
}
FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes) FORCE=true; shift;;
        -h|--help) print_usage; exit 0;;
        *) print_error "Unknown option: $1"; print_usage; exit 1;;
    esac
done

# Main execution
main() {
    # Display warning and confirmation
    print_warning "This script will uninstall Bitcoin Core and optionally remove all blockchain data."
    if ! $FORCE; then
        read -r -p "Continue with uninstallation? (yes/no): " CONTINUE
        CONTINUE=${CONTINUE,,}
        case "$CONTINUE" in
            y|yes) ;; 
            *) print_message "Uninstallation cancelled"; exit 0;;
        esac
    fi
    
    # Stop Bitcoin Core service
    stop_bitcoin_service
    
    # Uninstall Bitcoin Core binaries
    uninstall_bitcoin_binaries
    
    # Ask about removing blockchain data
    if $FORCE; then
        REMOVE_DATA=true
    else
        read -r -p "Remove all blockchain data and config? (yes/no): " REMOVE_DATA
        REMOVE_DATA=${REMOVE_DATA,,}
    fi
    case "$REMOVE_DATA" in
        y|yes) remove_blockchain_data;;
        *) print_message "Keeping Bitcoin Core data directory";;
    esac
    
    print_message "Bitcoin Core uninstallation completed!"
    
    # Check if there's any remaining data
    if [ -d "$BITCOIN_DATA_DIR" ] && [[ "$REMOVE_DATA" != "yes" ]]; then
        print_message "Bitcoin Core data is still available at: $BITCOIN_DATA_DIR"
        print_message "You can manually remove it later with: rm -rf $BITCOIN_DATA_DIR"
    fi
}

# Run the main function
main