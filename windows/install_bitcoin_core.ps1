# Bitcoin Core Installation and Node Setup Script for Windows
# This script automates the installation of Bitcoin Core and sets up a full node on Windows

# Ensure script is run with administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator" -ForegroundColor Red
    exit
}

# Function to display messages with colors
function Write-ColorMessage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor = "White"
    )
    
    Write-Host $Message -ForegroundColor $ForegroundColor
}

function Write-Success {
    param ([string]$Message)
    Write-ColorMessage "[+] $Message" -ForegroundColor Green
}

function Write-Warning {
    param ([string]$Message)
    Write-ColorMessage "[!] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param ([string]$Message)
    Write-ColorMessage "[-] $Message" -ForegroundColor Red
}

function Write-Header {
    param ([string]$Message)
    Write-ColorMessage "=== $Message ===" -ForegroundColor Cyan
}

# Create a temporary directory
$tempDir = Join-Path $env:TEMP "BitcoinCore_Install"
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Function to get the latest Bitcoin Core version
function Get-LatestBitcoinVersion {
    Write-Success "Determining latest Bitcoin Core version..."
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell Script")
        $content = $webClient.DownloadString("https://bitcoincore.org/en/download/")
        
        # Extract version using regex
        $versionMatch = [regex]::Match($content, 'Bitcoin Core ([0-9]+\.[0-9]+\.[0-9]+)')
        if ($versionMatch.Success) {
            $version = $versionMatch.Groups[1].Value
            Write-Success "Latest Bitcoin Core version: $version"
            return $version
        } else {
            Write-Error "Failed to determine the latest Bitcoin Core version"
            exit 1
        }
    } catch {
        Write-Error "Error fetching Bitcoin Core version: $_"
        exit 1
    }
}

# Function to download Bitcoin Core
function Download-BitcoinCore {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version
    )
    
    Write-Success "Downloading Bitcoin Core $Version for Windows..."
    
    # Determine system architecture
    $arch = "64"
    if ([Environment]::Is64BitOperatingSystem -eq $false) {
        $arch = "32"
    }
    
    $bitcoinFile = "bitcoin-$Version-win$arch-setup.exe"
    $bitcoinUrl = "https://bitcoincore.org/bin/bitcoin-core-$Version/$bitcoinFile"
    $outputFile = Join-Path $tempDir $bitcoinFile
    
    try {
        # Download Bitcoin Core installer
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell Script")
        Write-Host "Downloading from: $bitcoinUrl"
        $webClient.DownloadFile($bitcoinUrl, $outputFile)
        
        # Download SHA256SUMS and signature
        $shasumsUrl = "https://bitcoincore.org/bin/bitcoin-core-$Version/SHA256SUMS"
        $shasumsFile = Join-Path $tempDir "SHA256SUMS"
        $webClient.DownloadFile($shasumsUrl, $shasumsFile)
        
        $sigUrl = "https://bitcoincore.org/bin/bitcoin-core-$Version/SHA256SUMS.asc"
        $sigFile = Join-Path $tempDir "SHA256SUMS.asc"
        $webClient.DownloadFile($sigUrl, $sigFile)
        
        return $outputFile
    } catch {
        Write-Error "Error downloading Bitcoin Core: $_"
        exit 1
    }
}

