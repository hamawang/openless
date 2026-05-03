param(
  [ValidateSet("Debug", "Release")]
  [string]$Configuration = "Release",
  [string]$OutputDirectory = "",
  [string]$IntermediateDirectory = ""
)

$ErrorActionPreference = "Stop"

function Find-MSBuild {
  $cmd = Get-Command MSBuild.exe -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $vswhere) {
    $found = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\Current\Bin\MSBuild.exe" 2>$null |
      Select-Object -First 1
    if ($found -and (Test-Path $found)) {
      return $found
    }
  }

  $candidates = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "MSBuild.exe not found. Install Visual Studio Build Tools or run from Developer PowerShell."
}

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$solution = Join-Path $appRoot "windows-ime\OpenLessIme.sln"
$dll = Join-Path $appRoot "windows-ime\x64\$Configuration\OpenLessIme.dll"
$msbuild = Find-MSBuild
$msbuildArgs = @($solution, "/p:Configuration=$Configuration", "/p:Platform=x64")

function Get-FullPathWithTrailingSlash($Path) {
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if (-not $fullPath.EndsWith("\")) {
    return "$fullPath\"
  }
  return $fullPath
}

if (-not (Test-Path $solution)) {
  throw "Solution not found: $solution"
}

Write-Host "[build] $Configuration x64"
if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $outputDirectoryPath = Get-FullPathWithTrailingSlash $OutputDirectory
  New-Item -ItemType Directory -Force -Path $outputDirectoryPath | Out-Null
  $msbuildArgs += "/p:OutDir=$outputDirectoryPath"
  $dll = Join-Path $outputDirectoryPath "OpenLessIme.dll"
}

if (-not [string]::IsNullOrWhiteSpace($IntermediateDirectory)) {
  $intermediateDirectoryPath = Get-FullPathWithTrailingSlash $IntermediateDirectory
  New-Item -ItemType Directory -Force -Path $intermediateDirectoryPath | Out-Null
  $msbuildArgs += "/p:IntDir=$intermediateDirectoryPath"
}

& $msbuild @msbuildArgs
if ($LASTEXITCODE -ne 0) {
  throw "OpenLessIme build failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $dll)) {
  throw "OpenLessIme.dll was not produced: $dll"
}

Write-Host "[ok] $dll"
