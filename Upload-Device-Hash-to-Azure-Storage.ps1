# Install.ps1
# Runs as SYSTEM via Intune Win32 app
# Bundled script: $PSScriptRoot\Get-WindowsAutopilotInfo.ps1
<#
.Tested-With:
    - SAS: sv=2024-11-04&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2026-02-28T18:56:20Z&st=2026-02-02T10:41:20Z&spr=https&sig=vYQr3Ao%2B11KaijlEW51VhxbN27y5v83bEU1px%2BIcB6U%3D
    - Storage account: testingstract
    - Container: hash
#>

$ErrorActionPreference = "Stop"

# ====== Settings (EDIT THESE) ======
$storageAccount = "testingstract"
$container      = "hash"
$blobName       = "autopilot/all-devices.csv"
$sas            = "?sv=2024-11-04&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2026-02-28T18:56:20Z&st=2026-02-02T10:41:20Z&spr=https&sig=vYQr3Ao%2B11KaijlEW51VhxbN27y5v83bEU1px%2BIcB6U%3D"
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

$serial =
    $obj.'Device Serial Number' ??
    $obj.'Serial Number' ??
    $obj.SerialNumber

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

$row = $lines[1].Trim()

# Add tracking columns
$timestamp = (Get-Date).ToString("o")
$computer  = $env:COMPUTERNAME

$prefix = '"' + $timestamp.Replace('"','""') + '","' + $computer.Replace('"','""') + '",'
$finalRow = $prefix + $row.TrimStart()
$payload  = ($finalRow + "`n")

# Blob URIs
$baseUri   = "https://$storageAccount.blob.core.windows.net/$container/$blobName$sas"
$appendUri = $baseUri + "&comp=appendblock"

# Create Append Blob if missing
try {
    Invoke-RestMethod -Uri $baseUri -Method Put -Headers @{
        "x-ms-blob-type" = "AppendBlob"
        "x-ms-version"   = "2020-10-02"
    } | Out-Null
} catch {
    # 409 = already exists (fine)
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -ne 409) { throw }
}

# Append row
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
