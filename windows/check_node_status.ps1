# Bitcoin Node Status Checker for Windows
# This script provides a simple way to check the status of your Bitcoin node on Windows
# Supports both standard Bitcoin Core and SV2 Template Provider

# Node type variables
$BITCOIN_CORE_INSTALLED = $false
$BITCOIN_CORE_RUNNING = $false
$SV2_SUPPORT = $false
$SV2_RUNNING = $false
$NODE_TYPE = "core"
$SERVICE_NAME = "BitcoinCore"

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

# Detect node type
function Detect-NodeType {
    Write-Header "Detecting Bitcoin Node Type"
    
    # Check for standard bitcoind
    $bitcoindPath = "C:\Program Files\Bitcoin\daemon\bitcoind.exe"
    if (Test-Path $bitcoindPath) {
        Write-Success "Bitcoin Core is installed"
        $script:BITCOIN_CORE_INSTALLED = $true
    } else {
        Write-Warning "Bitcoin Core is not installed at the expected location"
        $script:BITCOIN_CORE_INSTALLED = $false
    }
    
    # Check for SV2 Template Provider
    if ($script:BITCOIN_CORE_INSTALLED) {
        $helpOutput = & $bitcoindPath -help 2>&1
        if ($helpOutput -match "sv2") {
            Write-Success "SV2 Template Provider support detected"
            $script:SV2_SUPPORT = $true
        } else {
            $script:SV2_SUPPORT = $false
        }
    }
    
    # Check if standard bitcoind service is running
    $bitcoinService = Get-Service -Name "BitcoinCore" -ErrorAction SilentlyContinue
    if ($bitcoinService -and $bitcoinService.Status -eq "Running") {
        Write-Success "Bitcoin Core service is running"
        $script:BITCOIN_CORE_RUNNING = $true
    } else {
        # Check if Bitcoin Core is running as a process
        $bitcoinProcess = Get-Process -Name "bitcoind" -ErrorAction SilentlyContinue
        if ($bitcoinProcess -and -not (Get-Process -Name "bitcoind" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "sv2" })) {
            Write-Success "Bitcoin Core is running as a process"
            $script:BITCOIN_CORE_RUNNING = $true
        } else {
            $script:BITCOIN_CORE_RUNNING = $false
        }
    }
    
    # Check if SV2 bitcoind service is running
    $sv2Service = Get-Service -Name "BitcoinCoreSV2" -ErrorAction SilentlyContinue
    if ($sv2Service -and $sv2Service.Status -eq "Running") {
        Write-Success "Bitcoin SV2 Template Provider service is running"
        $script:SV2_RUNNING = $true
    } else {
        # Check if SV2 is running as a process
        $sv2Process = Get-Process -Name "bitcoind" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "sv2" }
        if ($sv2Process) {
            Write-Success "Bitcoin SV2 Template Provider is running as a process"
            $script:SV2_RUNNING = $true
        } else {
            $script:SV2_RUNNING = $false
        }
    }
    
    # Determine which node to check
    if ($script:SV2_RUNNING) {
        Write-Success "Will check SV2 Template Provider status"
        $script:NODE_TYPE = "sv2"
        $script:SERVICE_NAME = "BitcoinCoreSV2"
    } elseif ($script:BITCOIN_CORE_RUNNING) {
        Write-Success "Will check standard Bitcoin Core status"
        $script:NODE_TYPE = "core"
        $script:SERVICE_NAME = "BitcoinCore"
    } else {
        if ($script:BITCOIN_CORE_INSTALLED) {
            Write-Warning "Bitcoin Core service is not running"
            Write-Host "You can start it with: Start-Service -Name BitcoinCore"
        }
        
        if ($script:SV2_SUPPORT) {
            Write-Warning "Bitcoin SV2 service is not running"
            Write-Host "You can start it with: Start-Service -Name BitcoinCoreSV2"
        }
        
        exit 1
    }
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

# Function to wait for RPC to be ready
function Wait-ForRPC {
    Write-Success "Waiting for Bitcoin RPC interface to be ready..."
    $maxAttempts = 30
    $attempt = 1

    while ($attempt -le $maxAttempts) {
        $result = Invoke-BitcoinCli -Command "getblockchaininfo"
        if ($result) {
            Write-Success "RPC interface is ready"
            return $true
        } else {
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 2
            $attempt++
        }
    }

    Write-Error "Timed out waiting for RPC interface. Check your Bitcoin Core configuration."
    return $false
}

