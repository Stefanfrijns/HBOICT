param (
    [string]$VMName,
    [string]$VDIPath
)

# Validate input parameters
if (-not $VMName -or -not $VDIPath) {
    throw "All parameters must be provided: VMName, VDIPath"
}

# Set up the log file
$logFilePath = "$env:Public\ConfigureAndStartVM.log"
function Log-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
}

# Log the start of the script
Log-Message "Script execution started. Parameters: VMName=$VMName, VDIPath=$VDIPath"

# Check if VBoxManage is available
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Log-Message "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

try {
    # Rename the VDI file to match the VM name
    $newVdiPath = Join-Path -Path (Split-Path -Parent $VDIPath) -ChildPath "$VMName.vdi"
    Move-Item -Path $VDIPath -Destination $newVdiPath -Force
    Log-Message "Renamed VDI file from $VDIPath to $newVdiPath"

    # Add storage controller with 1 port
    Log-Message "Adding storage controller..."
    & "$vboxManagePath" storagectl $VMName --name "SATA_Controller" --add sata --controller IntelAhci --portcount 1 --bootable on
    Log-Message "Storage controller added successfully."

    # Attach the VDI from the correct path
    Log-Message "Attaching VDI from $newVdiPath..."
    
    if (-not (Test-Path $newVdiPath)) {
        Log-Message "VDI file not found at $newVdiPath"
        throw "VDI file not found at $newVdiPath"
    }
    
    & "$vboxManagePath" storageattach $VMName --storagectl "SATA_Controller" --port 0 --device 0 --type hdd --medium "$newVdiPath"
    Log-Message "VDI attached successfully."

    # Verify attachment
    $escapedVdiPath = [regex]::Escape($newVdiPath)
    $verifyCommand = "& `"$vboxManagePath`" showvminfo `"$VMName`" --machinereadable"
    $vmInfo = Invoke-Expression $verifyCommand
    Log-Message "VM Info: $vmInfo"

    # Check if the VDI is attached correctly
    if ($vmInfo -notmatch "SATA_Controller-0-0.*medium=$escapedVdiPath") {
        Log-Message "Failed to attach VDI file to the VM."
        throw "Failed to attach VDI file to the VM."
    }

    # Configure boot order
    Log-Message "Configuring boot order..."
    & "$vboxManagePath" modifyvm $VMName --boot1 disk --boot2 none --boot3 none --boot4 none
    Log-Message "Boot order configured successfully."

    # Start the VM
    Log-Message "Starting VM..."
    & "$vboxManagePath" startvm $VMName --type headless
    Log-Message "VM started successfully."
}
catch {
    Log-Message "An error occurred: $_.Exception.Message"
    throw
}

Log-Message "Script execution completed successfully."
