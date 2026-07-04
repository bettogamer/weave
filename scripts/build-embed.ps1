# build-embed.ps1 — packages a release build of Weave, ready to EMBED in a consumer
# (e.g. Craft/libs/Weave, per ADR-0006) or to install standalone. The package is the
# Weave/ folder as-is: consumers include libs\Weave\Weave.xml from their toc/xml.
# Gate: the full test suite and luacheck must be green, or no package is produced.
# Usage: powershell -File scripts/build-embed.ps1 [-OutDir dist]
param(
    [string]$OutDir = "dist"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

# Version comes from Weave.lua (single source of truth)
$weaveLua = Get-Content (Join-Path $repo "Weave\Weave.lua") -Raw
if ($weaveLua -notmatch '_VERSION\s*=\s*"(\d+\.\d+\.\d+)"') {
    throw "could not find Weave._VERSION in Weave/Weave.lua"
}
$version = $Matches[1]

Push-Location $repo
try {
    # Gate 1: full headless suite
    $specs = Get-ChildItem "tests" -Recurse -Filter "*_spec.lua" | ForEach-Object {
        (Resolve-Path -Relative $_.FullName) -replace "\\", "/"
    }
    lua tests/run.lua @specs
    if ($LASTEXITCODE -ne 0) { throw "test suite failed - not packaging" }

    # Gate 2: luacheck over the library (vendored libs/ excluded by .luacheckrc)
    $luaFiles = Get-ChildItem "Weave" -Recurse -Filter "*.lua" |
        Where-Object { $_.FullName -notmatch "\\libs\\" } | ForEach-Object {
            (Resolve-Path -Relative $_.FullName) -replace "\\", "/"
        }
    luacheck @luaFiles --config .luacheckrc
    if ($LASTEXITCODE -ne 0) { throw "luacheck failed - not packaging" }
}
finally { Pop-Location }

$dest = Join-Path $repo "$OutDir\Weave-v$version\Weave"
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item -Recurse (Join-Path $repo "Weave\*") $dest

Write-Host ""
Write-Host "packaged Weave v$version -> $dest"
Write-Host "to embed: copy the inner 'Weave' folder to <consumer>/libs/Weave and"
Write-Host "include libs\Weave\Weave.xml from the consumer's .toc or .xml."
Write-Host "record the embedded version ($version) in the consumer's docs."
