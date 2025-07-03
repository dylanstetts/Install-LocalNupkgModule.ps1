# Prompt for the path to the downloaded .nupkg file
$packagePath = Read-Host "Enter the full path to the downloaded .nupkg file"

# Validate the file exists
if (-Not (Test-Path $packagePath)) {
    Write-Error "File not found at path: $packagePath"
    return
}

# Extract module name and version using regex
$packageName = [System.IO.Path]::GetFileNameWithoutExtension($packagePath)
if ($packageName -match "^(?<name>.+)\.(?<version>\d+\.\d+\.\d+)$") {
    $moduleName = $matches['name']
    $moduleVersion = $matches['version']
} else {
    Write-Error "Could not parse module name and version from file name: $packageName"
    return
}

# Define paths
$extractPath = "$env:TEMP\$moduleName"
$moduleInstallPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\$moduleName"

# Extract the .nupkg file
Write-Host "Extracting package..."
Expand-Archive -Path $packagePath -DestinationPath $extractPath -Force

# Create module directory and move files
Write-Host "Installing module to $moduleInstallPath..."
New-Item -ItemType Directory -Path $moduleInstallPath -Force | Out-Null
Copy-Item -Path "$extractPath\*" -Destination $moduleInstallPath -Recurse -Force

# Import the module
Write-Host "Importing module..."
Import-Module $moduleName -Force

# Verify installation
Write-Host "Installed modules:"
Get-Module $moduleName -ListAvailable
