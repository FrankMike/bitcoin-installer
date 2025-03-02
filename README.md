# Bitcoin Core Installer

This repository contains scripts to automate the installation, configuration, and monitoring of a Bitcoin Core full node on Linux and Windows systems.

## Features

- Automatically detects your operating system and distribution
- Downloads and installs the latest version of Bitcoin Core
- Verifies the download using cryptographic signatures
- Sets up a proper configuration file
- Creates a service for easy management (systemd on Linux, Windows Service on Windows)
- Supports multiple architectures (x86_64, aarch64 on Linux; 32-bit and 64-bit on Windows)
- Includes status monitoring scripts

## Requirements

### Linux
- A Linux system (Ubuntu, Debian, Fedora, CentOS, Arch, etc.)
- Root or sudo access
- At least 500GB of free disk space (for a full node)
- A reliable internet connection

### Windows
- Windows 7 or later (Windows 10/11 recommended)
- Administrator privileges
- At least 500GB of free disk space (for a full node)
- A reliable internet connection
- PowerShell 5.0 or later

## Installation

1. Clone this repository:

```bash
git clone https://github.com/yourusername/bitcoin-installer.git
cd bitcoin-installer
```

2. Choose the appropriate installation method for your operating system:

### Linux Installation

1. Make the scripts executable:

```bash
chmod +x install_bitcoin_core.sh check_node_status.sh
```

2. Run the installation script with sudo:

```bash
sudo ./install_bitcoin_core.sh
```

3. Follow the prompts during installation.

### Windows Installation

1. Open PowerShell as Administrator

2. Enable script execution if not already enabled:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

3. Run the installation script:

```powershell
.\install_bitcoin_core.ps1
```

4. Follow the prompts during installation.

## Configuration

The scripts create a default configuration file with sensible defaults for running a full node.

### Linux Configuration
Located at `~/.bitcoin/bitcoin.conf`. You can modify this file:

```bash
nano ~/.bitcoin/bitcoin.conf
```

### Windows Configuration
Located at `%APPDATA%\Bitcoin\bitcoin.conf`. You can modify this file:

```powershell
notepad $env:APPDATA\Bitcoin\bitcoin.conf
```

Some important configuration options:

- `txindex=1`: Maintains a full transaction index (useful for blockchain explorers)
- `prune=550`: Uncomment to enable pruning (reduces disk space requirements but limits functionality)
- `dbcache=450`: Database cache size in megabytes (increase for faster initial sync if you have more RAM)
- `maxuploadtarget=5000`: Limits the upload bandwidth (in MiB per day)

## Managing Your Bitcoin Node

### Linux Management

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

### Windows Management

After installation, you can manage your Bitcoin node using Windows Services or PowerShell:

- Start the node:
  ```powershell
  Start-Service -Name BitcoinCore
  ```

- Stop the node:
  ```powershell
  Stop-Service -Name BitcoinCore
  ```

- Check status:
  ```powershell
  Get-Service -Name BitcoinCore
  ```

- You can also manage the service through the Windows Services management console (`services.msc`)

## Monitoring Your Node

The repository includes status monitoring scripts that provide detailed information about your Bitcoin node:

### Linux Monitoring

```bash
./check_node_status.sh
```

### Windows Monitoring

```powershell
.\check_node_status.ps1
```

These scripts display:
- Service status
- Blockchain information (current block, sync progress, size)
- Network information (version, connections)
- Memory pool information
- Node uptime
- System resource usage

## Using Bitcoin Core

Once your node is running, you can interact with it using the bitcoin-cli command:

### Linux

```bash
# Get blockchain information
bitcoin-cli getblockchaininfo

# Or with specific RPC credentials
bitcoin-cli -rpcuser=yourusername -rpcpassword=yourpassword getblockchaininfo
```

### Windows

```powershell
# Get blockchain information
& "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe" getblockchaininfo

# Or with specific RPC credentials
& "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe" -rpcuser=yourusername -rpcpassword=yourpassword getblockchaininfo
```

## Initial Synchronization

The initial blockchain synchronization can take several days to complete depending on your hardware and internet connection. You can monitor the progress with the status scripts.

## Security Considerations

- The bitcoin.conf file has restricted permissions (600 on Linux)
- The service includes basic hardening measures
- Consider setting up a firewall to only allow connections on port 8333

## Troubleshooting

If you encounter issues:

### Linux Troubleshooting

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

### Windows Troubleshooting

1. Check the logs:
   ```powershell
   Get-Content "C:\Program Files\Bitcoin\daemon\bitcoin_error.log"
   ```

2. Verify your configuration:
   ```powershell
   & "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe" -conf="$env:APPDATA\Bitcoin\bitcoin.conf" getnetworkinfo
   ```

3. Ensure you have enough disk space:
   ```powershell
   Get-PSDrive C
   ```

4. Run the status check script for detailed information:
   ```powershell
   .\check_node_status.ps1
   ```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Bitcoin Core developers for their incredible work
- The Bitcoin community for their ongoing support and documentation