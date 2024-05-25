param (
    [string]$VMName
)

# Set up the log file
$logFilePath = "$env:Public\AttachVDI.log"
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
Log-Message "Script execution started. Parameter: VMName=$VMName"

# Check if VBoxManage is available
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Log-Message "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

try {
    # Retrieve the VDI path from the file
    $vdiPath = Get-Content -Path "$env:Public\vdiPath.txt"

    Log-Message "Attaching VDI from $vdiPath..."
    & "$vboxManagePath" storageattach $VMName --storagectl "SATA_Controller" --port 0 --device 0 --type hdd --medium "$vdiPath"
    Log-Message "VDI attached successfully."

    # Verify attachment
    $verifyCommand = "& `"$vboxManagePath`" showvminfo `"$VMName`" --machinereadable"
    $vmInfo = Invoke-Expression $verifyCommand
    Log-Message "VM Info: $vmInfo"

    # Check if the VDI is attached correctly
    if ($vmInfo -notmatch "SATA_Controller-0-0.*medium=$vdiPath") {
        Log-Message "Failed to attach VDI file to the VM."
        throw "Failed to attach VDI file to the VM."
    }

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
