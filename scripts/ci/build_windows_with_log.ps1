$ErrorActionPreference = 'Stop'
# Capture native stderr and preserve the build process exit code after Tee-Object.
$PSNativeCommandUseErrorActionPreference = $false
$WorkspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$LogDirectory = Join-Path $WorkspaceRoot 'build/windows-native-build'
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$LogPath = Join-Path $LogDirectory 'windows-build.log'

Push-Location -LiteralPath (Join-Path $WorkspaceRoot 'apps/mobile')
try {
    & flutter build windows --debug --verbose 2>&1 | Tee-Object -FilePath $LogPath
    $BuildExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $BuildExitCode