# Function to verify the download
function Verify-BitcoinDownload {
    param (
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath,
        
        [Parameter(Mandatory=$true)]
        [string]$ShasumsPath
    )
    
    Write-Success "Verifying download..."
    
    try {
        # Get the filename from the installer path
        $fileName = Split-Path $InstallerPath -Leaf
        
        # Read SHA256SUMS file and find the line for our file
        $shaContent = Get-Content $ShasumsPath
        $expectedHashLine = $shaContent | Where-Object { $_ -match $fileName }
        
        if (-not $expectedHashLine) {
            Write-Error "Could not find hash for $fileName in SHA256SUMS file"
            exit 1
        }
        
        # Extract expected hash
        $expectedHash = ($expectedHashLine -split ' ')[0]
        
        # Calculate actual hash
        $actualHash = (Get-FileHash -Path $InstallerPath -Algorithm SHA256).Hash.ToLower()
        
        # Compare hashes
        if ($actualHash -eq $expectedHash) {
            Write-Success "Verification successful! Hash matches."
            return $true
        } else {
            Write-Error "Hash verification failed!"
            Write-Host "Expected: $expectedHash"
            Write-Host "Actual: $actualHash"
            exit 1
        }
    } catch {
        Write-Error "Error verifying download: $_"
        exit 1
    }
}

# Function to install Bitcoin Core
function Install-BitcoinCore {
    param (
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath
    )
    
    Write-Success "Installing Bitcoin Core..."
    
    try {
        # Run the installer silently
        $process = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -PassThru -Wait
        
        if ($process.ExitCode -ne 0) {
            Write-Error "Installation failed with exit code $($process.ExitCode)"
            exit 1
        }
        
        Write-Success "Bitcoin Core has been installed successfully!"
        return $true
    } catch {
        Write-Error "Error installing Bitcoin Core: $_"
        exit 1
    }
}

# Function to create Bitcoin Core configuration
function Create-BitcoinConfig {
    Write-Success "Creating Bitcoin Core configuration..."
    
    # Determine Bitcoin data directory
    $bitcoinDataDir = Join-Path $env:APPDATA "Bitcoin"
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $bitcoinDataDir)) {
        New-Item -ItemType Directory -Path $bitcoinDataDir | Out-Null
        Write-Success "Created Bitcoin data directory: $bitcoinDataDir"
    } else {
        Write-Success "Bitcoin data directory already exists: $bitcoinDataDir"
    }
    
    $bitcoinConf = Join-Path $bitcoinDataDir "bitcoin.conf"
    
    # Create configuration file if it doesn't exist
    if (-not (Test-Path $bitcoinConf)) {
        # Generate random username and password for RPC
        $rpcUser = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
        $rpcPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})
        
        $configContent = @"
# Bitcoin Core configuration file

# Network-related settings
server=1
# Run on the test network instead of the real bitcoin network
#testnet=1
# Run a regression test network
#regtest=1

# Maintain a full transaction index (required for txindex=1)
txindex=1

# Accept connections from outside
listen=1

# Maximum number of inbound+outbound connections
maxconnections=125

# RPC server settings
rpcuser=$rpcUser
rpcpassword=$rpcPassword
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
"@
        
        Set-Content -Path $bitcoinConf -Value $configContent
        Write-Success "Created Bitcoin configuration file: $bitcoinConf"
    } else {
        Write-Success "Bitcoin configuration file already exists: $bitcoinConf"
    }
    
    return $bitcoinDataDir
}

