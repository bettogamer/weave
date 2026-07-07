# deploy-local.ps1 — copies Weave (standalone library addon) and WeaveDemo into the
# local WoW AddOns folder for in-game testing. Usage:
#   powershell -File scripts/deploy-local.ps1 [-AddOnsPath <path>]
param(
    [string]$AddOnsPath = "F:\Games\World of Warcraft\_retail_\Interface\AddOns"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $AddOnsPath)) {
    throw "AddOns folder not found: $AddOnsPath (pass -AddOnsPath)"
}

foreach ($pair in @(
    @{ src = Join-Path $repo "Weave";           dest = Join-Path $AddOnsPath "Weave" },
    @{ src = Join-Path $repo "demo\WeaveDemo";  dest = Join-Path $AddOnsPath "WeaveDemo" },
    @{ src = Join-Path $repo "demo\MiOro";      dest = Join-Path $AddOnsPath "MiOro" }
)) {
    if (Test-Path $pair.dest) { Remove-Item -Recurse -Force $pair.dest }
    Copy-Item -Recurse $pair.src $pair.dest
    Write-Host ("deployed " + $pair.dest)
}
Write-Host "Done - /reload in game."
