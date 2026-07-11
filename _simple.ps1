param(
  [string]$Project  = $PSScriptRoot,   # folder to share (defaults to this script's folder)
  [string]$Password                    # shared password (auto-generated if omitted)
)

$ErrorActionPreference = 'Continue'
$root  = $PSScriptRoot
$tools = Join-Path $root 'tools'
$ttyd  = Join-Path $tools 'ttyd.exe'
$cfd   = Join-Path $tools 'cloudflared.exe'
$cflog = Join-Path $tools 'cf-simple.log'
$cferr = Join-Path $tools 'cf-simple.err.log'
$linkfile = Join-Path $root 'link.txt'

$PORT  = 7681
$GUSER = 'guest'

# Password: -Password / $env:SHARE_PASSWORD, otherwise generate a readable one.
if (-not $Password) { $Password = $env:SHARE_PASSWORD }
if (-not $Password) {
  $adj  = 'Swift','Calm','Brave','Lucky','Witty','Cosmic','Mellow','Amber','Cobalt','Jade'
  $noun = 'Otter','Falcon','Lynx','Heron','Bison','Marten','Raven','Ibex','Cedar','Quartz'
  $rng  = New-Object Random
  $Password = '{0}-{1}-{2}' -f $adj[$rng.Next($adj.Count)], $noun[$rng.Next($noun.Count)], $rng.Next(1000,9999)
}
$PASSWORD = $Password

New-Item -ItemType Directory -Force -Path $tools | Out-Null

# --- one-time, host-side downloads (remote users install NOTHING) ---
if (-not (Test-Path $ttyd)) {
  Write-Host 'Downloading ttyd (web terminal)...'
  try { Invoke-WebRequest 'https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.win32.exe' -OutFile $ttyd -UseBasicParsing } catch {}
}
if (-not (Test-Path $ttyd)) { Write-Host 'ERROR: ttyd download failed.'; Read-Host 'Enter to exit'; exit 1 }
if (-not (Test-Path $cfd)) {
  Write-Host 'Downloading cloudflared (public link)...'
  try { Invoke-WebRequest 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile $cfd -UseBasicParsing } catch {}
}
if (-not (Test-Path $cfd)) { Write-Host 'ERROR: cloudflared download failed.'; Read-Host 'Enter to exit'; exit 1 }

# --- free our port, stop OUR leftover ttyd/cloudflared only ---
# Scoped to the copies in tools\ so unrelated ttyd/cloudflared processes the
# user runs for something else are left alone.
$old = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue
if ($old) { $old.OwningProcess | Select-Object -Unique | ForEach-Object { cmd /c "taskkill /F /T /PID $_" > $null 2>&1 } }
Get-Process ttyd,cloudflared -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $ttyd -or $_.Path -eq $cfd } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1
Remove-Item $cflog,$cferr -ErrorAction SilentlyContinue

# --- job object so EVERYTHING dies with this window (kill-on-close) ---------
# Whatever we assign to this job (ttyd, its child shells, and cloudflared) is
# killed by Windows the instant this host window goes away - even a forced
# close - so a closed window can never leave an orphaned public tunnel running
# and accessible.
$job = [IntPtr]::Zero
try {
  if (-not ('Win32Job' -as [type])) {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Win32Job {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string n);
  [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr j, int c, IntPtr i, uint l);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
  [StructLayout(LayoutKind.Sequential)] struct BASIC {
    public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
    public UIntPtr MinWorkingSet; public UIntPtr MaxWorkingSet; public uint ActiveProcessLimit;
    public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass; }
  [StructLayout(LayoutKind.Sequential)] struct IOC {
    public ulong a; public ulong b; public ulong c; public ulong d; public ulong e; public ulong f; }
  [StructLayout(LayoutKind.Sequential)] struct EXT {
    public BASIC Basic; public IOC Io; public UIntPtr ProcMem; public UIntPtr JobMem;
    public UIntPtr PeakProcMem; public UIntPtr PeakJobMem; }
  public static IntPtr Create() {
    IntPtr j = CreateJobObject(IntPtr.Zero, null);
    if (j == IntPtr.Zero) return IntPtr.Zero;
    var e = new EXT(); e.Basic.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    int len = Marshal.SizeOf(e); IntPtr p = Marshal.AllocHGlobal(len);
    Marshal.StructureToPtr(e, p, false);
    bool ok = SetInformationJobObject(j, 9, p, (uint)len); // JobObjectExtendedLimitInformation
    Marshal.FreeHGlobal(p);
    return ok ? j : IntPtr.Zero;
  }
  public static bool Assign(IntPtr j, int pid) {
    return AssignProcessToJobObject(j, System.Diagnostics.Process.GetProcessById(pid).Handle);
  }
}
'@
  }
  $job = [Win32Job]::Create()
} catch { $job = [IntPtr]::Zero }

