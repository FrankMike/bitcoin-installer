# Bitcoin Core Installation and Node Setup Script for Windows
# This script automates the installation of Bitcoin Core and sets up a full node on Windows
# Supports both standard Bitcoin Core and SV2 Template Provider for mining

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

# Function to download and install Bitcoin SV2 Template Provider
function Download-SV2Bitcoin {
    Write-Success "Downloading Bitcoin SV2 Template Provider for Windows..."
    
    # SV2 version and URL
    $version = "0.1.14"
    $arch = "64"
    if ([Environment]::Is64BitOperatingSystem -eq $false) {
        $arch = "32"
    }
    
    $bitcoinFile = "bitcoin-sv2-tp-$version-win$arch-setup.exe"
    $bitcoinUrl = "https://github.com/Sjors/bitcoin/releases/download/sv2-tp-$version/$bitcoinFile"
    $outputFile = Join-Path $tempDir $bitcoinFile
    
    try {
        # Download Bitcoin SV2 installer
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell Script")
        Write-Host "Downloading from: $bitcoinUrl"
        $webClient.DownloadFile($bitcoinUrl, $outputFile)
        
        return $outputFile
    } catch {
        Write-Error "Error downloading Bitcoin SV2 Template Provider: $_"
        Write-Warning "Falling back to standard Bitcoin Core installation"
        return $null
    }
}

# Function to install Bitcoin SV2 Template Provider
function Install-SV2Bitcoin {
    param (
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath
    )
    
    Write-Success "Installing Bitcoin SV2 Template Provider..."
    
    try {
        # Run the installer silently
        $process = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -PassThru -Wait
        
        if ($process.ExitCode -ne 0) {
            Write-Error "Installation failed with exit code $($process.ExitCode)"
            return $false
        }
        
        Write-Success "Bitcoin SV2 Template Provider has been installed successfully!"
        return $true
    } catch {
        Write-Error "Error installing Bitcoin SV2 Template Provider: $_"
        return $false
    }
}

# Function to create Bitcoin SV2 configuration
function Create-SV2Config {
    Write-Success "Creating Bitcoin SV2 configuration..."
    
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
# Bitcoin SV2 Template Provider configuration file

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

# Reduce bandwidth by limiting upload traffic
#maxuploadtarget=5000
"@
        
        Set-Content -Path $bitcoinConf -Value $configContent
        Write-Success "Created Bitcoin SV2 configuration file: $bitcoinConf"
    } else {
        # Check if SV2 configuration is already in the config
        $configContent = Get-Content $bitcoinConf -Raw
        if ($configContent -notmatch "sv2\s*=\s*1") {
            Write-Success "Adding SV2 configuration to existing bitcoin.conf"
            Add-Content -Path $bitcoinConf -Value @"

# SV2 Template Provider specific settings
sv2=1
sv2port=8442
sv2bind=0.0.0.0
sv2interval=1
sv2feedelta=10000
debug=sv2
loglevel=sv2:trace
"@
        } else {
            Write-Success "SV2 configuration already exists in bitcoin.conf"
            # Check if we need to add the additional SV2 parameters
            if ($configContent -notmatch "sv2port") {
                Write-Success "Adding additional SV2 parameters to bitcoin.conf"
                Add-Content -Path $bitcoinConf -Value @"
sv2port=8442
sv2bind=0.0.0.0
sv2interval=1
sv2feedelta=10000
debug=sv2
loglevel=sv2:trace
"@
            }
        }
    }
    
    return $bitcoinDataDir
}

