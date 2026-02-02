# Get-WindowsAutopilotInfo.ps1
# Collects Windows Autopilot hardware hash and outputs to CSV
# Based on Get-WindowsAutopilotInfo from PowerShell Gallery

param(
    [Parameter(Mandatory = $true)]
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

# Ensure output directory exists
$outDir = Split-Path -Path $OutputFile -Parent
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# Get device information
$session = New-CimSession
$serial = (Get-CimInstance -CimSession $session -ClassName Win32_BIOS).SerialNumber
$devDetail = (Get-CimInstance -CimSession $session -Namespace root/cimv2/mdm/dmmap -ClassName MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")

if ($devDetail) {
    $hash = $devDetail.DeviceHardwareData
} else {
    throw "Unable to retrieve hardware hash. Ensure script runs with admin privileges."
}

# Get computer info
$cs = Get-CimInstance -CimSession $session -ClassName Win32_ComputerSystem
$manufacturer = $cs.Manufacturer.Trim()
$model = $cs.Model.Trim()

Remove-CimSession $session

# Build CSV output
$csvData = [PSCustomObject]@{
    'Device Serial Number' = $serial
    'Windows Product ID'   = ''
    'Hardware Hash'        = $hash
    'Manufacturer name'    = $manufacturer
    'Device model'         = $model
}

# Export to CSV
$csvData | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Host "Autopilot hardware hash exported to: $OutputFile"