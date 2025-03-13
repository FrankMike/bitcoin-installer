#!/bin/bash

# Bitcoin Core Installation and Node Setup Script for macOS
# This script automates the installation of Bitcoin Core and sets up a full node
# Supports both standard Bitcoin Core and SV2 Template Provider

set -e  # Exit immediately if a command exits with a non-zero status

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Node type selection
NODE_TYPE="standard"

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

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
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

# Get the home directory of the actual user
USER_HOME=$(eval echo ~$ACTUAL_USER)

# Function to select node type
select_node_type() {
    print_header "Bitcoin Node Type Selection"
    echo "Please select the type of Bitcoin node you want to install:"
    echo "1) Standard Bitcoin Core (default)"
    echo "2) Bitcoin SV2 Template Provider (for mining)"
    
    read -p "Enter your choice [1-2]: " node_choice
    
    case $node_choice in
        2)
            NODE_TYPE="sv2"
            print_message "Selected: Bitcoin SV2 Template Provider"
            ;;
        *)
            NODE_TYPE="standard"
            print_message "Selected: Standard Bitcoin Core"
            ;;
    esac
}

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
        print_warning "Failed to get version from website, trying alternative method..."
        # Fallback to GitHub API
        LATEST_VERSION=$(curl -sL --connect-timeout 10 https://api.github.com/repos/bitcoin/bitcoin/releases/latest | grep -o '"tag_name": "v[^"]*"' | cut -d'"' -f4 | tr -d 'v')
    }
    
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
    
    # Define an array of Bitcoin Core release signing keys
    BITCOIN_KEYS=(
        "01EA5486DE18A882D4C2684590C8019E36C2E964"
        "152812300785C96444D3334D17565732E08E5E41" # Andrew Chow
        "E61773CD6E01040E2F1BD78CE7E2984B6289C93A" # Michael Folkson
        "9DEAE0DC7063249FB05474681E4AED62986CD25D" # Wladimir J. van der Laan
        "C388F6961FB972A95678E327F62711DBDCA8AE56" # Kvaciral
        "9D3CC86A72F8494342EA5FD10A41BDC3F4FAFF1C" # Aaron Clauson
        "637DB1E23370F84AFF88CCE03152347D07DA627C" # Hennadii Stepanov
        "F2CFC4ABD0B99D837EEBB7D09B79B45691DB4173" # Sebastian Kung
        "E86AE73439625BBEE306AAE6B66D427F873CB1A3" # Max Edwards
        "F19F5FF2B0589EC341220045BA03F4DBE0C63FB4" # Antoine Poinsot
        "F4FC70F07310028424EFC20A8E4256593F177720" # Christian Gugger
        "A0083660F235A27000CD3C81CE6EC49945C17EA6" # Jon Atack
        "0CCBAAFD76A2ECE2CCD3141DE2FFD5B1D88CA97D" # Marco Falke
        "101598DC823C1B5F9A6624ABA5E0907A0380E6C3" # Pieter Wuille
    )

    # Try multiple keyservers
    KEYSERVERS=("hkps://keys.openpgp.org" "hkps://keyserver.ubuntu.com" "hkps://pgp.mit.edu")

    # Import keys from keyservers
    KEY_IMPORT_SUCCESS=false
    for key in "${BITCOIN_KEYS[@]}"; do
        for server in "${KEYSERVERS[@]}"; do
            if gpg --keyserver "$server" --recv-keys "$key" 2>/dev/null; then
                print_message "Successfully imported key $key"
                KEY_IMPORT_SUCCESS=true
                break
            fi
        done
    done

    if [ "$KEY_IMPORT_SUCCESS" = false ]; then
        print_warning "Could not import keys from keyservers, trying direct download..."
        # Try downloading keys directly from Bitcoin Core website
        curl -sL https://bitcoincore.org/keys/keys.asc | gpg --import
        if [ $? -ne 0 ]; then
            print_error "Failed to import Bitcoin Core release signing keys"
            exit 1
        fi
    }
    
    # Verify the signature
    print_message "Verifying signature..."
    if ! gpg --verify SHA256SUMS.asc SHA256SUMS; then
        print_warning "Signature verification failed"
        exit 1
    fi
    
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

# Function to download and install Bitcoin SV2 Template Provider
download_sv2_bitcoin() {
    local version="0.1.14"
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
    
    print_message "Downloading Bitcoin SV2 Template Provider v$version for macOS ($arch)..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download Bitcoin SV2 binary
    BITCOIN_FILE="bitcoin-sv2-tp-$version-$arch-apple-darwin.tar.gz"
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
        if [ "$NODE_TYPE" = "sv2" ]; then
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
        else
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
        fi
        
        chown $ACTUAL_USER:staff "$BITCOIN_CONF"
        chmod 600 "$BITCOIN_CONF"
        print_message "Created Bitcoin configuration file: $BITCOIN_CONF"
    else
        if [ "$NODE_TYPE" = "sv2" ]; then
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
            fi
        else
            print_message "Bitcoin configuration file already exists"
        fi
    fi
}

