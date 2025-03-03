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

# Check if script is run with sudo/admin privileges
check_privileges() {
    if [[ "$OS" == "windows" ]]; then
        # For Windows, we'll just warn the user
        print_warning "Make sure you're running this script with administrator privileges"
    else
        # For Linux and macOS
        if [ "$EUID" -ne 0 ]; then
            print_error "This script must be run with sudo or as root"
            exit 1
        fi
    fi
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
    check_privileges

    case $OS in
        linux)
            print_message "Launching Linux installer..."
            cd linux
            chmod +x install_bitcoin_core.sh
            ./install_bitcoin_core.sh
            ;;
        mac)
            print_message "Launching macOS installer..."
            cd mac
            chmod +x install_bitcoin_core_mac.sh
            ./install_bitcoin_core_mac.sh
            ;;
        windows)
            print_message "Launching Windows installer..."
            cd windows
            # Set execution policy temporarily for this process
            powershell -Command "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process; & './install_bitcoin_core.ps1'"
            ;;
    esac
    
    print_message "Installation process completed!"
}

# Run the main function
main