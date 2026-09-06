[CmdletBinding()]
param([string]$OriginalZlib)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_native_dependencies.ps1')

function Assert-Failure([scriptblock]$Action, [string]$Pattern) {
  try { & $Action } catch {
    if ($_.Exception.Message -match $Pattern) { return }
    throw
  }
  throw "Expected failure matching $Pattern."
}

$debugNames = @(
  'ucrtbased.dll', 'msvcrtd.dll', 'msvcr120d.dll', 'concrt140d.dll', 'vccorlib140d.dll',
  'msvcp140d.dll', 'msvcp140_1d.dll', 'msvcp140_2d.dll',
  'msvcp140d_atomic_wait.dll', 'msvcp140d_codecvt_ids.dll',
  'vcruntime140d.dll', 'VCRUNTIME140_1D.dll', 'vcruntime140_threadsd.dll'
)
$originalCulture = [Globalization.CultureInfo]::CurrentCulture
try {
  foreach ($culture in @('en-US', 'tr-TR')) {
    [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($culture)
    foreach ($name in $debugNames) {
      if (-not (Test-WindowsDebugRuntime $name)) { throw "Missed debug runtime $name under $culture." }
    }
    foreach ($name in @('ucrtbase.dll', 'msvcp140.dll', 'msvcp140_1.dll', 'vcruntime140_threads.dll', 'media_kit.dll')) {
      if (Test-WindowsDebugRuntime $name) { throw "Rejected release module $name under $culture." }
    }
  }
} finally {
  [Globalization.CultureInfo]::CurrentCulture = $originalCulture
}

if ([string]::IsNullOrWhiteSpace($OriginalZlib)) {
  $repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  foreach ($configuration in @('Release', 'Debug')) {
    $candidate = Join-Path $repository "apps/mobile/build/windows/x64/runner/$configuration/zlib.dll"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $OriginalZlib = $candidate; break }
  }
}
if ([string]::IsNullOrWhiteSpace($OriginalZlib)) {
  throw 'Build the Windows app first, or supply the original ANGLE payload with -OriginalZlib.'
}
if ((Get-FileHash -LiteralPath $OriginalZlib).Hash.ToLowerInvariant() -ne $WindowsUnusedAngleZlibSha256) {
  throw 'The test requires the exact reviewed ANGLE zlib artifact.'
}
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root = Join-Path $temporaryRoot "aethertune-native-deps-test-$([guid]::NewGuid())"
try {
  $bundle = Join-Path $root 'bundle'
  $build = Join-Path $root 'build'
  New-Item -ItemType Directory -Path $bundle | Out-Null
  $runtime = Join-Path (Find-WindowsRuntimeDirectory) 'vcruntime140.dll'
  $exe = Join-Path $bundle 'aethertune.exe'
  $zlib = Join-Path $bundle 'zlib.dll'
  Copy-Item -LiteralPath $runtime -Destination $exe
  Copy-Item -LiteralPath $OriginalZlib -Destination $zlib
  Prepare-WindowsNativeDependencies $bundle
  if (Test-Path -LiteralPath $zlib) { throw 'The known unused artifact was not omitted.' }
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $bundle 'aethertune-windows-native.json') | ConvertFrom-Json
  if ($manifest.omitted[0].sha256 -ne $WindowsUnusedAngleZlibSha256 -or $manifest.modules.Count -ne 1) {
    throw 'Native manifest did not capture the inspected payload.'
  }
  if ($manifest.policyVersion -ne $WindowsNativePolicy.version) { throw 'Native policy version was not recorded.' }
  $asset = Join-Path $bundle 'app.so'
  [IO.File]::WriteAllText($asset, 'AOT fixture, not executable')
  Prepare-WindowsNativeDependencies $bundle
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $bundle 'aethertune-windows-native.json') | ConvertFrom-Json
  if ($manifest.omitted.Count -ne 0 -or $manifest.referenceScannedAssets.Count -ne 1 -or
      $manifest.referenceScannedAssets[0].sha256 -ne (Get-FileHash -LiteralPath $asset).Hash.ToLowerInvariant()) {
    throw 'AOT payload was not recorded when no dependency was omitted.'
  }
  Remove-Item -LiteralPath $asset

  $outside = Join-Path $root 'outside-stage'
  New-Item -ItemType Directory -Path $outside | Out-Null
  $link = Join-Path $bundle 'linked-assets'
  New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
  Assert-Failure { Prepare-WindowsNativeDependencies $bundle } 'must not be links'
  Remove-Item -LiteralPath $link -Force

  Copy-Item -LiteralPath $runtime -Destination $zlib
  Assert-Failure { Prepare-WindowsNativeDependencies $bundle } 'Unknown zlib.dll'
  Copy-Item -LiteralPath $OriginalZlib -Destination $zlib -Force
  [IO.File]::AppendAllText($exe, 'zlib.dll')
  Assert-Failure { Prepare-WindowsNativeDependencies $bundle } 'native reference'
  Copy-Item -LiteralPath $runtime -Destination $exe -Force
  $stream = [IO.File]::Open($exe, [IO.FileMode]::Append)
  try { $bytes = [Text.Encoding]::Unicode.GetBytes('Cr_z_zlibVersion'); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
  Assert-Failure { Prepare-WindowsNativeDependencies $bundle } 'native reference'
  Copy-Item -LiteralPath $runtime -Destination $exe -Force
  $aot = Join-Path $bundle 'app.so'
  [IO.File]::WriteAllText($aot, 'zlib.dll')
  Assert-Failure { Prepare-WindowsNativeDependencies $bundle } 'native reference'
  Remove-Item -LiteralPath $aot

  & cmake -S (Join-Path $PSScriptRoot 'testdata/windows_native_dependencies') -B $build -A x64
  if ($LASTEXITCODE -ne 0) { throw 'Native import fixture configuration failed.' }
  & cmake --build $build --config Release
  if ($LASTEXITCODE -ne 0) { throw 'Native import fixture build failed.' }
  $dumpbin = Find-WindowsDumpbin
  foreach ($name in @('direct_consumer', 'delayed_consumer')) {
    $source = Join-Path $build "Release/$name.dll"
    if (@(Get-WindowsNativeImports $source $dumpbin) -notcontains 'zlib.dll') {
      throw "Did not detect the $name import table."
    }
    $consumer = Join-Path $bundle 'consumer.dll'
    Copy-Item -LiteralPath $source -Destination $consumer
    Assert-Failure { Prepare-WindowsNativeDependencies $bundle } 'native reference'
    Remove-Item -LiteralPath $consumer
  }
  Copy-Item -LiteralPath (Join-Path $build 'Release/debug_consumer.dll') -Destination (Join-Path $bundle 'debug.dll')
  Assert-Failure { Prepare-WindowsNativeDependencies $bundle } 'Debug C\+\+ runtime'
  if (-not (Test-Path -LiteralPath $zlib)) { throw 'A rejected audit removed the original dependency.' }
  if ((Get-FileHash -LiteralPath $OriginalZlib).Hash.ToLowerInvariant() -ne $WindowsUnusedAngleZlibSha256) {
    throw 'The test changed the original bundle.'
  }
  Write-Output 'Native dependency policy: release/debug names, omission, AOT inventory, link rejection, unknown artifact, ASCII/UTF-16/AOT references, direct/delay imports and debug runtime checks passed.'
} finally {
  if ((Split-Path -Parent ([IO.Path]::GetFullPath($root))).TrimEnd('\') -ne $temporaryRoot.TrimEnd('\') -or
      (Split-Path -Leaf $root) -notmatch '^aethertune-native-deps-test-[0-9a-f-]{36}$') {
    throw 'Refusing cleanup of an unexpected native dependency test directory.'
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
