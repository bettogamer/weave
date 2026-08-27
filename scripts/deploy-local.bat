@echo off
REM deploy-local.bat — wrapper for deploy-local.ps1 on machines whose PowerShell
REM ExecutionPolicy blocks scripts ("la ejecucion de scripts esta deshabilitada").
REM -ExecutionPolicy Bypass applies to THIS process only: nothing on the system
REM changes, and no elevation is needed.
REM
REM Usage (from the repo root, or by double-clicking it):
REM   scripts\deploy-local.bat
REM   scripts\deploy-local.bat -AddOnsPath "D:\WoW\_retail_\Interface\AddOns"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-local.ps1" %*
