# Per-function GDScript profile: runs tools/script_profile.gd headless with
# Godot's own script profiler on, and prints the functions ranked by self time.
#
#   powershell -File tools/script-profile.ps1                 # 60 s, 80 cars (the slider's top), 300 m full sim
#   powershell -File tools/script-profile.ps1 -Secs 20 -Cars 40 -Top 20
#
# Raw engine output: bench-results/script-profile-<timestamp>.txt (gitignored).
# Ranked table (all functions): the same name with .csv.
# Columns: self = time in the function's own lines, including the engine calls
# it makes directly; total = self plus everything it calls; both as seconds over
# the whole run, per physics tick, and per call.
param(
	[string] $Godot = "$HOME/Documents/Godot_v4.7.2-stable_win64_console.exe",
	[int] $Secs = 60,
	[int] $Cars = 80,
	[int] $Detail = 300,
	[int] $Top = 10,
	[string] $Extra = "",
	[int] $TimeoutSec = 3000
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "bench-results"
New-Item -ItemType Directory -Force $dir | Out-Null
$raw = Join-Path $dir ("script-profile-{0}.txt" -f (Get-Date -Format "yyyy-MM-dd_HHmmss"))
$run = $Secs + 3  # the tool skips a 3 s warm-up
$a = @("-d", "--headless", "--fixed-fps", "60", "--path", "`"$root`"", "--audio-driver", "Dummy",
	"-s", "res://tools/script_profile.gd", "--", "--benchmark", "--secs=$run", "--traffic=$Cars", "--detail=$Detail")
$a += $Extra.Split(" ", [StringSplitOptions]::RemoveEmptyEntries)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Godot
$psi.Arguments = ($a -join " ")
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.RedirectStandardInput = $true  # the local debugger reads stdin if a script error breaks in
$others = @(Get-Process | Where-Object { $_.Name -like "Godot*" }).Count
Write-Host ("[{0}] profiling {1} s, {2} cars, {3} m; other Godot processes: {4}" -f (Get-Date -Format "HH:mm:ss"), $Secs, $Cars, $Detail, $others)
$p = [System.Diagnostics.Process]::Start($psi)
try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High } catch {}
$so = $p.StandardOutput.ReadToEndAsync()
$null = $p.StandardError.ReadToEndAsync()
$p.StandardInput.Close()
if (-not $p.WaitForExit($TimeoutSec * 1000)) {
	taskkill /T /F /PID $p.Id | Out-Null
	Write-Host "TIMEOUT: killed after $TimeoutSec s"
	exit 1
}
[IO.File]::WriteAllText($raw, $so.Result, (New-Object System.Text.UTF8Encoding($false)))

$lines = $so.Result -split "`r?`n"
$start = -1
for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i].StartsWith("ACCUMULATED:")) { $start = $i; break } }
$endLine = $lines | Where-Object { $_.StartsWith("SPROF_END ") } | Select-Object -First 1
if ($start -lt 0 -or -not $endLine) { Write-Host "no profile in the output; see $raw"; exit 1 }
$meta = $endLine.Substring(10) | ConvertFrom-Json
$inv = [Globalization.CultureInfo]::InvariantCulture
$rows = New-Object System.Collections.Generic.List[object]
for ($i = $start + 1; $i -lt $lines.Count - 1; $i++) {
	if ($lines[$i] -match '^\d+:(res://.+?)::(\d+)::(.+)$') {
		$file = $Matches[1]; $fn = $Matches[3]
		if ($lines[$i + 1] -match 'total: ([\d.eE+-]+)/.*self: ([\d.eE+-]+)/.*tcalls: (\d+)') {
			$calls = [int64]$Matches[3]
			if ($calls -eq 0 -or $file.StartsWith("res://tools/")) { continue }
			$total = [double]::Parse($Matches[1], $inv); $self = [double]::Parse($Matches[2], $inv)
			$rows.Add([pscustomobject]@{ func = $fn; file = $file.Substring(6); calls = $calls; self_s = $self; total_s = $total })
		}
	}
}
$selfSum = ($rows | Measure-Object self_s -Sum).Sum
$ticks = [double]$meta.ticks
$table = $rows | Sort-Object self_s -Descending | ForEach-Object { $rank = 0 } {
	$rank++
	[pscustomobject]@{
		rank = $rank; func = $_.func; file = $_.file
		self_pct = [math]::Round(100 * $_.self_s / $selfSum, 1)
		self_s = [math]::Round($_.self_s, 3); total_s = [math]::Round($_.total_s, 3)
		self_ms_per_tick = [math]::Round(1000 * $_.self_s / $ticks, 3)
		calls_per_tick = [math]::Round($_.calls / $ticks, 1)
		self_us_per_call = [math]::Round(1e6 * $_.self_s / $_.calls, 2)
	}
}
$csv = [IO.Path]::ChangeExtension($raw, ".csv")
$table | Export-Csv -NoTypeInformation -Encoding UTF8 $csv
Write-Host ("{0} game seconds, {1} wall seconds, {2} ticks at {3} Hz, {4} frames, {5} cars, {6} m, {7}" -f $meta.game_secs, $meta.wall_secs, $meta.ticks, $meta.physics_hz, $meta.frames, $meta.cars, $meta.detail_m, $meta.renderer)
Write-Host ("all script self time: {0:N1} s = {1:N2} ms per tick (profiler on)" -f $selfSum, (1000 * $selfSum / $ticks))
$table | Select-Object -First $Top | Format-Table rank, func, self_pct, self_s, total_s, self_ms_per_tick, calls_per_tick, self_us_per_call -AutoSize | Out-String -Width 220 | Write-Host
Write-Host "raw: $raw"
Write-Host "all functions: $csv"
