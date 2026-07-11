@echo off
title philia - simple session
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_simple.ps1" %*
