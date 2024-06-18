param (
    [string]$VMName,
    [string]$VHDUrl,
    [string]$OSType,
    [string]$DistroName,
    [int]$MemorySize,
    [int]$CPUs,
    [string]$NetworkTypes,  # JSON-string
    [string]$Applications,
    [string]$ConfigureNetworkPath
)

# Tijdelijk wijzigen van de Execution Policy om het uitvoeren van scripts toe te staan
$previousExecutionPolicy = Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Tijdelijk wijzigen van de Execution Policy om het uitvoeren van scripts toe te staan
$previousExecutionPolicy = Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

[string]$ConfigureNetworkUrl = "https://raw.githubusercontent.com/Stefanfrijns/HBOICT/main/test6/configurenetwork1.ps1"
[string]$CreateVM1Url = "https://raw.githubusercontent.com/Stefanfrijns/HBOICT/main/test6/createvm.ps1"
[string]$ModifyVMSettingsUrl = "https://raw.githubusercontent.com/Stefanfrijns/HBOICT/main/Virtualbox/ModifyVMSettings.ps1"

# Functie om een bestand te downloaden
function Download-File {
    param (
        [string]$url,
        [string]$output
    )
    if (-not (Test-Path $output)) {
        try {
            $client = New-Object System.Net.WebClient
            $client.DownloadFile($url, $output)
            Write-Output "Downloaded file from $url to $output"
        } catch {
            Write-Output "Failed to download file from $url to $output"
            throw
        }
    } else {
        Write-Output "File already exists: $output. Skipping download."
    }
}

# Log functie
$logFilePath = "$env:Public\LinuxMainScript.log"
function Log-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
}

# Controleer of VBoxManage beschikbaar is
$vboxManagePath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManagePath)) {
    Log-Message "VBoxManage not found. Ensure VirtualBox is installed."
    throw "VBoxManage not found."
}

# Lokale paden voor de gedownloade bestanden
$configureNetworkPath = "$env:Public\Downloads\ConfigureNetwork.ps1"
$createVM1LocalPath = "$env:Public\Downloads\CreateVM1.ps1"
$modifyVMSettingsLocalPath = "$env:Public\Downloads\ModifyVMSettings.ps1"
$createdVMsPath = "$env:Public\created_vms.txt"

# Download de JSON-bestanden en de scripts
Download-File -url $ConfigureNetworkUrl -output $configureNetworkPath
Download-File -url $CreateVM1Url -output $createVM1LocalPath
Download-File -url $ModifyVMSettingsUrl -output $modifyVMSettingsLocalPath


# Controleer of het bestand met aangemaakte VM's bestaat
$createdVMsPath = "$env:Public\created_vms.txt"
if (-not (Test-Path $createdVMsPath)) {
    New-Item -ItemType File -Force -Path $createdVMsPath
}

# Lees de lijst van aangemaakte VM's en filter lege regels en dubbele invoer
$createdVMs = Get-Content $createdVMsPath -Raw -ErrorAction SilentlyContinue | Out-String -ErrorAction SilentlyContinue
$createdVMs = $createdVMs -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Sort-Object -Unique

Write-Output "List of created VMs:"
$createdVMs | ForEach-Object { Write-Output " - $_" }

Write-Output "Checking for VM: '$VMName'"

# Check if the VM already exists
$vmExists = $false
foreach ($createdVM in $createdVMs) {
    Log-Message "Comparing '$VMName' with '$createdVM'"
    if ($createdVM.Trim() -eq $VMName) {
        Log-Message "Found existing VM: '$createdVM'"
        $vmExists = $true
        break
    }
}

if ($vmExists) {
    Log-Message "VM $VMName already exists. Checking if it's running."
    $vmState = & "$vboxManagePath" showvminfo "$VMName" --machinereadable | Select-String -Pattern "^VMState=" | ForEach-Object { $_.Line.Split("=")[1].Trim('"') }
    if ($vmState -eq "running") {
        Log-Message "VM $VMName is already running. Prompting user for permission to shut down."
        $userInput = Read-Host "VM $VMName is currently running. Do you want to shut it down to apply changes? (yes/no)"
        if ($userInput -eq "yes") {
            & "$vboxManagePath" controlvm $VMName acpipowerbutton
            Start-Sleep -Seconds 10
        } else {
            Log-Message "Skipping changes for VM $VMName."
            exit
        }
    }
    # Call the script to modify the VM settings
    $arguments = @(
        "-VMName", $VMName,
        "-MemorySize", $MemorySize,
        "-CPUs", $CPUs,
        "-NetworkTypes", $NetworkTypes,
        "-Applications", $Applications,
        "-ConfigureNetworkPath", $configureNetworkPath
    )
    & pwsh -File $modifyVMSettingsLocalPath @arguments
} else {
    Log-Message "Creating new VM: $VMName"
    # Roep het CreateVM1.ps1 script aan met de juiste parameters
    $arguments = @(
        "-VMName", $VMName,
        "-VHDUrl", $VHDUrl,
        "-OSType", $OSType,
        "-DistroName", $DistroName,
        "-MemorySize", $MemorySize,
        "-CPUs", $CPUs,
        "-NetworkTypes", $NetworkTypes,
        "-Applications", $Applications,
        "-ConfigureNetworkPath", $configureNetworkPath
    )
    & pwsh -File $createVM1LocalPath @arguments

    # Voeg de naam van de aangemaakte VM toe aan created_vms.txt
    Add-Content -Path $createdVMsPath -Value $VMName
}

# Herstellen van de oorspronkelijke Execution Policy
Set-ExecutionPolicy -ExecutionPolicy $previousExecutionPolicy -Scope Process -Force

Log-Message "Script execution completed successfully."
