# Install.ps1
# Runs as SYSTEM via Intune Win32 app
# Bundled script: $PSScriptRoot\Get-WindowsAutopilotInfo.ps1
<#
.SYNOPSIS
    Collects Windows Autopilot device hash and uploads to Azure Blob Storage.
.DESCRIPTION
    This script generates the Windows Autopilot device hash CSV using the bundled
    Get-WindowsAutopilotInfo.ps1 script, then uploads the data to an Azure Blob Storage
    Append Blob. It tracks uploads per-device using a local marker file to avoid duplicate
    uploads for the same device.
.PARAMETER storageAccount
    The name of the Azure Storage Account (without .blob.core.windows.net).
.PARAMETER container
    The name of the Blob Container to upload to.
.PARAMETER blobName
    The name of the Append Blob to upload data to.
.PARAMETER sas
    The SAS token for accessing the Blob Storage (including leading '?').
.NOTES
    Author: Peter Opeyemi James
    Date:   2026-02-02
    Version:1.0
#>

$ErrorActionPreference = "Stop"

# ====== Settings (EDIT THESE) ======
$storageAccount = "<YOUR_STORAGE_ACCOUNT_NAME>"
$container      = "<YOUR_CONTAINER_NAME>"
$blobName       = "autopilot/all-devices.csv"
$sas            = "<YOUR_SAS_TOKEN_HERE>"  # e.g. "?sv=2024-11-04&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2026-02-28T18:56:20Z&st=2026-02-02T10:41:20Z&spr=https&sig=..."
# ==================================

# Local working paths
$baseDir    = "C:\ProgramData\Autopilot"
$uploadDir  = Join-Path $baseDir "uploaded"
$localCsv   = Join-Path $baseDir "AutopilotHash.csv"

New-Item -ItemType Directory -Path $baseDir   -Force | Out-Null
New-Item -ItemType Directory -Path $uploadDir -Force | Out-Null

# Resolve bundled script
$apScript = Join-Path $PSScriptRoot "Get-WindowsAutopilotInfo.ps1"
if (-not (Test-Path $apScript)) { throw "Bundled script not found: $apScript" }

# Generate Autopilot CSV
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $apScript -OutputFile $localCsv

if (-not (Test-Path $localCsv)) { throw "Autopilot CSV not created at $localCsv" }

# Import CSV robustly and extract serial
$obj = Import-Csv -Path $localCsv | Select-Object -First 1
if (-not $obj) { throw "Autopilot CSV contained no rows" }

# Try multiple possible column names (PowerShell 5.1 compatible)
$serial = $null
if ($obj.'Device Serial Number') {
    $serial = $obj.'Device Serial Number'
} elseif ($obj.'Serial Number') {
    $serial = $obj.'Serial Number'
} elseif ($obj.SerialNumber) {
    $serial = $obj.SerialNumber
}

if (-not $serial -or [string]::IsNullOrWhiteSpace($serial)) {
    # Fallback to BIOS serial if CSV headers differ
    $serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
}

if (-not $serial -or [string]::IsNullOrWhiteSpace($serial)) {
    throw "Unable to determine device serial number."
}

# Build per-serial marker path (sanitize filename)
$serialSafe = ($serial -replace '[\\/:*?"<>|]', '_').Trim()
$markerPath = Join-Path $uploadDir "$serialSafe.uploaded"

# If already uploaded for this serial, skip
if (Test-Path $markerPath) {
    exit 0
}

# Read header + data row to build single-line payload
$lines = Get-Content -Path $localCsv -Encoding UTF8
if ($lines.Count -lt 2) { throw "CSV did not contain a data row" }

$header = $lines[0].Trim()
$row = $lines[1].Trim()

# Add tracking columns
$timestamp = (Get-Date).ToString("o")
$computer  = $env:COMPUTERNAME

# Blob URIs
$baseUri   = "https://$storageAccount.blob.core.windows.net/$container/$blobName$sas"
$appendUri = $baseUri + "&comp=appendblock"

# Check if blob exists
$blobExists = $false
try {
    $response = Invoke-WebRequest -Uri $baseUri -Method Head -Headers @{
        "x-ms-version" = "2020-10-02"
    } -UseBasicParsing
    $blobExists = $true
} catch {
    # Blob doesn't exist
    $blobExists = $false
}

# If blob doesn't exist, create it with header
if (-not $blobExists) {
    # Create Append Blob
    Invoke-RestMethod -Uri $baseUri -Method Put -Headers @{
        "x-ms-blob-type" = "AppendBlob"
        "x-ms-version"   = "2020-10-02"
    } | Out-Null
    
    # Write header row with tracking columns
    $headerWithTracking = '"UploadTimestamp","ComputerName",' + $header + "`n"
    Invoke-RestMethod -Uri $appendUri -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($headerWithTracking)) -Headers @{
        "x-ms-version" = "2020-10-02"
    } -ContentType "text/plain" | Out-Null
}

# Build data row with tracking columns
$prefix = '"' + $timestamp.Replace('"','""') + '","' + $computer.Replace('"','""') + '",'
$finalRow = $prefix + $row.TrimStart()
$payload  = ($finalRow + "`n")

# Append data row
Invoke-RestMethod -Uri $appendUri -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -Headers @{
    "x-ms-version" = "2020-10-02"
} -ContentType "text/plain" | Out-Null

# Write marker ONLY after successful append
$markerContent = @(
    "UploadedUtc=$([DateTime]::UtcNow.ToString('o'))"
    "Serial=$serial"
    "ComputerName=$computer"
    "Blob=$container/$blobName"
) -join "`r`n"

Set-Content -Path $markerPath -Value $markerContent -Encoding UTF8 -Force

exit 0
