# Install-LocalNupkgModule.ps1
Workaround for persistent network issues while attempting to download and install powershell modules.

This PowerShell script simplifies the process of installing a PowerShell module from a `.nupkg` file. It extracts the module, installs it to the user's local module path, and imports it for immediate use.

## 🛠Features

- Prompts for the path to a `.nupkg` file  
- Validates the file exists  
- Extracts module name and version from the filename  
- Unpacks the `.nupkg` archive  
- Installs the module to the user's PowerShell module directory  
- Imports the module and verifies installation  

## Prerequisites

- PowerShell 5.1 or later  
- The `.nupkg` file must follow the naming convention: `ModuleName.Version.nupkg`  
  - Example: `MyModule.1.0.0.nupkg`

## Usage

1. Open PowerShell.
2. Run the script.
3. When prompted, enter the full path to the `.nupkg` file:

```powershell
Enter the full path to the downloaded .nupkg file: C:\Path\To\YourModule.1.0.0.nupkg
```

The script will:

- Extract the .nupkg file to a temporary directory
- Copy the module files to your PowerShell modules folder
- Import the module
- Display the installed module details

# Installation Path

Modules are installed to:

```powershell
$env:USERPROFILE\Documents\WindowsPowerShell\Modules
```

# Example Output

```powershell
Extracting package...
Installing module to C:\Users\YourName\Documents\WindowsPowerShell\Modules\YourModule...
Importing module...
Installed modules:

    Directory: C:\Users\YourName\Documents\WindowsPowerShell\Modules

ModuleType Version    Name        ExportedCommands
---------- -------    ----        ----------------
Script     1.0.0      YourModule  {Get-YourCommand, Set-YourCommand}
```

# Notes

- Ensure the .nupkg file is not corrupted and follows the expected naming format.
- The script uses Expand-Archive, which is available in PowerShell 5.1+.
