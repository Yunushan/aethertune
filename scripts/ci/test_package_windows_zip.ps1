[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Join-Path ([System.IO.Path]::GetTempPath()) "aethertune-windows-package-$([guid]::NewGuid())"
$bundle = Join-Path $root 'bundle'
$archivePath = Join-Path $root 'release/aethertune-windows-x64.zip'
$packageScript = Join-Path $PSScriptRoot 'package_windows_zip.ps1'

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'data') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $bundle 'aethertune.exe'), 'fixture')
  [System.IO.File]::WriteAllText((Join-Path $bundle 'data/icudtl.dat'), 'fixture')

  & $packageScript -BundlePath $bundle -OutputPath $archivePath

  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw 'The Windows ZIP package was not created.'
  }
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
