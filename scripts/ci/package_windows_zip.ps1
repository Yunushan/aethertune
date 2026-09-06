[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath,
  [Parameter(Mandatory = $true)]
  [string]$OutputPath,
  [string]$RuntimeDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_native_dependencies.ps1')

$bundle = Resolve-Path -LiteralPath $BundlePath
$executablePath = Join-Path $bundle.Path 'aethertune.exe'
$dataPath = Join-Path $bundle.Path 'data'

if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
  throw "Expected a Windows Flutter bundle containing aethertune.exe at $executablePath."
}

if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) {
  throw "Expected a Windows Flutter bundle containing a data directory at $dataPath."
}

$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Remove-Item -LiteralPath $resolvedOutputPath -Force -ErrorAction SilentlyContinue

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$stagingRoot = Join-Path $temporaryRoot "aethertune-zip-$([guid]::NewGuid())"
try {
  New-Item -ItemType Directory -Path $stagingRoot | Out-Null
  Copy-Item -Path (Join-Path $bundle.Path '*') -Destination $stagingRoot -Recurse -Force
  Add-WindowsRuntimeFiles -DestinationPath $stagingRoot -RuntimeDirectory $RuntimeDirectory
  Prepare-WindowsNativeDependencies -StagingPath $stagingRoot
  Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $resolvedOutputPath
} finally {
  if ((Split-Path -Parent ([System.IO.Path]::GetFullPath($stagingRoot))).TrimEnd('\') -ne $temporaryRoot.TrimEnd('\') -or
      (Split-Path -Leaf $stagingRoot) -notmatch '^aethertune-zip-[0-9a-f-]{36}$') {
    throw 'Refusing to remove an unexpected ZIP staging directory.'
  }
  Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedOutputPath)
try {
  $entries = @($archive.Entries | ForEach-Object FullName)
  if ($entries -notcontains 'aethertune.exe') {
    throw 'The Windows ZIP is missing aethertune.exe.'
  }
  if (-not ($entries | Where-Object { $_ -like 'data/*' })) {
    throw 'The Windows ZIP is missing the Flutter data payload.'
  }
  foreach ($entry in ($WindowsRuntimeRequiredFiles + 'aethertune-windows-runtime.json' + 'aethertune-windows-native.json')) {
    if ($entries -notcontains $entry) { throw "The Windows ZIP is missing $entry." }
  }
} finally {
  $archive.Dispose()
}
