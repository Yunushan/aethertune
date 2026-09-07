$WindowsRuntimeRequiredFiles = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')

function Find-WindowsVisualStudioInstallation {
  $vswhere = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio/Installer/vswhere.exe'
  if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw 'Visual Studio C++ redistributable files are required; install the C++ desktop workload or supply RuntimeDirectory.'
  }
  $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installation)) {
    throw 'Cannot locate a Visual Studio C++ installation for Windows runtime packaging.'
  }
  return $installation.Trim()
}

function Find-WindowsRuntimeDirectory {
  $redistRoot = Join-Path (Find-WindowsVisualStudioInstallation) 'VC/Redist/MSVC'
  $versions = @(Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object {
    $_.Name -match '^14\.\d+\.\d+$'
  } | Sort-Object { [version]$_.Name } -Descending)
  foreach ($version in $versions) {
    $x64 = Join-Path $version.FullName 'x64'
    if (-not (Test-Path -LiteralPath $x64 -PathType Container)) { continue }
    $crt = @(Get-ChildItem -LiteralPath $x64 -Directory -Filter 'Microsoft.VC14*.CRT')
    if ($crt.Count -eq 1) { return $crt[0].FullName }
  }
  throw 'No x64 release C++ runtime directory was found in Visual Studio.'
}

function Assert-WindowsX64Image([string]$Path) {
  $stream = [System.IO.File]::OpenRead($Path)
  $reader = [System.IO.BinaryReader]::new($stream)
  try {
    if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) {
      throw "Runtime is not a PE image: $Path"
    }
    $stream.Position = 0x3c
    $peOffset = $reader.ReadUInt32()
    if ([long]$peOffset + 6 -gt $stream.Length) {
      throw "Runtime has an invalid PE header: $Path"
    }
    $stream.Position = $peOffset
    if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x8664) {
      throw "Runtime must be an x64 PE image: $Path"
    }
  } finally {
    $reader.Dispose()
  }
}

function Add-WindowsRuntimeFiles {
  param(
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [string]$RuntimeDirectory
  )
  if ([string]::IsNullOrWhiteSpace($RuntimeDirectory)) {
    $RuntimeDirectory = Find-WindowsRuntimeDirectory
  }
  $source = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
  $destination = (Resolve-Path -LiteralPath $DestinationPath).Path
  if ($source -eq $destination) { throw 'Runtime source and package destination must differ.' }
  foreach ($name in $WindowsRuntimeRequiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) {
      throw "Missing required release runtime $name in $source."
    }
  }
  # Use only the release CRT family from the licensed Visual Studio redist payload.
  $files = @(Get-ChildItem -LiteralPath $source -File -Filter '*.dll' | Sort-Object Name)
  $manifest = @()
  foreach ($file in $files) {
    if ($file.Name -notmatch '^(?:concrt140|msvcp140(?:_1|_2|_atomic_wait|_codecvt_ids)?|vccorlib140|vcruntime140(?:_1|_threads)?)\.dll$') {
      throw "Unexpected file in the release runtime directory: $($file.Name)"
    }
    Assert-WindowsX64Image $file.FullName
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|, )O=Microsoft Corporation(?:,|$)') {
      throw "Runtime must have a valid Microsoft signature: $($file.Name)"
    }
    $manifest += [ordered]@{
      file = $file.Name
      version = $file.VersionInfo.FileVersion
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  }
  # Validate the complete source before changing the package staging directory.
  foreach ($file in $files) {
    $target = Join-Path $destination $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    $expected = $manifest | Where-Object file -eq $file.Name
    if ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -ne $expected.sha256) {
      throw "Copied runtime hash differs: $($file.Name)"
    }
  }
  $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $destination 'aethertune-windows-runtime.json') -Encoding utf8NoBOM
}
