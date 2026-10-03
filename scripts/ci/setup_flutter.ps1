$ErrorActionPreference = 'Stop'

function Assert-NativeCommandSuccess {
    param([string] $Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE"
    }
}

$FlutterVersion = '3.44.6'
$FlutterCommit = 'ee80f08bbf97172ec030b8751ceab557177a34a6'
$RunnerTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
if (-not [IO.Path]::IsPathFullyQualified($RunnerTemp)) {
    throw "Runner temporary directory must be absolute: $RunnerTemp"
}
$RunnerTemp = [IO.Path]::GetFullPath($RunnerTemp)
if (-not (Test-Path -LiteralPath $RunnerTemp -PathType Container)) {
    throw "Runner temporary directory does not exist: $RunnerTemp"
}
$FlutterRoot = [IO.Path]::GetFullPath((Join-Path $RunnerTemp "aethertune-flutter-$FlutterCommit"))
$RunnerTempBoundary = $RunnerTemp.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$FlutterParentBoundary = [IO.Directory]::GetParent($FlutterRoot).FullName.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $FlutterParentBoundary.Equals($RunnerTempBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Flutter SDK directory must be a direct child of runner temporary directory: $FlutterRoot"
}

if (Test-Path -LiteralPath $FlutterRoot) {
    $FlutterDirectory = Get-Item -LiteralPath $FlutterRoot -Force
    if ($FlutterDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Flutter SDK directory is a reparse point; preserving it: $FlutterRoot"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $FlutterRoot '.git') -PathType Container)) {
        throw "Existing Flutter SDK directory has no Git checkout; preserving it: $FlutterRoot"
    }
} else {
    New-Item -ItemType Directory -Path $FlutterRoot | Out-Null
    git -C $FlutterRoot init --quiet
    Assert-NativeCommandSuccess 'Flutter SDK git init'
    git -C $FlutterRoot remote add origin https://github.com/flutter/flutter.git
    Assert-NativeCommandSuccess 'Flutter SDK git remote add'
    git -C $FlutterRoot fetch --depth=1 origin "refs/tags/${FlutterVersion}:refs/tags/${FlutterVersion}"
    Assert-NativeCommandSuccess 'Flutter SDK git fetch'
    # Apply long-path support to this checkout process without writing Git settings.
    git -c core.longpaths=true -C $FlutterRoot checkout --quiet --detach "refs/tags/${FlutterVersion}"
    Assert-NativeCommandSuccess 'Flutter SDK git checkout'
}

$CommitOutput = git -C $FlutterRoot rev-parse HEAD
Assert-NativeCommandSuccess 'Flutter SDK git rev-parse'
$ActualCommit = ($CommitOutput | Out-String).Trim()
if ($ActualCommit -ne $FlutterCommit) {
    throw "Flutter SDK commit mismatch: expected $FlutterCommit, got $ActualCommit"
}

$FlutterBin = Join-Path $FlutterRoot 'bin'
Write-Host "Using Flutter $FlutterVersion at commit $ActualCommit"
& (Join-Path $FlutterBin 'flutter.bat') --version
Assert-NativeCommandSuccess 'Flutter SDK version check'

"FLUTTER_ROOT=$FlutterRoot" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
$FlutterBin | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8
$env:PATH = "$FlutterBin;$env:PATH"
