param (
    [string]$VMName,
    [string]$VHDUrl,
    [string]$OSType,
    [int]$MemorySize,
    [int]$CPUs,
    [string]$NetworkTypes,
    [string]$Applications,
    [string]$ConfigureNetworkPath
)

# Tijdelijk wijzigen van de Execution Policy om het uitvoeren van scripts toe te staan
$previousExecutionPolicy = Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Path to VBoxManage
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# Log-bestand instellen
$logFilePath = "$env:Public\CreateVM1.log"
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

    $vmdkFile = Get-ChildItem -Path $outputFolder -Filter *.vmdk -Recurse | Select-Object -First 1
    if (-not $vmdkFile) {
        throw "VMDK file not found after extraction. Check $logFilePath for details."
    }
    Log-Message "VMDK file extracted to $($vmdkFile.FullName)"
    return $vmdkFile.FullName
}

# Ensure the downloads directory exists
$downloadsPath = "$env:Public\Downloads"
$tempExtractedPath = "$downloadsPath\$VMName"
$vhdLocalPath = "$env:Public\$VMName.7z"
$vhdExtractedPath = "C:\Users\Public\LinuxVMs\$VMName"
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"

try {
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
    $vmdkFilePath = $vmdkFilePath -join ""
    $vmdkFilePath = $vmdkFilePath.Trim()
    $vmdkFilePath = $vmdkFilePath -replace ".*(C:\\Users\\Public\\Downloads\\.*?\\.*?\.vmdk).*", '$1'
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
    & "$vboxManagePath" clonevdi "$renamedVMDKPath" "$clonedVMDKPath"
    Log-Message "VMDK cloned successfully to $clonedVMDKPath"

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

    # Attach the cloned VMDK to the VM
    Log-Message "Attaching cloned VMDK to VM..."
    & "$vboxManagePath" storageattach $VMName --storagectl "SATA_Controller" --port 0 --device 0 --type hdd --medium "$clonedVMDKPath"
    Log-Message "Cloned VMDK attached successfully."

    # Controleer of het netwerkconfiguratiescript bestaat en lees de inhoud
    if (-not (Test-Path $ConfigureNetworkPath)) {
        throw "Network configuration script not found at $ConfigureNetworkPath"
    }
    $configureNetworkScriptContent = Get-Content -Path $ConfigureNetworkPath -Raw

    # Lees de netwerktypes
    Log-Message "NetworkTypes parameter: $NetworkTypes"
    $networkTypes = $NetworkTypes | ConvertFrom-Json
    Log-Message "Parsed NetworkTypes: $($networkTypes | ConvertTo-Json -Compress)"

    # Configureer de netwerken
    $nicIndex = 1
    foreach ($networkType in $networkTypes) {
        if (-not $networkType.Type -or -not $networkType.AdapterName -or -not $networkType.Network) {
            Log-Message "Missing parameters for network configuration: Type=$($networkType.Type), AdapterName=$($networkType.AdapterName), Network=$($networkType.Network)"
            throw "All parameters must be provided: VMName, NetworkType, AdapterName, SubnetNetwork"
        }
    
        $args = @(
            "-VMName", $VMName,
            "-NetworkType", $networkType.Type,
            "-AdapterName", $networkType.AdapterName,
            "-SubnetNetwork", $networkType.Network,
            "-NicIndex", $nicIndex
        )
        Invoke-Command -ScriptBlock ([ScriptBlock]::Create($configureNetworkScriptContent)) -ArgumentList $args

        $nicIndex++
    }

    Log-Message "Starting VM..."
    & "$vboxManagePath" startvm $VMName --type headless
    Log-Message "VM started successfully."
}
catch {
    Log-Message "An error occurred: $($_.Exception.Message)"
    throw
}
Log-Message "Script execution completed successfully."

# Herstel de oorspronkelijke Execution Policy
Set-ExecutionPolicy -ExecutionPolicy $previousExecutionPolicy -Scope Process -Force
