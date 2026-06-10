param(
  [string]$Project  = $PSScriptRoot,   # folder to share (defaults to this script's folder)
  [string]$Password                    # shared password (auto-generated if omitted)
)

$ErrorActionPreference = 'Continue'
$root   = $PSScriptRoot
$collab = Join-Path $root 'collab'
$tools  = Join-Path $root 'tools'
$cfd    = Join-Path $tools 'cloudflared.exe'
$cflog  = Join-Path $tools 'cf-collab.log'
$cferr  = Join-Path $tools 'cf-collab.err.log'
$linkfile = Join-Path $root 'link.txt'

$PORT     = 7681

# Password: -Password / $env:SHARE_PASSWORD, otherwise generate a readable one.
if (-not $Password) { $Password = $env:SHARE_PASSWORD }
if (-not $Password) {
  $adj  = 'Swift','Calm','Brave','Lucky','Witty','Cosmic','Mellow','Amber','Cobalt','Jade'
  $noun = 'Otter','Falcon','Lynx','Heron','Bison','Marten','Raven','Ibex','Cedar','Quartz'
  $rng  = New-Object Random
  $Password = '{0}-{1}-{2}' -f $adj[$rng.Next($adj.Count)], $noun[$rng.Next($noun.Count)], $rng.Next(1000,9999)
}
$PASSWORD = $Password
$PROJECT  = $Project   # defaults to this script's folder (see -Project param)

# Host-only kill switch. A secret known ONLY to this local host window: the host
# opens the admin URL below (on this PC) to get an in-browser "Stop session"
# button. It is never shown over the tunnel and never written to link.txt.
$AdminToken = ([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))
$adminUrl   = "http://localhost:$PORT/?admin=$AdminToken"

New-Item -ItemType Directory -Force -Path $tools | Out-Null

# --- cloudflared (host-side; remote users install NOTHING) ---
if (-not (Test-Path $cfd)) {
  Write-Host 'Downloading cloudflared...'
  try { Invoke-WebRequest 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile $cfd -UseBasicParsing } catch {}
}
if (-not (Test-Path $cfd)) { Write-Host 'ERROR: cloudflared download failed.'; Read-Host 'Enter to exit'; exit 1 }

# --- node dependencies (one-time) ---
if (-not (Test-Path (Join-Path $collab 'node_modules'))) {
  Write-Host 'Installing terminal-server dependencies (one-time, ~1 min)...'
  Push-Location $collab
  & npm install ws "@homebridge/node-pty-prebuilt-multiarch" --no-audit --no-fund --loglevel=error
  Pop-Location
}

# --- free our port (old session/ttyd), stop leftover cloudflared (safe) ---
$old = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue
if ($old) { $old.OwningProcess | Select-Object -Unique | ForEach-Object { cmd /c "taskkill /F /T /PID $_" > $null 2>&1 } }
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1
Remove-Item $cflog,$cferr -ErrorAction SilentlyContinue

# --- job object so EVERYTHING dies with this window (kill-on-close) ---------
# Whatever we assign to this job (the node server, cloudflared, and the child
# shells node spawns) is killed by Windows the instant this host window goes
# away - even a forced close - so a closed window can never leave an orphaned
# public tunnel running and accessible.
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

