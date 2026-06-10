@echo off
setlocal enabledelayedexpansion
title Share Claude Code session

set "TOOLS=%~dp0tools"
set "PORT=7681"
set "GUSER=guest"

REM ---- which folder to share (defaults to this script's own folder) ----
REM Pass a path as the first argument to share a different folder, e.g.:
REM     launch-simple.bat "C:\path\to\my project"
set "PROJECT=%~1"
if not defined PROJECT set "PROJECT=%~dp0"
if "%PROJECT:~-1%"=="\" set "PROJECT=%PROJECT:~0,-1%"

REM ---- shared password ----
REM A fresh, readable password is generated every run and shown below.
REM Set SHARE_PASSWORD before running if you want to pin a fixed one.
set "GPASS=%SHARE_PASSWORD%"
if not defined GPASS for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "$a='Swift','Calm','Brave','Lucky','Witty','Cosmic','Mellow','Amber','Cobalt','Jade';$n='Otter','Falcon','Lynx','Heron','Bison','Marten','Raven','Ibex','Cedar','Quartz';$r=New-Object Random;'{0}-{1}-{2}' -f $a[$r.Next($a.Count)],$n[$r.Next($n.Count)],$r.Next(1000,9999)"`) do set "GPASS=%%p"
set "TTYD=%TOOLS%\ttyd.exe"
set "CFD=%TOOLS%\cloudflared.exe"
set "CFLOG=%TOOLS%\cf.log"
set "LINKFILE=%~dp0link.txt"

if not exist "%TOOLS%" mkdir "%TOOLS%"

REM ---- one-time, host-side download (the REMOTE person downloads NOTHING) ----
if not exist "%TTYD%" (
  echo Downloading ttyd ^(web terminal^) ...
  powershell -NoProfile -Command "try{Invoke-WebRequest -Uri 'https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.win32.exe' -OutFile '%TTYD%' -UseBasicParsing}catch{exit 1}"
)
if not exist "%CFD%" (
  echo Downloading cloudflared ^(public link^) ...
  powershell -NoProfile -Command "try{Invoke-WebRequest -Uri 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile '%CFD%' -UseBasicParsing}catch{exit 1}"
)
if not exist "%TTYD%" ( echo. & echo ERROR: could not download ttyd. & pause & exit /b 1 )
if not exist "%CFD%"  ( echo. & echo ERROR: could not download cloudflared. & pause & exit /b 1 )

REM ---- kill any leftover session so ports/passwords/links are clean ----
taskkill /f /im ttyd.exe >nul 2>&1
taskkill /f /im cloudflared.exe >nul 2>&1

REM ---- start the writable web terminal, launching Claude Code in the project ----
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_simple-terminal.ps1" -Ttyd "%TTYD%" -Port "%PORT%" -Cred "%GUSER%:%GPASS%" -Cwd "%PROJECT%"

REM ---- start the public tunnel, capturing its output so we can read the link ----
del "%CFLOG%" >nul 2>&1
start "cloudflared" /min cmd /c "%CFD% tunnel --url http://localhost:%PORT% > %CFLOG% 2>&1"

cls
echo ==================================================================
echo    SHARING A CLAUDE CODE SESSION - waiting for public link...
echo ==================================================================
set "LINK="
for /l %%i in (1,1,45) do (
  if not defined LINK (
    for /f "delims=" %%u in ('powershell -NoProfile -Command "try{$fs=[IO.File]::Open('%CFLOG%','Open','Read','ReadWrite');$sr=New-Object IO.StreamReader($fs);$t=$sr.ReadToEnd();$sr.Close();$fs.Close();$m=[regex]::Match($t,'https://[a-z0-9.-]+\.trycloudflare\.com');if($m.Success){$m.Value}}catch{}"') do set "LINK=%%u"
    if not defined LINK ( timeout /t 1 /nobreak >nul )
  )
)

cls
if defined LINK (
  > "%LINKFILE%" echo !LINK!
  echo ==================================================================
  echo    SEND THE OTHER PERSON ALL THREE:
  echo ==================================================================
  echo.
  echo        Link:     !LINK!
  echo        Username: %GUSER%
  echo        Password: %GPASS%
  echo.
  echo    ^(link also saved to: %LINKFILE%^)
  echo.
  echo    They open the link in ANY browser - they install nothing.
  echo    This grants FULL control of Claude on this PC, including
  echo    your files and anything you are signed into.
) else (
  echo    Could not auto-detect the link. Open this file and look for a
  echo    https://...trycloudflare.com  line:
  echo        %CFLOG%
)
echo ==================================================================
echo.
echo    KEEP THIS WINDOW OPEN. Press any key to STOP sharing.
pause >nul
taskkill /f /im cloudflared.exe >nul 2>&1
taskkill /f /im ttyd.exe >nul 2>&1
endlocal
