# Intune Autopilot Hardware Hash Collection - Deployment Guide

This guide explains how to deploy the Windows Autopilot hardware hash collection package to your managed devices using Intune.

## Overview

This package collects Windows Autopilot hardware hash information from managed devices and uploads it to Azure Blob Storage for device enrollment workflows. The package includes:

- **Install.ps1** - Main deployment script (runs as SYSTEM context)
- **Get-WindowsAutopilotInfo.ps1** - Autopilot info collection helper script
- **README.md** - Project documentation

## Prerequisites

- Devices managed by Intune
- Windows 10/11 Pro or higher
- Administrator/SYSTEM access on devices
- Azure Storage Account with SAS token for Blob access
- PowerShell execution policy allowing script execution

## Deployment Method 1: Win32 Application

### Overview

Deploying as a Win32 app packages the scripts into an `.intunewin` file and uses Intune's detection logic to verify successful execution. This is the **recommended method** for enterprise environments.

### Prerequisites

- Microsoft Intune Management Extension on target devices (auto-installed)
- Win32 app deployment permissions in Intune

### Step 1: Prepare the Package

1. Create a deployment folder on your local machine:
   ```
   C:\Intune-Deployment\
   ├── Install.ps1
   └── Get-WindowsAutopilotInfo.ps1
   ```

2. **Update configuration** in `Install.ps1`:
   - Replace `$storageAccount` with your Azure Storage Account name
   - Replace `$container` with your Blob container name
   - Replace `$blobName` with your desired path (e.g., `autopilot/all-devices.csv`)
   - Replace `$sas` with your SAS token which must begin with ?

### Step 2: Create the Win32 Package

1. Download the **Microsoft Win32 Content Prep Tool** from GitHub (microsoft/Microsoft-Win32-Content-Prep-Tool)

2. Run the tool:
   ```powershell
   .\IntuneWinAppUtil.exe -c C:\Intune-Deployment -s Install.ps1 -o C:\Output
   ```
   This creates `Install.intunewin` in the output folder.

### Step 3: Create the Intune Application