# --- start the collaborative terminal server ---
$env:PORT              = "$PORT"
$env:SHARE_PASSWORD    = $PASSWORD
$env:SHARE_CWD         = $PROJECT
$env:SHARE_ADMIN_TOKEN = $AdminToken
$nodeProc = Start-Process -FilePath 'node' -ArgumentList ('"' + (Join-Path $collab 'server.js') + '"') `
  -WindowStyle Minimized -PassThru `
  -RedirectStandardOutput (Join-Path $collab 'server.out.log') `
  -RedirectStandardError  (Join-Path $collab 'server.err.log')
# Tie the server (and every shell it later spawns) to the kill-on-close job.
if ($job -ne [IntPtr]::Zero -and $nodeProc) { try { [Win32Job]::Assign($job, $nodeProc.Id) | Out-Null } catch {} }
Start-Sleep 2

# --- public tunnel ---
$cfProc = Start-Process -FilePath $cfd -WindowStyle Minimized -PassThru `
  -ArgumentList @('tunnel','--url',"http://localhost:$PORT") `
  -RedirectStandardOutput $cflog -RedirectStandardError $cferr
# Tie the tunnel to the same kill-on-close job.
if ($job -ne [IntPtr]::Zero -and $cfProc) { try { [Win32Job]::Assign($job, $cfProc.Id) | Out-Null } catch {} }

# --- always-on-top "collabterm live" indicator (host awareness) ------------
# A topmost red dot in the top-right of the screen so the host can't lose track
# of an open session, even with every window minimized. Tied to the same job,
# so it shows for exactly as long as the session is live.
$ovProc = $null
$overlayScript = Join-Path $root 'collab-overlay.ps1'
if (Test-Path $overlayScript) {
  try {
    $ovProc = Start-Process -FilePath 'powershell' -WindowStyle Hidden -PassThru -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-File',$overlayScript,'-HostPid',$PID)
    if ($job -ne [IntPtr]::Zero -and $ovProc) { try { [Win32Job]::Assign($job, $ovProc.Id) | Out-Null } catch {} }
  } catch {}
}

# --- read the public link (shared read so the file lock can't block us) ---
function Read-Shared($p){ try { $fs=[IO.File]::Open($p,'Open','Read','ReadWrite'); $sr=New-Object IO.StreamReader($fs); $t=$sr.ReadToEnd(); $sr.Close(); $fs.Close(); return $t } catch { return '' } }
$link = $null
for ($i=0; $i -lt 45 -and -not $link; $i++) {
  Start-Sleep 1
  foreach ($f in @($cflog,$cferr)) { $m=[regex]::Match((Read-Shared $f),'https://[a-z0-9.-]+\.trycloudflare\.com'); if($m.Success){ $link=$m.Value; break } }
}

Clear-Host
Write-Host '=================================================================='
if ($link) {
  Set-Content -Path $linkfile -Value $link -Encoding ascii
  Write-Host '   COLLABORATIVE CLAUDE SESSION'
  Write-Host '=================================================================='
  Write-Host ''
  Write-Host "       Link:     $link"
  Write-Host "       Password: $PASSWORD"
  Write-Host ''
  Write-Host "   (link also saved to $linkfile)"
  Write-Host ''
  Write-Host '   Everyone opens the link, enters the password, picks a name.'
  Write-Host '   They all SEE & CONTROL the same terminal + a shared chat.'
  Write-Host '   Browser only - nobody installs anything.'
} else {
  Write-Host '   Could not detect the link.'
  Write-Host "   Check $cflog  and  $collab\server.err.log"
}
Write-Host '=================================================================='
Write-Host ''
Write-Host '   HOST CONTROLS (this PC only - do NOT share this link):'
Write-Host "       $adminUrl"
Write-Host '   Open it on this PC, enter the password, and you get a red'
Write-Host '   "Stop session" button that kills the WHOLE session for everyone.'
Write-Host ''
Write-Host '   This grants FULL control of Claude on this PC (your files and'
Write-Host '   anything you are signed into) to everyone with the link + password.'
Write-Host '   KEEP THIS WINDOW OPEN. Press Enter here (or click "Stop session"'
Write-Host '   in the host tab) to STOP sharing.'
Write-Host '=================================================================='

# --- linked shutdown: stop everything if ANY piece stops -------------------
# Wait until the host presses Enter, OR the node server exits (e.g. the
# in-browser "Stop session" button), OR the tunnel dies. Whichever happens
# first, we tear down the rest so nothing is left running or publicly exposed.
# The job object above is the backstop for a hard window close.
$reason = $null
while (-not $reason) {
  if ($nodeProc.HasExited) { $reason = 'the terminal server stopped'; break }
  if ($cfProc.HasExited)   { $reason = 'the tunnel stopped';          break }
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

# --- clean up everything we started (and its child shells/agents) ---
if ($ovProc   -and -not $ovProc.HasExited)   { try { Stop-Process -Id $ovProc.Id -Force -ErrorAction SilentlyContinue } catch {} }
if ($cfProc   -and -not $cfProc.HasExited)   { try { Stop-Process -Id $cfProc.Id -Force -ErrorAction SilentlyContinue } catch {} }
if ($nodeProc -and -not $nodeProc.HasExited) { cmd /c "taskkill /F /T /PID $($nodeProc.Id)" > $null 2>&1 }
Write-Host 'Session stopped. You can close this window.'
