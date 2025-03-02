# Bitcoin Core Installer Launcher for Windows
# This script launches the appropriate installer based on the OS

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

# Main function
function Main {
    Write-Header "Bitcoin Core Installer Launcher"
    
    # Check if running on Windows
    if ($PSVersionTable.Platform -eq "Unix") {
        Write-Warning "This script is designed for Windows. For Linux or macOS, please use the install.sh script."
        exit
    }
    
    Write-Success "Detected Windows operating system"
    Write-Success "Launching Windows installer..."
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Warning "This script should be run as Administrator"
        Write-Host "Please follow these steps:"
        Write-Host "1. Open PowerShell as Administrator"
        Write-Host "2. Navigate to the windows directory: cd windows"
        Write-Host "3. Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
        Write-Host "4. Run: .\install_bitcoin_core.ps1"
    } else {
        # Navigate to the Windows directory
        Set-Location -Path ".\windows"
        
        # Check if execution policy allows running scripts
        $executionPolicy = Get-ExecutionPolicy
        if ($executionPolicy -eq "Restricted") {
            Write-Warning "PowerShell execution policy is set to Restricted"
            Write-Host "To enable script execution, run:"
            Write-Host "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
            exit
        }
        
        # Launch the installer
        Write-Success "Starting Bitcoin Core installation..."
        & ".\install_bitcoin_core.ps1"
    }
}

# Run the main function
Main