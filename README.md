# Install-LocalGraphModule.ps1

## Overview

This PowerShell script downloads and installs all Microsoft.Graph sub-modules from the PowerShell Gallery using direct HTTP requests with retry logic. It is designed for environments with unreliable internet or DNS resolution issues.

## Features

- Recursively downloads Microsoft.Graph modules and their dependencies
- Retries failed HTTP requests (e.g., due to DNS failures)
- Builds a local NuGet-compatible repository from `.nupkg` files
- Installs modules from the local feed using `Install-Module`
- Supports `Download`, `Install`, or `Both` modes
- Prompts for `PSModulePath` selection
- Validates administrator privileges before installation

## Usage

```powershell
# Download and install modules
.\Install-LocalGraphModule.ps1 -Action Both -Path "C:\GraphModules"

# Download only
.\Install-LocalGraphModule.ps1 -Action Download -Path "C:\GraphModules"

# Install only (from previously downloaded .nupkg files)
.\Install-LocalGraphModule.ps1 -Action Install -Path "C:\GraphModules"
```

## Requirements

- PowerShell 5.1 or later
- Internet access (for downloading modules and nuget.exe)
- Administrator privileges (for installing modules globally)

## Notes

- The script uses nuget.exe to build a local feed. It will download it automatically if not present.
- The script skips the Microsoft.Graph meta-package intentionally.

## Troubleshooting

- If modules fail to install, ensure the .nupkg files are valid and the feed is correctly initialized.
- Use -Verbose to see detailed output during execution.
