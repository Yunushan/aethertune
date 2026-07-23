[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Join-Path ([System.IO.Path]::GetTempPath()) "aethertune-windows-msix-$([guid]::NewGuid())"
$bundle = Join-Path $root 'bundle'
$packagePath = Join-Path $root 'release/aethertune-windows-x64.msix'
$packageScript = Join-Path $PSScriptRoot 'package_windows_msix.ps1'

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'data/flutter_assets') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $bundle 'aethertune.exe'), 'fixture')
  [System.IO.File]::WriteAllText(
    (Join-Path $bundle 'data/flutter_assets/AssetManifest.bin'),
    'fixture asset manifest'
  )

  & $packageScript -BundlePath $bundle -OutputPath $packagePath -Version '0.1.0+1'

  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw 'The Windows MSIX package was not created.'
  }
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
