param (
    [string]$VMName,
    [string]$NetworkType,
    [string]$AdapterName,
    [string]$SubnetNetwork,
    [string]$IPAddress
)

# Validate input parameters
if (-not $VMName -or -not $NetworkType -or -not $AdapterName -or -not $SubnetNetwork -or -not $IPAddress) {
    throw "All parameters must be provided: VMName, NetworkType, AdapterName, SubnetNetwork, IPAddress"
}

# Path to VBoxManage
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

##########Functions###########

$logFilePath = "$env:Public\ConfigureNetwork.log"
function Log-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
}

# Function to get available bridged network adapters
function Get-BridgedNetworkAdapters {
    $adapters = & "$vboxManagePath" list bridgedifs | Select-String -Pattern "Name: " | ForEach-Object { $_.Line.Split(":")[1].Trim() }
    if ($adapters.Count -eq 0) {
        throw "No bridged adapters found."
    }
    return $adapters[0]  # Return the first available adapter
}

# Function to get available host-only network adapters
function Get-HostOnlyNetworkAdapters {
    $adapters = & "$vboxManagePath" list hostonlyifs | Select-String -Pattern "Name: " | ForEach-Object { $_.Line.Split(":")[1].Trim() }
    return $adapters
}

# Function to create a host-only network adapter
function Create-HostOnlyAdapter {
    $output = & "$vboxManagePath" hostonlyif create 2>&1
    if ($output -match "Interface '(\S+)' was successfully created") {
        return $matches[1]
    }
    Log-Message "Failed to create host-only adapter: $output"
    throw "Failed to create host-only adapter."
}

# Function to configure network
function Configure-Network {
    param (
        [string]$VMName,
        [string]$NetworkType,
        [string]$AdapterName,
        [string]$SubnetNetwork,
        [string]$IPAddress
    )
    switch ($NetworkType) {
        "host-only" {
            $adapters = Get-HostOnlyNetworkAdapters
            if ($adapters.Count -eq 0) {
                Log-Message "No host-only adapters found. Creating one..."
                $adapter = Create-HostOnlyAdapter
                Log-Message "Created host-only adapter $adapter"
            } else {
                $adapter = $adapters | Where-Object { $_ -eq $AdapterName }
                if (-not $adapter) {
                    $adapter = Create-HostOnlyAdapter
                    Log-Message "Created host-only adapter $adapter"
                }
            }
            & "$vboxManagePath" modifyvm $VMName --nic1 hostonly --hostonlyadapter1 $adapter
            Log-Message "Configured host-only network for $VMName using adapter $adapter"
            & "$vboxManagePath" hostonlyif ipconfig $adapter --ip $IPAddress --netmask $SubnetNetwork
            Log-Message "Configured IP address $IPAddress and subnet $SubnetNetwork for adapter $adapter"
        }
        "nat" {
            & "$vboxManagePath" modifyvm $VMName --nic1 nat --natnet1 "$SubnetNetwork"
            Log-Message "Configured NAT network for $VMName with subnet $SubnetNetwork"
        }
        "bridged" {
            $adapter = Get-BridgedNetworkAdapters
            & "$vboxManagePath" modifyvm $VMName --nic1 bridged --bridgeadapter1 $adapter
            Log-Message "Configured bridged network for $VMName using adapter $adapter"
        }
        default {
            throw "Unsupported network type: $NetworkType"
        }
    }
}

##########EXECUTE###########

# Call the function to configure the network
try {
    Log-Message "Starting network configuration for $VMName with network type $NetworkType"
    Configure-Network -VMName $VMName -NetworkType $NetworkType -AdapterName $AdapterName -SubnetNetwork $SubnetNetwork -IPAddress $IPAddress
    Log-Message "Network configuration completed for $VMName"
}
catch {
    Log-Message "An error occurred: $($_.Exception.Message)"
    throw
}

Log-Message "Script execution completed successfully."
