param (
    [string]$VMName,
    [string]$NetworkType,
    [string]$AdapterName,
    [string]$SubnetNetwork,
    [int]$NicIndex
)

# Validate input parameters
if (-not $VMName -or -not $NetworkType -or -not $AdapterName -or (-not $SubnetNetwork -and $NetworkType -ne "bridged") -or -not $NicIndex) {
    throw "All parameters must be provided: VMName, NetworkType, AdapterName, SubnetNetwork (except for bridged), NicIndex"
}

# Path to VBoxManage
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$publicFolderPath = "$env:Public\VMNetworkConfigurations"
$controlFilePath = "$publicFolderPath\controlehostonly.txt"

# Function to create a host-only network adapter
function Create-HostOnlyAdapter {
    $output = & "$vboxManagePath" hostonlyif create | Out-String

    if ($output -match "Interface 'VirtualBox Host-Only Ethernet Adapter #(\d+)' was successfully created") {
        $adapterNumber = $matches[1]
        $adapterName = "VirtualBox Host-Only Ethernet Adapter #$adapterNumber"
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

    $ipconfigOutput = & "$vboxManagePath" hostonlyif ipconfig "$adapterName" --ip "$network" --netmask "$subnetMask"
    Write-Output "hostonlyif ipconfig output: $ipconfigOutput"

    if ($ipconfigOutput -notmatch "successfully configured") {
        throw "Failed to configure IP for adapter ${adapterName}: $ipconfigOutput"
    }
}

# Function to get the course name from the VM name
function Get-CourseName {
    param (
        [string]$vmName
    )
    return ($vmName -split '_')[0]
}

# Save network configuration to file
function Save-NetworkConfiguration {
    param (
        [string]$courseName,
        [string]$VMName,
        [string]$OriginalAdapterName,
        [string]$ActualAdapterName
    )
    $courseConfigFile = "$publicFolderPath\NetworkConfig_$courseName.json"

    if (-not (Test-Path $publicFolderPath)) {
        New-Item -ItemType Directory -Path $publicFolderPath -Force
    }

    $networkConfig = @()
    if (Test-Path $courseConfigFile) {
        $networkConfig = (Get-Content -Path $courseConfigFile -Raw | ConvertFrom-Json)
        if (-not ($networkConfig -is [System.Collections.ArrayList])) {
            $networkConfig = @($networkConfig)
        }
    }

    $networkConfig += [PSCustomObject]@{
        VMName              = $VMName
        OriginalAdapterName = $OriginalAdapterName
        ActualAdapterName   = $ActualAdapterName
    }

    $networkConfig | ConvertTo-Json -Compress | Set-Content -Path $courseConfigFile
    Write-Output "Network configuration saved to $courseConfigFile"
}

# Function to get the actual adapter name from the configuration file
function Get-ActualAdapterName {
    param (
        [string]$courseName,
        [string]$OriginalAdapterName
    )
    $courseConfigFile = "$publicFolderPath\NetworkConfig_$courseName.json"

    if (Test-Path $courseConfigFile) {
        $configContent = Get-Content -Path $courseConfigFile -Raw | ConvertFrom-Json
        $config = $configContent | Where-Object { $_.OriginalAdapterName -eq $OriginalAdapterName }
        if ($config) {
            return $config.ActualAdapterName
        }
    }
    return $null
}

# Ensure a host-only adapter is always created initially if the control file is empty
if (-not (Test-Path $controlFilePath) -or (Get-Content -Path $controlFilePath -Raw).Trim() -eq '') {
    try {
        Write-Output "Creating initial host-only adapter for control purposes..."
        Create-HostOnlyAdapter | Out-Null
    } catch {
        Write-Output "An error occurred while creating the initial host-only adapter: $($_.Exception.Message)"
    } finally {
        Set-Content -Path $controlFilePath -Value '1'
    }
}

try {
    Write-Output "Starting network configuration for $VMName with network type $NetworkType"
    
    $courseName = Get-CourseName -vmName $VMName
    $actualAdapterName = Get-ActualAdapterName -courseName $courseName -OriginalAdapterName $AdapterName

    if ($actualAdapterName) {
        Write-Output "Using existing adapter $actualAdapterName for $VMName"
    } else {
        if ($NetworkType -eq "host-only") {
            $actualAdapterName = Create-HostOnlyAdapter
            Configure-HostOnlyAdapterIP -adapterName $actualAdapterName -SubnetNetwork $SubnetNetwork
            Save-NetworkConfiguration -courseName $courseName -VMName $VMName -OriginalAdapterName $AdapterName -ActualAdapterName $actualAdapterName
        } elseif ($NetworkType -eq "natnetwork") {
            $natNetName = "NatNetwork_$AdapterName"
            Write-Output "Adding NAT network with name $natNetName and network $SubnetNetwork"
            & "$vboxManagePath" natnetwork add --netname $natNetName --network $SubnetNetwork --dhcp off
            $actualAdapterName = $natNetName
            Save-NetworkConfiguration -courseName $courseName -VMName $VMName -OriginalAdapterName $AdapterName -ActualAdapterName $actualAdapterName
        } elseif ($NetworkType -eq "bridged") {
            $actualAdapterName = $AdapterName
            Save-NetworkConfiguration -courseName $courseName -VMName $VMName -OriginalAdapterName $AdapterName -ActualAdapterName $actualAdapterName
        } else {
            throw "Unsupported network type: $NetworkType"
        }
    }

    # Configure the network adapters
    if ($NetworkType -eq "host-only") {
        Write-Output "Configuring host-only network for $VMName using adapter $actualAdapterName"
        & "$vboxManagePath" modifyvm $VMName --nic$NicIndex hostonly --hostonlyadapter$NicIndex $actualAdapterName
    } elseif ($NetworkType -eq "natnetwork") {
        Write-Output "Configuring NAT network for $VMName using network $actualAdapterName"
        & "$vboxManagePath" modifyvm $VMName --nic$NicIndex natnetwork --nat-network$NicIndex $actualAdapterName
    } elseif ($NetworkType -eq "bridged") {
        Write-Output "Configuring bridged network for $VMName using adapter $actualAdapterName"
        & "$vboxManagePath" modifyvm $VMName --nic$NicIndex bridged --bridgeadapter$NicIndex $actualAdapterName
    }

    Start-Sleep -Seconds 2  # Pause for 2 seconds to avoid lock issues
    Write-Output "Network configuration completed for $VMName"
} catch {
    Write-Output "An error occurred: $($_.Exception.Message)"
    throw
}

Write-Output "Script execution completed successfully."
