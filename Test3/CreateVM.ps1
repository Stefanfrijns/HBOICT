param (
    [string]$VMName,
    [string]$VHDUrl,
    [string]$OSType,
    [int]$MemorySize,
    [int]$CPUs
)

# Validate input parameters
if (-not $VMName -or -not $VHDUrl -or -not $OSType -or -not $MemorySize -or -not $CPUs) {
    throw "All parameters must be provided: VMName, VHDUrl, OSType, MemorySize, CPUs"
}

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

# Function to download a file
function Download-File {
    param (
        [string]$url,
        [string]$output
    )
    try {
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $output)
        Log-Message "Downloaded file from $url to $output"
    } catch {
        Log-Message "Failed to download file from $url to $output"
        throw
    }
}

# Function to extract .7z file
function Extract-7z {
    param (
        [string]$sevenZipPath,
        [string]$inputFile,
        [string]$outputFolder
    )
    if (Test-Path $outputFolder) {
        $vdiFile = Get-ChildItem -Path $outputFolder -Filter *.vdi -Recurse | Select-Object -First 1
        if ($vdiFile) {
            Log-Message "VDI file already exists in $outputFolder. Skipping extraction."
            return $vdiFile.FullName
        } else {
            Remove-Item -Recurse -Force $outputFolder
        }
    }
    New-Item -ItemType Directory -Force -Path $outputFolder

    $logFilePath = "$env:Public\7zExtract.log"
    $extractCommand = "& `"$sevenZipPath`" x `"$inputFile`" -o`"$outputFolder`""
    Log-Message "Running extract command: $extractCommand"
    
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $sevenZipPath
    $startInfo.Arguments = "x `"$inputFile`" -o`"$outputFolder`""
    $startInfo.RedirectStandardOutput = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    $output | Add-Content -Path $logFilePath

    $vdiFile = Get-ChildItem -Path $outputFolder -Filter *.vdi -Recurse | Select-Object -First 1
    if (-not $vdiFile) {
        throw "VDI file not found after extraction. Check $logFilePath for details."
    }
    Log-Message "VDI file extracted to $($vdiFile.FullName)"
    return $vdiFile.FullName
}

# Log the start of the script
Log-Message "Script execution started. Parameters: VMName=$VMName, VHDUrl=$VHDUrl, OSType=$OSType, MemorySize=$MemorySize, CPUs=$CPUs"

# Check if VBoxManage is available
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Log-Message "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

# Check if 7-Zip is available
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $sevenZipPath)) {
    Log-Message "7-Zip not found. Ensure 7-Zip is installed."
    throw "7-Zip not found."
}

# Download and extract the VHD
$downloadsPath = "$env:Public\Downloads"
$tempExtractedPath = "$downloadsPath\temp"
$vhdLocalPath = "$downloadsPath\$VMName.7z"
$vhdExtractedPath = "C:\Users\Public\LinuxVMs\$VMName"

try {
    # Ensure the downloads directory exists
    if (-not (Test-Path $downloadsPath)) {
        New-Item -ItemType Directory -Force -Path $downloadsPath
    }

    # Check if the file already exists
    if (Test-Path $vhdLocalPath) {
        Log-Message "VHD archive file already exists at $vhdLocalPath. Skipping download."
    } else {
        Log-Message "Downloading VHD from $VHDUrl..."
        Download-File $VHDUrl $vhdLocalPath
        Log-Message "Download completed. File size: $((Get-Item $vhdLocalPath).Length) bytes"
    }

    Log-Message "Extracting VHD to $tempExtractedPath..."
    $vdiFilePath = Extract-7z -sevenZipPath $sevenZipPath -inputFile $vhdLocalPath -outputFolder $tempExtractedPath
    Log-Message "Extraction process completed."

    if (-not $vdiFilePath) {
        Log-Message "Extracted VDI file not found in $tempExtractedPath"
        throw "Extraction failed or VDI file not found."
    }
    Log-Message "VDI file path: $vdiFilePath"

    # Clone the VDI file to the target directory
    $clonedVDIPath = "$vhdExtractedPath\$VMName.vdi"
    Log-Message "Cloning VDI to $clonedVDIPath..."
    $cloneCommand = "& `"$vboxManagePath`" clonevdi `"$vdiFilePath`" `"$clonedVDIPath`""
    Log-Message "Running clone command: $cloneCommand"
    Invoke-Expression $cloneCommand
    Log-Message "VDI cloned successfully to $clonedVDIPath"

    # Create the VM
    Log-Message "Creating VM..."
    & "$vboxManagePath" createvm --name $VMName --ostype $OSType --register
    Log-Message "VM created successfully."

    # Modify VM settings
    Log-Message "Modifying VM settings..."
    & "$vboxManagePath" modifyvm $VMName --memory $MemorySize --cpus $CPUs --nic1 nat --vram 16 --graphicscontroller vmsvga
    Log-Message "VM settings modified successfully."

    # Add storage controller with 1 port
    Log-Message "Adding storage controller..."
    & "$vboxManagePath" storagectl $VMName --name "SATA_Controller" --add sata --controller IntelAhci --portcount 1 --bootable on
    Log-Message "Storage controller added successfully."

    # Attach the VDI to the VM
    Log-Message "Attaching VDI to VM..."
    $storageAttachCommand = "& `"$vboxManagePath`" storageattach `"$VMName`" --storagectl `"SATA_Controller`" --port 0 --device 0 --type hdd --medium `"$clonedVDIPath`""
    Log-Message "Running storage attach command: $storageAttachCommand"
    Invoke-Expression $storageAttachCommand
    Log-Message "VDI attached successfully."

    # Start the VM
    Log-Message "Starting VM..."
    $startVMCommand = "& `"$vboxManagePath`" startvm `"$VMName`" --type headless"
    Log-Message "Running start VM command: $startVMCommand"
    Invoke-Expression $startVMCommand
    Log-Message "VM started successfully."
}
catch {
    Log-Message "An error occurred: $($_.Exception.Message)"
    throw
}

Log-Message "Script execution completed successfully."