# Function to create Windows service for Bitcoin Core
function Create-BitcoinService {
    Write-Success "Creating Windows service for Bitcoin Core..."
    
    # Check if NSSM (Non-Sucking Service Manager) is installed
    $nssmPath = "C:\Program Files\nssm\nssm.exe"
    if (-not (Test-Path $nssmPath)) {
        # Download and install NSSM
        Write-Warning "NSSM not found. Downloading and installing..."
        
        $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
        $nssmZip = Join-Path $tempDir "nssm.zip"
        $nssmExtract = Join-Path $tempDir "nssm"
        
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "PowerShell Script")
            $webClient.DownloadFile($nssmUrl, $nssmZip)
            
            # Extract NSSM
            Expand-Archive -Path $nssmZip -DestinationPath $nssmExtract -Force
            
            # Copy NSSM to Program Files
            $nssmBin = if ([Environment]::Is64BitOperatingSystem) {
                Join-Path $nssmExtract "nssm-2.24\win64\nssm.exe"
            } else {
                Join-Path $nssmExtract "nssm-2.24\win32\nssm.exe"
            }
            
            New-Item -ItemType Directory -Path "C:\Program Files\nssm" -Force | Out-Null
            Copy-Item -Path $nssmBin -Destination $nssmPath -Force
            
            Write-Success "NSSM installed successfully"
        } catch {
            Write-Error "Error installing NSSM: $_"
            Write-Warning "You'll need to manually start Bitcoin Core after installation"
            return $false
        }
    }
    
    # Check if Bitcoin service already exists
    $serviceExists = Get-Service -Name "BitcoinCore" -ErrorAction SilentlyContinue
    
    if ($serviceExists) {
        Write-Warning "Bitcoin Core service already exists"
    } else {
        # Path to Bitcoin daemon
        $bitcoinPath = "C:\Program Files\Bitcoin\daemon\bitcoind.exe"
        
        if (-not (Test-Path $bitcoinPath)) {
            Write-Error "Bitcoin daemon not found at $bitcoinPath"
            Write-Warning "You'll need to manually start Bitcoin Core after installation"
            return $false
        }
        
        # Create service using NSSM
        try {
            & $nssmPath install BitcoinCore $bitcoinPath
            & $nssmPath set BitcoinCore DisplayName "Bitcoin Core Node"
            & $nssmPath set BitcoinCore Description "Bitcoin Core full node service"
            & $nssmPath set BitcoinCore Start SERVICE_AUTO_START
            & $nssmPath set BitcoinCore AppStdout "C:\Program Files\Bitcoin\daemon\bitcoin_service.log"
            & $nssmPath set BitcoinCore AppStderr "C:\Program Files\Bitcoin\daemon\bitcoin_error.log"
            & $nssmPath set BitcoinCore AppRotateFiles 1
            & $nssmPath set BitcoinCore AppRotateBytes 10485760  # 10 MB
            
            Write-Success "Bitcoin Core service has been created"
            
            # Start the service
            Start-Service -Name "BitcoinCore"
            Write-Success "Bitcoin Core service has been started"
        } catch {
            Write-Error "Error creating Bitcoin Core service: $_"
            Write-Warning "You'll need to manually start Bitcoin Core after installation"
            return $false
        }
    }
    
    return $true
}

# Main execution
function Main {
    Write-Header "Bitcoin Core Installation for Windows"
    
    # Get the latest version
    $version = Get-LatestBitcoinVersion
    
    # Download Bitcoin Core
    $installerPath = Download-BitcoinCore -Version $version
    
    # Verify the download
    $shasumsPath = Join-Path $tempDir "SHA256SUMS"
    Verify-BitcoinDownload -InstallerPath $installerPath -ShasumsPath $shasumsPath
    
    # Install Bitcoin Core
    Install-BitcoinCore -InstallerPath $installerPath
    
    # Create Bitcoin configuration
    $dataDir = Create-BitcoinConfig
    
    # Create Windows service
    $serviceCreated = Create-BitcoinService
    
    # Clean up
    Remove-Item -Path $tempDir -Recurse -Force
    
    Write-Header "Installation Complete"
    Write-Success "Bitcoin Core $version has been installed successfully!"
    Write-Success "Data directory: $dataDir"
    
    if ($serviceCreated) {
        Write-Success "Bitcoin Core is running as a Windows service (BitcoinCore)"
        Write-Success "You can manage it from the Services management console or with these commands:"
        Write-Host "  - Start: Start-Service -Name BitcoinCore"
        Write-Host "  - Stop: Stop-Service -Name BitcoinCore"
        Write-Host "  - Status: Get-Service -Name BitcoinCore"
    } else {
        Write-Warning "Bitcoin Core service was not created"
        Write-Success "You can start Bitcoin Core manually from the Start Menu"
    }
    
    Write-Success "Initial blockchain synchronization will take several days"
    Write-Success "You can monitor the progress using the Bitcoin Core GUI or bitcoin-cli"
}

# Run the main function
Main 