1. Sign into **Microsoft Intune admin center** (https://intune.microsoft.com)

2. Navigate to **Apps** > **All apps** > **New app** > **Windows app (Win32)**

3. **Upload app package**:
   - Click **Select file** and upload the `Install.intunewin` file

4. **Configure app information**:
   - **Name**: `Autopilot Hardware Hash Collection`
   - **Description**: `Collects device hardware hash for Autopilot enrollment`
   - **Publisher**: `Internal`
   - **Version**: `1.0.0`

5. **Configure program**:
   - **Installation command**: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1`
   - **Uninstall command**: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -Path 'C:\ProgramData\Autopilot' -Recurse -Force -ErrorAction SilentlyContinue; exit 0"`
   - **Install behavior**: `System`
   - **Device restart behavior**: `No specific action`

6. **Configure detection rule** (Critical for success tracking):
   - Click **Add** under "Detection rules"
   - **Rule type**: `Use a custom detection script`
   - **Script type**: `PowerShell`
   - **Run script in 64-bit PowerShell**: `Yes`
   - **Detection script**:
     ```powershell
     # Check if CSV was generated and uploaded marker exists
     $baseDir = "C:\ProgramData\Autopilot"
     if (Test-Path "$baseDir\AutopilotHash.csv") {
         Write-Host "Autopilot hash collected"
         exit 0
     } else {
         exit 1
     }
     ```

7. **Configure assignments**:
   - Click **Assignments** tab
   - **Add group**: Select target device group
   - **Intent**: `Required`
   - Click **Save**

8. Click **Create** to finalize the app.

### Monitoring Win32 Deployment

1. In Intune admin center, go to **Apps** > **All apps** > Select your app

2. View deployment status:
   - **Device and User check-in status** - Shows per-device success/failure
   - **Aggregated view** - Overall deployment health

3. For troubleshooting device logs:
   - On target device, check: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`

---

## Deployment Method 2: Intune Script

### Overview

Deploying as a remediation script or device configuration script is simpler but provides less robust deployment tracking. Use this method for rapid testing or smaller deployments.

### Prerequisites

- Azure AD joined or Hybrid Azure AD joined devices
- Intune management permissions
- PowerShell script deployment permission in Intune

### Step 1: Prepare the Script

1. **Update configuration** in `Install.ps1`:
   - Replace `$storageAccount` with your Azure Storage Account name
   - Replace `$container` with your Blob container name
   - Replace `$blobName` with your desired path
   - Replace `$sas` with your SAS token

2. **Combine into a single script** (Optional but recommended):
   - The Install.ps1 already includes embedded path logic for bundled scripts
   - Alternatively, you can concatenate both scripts into one file for simplicity

### Step 2: Deploy as a Remediation Script

1. Sign into **Microsoft Intune admin center** (https://intune.microsoft.com)

2. Navigate to **Devices** > **Compliance** > **Scripts** (or under **Endpoint Analytics** > **Remediation scripts**)

3. Click **Create** > **Remediation script**

4. **Configure script**:
   - **Name**: `Collect Autopilot Hardware Hash`
   - **Description**: `Gathers and uploads device hardware hash for Autopilot`
   - **Operating System**: `Windows`

5. **Upload detection script**:
   - Click **Edit** under Detection script
   - Paste the following:
     ```powershell
     # Detection script - Check if hash has been collected
     $baseDir = "C:\ProgramData\Autopilot"
     $markerFile = "$baseDir\uploaded"
     
     if (Test-Path "$baseDir\AutopilotHash.csv" -PathType Leaf) {
         exit 0  # Compliant - script ran successfully
     } else {
         exit 1  # Non-compliant - needs remediation
     }
     ```

6. **Upload remediation script**:
   - Click **Edit** under Remediation script
   - Paste the contents of your `Install.ps1` (with bundled script included or as single script)

7. **Configure deployment**:
   - **Run this script using the logged-in credentials**: `No` (runs as SYSTEM)
   - **Run script in 64-bit PowerShell**: `Yes`
   - **Enforce script signature check**: `No`

8. **Assign to groups**:
   - Click **Select groups**
   - Choose your target device groups
   - Click **Save**

9. Click **Create** to finalize the script.

### Alternative: Deploy via Device Management Scripts

For an alternative approach without compliance checks:

1. Navigate to **Devices** > **Scripts** (PowerShell scripts)

2. Click **Add** and upload your script

3. Configure **Execution context**: `System`

4. **Timeout**: `10 minutes` (or higher if needed)

5. Assign to device groups as needed

### Monitoring Script Deployment

1. In Intune admin center, go to **Devices** > **Scripts** (or Remediation scripts)

2. Select your script and view:
   - **Overview** - Last check-in status across devices
   - **Device and User check-in status** - Per-device results
   - **Execution status** - Compliance/remediation results

3. For device-side logs:
   - On target device, check event viewer: **Windows Logs** > **System** 
   - Look for entries from `Intune Management Extension`

---

## Configuration & Customization

### Storage Account Settings

Update these variables in `Install.ps1` to point to your Azure resources:

```powershell
$storageAccount = "your-storage-account"   # Without .blob.core.windows.net
$container      = "your-container"         # Blob container name
$blobName       = "autopilot/hash.csv"     # Path within container
$sas            = "?sv=2024-XX-XX&..."     # Full SAS token with leading ?
```

### Azure Storage Setup

1. Create a Storage Account in Azure portal

2. Create a Blob container (e.g., "hash")

3. Generate a **SAS token** with:
   - **Permissions**: `Add`, `Create`, `Write`
   - **Expiry**: 6+ months (adjust as needed)
   - **Allowed protocols**: `HTTPS`

4. Copy the full token including the leading `?`

### Output File Format

The script creates a CSV with the following columns:

```
UploadedUtc,ComputerName,Device Serial Number,Windows Product ID,Hardware Hash,Manufacturer name,Device model
```

**Example**:
```
2026-02-02T10:45:30.1234567Z,DESKTOP-XYZ123,"SN123456","","A2B3C4D5E6F7...",Dell,XPS 13
```

---

## Troubleshooting

### Script Fails to Run

**Symptom**: Script exits with error
- Check PowerShell execution policy: `Get-ExecutionPolicy`
- Verify Intune Management Extension is installed
- Check C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ for errors

### Azure Upload Fails

**Symptom**: Hardware hash not appearing in Blob Storage
- Verify storage account name, container, and SAS token are correct
- Check SAS token hasn't expired
- Confirm SAS token has `Add`, `Create`, `Write` permissions
- Test connectivity to Azure: `Invoke-WebRequest -Uri "https://<account>.blob.core.windows.net"`

### Detection Script Doesn't Work

**Symptom**: Win32 app shows "Not applicable" for all devices
- Verify detection script is valid PowerShell (test locally first)
- Ensure the detection condition exists before assigning the app
- Check that installation paths match what the detection script checks

### Device Shows "Not Compliant" (Remediation Scripts)

**Symptom**: Script keeps showing non-compliant after running
- Verify detection script properly checks for success markers
- Ensure remediation script is returning `exit 0` on success
- Check target device can reach Azure Storage endpoint
- Review script execution logs on device



## Additional Resources

- [Intune Win32 app management](https://docs.microsoft.com/en-us/mem/intune/apps/app-management)
- [Intune device configuration scripts](https://docs.microsoft.com/en-us/mem/intune/configuration/powershell-scripts)
- [Windows Autopilot hardware hash collection](https://docs.microsoft.com/en-us/windows/deployment/windows-autopilot/overview)
- [Azure Storage SAS tokens](https://docs.microsoft.com/en-us/azure/storage/common/storage-sas-overview)
