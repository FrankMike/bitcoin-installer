#!/bin/bash

# Bitcoin SV2 Template Provider Installation Script
# This script automates the installation of the Bitcoin custom Node as a SV2 Template Provider

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

print_message "Installing Bitcoin SV2 Template Provider for user: $ACTUAL_USER"

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
            apt-get update || {
                print_error "Failed to update package lists"
                exit 1
            }
            DEBIAN_FRONTEND=noninteractive apt-get install -y wget gnupg curl software-properties-common apt-transport-https ca-certificates || {
                print_error "Failed to install dependencies"
                exit 1
            }
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
    
    # Verify dependencies
    for cmd in wget gpg curl; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Required dependency '$cmd' is not installed"
            exit 1
        fi
    done
    
    print_message "Dependencies installed successfully"
}

# Download and install Bitcoin SV2 Template Provider
download_sv2_bitcoin() {
    local version="0.1.14"
    local arch="x86_64"
    
    print_message "Downloading Bitcoin SV2 Template Provider v$version for Linux $arch..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download Bitcoin SV2 binary
    BITCOIN_FILE="bitcoin-sv2-tp-$version-$arch-linux-gnu.tar.gz"
    BITCOIN_URL="https://github.com/Sjors/bitcoin/releases/download/sv2-tp-$version/$BITCOIN_FILE"
    
    wget "$BITCOIN_URL" || {
        print_error "Failed to download Bitcoin SV2 Template Provider"
        exit 1
    }
    
    # Extract the archive
    print_message "Extracting Bitcoin SV2 Template Provider..."
    tar -xzf "$BITCOIN_FILE"
    
    # Install Bitcoin SV2 Template Provider
    print_message "Installing Bitcoin SV2 Template Provider..."
    
    # Determine the directory name after extraction
    EXTRACT_DIR=$(find . -type d -name "bitcoin-*" -o -name "sv2-*" | head -n 1)
    if [ -z "$EXTRACT_DIR" ]; then
        # If no directory found, assume it extracts to a 'bin' directory
        EXTRACT_DIR="."
    fi
    
    # Check if bin directory exists in the extracted folder
    if [ -d "$EXTRACT_DIR/bin" ]; then
        cp -r "$EXTRACT_DIR/bin/"* /usr/local/bin/
    else
        # If no bin directory, copy all executables
        find "$EXTRACT_DIR" -type f -executable -exec cp {} /usr/local/bin/ \;
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    print_message "Bitcoin SV2 Template Provider v$version has been installed successfully!"
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
    print_message "Creating Bitcoin SV2 configuration..."
    
    BITCOIN_CONF="$BITCOIN_DATA_DIR/bitcoin.conf"
    
    # Create configuration file if it doesn't exist
    if [ ! -f "$BITCOIN_CONF" ]; then
        cat > "$BITCOIN_CONF" << EOF
# Bitcoin SV2 Template Provider configuration file

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

# SV2 Template Provider specific settings
sv2=1
sv2port=8442
sv2bind=0.0.0.0
sv2interval=1
sv2feedelta=10000
debug=sv2
loglevel=sv2:trace

# Miscellaneous options
# Set database cache size in megabytes
dbcache=450
EOF
        
        chown $ACTUAL_USER:$ACTUAL_USER "$BITCOIN_CONF"
        chmod 600 "$BITCOIN_CONF"
        print_message "Created Bitcoin configuration file: $BITCOIN_CONF"
    else
        # Check if SV2 configuration is already in the config
        if ! grep -q "sv2=1" "$BITCOIN_CONF"; then
            print_message "Adding SV2 configuration to existing bitcoin.conf"
            cat >> "$BITCOIN_CONF" << EOF

# SV2 Template Provider specific settings
sv2=1
sv2port=8442
sv2bind=0.0.0.0
sv2interval=1
sv2feedelta=10000
debug=sv2
loglevel=sv2:trace
EOF
        else
            print_message "SV2 configuration already exists in bitcoin.conf"
            # Check if we need to add the additional SV2 parameters
            if ! grep -q "sv2port" "$BITCOIN_CONF"; then
                print_message "Adding additional SV2 parameters to bitcoin.conf"
                cat >> "$BITCOIN_CONF" << EOF
sv2port=8442
sv2bind=0.0.0.0
sv2interval=1
sv2feedelta=10000
debug=sv2
loglevel=sv2:trace
EOF
            fi
        fi
    fi
}

