#!/bin/bash

# Bitcoin Core Installer Launcher
# This script detects the OS and launches the appropriate installer

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

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        print_message "Detected Linux operating system"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="mac"
        print_message "Detected macOS operating system"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        OS="windows"
        print_message "Detected Windows operating system"
    else
        print_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
}

# Main function
main() {
    print_message "Bitcoin Core Installer Launcher"
    detect_os

    case $OS in
        linux)
            print_message "Launching Linux installer..."
            cd linux
            chmod +x install_bitcoin_core.sh
            echo "To install Bitcoin Core, run: sudo ./install_bitcoin_core.sh"
            ;;
        mac)
            print_message "Launching macOS installer..."
            cd mac
            chmod +x install_bitcoin_core_mac.sh
            echo "To install Bitcoin Core, run: sudo ./install_bitcoin_core_mac.sh"
            ;;
        windows)
            print_message "For Windows installation:"
            echo "1. Open PowerShell as Administrator"
            echo "2. Navigate to the windows directory: cd windows"
            echo "3. Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
            echo "4. Run: ./install_bitcoin_core.ps1"
            ;;
    esac
}

# Run the main function
main