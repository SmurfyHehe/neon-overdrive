# Audio CPU cost, whole process (2026-10-09). Runs tests/audio_cost.gd with the
# player's sound nodes on and off, N times each, and prints the process's total
# CPU time (all threads: the main thread's GDScript plus the audio thread's
# mixing) next to the test's own main-thread numbers. The on/off difference is
# what the car sounds cost; on - off in CPU seconds over the run is the number
# to compare across branches.
#
#   powershell -File tools/audio_cost.ps1            3 runs per mode
#   powershell -File tools/audio_cost.ps1 -Runs 5
#
# Other Godot processes on the machine add noise: the script lists how many are
# running before it starts. Run it when the machine is otherwise quiet.
param(
	[int] $Runs = 3,
	[string] $Godot = "$env:USERPROFILE\Documents\Godot_v4.7.2-stable_win64.exe"  # the windowed exe: the _console one is a wrapper whose CPU time is not the game's
)
Set-Location (Join-Path $PSScriptRoot "..")
$others = @(Get-Process -Name "Godot*" -ErrorAction SilentlyContinue).Count
Write-Host ("other Godot processes running: {0}" -f $others)
$env:NEON_TRAFFIC = "0"
$env:NEON_CURVES = "0"
$env:NEON_HILLS = "0"
$result = @{}
foreach ($mode in @("on", "off")) {
	$cpu = @()
	$lines = @()
	for ($i = 0; $i -lt $Runs; $i++) {
		$env:AUDIO_COST = $mode
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = $Godot
		$psi.Arguments = "--headless --audio-driver Dummy --path . -s res://tests/audio_cost.gd"
		$psi.UseShellExecute = $false
		$psi.RedirectStandardOutput = $true
		$p = [System.Diagnostics.Process]::Start($psi)
		$out = $p.StandardOutput.ReadToEnd()
		$p.WaitForExit()
		$secs = $p.TotalProcessorTime.TotalSeconds
		$cpu += $secs
		$game = ($out -split "`n" | Where-Object { $_ -like "game:*" }) -join ""
		$synth = ($out -split "`n" | Where-Object { $_ -like "synth:*" }) -join ""
		$lines += ("  {0} run {1}: cpu {2:N2} s | {3} | {4}" -f $mode, ($i + 1), $secs, $game.Trim(), $synth.Trim())
		if ($out -notmatch "RESULT: PASS") { Write-Host $out }
	}
	$result[$mode] = ($cpu | Measure-Object -Average).Average
	Write-Host ("[{0}] mean cpu {1:N2} s over {2} runs" -f $mode, $result[$mode], $Runs)
	$lines | ForEach-Object { Write-Host $_ }
}
Write-Host ("audio cost = on - off = {0:N2} CPU seconds per run" -f ($result["on"] - $result["off"]))
