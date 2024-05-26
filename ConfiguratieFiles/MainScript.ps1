param (
    [string]$ConfigFilePath = "config.json",
    [string]$OutputScriptPath = "Studentscript.ps1"
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

# Start met het bouwen van de output script content
$outputScriptContent = @"
# Dit script richt de virtuele omgeving in zoals gespecificeerd in de JSON configuratie
param (
    [string]`$GitHubRepoUrl = 'https://raw.githubusercontent.com/Stefanfrijns/HBOICT/main/Test3'
)

# Functie om een script van GitHub te downloaden en uit te voeren
function Execute-GitHubScript {
    param (
        [string]`$scriptName,
        [string]`$vmName = '',
        [string]`$vhdUrl = '',
        [string]`$osType = '',
        [int]`$memorySize = 0,
        [int]`$cpus = 0
    )
    `$scriptUrl = "`$GitHubRepoUrl/`$scriptName"
    `$scriptPath = [System.IO.Path]::Combine(`$env:Temp, `$scriptName)
    try {
        (New-Object System.Net.WebClient).DownloadFile(`$scriptUrl, `$scriptPath)
        if (Test-Path `$scriptPath) {
            if (`$vmName -ne '' -and `$vhdUrl -ne '' -and `$osType -ne '' -and `$memorySize -ne 0 -and `$cpus -ne 0) {
                & powershell.exe -File `$scriptPath -VMName `$vmName -VHDUrl `$vhdUrl -OSType `$osType -MemorySize `$memorySize -CPUs `$cpus
            } else {
                & powershell.exe -File `$scriptPath
            }
        } else {
            Write-Output "Failed to download script: `$scriptUrl"
        }
    } catch {
        Write-Output "Error downloading or executing script: `$scriptUrl"
        throw
    }
}

# Altijd eerst het Installdependencies.ps1 script uitvoeren zonder parameters
Execute-GitHubScript -scriptName 'Installdependencies.ps1'

"@

# Itereer over de omgevingen en VM's in de JSON configuratie
foreach ($environment in $json.environments) {
    foreach ($vm in $environment.vms) {
        for ($i = 1; $i -le $vm.count; $i++) {
            $vmName = "$($vm.type)_VM$i"
            $VHDUrl = $vm.config.vhd_url
            $OSType = $vm.config.os_type
            $MemorySize = $vm.config.memory_size
            $CPUs = [int]$vm.config.cpus  # Convert to integer

            $outputScriptContent += @"
 # Setup $vmName
`$VMName = '$vmName'
`$VHDUrl = '$VHDUrl'
`$OSType = '$OSType'
`$MemorySize = $MemorySize
`$CPUs = $CPUs

# Voer het script uit om de VM aan te maken
Execute-GitHubScript -scriptName 'CreateVM.ps1' -vmName `"$VMName`" -vhdUrl `"$VHDUrl`" -osType `"$OSType`" -memorySize `$MemorySize -cpus `$CPUs
"@
        }
    }
}

# Sla het output script op naar het opgegeven pad
Set-Content -Path $OutputScriptPath -Value $outputScriptContent

Write-Output "Generated script saved to $OutputScriptPath"
