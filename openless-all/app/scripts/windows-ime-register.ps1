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

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dll = Join-Path $appRoot "windows-ime\x64\$Configuration\OpenLessIme.dll"

if (-not (Test-Path $dll)) {
  & (Join-Path $PSScriptRoot "windows-ime-build.ps1") -Configuration $Configuration
}

$regsvr32 = Get-Regsvr32x64
& $regsvr32 /s $dll
if ($LASTEXITCODE -ne 0) {
  throw "regsvr32 failed with exit code $LASTEXITCODE"
}

Write-Host "[ok] OpenLess TSF IME registered"
