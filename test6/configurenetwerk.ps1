param (
    [string]$VMName,
    [string]$NetworkTypes
)

# Parse NetworkTypes
$networkTypes = $NetworkTypes | ConvertFrom-Json

# Path to VBoxManage
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# Log functie
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
        [string]$SubnetNetwork
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
                }
            }
            & "$vboxManagePath" modifyvm $VMName --nic1 hostonly --hostonlyadapter1 $adapter
            Log-Message "Configured host-only network for $VMName using adapter $adapter"
        }
        "nat" {
            & "$vboxManagePath" modifyvm $VMName --nic1 nat
            Log-Message "Configured NAT network for $VMName"
        }
        "bridged" {
            $adapter = Get-BridgedNetworkAdapters
            & "$vboxManagePath" modifyvm $VMName --nic1 bridged --bridgeadapter1 $adapter
            Log-Message "Configured bridged network for $VMName using adapter $adapter"
        }
        "natnetwork" {
            & "$vboxManagePath" modifyvm $VMName --nic1 natnetwork --nat-network1 $AdapterName
            Log-Message "Configured NAT Network for $VMName using adapter $AdapterName"
        }
        default {
            throw "Unsupported network type: $NetworkType"
        }
    }
}

# Iterate over the network types and configure each network
foreach ($networkType in $networkTypes) {
    $subnet = $config.EnvironmentVariables.Subnets | Where-Object { $_.Name -eq $networkType.Name }

    if ($subnet) {
        Configure-Network -VMName $VMName -NetworkType $subnet.Type -AdapterName $subnet.AdapterName -SubnetNetwork $subnet.Network
    } else {
        Log-Message "No subnet configuration found for network type $networkType"
    }
}

Log-Message "Script execution completed successfully."
