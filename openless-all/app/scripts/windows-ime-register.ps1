param(
  [ValidateSet("Debug", "Release")]
  [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

function Get-Regsvr32x64 {
  $sysnative = Join-Path $env:WINDIR "Sysnative\regsvr32.exe"
  if (Test-Path $sysnative) {
    return $sysnative
  }
  return (Join-Path $env:WINDIR "System32\regsvr32.exe")
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dll = Join-Path $appRoot "windows-ime\x64\$Configuration\OpenLessIme.dll"

if (-not (Test-Path $dll)) {
  & (Join-Path $PSScriptRoot "windows-ime-build.ps1") -Configuration $Configuration
}

if (-not (Test-IsAdministrator)) {
  throw "Registering the OpenLess TSF IME requires an elevated Administrator PowerShell."
}

$regsvr32 = Get-Regsvr32x64
$process = Start-Process -FilePath $regsvr32 -ArgumentList @("/s", $dll) -Wait -PassThru
if ($process.ExitCode -ne 0) {
  throw "regsvr32 failed with exit code $($process.ExitCode)"
}

Write-Host "[ok] OpenLess TSF IME registered"
