param (
    [string]$VMName,
    [int]$MemorySize,
    [int]$CPUs,
    [string]$NetworkType,
    [string]$ConfigureNetworkPath
)

# Validate input parameters
if (-not $VMName -or -not $MemorySize -or -not $CPUs -or -not $NetworkType -or -not $ConfigureNetworkPath) {
    throw "All parameters must be provided: VMName, MemorySize, CPUs, NetworkType, ConfigureNetworkPath"
}

# Set up the log file
$logFilePath = "$env:Public\ModifyVMSettings.log"
function Log-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
}

# Check if VBoxManage is available
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Log-Message "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

# Log the start of the script
Log-Message "Script execution started. Parameters: VMName=$VMName, MemorySize=$MemorySize, CPUs=$CPUs, NetworkType=$NetworkType, ConfigureNetworkPath=$ConfigureNetworkPath"

# Modify VM settings
try {
    # Modify memory and CPU settings
    Log-Message "Modifying VM settings for $VMName..."
    & "$vboxManagePath" modifyvm $VMName --memory $MemorySize --cpus $CPUs
    Log-Message "Memory and CPU settings modified for $VMName."

    # Configure network
    Log-Message "Configuring network for VM..."
    $networkArguments = @(
        "-VMName", $VMName,
        "-NetworkType", $NetworkType
    )
    & pwsh -File $ConfigureNetworkPath @networkArguments
    Log-Message "Network configuration completed successfully for $VMName."

    # Start the VM
    Log-Message "Starting VM $VMName..."
    & "$vboxManagePath" startvm $VMName --type headless
    Log-Message "VM $VMName started successfully."
}
catch {
    Log-Message "An error occurred: $($_.Exception.Message)"
    throw
}

Log-Message "Script execution completed successfully."
