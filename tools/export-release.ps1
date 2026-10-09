# Exports the Windows release build and puts the licence notices next to it
# (release readiness, 2026-10-08).
#
#   powershell -File tools/export-release.ps1
#
# Output in build/: the exe (product name and version come from project.godot,
# see scripts/core/game_info.gd) and THIRD_PARTY_NOTICES.txt, which Godot's and
# GEVP's MIT licences ask to ship with every copy. Zip or upload the two
# together. Needs the Godot 4.7.2 export templates (Editor > Manage Export
# Templates). Godot is looked up in $env:GODOT, then in Documents.
param([string] $Godot = $env:GODOT)
$ErrorActionPreference = "Stop"
if (-not $Godot) { $Godot = Join-Path $env:USERPROFILE "Documents\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $Godot)) { Write-Error "Godot not found at $Godot. Set GODOT to the console exe."; exit 2 }
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
New-Item -ItemType Directory -Force build | Out-Null

# The exe's product name: Godot does not fill it from project.godot (its
# versions it does), so copy the name across. A rename shows up as this one
# line changing in export_presets.cfg; commit it with the project.godot change.
$name = (Select-String -Path project.godot -Pattern '^config/name="(.*)"$').Matches[0].Groups[1].Value
$presets = Get-Content export_presets.cfg -Raw
$synced = $presets -replace '(?m)^application/product_name=".*"$', ('application/product_name="' + $name + '"')
if ($synced -ne $presets) { [IO.File]::WriteAllText((Join-Path $root "export_presets.cfg"), $synced) ; Write-Host "export_presets.cfg: product name set to $name" }

& $Godot --headless --path . --import | Out-Null
& $Godot --headless --path . -s res://tools/write_licence_notices.gd -- res://build/THIRD_PARTY_NOTICES.txt
if ($LASTEXITCODE -ne 0) { Write-Error "Writing the licence notices failed."; exit 1 }
& $Godot --headless --path . --export-release "Windows Desktop" build/NeonOverdrive.exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path build/NeonOverdrive.exe)) { Write-Error "Export failed."; exit 1 }
Write-Host "Built:"
Get-ChildItem build -File | Format-Table Name, Length -AutoSize
