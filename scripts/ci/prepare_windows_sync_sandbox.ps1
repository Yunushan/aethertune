[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ProbeZip,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [Parameter(Mandatory=$true)][string]$OpenSslPath
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repository 'build')).TrimEnd('\') + '\'
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $output.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Transport Sandbox fixtures must stay below the repository build directory.'
}
if ((Test-Path -LiteralPath $output) -and @(Get-ChildItem -LiteralPath $output -Force).Count -gt 0) {
  throw 'Use a new or empty directory to retain prior acceptance evidence.'
}
$probe = (Resolve-Path -LiteralPath $ProbeZip).Path
if (-not $probe.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase) -or
    (Get-Item -LiteralPath $probe).Attributes -band [IO.FileAttributes]::ReparsePoint) {
  throw 'Only a regular probe ZIP inside the repository build directory may be mapped.'
}
$inputDirectory = Join-Path $output 'input'
$evidenceDirectory = Join-Path $output 'evidence'
$certificates = Join-Path $inputDirectory 'certificates'
New-Item -ItemType Directory -Path $certificates, $evidenceDirectory -Force | Out-Null
Copy-Item -LiteralPath $probe -Destination (Join-Path $inputDirectory 'probe.zip')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows_sync_sandbox_guest.ps1') -Destination (Join-Path $inputDirectory 'guest.ps1')
[IO.File]::WriteAllText((Join-Path $inputDirectory 'sync-fixture-v1'), "aethertune-windows-sync-acceptance-v1`n")
$extensions = Join-Path $PSScriptRoot 'testdata/sync_transport_leaf.ext'
foreach ($name in @('trusted', 'untrusted')) {
  $ca = Join-Path $certificates "$name-ca"
  $leaf = Join-Path $certificates "$name-leaf"
  & $OpenSslPath req -x509 -newkey rsa:2048 -nodes -keyout "$ca.key" -out "$ca.pem" -days 2 -subj "/CN=AetherTune Synthetic $name CA" -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic CA generation failed.' }
  & $OpenSslPath req -new -newkey rsa:2048 -nodes -keyout "$leaf.key" -out "$leaf.csr" -subj '/CN=127.0.0.1'
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic leaf generation failed.' }
  & $OpenSslPath x509 -req -in "$leaf.csr" -CA "$ca.pem" -CAkey "$ca.key" -set_serial 1 -out "$leaf.pem" -days 2 -extfile $extensions
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic leaf signing failed.' }
  & $OpenSslPath x509 -in "$ca.pem" -outform DER -out "$ca.cer"
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic root conversion failed.' }
  & $OpenSslPath x509 -in "$leaf.pem" -outform DER -out "$leaf.cer"
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic leaf conversion failed.' }
}

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