# Function to create Windows service for Bitcoin SV2
function Create-SV2Service {
    Write-Success "Creating Windows service for Bitcoin SV2 Template Provider..."
    
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
            Write-Warning "You'll need to manually start Bitcoin SV2 after installation"
            return $false
        }
    }
    
    # Check if Bitcoin SV2 service already exists
    $serviceExists = Get-Service -Name "BitcoinCoreSV2" -ErrorAction SilentlyContinue
    
    if ($serviceExists) {
        Write-Warning "Bitcoin SV2 service already exists"
    } else {
        # Path to Bitcoin daemon
        $bitcoinPath = "C:\Program Files\Bitcoin\daemon\bitcoind.exe"
        
        if (-not (Test-Path $bitcoinPath)) {
            Write-Error "Bitcoin daemon not found at $bitcoinPath"
            Write-Warning "You'll need to manually start Bitcoin SV2 after installation"
            return $false
        }
        
        # Create service using NSSM
        try {
            & $nssmPath install BitcoinCoreSV2 $bitcoinPath
            & $nssmPath set BitcoinCoreSV2 DisplayName "Bitcoin SV2 Template Provider"
            & $nssmPath set BitcoinCoreSV2 Description "Bitcoin SV2 Template Provider for mining"
            & $nssmPath set BitcoinCoreSV2 AppParameters "-sv2 -sv2port=8442 -sv2bind=0.0.0.0 -sv2interval=1 -sv2feedelta=10000 -debug=sv2 -loglevel=sv2:trace"
            & $nssmPath set BitcoinCoreSV2 Start SERVICE_AUTO_START
            & $nssmPath set BitcoinCoreSV2 AppStdout "C:\Program Files\Bitcoin\daemon\bitcoin_sv2_service.log"
            & $nssmPath set BitcoinCoreSV2 AppStderr "C:\Program Files\Bitcoin\daemon\bitcoin_sv2_error.log"
            & $nssmPath set BitcoinCoreSV2 AppRotateFiles 1
            & $nssmPath set BitcoinCoreSV2 AppRotateBytes 10485760  # 10 MB
            
            Write-Success "Bitcoin SV2 service has been created"
            
            # Start the service
            Start-Service -Name "BitcoinCoreSV2"
            Write-Success "Bitcoin SV2 service has been started"
        } catch {
            Write-Error "Error creating Bitcoin SV2 service: $_"
            Write-Warning "You'll need to manually start Bitcoin SV2 after installation"
            return $false
        }
    }
    
    return $true
}

# Function to set environment variables for SV2 mining
function Setup-SV2Environment {
    Write-Success "Setting up environment variables for SV2 mining..."
    
    # Create a file to store environment variables
    $envFile = Join-Path $env:USERPROFILE ".sv2_environment.ps1"
    
    # Default token for testing
    $defaultToken = "oFzg1EUmceEcDuvzT3qt"
    
    # Ask for token or use default
    Write-Host "Enter your miner TOKEN (press Enter to use default testing token '$defaultToken'): " -NoNewline
    $token = Read-Host
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = $defaultToken
    }
    
    # Set TP_ADDRESS based on local installation
    $tpAddress = "127.0.0.1:8442"
    
    # Write environment variables to file
    $envContent = @"
# SV2 Template Provider Environment Variables
`$TOKEN = "$token"
`$TP_ADDRESS = "$tpAddress"

# Export as environment variables
[Environment]::SetEnvironmentVariable("TOKEN", `$TOKEN, "User")
[Environment]::SetEnvironmentVariable("TP_ADDRESS", `$TP_ADDRESS, "User")

Write-Host "SV2 environment variables set:"
Write-Host "TOKEN=$TOKEN"
Write-Host "TP_ADDRESS=$TP_ADDRESS"
"@
    
    Set-Content -Path $envFile -Value $envContent
    
    # Set environment variables for current session
    $env:TOKEN = $token
    $env:TP_ADDRESS = $tpAddress
    
    # Add to PowerShell profile if it exists
    $profilePath = $PROFILE
    if (Test-Path $profilePath) {
        $profileContent = Get-Content $profilePath -Raw
        if ($profileContent -notmatch "\.sv2_environment\.ps1") {
            Add-Content -Path $profilePath -Value "`n# Source SV2 environment variables`nif (Test-Path `"$envFile`") { . `"$envFile`" }"
            Write-Success "Added SV2 environment to PowerShell profile"
        }
    } else {
        # Create profile if it doesn't exist
        $profileDir = Split-Path $profilePath -Parent
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        Set-Content -Path $profilePath -Value "# PowerShell Profile`n`n# Source SV2 environment variables`nif (Test-Path `"$envFile`") { . `"$envFile`" }"
        Write-Success "Created PowerShell profile with SV2 environment"
    }
    
    Write-Success "Environment variables have been set:"
    Write-Success "TOKEN=$token"
    Write-Success "TP_ADDRESS=$tpAddress"
    Write-Success "These variables will be available in new PowerShell sessions"
}

