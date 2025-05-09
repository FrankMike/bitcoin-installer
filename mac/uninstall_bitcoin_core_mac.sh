#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Bitcoin Core Uninstallation Script for macOS
# Usage: $(basename "$0") [-h|--help] [-y|--yes]

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m'

print_header() { echo -e "${BLUE}=== $1 ===${NC}"; }
print_message() { echo -e "${GREEN}[+] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }
print_error() { echo -e "${RED}[-] $1${NC}"; }

print_usage() {
  echo "Usage: $(basename \"$0\") [-h|--help] [-y|--yes]"
}

# Parse options
FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage; exit 0;
      ;;
    -y|--yes)
      FORCE=true; shift;
      ;;
    *)
      print_error "Unknown option: $1"; print_usage; exit 1;
      ;;
  esac
done

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  print_error "Please run this script with sudo or as root"
  exit 1
fi

# Determine actual user and home
if [ -n "${SUDO_USER-}" ]; then
  ACTUAL_USER="$SUDO_USER"
else
  ACTUAL_USER=$(whoami)
fi
USER_HOME=$(eval echo ~${ACTUAL_USER})
DATA_DIR="$USER_HOME/Library/Application Support/Bitcoin"

stop_services() {
  print_header "Stopping Bitcoin Node"
  if pgrep -x bitcoind &> /dev/null; then
    print_message "Killing bitcoind processes"
    pkill bitcoind
  else
    print_warning "No bitcoind processes found"
  fi
  for svc in org.bitcoin.bitcoind org.bitcoin.bitcoind-sv2; do
    if launchctl list | grep -q "$svc"; then
      print_message "Unloading $svc"
      launchctl unload -w "/Library/LaunchDaemons/${svc}.plist" 2>/dev/null || print_warning "Failed to unload $svc"
    fi
  done
}

remove_binaries() {
  print_header "Removing Binaries"
  local bins=(bitcoind bitcoin-cli bitcoin-qt bitcoin-tx bitcoin-wallet bitcoin-util)
  for b in "${bins[@]}"; do
    if [ -f "/usr/local/bin/$b" ]; then
      rm -f "/usr/local/bin/$b"
      print_message "Removed $b"
    fi
  done
  # SV2 binary if present
  if [ -f "/usr/local/bin/bitcoin-sv2-tp" ]; then
    rm -f "/usr/local/bin/bitcoin-sv2-tp"
    print_message "Removed bitcoin-sv2-tp"
  fi
}

remove_data() {
  print_header "Removing Data and Config"
  if [ -d "$DATA_DIR" ]; then
    rm -rf "$DATA_DIR"
    print_message "Removed $DATA_DIR"
  else
    print_warning "Data directory not found: $DATA_DIR"
  fi
}

main() {
  print_header "Bitcoin Core Uninstallation for macOS"
  if ! $FORCE; then
    read -r -p "Proceed with uninstallation? (yes/no): " ans
    case "${ans,,}" in
      y|yes) ;;
      *) print_message "Aborting uninstallation"; exit 0;;
    esac
  fi

  stop_services
  remove_binaries

  if ! $FORCE; then
    read -r -p "Remove blockchain data and configuration? (yes/no): " rem
    case "${rem,,}" in
      y|yes) remove_data;;
      *) print_message "Data left at $DATA_DIR";;
    esac
  else
    remove_data
  fi

  print_header "Uninstallation Complete"
}

main
