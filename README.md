# Windows Autopilot Hardware Hash Collection

Intune deployment package for collecting and uploading device hardware hashes to Azure Blob Storage for Windows Autopilot enrollment workflows.

## What's Included

- **Install.ps1** - Main deployment script (runs as SYSTEM)
- **Get-WindowsAutopilotInfo.ps1** - Hardware hash collection helper
- **DEPLOYMENT_GUIDE.md** - Complete deployment instructions

## Quick Start

1. Update Azure Storage settings in `Install.ps1`:
   - `$storageAccount` - Your storage account name
   - `$container` - Blob container name
   - `$blobName` - CSV path in container
   - `$sas` - SAS token with Add/Create/Write permissions

2. Choose deployment method:
   - **Win32 App** (recommended for enterprise) - See DEPLOYMENT_GUIDE.md for full instructions
   - **Intune Script** (simpler, faster) - See DEPLOYMENT_GUIDE.md for full instructions

## Requirements

- Windows 10/11 Pro or higher
- Intune management
- Azure Storage Account with SAS token
- PowerShell execution allowed

## Documentation

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed deployment instructions, troubleshooting, and best practices.

## Author
Peter Opeyemi James
02/02/2026