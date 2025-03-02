#!/bin/bash

# Bitcoin Core Installation and Node Setup Script for macOS
# This script automates the installation of Bitcoin Core and sets up a full node

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

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script with sudo"
    exit 1
fi

# Get the actual user who ran the script with sudo
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER=$SUDO_USER
else
    ACTUAL_USER=$(whoami)
fi

print_message "Installing Bitcoin Core for user: $ACTUAL_USER"

# Get the home directory of the actual user
USER_HOME=$(eval echo ~$ACTUAL_USER)

# Check if Homebrew is installed
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew is not installed. Installing Homebrew..."
        # Install Homebrew as the actual user, not as root
        sudo -u $ACTUAL_USER /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for the current session
        if [[ $(uname -m) == "arm64" ]]; then
            # For Apple Silicon Macs
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            # For Intel Macs
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        
        print_message "Homebrew installed successfully"
    else
        print_message "Homebrew is already installed"
    fi
}

# Install dependencies
install_dependencies() {
    print_message "Installing dependencies..."
    
    # Install dependencies using Homebrew
    sudo -u $ACTUAL_USER brew update
    sudo -u $ACTUAL_USER brew install wget gnupg curl
    
    print_message "Dependencies installed successfully"
}

# Function to get the latest Bitcoin Core version
get_latest_version() {
    print_message "Determining latest Bitcoin Core version..."
    
    # Get the latest release version from the Bitcoin Core website
    LATEST_VERSION=$(curl -s https://bitcoincore.org/en/download/ | grep -o 'Bitcoin Core [0-9]\+\.[0-9]\+\.[0-9]\+' | head -n 1 | cut -d ' ' -f 3)
    
    if [ -z "$LATEST_VERSION" ]; then
        print_error "Failed to determine the latest Bitcoin Core version"
        exit 1
    fi
    
    print_message "Latest Bitcoin Core version: $LATEST_VERSION"
    echo "$LATEST_VERSION"
}

# Function to download and verify Bitcoin Core
download_bitcoin_core() {
    local version=$1
    local arch=$(uname -m)
    
    # Map architecture to Bitcoin Core naming convention
    case $arch in
        x86_64)
            arch="x86_64"
            ;;
        arm64)
            arch="arm64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    
    print_message "Downloading Bitcoin Core $version for macOS ($arch)..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download Bitcoin Core binary
    BITCOIN_FILE="bitcoin-$version-$arch-apple-darwin.tar.gz"
    BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-$version/$BITCOIN_FILE"
    
    wget "$BITCOIN_URL" || {
        print_error "Failed to download Bitcoin Core"
        exit 1
    }
    
    # Download SHA256SUMS and signature
    wget "https://bitcoincore.org/bin/bitcoin-core-$version/SHA256SUMS" || {
        print_error "Failed to download SHA256SUMS"
        exit 1
    }
    
    wget "https://bitcoincore.org/bin/bitcoin-core-$version/SHA256SUMS.asc" || {
        print_error "Failed to download SHA256SUMS.asc"
        exit 1
    }
    
    # Import Bitcoin Core release signing keys
    print_message "Importing Bitcoin Core release signing keys..."
    gpg --keyserver hkps://keys.openpgp.org --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964 || {
        print_warning "Failed to import keys from keys.openpgp.org, trying alternative keyserver..."
        gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964 || {
            print_error "Failed to import Bitcoin Core release signing keys"
            exit 1
        }
    }
    
    # Verify the signature
    print_message "Verifying signature..."
    gpg --verify SHA256SUMS.asc SHA256SUMS || {
        print_error "Signature verification failed"
        exit 1
    }
    
    # Verify the download
    print_message "Verifying download..."
    grep "$BITCOIN_FILE" SHA256SUMS | shasum -a 256 -c || {
        print_error "SHA256 verification failed"
        exit 1
    }
    
    print_message "Verification successful!"
    
    # Extract the archive
    print_message "Extracting Bitcoin Core..."
    tar -xzf "$BITCOIN_FILE"
    
    # Install Bitcoin Core
    print_message "Installing Bitcoin Core..."
    mkdir -p /usr/local/bin
    cp -r "bitcoin-$version/bin/"* /usr/local/bin/
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    print_message "Bitcoin Core $version has been installed successfully!"
}

