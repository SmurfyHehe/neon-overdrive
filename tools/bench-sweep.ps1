# Stress-test sweep: runs the in-game benchmark (scripts/benchmark.gd) once per
# configuration with the real renderer (a window opens for each run; do not
# touch the machine while it runs) and prints one table of fps, 1% lows and
# frame-time spikes. Re-run it at the end of the project and compare.
#
#   powershell -File tools/bench-sweep.ps1                 # -Set quick (default)
#   powershell -File tools/bench-sweep.ps1 -Set full -Secs 60
#   powershell -File tools/bench-sweep.ps1 -Set custom -Custom "--traffic=80 --hills=1","--scale=0.75"
#
# Sets:
#   quick   baseline + heaviest-load + 3 resolution scales            (~5 runs)
#   full    traffic ladder, hills/curves route, lane changes, cockpit with
#           mirrors (low/med/high) and window, render scales, MSAA     (~20 runs)
#   tiers   Low / Medium / High at 1920x1080: plain drive, then the heavy
#           route in the cockpit, then Medium heavy with dynamic resolution
#           on (--gfx, --dynres in benchmark.gd)                       (~7 runs)
# Each run is identical road + seed (benchmark.gd), so rows compare directly.
# Results also go to bench-results/<timestamp>.md (gitignored).
param(
	[string] $Godot = "$HOME/Documents/Godot_v4.7.2-stable_win64_console.exe",
	[ValidateSet("quick", "full", "tiers", "custom")] [string] $Set = "quick",
	[int] $Secs = 30,
	[string[]] $Custom = @(),
	[string] $Label = "",
	[int] $Repeat = 1             # runs per config; the median-fps run is reported
)

$ErrorActionPreference = "Continue"   # Godot writes warnings to stderr
$root = Split-Path -Parent $PSScriptRoot
$configs = switch ($Set) {
	"quick" { @(
		"--traffic=16",
		"--traffic=80 --detail=300 --hills=1 --curves=1 --weave=1",
		"--traffic=16 --scale=0.75",
		"--traffic=16 --scale=0.5",
		"--traffic=16 --res=1920x1080",
		"--view=cockpit --mirrors=1 --mirror_q=1 --window=1") }
	"full" { @(
		"--traffic=0", "--traffic=16", "--traffic=40", "--traffic=80",
		"--traffic=16 --detail=100", "--traffic=80 --detail=300",
		"--traffic=16 --hills=1 --curves=1",
		"--traffic=16 --weave=1",
		"--traffic=80 --detail=300 --hills=1 --curves=1 --weave=1",
		"--view=cockpit --mirrors=0",
		"--view=cockpit --mirrors=1 --mirror_q=0",
		"--view=cockpit --mirrors=1 --mirror_q=1",
		"--view=cockpit --mirrors=1 --mirror_q=2",
		"--view=cockpit --mirrors=1 --mirror_q=1 --window=1 --traffic=40",
		"--traffic=16 --res=1920x1080", "--traffic=16 --res=1920x1080 --scale=0.75", "--traffic=16 --res=1920x1080 --scale=0.5",
		"--traffic=16 --msaa=0", "--traffic=16 --msaa=2", "--traffic=16 --msaa=4",
		"--traffic=80 --detail=300 --hills=1 --curves=1 --weave=1 --view=cockpit --mirrors=1 --mirror_q=2 --window=1 --msaa=4") }
	"tiers" { @(
		"--gfx=low --res=1920x1080", "--gfx=medium --res=1920x1080", "--gfx=high --res=1920x1080",
		"--gfx=low --res=1920x1080 --hills=1 --curves=1 --weave=1 --view=cockpit --window=1",
		"--gfx=medium --res=1920x1080 --hills=1 --curves=1 --weave=1 --view=cockpit --window=1",
		"--gfx=high --res=1920x1080 --hills=1 --curves=1 --weave=1 --view=cockpit --window=1",
		"--gfx=medium --res=1920x1080 --hills=1 --curves=1 --weave=1 --view=cockpit --window=1 --dynres=1") }
	"custom" { $Custom }
}

function Get-Num($line, $re) {
	if ($line -match $re) { return [double]$Matches[1] } else { return [double]::NaN }
}

$rows = @()
$i = 0
$gpuNote = ""
foreach ($cfg in $configs) {
	$i++
	Write-Host ("[{0}/{1}] {2}" -f $i, $configs.Count, $cfg)
	$argList = @("--path", $root, "--audio-driver", "Dummy", "--", "--benchmark", "--secs=$Secs") + ($cfg.Split(" ", [StringSplitOptions]::RemoveEmptyEntries))
	$runs = @()
	for ($r = 0; $r -lt $Repeat; $r++) {
		$out = & $Godot @argList 2>&1 | Out-String
		$line = ($out -split "`r?`n" | Where-Object { $_ -like "BENCHMARK 20*" } | Select-Object -Last 1)
		if ($line) { $runs += [pscustomobject]@{
			Fps = [int](Get-Num $line 'avg=[\d.]+ms \((\d+) fps\)')
			Low1 = [int](Get-Num $line '1%low=[\d.]+ms \((\d+) fps\)')
			P99 = Get-Num $line 'p99=([\d.]+)'
			Max = Get-Num $line 'max=([\d.]+)'
			Gpu = Get-Num $line 'gpu=([\d.]+)ms'
			Cpu = Get-Num $line 'process=([\d.]+)ms'
			Phys = Get-Num $line 'physics=([\d.]+)ms'
			Draws = [int](Get-Num $line 'draw_calls avg=(\d+)')
			Sp = [int](Get-Num $line 'spikes>33ms=(\d+)') } }
	}
	if ($runs.Count -eq 0) {
		Write-Host "  no result line (run failed)"
		$rows += [pscustomobject]@{ Config = $cfg; Fps = "FAIL"; Low1 = ""; "p99 ms" = ""; "max ms" = ""; Spikes = ""; "GPU ms" = ""; "script ms" = ""; "physics ms" = ""; Draws = "" }
		continue
	}
	$m = ($runs | Sort-Object Fps)[[int][math]::Floor(($runs.Count - 1) / 2)]
	$rows += [pscustomobject]@{ Config = $cfg; Fps = $m.Fps; Low1 = $m.Low1; "p99 ms" = $m.P99; "max ms" = $m.Max; Spikes = $m.Sp; "GPU ms" = $m.Gpu; "script ms" = $m.Cpu; "physics ms" = $m.Phys; Draws = $m.Draws }
}
Write-Host ""
$rows | Format-Table -AutoSize
$dir = Join-Path $root "bench-results"
New-Item -ItemType Directory -Force $dir | Out-Null
$stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$md = "# Benchmark sweep $stamp $Label`n`n(set=$Set, $Secs s per run, Fps = average, Low1 = 1% low fps; ms columns are per-frame averages except p99/max)`n`n"
$md += "| Config | Fps | 1% low | p99 ms | max ms | frames >33 ms | GPU ms | script ms | physics ms | draws |`n|---|---|---|---|---|---|---|---|---|---|`n"
foreach ($r in $rows) { $md += "| $($r.Config) | $($r.Fps) | $($r.Low1) | $($r.'p99 ms') | $($r.'max ms') | $($r.Spikes) | $($r.'GPU ms') | $($r.'script ms') | $($r.'physics ms') | $($r.Draws) |`n" }
Set-Content -Path (Join-Path $dir "$stamp.md") -Value $md -Encoding utf8
Write-Host "Saved bench-results/$stamp.md"