# Main execution
function Main {
    # Ask user which version to install
    Write-Header "Bitcoin Node Installation for Windows"
    Write-Host "Which Bitcoin node would you like to install?"
    Write-Host "1. Standard Bitcoin Core"
    Write-Host "2. Bitcoin SV2 Template Provider (for mining)"
    
    $choice = Read-Host "Enter your choice (1 or 2)"
    
    if ($choice -eq "2") {
        $installSV2 = $true
        Write-Success "You selected Bitcoin SV2 Template Provider installation"
    } else {
        $installSV2 = $false
        Write-Success "You selected standard Bitcoin Core installation"
    }
    
    if ($installSV2) {
        # Try to download SV2 version
        $installerPath = Download-SV2Bitcoin
        
        if ($installerPath -and (Test-Path $installerPath)) {
            # Install Bitcoin SV2
            $sv2Installed = Install-SV2Bitcoin -InstallerPath $installerPath
            
            if ($sv2Installed) {
                # Create SV2 configuration
                $dataDir = Create-SV2Config
                
                # Create Windows service for SV2
                $serviceCreated = Create-SV2Service
                
                # Set up environment variables for mining
                Setup-SV2Environment
                
                Write-Header "Installation Complete"
                Write-Success "Bitcoin SV2 Template Provider has been installed successfully!"
                Write-Success "Data directory: $dataDir"
                
                if ($serviceCreated) {
                    Write-Success "Bitcoin SV2 is running as a Windows service (BitcoinCoreSV2)"
                    Write-Success "You can manage it from the Services management console or with these commands:"
                    Write-Host "  - Start: Start-Service -Name BitcoinCoreSV2"
                    Write-Host "  - Stop: Stop-Service -Name BitcoinCoreSV2"
                    Write-Host "  - Status: Get-Service -Name BitcoinCoreSV2"
                } else {
                    Write-Warning "Bitcoin SV2 service was not created"
                    Write-Success "You can start Bitcoin SV2 manually with this command:"
                    Write-Host "  & 'C:\Program Files\Bitcoin\daemon\bitcoind.exe' -sv2 -sv2port=8442 -sv2bind=0.0.0.0 -sv2interval=1 -sv2feedelta=10000 -debug=sv2 -loglevel=sv2:trace"
                }
                
                Write-Success "Initial blockchain synchronization will take several days"
                Write-Success "You can monitor the progress using the Bitcoin Core GUI or bitcoin-cli"
                Write-Success "For mining, use the TOKEN and TP_ADDRESS environment variables"
                
                Write-Warning "IMPORTANT: This is a development version of Bitcoin Core with SV2 Template Provider support."
                Write-Warning "To manually start the node with the same parameters, you can run:"
                Write-Warning "& 'C:\Program Files\Bitcoin\daemon\bitcoind.exe' -sv2 -sv2port=8442 -sv2bind=0.0.0.0 -sv2interval=1 -sv2feedelta=10000 -debug=sv2 -loglevel=sv2:trace"
                
                # Clean up
                Remove-Item -Path $tempDir -Recurse -Force
                return
            }
        }
        
        # If SV2 installation failed, fall back to standard installation
        Write-Warning "Failed to install Bitcoin SV2 Template Provider"
        Write-Warning "Falling back to standard Bitcoin Core installation"
    }
    
    # Standard Bitcoin Core installation
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