[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath,
  [Parameter(Mandatory = $true)]
  [string]$OutputPath,
  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = 'Stop'

function Find-MakeAppx {
  $command = Get-Command MakeAppx.exe -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }

  $kitsRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10\bin'
  $candidates = @(
    Get-ChildItem -LiteralPath $kitsRoot -Filter MakeAppx.exe -Recurse `
      -ErrorAction SilentlyContinue |
      Where-Object { $_.DirectoryName -match '\\x64$' } |
      Sort-Object FullName -Descending
  )
  if ($candidates.Count -eq 0) {
    throw 'MakeAppx.exe from the Windows SDK is required to build an MSIX package.'
  }
  return $candidates[0].FullName
}

function Get-MsixVersion([string]$FlutterVersion) {
  if ($FlutterVersion -notmatch '^(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$') {
    throw "Expected a stable Flutter version such as 1.2.3+4, got '$FlutterVersion'."
  }
  $parts = @($Matches[1], $Matches[2], $Matches[3], '0') | ForEach-Object {
    $value = [int]$_
    if ($value -gt 65535) {
      throw "MSIX version component '$value' must not exceed 65535."
    }
    $value
  }
  return ($parts -join '.')
}

function New-Logo([string]$Path, [int]$Width, [int]$Height) {
  Add-Type -AssemblyName System.Drawing
  $bitmap = [System.Drawing.Bitmap]::new($Width, $Height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(12, 20, 35))
    $brush = [System.Drawing.SolidBrush]::new(
      [System.Drawing.Color]::FromArgb(34, 211, 238)
    )
    try {
      $diameter = [Math]::Min($Width, $Height) * 0.56
      $left = ($Width - $diameter) / 2
      $top = ($Height - $diameter) / 2
      $graphics.FillEllipse($brush, $left, $top, $diameter, $diameter)
    } finally {
      $brush.Dispose()
    }
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

$bundle = Resolve-Path -LiteralPath $BundlePath
$executablePath = Join-Path $bundle.Path 'aethertune.exe'
$assetManifestPath = Join-Path $bundle.Path 'data/flutter_assets/AssetManifest.bin'

if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
  throw "Expected a Windows Flutter bundle containing aethertune.exe at $executablePath."
}
if (-not (Test-Path -LiteralPath $assetManifestPath -PathType Leaf)) {
  throw "Expected Flutter assets at $assetManifestPath."
}

$msixVersion = Get-MsixVersion $Version
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Remove-Item -LiteralPath $resolvedOutputPath -Force -ErrorAction SilentlyContinue

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "aethertune-msix-$([guid]::NewGuid())"
try {
  $appRoot = Join-Path $stagingRoot 'VFS/ProgramFilesX64/AetherTune'
  $assetRoot = Join-Path $stagingRoot 'Assets'
  New-Item -ItemType Directory -Force -Path $appRoot, $assetRoot | Out-Null
  Copy-Item -Path (Join-Path $bundle.Path '*') -Destination $appRoot -Recurse -Force

  New-Logo -Path (Join-Path $assetRoot 'Square44x44Logo.png') -Width 44 -Height 44
  New-Logo -Path (Join-Path $assetRoot 'Square150x150Logo.png') -Width 150 -Height 150
  New-Logo -Path (Join-Path $assetRoot 'Square310x310Logo.png') -Width 310 -Height 310
  New-Logo -Path (Join-Path $assetRoot 'Wide310x150Logo.png') -Width 310 -Height 150
  New-Logo -Path (Join-Path $assetRoot 'StoreLogo.png') -Width 50 -Height 50

  @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities" IgnorableNamespaces="uap rescap">
  <Identity Name="AetherTune" Publisher="CN=AetherTune" Version="$msixVersion" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>AetherTune</DisplayName>
    <PublisherDisplayName>AetherTune Contributors</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Applications>
    <Application Id="App" Executable="VFS\ProgramFilesX64\AetherTune\aethertune.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="AetherTune" Description="Free and open-source music player" BackgroundColor="transparent" Square150x150Logo="Assets\Square150x150Logo.png" Square44x44Logo="Assets\Square44x44Logo.png">
        <uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" Square310x310Logo="Assets\Square310x310Logo.png" />
      </uap:VisualElements>
    </Application>
  </Applications>
  <Capabilities>
    <Capability Name="internetClient" />
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
"@ | Set-Content -LiteralPath (Join-Path $stagingRoot 'AppxManifest.xml') -Encoding utf8NoBOM

  $makeAppx = Find-MakeAppx
  & $makeAppx pack /d $stagingRoot /p $resolvedOutputPath /o
  if ($LASTEXITCODE -ne 0) {
    throw "MakeAppx.exe failed with exit code $LASTEXITCODE."
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedOutputPath)
  try {
    $entries = @($archive.Entries | ForEach-Object FullName)
    $requiredEntries = @(
      '[Content_Types].xml',
      'AppxBlockMap.xml',
      'AppxManifest.xml',
      'VFS/ProgramFilesX64/AetherTune/aethertune.exe',
      'VFS/ProgramFilesX64/AetherTune/data/flutter_assets/AssetManifest.bin',
      'Assets/Square44x44Logo.png'
    )
    foreach ($entry in $requiredEntries) {
      if ($entries -notcontains $entry) {
        throw "The Windows MSIX is missing $entry."
      }
    }
  } finally {
    $archive.Dispose()
  }
} finally {
  Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
