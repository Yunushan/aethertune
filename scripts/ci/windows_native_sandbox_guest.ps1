$ErrorActionPreference = 'Stop'
# Keep this guard outside the shutdown finally block: accidental host execution
# must neither alter the user's app data nor shut down their computer.
if ($env:USERNAME -ne 'WDAGUtilityAccount' -or $env:USERPROFILE -ne 'C:\Users\WDAGUtilityAccount' -or
    -not (Test-Path -LiteralPath 'C:\Input\acceptance-fixture-v1') -or
    (Get-Content -Raw -LiteralPath 'C:\Input\acceptance-fixture-v1') -ne "aethertune-windows-native-acceptance-v1`n") {
  throw 'This driver may run only in the marked Windows Sandbox guest.'
}

$result = [ordered]@{ status='starting'; startedAt=[DateTime]::UtcNow.ToString('o'); phases=@(); keys=@() }
$script:app = $null
$script:stdout = $null
$script:stderr = $null

function Save-Desktop([string]$Name) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
    $bitmap.Save((Join-Path 'C:\Evidence' $Name), [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

function Stop-OwnedApp([string]$Phase) {
  if ($null -eq $script:app) { return }
  if (-not $script:app.HasExited) { $script:app.Kill() }
  if (-not $script:app.WaitForExit(5000)) { throw 'Owned application did not exit.' }
  $script:stdout.GetAwaiter().GetResult() | Set-Content -LiteralPath "C:\Evidence\$Phase-stdout.log"
  $script:stderr.GetAwaiter().GetResult() | Set-Content -LiteralPath "C:\Evidence\$Phase-stderr.log"
  $script:app.Dispose()
  $script:app = $null
}

function Run-App([string]$Directory, [string]$Phase, [switch]$Observe) {
  $start = [Diagnostics.ProcessStartInfo]::new((Join-Path $Directory 'aethertune.exe'))
  $start.WorkingDirectory = $Directory
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.EnvironmentVariables['AETHERTUNE_ACCEPTANCE_PHASE'] = $Phase
  $script:app = [Diagnostics.Process]::Start($start)
  $script:stdout = $script:app.StandardOutput.ReadToEndAsync()
  $script:stderr = $script:app.StandardError.ReadToEndAsync()
  $modules = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $sent = [Collections.Generic.HashSet[string]]::new()
  $deadline = [DateTime]::UtcNow.AddSeconds(180)
  $windowSince = $null
  try {
    while (-not $script:app.WaitForExit(100)) {
      if ([DateTime]::UtcNow -gt $deadline) { throw "$Phase timed out." }
      $script:app.Refresh()
      try {
        foreach ($module in $script:app.Modules) { [void]$modules.Add($module.FileName) }
      } catch { }
      $failureRequest = 'C:\Evidence\failure-capture-request.json'
      if ((Test-Path -LiteralPath $failureRequest) -and -not (Test-Path -LiteralPath "C:\Evidence\$Phase-failure-captured")) {
        try { $capture = Get-Content -Raw -LiteralPath $failureRequest | ConvertFrom-Json } catch { $capture = $null }
        if ($null -ne $capture -and $capture.pid -eq $script:app.Id -and $capture.phase -eq $Phase) {
          Save-Desktop "$Phase-failure-desktop.png"
          [IO.File]::WriteAllText("C:\Evidence\$Phase-failure-captured", 'captured')
        }
      }
      if ($Observe) {
        if ($script:app.MainWindowHandle -ne [IntPtr]::Zero -and $null -eq $windowSince) {
          $windowSince = [DateTime]::UtcNow
        }
        if ($null -ne $windowSince -and ([DateTime]::UtcNow - $windowSince).TotalSeconds -ge 15) {
          Save-Desktop 'production-desktop.png'
          $result.phases += [ordered]@{ phase=$Phase; status='window-alive-15-seconds'; processId=$script:app.Id; modules=@($modules | Sort-Object) }
          return
        }
        continue
      }
      if ($Phase -eq 'exercise') {
        foreach ($name in @('pause','resume','next','previous')) {
          $request = "C:\Evidence\key-$name-request.json"
          if ($sent.Contains($name) -or -not (Test-Path -LiteralPath $request)) { continue }
          try { $key = Get-Content -Raw -LiteralPath $request | ConvertFrom-Json } catch { continue }
          $expected = @{ pause=0xb3; resume=0xb3; next=0xb0; previous=0xb1 }[$name]
          if ($key.pid -ne $script:app.Id -or $key.name -ne $name -or $key.virtualKey -ne $expected) {
            throw 'Unexpected native media-key request.'
          }
          [GuestMediaKeys]::Send([uint16]$expected)
          [void]$sent.Add($name)
          $result.keys += [ordered]@{ name=$name; virtualKey=$expected; processId=$script:app.Id; sentAt=[DateTime]::UtcNow.ToString('o') }
        }
        if (Test-Path -LiteralPath 'C:\Evidence\video-capture-request.json') {
          try { $video = Get-Content -Raw -LiteralPath 'C:\Evidence\video-capture-request.json' | ConvertFrom-Json } catch { $video = $null }
          if ($null -ne $video -and $video.pid -eq $script:app.Id -and $video.name -cin @('h264','vp9','invalid','retry','apng','network-timeout','network-retry','deadline-timeout','deadline-retry')) {
            $marker = "C:\Evidence\video-$($video.name)-desktop-captured"
            if (-not (Test-Path -LiteralPath $marker)) {
              Save-Desktop "video-$($video.name)-desktop.png"
              [IO.File]::WriteAllText($marker, 'captured')
            }
          }
        }
      }
    }
    $script:app.WaitForExit()
    $exitCode = $script:app.ExitCode
    $phaseResult = $null
    if (Test-Path -LiteralPath "C:\Evidence\$Phase.json") {
      $phaseResult = Get-Content -Raw -LiteralPath "C:\Evidence\$Phase.json" | ConvertFrom-Json
    }
    $result.phases += [ordered]@{ phase=$Phase; exitCode=$exitCode; report=$phaseResult; modules=@($modules | Sort-Object) }
    if ($Observe -or $exitCode -ne 0 -or $null -eq $phaseResult -or $phaseResult.status -ne 'passed') {
      throw "$Phase did not complete successfully (exit $exitCode)."
    }
  } finally {
    Stop-OwnedApp $Phase
  }
}

try {
  if (Test-Path -LiteralPath 'HKCU:\Software\Classes\aethertune') {
    throw 'The guest already has an AetherTune URL registration.'
  }
  $result.packages = @('probe.zip','production.zip') | ForEach-Object {
    [ordered]@{ file=$_; sha256=(Get-FileHash -LiteralPath (Join-Path 'C:\Input' $_)).Hash.ToLowerInvariant() }
  }
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'C:\Evidence\started.json'
  Expand-Archive -LiteralPath 'C:\Input\probe.zip' -DestinationPath 'C:\Probe'
  Expand-Archive -LiteralPath 'C:\Input\production.zip' -DestinationPath 'C:\Application'
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class GuestMediaKeys {
  [StructLayout(LayoutKind.Sequential)] struct KeyboardInput {
    public ushort key, scan; public uint flags, time; public UIntPtr extra;
  }
  [StructLayout(LayoutKind.Explicit, Size=32)] struct InputUnion {
    [FieldOffset(0)] public KeyboardInput keyboard;
  }
  [StructLayout(LayoutKind.Sequential)] struct Input {
    public uint type; public InputUnion value;
  }
  [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, Input[] inputs, int size);
  [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
  public static void Send(ushort key) {
    if (key != 0xb3 && key != 0xb0 && key != 0xb1) throw new ArgumentException("Unsupported test key");
    Input down = new Input { type=1, value=new InputUnion { keyboard=new KeyboardInput { key=key } } };
    Input up = down; up.value.keyboard.flags=2;
    int size = Marshal.SizeOf(typeof(Input));
    if (size != 40) throw new InvalidOperationException("Expected the x64 INPUT layout");
    if (SendInput(2, new Input[] { down, up }, size) != 2) throw new Win32Exception(Marshal.GetLastWin32Error());
  }
}
'@
  [void][GuestMediaKeys]::SetErrorMode(0x8003)
  $failures = @()
  foreach ($phase in @('exercise', 'reopen', 'production')) {
    try {
      if ($phase -eq 'production') { Run-App 'C:\Application' $phase -Observe }
      else { Run-App 'C:\Probe' $phase }
    } catch {
      $failures += [ordered]@{ phase=$phase; error=$_.Exception.Message }
    }
  }
  $result.failures = $failures
  $result.status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
} catch {
  $result.status = 'failed'
  $result.error = $_.Exception.Message
  Save-Desktop 'failure-desktop.png'
} finally {
  if ($null -ne $script:app) { Stop-OwnedApp 'cleanup' }
  $result.finishedAt = [DateTime]::UtcNow.ToString('o')
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath 'C:\Evidence\result.json'
  shutdown.exe /s /t 0
}
