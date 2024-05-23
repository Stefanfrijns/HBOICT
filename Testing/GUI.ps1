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

# Laad de configuratie
$configFilePath = "C:\path\to\config.json"
$config = Load-Config -path $configFilePath

# GUI opzetten
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" 
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" 
        Title="VM Creation Tool" Height="200" Width="400">
    <Grid>
        <ComboBox Name="ModuleComboBox" HorizontalAlignment="Left" VerticalAlignment="Top" Width="360" Margin="10,10,0,0" />
        <Button Name="CreateVMButton" Content="Create VM" HorizontalAlignment="Left" VerticalAlignment="Top" Width="360" Margin="10,50,0,0" />
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
$createVMButton = $window.FindName("CreateVMButton")
$createVMButton.Add_Click({
    $selectedModule = $comboBox.SelectedItem
    if ($selectedModule) {
        $moduleConfig = $config.modules | Where-Object { $_.module -eq $selectedModule }

        # Roep het CreateVM.ps1 script aan met de juiste parameters
        $vmConfig = $moduleConfig.vm
        $scriptPath = "C:\path\to\CreateVM.ps1"
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -VMName `"$vmConfig.name`" -VHDPath `"$vmConfig.vhd_path`" -OSType `"$vmConfig.os_type`" -MemorySize $vmConfig.memory_size -CPUs $vmConfig.cpus" -Wait

        [System.Windows.MessageBox]::Show("VM '$($vmConfig.name)' created and started successfully for module '$selectedModule'.", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } else {
        [System.Windows.MessageBox]::Show("Please select a module.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})

# Toon de GUI
$window.ShowDialog() | Out-Null
