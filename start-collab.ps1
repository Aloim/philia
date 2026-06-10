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

# --- start the collaborative terminal server ---
$env:PORT           = "$PORT"
$env:SHARE_PASSWORD = $PASSWORD
$env:SHARE_CWD      = $PROJECT
$nodeProc = Start-Process -FilePath 'node' -ArgumentList ('"' + (Join-Path $collab 'server.js') + '"') `
  -WindowStyle Minimized -PassThru `
  -RedirectStandardOutput (Join-Path $collab 'server.out.log') `
  -RedirectStandardError  (Join-Path $collab 'server.err.log')
Start-Sleep 2

# --- public tunnel ---
$cfProc = Start-Process -FilePath $cfd -WindowStyle Minimized -PassThru `
  -ArgumentList @('tunnel','--url',"http://localhost:$PORT") `
  -RedirectStandardOutput $cflog -RedirectStandardError $cferr

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
Write-Host '   This grants FULL control of Claude on this PC (your files and'
Write-Host '   anything you are signed into) to everyone with the link + password.'
Write-Host '   KEEP THIS WINDOW OPEN. Press Enter to STOP sharing.'
Read-Host | Out-Null

# --- clean up only what we started (and its child shells) ---
if ($cfProc)   { try { Stop-Process -Id $cfProc.Id -Force -ErrorAction SilentlyContinue } catch {} }
if ($nodeProc) { cmd /c "taskkill /F /T /PID $($nodeProc.Id)" > $null 2>&1 }
