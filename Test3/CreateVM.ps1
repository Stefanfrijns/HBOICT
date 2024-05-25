param (
    [string]$VMName,
    [string]$OSType,
    [int]$MemorySize,
    [int]$CPUs
)

# Set up the log file
$logFilePath = "$env:Public\CreateVM.log"
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
Log-Message "Script execution started. Parameters: VMName=$VMName, OSType=$OSType, MemorySize=$MemorySize, CPUs=$CPUs"

# Check if VBoxManage is available
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Log-Message "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

# Read the VDI path from the previous script
$vdiFilePath = Get-Content "$env:Public\VDIPath.txt" -ErrorAction Stop

if (-not (Test-Path $vdiFilePath)) {
    Log-Message "VDI file not found at $vdiFilePath"
    throw "VDI file not found."
}

try {
    # Create the VM
    Log-Message "Creating VM..."
    & "$vboxManagePath" createvm --name $VMName --ostype $OSType --register
    Log-Message "VM created successfully."

    # Modify VM settings
    Log-Message "Modifying VM settings..."
    & "$vboxManagePath" modifyvm $VMName --memory $MemorySize --cpus $CPUs --nic1 nat
    Log-Message "VM settings modified successfully."

    # Add storage controller with 1 port
    Log-Message "Adding storage controller..."
    & "$vboxManagePath" storagectl $VMName --name "SATA Controller" --add sata --controller IntelAhci --portcount 1
    Log-Message "Storage controller added successfully."

    # Attach the VDI
    Log-Message "Attaching VDI..."
    $attachCommand = "& `"$vboxManagePath`" storageattach `"$VMName`" --storagectl `"'SATA Controller'`" --port 0 --device 0 --type hdd --medium `"$vdiFilePath`""
    Log-Message "Running attach command: $attachCommand"
    Invoke-Expression $attachCommand
    Log-Message "VDI attached successfully."

    # Verify attachment
    $verifyCommand = "& `"$vboxManagePath`" showvminfo `"$VMName`" --machinereadable"
    $vmInfo = Invoke-Expression $verifyCommand
    Log-Message "VM Info: $vmInfo"

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
