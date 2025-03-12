#!/bin/bash

# Bitcoin Core Uninstallation Script
# This script stops Bitcoin Core service and uninstalls the software

set -e  # Exit immediately if a command exits with a non-zero status

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
    
    if systemctl is-active --quiet bitcoind; then
        systemctl stop bitcoind
        print_message "Bitcoin Core service stopped"
    else
        print_warning "Bitcoin Core service is not running"
    fi
    
    # Disable the service
    if systemctl is-enabled --quiet bitcoind 2>/dev/null; then
        systemctl disable bitcoind
        print_message "Bitcoin Core service disabled"
    fi
    
    # Remove systemd service file
    if [ -f "/etc/systemd/system/bitcoind.service" ]; then
        rm -f /etc/systemd/system/bitcoind.service
        systemctl daemon-reload
        print_message "Bitcoin Core systemd service file removed"
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

# Main execution
main() {
    # Display warning and confirmation
    print_warning "This script will uninstall Bitcoin Core and optionally remove all blockchain data."
    read -p "Do you want to continue with uninstallation? (yes/no): " CONTINUE
    
    if [[ "$CONTINUE" != "yes" ]]; then
        print_message "Uninstallation cancelled"
        exit 0
    fi
    
    # Stop Bitcoin Core service
    stop_bitcoin_service
    
    # Uninstall Bitcoin Core binaries
    uninstall_bitcoin_binaries
    
    # Ask about removing blockchain data
    read -p "Do you want to remove all blockchain data and configuration? (yes/no): " REMOVE_DATA
    
    if [[ "$REMOVE_DATA" == "yes" ]]; then
        remove_blockchain_data
    else
        print_message "Keeping Bitcoin Core data directory"
    fi
    
    print_message "Bitcoin Core uninstallation completed!"
    
    # Check if there's any remaining data
    if [ -d "$BITCOIN_DATA_DIR" ] && [[ "$REMOVE_DATA" != "yes" ]]; then
        print_message "Bitcoin Core data is still available at: $BITCOIN_DATA_DIR"
        print_message "You can manually remove it later with: rm -rf $BITCOIN_DATA_DIR"
    fi
}

# Run the main function
main 