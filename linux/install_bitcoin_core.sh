#!/bin/bash

# Bitcoin Core Installation and Node Setup Script
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

print_message "Installing Bitcoin Core for user: $ACTUAL_USER"

# Get the home directory of the actual user
USER_HOME=$(eval echo ~$ACTUAL_USER)

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    print_error "Could not detect Linux distribution"
    exit 1
fi

print_message "Detected Linux distribution: $DISTRO"

# Install dependencies based on distribution
install_dependencies() {
    print_message "Installing dependencies..."
    
    case $DISTRO in
        ubuntu|debian|pop|mint|elementary)
            apt-get update
            apt-get install -y wget gnupg curl software-properties-common apt-transport-https ca-certificates
            ;;
        fedora|centos|rhel)
            dnf install -y wget gnupg curl ca-certificates
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm wget gnupg curl
            ;;
        *)
            print_warning "Unsupported distribution. Installing basic dependencies..."
            if command -v apt-get &> /dev/null; then
                apt-get update
                apt-get install -y wget gnupg curl
            elif command -v dnf &> /dev/null; then
                dnf install -y wget gnupg curl
            elif command -v pacman &> /dev/null; then
                pacman -Sy --noconfirm wget gnupg curl
            else
                print_error "Could not install dependencies. Please install wget, gnupg, and curl manually."
                exit 1
            fi
            ;;
    esac
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
        aarch64|arm64)
            arch="aarch64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    
    print_message "Downloading Bitcoin Core $version for $arch..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download Bitcoin Core binary
    BITCOIN_FILE="bitcoin-$version-$arch-linux-gnu.tar.gz"
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
    grep "$BITCOIN_FILE" SHA256SUMS | sha256sum -c || {
        print_error "SHA256 verification failed"
        exit 1
    }
    
    print_message "Verification successful!"
    
    # Extract the archive
    print_message "Extracting Bitcoin Core..."
    tar -xzf "$BITCOIN_FILE"
    
    # Install Bitcoin Core
    print_message "Installing Bitcoin Core..."
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
    BITCOIN_DATA_DIR="$USER_HOME/.bitcoin"
    if [ ! -d "$BITCOIN_DATA_DIR" ]; then
        mkdir -p "$BITCOIN_DATA_DIR"
        chown -R $ACTUAL_USER:$ACTUAL_USER "$BITCOIN_DATA_DIR"
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
        
        chown $ACTUAL_USER:$ACTUAL_USER "$BITCOIN_CONF"
        chmod 600 "$BITCOIN_CONF"
        print_message "Created Bitcoin configuration file: $BITCOIN_CONF"
    else
        print_message "Bitcoin configuration file already exists"
    fi
}

# Function to create systemd service
create_systemd_service() {
    print_message "Creating systemd service for Bitcoin Core..."
    
    SYSTEMD_SERVICE="/etc/systemd/system/bitcoind.service"
    
    cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Bitcoin Core Daemon
After=network.target

[Service]
User=$ACTUAL_USER
Group=$ACTUAL_USER
Type=forking
ExecStart=/usr/local/bin/bitcoind -daemon
ExecStop=/usr/local/bin/bitcoin-cli stop
Restart=on-failure
TimeoutStartSec=infinity
TimeoutStopSec=600

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF
    
    print_message "Created systemd service: $SYSTEMD_SERVICE"
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable the service to start at boot
    systemctl enable bitcoind.service
    
    print_message "Bitcoin Core service has been enabled to start at boot"
}

# Main execution
main() {
    print_message "Starting Bitcoin Core installation and setup..."
    
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
    
    # Create systemd service
    create_systemd_service
    
    print_message "Bitcoin Core installation and setup completed successfully!"
    print_message "You can start the Bitcoin Core daemon with: sudo systemctl start bitcoind"
    print_message "Check the status with: sudo systemctl status bitcoind"
    print_message "View logs with: sudo journalctl -u bitcoind -f"
    
    # Ask if the user wants to start the service now
    read -p "Do you want to start Bitcoin Core now? (y/n): " START_NOW
    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        systemctl start bitcoind
        print_message "Bitcoin Core has been started"
        systemctl status bitcoind
    else
        print_message "You can start Bitcoin Core later with: sudo systemctl start bitcoind"
    fi
}

# Run the main function
main 