# --- start the web terminal (loopback only; the tunnel connects locally) ---
# Dark background for the web terminal (xterm.js theme). Inner quotes are
# escaped as \" so they survive to ttyd's JSON parser.
$theme = 'theme={\"background\":\"#0d0d0d\",\"foreground\":\"#e6e6e6\",\"cursor\":\"#d97757\"}'
$ttydProc = Start-Process -FilePath $ttyd -WindowStyle Minimized -PassThru -ArgumentList @(
  '-p',"$PORT",'-i','127.0.0.1','-W','-c',"${GUSER}:$PASSWORD",'-w',$Project,'-t',$theme,'powershell','-NoLogo')
if ($job -ne [IntPtr]::Zero -and $ttydProc) { try { [Win32Job]::Assign($job, $ttydProc.Id) | Out-Null } catch {} }
Start-Sleep 1

# --- public tunnel ---
$cfProc = Start-Process -FilePath $cfd -WindowStyle Minimized -PassThru `
  -ArgumentList @('tunnel','--url',"http://localhost:$PORT") `
  -RedirectStandardOutput $cflog -RedirectStandardError $cferr
if ($job -ne [IntPtr]::Zero -and $cfProc) { try { [Win32Job]::Assign($job, $cfProc.Id) | Out-Null } catch {} }

# --- always-on-top "philia live" indicator (host awareness) ----------------
$ovProc = $null
$overlayScript = Join-Path $root 'philia-overlay.ps1'
if (Test-Path $overlayScript) {
  try {
    $ovProc = Start-Process -FilePath 'powershell' -WindowStyle Hidden -PassThru -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-File',$overlayScript,'-HostPid',$PID)
    if ($job -ne [IntPtr]::Zero -and $ovProc) { try { [Win32Job]::Assign($job, $ovProc.Id) | Out-Null } catch {} }
  } catch {}
}

# --- read the public link (shared read so the file lock can't block us) ---
function Read-Shared($p){ try { $fs=[IO.File]::Open($p,'Open','Read','ReadWrite'); $sr=New-Object IO.StreamReader($fs); $t=$sr.ReadToEnd(); $sr.Close(); $fs.Close(); return $t } catch { return '' } }

Clear-Host
Write-Host '=================================================================='
Write-Host '   PHILIA SIMPLE SESSION'
Write-Host '=================================================================='
Write-Host ''
$spin = '|','/','-','\'
$link = $null
for ($i=0; $i -lt 45 -and -not $link; $i++) {
  Write-Host ("`r   Loading - waiting for the public link...  {0} " -f $spin[$i % $spin.Count]) -NoNewline
  Start-Sleep 1
  foreach ($f in @($cflog,$cferr)) { $m=[regex]::Match((Read-Shared $f),'https://[a-z0-9.-]+\.trycloudflare\.com'); if($m.Success){ $link=$m.Value; break } }
}

Clear-Host
Write-Host '=================================================================='
if ($link) {
  Set-Content -Path $linkfile -Value $link -Encoding ascii
  Write-Host '   PHILIA SIMPLE SESSION - SEND THE OTHER PERSON ALL THREE:'
  Write-Host '=================================================================='
  Write-Host ''
  Write-Host "       Link:     $link"
  Write-Host "       Username: $GUSER"
  Write-Host "       Password: $PASSWORD"
  Write-Host ''
  Write-Host "   (link also saved to $linkfile)"
  Write-Host ''
  Write-Host '   They open the link in ANY browser - they install nothing.'
} else {
  Write-Host '   Could not detect the link.'
  Write-Host "   Check $cflog"
}
Write-Host '=================================================================='
Write-Host ''
Write-Host '   This grants FULL control of a shell on this PC (your files and'
Write-Host '   anything you are signed into) to everyone with the link, the'
Write-Host '   username, and the password.'
Write-Host '   KEEP THIS WINDOW OPEN. Press Enter here to STOP sharing.'
Write-Host '=================================================================='

# --- linked shutdown: stop everything if ANY piece stops -------------------
# Wait until the host presses Enter, OR ttyd exits, OR the tunnel dies.
# Whichever happens first, we tear down the rest so nothing is left running or
# publicly exposed. The job object above is the backstop for a hard window close.
$reason = $null
while (-not $reason) {
  if ($ttydProc.HasExited) { $reason = 'the web terminal stopped'; break }
  if ($cfProc.HasExited)   { $reason = 'the tunnel stopped';       break }
  try {
    if ([Console]::KeyAvailable) {
      $k = [Console]::ReadKey($true)
      if ($k.Key -eq 'Enter') { $reason = 'you pressed Enter'; break }
    }
  } catch { Read-Host | Out-Null; $reason = 'you pressed Enter'; break }
  Start-Sleep -Milliseconds 300
}

Write-Host ''
Write-Host "Stopping session ($reason)..."

# --- clean up everything we started (and the shells ttyd spawned) ---
if ($ovProc   -and -not $ovProc.HasExited)   { try { Stop-Process -Id $ovProc.Id -Force -ErrorAction SilentlyContinue } catch {} }
if ($cfProc   -and -not $cfProc.HasExited)   { try { Stop-Process -Id $cfProc.Id -Force -ErrorAction SilentlyContinue } catch {} }
if ($ttydProc -and -not $ttydProc.HasExited) { cmd /c "taskkill /F /T /PID $($ttydProc.Id)" > $null 2>&1 }
Write-Host 'Session stopped. You can close this window.'
