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

    if ($output -match "Interface '(\S+)' was successfully created") {
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
                $adapter = Create-HostOnlyAdapter
            }
            Log-Message "Configuring host-only network for $VMName using adapter $adapter"
            Configure-HostOnlyAdapterIP -adapterName $adapter -SubnetNetwork $SubnetNetwork
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
        [string]$NetworkType,
        [string]$AdapterName,
        [string]$SubnetNetwork,
        [int]$NicIndex
    )
    if (-not (Test-Path $publicFolderPath)) {
        New-Item -ItemType Directory -Path $publicFolderPath -Force
    }
    $networkConfig = "VMName: $VMName`nNetworkType: $NetworkType`nAdapterName: $AdapterName`nSubnetNetwork: $SubnetNetwork`nNicIndex: $NicIndex"
    Set-Content -Path $networkConfigFile -Value $networkConfig
    Log-Message "Network configuration saved to $networkConfigFile"
}

########## EXECUTE ###########

# Call the function to configure the network
try {
    Log-Message "Starting network configuration for $VMName with network type $NetworkType"
    Configure-Network -VMName $VMName -NetworkType $NetworkType -AdapterName $AdapterName -SubnetNetwork $SubnetNetwork -NicIndex $NicIndex
    Save-NetworkConfiguration -VMName $VMName -NetworkType $NetworkType -AdapterName $AdapterName -SubnetNetwork $SubnetNetwork -NicIndex $NicIndex
    Log-Message "Network configuration completed for $VMName"
}
catch {
    Log-Message "An error occurred: $($_.Exception.Message)"
    throw
}

Log-Message "Script execution completed successfully."
