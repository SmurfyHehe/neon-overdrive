# Rebuilds Godot's per-machine class cache (.godot/global_script_class_cache.cfg).
#
# .godot/ is gitignored, so when a pull deletes or moves a script that
# declares a class_name, your local cache still points at the old path and
# the game fails to boot with a missing-script / parse error (issue #42).
# Opening the project once in the editor rebuilds the cache; this does it
# headless and exits.
#
# Usage (from anywhere):  powershell -File tools/refresh-godot-cache.ps1
# Godot is found via $env:GODOT, then PATH, then ~/Documents.

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

$godot = $env:GODOT
if (-not $godot) {
    foreach ($name in 'godot', 'Godot_v4.7.2-stable_win64_console') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $godot = $cmd.Source; break }
    }
}
if (-not $godot) {
    $found = Get-ChildItem "$HOME\Documents" -Filter 'Godot_v4*_console.exe' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($found) { $godot = $found.FullName }
}
if (-not $godot -or -not (Test-Path $godot)) {
    Write-Error "Godot not found. Set `$env:GODOT to the Godot console executable and re-run."
}

Write-Host "Refreshing class cache with $godot"
& $godot --headless --editor --quit --path $projectDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Done. The game should boot now."
