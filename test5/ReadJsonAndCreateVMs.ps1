# Tijdelijk wijzigen van de Execution Policy om het uitvoeren van scripts toe te staan
$previousExecutionPolicy = Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

param (
    [string]$ConfigFilePath = "config.json"
)

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

# Lees de JSON configuratie
$json = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json

foreach ($environment in $json.environments) {
    foreach ($vm in $environment.vms) {
        for ($i = 1; $i -le $vm.count; $i++) {
            $vmName = "$($vm.type)_VM$i"
            $VHDUrl = $vm.config.vhd_url
            $OSType = $vm.config.os_type
            $MemorySize = [int]$vm.config.memory_size  # Convert to integer
            $CPUs = [int]$vm.config.cpus  # Convert to integer

            # Roep het CreateVM1.ps1 script aan met de juiste parameters
            $createVM1ScriptPath = "C:\Path\To\CreateVM1.ps1"  # Pas dit aan naar de juiste locatie
            $arguments = @(
                "-VMName", $vmName,
                "-VHDUrl", $VHDUrl,
                "-OSType", $OSType,
                "-MemorySize", $MemorySize,
                "-CPUs", $CPUs
            )
            & powershell.exe -File $createVM1ScriptPath @arguments
        }
    }
}

# Herstellen van de oorspronkelijke Execution Policy
Set-ExecutionPolicy -ExecutionPolicy $previousExecutionPolicy -Scope Process -Force

Write-Output "Script execution completed successfully."

