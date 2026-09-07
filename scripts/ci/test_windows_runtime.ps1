[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_runtime.ps1')

function Assert-Fails([scriptblock]$Action, [string]$Pattern) {
  try { & $Action } catch {
    if ($_.Exception.Message -match $Pattern) { return }
    throw
  }
  throw "Expected failure matching: $Pattern"
}

$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$root = Join-Path $temporaryRoot "aethertune-runtime-test-$([guid]::NewGuid())"
try {
  $runtime = Find-WindowsRuntimeDirectory
  $destination = Join-Path $root 'valid'
  $invalidSource = Join-Path $root 'invalid-source'
  $emptyDestination = Join-Path $root 'empty-destination'
  New-Item -ItemType Directory -Path $destination, $invalidSource, $emptyDestination | Out-Null
  Add-WindowsRuntimeFiles -DestinationPath $destination -RuntimeDirectory $runtime
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $destination 'aethertune-windows-runtime.json') | ConvertFrom-Json
  foreach ($name in $WindowsRuntimeRequiredFiles) {
    $entry = @($manifest | Where-Object file -eq $name)
    if ($entry.Count -ne 1 -or
        $entry[0].sha256 -ne (Get-FileHash -LiteralPath (Join-Path $runtime $name)).Hash.ToLowerInvariant() -or
        $entry[0].sha256 -ne (Get-FileHash -LiteralPath (Join-Path $destination $name)).Hash.ToLowerInvariant()) {
      throw "Runtime payload or manifest mismatch for $name."
    }
  }

  Assert-Fails { Add-WindowsRuntimeFiles -DestinationPath $emptyDestination -RuntimeDirectory $invalidSource } 'Missing required release runtime'
  foreach ($name in $WindowsRuntimeRequiredFiles) {
    Copy-Item -LiteralPath (Join-Path $runtime $name) -Destination $invalidSource
  }
  $invalidFile = Join-Path $invalidSource 'msvcp140.dll'
  $original = [System.IO.File]::ReadAllBytes($invalidFile)
  [System.IO.File]::WriteAllBytes($invalidFile, [byte[]]@(1,2,3))
  Assert-Fails { Add-WindowsRuntimeFiles -DestinationPath $emptyDestination -RuntimeDirectory $invalidSource } 'not a PE image'

  $altered = $original.Clone()
  $peOffset = [BitConverter]::ToUInt32($altered, 0x3c)
  $altered[$peOffset + 4] = 0x4c
  $altered[$peOffset + 5] = 0x01
  [System.IO.File]::WriteAllBytes($invalidFile, $altered)
  Assert-Fails { Add-WindowsRuntimeFiles -DestinationPath $emptyDestination -RuntimeDirectory $invalidSource } 'must be an x64 PE'

  $altered = $original.Clone()
  $altered[0x40] = $altered[0x40] -bxor 1
  [System.IO.File]::WriteAllBytes($invalidFile, $altered)
  Assert-Fails { Add-WindowsRuntimeFiles -DestinationPath $emptyDestination -RuntimeDirectory $invalidSource } 'valid Microsoft signature'

  [System.IO.File]::WriteAllBytes($invalidFile, $original)
  Copy-Item -LiteralPath $invalidFile -Destination (Join-Path $invalidSource 'vcruntime140d.dll')
  Assert-Fails { Add-WindowsRuntimeFiles -DestinationPath $emptyDestination -RuntimeDirectory $invalidSource } 'Unexpected file'
  if (@(Get-ChildItem -LiteralPath $emptyDestination -Force).Count -ne 0) {
    throw 'Failed runtime validation modified the package destination.'
  }
  Write-Output 'Windows runtime: valid payload plus five fail-closed cases passed.'
} finally {
  if ((Split-Path -Parent ([System.IO.Path]::GetFullPath($root))).TrimEnd('\') -ne $temporaryRoot.TrimEnd('\') -or
      (Split-Path -Leaf $root) -notmatch '^aethertune-runtime-test-[0-9a-f-]{36}$') {
    throw 'Refusing to remove an unexpected runtime test directory.'
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
