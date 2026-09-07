$ErrorActionPreference = 'Stop'
# This guard precedes certificate import, app launch and the shutdown finally.
if ($env:USERNAME -ne 'WDAGUtilityAccount' -or $env:USERPROFILE -ne 'C:\Users\WDAGUtilityAccount' -or
    -not (Test-Path -LiteralPath 'C:\Input\sync-fixture-v1') -or
    (Get-Content -Raw -LiteralPath 'C:\Input\sync-fixture-v1') -ne "aethertune-windows-sync-acceptance-v1`n") {
  throw 'This driver may run only inside its marked disposable Windows Sandbox.'
}

$result = [ordered]@{ status='starting'; startedAt=[DateTime]::UtcNow.ToString('o'); phases=@() }
$app = $null
$peer = $null
$rootStore = $null
$certificate = $null
try {
  $result.stage = 'compile-peer'
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'C:\Evidence\started.json'
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
public sealed class SyncGuestPeer : IDisposable {
  readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
  TcpClient client;
  readonly Task task;
  public readonly ManualResetEventSlim Received = new ManualResetEventSlim(false);
  public readonly ManualResetEventSlim Disconnected = new ManualResetEventSlim(false);
  public Exception Error;
  public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
  [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
  public SyncGuestPeer(string phase) {
    listener.Start();
    task = Serve(phase);
  }
  async Task Serve(string phase) {
    try {
      client = await listener.AcceptTcpClientAsync();
      var stream = client.GetStream();
      var bytes = new byte[8192];
      int count = await stream.ReadAsync(bytes, 0, bytes.Length);
      if (count == 0) throw new IOException("Peer disconnected without sending a request");
      if (phase == "body") {
        var response = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 10000\r\nContent-Type: application/json\r\n\r\n{");
        await stream.WriteAsync(response, 0, response.Length);
        await stream.FlushAsync();
      }
      Received.Set();
      while (await stream.ReadAsync(bytes, 0, bytes.Length) > 0) { }
    } catch (IOException error) {
      if (!Received.IsSet) Error = error;
    } catch (Exception error) {
      Error = error;
    } finally {
      Disconnected.Set();
    }
  }
  public void Dispose() {
    listener.Stop();
    if (client != null) client.Close();
    if (!task.Wait(5000)) throw new TimeoutException("Guest peer did not stop");
    Received.Dispose();
    Disconnected.Dispose();
  }
}
'@
  [void][SyncGuestPeer]::SetErrorMode(0x8003)
  $result.packageSha256 = (Get-FileHash -LiteralPath 'C:\Input\probe.zip').Hash.ToLowerInvariant()
  $result.stage = 'extract-package'
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'C:\Evidence\started.json'
  Expand-Archive -LiteralPath 'C:\Input\probe.zip' -DestinationPath 'C:\Application'
  $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new('C:\Input\certificates\trusted-ca.cer')
  # CurrentUser Root uses an interactive Windows security warning. The marked
  # disposable guest has an administrator session; its machine store is local
  # to this VM and does not alter the host or weaken certificate validation.
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The isolated certificate fixture requires the default Sandbox administrator session.'
  }
  $result.stage = 'import-synthetic-guest-root'
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'C:\Evidence\started.json'
  $rootStore = [Security.Cryptography.X509Certificates.X509Store]::new('Root', 'LocalMachine')
  $rootStore.Open('ReadWrite')
  $rootStore.Add($certificate)
  $result.syntheticRootThumbprint = $certificate.Thumbprint
  $result.syntheticRootScope = 'disposable-guest-LocalMachine'
  $result.syntheticRootPresent = @(Get-ChildItem Cert:\LocalMachine\Root | Where-Object Thumbprint -eq $certificate.Thumbprint).Count -eq 1
  $leaf = [Security.Cryptography.X509Certificates.X509Certificate2]::new('C:\Input\certificates\trusted-leaf.cer')
  $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
  try {
    $chain.ChainPolicy.RevocationMode = 'NoCheck'
    $result.fixtureChainBuilds = $chain.Build($leaf)
    $result.fixtureChainStatus = @($chain.ChainStatus | Select-Object Status,StatusInformation)
    $result.fixtureLeafValidity = @($leaf.NotBefore.ToUniversalTime().ToString('o'), $leaf.NotAfter.ToUniversalTime().ToString('o'))
  } finally { $chain.Dispose(); $leaf.Dispose() }
  if (-not $result.syntheticRootPresent -or -not $result.fixtureChainBuilds) {
    throw 'The synthetic certificate fixture was not trusted by the guest platform.'
  }
  $result.stage = 'run-contracts'
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'C:\Evidence\started.json'

  foreach ($phase in @('contracts', 'tls', 'headers', 'body')) {
    $result.stage = "run-$phase"
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'C:\Evidence\started.json'
    $phaseResult = [ordered]@{ phase=$phase; status='starting' }
    $stdout = $null
    $stderr = $null
    try {
      $start = [Diagnostics.ProcessStartInfo]::new('C:\Application\aethertune.exe')
      $start.WorkingDirectory = 'C:\Application'
      $start.UseShellExecute = $false
      $start.CreateNoWindow = $true
      $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
      $start.RedirectStandardOutput = $true
      $start.RedirectStandardError = $true
      $start.EnvironmentVariables['AETHERTUNE_SYNC_PHASE'] = $phase
      if ($phase -ne 'contracts') {
        $peer = [SyncGuestPeer]::new($phase)
        $start.EnvironmentVariables['AETHERTUNE_SYNC_PORT'] = $peer.Port.ToString()
      }
      $app = [Diagnostics.Process]::Start($start)
      $stdout = $app.StandardOutput.ReadToEndAsync()
      $stderr = $app.StandardError.ReadToEndAsync()
      $phaseResult.pid = $app.Id
      if ($phase -eq 'contracts') {
        if (-not $app.WaitForExit(90000)) { throw 'Contract acceptance timed out.' }
        $app.WaitForExit()
        $phaseResult.report = Get-Content -Raw -LiteralPath 'C:\Evidence\contracts.json' | ConvertFrom-Json
        if ($app.ExitCode -ne 0 -or $phaseResult.report.status -ne 'passed') {
          throw 'Integrated application transport contracts failed.'
        }
      } else {
        if (-not $peer.Received.Wait(15000) -or $null -ne $peer.Error) { throw 'External peer did not receive an application request.' }
        Start-Sleep -Milliseconds 150
        $app.Refresh()
        if ($app.HasExited -or $peer.Disconnected.IsSet) { throw 'Request ended before the native close control.' }
        $ready = Get-Content -Raw -LiteralPath "C:\Evidence\ready-$phase.json" | ConvertFrom-Json
        if ($ready.pid -ne $app.Id -or $ready.status -ne 'ready') { throw 'Unexpected application phase marker.' }
        $phaseResult.loadedTransport = @($app.Modules | Where-Object ModuleName -eq 'rhttp.dll' | ForEach-Object FileName)
        if ($phaseResult.loadedTransport.Count -ne 1 -or $phaseResult.loadedTransport[0] -ne 'C:\Application\rhttp.dll') {
          throw 'The application did not load the packaged transport DLL.'
        }
        $watch = [Diagnostics.Stopwatch]::StartNew()
        if (-not $app.CloseMainWindow()) { throw 'No native application window accepted the close request.' }
        if (-not $app.WaitForExit(5000)) { throw 'Native application close did not finish in five seconds.' }
        $phaseResult.processExitMs = $watch.ElapsedMilliseconds
        if (-not $peer.Disconnected.Wait(2000) -or $null -ne $peer.Error) { throw 'Peer did not observe clean connection release.' }
        $phaseResult.peerDisconnectedMs = $watch.ElapsedMilliseconds
        $phaseResult.forcedKill = $false
        if ($app.ExitCode -ne 0) { throw "Native close returned abnormal code $($app.ExitCode)." }
      }
      $phaseResult.exitCode = $app.ExitCode
      $phaseResult.status = 'passed'
    } catch {
      $phaseResult.status = 'failed'
      $phaseResult.error = $_.Exception.Message
    } finally {
      if ($null -ne $app) {
        if (-not $app.HasExited) { $app.Kill(); $phaseResult.forcedKill = $true }
        if (-not $app.WaitForExit(5000)) { throw 'Owned application cleanup failed.' }
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        $output | Set-Content -LiteralPath "C:\Evidence\$phase-stdout.log"
        $errorOutput | Set-Content -LiteralPath "C:\Evidence\$phase-stderr.log"
        if (($output + $errorOutput) -match '(?i)panicked|Dart_PostCObject|cannot post|Dart callback|unhandled exception') {
          $phaseResult.status = 'failed'
          $phaseResult.asynchronousNativeError = $true
        }
        $app.Dispose()
        $app = $null
      }
      if ($null -ne $peer) { $peer.Dispose(); $peer = $null }
      $result.phases += $phaseResult
    }
  }
  $result.status = if (@($result.phases | Where-Object status -ne 'passed').Count -eq 0) { 'passed' } else { 'failed' }
} catch {
  $result.status = 'failed'
  $result.error = $_.Exception.Message
} finally {
  $cleanupErrors = @()
  try {
    if ($null -ne $app) {
      if (-not $app.HasExited) { $app.Kill() }
      if (-not $app.WaitForExit(5000)) { throw 'Owned application did not stop.' }
      $app.Dispose()
    }
  } catch { $cleanupErrors += $_.Exception.Message }
  try {
    if ($null -ne $peer) { $peer.Dispose() }
  } catch { $cleanupErrors += $_.Exception.Message }
  try {
    if ($null -ne $rootStore) {
      if ($null -ne $certificate) { $rootStore.Remove($certificate) }
      $rootStore.Close()
    }
  } catch {
    $cleanupErrors += $_.Exception.Message
  }
  if ($cleanupErrors.Count -gt 0) { $result.status = 'failed' }
  $result.cleanupErrors = $cleanupErrors
  $result.finishedAt = [DateTime]::UtcNow.ToString('o')
  try {
    $result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath 'C:\Evidence\result.json'
  } finally {
    shutdown.exe /s /t 0
  }
}
