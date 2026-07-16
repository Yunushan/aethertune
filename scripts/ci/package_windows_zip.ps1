[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath,
  [Parameter(Mandatory = $true)]
  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

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

Compress-Archive -Path (Join-Path $bundle.Path '*') -DestinationPath $resolvedOutputPath

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
} finally {
  $archive.Dispose()
}
