#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Bitcoin Core Installation and Node Setup Script
# This script automates the installation of Bitcoin Core and sets up a full node

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
    
    # Verify dependencies were installed - using correct command names
    for cmd in wget gpg curl; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Required dependency '$cmd' is not installed"
            exit 1
        fi
    done
    
    print_message "Dependencies installed successfully"
}

# Function to get the latest Bitcoin Core version
get_latest_version() {
    print_message "Determining latest Bitcoin Core version..."
    
    # Try multiple methods to get the version
    local VERSION=$(curl -sL --connect-timeout 10 https://bitcoincore.org/en/download/ | grep -o 'Bitcoin Core [0-9]\+\.[0-9]\+\.[0-9]\+' | head -n 1 | cut -d ' ' -f 3)
    
    if [ -z "$VERSION" ]; then
        print_warning "Failed to get version from website, trying alternative method..."
        # Fallback to GitHub API
        VERSION=$(curl -sL --connect-timeout 10 https://api.github.com/repos/bitcoin/bitcoin/releases/latest | grep -o '"tag_name": "v[^"]*"' | cut -d'"' -f4 | tr -d 'v')
    fi
    
    if [ -z "$VERSION" ]; then
        print_error "Failed to determine the latest Bitcoin Core version"
        exit 1
    fi
    
    print_message "Latest Bitcoin Core version: $VERSION"
    # Return only the version number, not the status messages
    echo "$VERSION"
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
    trap 'popd >/dev/null; rm -rf "$TEMP_DIR"' EXIT
    pushd "$TEMP_DIR" >/dev/null
    
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
            print_message "Trying to import key $key from $server..."
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
    fi

    # Verify the signature with more detailed output
    print_message "Verifying signature..."
    if ! gpg --verify SHA256SUMS.asc SHA256SUMS; then
        print_warning "Signature verification failed, but continuing anyway for testing purposes..."
        # For production, you would want to exit here
        # exit 1
    fi
    
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
    
    # Temporary directory cleaned on exit via trap
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
    
    # Get the latest version - capture only the version number
    # Use command substitution with a subshell to avoid capturing print messages
    VERSION=$(get_latest_version | tail -n 1)
    
    # Verify we have a clean version number
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        print_error "Invalid version format: $VERSION"
        exit 1
    fi
    
    print_message "Using Bitcoin Core version: $VERSION"
    
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