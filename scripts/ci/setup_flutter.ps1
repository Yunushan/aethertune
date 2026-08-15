$ErrorActionPreference = 'Stop'

$FlutterVersion = '3.44.6'
$FlutterCommit = 'ee80f08bbf97172ec030b8751ceab557177a34a6'
$RunnerTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$FlutterRoot = Join-Path $RunnerTemp "aethertune-flutter-$FlutterCommit"

if (-not (Test-Path (Join-Path $FlutterRoot '.git'))) {
    if (Test-Path $FlutterRoot) {
        Remove-Item -LiteralPath $FlutterRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $FlutterRoot -Force | Out-Null
    git -C $FlutterRoot init --quiet
    git -C $FlutterRoot remote add origin https://github.com/flutter/flutter.git
    git -C $FlutterRoot fetch --depth=1 origin "refs/tags/$FlutterVersion:refs/tags/$FlutterVersion"
    git -C $FlutterRoot checkout --quiet --detach "refs/tags/$FlutterVersion"
}

$ActualCommit = (git -C $FlutterRoot rev-parse HEAD).Trim()
if ($ActualCommit -ne $FlutterCommit) {
    throw "Flutter SDK commit mismatch: expected $FlutterCommit, got $ActualCommit"
}

"FLUTTER_ROOT=$FlutterRoot" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
$FlutterBin = Join-Path $FlutterRoot 'bin'
$FlutterBin | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8
$env:PATH = "$FlutterBin;$env:PATH"

Write-Host "Using Flutter $FlutterVersion at commit $ActualCommit"
& (Join-Path $FlutterBin 'flutter.bat') --version
