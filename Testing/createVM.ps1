param (
    [string]$VMName,
    [string]$VHDUrl,
    [string]$OSType,
    [int]$MemorySize,
    [int]$CPUs
)

# Functie om een bestand te downloaden
function Download-File($url, $output) {
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($url, $output)
}

# Functie om 7z-bestanden te extraheren
function Extract-7z($file, $destination) {
    $7zPath = "C:\Program Files\7-Zip\7z.exe"
    & $7zPath x $file -o$destination
}

# Pad instellen voor het logbestand
$logFilePath = "C:\Users\stefa\hboict\CreateVM.log"
function Log-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
}

# Begin van het script loggen
Log-Message "Script execution started. Parameters: VMName=$VMName, VHDUrl=$VHDUrl, OSType=$OSType, MemorySize=$MemorySize, CPUs=$CPUs"

# Check if VBoxManage is available
if (-not (Get-Command "VBoxManage" -ErrorAction SilentlyContinue)) {
    Log-Message "VBoxManage not found. Please ensure VirtualBox is installed and VBoxManage is in your PATH."
    exit 1
}

# Download en extraheer de VHD
$vhdLocalPath = "C:\Users\stefa\hboict\$VMName.7z"
$vhdExtractedPath = "C:\Users\stefa\hboict\$VMName"
$vhdFilePath = "$vhdExtractedPath\UbuntuServer_24.04.vhd"

try {
    Log-Message "Downloading VHD from $VHDUrl..."
    Download-File $VHDUrl $vhdLocalPath
    Log-Message "Download completed."

    Log-Message "Extracting VHD..."
    Extract-7z $vhdLocalPath $vhdExtractedPath
    Log-Message "Extraction completed."

    # Create the VM
    Log-Message "Creating VM..."
    VBoxManage createvm --name $VMName --ostype $OSType --register
    Log-Message "VM created successfully."

    # Modify VM settings
    Log-Message "Modifying VM settings..."
    VBoxManage modifyvm $VMName --memory $MemorySize --cpus $CPUs --nic1 nat
    Log-Message "VM settings modified successfully."

    # Add storage controller
    Log-Message "Adding storage controller..."
    VBoxManage storagectl $VMName --name "SATA Controller" --add sata --controller IntelAhci
    Log-Message "Storage controller added successfully."

    # Attach the VHD
    Log-Message "Attaching VHD..."
    VBoxManage storageattach $VMName --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $vhdFilePath
    Log-Message "VHD attached successfully."

    # Configure boot order
    Log-Message "Configuring boot order..."
    VBoxManage modifyvm $VMName --boot1 disk --boot2 none --boot3 none --boot4 none
    Log-Message "Boot order configured successfully."

    # Start the VM
    Log-Message "Starting VM..."
    VBoxManage startvm $VMName --type headless
    Log-Message "VM started successfully."
}
catch {
    Log-Message "An error occurred: $_"
    throw
}

Log-Message "Script execution completed successfully."
