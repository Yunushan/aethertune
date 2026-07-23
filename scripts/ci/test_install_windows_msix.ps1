[CmdletBinding()]
param()

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
    throw 'SignTool.exe from the Windows SDK is required to verify MSIX installation.'
  }
  return $candidates[0].FullName
}

function Require-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'MSIX install verification requires an elevated Windows administrator account for temporary machine certificate trust.'
  }
}

Require-Administrator

$root = Join-Path ([System.IO.Path]::GetTempPath()) "aethertune-windows-msix-install-$([guid]::NewGuid())"
$bundle = Join-Path $root 'bundle'
$packagePath = Join-Path $root 'release/aethertune-windows-x64.msix'
$certificatePath = Join-Path $root 'aethertune-test.cer'
$pfxPath = Join-Path $root 'aethertune-test.pfx'
$packageScript = Join-Path $PSScriptRoot 'package_windows_msix.ps1'
$certificate = $null
$installedPackage = $null
$machineTrustInstalled = $false

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'data/flutter_assets') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $bundle 'aethertune.exe'), 'fixture')
  [System.IO.File]::WriteAllText(
    (Join-Path $bundle 'data/flutter_assets/AssetManifest.bin'),
    'fixture asset manifest'
  )
  & $packageScript -BundlePath $bundle -OutputPath $packagePath -Version '0.1.0+1'

  Write-Host 'Creating temporary MSIX signing certificate.'
  $certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject 'CN=AetherTune' `
    -KeyUsage DigitalSignature `
    -KeyExportPolicy Exportable `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -TextExtension @(
      '2.5.29.19={text}ca=false',
      '2.5.29.37={text}1.3.6.1.5.5.7.3.3'
    )
  $password = ConvertTo-SecureString 'aethertune-ci-only' -AsPlainText -Force
  Write-Host 'Exporting temporary MSIX signing certificate.'
  Export-Certificate -Cert $certificate -FilePath $certificatePath | Out-Null
  Export-PfxCertificate -Cert $certificate -FilePath $pfxPath -Password $password | Out-Null
  Write-Host 'Adding temporary MSIX certificate trust.'
  Import-Certificate `
    -FilePath $certificatePath `
    -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' | Out-Null
  Import-Certificate `
    -FilePath $certificatePath `
    -CertStoreLocation 'Cert:\CurrentUser\Root' | Out-Null
  & certutil.exe -addstore TrustedPeople $certificatePath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'The temporary machine trusted-people certificate could not be added.'
  }
  $machineTrustInstalled = $true

  Write-Host 'Signing temporary MSIX package.'
  $signTool = Find-SignTool
  & $signTool sign /fd SHA256 /f $pfxPath /p 'aethertune-ci-only' $packagePath
  if ($LASTEXITCODE -ne 0) {
    throw "SignTool.exe failed with exit code $LASTEXITCODE."
  }
  & $signTool verify /pa $packagePath
  if ($LASTEXITCODE -ne 0) {
    throw "SignTool.exe verification failed with exit code $LASTEXITCODE."
  }

  Write-Host 'Installing temporary signed MSIX package.'
  Add-AppxPackage -Path $packagePath
  Write-Host 'Verifying installed MSIX package payload.'
  $installedPackage = Get-AppxPackage -Name AetherTune |
    Sort-Object Version -Descending |
    Select-Object -First 1
  if ($null -eq $installedPackage) {
    throw 'The temporary AetherTune MSIX was not registered after installation.'
  }
  $assetManifest = Join-Path $installedPackage.InstallLocation `
    'VFS\ProgramFilesX64\AetherTune\data\flutter_assets\AssetManifest.bin'
  if (-not (Test-Path -LiteralPath $assetManifest -PathType Leaf)) {
    throw 'The installed AetherTune MSIX is missing the Flutter asset manifest.'
  }
} finally {
  Write-Host 'Cleaning up temporary MSIX install test state.'
  if ($null -ne $installedPackage) {
    Remove-AppxPackage -Package $installedPackage.PackageFullName `
      -ErrorAction SilentlyContinue
  }
  if ($null -ne $certificate) {
    Remove-Item -LiteralPath "Cert:\CurrentUser\TrustedPeople\$($certificate.Thumbprint)" `
      -Force -ErrorAction SilentlyContinue
    & certutil.exe -user -delstore Root $certificate.Thumbprint | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw 'The temporary current-user root certificate could not be removed.'
    }
    if ($machineTrustInstalled) {
      & certutil.exe -delstore TrustedPeople $certificate.Thumbprint | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw 'The temporary machine trusted-people certificate could not be removed.'
      }
    }
    Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($certificate.Thumbprint)" `
      -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
