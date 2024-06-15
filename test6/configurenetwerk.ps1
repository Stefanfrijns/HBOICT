param (
    [string]$VMName,
    [string]$NetworkType,
    [string]$AdapterName,
    [string]$SubnetNetwork,
    [int]$NicIndex
)

# Validate input parameters
if (-not $VMName -or -not $NetworkType -or -not $AdapterName -or -not $SubnetNetwork -or -not $NicIndex) {
    throw "All parameters must be provided: VMName, NetworkType, AdapterName, SubnetNetwork, NicIndex"
}

# Path to VBoxManage
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$publicFolderPath = "$env:Public\VMNetworkConfigurations"
$networkConfigFile = "$publicFolderPath\NetworkConfig_$VMName.txt"

########## Functions ###########

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
    Log-Message "hostonlyif create output: $output"

    if ($output -match "Interface '(.+)' was successfully created") {
        $adapterName = $matches[1]
        Log-Message "Created host-only adapter $adapterName"
        return $adapterName
    } else {
        throw "Failed to create host-only adapter: $output"
    }
}

# Function to configure IP for host-only adapter
function Configure-HostOnlyAdapterIP {
    param (
        [string]$adapterName,
        [string]$SubnetNetwork
    )

    # Extract network and subnet mask
    if ($SubnetNetwork -match "^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\/(\d{1,2})$") {
        $network = $matches[1]
        $cidr = [int]$matches[2]

        # Convert CIDR to subnet mask
        $subnetMask = [string]::Join('.', (0..3 | ForEach-Object {
            if ($cidr -ge ($_ + 1) * 8) {
                255
            } elseif ($cidr -le $_ * 8) {
                0
            } else {
                256 - [math]::pow(2, 8 - ($cidr % 8))
            }
        }))
    } else {
        throw "Invalid SubnetNetwork format. Expected format is 'x.x.x.x/x'"
    }

    $ipconfigOutput = & "$vboxManagePath" hostonlyif ipconfig $adapterName --ip $network --netmask $subnetMask 2>&1
    Log-Message "hostonlyif ipconfig output: $ipconfigOutput"

    if ($ipconfigOutput -notmatch "successfully configured") {
        throw "Failed to configure IP for adapter ${adapterName}: $ipconfigOutput"
    }
}

# Function to configure network
function Configure-Network {
    param (
        [string]$VMName,
        [string]$NetworkType,
        [string]$AdapterName,
        [string]$SubnetNetwork,
        [int]$NicIndex
    )
    switch ($NetworkType) {
        "host-only" {
            $adapter = Get-HostOnlyNetworkAdapters | Where-Object { $_ -eq $AdapterName }
            if (-not $adapter) {
                Log-Message "No host-only adapters found. Creating one..."
                try {
                    $adapter = Create-HostOnlyAdapter
                    Configure-HostOnlyAdapterIP -adapterName $adapter -SubnetNetwork $SubnetNetwork
                } catch {
                    Log-Message "Failed to create host-only adapter: $($_.Exception.Message)"
                    return  # Continue even if adapter creation fails
                }
            } else {
                $adapter = $AdapterName
            }
            Log-Message "Configuring host-only network for $VMName using adapter $adapter"
            & "$vboxManagePath" modifyvm $VMName --nic$NicIndex hostonly --hostonlyadapter$NicIndex $adapter
        }
        "natnetwork" {
            $natNetName = "NatNetwork_$AdapterName"
            Log-Message "Adding NAT network with name $natNetName and network $SubnetNetwork"
            & "$vboxManagePath" natnetwork add --netname $natNetName --network $SubnetNetwork --dhcp off
            Log-Message "Configuring NAT network for $VMName using network $natNetName"
            & "$vboxManagePath" modifyvm $VMName --nic$NicIndex natnetwork --nat-network$NicIndex $natNetName
        }
        "bridged" {
            $adapter = Get-BridgedNetworkAdapters
            Log-Message "Configuring bridged network for $VMName using adapter $adapter"
            & "$vboxManagePath" modifyvm $VMName --nic$NicIndex bridged --bridgeadapter$NicIndex $adapter
        }
        default {
            throw "Unsupported network type: $NetworkType"
        }
    }
}

# Save network configuration to file
function Save-NetworkConfiguration {
    param (
        [string]$VMName,
        [string]$OriginalAdapterName,
        [string]$ActualAdapterName
    )
    if (-not (Test-Path $publicFolderPath)) {
        New-Item -ItemType Directory -Path $publicFolderPath -Force
    }
    $networkConfig = "VMName: $VMName`nOriginalAdapterName: $OriginalAdapterName`nActualAdapterName: $ActualAdapterName"
    Set-Content -Path $networkConfigFile -Value $networkConfig
    Log-Message "Network configuration saved to $networkConfigFile"
}

########## EXECUTE ###########

# Call the function to configure the network
try {
    Log-Message "Starting network configuration for $VMName with network type $NetworkType"
    $actualAdapterName = ""
    switch ($NetworkType) {
        "host-only" {
            $adapter = Get-HostOnlyNetworkAdapters | Where-Object { $_ -eq $AdapterName }
            if (-not $adapter) {
                Log-Message "No host-only adapters found. Creating one..."
                try {
                    $actualAdapterName = Create-HostOnlyAdapter
                    Configure-HostOnlyAdapterIP -adapterName $actualAdapterName -SubnetNetwork $SubnetNetwork
                } catch {
                    Log-Message "Failed to create host-only adapter: $($_.Exception.Message)"
                    return  # Continue even if adapter creation fails
                }
            } else {
                $actualAdapterName = $AdapterName
                Configure-HostOnlyAdapterIP -adapterName $actualAdapterName -SubnetNetwork $SubnetNetwork
            }
            Log-Message "Configuring host-only network for $VMName using adapter $actualAdapterName"
            & "$vboxManagePath" modifyvm $VMName --nic$NicIndex hostonly --hostonlyadapter$NicIndex $actualAdapterName
        }
        "natnetwork" {
            $natNetName = "NatNetwork_$AdapterName"
            Log-Message "Adding NAT network with name $natNetName and network $SubnetNetwork"
            & "$vboxManagePath" natnetwork add --netname $natNetName --network $SubnetNetwork --dhcp off
            Log-Message "Configuring NAT network for $VMName using network $natNetName"
            & "$vboxManagePath" modifyvm $VMName --nic$NicIndex natnetwork --nat-network$NicIndex $natNetName
        }
        "bridged" {
            $adapter = Get-BridgedNetworkAdapters
            Log-Message "Configuring bridged network for $VMName using adapter $adapter"
            & "$vboxManagePath" modifyvm $VMName --nic$NicIndex bridged --bridgeadapter$NicIndex $adapter
        }
        default {
            throw "Unsupported network type: $NetworkType"
        }
    }

    # Save the network configuration
    Save-NetworkConfiguration -VMName $VMName -OriginalAdapterName $AdapterName -ActualAdapterName $actualAdapterName
    Log-Message "Network configuration completed for $VMName"
}
catch {
    Log-Message "An error occurred: $($_.Exception.Message)"
    # Do not throw to continue execution
}

Log-Message "Script execution completed successfully."
