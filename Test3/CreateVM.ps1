param (
    [string]$VMName,
    [string]$VDIPath,
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

# Check if VBoxManage is available
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Log-Message "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

# Create the VM
Log-Message "Creating VM $VMName..."
& "$vboxManagePath" createvm --name $VMName --ostype $OSType --register
Log-Message "VM $VMName created successfully."

# Modify VM settings
Log-Message "Modifying VM settings for $VMName..."
& "$vboxManagePath" modifyvm $VMName --memory $MemorySize --cpus $CPUs --nic1 nat --vram 16 --graphicscontroller vmsvga
Log-Message "VM settings modified successfully for $VMName."

# Add storage controller with 1 port
Log-Message "Adding storage controller for $VMName..."
& "$vboxManagePath" storagectl $VMName --name "SATA_Controller" --add sata --controller IntelAhci --portcount 1 --bootable on
Log-Message "Storage controller added successfully for $VMName."

# Attach the VDI from the correct path
Log-Message "Attaching VDI from $VDIPath to $VMName..."
& "$vboxManagePath" storageattach $VMName --storagectl "SATA_Controller" --port 0 --device 0 --type hdd --medium "$VDIPath"
Log-Message "VDI attached successfully to $VMName."

# Configure boot order
Log-Message "Configuring boot order for $VMName..."
& "$vboxManagePath" modifyvm $VMName --boot1 disk --boot2 none --boot3 none --boot4 none
Log-Message "Boot order configured successfully for $VMName."

# Start the VM
Log-Message "Starting VM $VMName..."
& "$vboxManagePath" startvm $VMName --type headless
Log-Message "VM $VMName started successfully."
