param(
    [ValidateSet('Download','Install','Both')]
    [string]$Action,

    [string]$Path
)

<#
.SYNOPSIS
  Download & install all Microsoft.Graph sub-modules via direct HTTP + retry/backoff.

.DESCRIPTION
  This script downloads Microsoft.Graph modules and their dependencies from the PowerShell Gallery,
  and installs them from a local repository. It supports environments with unreliable internet or DNS.
#>


# Prompt for action if not provided
if (-not $Action) {
    Write-Host "`nChoose an action:"
    Write-Host "[1] Download only"
    Write-Host "[2] Install only"
    Write-Host "[3] Both download and install"
    $choice = Read-Host "Enter your choice (1-3)"
    switch ($choice) {
        '1' { $Action = 'Download' }
        '2' { $Action = 'Install' }
        '3' { $Action = 'Both' }
        default {
            Write-Error "Invalid choice. Exiting."
            exit 1
        }
    }
}

# Prompt for path if not provided
if (-not $Path) {
    $Path = Read-Host "Enter the folder path to use for downloading/storing modules"
}

# Ensure output folder exists
if (-not (Test-Path $Path)) {
    New-Item -Path $Path -ItemType Directory | Out-Null
}

# Check for admin rights
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning "This script must be run as Administrator to install all modules correctly."
    Write-Warning "Please right-click PowerShell and choose 'Run as Administrator'."
    exit 1
}

# Initialize the module tracking hashtable
$DownloadedModules = @{}


