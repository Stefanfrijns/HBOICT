param (
    [string]$VMName,
    [string]$VHDUrl
)

# Set up the log file
$logFilePath = "$env:Public\DownloadExtract.log"
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

    # Output the path of the VDI file for the next script
    $vdiFilePath.FullName | Out-File -FilePath "$env:Public\VDIPath.txt" -Force

}
catch {
    Log-Message "An error occurred: $_.Exception.Message"
    throw
}

Log-Message "Script execution completed successfully."
