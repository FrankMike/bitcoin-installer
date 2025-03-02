# Bitcoin Node Status Checker for Windows
# This script provides a simple way to check the status of your Bitcoin node on Windows

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

# Check if Bitcoin CLI is installed
$bitcoinCliPath = "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe"
if (-not (Test-Path $bitcoinCliPath)) {
    Write-Error "Bitcoin CLI not found at $bitcoinCliPath"
    Write-Warning "Make sure Bitcoin Core is installed correctly"
    exit 1
}

# Function to run bitcoin-cli commands
function Invoke-BitcoinCli {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Arguments
    )
    
    $allArgs = @($Command) + $Arguments
    
    try {
        $result = & $bitcoinCliPath $allArgs 2>&1
        
        # Check if the result is an error
        if ($result -match "error" -or $LASTEXITCODE -ne 0) {
            return $null
        }
        
        return $result
    } catch {
        return $null
    }
}

# Function to parse JSON output
function ConvertFrom-JsonOutput {
    param (
        [Parameter(Mandatory=$true)]
        [string]$JsonString
    )
    
    try {
        $jsonObject = $JsonString | ConvertFrom-Json
        return $jsonObject
    } catch {
        Write-Error "Failed to parse JSON output: $_"
        return $null
    }
}

# Check if Bitcoin Core service is running
Write-Header "Bitcoin Core Service Status"
$bitcoinService = Get-Service -Name "BitcoinCore" -ErrorAction SilentlyContinue

if ($bitcoinService -and $bitcoinService.Status -eq "Running") {
    Write-Success "Bitcoin Core service is running"
} else {
    # Check if Bitcoin Core is running as a process
    $bitcoinProcess = Get-Process -Name "bitcoind" -ErrorAction SilentlyContinue
    
    if ($bitcoinProcess) {
        Write-Success "Bitcoin Core is running as a process"
    } else {
        Write-Warning "Bitcoin Core is not running"
        Write-Host "You can start it with: Start-Service -Name BitcoinCore"
        Write-Host "Or manually run bitcoind.exe"
        exit 1
    }
}

# Get blockchain info
Write-Header "Blockchain Information"
$blockchainInfoJson = Invoke-BitcoinCli -Command "getblockchaininfo"

if (-not $blockchainInfoJson) {
    Write-Error "Failed to get blockchain information. Check if the node is fully started."
    exit 1
}

$blockchainInfo = ConvertFrom-JsonOutput -JsonString $blockchainInfoJson

# Display blockchain information
Write-Host "Chain: $($blockchainInfo.chain)"
Write-Host "Current Block: $($blockchainInfo.blocks)"
Write-Host "Headers: $($blockchainInfo.headers)"
Write-Host "Sync Progress: $([math]::Round($blockchainInfo.verificationprogress * 100, 2))%"
Write-Host "Blockchain Size: $([math]::Round($blockchainInfo.size_on_disk / 1GB, 2)) GB"
Write-Host "Pruned: $($blockchainInfo.pruned)"

# Check if fully synced
if ($blockchainInfo.blocks -eq $blockchainInfo.headers -and $blockchainInfo.verificationprogress -ge 0.9999) {
    Write-Success "Node is fully synced!"
} else {
    $blocksRemaining = $blockchainInfo.headers - $blockchainInfo.blocks
    Write-Warning "Node is still syncing. $blocksRemaining blocks remaining."
}

# Get network info
Write-Header "Network Information"
$networkInfoJson = Invoke-BitcoinCli -Command "getnetworkinfo"

if (-not $networkInfoJson) {
    Write-Error "Failed to get network information"
    exit 1
}

$networkInfo = ConvertFrom-JsonOutput -JsonString $networkInfoJson

# Display network information
Write-Host "Version: $($networkInfo.version)"
Write-Host "User Agent: $($networkInfo.subversion)"
Write-Host "Connections: $($networkInfo.connections)"
Write-Host "Networks: $($networkInfo.networks | ForEach-Object { $_.name }) -join ', '"

# Get memory pool information
Write-Header "Memory Pool Information"
$mempoolInfoJson = Invoke-BitcoinCli -Command "getmempoolinfo"

if (-not $mempoolInfoJson) {
    Write-Error "Failed to get mempool information"
    exit 1
}

$mempoolInfo = ConvertFrom-JsonOutput -JsonString $mempoolInfoJson

# Display mempool information
Write-Host "Transactions in mempool: $($mempoolInfo.size)"
Write-Host "Mempool size: $([math]::Round($mempoolInfo.bytes / 1MB, 2)) MB"

# Get node uptime
Write-Header "Node Uptime"
$uptimeJson = Invoke-BitcoinCli -Command "uptime"

if ($uptimeJson) {
    $uptime = [int]$uptimeJson
    $days = [math]::Floor($uptime / 86400)
    $hours = [math]::Floor(($uptime % 86400) / 3600)
    $minutes = [math]::Floor(($uptime % 3600) / 60)
    
    Write-Host "Node has been running for: $days days, $hours hours, $minutes minutes"
} else {
    Write-Error "Failed to get node uptime"
}

# Check system resources
Write-Header "System Resources"

# Check disk space
$bitcoinDataDir = Join-Path $env:APPDATA "Bitcoin"
$drive = (Get-Item $bitcoinDataDir).PSDrive
$diskSpace = Get-PSDrive -Name $drive.Name

$totalGB = [math]::Round($diskSpace.Used / 1GB + $diskSpace.Free / 1GB, 2)
$usedGB = [math]::Round($diskSpace.Used / 1GB, 2)
$freeGB = [math]::Round($diskSpace.Free / 1GB, 2)
$usedPercent = [math]::Round(($diskSpace.Used / ($diskSpace.Used + $diskSpace.Free)) * 100, 2)

Write-Host "Disk usage: $usedPercent% (Used: $usedGB GB, Free: $freeGB GB, Total: $totalGB GB)"

# Check memory usage
$computerSystem = Get-CimInstance -ClassName Win32_OperatingSystem
$totalMemoryGB = [math]::Round($computerSystem.TotalVisibleMemorySize / 1MB, 2)
$freeMemoryGB = [math]::Round($computerSystem.FreePhysicalMemory / 1MB, 2)
$usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
$memoryUsagePercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)

Write-Host "Memory usage: $memoryUsagePercent% (Used: $usedMemoryGB GB, Free: $freeMemoryGB GB, Total: $totalMemoryGB GB)"

# Check CPU load
$cpuLoad = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
Write-Host "CPU load: $cpuLoad%"

# Summary
Write-Header "Summary"
if ($blockchainInfo.blocks -eq $blockchainInfo.headers -and $blockchainInfo.verificationprogress -ge 0.9999) {
    Write-Success "Your Bitcoin node is fully synced and operational!"
} else {
    Write-Warning "Your Bitcoin node is still syncing. Please be patient."
}

if ($networkInfo.connections -lt 8) {
    Write-Warning "You have few connections ($($networkInfo.connections)). Check your network configuration."
} else {
    Write-Success "You have a healthy number of connections ($($networkInfo.connections))."
}

Write-Host ""
Write-Host "For more detailed information, use: & '$bitcoinCliPath' help" 