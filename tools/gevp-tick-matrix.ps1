# Runs tools/gevp_tick_breakdown.gd (per-car tick pieces) or
# tools/traffic_profile.gd (whole-frame split) over a matrix of
#   build    debug (the editor .exe) | release (the release export template)
#   physics  godot | jolt
#   tyres    gd (vendored GDScript) | native (C++ GevpTyreNative)
# headless, several rounds, the order reversed every other round so a busy
# laptop hits every combination alike.
#
#   powershell -File tools/gevp-tick-matrix.ps1
#   powershell -File tools/gevp-tick-matrix.ps1 -Tool profile -Cars 40 -Builds release -Rounds 3
#
# Physics engine and (for release) the tool itself are chosen through
# override.cfg next to project.godot, rewritten before each run and left empty
# at the end. A release template cannot take --path or -s, so it is copied
# into the project folder (*.exe is gitignored) and started from there.
# Raw results: bench-results/<tool>-matrix-<timestamp>.jsonl, one JSON per run,
# with "combo" added.
param(
	[ValidateSet("tick", "profile")] [string] $Tool = "tick",
	[string[]] $Builds = @("debug", "release"),
	[string[]] $Physics = @("godot", "jolt"),
	[string[]] $Tyres = @("gd", "native"),
	[int] $Rounds = 4,
	[int] $Secs = 10,
	[int] $Cars = 40,
	[int] $Detail = 300,
	[string] $Godot = "$HOME/Documents/Godot_v4.7.2-stable_win64_console.exe",
	[string] $Template = "$env:APPDATA/Godot/export_templates/4.7.2.stable/windows_release_x86_64_console.exe",
	[int] $TimeoutSec = 600
)

$ErrorActionPreference = "Continue"
$Builds = @($Builds | ForEach-Object { $_.Split(",") })
$Physics = @($Physics | ForEach-Object { $_.Split(",") })
$Tyres = @($Tyres | ForEach-Object { $_.Split(",") })
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "bench-results"
New-Item -ItemType Directory -Force $dir | Out-Null
$out = Join-Path $dir ("{0}-matrix-{1}.jsonl" -f $Tool, (Get-Date -Format "yyyy-MM-dd_HHmmss"))
$override = Join-Path $root "override.cfg"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script = if ($Tool -eq "tick") { "gevp_tick_breakdown" } else { "traffic_profile" }
$class = if ($Tool -eq "tick") { "GevpTickBreakdown" } else { "TrafficProfile" }
$tag = if ($Tool -eq "tick") { "TICK_JSON " } else { "TPROF_JSON " }
$releaseExe = Join-Path $root "release_console.exe"
if (($Builds -contains "release") -and -not (Test-Path $releaseExe)) { Copy-Item $Template $releaseExe }

$combos = @()
foreach ($b in $Builds) { foreach ($p in $Physics) { foreach ($t in $Tyres) { $combos += ,@($b, $p, $t) } } }

for ($r = 1; $r -le $Rounds; $r++) {
	for ($k = 0; $k -lt $combos.Count; $k++) {
		$c = $combos[$(if ($r % 2 -eq 0) { $combos.Count - 1 - $k } else { $k })]
		$build, $phys, $tyre = $c
		$cfg = ""
		if ($phys -eq "jolt") { $cfg += "[physics]`n3d/physics_engine=`"Jolt Physics`"`n" }
		if ($build -eq "release") { $cfg += "[application]`nrun/main_loop_type=`"$class`"`n" }
		[IO.File]::WriteAllText($override, $cfg, $utf8)
		$a = @("--headless", "--fixed-fps", "60", "--audio-driver", "Dummy")
		if ($build -eq "debug") { $a += @("--path", "`"$root`"", "-s", "res://tools/$script.gd") }
		$a += @("--", "--benchmark", "--secs=$Secs", "--traffic=$Cars", "--detail=$Detail")
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = $(if ($build -eq "debug") { $Godot } else { $releaseExe })
		$psi.Arguments = ($a -join " ")
		$psi.WorkingDirectory = $root
		$psi.UseShellExecute = $false
		$psi.RedirectStandardOutput = $true
		$psi.RedirectStandardError = $true
		$psi.EnvironmentVariables["NEON_NATIVE_TYRES"] = $(if ($tyre -eq "native") { "1" } else { "0" })
		$others = @(Get-Process | Where-Object { $_.Name -like "Godot*" }).Count
		Write-Host ("[{0}] round {1}/{2}  {3} {4} {5}  other Godot={6}" -f (Get-Date -Format "HH:mm:ss"), $r, $Rounds, $build, $phys, $tyre, $others)
		$p = [System.Diagnostics.Process]::Start($psi)
		try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High } catch {}
		$so = $p.StandardOutput.ReadToEndAsync()
		$null = $p.StandardError.ReadToEndAsync()
		if (-not $p.WaitForExit($TimeoutSec * 1000)) {
			taskkill /T /F /PID $p.Id | Out-Null
			Write-Host "  TIMEOUT: killed after $TimeoutSec s"
			continue
		}
		$line = $so.Result -split "`n" | Where-Object { $_.StartsWith($tag) } | Select-Object -First 1
		if (-not $line) { Write-Host "  no result line"; continue }
		$json = $line.Substring($tag.Length).Trim()
		$json = "{`"combo`":`"$build $phys $tyre`",`"others`":$others," + $json.Substring(1)
		[IO.File]::AppendAllText($out, $json + "`n", $utf8)
	}
}
[IO.File]::WriteAllText($override, "", $utf8)
Write-Host "raw: $out"
