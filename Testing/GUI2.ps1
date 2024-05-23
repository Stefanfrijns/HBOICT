Add-Type -AssemblyName PresentationFramework

# Functie om JSON-configuratie te laden
function Load-Config($path) {
    if (Test-Path $path) {
        return Get-Content -Path $path -Raw | ConvertFrom-Json
    } else {
        [System.Windows.MessageBox]::Show("Config file not found at path: $path", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        exit 1
    }
}

# Functie om het scriptbestand te genereren
function Generate-Script($config, $outputPath) {
    $scriptContent = @"
param (
    [string]`$VMName = `"$($config.vm.name)`",
    [string]`$VHDUrl = `"$($config.vm.vhd_url)`",
    [string]`$OSType = `"$($config.vm.os_type)`",
    [int]`$MemorySize = $($config.vm.memory_size),
    [int]`$CPUs = $($config.vm.cpus)
)

# Functie om een bestand te downloaden
function Download-File(`$url, `$output) {
    `$client = New-Object System.Net.WebClient
    `$client.DownloadFile(`$url, `$output)
}

# Functie om 7z-bestanden te extraheren
function Extract-7z(`$file, `$destination) {
    `$7zPath = `"$env:ProgramFiles\7-Zip\7z.exe`"
    if (-not (Test-Path `$7zPath)) {
        # 7-Zip installeren als het niet aanwezig is
        `$installerPath = `"$env:Public\7z.exe`"
        Download-File `"https://www.7-zip.org/a/7z1900-x64.exe`" `$installerPath
        Start-Process -FilePath `$installerPath -ArgumentList `"/S`" -Wait
        Remove-Item `$installerPath
    }
    & `$7zPath x `$file -o`$destination
}

# Functie om VirtualBox te installeren
function Install-VirtualBox {
    `$vboxInstallerUrl = `"https://download.virtualbox.org/virtualbox/6.1.18/VirtualBox-6.1.18-142142-Win.exe`" # Pas dit aan naar de nieuwste versie indien nodig
    `$vboxInstallerPath = `"$env:Public\VirtualBox-6.1.18-142142-Win.exe`"

    Download-File `$vboxInstallerUrl `$vboxInstallerPath
    Start-Process -FilePath `$vboxInstallerPath -ArgumentList `"--silent`" -Wait
    Remove-Item `$vboxInstallerPath

    # Voeg VirtualBox aan PATH toe
    `$vboxPath = `"$env:ProgramFiles\Oracle\VirtualBox`"
    if (-not (`$env:Path -contains `$vboxPath)) {
        [Environment]::SetEnvironmentVariable(`"Path`", `$env:Path + `";`$vboxPath`", [System.EnvironmentVariableTarget]::Machine)
        `$env:Path += `";`$vboxPath`"
    }
}

# Logbestand instellen
`$logFilePath = `"$env:Public\CreateVM.log`"
function Log-Message {
    param (
        [string]`$message
    )
    `$timestamp = Get-Date -Format `"yyyy-MM-dd HH:mm:ss`"
    `$logMessage = `"$timestamp - `$message`"
    Write-Output `$logMessage
    Add-Content -Path `$logFilePath -Value `$logMessage
}

# Begin van het script loggen
Log-Message `"Script execution started. Parameters: VMName=`$VMName, VHDUrl=`$VHDUrl, OSType=`$OSType, MemorySize=`$MemorySize, CPUs=`$CPUs`"

# Check if VBoxManage is available, and install VirtualBox if not
if (-not (Get-Command `"VBoxManage`" -ErrorAction SilentlyContinue)) {
    Log-Message `"VBoxManage not found. Installing VirtualBox...`"
    Install-VirtualBox
    Log-Message `"VirtualBox installed successfully.`"
}

# Download en extraheer de VHD
`$vhdLocalPath = `"$env:Public\$VMName.7z`"
`$vhdExtractedPath = `"$env:Public\$VMName`"
`$vhdFilePath = `"$vhdExtractedPath\UbuntuServer_24.04.vhd`"

try {
    Log-Message `"Downloading VHD from `$VHDUrl...`"
    Download-File `$VHDUrl `$vhdLocalPath
    Log-Message `"Download completed.`"

    Log-Message `"Extracting VHD...`"
    Extract-7z `$vhdLocalPath `$vhdExtractedPath
    if (-not (Test-Path `$vhdFilePath)) {
        throw `"Extraction failed or VHD file not found.`"
    }
    Log-Message `"Extraction completed.`"

    # Create the VM
    Log-Message `"Creating VM...`"
    VBoxManage createvm --name `$VMName --ostype `$OSType --register
    Log-Message `"VM created successfully.`"

    # Modify VM settings
    Log-Message `"Modifying VM settings...`"
    VBoxManage modifyvm `$VMName --memory `$MemorySize --cpus `$CPUs --nic1 nat
    Log-Message `"VM settings modified successfully.`"

    # Add storage controller
    Log-Message `"Adding storage controller...`"
    VBoxManage storagectl `$VMName --name `"SATA Controller`" --add sata --controller IntelAhci
    Log-Message `"Storage controller added successfully.`"

    # Attach the VHD
    Log-Message `"Attaching VHD...`"
    VBoxManage storageattach `$VMName --storagectl `"SATA Controller`" --port 0 --device 0 --type hdd --medium `$vhdFilePath
    Log-Message `"VHD attached successfully.`"

    # Configure boot order
    Log-Message `"Configuring boot order...`"
    VBoxManage modifyvm `$VMName --boot1 disk --boot2 none --boot3 none --boot4 none
    Log-Message `"Boot order configured successfully.`"

    # Start the VM
    Log-Message `"Starting VM...`"
    VBoxManage startvm `$VMName --type headless
    Log-Message `"VM started successfully.`"
}
catch {
    Log-Message `"An error occurred: `$_.Exception.Message`"
    throw
}

Log-Message `"Script execution completed successfully.`"
"@
    Set-Content -Path $outputPath -Value $scriptContent
}

# Laad de configuratie
$configFilePath = "C:\Users\stefa\hboict\HBOICT\Testing\config.json" # Pas dit pad aan naar de locatie van je JSON-bestand
$config = Load-Config -path $configFilePath

# GUI opzetten
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" 
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" 
        Title="VM Creation Tool" Height="200" Width="400">
    <Grid>
        <ComboBox Name="ModuleComboBox" HorizontalAlignment="Left" VerticalAlignment="Top" Width="360" Margin="10,10,0,0" />
        <Button Name="GenerateScriptButton" Content="Generate Script" HorizontalAlignment="Left" VerticalAlignment="Top" Width="360" Margin="10,50,0,0" />
    </Grid>
</Window>
"@

# XAML laden
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# ComboBox vullen
$comboBox = $window.FindName("ModuleComboBox")
$config.modules | ForEach-Object { $comboBox.Items.Add($_.module) }

# Event-handler voor de knop
$generateScriptButton = $window.FindName("GenerateScriptButton")
$generateScriptButton.Add_Click({
    $selectedModule = $comboBox.SelectedItem
    if ($selectedModule) {
        $moduleConfig = $config.modules | Where-Object { $_.module -eq $selectedModule }

        # Pad voor het gegenereerde script
        $scriptOutputPath = "C:\Users\stefa\hboict\GeneratedScript.ps1" # Pas dit pad aan indien nodig

        # Genereer het script
        Generate-Script $moduleConfig $scriptOutputPath

        [System.Windows.MessageBox]::Show("Script generated successfully at $scriptOutputPath.", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } else {
        [System.Windows.MessageBox]::Show("Please select a module.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})

# Toon de GUI
$window.ShowDialog() | Out-Null
