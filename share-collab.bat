@echo off
title Claude collaborative session
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-collab.ps1" %*
