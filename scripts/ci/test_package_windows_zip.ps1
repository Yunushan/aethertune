[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_runtime.ps1')

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$root = Join-Path $temporaryRoot "aethertune-windows-package-$([guid]::NewGuid())"
$bundle = Join-Path $root 'bundle'
$archivePath = Join-Path $root 'release/aethertune-windows-x64.zip'
$packageScript = Join-Path $PSScriptRoot 'package_windows_zip.ps1'

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'data') | Out-Null
  # A real x64 PE fixture exercises import inspection; it is never executed.
  Copy-Item -LiteralPath (Join-Path (Find-WindowsRuntimeDirectory) 'vcruntime140.dll') -Destination (Join-Path $bundle 'aethertune.exe')
  [System.IO.File]::WriteAllText((Join-Path $bundle 'data/icudtl.dat'), 'fixture')

  & $packageScript -BundlePath $bundle -OutputPath $archivePath

  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw 'The Windows ZIP package was not created.'
  }
  $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
  try {
    foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'aethertune-windows-runtime.json', 'aethertune-windows-native.json')) {
      if ($null -eq $archive.GetEntry($name)) { throw "ZIP is missing $name." }
      if (Test-Path -LiteralPath (Join-Path $bundle $name)) { throw 'Packaging modified its input bundle.' }
    }
  } finally { $archive.Dispose() }
} finally {
  if ((Split-Path -Parent ([System.IO.Path]::GetFullPath($root))).TrimEnd('\') -ne $temporaryRoot.TrimEnd('\') -or
      (Split-Path -Leaf $root) -notmatch '^aethertune-windows-package-[0-9a-f-]{36}$') {
    throw 'Refusing to remove an unexpected ZIP test directory.'
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
