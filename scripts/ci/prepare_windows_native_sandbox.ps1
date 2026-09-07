[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ProbeZip,
  [Parameter(Mandatory=$true)][string]$ProductionZip,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [Parameter(Mandatory=$true)][string]$FfmpegPath,
  [string]$PythonPath = 'python'
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repository 'build')).TrimEnd('\') + '\'
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $output.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Sandbox fixture directories must be below this repository build directory.'
}
if ((Test-Path -LiteralPath $output) -and @(Get-ChildItem -LiteralPath $output -Force).Count -gt 0) {
  throw 'Use a new or empty output directory to preserve previous evidence.'
}
foreach ($path in @($ProbeZip, $ProductionZip)) {
  $resolved = (Resolve-Path -LiteralPath $path).Path
  if (-not $resolved.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase) -or
      (Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Only regular archive files below the repository build directory may be mapped.'
  }
}
$inputDirectory = Join-Path $output 'input'
$evidenceDirectory = Join-Path $output 'evidence'
New-Item -ItemType Directory -Force -Path $inputDirectory, $evidenceDirectory | Out-Null
Copy-Item -LiteralPath $ProbeZip -Destination (Join-Path $inputDirectory 'probe.zip')
Copy-Item -LiteralPath $ProductionZip -Destination (Join-Path $inputDirectory 'production.zip')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows_native_sandbox_guest.ps1') -Destination (Join-Path $inputDirectory 'guest.ps1')
[IO.File]::WriteAllText((Join-Path $inputDirectory 'acceptance-fixture-v1'), "aethertune-windows-native-acceptance-v1`n")
& $PythonPath (Join-Path $PSScriptRoot 'generate_windows_media_fixture.py') --output (Join-Path $inputDirectory 'media') --ffmpeg $FfmpegPath
if ($LASTEXITCODE -ne 0) { throw 'Synthetic media generation/decoding failed; Python with Pillow and FFmpeg are required.' }

$configuration = [xml]@'
<Configuration>
  <VGpu>Disable</VGpu>
  <Networking>Disable</Networking>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection>
  <MemoryInMB>4096</MemoryInMB>
  <MappedFolders>
    <MappedFolder><HostFolder></HostFolder><SandboxFolder>C:\Input</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder></HostFolder><SandboxFolder>C:\Evidence</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Input\guest.ps1</Command></LogonCommand>
</Configuration>
'@
$configuration.Configuration.MappedFolders.MappedFolder[0].HostFolder = $inputDirectory
$configuration.Configuration.MappedFolders.MappedFolder[1].HostFolder = $evidenceDirectory
$configurationPath = Join-Path $output 'acceptance.wsb'
$configuration.Save($configurationPath)
Write-Output $configurationPath
