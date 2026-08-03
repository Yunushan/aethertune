[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ExecutablePath,
  [Parameter(Mandatory = $true)]
  [string]$SigningCertificatePath,
  [Parameter(Mandatory = $true)]
  [string]$SigningCertificatePassword
)

$ErrorActionPreference = 'Stop'

function Find-SignTool {
  $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }

  $kitsRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10\bin'
  $candidates = @(
    Get-ChildItem -LiteralPath $kitsRoot -Filter signtool.exe -Recurse `
      -ErrorAction SilentlyContinue |
      Where-Object { $_.DirectoryName -match '\\x64$' } |
      Sort-Object FullName -Descending
  )
  if ($candidates.Count -eq 0) {
    throw 'signtool.exe from the Windows SDK is required for signed Windows binaries.'
  }
  return $candidates[0].FullName
}

$resolvedExecutablePath = Resolve-Path -LiteralPath $ExecutablePath
if (-not (Test-Path -LiteralPath $resolvedExecutablePath -PathType Leaf)) {
  throw "Windows executable does not exist: $ExecutablePath"
}
if (-not (Test-Path -LiteralPath $SigningCertificatePath -PathType Leaf)) {
  throw "Signing certificate does not exist: $SigningCertificatePath"
}

$signTool = Find-SignTool
& $signTool sign /fd SHA256 /a /f $SigningCertificatePath /p $SigningCertificatePassword $resolvedExecutablePath.Path
if ($LASTEXITCODE -ne 0) {
  throw "signtool.exe failed with exit code $LASTEXITCODE."
}

& $signTool verify /pa /all $resolvedExecutablePath.Path
if ($LASTEXITCODE -ne 0) {
  throw "signtool.exe could not verify the Authenticode signature."
}

$signature = Get-AuthenticodeSignature -FilePath $resolvedExecutablePath.Path
if ($null -eq $signature.SignerCertificate -or $signature.Status -ne 'Valid') {
  throw "The executable Authenticode signature is not valid: $($signature.Status)."
}
