param (
    [string]$VMName,
    [string]$VHDUrl,
    [string]$OSType,
    [int]$MemorySize,
    [int]$CPUs
)

# Logbestand instellen
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

# Functie om een bestand te downloaden
function Download-File {
    param (
        [string]$url,
        [string]$output
    )
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($url, $output)
}

# Functie om .7z-bestand te extraheren
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

# Begin van het script loggen
Log-Message "Script execution started. Parameters: VMName=$VMName, VHDUrl=$VHDUrl, OSType=$OSType, MemorySize=$MemorySize, CPUs=$CPUs"

# Controleer of VBoxManage beschikbaar is
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Log-Message "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

# Controleer of 7-Zip beschikbaar is
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $sevenZipPath)) {
    Log-Message "7-Zip not found. Ensure 7-Zip is installed."
    throw "7-Zip not found."
}

# Download en extraheer de VHD
$vhdLocalPath = "$env:Public\$VMName.7z"
$vhdExtractedPath = "$env:Public\$VMName"

try {
    # Controleer of het bestand al bestaat
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

    # Create the VM
    Log-Message "Creating VM..."
    & "$vboxManagePath" createvm --name $VMName --ostype $OSType --register
    Log-Message "VM created successfully."

    # Modify VM settings
    Log-Message "Modifying VM settings..."
    & "$vboxManagePath" modifyvm $VMName --memory $MemorySize --cpus $CPUs --nic1 nat
    Log-Message "VM settings modified successfully."

    # Add storage controller
    Log-Message "Adding storage controller..."
    & "$vboxManagePath" storagectl $VMName --name "SATA Controller" --add sata --controller IntelAhci
    Log-Message "Storage controller added successfully."

    # Attach the VDI
    Log-Message "Attaching VDI..."
    $vdiFilePathEscaped = $vdiFilePath.FullName.Replace(" ", "` ")
    & "$vboxManagePath" storageattach $VMName --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$vdiFilePathEscaped"
    Log-Message "VDI attached successfully."

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
