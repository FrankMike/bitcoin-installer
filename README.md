# Bitcoin Core Installer

This repository contains scripts to automate the installation, configuration, and monitoring of a Bitcoin Core full node on Linux systems.

## Features

- Automatically detects your Linux distribution
- Downloads and installs the latest version of Bitcoin Core
- Verifies the download using cryptographic signatures
- Sets up a proper configuration file
- Creates a systemd service for easy management
- Supports multiple architectures (x86_64, aarch64)
- Includes a status monitoring script

## Requirements

- A Linux system (Ubuntu, Debian, Fedora, CentOS, Arch, etc.)
- Root or sudo access
- At least 500GB of free disk space (for a full node)
- A reliable internet connection

## Installation

1. Clone this repository:

```bash
git clone https://github.com/yourusername/bitcoin-installer.git
cd bitcoin-installer
```

2. Make the scripts executable:

```bash
chmod +x install_bitcoin_core.sh check_node_status.sh
```

3. Run the installation script with sudo:

```bash
sudo ./install_bitcoin_core.sh
```

4. Follow the prompts during installation.

## Configuration

The script creates a default configuration file at `~/.bitcoin/bitcoin.conf` with sensible defaults for running a full node. You can modify this file to suit your needs:

```bash
nano ~/.bitcoin/bitcoin.conf
```

Some important configuration options:

- `txindex=1`: Maintains a full transaction index (useful for blockchain explorers)
- `prune=550`: Uncomment to enable pruning (reduces disk space requirements but limits functionality)
- `dbcache=450`: Database cache size in megabytes (increase for faster initial sync if you have more RAM)
- `maxuploadtarget=5000`: Limits the upload bandwidth (in MiB per day)

## Managing Your Bitcoin Node

After installation, you can manage your Bitcoin node using systemd:

- Start the node:
  ```bash
  sudo systemctl start bitcoind
  ```

- Stop the node:
  ```bash
  sudo systemctl stop bitcoind
  ```

- Check status:
  ```bash
  sudo systemctl status bitcoind
  ```

- View logs:
  ```bash
  sudo journalctl -u bitcoind -f
  ```

- Enable auto-start at boot:
  ```bash
  sudo systemctl enable bitcoind
  ```

## Monitoring Your Node

The repository includes a status monitoring script that provides detailed information about your Bitcoin node:

```bash
./check_node_status.sh
```

This script displays:
- Service status
- Blockchain information (current block, sync progress, size)
- Network information (version, connections)
- Memory pool information
- Node uptime
- System resource usage

## Using Bitcoin Core

Once your node is running, you can interact with it using the bitcoin-cli command:

```bash
# Get blockchain information
bitcoin-cli getblockchaininfo

# Or with specific RPC credentials
bitcoin-cli -rpcuser=yourusername -rpcpassword=yourpassword getblockchaininfo
```

## Initial Synchronization

The initial blockchain synchronization can take several days to complete depending on your hardware and internet connection. You can monitor the progress with:

```bash
./check_node_status.sh
```

## Security Considerations

- The bitcoin.conf file has restricted permissions (600)
- The systemd service includes basic hardening measures
- Consider setting up a firewall to only allow connections on port 8333

## Troubleshooting

If you encounter issues:

1. Check the logs:
   ```bash
   sudo journalctl -u bitcoind -f
   ```

2. Verify your configuration:
   ```bash
   bitcoin-cli -conf=$HOME/.bitcoin/bitcoin.conf getnetworkinfo
   ```

3. Ensure you have enough disk space:
   ```bash
   df -h
   ```

4. Run the status check script for detailed information:
   ```bash
   ./check_node_status.sh
   ```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Bitcoin Core developers for their incredible work
- The Bitcoin community for their ongoing support and documentation