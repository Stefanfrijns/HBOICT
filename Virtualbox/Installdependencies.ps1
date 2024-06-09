
# Functie om een bestand te downloaden
function Download-File {
    param (
        [string]$url,
        [string]$output
    )
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($url, $output)
}

# Controleer of het script als administrator wordt uitgevoerd
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Warning "Dit script moet als administrator worden uitgevoerd."
    Start-Process powershell.exe "-File $PSCommandPath" -Verb RunAs
    exit
}

# Functie om te controleren of Visual C++ 2019 Redistributable is geïnstalleerd
function Is-VCRuntimeInstalled {
    $vcRuntimeKey = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
    if (Test-Path $vcRuntimeKey) {
        $vcRuntimeVersion = (Get-ItemProperty -Path $vcRuntimeKey).Version
        if ($vcRuntimeVersion -ge "14.0.24215.1") {
            return $true
        }
    }
    return $false
}

# Functie om Visual C++ 2019 Redistributable te installeren
function Install-VCRuntime {
    if (Is-VCRuntimeInstalled) {
        Write-Output "Visual C++ 2019 Redistributable is already installed. Skipping installation."
        return
    }

    $vcRuntimeUrl = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
    $vcRuntimePath = "$env:Public\vc_redist.x64.exe"

    Write-Output "Downloading Visual C++ 2019 Redistributable..."
    Download-File $vcRuntimeUrl $vcRuntimePath
    Write-Output "Visual C++ 2019 Redistributable downloaded. Starting installation..."
    
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $vcRuntimePath
    $startInfo.Arguments = "/quiet /norestart"
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $output = $process.StandardOutput.ReadToEnd()
    $errorOutput = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $output | Add-Content -Path "$env:Public\VCRuntimeInstall.log"
    $errorOutput | Add-Content -Path "$env:Public\VCRuntimeInstallError.log"

    if ($process.ExitCode -ne 0) {
        Write-Output "Visual C++ 2019 Redistributable installation failed. Check VCRuntimeInstallError.log for details."
        throw "Visual C++ 2019 Redistributable installation failed."
    }

    Remove-Item $vcRuntimePath
    Write-Output "Visual C++ 2019 Redistributable installed successfully."
}

# Functie om VirtualBox te installeren
function Install-VirtualBox {
    $vboxPath = "C:\Program Files\Oracle\VirtualBox"
    $vboxManagePath = "$vboxPath\VBoxManage.exe"

    if (Test-Path $vboxManagePath) {
        Write-Output "VirtualBox is already installed. Skipping installation."
        return
    }

    $vboxInstallerUrl = "https://download.virtualbox.org/virtualbox/7.0.18/VirtualBox-7.0.18-162988-Win.exe"
    $vboxInstallerPath = "$env:Public\VirtualBox-7.0.18-162988-Win.exe"

    Write-Output "Downloading VirtualBox installer..."
    Download-File $vboxInstallerUrl $vboxInstallerPath
    Write-Output "VirtualBox installer downloaded. Starting installation..."
    
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $vboxInstallerPath
    $startInfo.Arguments = "--silent"
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $output = $process.StandardOutput.ReadToEnd()
    $errorOutput = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $output | Add-Content -Path "$env:Public\VirtualBoxInstall.log"
    $errorOutput | Add-Content -Path "$env:Public\VirtualBoxInstallError.log"

    if ($process.ExitCode -ne 0) {
        Write-Output "VirtualBox installation failed. Check VirtualBoxInstallError.log for details."
        throw "VirtualBox installation failed."
    }

    Remove-Item $vboxInstallerPath

    # Voeg VirtualBox aan PATH toe voor de huidige gebruiker
    if (-not ($env:Path -contains $vboxPath)) {
        [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$vboxPath", [System.EnvironmentVariableTarget]::User)
        $env:Path += ";$vboxPath"
    }

    # Controleer of de installatie is geslaagd
    if (Test-Path $vboxManagePath) {
        Write-Output "VirtualBox installation successful."
    } else {
        Write-Output "VirtualBox installation failed. VBoxManage.exe not found."
        throw "VirtualBox installation failed."
    }
}

# Functie om 7-Zip te installeren
function Install-7Zip {
    $sevenZipPath = "C:\Program Files\7-Zip\7z.exe"
    
    if (Test-Path $sevenZipPath) {
        Write-Output "7-Zip is already installed. Skipping installation."
        return
    }

    $sevenZipUrl = "https://www.7-zip.org/a/7z1900-x64.exe"
    $sevenZipPathDownload = "$env:Public\7z1900-x64.exe"
    Write-Output "Downloading 7-Zip..."
    Download-File -url $sevenZipUrl -output $sevenZipPathDownload
    Write-Output "7-Zip downloaded. Starting installation..."
    Start-Process -FilePath $sevenZipPathDownload -ArgumentList "/S" -Wait
    Remove-Item $sevenZipPathDownload
    Write-Output "7-Zip installed successfully."
}


# Installeer de vereiste software
Install-VCRuntime
Install-VirtualBox
Install-7Zip


