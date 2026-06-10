@echo off
title collabterm - collaborative session
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-collab.ps1" %*