# Function to create data directory
setup_data_directory() {
    print_message "Setting up Bitcoin data directory..."
    
    # Create data directory
    BITCOIN_DATA_DIR="$USER_HOME/Library/Application Support/Bitcoin"
    if [ ! -d "$BITCOIN_DATA_DIR" ]; then
        mkdir -p "$BITCOIN_DATA_DIR"
        chown -R $ACTUAL_USER:staff "$BITCOIN_DATA_DIR"
        chmod 750 "$BITCOIN_DATA_DIR"
        print_message "Created Bitcoin data directory: $BITCOIN_DATA_DIR"
    else
        print_message "Bitcoin data directory already exists"
    fi
}

# Function to create Bitcoin Core configuration
create_bitcoin_config() {
    print_message "Creating Bitcoin Core configuration..."
    
    BITCOIN_CONF="$BITCOIN_DATA_DIR/bitcoin.conf"
    
    # Create configuration file if it doesn't exist
    if [ ! -f "$BITCOIN_CONF" ]; then
        cat > "$BITCOIN_CONF" << EOF
# Bitcoin Core configuration file

# Network-related settings
server=1
# Run on the test network instead of the real bitcoin network
#testnet=1
# Run a regression test network
#regtest=1

# Maintain a full transaction index (required for txindex=1)
txindex=1

# Accept connections from outside (default: 1 if no -proxy or -connect)
listen=1

# Maximum number of inbound+outbound connections
maxconnections=125

# RPC server settings
rpcuser=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 12)
rpcpassword=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
rpcbind=127.0.0.1
rpcallowip=127.0.0.1

# Reduce storage requirements by only keeping the most recent N MiB of block data
# Uncomment to enable pruning (not recommended for a full node)
#prune=550

# Miscellaneous options
# Set database cache size in megabytes
dbcache=450

# Reduce bandwidth by limiting upload traffic
#maxuploadtarget=5000
EOF
        
        chown $ACTUAL_USER:staff "$BITCOIN_CONF"
        chmod 600 "$BITCOIN_CONF"
        print_message "Created Bitcoin configuration file: $BITCOIN_CONF"
    else
        print_message "Bitcoin configuration file already exists"
    fi
}

# Function to create a launch agent for Bitcoin Core
create_launch_agent() {
    print_message "Creating launch agent for Bitcoin Core..."
    
    LAUNCH_AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
    PLIST_FILE="$LAUNCH_AGENTS_DIR/org.bitcoin.bitcoind.plist"
    
    # Create LaunchAgents directory if it doesn't exist
    if [ ! -d "$LAUNCH_AGENTS_DIR" ]; then
        mkdir -p "$LAUNCH_AGENTS_DIR"
        chown $ACTUAL_USER:staff "$LAUNCH_AGENTS_DIR"
    fi
    
    # Create the plist file
    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.bitcoin.bitcoind</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/bitcoind</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${USER_HOME}/Library/Application Support/Bitcoin/debug.log</string>
    <key>StandardErrorPath</key>
    <string>${USER_HOME}/Library/Application Support/Bitcoin/error.log</string>
    <key>UserName</key>
    <string>${ACTUAL_USER}</string>
    <key>WorkingDirectory</key>
    <string>${USER_HOME}</string>
</dict>
</plist>
EOF
    
    # Set proper ownership and permissions
    chown $ACTUAL_USER:staff "$PLIST_FILE"
    chmod 644 "$PLIST_FILE"
    
    print_message "Created launch agent: $PLIST_FILE"
    
    # Load the launch agent
    sudo -u $ACTUAL_USER launchctl load "$PLIST_FILE"
    
    print_message "Bitcoin Core launch agent has been loaded"
}

# Main execution
main() {
    print_message "Starting Bitcoin Core installation and setup for macOS..."
    
    # Check and install Homebrew
    check_homebrew
    
    # Install dependencies
    install_dependencies
    
    # Get the latest version
    VERSION=$(get_latest_version)
    
    # Download and install Bitcoin Core
    download_bitcoin_core "$VERSION"
    
    # Setup data directory
    setup_data_directory
    
    # Create Bitcoin Core configuration
    create_bitcoin_config
    
    # Create launch agent
    create_launch_agent
    
    print_message "Bitcoin Core installation and setup completed successfully!"
    print_message "Bitcoin Core will start automatically when you log in"
    print_message "You can start it now with: launchctl start org.bitcoin.bitcoind"
    print_message "You can stop it with: launchctl stop org.bitcoin.bitcoind"
    
    # Ask if the user wants to start the service now
    read -p "Do you want to start Bitcoin Core now? (y/n): " START_NOW
    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        sudo -u $ACTUAL_USER launchctl start org.bitcoin.bitcoind
        print_message "Bitcoin Core has been started"
    else
        print_message "You can start Bitcoin Core later with: launchctl start org.bitcoin.bitcoind"
    fi
}

# Run the main function
main 