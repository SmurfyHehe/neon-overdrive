# Runs tools/crossing_bench.gd (engine-call cost per car per tick, from C++)
# over a matrix of
#   build    debug (the editor .exe) | release (the release export template)
#   physics  godot | jolt
#   cars     one run per car count (full-sim cars, --detail=300)
# headless, several rounds, the order reversed every other round so a busy
# laptop hits every combination alike. One Godot at a time. Cars drive on GDScript
# tyres (NEON_NATIVE_TYRES=0), as the game does today.
#
#   powershell -File tools/crossing-bench-matrix.ps1
#   powershell -File tools/crossing-bench-matrix.ps1 -Builds debug -Cars 22 -Rounds 1 -Secs 12
#
# Physics engine and (for release) the tool itself are chosen through
# override.cfg next to project.godot, rewritten before each run and left empty
# at the end. A release template cannot take --path or -s, so it is copied
# into the project folder (*.exe is gitignored, as release_console.exe next to
# release.exe) and started from there.
# Raw results: bench-results/crossing-matrix-<timestamp>.jsonl, one JSON per
# run, with "combo" added.
param(
	[string[]] $Builds = @("debug", "release"),
	[string[]] $Physics = @("godot", "jolt"),
	[string[]] $Cars = @("30", "54"),
	[int] $Rounds = 3,
	[int] $Secs = 38,
	[string] $Godot = "$HOME/Documents/Godot_v4.7.2-stable_win64_console.exe",
	[string] $Template = "$env:APPDATA/Godot/export_templates/4.7.2.stable/windows_release_x86_64_console.exe",
	[int] $TimeoutSec = 300
)

$ErrorActionPreference = "Continue"
$Builds = @($Builds | ForEach-Object { $_.Split(",") })
$Physics = @($Physics | ForEach-Object { $_.Split(",") })
$Cars = @($Cars | ForEach-Object { $_.Split(",") })
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "bench-results"
New-Item -ItemType Directory -Force $dir | Out-Null
$out = Join-Path $dir ("crossing-matrix-{0}.jsonl" -f (Get-Date -Format "yyyy-MM-dd_HHmmss"))
$override = Join-Path $root "override.cfg"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$releaseExe = Join-Path $root "release_console.exe"
# The console template starts "<its own name minus _console>.exe", so the
# non-console template is copied next to it as release.exe.
if (($Builds -contains "release") -and -not (Test-Path $releaseExe)) { Copy-Item $Template $releaseExe }
$releaseMain = Join-Path $root "release.exe"
if (($Builds -contains "release") -and -not (Test-Path $releaseMain)) { Copy-Item ($Template -replace "_console", "") $releaseMain }

$combos = @()
foreach ($b in $Builds) { foreach ($p in $Physics) { foreach ($n in $Cars) { $combos += ,@($b, $p, $n) } } }

for ($r = 1; $r -le $Rounds; $r++) {
	for ($k = 0; $k -lt $combos.Count; $k++) {
		$c = $combos[$(if ($r % 2 -eq 0) { $combos.Count - 1 - $k } else { $k })]
		$build, $phys, $n = $c
		$cfg = ""
		if ($phys -eq "jolt") { $cfg += "[physics]`n3d/physics_engine=`"Jolt Physics`"`n" }
		if ($build -eq "release") { $cfg += "[application]`nrun/main_loop_type=`"CrossingBenchTool`"`n" }
		[IO.File]::WriteAllText($override, $cfg, $utf8)
		$a = @("--headless", "--fixed-fps", "60", "--audio-driver", "Dummy")
		if ($build -eq "debug") { $a += @("--path", "`"$root`"", "-s", "res://tools/crossing_bench.gd") }
		$a += @("--", "--benchmark", "--secs=$Secs", "--traffic=$n", "--detail=300")
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = $(if ($build -eq "debug") { $Godot } else { $releaseExe })
		$psi.Arguments = ($a -join " ")
		$psi.WorkingDirectory = $root
		$psi.UseShellExecute = $false
		$psi.RedirectStandardOutput = $true
		$psi.RedirectStandardError = $true
		$psi.EnvironmentVariables["NEON_NATIVE_TYRES"] = "0"
		$others = @(Get-Process | Where-Object { $_.Name -like "Godot*" -or $_.Name -like "release_console*" }).Count
		Write-Host ("[{0}] round {1}/{2}  {3} {4} cars={5}  other Godot={6}" -f (Get-Date -Format "HH:mm:ss"), $r, $Rounds, $build, $phys, $n, $others)
		$p = [System.Diagnostics.Process]::Start($psi)
		try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High } catch {}
		$so = $p.StandardOutput.ReadToEndAsync()
		$null = $p.StandardError.ReadToEndAsync()
		if (-not $p.WaitForExit($TimeoutSec * 1000)) {
			taskkill /T /F /PID $p.Id | Out-Null
			Write-Host "  TIMEOUT: killed after $TimeoutSec s"
			continue
		}
		$line = $so.Result -split "`n" | Where-Object { $_.StartsWith("CBENCH_JSON ") } | Select-Object -First 1
		if (-not $line) { Write-Host "  no result line"; continue }
		$json = $line.Substring(12).Trim()
		$json = "{`"combo`":`"$build $phys $n`",`"round`":$r,`"others`":$others," + $json.Substring(1)
		[IO.File]::AppendAllText($out, $json + "`n", $utf8)
	}
}
[IO.File]::WriteAllText($override, "", $utf8)
Write-Host "raw: $out"
