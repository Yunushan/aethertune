. (Join-Path $PSScriptRoot 'windows_runtime.ps1')

$WindowsNativePolicy = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'windows_native_policy.json') | ConvertFrom-Json
$WindowsUnusedAngleZlibSha256 = $WindowsNativePolicy.unusedAngleZlibSha256
$WindowsDebugRuntimePattern = $WindowsNativePolicy.debugRuntimePattern

function Test-WindowsDebugRuntime([string]$Name) {
  return [regex]::IsMatch($Name, $WindowsDebugRuntimePattern,
    ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant))
}

function Find-WindowsDumpbin {
  $command = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
  if ($null -ne $command) { return $command.Source }
  $toolsRoot = Join-Path (Find-WindowsVisualStudioInstallation) 'VC/Tools/MSVC'
  $versions = @(Get-ChildItem -LiteralPath $toolsRoot -Directory | Where-Object {
    $_.Name -match '^14\.\d+\.\d+$'
  } | Sort-Object { [version]$_.Name } -Descending)
  foreach ($version in $versions) {
    $path = Join-Path $version.FullName 'bin/Hostx64/x64/dumpbin.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
  }
  throw 'DUMPBIN from the Visual Studio C++ toolchain is required for native dependency validation.'
}

function Get-WindowsNativeImports([string]$Path, [string]$Dumpbin) {
  Assert-WindowsX64Image $Path
  $language = $env:VSLANG
  try {
    $env:VSLANG = '1033'
    # /IMPORTS includes delay-load imports, unlike a simple loaded-module sample.
    $output = @(& $Dumpbin /nologo /imports $Path 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($output -match '(?i)(fatal error|warning LNK)') -or
        -not ($output -match 'File Type: (DLL|EXECUTABLE IMAGE)')) {
      throw "Cannot inspect native imports for $Path."
    }
    return @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object {
      $_ -match '^[A-Za-z0-9_.-]+\.dll$'
    } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
  } finally {
    $env:VSLANG = $language
  }
}

function Test-WindowsZlibReference([string]$Path) {
  $content = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
  foreach ($token in @('zlib.dll', 'Cr_z_')) {
    $wide = $token.ToCharArray() -join [string][char]0
    if ($content.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $content.IndexOf($wide, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
      return $true
    }
  }
  return $false
}

function Prepare-WindowsNativeDependencies {
  param([Parameter(Mandatory = $true)][string]$StagingPath)
  if ((Get-Item -LiteralPath $StagingPath).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Native package staging directories must not be links.'
  }
  $root = (Resolve-Path -LiteralPath $StagingPath).Path
  $dumpbin = Find-WindowsDumpbin
  $items = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
  foreach ($item in $items) {
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      throw "Native package files and directories must not be links: $($item.Name)"
    }
  }
  $files = @($items | Where-Object {
    -not $_.PSIsContainer -and $_.Extension -in '.dll', '.exe'
  } | Sort-Object FullName)
  $zlibPath = Join-Path $root 'zlib.dll'
  $omitted = @()
  if (Test-Path -LiteralPath $zlibPath -PathType Leaf) {
    $hash = (Get-FileHash -LiteralPath $zlibPath).Hash.ToLowerInvariant()
    if ($hash -ne $WindowsUnusedAngleZlibSha256) {
      throw 'Unknown zlib.dll payload; review its provenance and consumers before changing the native dependency policy.'
    }
    $omitted += [ordered]@{
      file = 'zlib.dll'
      sha256 = $hash
      reason = 'Known unreferenced Chromium-prefixed debug artifact from ANGLE v1.0.1'
    }
  }
  $modules = @()
  $opaqueAssets = @()
  foreach ($asset in ($items | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.so' } | Sort-Object FullName)) {
    if ($omitted.Count -gt 0 -and (Test-WindowsZlibReference $asset.FullName)) {
      throw "Cannot omit zlib.dll: a native reference remains in $($asset.Name)."
    }
    $opaqueAssets += [ordered]@{
      file = [IO.Path]::GetRelativePath($root, $asset.FullName).Replace('\', '/')
      sha256 = (Get-FileHash -LiteralPath $asset.FullName).Hash.ToLowerInvariant()
    }
  }
  foreach ($file in $files) {
    if ($file.FullName -eq $zlibPath) { continue }
    $imports = @(Get-WindowsNativeImports -Path $file.FullName -Dumpbin $dumpbin)
    if ((Test-WindowsDebugRuntime $file.Name) -or @($imports | Where-Object { Test-WindowsDebugRuntime $_ }).Count -gt 0) {
      throw "Debug C++ runtime dependency in release module $($file.Name)."
    }
    if ($omitted.Count -gt 0 -and
        ($imports -contains 'zlib.dll' -or (Test-WindowsZlibReference $file.FullName))) {
      throw "Cannot omit zlib.dll: a native reference remains in $($file.Name)."
    }
    $modules += [ordered]@{
      file = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
      sha256 = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
      imports = $imports
    }
  }
  if ($modules.Count -eq 0) { throw 'No native PE modules were found in the package staging directory.' }
  # Only this exact reviewed artifact is omitted, and only after every check passes.
  if ($omitted.Count -gt 0) { Remove-Item -LiteralPath $zlibPath -Force }
  [ordered]@{ schemaVersion=1; policyVersion=$WindowsNativePolicy.version; modules=$modules; omitted=$omitted; referenceScannedAssets=$opaqueAssets } |
    ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $root 'aethertune-windows-native.json') -Encoding utf8NoBOM
}
