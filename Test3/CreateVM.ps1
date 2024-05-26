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

# Function to extract .7z file and return the path of the VDI file
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

# Function to set a new UUID for a VDI file
function Set-VDIUUID {
    param (
        [string]$vboxManagePath,
        [string]$vdiFilePath
    )
    try {
        $newUUID = [guid]::NewGuid().ToString()
        $uuidCommand = "$vboxManagePath internalcommands sethduuid `"$vdiFilePath`" `"$newUUID`""
        Log-Message "Running UUID command: $uuidCommand"
        & "$vboxManagePath" internalcommands sethduuid "$vdiFilePath" "$newUUID"
        Log-Message "New UUID assigned to ${vdiFilePath}: $newUUID"
        return $newUUID
    } catch {
        Log-Message "Failed to assign new UUID to $vdiFilePath"
        throw
    }
}

# Function to create a .vbox file
function Create-VBoxFile {
    param (
        [string]$vboxFilePath,
        [string]$vmName,
        [string]$osType,
        [int]$memorySize,
        [int]$cpus,
        [string]$vdiFilePath,
        [string]$vdiUUID
    )

    $vboxContent = @"
<?xml version="1.0"?>
<VirtualBox xmlns="http://www.virtualbox.org/" version="1.19-windows">
  <Machine uuid="{$([guid]::NewGuid())}" name="$vmName" OSType="$osType" snapshotFolder="Snapshots">
    <Description>$vmName VirtualBox Image</Description>
    <MediaRegistry>
      <HardDisks>
        <HardDisk uuid="{$vdiUUID}" location="$vdiFilePath" format="VDI" type="Normal"/>
      </HardDisks>
    </MediaRegistry>
    <Hardware>
      <CPU count="$cpus"/>
      <Memory RAMSize="$memorySize"/>
      <Display controller="VMSVGA" VRAMSize="16"/>
      <Network>
        <Adapter slot="0" enabled="true" type="82540EM">
          <NAT/>
        </Adapter>
      </Network>
      <StorageControllers>
        <StorageController name="SATA" type="AHCI" PortCount="1" useHostIOCache="false" Bootable="true">
          <AttachedDevice type="HardDisk" port="0" device="0">
            <Image uuid="{$vdiUUID}"/>
          </AttachedDevice>
        </StorageController>
      </StorageControllers>
    </Hardware>
  </Machine>
</VirtualBox>
"@

    $vboxContent | Set-Content -Path $vboxFilePath
    Log-Message "Created .vbox file at $vboxFilePath"
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
        Log-Message "Download completed. File size: $((Get-Item $vhdLocalPath).Length) bytes"
    }

    Log-Message "Extracting VHD to $vhdExtractedPath..."
    $vdiFilePath = Extract-7z -sevenZipPath $sevenZipPath -inputFile $vhdLocalPath -outputFolder $vhdExtractedPath
    Log-Message "Extraction process completed."

    if (-not $vdiFilePath) {
        Log-Message "Extracted VDI file not found in $vhdExtractedPath"
        throw "Extraction failed or VDI file not found."
    }
    Log-Message "VDI file path: $vdiFilePath"

    # Ensure the VDI file path is correct
    if (Test-Path $vdiFilePath) {
        Log-Message "VDI file confirmed at path: $vdiFilePath"
    } else {
        Log-Message "VDI file not found at path: $vdiFilePath"
        throw "VDI file not found at path: $vdiFilePath"
    }

    # Assign a new UUID to the VDI file
    $vdiUUID = Set-VDIUUID -vboxManagePath $vboxManagePath -vdiFilePath $vdiFilePath

    # Create the .vbox file
    $vboxFilePath = "$vhdExtractedPath\$VMName.vbox"
    Create-VBoxFile -vboxFilePath $vboxFilePath -vmName $VMName -osType $OSType -memorySize $MemorySize -cpus $CPUs -vdiFilePath $vdiFilePath -vdiUUID $vdiUUID

    # Register the VM
    Log-Message "Registering VM..."
    & "$vboxManagePath" registervm "$vboxFilePath"
    Log-Message "VM registered successfully."

    # Start the VM
    Log-Message "Starting VM..."
    & "$vboxManagePath" startvm $VMName --type headless
    Log-Message "VM started successfully."
}
catch {
    Log-Message "An error occurred: $($_.Exception.Message)"
    throw
}

Log-Message "Script execution completed successfully."