#-------------------------------------------------
# Helper: retry any Invoke-WebRequest until it succeeds
#-------------------------------------------------
function Retry-Http {
    param(
        [ScriptBlock]$Call,
        [int]$DelaySeconds = 10
    )
    while ($true) {
        try {
            return & $Call
        }
        catch {
            Write-Warning ("HTTP error: {0}`nRetrying in {1}s…" -f $_.Exception.Message, $DelaySeconds)
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

#-------------------------------------------------
# Fetch module metadata from PSGallery OData
#-------------------------------------------------
function Get-PackageEntry {
    param([string]$Id)

    $url = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='$Id'"
    $resp = Retry-Http { Invoke-WebRequest -UseBasicParsing -Uri $url }
    return [xml]$resp.Content
}

#-------------------------------------------------
# Recursively download module + its dependencies
#-------------------------------------------------
$Downloaded = @{}
function Download-ModuleAndDeps {
  param(
    [string]$Id,
    [string]$Version = ''
  )

  # 1) Resolve latest version if not given
  if (-not $Version) {
    $entry   = Get-PackageEntry -Id $Id
    $Version = $entry.feed.entry[0].properties.'d:Version'
  }

  $key = "$Id.$Version"
  if ($Downloaded[$key]) { return }
  $Downloaded[$key] = $true

  # 2) Download the .nupkg (root and sub-modules alike)
  $nupkg = Join-Path $Path "$Id.$Version.nupkg"
  if (-not (Test-Path $nupkg)) {
    Write-Host "Downloading $Id v$Version..."
    $dlUrl = "https://www.powershellgallery.com/api/v2/package/$Id/$Version"
    Retry-Http { Invoke-WebRequest -UseBasicParsing -Uri $dlUrl -OutFile $nupkg }
  }
  else {
    Write-Host "Already downloaded: $Id v$Version"
  }

  # 3) Unpack its .nuspec to determine dependencies
  $temp = Join-Path $env:TEMP "GraphDep_${Id}_$Version"
  Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive -Path $nupkg -DestinationPath $temp -Force

  $nuspec = Get-ChildItem -Path $temp -Filter '*.nuspec' -Recurse | Select-Object -First 1
  $xml    = [xml](Get-Content $nuspec.FullName)

  foreach ($d in $xml.package.metadata.dependencies.dependency) {
    # pick the single-version in a range like "[2.28.0]"  
    $ver = ($d.version -split '[\[\]\(\),]') | Where-Object { $_ -match '^\d+\.\d+\.\d+$' }
    Download-ModuleAndDeps -Id $d.id -Version $ver
  }

  Remove-Item $temp -Recurse -Force
}

#-------------------------------------------------
# Initialize the NuGet Feed with our packages:
#-------------------------------------------------

function Initialize-NuGetFeed {
    param (
        [string]$SourcePath,
        [string]$FeedPath,
        [string]$NuGetExePath = "$env:TEMP\nuget.exe"
    )

    Write-Host "=== Entered Initialize-NuGetFeed ==="
    Write-Host "Source: $SourcePath"
    Write-Host "Feed:   $FeedPath"

    # Step 1: Download nuget.exe if needed
    if (-not (Test-Path $NuGetExePath)) {
        Write-Host "Downloading nuget.exe with retry logic..."
        Retry-Http {
            Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $NuGetExePath -UseBasicParsing
        }
    }


    # Step 2: Clean feed folder
    if (Test-Path $FeedPath) {
        Write-Host "Cleaning existing feed folder: $FeedPath"
        Remove-Item -Path "$FeedPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Path $FeedPath | Out-Null
    }

    # Step 3: Copy .nupkg files
    Get-ChildItem -Path $SourcePath -Filter *.nupkg | ForEach-Object {
        Copy-Item $_.FullName -Destination $FeedPath -Force
    }

    # Step 4: Run nuget init with output capture
    Write-Host "Initializing NuGet feed at $FeedPath..."
    $initOutput = & $NuGetExePath init "`"$FeedPath`"" "`"$FeedPath`"" -Expand -ForceEnglishOutput -Verbosity detailed 2>&1
    Write-Host "NuGet init output:`n$initOutput"
}




#-------------------------------------------------
# Install every downloaded .nupkg into selected PSModulePath
#-------------------------------------------------
function Install-AllModules {
    param(
        [Parameter(Mandatory)]
        [hashtable]$DownloadedModules
    )

    if ($DownloadedModules.Count -eq 0) {
        Write-Host "Rebuilding module list from .nupkg files in $Path..."
        Get-ChildItem -Path $Path -Filter '*.nupkg' | ForEach-Object {
            $file = $_.BaseName
            $parts = $file -split '\.'
            if ($parts.Length -ge 4) {
                $version = $parts[-3..-1] -join '.'
                $name    = $parts[0..($parts.Length - 4)] -join '.'
                $DownloadedModules["$name.$version"] = $true
            } else {
                Write-Warning "Unexpected filename format: $file"
            }
        }
    }


    $paths = $env:PSModulePath -split ';'
    Write-Host "`nAvailable PSModulePath entries:"
    for ($i = 0; $i -lt $paths.Length; $i++) {
        Write-Host "[$i] $($paths[$i])"
    }

    $selection = Read-Host "Enter the number of the path to use for module installation"
    if ($selection -notmatch '^\d+$' -or [int]$selection -ge $paths.Length) {
        Write-Error "Invalid selection. Aborting."
        return
    }

    $installPath = $paths[$selection]
    Write-Host "`nUsing path: $installPath"

    # Step 2: Prepare local repo structure
    $repoName = 'LocalGraph'
    $repoPath = Join-Path $installPath 'LocalGraphRepo'


    foreach ($key in $DownloadedModules.Keys) {
        $parts = $key -split '\.'

        if ($parts.Length -ge 4) {
            $version = $parts[-3..-1] -join '.'
            $name    = $parts[0..($parts.Length - 4)] -join '.'
        } else {
            Write-Warning "Unexpected key format: $key"
            continue
        }


        if ($name -eq 'Microsoft.Graph') {
            Write-Host "Skipping meta-package Microsoft.Graph"
            continue
        }

        $nupkg = Join-Path $Path "$name.$version.nupkg"
        $dest  = Join-Path $repoPath "$name\$version"

        if (-not (Test-Path $nupkg)) {
            Write-Warning "Expected .nupkg file not found: $nupkg"
            continue
        }

        Write-Host "Preparing to extract $nupkg to $dest..."

        try {
            if (-not (Test-Path $dest)) {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
            }

            Expand-Archive -Path $nupkg -DestinationPath $dest -Force
            Write-Host "Successfully extracted $name v$version to $dest"
        }
        catch {
            Write-Warning ("Failed to extract " + $nupkg + " : " + $($_.Exception.Message))
        }
    }

        # Build NuGet feed from .nupkg files
    Initialize-NuGetFeed -SourcePath $Path -FeedPath $repoPath

    # Register the feed
    if (-not (Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Name $repoName -SourceLocation $repoPath -InstallationPolicy Trusted
    } else {
        Set-PSRepository -Name $repoName -SourceLocation $repoPath -InstallationPolicy Trusted
    }

    if (-not (Test-Path $repoPath)) {
        New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
    }


    if (-not (Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Name $repoName -SourceLocation $repoPath -InstallationPolicy Trusted
    } else {
        Set-PSRepository -Name $repoName -InstallationPolicy Trusted
    }

    foreach ($key in $DownloadedModules.Keys) {
        $parts = $key -split '\.'

        if ($parts.Length -ge 4) {
            $version = $parts[-3..-1] -join '.'
            $name    = $parts[0..($parts.Length - 4)] -join '.'
        } else {
            Write-Warning "Unexpected key format: $key"
            continue
        }


        Write-Host "Installing module '$name' version '$version'..."
        try {
            Install-Module -Name $name -RequiredVersion $version -Repository $repoName -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "Module '$name' v$version installed successfully."
        } catch {
            $errMsg = $_.Exception.Message
            Write-Warning ("Failed to install {0} v{1}: {2}" -f $name, $version, $errMsg)
        }
    }

    Write-Host "`nInstall-AllModules complete. Modules installed to: $installPath"
}

#-------------------------------------------------
# Main Execution
#-------------------------------------------------
# -- main

# Download Only
if ($Action -in 'Download') {
  Write-Host "`n==> Download Phase`n"
  Download-ModuleAndDeps -Id 'Microsoft.Graph'
  Write-Host "`nDownload complete. Packages in $Path`n"
}

# Install Only
if ($Action -in 'Install') {
  Write-Host "`n==> Install Phase`n"
  Install-AllModules -DownloadedModules $DownloadedModules
  Write-Host "`nInstall complete. Modules in $((($env:PSModulePath -split ';')[0]))`n"
}

# Download and Install
if ($Action -in 'Both') {
  Write-Host "`n==> Download Phase`n"
  Download-ModuleAndDeps -Id 'Microsoft.Graph'
  Write-Host "`nDownload complete. Packages in $Path`n"
  Write-Host "`n==> Install Phase`n"
  Install-AllModules -DownloadedModules $DownloadedModules
  Write-Host "`nInstall complete. Modules in $((($env:PSModulePath -split ';')[0]))`n"
}