# Function to create systemd service
create_systemd_service() {
    print_message "Creating systemd service for Bitcoin SV2..."
    
    SYSTEMD_SERVICE="/etc/systemd/system/bitcoind-sv2.service"
    
    cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Bitcoin SV2 Template Provider Daemon
After=network.target

[Service]
User=$ACTUAL_USER
Group=$ACTUAL_USER
Type=forking
ExecStart=/usr/local/bin/bitcoind -daemon -sv2 -sv2port=8442 -sv2bind=0.0.0.0 -sv2interval=1 -sv2feedelta=10000 -debug=sv2 -loglevel=sv2:trace
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
    systemctl enable bitcoind-sv2.service
    
    print_message "Bitcoin SV2 service has been enabled to start at boot"
}

# Function to set environment variables
setup_environment_variables() {
    print_message "Setting up environment variables for mining..."
    
    # Create a file to store environment variables
    ENV_FILE="$USER_HOME/.sv2_environment"
    
    # Default token for testing
    DEFAULT_TOKEN="oFzg1EUmceEcDuvzT3qt"
    
    # Ask for token or use default
    read -p "Enter your miner TOKEN (press Enter to use default testing token '$DEFAULT_TOKEN'): " TOKEN
    TOKEN=${TOKEN:-$DEFAULT_TOKEN}
    
    # Set TP_ADDRESS based on local installation
    TP_ADDRESS="127.0.0.1:8442"
    
    # Write environment variables to file
    cat > "$ENV_FILE" << EOF
# SV2 Template Provider Environment Variables
export TOKEN="$TOKEN"
export TP_ADDRESS="$TP_ADDRESS"
EOF
    
    # Set proper permissions
    chown $ACTUAL_USER:$ACTUAL_USER "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    
    # Add source command to user's .bashrc if not already there
    if ! grep -q "source $ENV_FILE" "$USER_HOME/.bashrc"; then
        echo -e "\n# Source SV2 environment variables\nif [ -f $ENV_FILE ]; then\n    source $ENV_FILE\nfi" >> "$USER_HOME/.bashrc"
    fi
    
    # Also add to .profile for login shells
    if ! grep -q "source $ENV_FILE" "$USER_HOME/.profile" && [ -f "$USER_HOME/.profile" ]; then
        echo -e "\n# Source SV2 environment variables\nif [ -f $ENV_FILE ]; then\n    source $ENV_FILE\nfi" >> "$USER_HOME/.profile"
    fi
    
    # Source the file for the current session
    source "$ENV_FILE"
    
    print_message "Environment variables have been set:"
    print_message "TOKEN=$TOKEN"
    print_message "TP_ADDRESS=$TP_ADDRESS"
    print_message "These variables will be available in new terminal sessions"
    print_message "To use them in the current session, run: source $ENV_FILE"
}

# Main execution
main() {
    print_message "Starting Bitcoin SV2 Template Provider installation and setup..."
    
    # Install dependencies
    install_dependencies
    
    # Download and install Bitcoin SV2
    download_sv2_bitcoin
    
    # Setup data directory
    setup_data_directory
    
    # Create Bitcoin SV2 configuration
    create_bitcoin_config
    
    # Create systemd service
    create_systemd_service
    
    # Set up environment variables
    setup_environment_variables
    
    print_message "Bitcoin SV2 Template Provider installation and setup completed successfully!"
    print_message "You can start the Bitcoin SV2 daemon with: sudo systemctl start bitcoind-sv2"
    print_message "Check the status with: sudo systemctl status bitcoind-sv2"
    print_message "View logs with: sudo journalctl -u bitcoind-sv2 -f"
    
    print_message "The SV2 Template Provider is configured to:"
    print_message "- Listen for mining requests on port 8442"
    print_message "- Accept connections from any computer (sv2bind=0.0.0.0)"
    print_message "- Send a new mining template every second if no better one appears"
    print_message "- Send a new template if fees increase by at least 10,000 satoshis"
    print_message "- Log detailed SV2 information for debugging"
    
    # Ask if the user wants to start the service now
    read -p "Do you want to start Bitcoin SV2 now? (y/n): " START_NOW
    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        systemctl start bitcoind-sv2
        print_message "Bitcoin SV2 has been started"
        systemctl status bitcoind-sv2
    else
        print_message "You can start Bitcoin SV2 later with: sudo systemctl start bitcoind-sv2"
    fi
    
    print_warning "IMPORTANT: This is a development version of Bitcoin Core with SV2 Template Provider support."
    print_warning "To manually start the node with the same parameters, you can run:"
    print_warning "bitcoind -sv2 -sv2port=8442 -sv2bind=0.0.0.0 -sv2interval=1 -sv2feedelta=10000 -debug=sv2 -loglevel=sv2:trace"
    
    print_message "Environment variables have been set up for mining:"
    print_message "TOKEN - Your unique miner identification token"
    print_message "TP_ADDRESS - The address of your Bitcoin node (127.0.0.1:8442)"
    print_message "These variables will be available in new terminal sessions"
}

# Run the main function
main 