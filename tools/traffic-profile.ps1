# Traffic frame-time profile ladder: runs tools/traffic_profile.gd at each car
# count, headless (CPU only, --fixed-fps 60) and windowed (real renderer: GPU
# ms, draw calls), a few times each, and prints the median run per row.
#
#   powershell -File tools/traffic-profile.ps1
#   powershell -File tools/traffic-profile.ps1 -Cars 0,40 -Modes headless -Repeat 1 -Secs 10
#
# Each Godot run gets High priority so other work on the laptop disturbs it
# less, and the total CPU load and the number of other Godot processes just
# before the run are stored with it (load=, others= in "opts"): a row measured
# on a busy laptop says so. Do not touch the machine during windowed runs.
# Raw results: bench-results/traffic-profile-<timestamp>.jsonl (gitignored),
# one JSON object per run (see traffic_profile.gd for the fields).
param(
	[string] $Godot = "$HOME/Documents/Godot_v4.7.2-stable_win64_console.exe",
	[string[]] $Cars = @("0", "30", "40", "80"),
	[string[]] $Modes = @("headless", "windowed"),
	[int] $Repeat = 3,
	[int] $Secs = 20,
	[int] $Detail = 300,          # m of full-sim / draw distance (300 is the slider's top)
	[string] $Gfx = "medium",
	[string] $Res = "1920x1080",
	[string] $Extra = "",         # more benchmark options, e.g. "--hills=1 --curves=1"
	[int] $TimeoutSec = 600
)

$ErrorActionPreference = "Continue"
# "powershell -File" hands "-Cars 0,40" and "-Modes a,b" over as one string each.
$Modes = @($Modes | ForEach-Object { $_.Split(",") })
$Cars = @($Cars | ForEach-Object { $_.Split(",") })
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "bench-results"
New-Item -ItemType Directory -Force $dir | Out-Null
$out = Join-Path $dir ("traffic-profile-{0}.jsonl" -f (Get-Date -Format "yyyy-MM-dd_HHmmss"))

function Get-Load {
	$s = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 1).CounterSamples
	return [int]$s[0].CookedValue
}

foreach ($mode in $Modes) {
	foreach ($n in $Cars) {
		for ($r = 1; $r -le $Repeat; $r++) {
			$load = Get-Load
			$others = @(Get-Process | Where-Object { $_.Name -like "Godot*" }).Count
			$a = @()
			if ($mode -eq "headless") { $a += @("--headless", "--fixed-fps", "60") }
			$a += @("--path", "`"$root`"", "--audio-driver", "Dummy", "-s", "res://tools/traffic_profile.gd", "--",
				"--benchmark", "--secs=$Secs", "--traffic=$n", "--detail=$Detail", "--gfx=$Gfx", "--res=$Res",
				"--out=`"$out`"", "--mode=$mode", "--load=$load", "--others=$others")
			$a += $Extra.Split(" ", [StringSplitOptions]::RemoveEmptyEntries)
			$psi = New-Object System.Diagnostics.ProcessStartInfo
			$psi.FileName = $Godot
			$psi.Arguments = ($a -join " ")
			$psi.UseShellExecute = $false
			$psi.RedirectStandardOutput = $true
			$psi.RedirectStandardError = $true
			Write-Host ("[{0}] {1} cars={2} run {3}/{4}  cpu load before={5}% other Godot={6}" -f (Get-Date -Format "HH:mm:ss"), $mode, $n, $r, $Repeat, $load, $others)
			$p = [System.Diagnostics.Process]::Start($psi)
			try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High } catch {}
			$null = $p.StandardOutput.ReadToEndAsync()
			$null = $p.StandardError.ReadToEndAsync()
			if (-not $p.WaitForExit($TimeoutSec * 1000)) {
				taskkill /T /F /PID $p.Id | Out-Null
				Write-Host "  TIMEOUT: killed after $TimeoutSec s"
			}
		}
	}
}

if (-not (Test-Path $out)) { Write-Host "no results written"; exit 1 }
$rows = Get-Content $out | ForEach-Object { $_ | ConvertFrom-Json }
Write-Host ""
Write-Host "Median run (by average frame time) per row. ms per frame unless noted."
$table = foreach ($g in ($rows | Group-Object { "{0}|{1}" -f $_.headless, $_.cars })) {
	$sorted = @($g.Group | Sort-Object frame_ms_avg)
	$m = $sorted[[int][math]::Floor(($sorted.Count - 1) / 2)]
	[pscustomobject]@{
		mode = $(if ($m.headless) { "headless" } else { "windowed" })
		cars = $m.cars; full_sim = $m.cars_full_sim_avg; runs = $sorted.Count
		frame = $m.frame_ms_avg; fps = $m.fps_avg; low1 = $m.frame_ms_1pct_low; ticks = $m.ticks_per_frame
		phys_scripts = $m.physics_scripts_ms; phys_engine = $m.physics_engine_ms; proc_scripts = $m.process_scripts_ms
		rest = $m.rest_ms; gpu = $m.gpu_ms; render_cpu = $m.render_cpu_ms
		draws = $m.draw_calls; prims = $m.primitives; mats = $m.census.unique_materials; shaders = $m.census.unique_shaders
		spread = ("{0}-{1}" -f $sorted[0].frame_ms_avg, $sorted[-1].frame_ms_avg)
	}
}
$table | Sort-Object mode, { [int]$_.cars } | Format-Table mode, cars, full_sim, runs, frame, fps, low1, ticks, spread -AutoSize | Out-String -Width 200 | Write-Host
$table | Sort-Object mode, { [int]$_.cars } | Format-Table mode, cars, phys_scripts, phys_engine, proc_scripts, rest, gpu, render_cpu, draws, prims, mats, shaders -AutoSize | Out-String -Width 200 | Write-Host
Write-Host "raw: $out"
