[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_runtime.ps1')

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$root = Join-Path $temporaryRoot "aethertune-windows-msix-$([guid]::NewGuid())"
$bundle = Join-Path $root 'bundle'
$packagePath = Join-Path $root 'release/aethertune-windows-x64.msix'
$packageScript = Join-Path $PSScriptRoot 'package_windows_msix.ps1'

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'data/flutter_assets') | Out-Null
  Copy-Item -LiteralPath (Join-Path (Find-WindowsRuntimeDirectory) 'vcruntime140.dll') -Destination (Join-Path $bundle 'aethertune.exe')
  [System.IO.File]::WriteAllText(
    (Join-Path $bundle 'data/flutter_assets/AssetManifest.bin'),
    'fixture asset manifest'
  )

  & $packageScript -BundlePath $bundle -OutputPath $packagePath -Version '0.1.0+1'

  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw 'The Windows MSIX package was not created.'
  }
  $archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
  try {
    foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'aethertune-windows-runtime.json', 'aethertune-windows-native.json')) {
      if ($null -eq $archive.GetEntry("VFS/ProgramFilesX64/AetherTune/$name")) { throw "MSIX is missing $name." }
      if (Test-Path -LiteralPath (Join-Path $bundle $name)) { throw 'Packaging modified its input bundle.' }
    }
  } finally { $archive.Dispose() }
} finally {
  if ((Split-Path -Parent ([System.IO.Path]::GetFullPath($root))).TrimEnd('\') -ne $temporaryRoot.TrimEnd('\') -or
      (Split-Path -Leaf $root) -notmatch '^aethertune-windows-msix-[0-9a-f-]{36}$') {
    throw 'Refusing to remove an unexpected MSIX test directory.'
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
