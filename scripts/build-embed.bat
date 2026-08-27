@echo off
REM build-embed.bat — wrapper for build-embed.ps1 on machines whose PowerShell
REM ExecutionPolicy blocks scripts ("la ejecucion de scripts esta deshabilitada").
REM -ExecutionPolicy Bypass applies to THIS process only: nothing on the system
REM changes, and no elevation is needed.
REM
REM Packages dist\Weave-v<version>\ (version read from Weave/Weave.lua). Gated on
REM the full test suite and luacheck, so `lua` and `luacheck` must be on PATH.
REM
REM Usage (from the repo root):
REM   scripts\build-embed.bat
REM   scripts\build-embed.bat -OutDir dist
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-embed.ps1" %*
