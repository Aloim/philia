@echo off
title philia - collaborative session
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_philia.ps1" %*
