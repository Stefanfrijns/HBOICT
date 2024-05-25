param (
    [string]$VMName,
    [string]$VHDUrl,
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

# Function to download a file
function Download-File {
    param (
        [string]$url,
        [string]$output
    )
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($url, $output)
}

# Function to extract .7z file
function Extract-7z {
    param (
        [string]$sevenZipPath,
        [string]$inputFile,
        [string]$outputFolder
    )
    if (Test-Path $outputFolder) {
        $vdiFilePath = Get-ChildItem -Path $outputFolder -Filter *.vdi -Recurse | Select-Object -First 1
        if ($vdiFilePath) {
            Write-Output "VDI file already exists in $outputFolder. Skipping extraction."
            return $vdiFilePath
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

    $vdiFilePath = Get-ChildItem -Path $outputFolder -Filter *.vdi -Recurse | Select-Object -First 1
    if (-not $vdiFilePath) {
        throw "VDI file not found after extraction. Check $logFilePath for details."
    }
    return $vdiFilePath
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
$vhdLocalPath = "$env:Public\$VMName.7z"
$vhdExtractedPath = "C:\Users\Public\LinuxVMs\$VMName"

try {
    # Check if the file already exists
    if (Test-Path $vhdLocalPath) {
        Log-Message "VHD archive file already exists at $vhdLocalPath. Skipping download."
    } else {
        Log-Message "Downloading VHD from $VHDUrl..."
        Download-File $VHDUrl $vhdLocalPath
        Log-Message "Download completed. File size: $(Get-Item $vhdLocalPath).Length bytes"
    }

    Log-Message "Extracting VHD to $vhdExtractedPath..."
    $vdiFilePath = Extract-7z -sevenZipPath $sevenZipPath -inputFile $vhdLocalPath -outputFolder $vhdExtractedPath
    Log-Message "Extraction process completed."

    if (-not $vdiFilePath) {
        Log-Message "Extracted VDI file not found in $vhdExtractedPath"
        throw "Extraction failed or VDI file not found."
    }
    Log-Message "VDI file found at $($vdiFilePath.FullName)"

    # Wait to ensure the file system is updated
    Start-Sleep -Seconds 5

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
    & "$vboxManagePath" storagectl $VMName --name "SATA_Controller" --add sata --controller IntelAhci --portcount 1
    Log-Message "Storage controller added successfully."

    # Attach the VDI from the correct path
    $vdiPath = "C:\Users\Public\LinuxVMs\$VMName\$($vdiFilePath.Name)"
    Log-Message "Attaching VDI from $vdiPath..."
    $attachCommand = "& `"$vboxManagePath`" storageattach `"$VMName`" --storagectl `"'SATA_Controller'`" --port 0 --device 0 --type hdd --medium `"$vdiPath`""
    Log-Message "Running attach command: $attachCommand"
    try {
        Invoke-Expression $attachCommand
        Log-Message "VDI attached successfully."
    } catch {
        Log-Message "Failed to attach VDI. Error: $_"
        throw "Failed to attach VDI file to the VM."
    }

    # Verify attachment
    $verifyCommand = "& `"$vboxManagePath`" showvminfo `"$VMName`" --machinereadable"
    $vmInfo = Invoke-Expression $verifyCommand
    Log-Message "VM Info: $vmInfo"

    # Check if the VDI is attached correctly
    if ($vmInfo -notmatch "SATA_Controller-0-0.*medium=$vdiPath") {
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