# Function to create a launch agent for Bitcoin Core
create_launch_agent() {
    print_message "Creating launch agent for Bitcoin..."
    
    LAUNCH_AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
    
    if [ "$NODE_TYPE" = "sv2" ]; then
        PLIST_FILE="$LAUNCH_AGENTS_DIR/org.bitcoin.bitcoind-sv2.plist"
        SERVICE_NAME="org.bitcoin.bitcoind-sv2"
        DAEMON_ARGS="-daemon -sv2 -sv2port=8442 -sv2bind=0.0.0.0 -sv2interval=1 -sv2feedelta=10000 -debug=sv2 -loglevel=sv2:trace"
    else
        PLIST_FILE="$LAUNCH_AGENTS_DIR/org.bitcoin.bitcoind.plist"
        SERVICE_NAME="org.bitcoin.bitcoind"
        DAEMON_ARGS="-daemon"
    fi
    
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
    <string>$SERVICE_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/bitcoind</string>
EOF

    # Add daemon arguments
    for arg in $DAEMON_ARGS; do
        echo "        <string>$arg</string>" >> "$PLIST_FILE"
    done

    # Complete the plist file
    cat >> "$PLIST_FILE" << EOF
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
    sudo -u $ACTUAL_USER launchctl unload "$PLIST_FILE" 2>/dev/null || true
    sudo -u $ACTUAL_USER launchctl load "$PLIST_FILE"
    
    print_message "Bitcoin launch agent has been loaded"
}

# Function to set environment variables for SV2
setup_environment_variables() {
    if [ "$NODE_TYPE" = "sv2" ]; then
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
        chown $ACTUAL_USER:staff "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        
        # Add source command to user's .zshrc if not already there
        if [ -f "$USER_HOME/.zshrc" ] && ! grep -q "source $ENV_FILE" "$USER_HOME/.zshrc"; then
            echo -e "\n# Source SV2 environment variables\nif [ -f $ENV_FILE ]; then\n    source $ENV_FILE\nfi" >> "$USER_HOME/.zshrc"
        fi
        
        # Also add to .bash_profile for bash users
        if [ -f "$USER_HOME/.bash_profile" ] && ! grep -q "source $ENV_FILE" "$USER_HOME/.bash_profile"; then
            echo -e "\n# Source SV2 environment variables\nif [ -f $ENV_FILE ]; then\n    source $ENV_FILE\nfi" >> "$USER_HOME/.bash_profile"
        fi
        
        print_message "Environment variables have been set:"
        print_message "TOKEN=$TOKEN"
        print_message "TP_ADDRESS=$TP_ADDRESS"
        print_message "These variables will be available in new terminal sessions"
        print_message "To use them in the current session, run: source $ENV_FILE"
    fi
}

# Main execution
main() {
    print_message "Starting Bitcoin installation and setup for macOS..."
    
    # Select node type
    select_node_type
    
    # Check and install Homebrew
    check_homebrew
    
    # Install dependencies
    install_dependencies
    
    if [ "$NODE_TYPE" = "sv2" ]; then
        # Download and install Bitcoin SV2
        download_sv2_bitcoin
        print_message "Installing Bitcoin as SV2 Template Provider..."
    else
        # Get the latest version
        VERSION=$(get_latest_version | tail -n 1)
        
        # Verify we have a clean version number
        if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            print_error "Invalid version format: $VERSION"
            exit 1
        fi
        
        print_message "Using Bitcoin Core version: $VERSION"
        
        # Download and install Bitcoin Core
        download_bitcoin_core "$VERSION"
        print_message "Installing standard Bitcoin Core..."
    fi
    
    # Setup data directory
    setup_data_directory
    
    # Create Bitcoin Core configuration
    create_bitcoin_config
    
    # Create launch agent
    create_launch_agent
    
    # Set up environment variables for SV2 if needed
    setup_environment_variables
    
    if [ "$NODE_TYPE" = "sv2" ]; then
        print_message "Bitcoin SV2 Template Provider installation and setup completed successfully!"
        print_message "Bitcoin SV2 will start automatically when you log in"
        print_message "You can start it now with: launchctl start $SERVICE_NAME"
        print_message "You can stop it with: launchctl stop $SERVICE_NAME"
        
        print_message "The SV2 Template Provider is configured to:"
        print_message "- Listen for mining requests on port 8442"
        print_message "- Accept connections from any computer (sv2bind=0.0.0.0)"
        print_message "- Send a new mining template every second if no better one appears"
        print_message "- Send a new template if fees increase by at least 10,000 satoshis"
        print_message "- Log detailed SV2 information for debugging"
        
        print_warning "IMPORTANT: This is a development version of Bitcoin Core with SV2 Template Provider support."
    else
        print_message "Bitcoin Core installation and setup completed successfully!"
        print_message "Bitcoin Core will start automatically when you log in"
        print_message "You can start it now with: launchctl start org.bitcoin.bitcoind"
        print_message "You can stop it with: launchctl stop org.bitcoin.bitcoind"
    fi
    
    # Ask if the user wants to start the service now
    read -p "Do you want to start Bitcoin now? (y/n): " START_NOW
    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        sudo -u $ACTUAL_USER launchctl start $SERVICE_NAME
        print_message "Bitcoin has been started"
    else
        print_message "You can start Bitcoin later with: launchctl start $SERVICE_NAME"
    fi
}

# Run the main function
main 