# Check SV2 specific information
function Check-SV2Info {
    if ($script:NODE_TYPE -eq "sv2") {
        Write-Header "SV2 Template Provider Information"
        
        # Bitcoin data directory
        $bitcoinDataDir = Join-Path $env:APPDATA "Bitcoin"
        $bitcoinConf = Join-Path $bitcoinDataDir "bitcoin.conf"
        
        # Check if sv2 is enabled in the config
        if (Test-Path $bitcoinConf) {
            $configContent = Get-Content $bitcoinConf -Raw
            if ($configContent -match "sv2\s*=\s*1") {
                Write-Success "SV2 is enabled in configuration"
                
                # Get SV2 port from config
                $sv2PortMatch = [regex]::Match($configContent, "sv2port\s*=\s*(\d+)")
                if ($sv2PortMatch.Success) {
                    $sv2Port = $sv2PortMatch.Groups[1].Value
                    Write-Host "SV2 Port: $sv2Port"
                } else {
                    $sv2Port = 8442
                    Write-Host "SV2 Port: $sv2Port (default)"
                }
                
                # Get SV2 bind address from config
                $sv2BindMatch = [regex]::Match($configContent, "sv2bind\s*=\s*([^\s]+)")
                if ($sv2BindMatch.Success) {
                    $sv2Bind = $sv2BindMatch.Groups[1].Value
                    Write-Host "SV2 Bind Address: $sv2Bind"
                } else {
                    Write-Host "SV2 Bind Address: 0.0.0.0 (default)"
                }
                
                # Check if SV2 port is open
                try {
                    $tcpClient = New-Object System.Net.Sockets.TcpClient
                    $portOpen = $tcpClient.ConnectAsync("127.0.0.1", $sv2Port).Wait(1000)
                    if ($portOpen) {
                        Write-Success "SV2 port $sv2Port is open and accepting connections"
                    } else {
                        Write-Warning "SV2 port $sv2Port is not responding"
                    }
                    $tcpClient.Close()
                } catch {
                    Write-Warning "SV2 port $sv2Port is not responding"
                }
                
                # Check for SV2 environment variables
                $sv2EnvFile = Join-Path $env:USERPROFILE ".sv2_environment.ps1"
                if (Test-Path $sv2EnvFile) {
                    Write-Success "SV2 environment file found at $sv2EnvFile"
                    
                    # Source the environment file to get variables
                    . $sv2EnvFile
                    
                    if ($TOKEN) {
                        Write-Host "SV2 Token is configured"
                    } else {
                        Write-Warning "SV2 Token is not configured"
                    }
                    
                    if ($TP_ADDRESS) {
                        Write-Host "Template Provider Address: $TP_ADDRESS"
                    } else {
                        Write-Warning "Template Provider Address is not configured"
                    }
                } else {
                    Write-Warning "SV2 environment file not found"
                }
                
                # Try to get SV2 debug information from the log
                $debugLogPath = Join-Path $bitcoinDataDir "debug.log"
                if (Test-Path $debugLogPath) {
                    $sv2LogEntries = Select-String -Path $debugLogPath -Pattern "sv2" -Tail 5
                    if ($sv2LogEntries) {
                        Write-Success "Recent SV2 log entries:"
                        $sv2LogEntries | ForEach-Object { Write-Host $_.Line }
                    }
                }
            } else {
                Write-Warning "SV2 is not enabled in bitcoin.conf"
            }
        } else {
            Write-Warning "Bitcoin configuration file not found at $bitcoinConf"
        }
    }
}

# Main script execution
Detect-NodeType

# Wait for RPC to be ready
if (-not (Wait-ForRPC)) {
    exit 1
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
Write-Host "Networks: $(($networkInfo.networks | ForEach-Object { $_.name }) -join ', ')"

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

# Check SV2 specific info if applicable
Check-SV2Info

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

if ($script:NODE_TYPE -eq "sv2") {
    Write-Success "You are running a Bitcoin SV2 Template Provider node."
    Write-Success "This node can be used for mining with SV2 compatible miners."
}

Write-Host ""
Write-Host "For more detailed information, use: & '$bitcoinCliPath' help" 