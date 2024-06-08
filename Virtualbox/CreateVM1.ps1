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
        Remove-Item -Recurse -Force $outputFolder
    }
    New-Item -ItemType Directory -Force -Path $outputFolder

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $sevenZipPath
    $startInfo.Arguments = "x `"$inputFile`" -o`"$outputFolder`""
    $startInfo.RedirectStandardOutput = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()

    $vmdkFile = Get-ChildItem -Path $outputFolder -Filter *.vmdk -Recurse | Select-Object -First 1
    if (-not $vmdkFile) {
        throw "VMDK file not found after extraction."
    }
    return $vmdkFile.FullName
}

# Remove illegal characters from the VM name
function Remove-IllegalCharacters {
    param (
        [string]$name
    )
    $illegalChars = [System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars()
    $sanitized = $name -replace "[$illegalChars]", ""
    return $sanitized
}

# Function to install VirtualBox Extension Pack
function Install-VirtualBoxExtensionPack {
    $extensionPackUrl = "https://download.virtualbox.org/virtualbox/6.1.22/Oracle_VM_VirtualBox_Extension_Pack-6.1.22.vbox-extpack"  # Pas dit aan naar de gewenste versie
    $extensionPackPath = "$env:TEMP\Oracle_VM_VirtualBox_Extension_Pack.vbox-extpack"

    $extPackInstalled = & "$vboxManagePath" list extpacks | Select-String "Oracle VM VirtualBox Extension Pack"
    if ($extPackInstalled) {
        Log-Message "VirtualBox Extension Pack is already installed. Skipping installation."
        return
    }

    Download-File -url $extensionPackUrl -output $extensionPackPath
    & "$vboxManagePath" extpack install "$extensionPackPath" --replace --accept-license=56be48f923303c8cababb0f812b9c3c4
    Log-Message "VirtualBox Extension Pack installed successfully."
}

# Sanitize VMName
$VMName = Remove-IllegalCharacters -name $VMName
Log-Message "Sanitized VMName: $VMName"

# Log the start of the script
Log-Message "Script execution started. Parameters: VMName=$VMName, VHDUrl=$VHDUrl, OSType=$OSType, MemorySize=$MemorySize, CPUs=$CPUs, NetworkType=$NetworkType, ConfigureNetworkPath=$ConfigureNetworkPath"

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

# Install VirtualBox Extension Pack
try {
    Install-VirtualBoxExtensionPack
} catch {
    Log-Message "Failed to install VirtualBox Extension Pack: $($_.Exception.Message)"
    throw
}

# Download and extract the VHD
$downloadsPath = "$env:Public\Downloads"
$tempExtractedPath = "$downloadsPath\$VMName"
$vhdLocalPath = "$env:Public\$VMName.7z"
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
    $vmdkFilePath = Extract-7z -sevenZipPath $sevenZipPath -inputFile $vhdLocalPath -outputFolder $tempExtractedPath
    Log-Message "Extraction process completed."

    if (-not $vmdkFilePath) {
        Log-Message "Extracted VMDK file not found in $tempExtractedPath"
        throw "Extraction failed or VMDK file not found."
    }
    Log-Message "VMDK file path: $vmdkFilePath"

    # Ensure $vmdkFilePath is a string and correct
    $vmdkFileName = [System.IO.Path]::GetFileName($vmdkFilePath)
    $vmdkFilePath = Join-Path -Path $tempExtractedPath -ChildPath $vmdkFileName
    Log-Message "Validated VMDK file path: $vmdkFilePath"

    # Rename the extracted VMDK file to VMName.vmdk
    $renamedVMDKPath = "$tempExtractedPath\$VMName.vmdk"
    Log-Message "Renaming VMDK file from $vmdkFilePath to $renamedVMDKPath"
    Rename-Item -Path $vmdkFilePath -NewName "$VMName.vmdk"
    Log-Message "VMDK file renamed to $renamedVMDKPath"

    # Assign a new UUID to the renamed VMDK file
    Log-Message "Assigning new UUID to VMDK file..."
    & "$vboxManagePath" internalcommands sethduuid "$renamedVMDKPath"
    Log-Message "New UUID assigned to $renamedVMDKPath"

    # Ensure the target directory exists
    if (-not (Test-Path $vhdExtractedPath)) {
        New-Item -ItemType Directory -Force -Path $vhdExtractedPath
    }

    # Clone the VMDK file to the target directory
    $clonedVMDKPath = "$vhdExtractedPath\$VMName.vmdk"
    Log-Message "Cloning VMDK to $clonedVMDKPath..."
    & "$vboxManagePath" clonemedium disk "$renamedVMDKPath" "$clonedVMDKPath"
    Log-Message "VMDK cloned successfully to $clonedVMDKPath"

    # Create the VM
    Log-Message "Creating VM..."
    & "$vboxManagePath" createvm --name $VMName --ostype $OSType --register
    Log-Message "VM created successfully."

    # Modify VM settings
    Log-Message "Modifying VM settings..."
    & "$vboxManagePath" modifyvm $VMName --memory $MemorySize --cpus $CPUs --vram 16 --graphicscontroller vmsvga
    Log-Message "VM settings modified successfully."

    # Add storage controller with 1 port
    Log-Message "Adding storage controller..."
    & "$vboxManagePath" storagectl $VMName --name "SATA_Controller" --add sata --controller IntelAhci --portcount 1 --bootable on
    Log-Message "Storage controller added successfully."

    # Attach the cloned VMDK to the VM
    Log-Message "Attaching cloned VMDK to VM..."
    & "$vboxManagePath" storageattach $VMName --storagectl "SATA_Controller" --port 0 --device 0 --type hdd --medium "$clonedVMDKPath"
    Log-Message "Cloned VMDK attached successfully."

    # Configure network
    Log-Message "Configuring network for VM..."
    $networkArguments = @(
        "-VMName", $VMName,
        "-NetworkType", $NetworkType
    )
    & pwsh -File $ConfigureNetworkPath @networkArguments
    Log-Message "Network configuration completed successfully."

    # Enable guest control
    Log-Message "Enabling guest control for VM..."
    & "$vboxManagePath" modifyvm $VMName --vrde on
    Log-Message "Guest control enabled for VM."

    # Start the VM
    Log-Message "Starting VM..."
    & "$vboxManagePath" startvm $VMName --type headless
    Log-Message "VM started successfully."

    # Add VM name to the list of created VMs
    $createdVMsPath = "$env:Public\created_vms.txt"
    Add-Content -Path $createdVMsPath -Value $VMName
    Log-Message "VM name $VMName added to $createdVMsPath."
}
catch {
    Log-Message "An error occurred: $($_.Exception.Message)"
    throw
}
Log-Message "Script execution completed successfully."
