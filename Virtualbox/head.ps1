# Tijdelijk wijzigen van de Execution Policy om het uitvoeren van scripts toe te staan
$previousExecutionPolicy = Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

[string]$ConfigUrl = "https://raw.githubusercontent.com/Matthias-Schulski/saxion-flex-infra/main/courses/course2.json"
[string]$VHDLinksUrl = "https://raw.githubusercontent.com/Matthias-Schulski/saxion-flex-infra/main/courses/harddisks.json"
[string]$ConfigureNetworkUrl = "https://raw.githubusercontent.com/Matthias-Schulski/saxion-flex-infra/main/infra/linux/virtualbox/ConfigureNetwork.ps1" 
[string]$CreateVM1Url = "https://raw.githubusercontent.com/Stefanfrijns/HBOICT/main/Virtualbox/CreateVM1.ps1"
[string]$ModifyVMSettingsUrl = "https://raw.githubusercontent.com/Stefanfrijns/HBOICT/main/Virtualbox/ModifyVMSettings.ps1"
[string]$ExtraScriptUrl = "https://raw.githubusercontent.com/Stefanfrijns/HBOICT/main/Virtualbox/Installdependencies.ps1"

# Functie om een bestand te downloaden
function Download-File {
    param (
        [string]$url,
        [string]$output
    )
    try {
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $output)
        Write-Output "Downloaded file from $url to $output"
    } catch {
        Write-Output "Failed to download file from $url to $output"
        throw
    }
}

# Functie om het OS-type te bepalen
function Get-OSType {
    param (
        [string]$osName
    )
    if ($osName -match "Ubuntu") {
        return "Ubuntu_64"
    } elseif ($osName -match "Debian") {
        return "Debian_64"
    } else {
        return "Other_64"
    }
}

# Controleer of VBoxManage beschikbaar is
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Write-Output "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

# Lokale paden voor de gedownloade bestanden
$configLocalPath = "$env:Public\Downloads\config.json"
$vhdLinksLocalPath = "$env:Public\Downloads\vhdlink.json"
$configureNetworkLocalPath = "$env:Public\Downloads\ConfigureNetwork.ps1"
$createVM1LocalPath = "$env:Public\Downloads\CreateVM1.ps1"
$modifyVMSettingsLocalPath = "$env:Public\Downloads\ModifyVMSettings.ps1"
$extraScriptLocalPath = "$env:Public\Downloads\ExtraScript.ps1"
$createdVMsPath = "$env:Public\created_vms.txt"

# Download de JSON-bestanden en de scripts
Download-File -url $ConfigUrl -output $configLocalPath
Download-File -url $VHDLinksUrl -output $vhdLinksLocalPath
Download-File -url $ConfigureNetworkUrl -output $configureNetworkLocalPath
Download-File -url $CreateVM1Url -output $createVM1LocalPath
Download-File -url $ModifyVMSettingsUrl -output $modifyVMSettingsLocalPath
Download-File -url $ExtraScriptUrl -output $extraScriptLocalPath

# Voer het extra script uit
& pwsh -File $extraScriptLocalPath

# Lees de JSON configuratie
$config = Get-Content $configLocalPath -Raw | ConvertFrom-Json
$vhdLinks = Get-Content $vhdLinksLocalPath -Raw | ConvertFrom-Json

# Map to store OS to VHD URL
$vhdUrlMap = @{}
foreach ($vhdLink in $vhdLinks) {
    $vhdUrlMap[$vhdLink.OS] = $vhdLink.VHDUrl
}

# Controleer of het bestand met aangemaakte VM's bestaat
if (-not (Test-Path $createdVMsPath)) {
    New-Item -ItemType File -Force -Path $createdVMsPath
}

# Lees de lijst van aangemaakte VM's
$createdVMs = Get-Content $createdVMsPath -Raw -ErrorAction SilentlyContinue | Out-String -ErrorAction SilentlyContinue
$createdVMs = $createdVMs -split "`n" | ForEach-Object { $_.Trim() }

foreach ($vm in $config.VMs) {
    $vmName = $vm.VMName
    $osTypeKey = $vm.VMVHDFile  # Use VMVHDFile field to determine the OS type
    $VHDUrl = $vhdUrlMap[$osTypeKey]
    if (-not $VHDUrl) {
        Write-Output "VHD URL not found for $osTypeKey. Skipping VM creation for $vmName."
        continue
    }
    $OSType = Get-OSType -osName $osTypeKey
    $MemorySize = 2048  # Default memory size, change logic if needed
    $CPUs = 2  # Default CPU count, change logic if needed
    $NetworkType = $vm.VMNetworkType

    # Check if the VM already exists
    if ($createdVMs -contains $vmName) {
        Write-Output "VM $vmName already exists. Checking if it's running."
        $vmState = & "$vboxManagePath" showvminfo "$vmName" --machinereadable | Select-String -Pattern "^VMState=" | ForEach-Object { $_.Line.Split("=")[1].Trim('"') }
        if ($vmState -eq "running") {
            Write-Output "VM $vmName is already running. Prompting user for permission to shut down."
            $userInput = Read-Host "VM $vmName is currently running. Do you want to shut it down to apply changes? (yes/no)"
            if ($userInput -eq "yes") {
                & "$vboxManagePath" controlvm $vmName acpipowerbutton
                Start-Sleep -Seconds 10
            } else {
                Write-Output "Skipping changes for VM $vmName."
                continue
            }
        }
        # Call the script to modify the VM settings
        $arguments = @(
            "-VMName", $vmName,
            "-MemorySize", $MemorySize,
            "-CPUs", $CPUs,
            "-NetworkType", $NetworkType,
            "-ConfigureNetworkPath", $configureNetworkLocalPath
        )
        & pwsh -File $modifyVMSettingsLocalPath @arguments
    } else {
        # Roep het CreateVM1.ps1 script aan met de juiste parameters
        $arguments = @(
            "-VMName", $vmName,
            "-VHDUrl", $VHDUrl,
            "-OSType", $OSType,
            "-MemorySize", $MemorySize,
            "-CPUs", $CPUs,
            "-NetworkType", $NetworkType,
            "-ConfigureNetworkPath", $configureNetworkLocalPath
        )
        & pwsh -File $createVM1LocalPath @arguments
    }
}

# Herstellen van de oorspronkelijke Execution Policy
Set-ExecutionPolicy -ExecutionPolicy $previousExecutionPolicy -Scope Process -Force

Write-Output "Script execution completed successfully."
