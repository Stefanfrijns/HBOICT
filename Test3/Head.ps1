param (
    [string]$VMName = "UbuntuServerVM",
    [string]$VHDUrl = "https://dlconusc1.linuxvmimages.com/046389e06777452db2ccf9a32efa3760:virtualbox/U/24.04/UbuntuServer_24.04_VB.7z",
    [string]$OSType = "Ubuntu_64",
    [int]$MemorySize = 2048,
    [int]$CPUs = 2
)

# Function to download a file
function Download-File {
    param (
        [string]$url,
        [string]$output
    )
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($url, $output)
}

# URLs to download the scripts from GitHub
$downloadExtractUrl = "https://raw.githubusercontent.com/your-repo/your-project/main/DownloadExtract.ps1"
$createVMUrl = "https://raw.githubusercontent.com/your-repo/your-project/main/CreateVM.ps1"

# Local paths to save the downloaded scripts
$downloadExtractPath = "$env:Public\DownloadExtract.ps1"
$createVMPath = "$env:Public\CreateVM.ps1"

# Download the scripts
Download-File -url $downloadExtractUrl -output $downloadExtractPath
Download-File -url $createVMUrl -output $createVMPath

# Ensure the scripts are executable
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Execute the DownloadExtract.ps1 script
& "$downloadExtractPath" -VMName $VMName -VHDUrl $VHDUrl

# Wait for the extraction to complete
Start-Sleep -Seconds 10

# Execute the CreateVM.ps1 script
& "$createVMPath" -VMName $VMName -OSType $OSType -MemorySize $MemorySize -CPUs $CPUs
