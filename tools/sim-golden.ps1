# Golden run of the car physics: records tools/sim_golden.gd once on the
# GDScript path and once on the C++ path (NEON_SIM_NATIVE=1), then compares the
# two files. One Godot at a time. Exit code 0 = PASS.
#
#   powershell -File tools/sim-golden.ps1
#   powershell -File tools/sim-golden.ps1 -Repeat     also records the GDScript path a second
#                                                     time and compares the two GDScript runs
#                                                     (shows how repeatable the reference is)
#
# Files: bench-results/sim-golden-<gd|native|gd2>.csv (bench-results is gitignored).
param(
	[switch] $Repeat,
	[string] $Godot = "$HOME/Documents/Godot_v4.7.2-stable_win64_console.exe"
)

$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "bench-results"
New-Item -ItemType Directory -Force $dir | Out-Null

function Invoke-Godot([string[]] $GodotArgs, [string] $Native) {
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $Godot
	$psi.Arguments = ($GodotArgs -join " ")
	$psi.WorkingDirectory = $root
	$psi.UseShellExecute = $false
	$psi.EnvironmentVariables["NEON_SIM_NATIVE"] = $Native
	$p = [System.Diagnostics.Process]::Start($psi)
	if (-not $p.WaitForExit(600000)) {
		taskkill /T /F /PID $p.Id | Out-Null
		Write-Host "TIMEOUT"
		return 124
	}
	return $p.ExitCode
}

function Record-Run([string] $Name, [string] $Native) {
	Write-Host "--- record $Name"
	$file = "bench-results/sim-golden-$Name.csv"
	return (Invoke-Godot @("--headless", "--audio-driver", "Dummy", "--fixed-fps", "120", "--path", ".", "-s", "res://tools/sim_golden.gd", "--", "out=$file") $Native)
}

function Compare-Runs([string] $A, [string] $B) {
	Write-Host "--- compare $A against $B"
	return (Invoke-Godot @("--headless", "--audio-driver", "Dummy", "--path", ".", "-s", "res://tools/sim_golden.gd", "--", "compare=bench-results/sim-golden-$A.csv,bench-results/sim-golden-$B.csv") "0")
}

$bad = 0
if ((Record-Run "gd" "0") -ne 0) { $bad++ }
if ((Record-Run "native" "1") -ne 0) { $bad++ }
if ($Repeat) {
	if ((Record-Run "gd2" "0") -ne 0) { $bad++ }
	if ((Compare-Runs "gd" "gd2") -ne 0) { $bad++ }
}
if ((Compare-Runs "gd" "native") -ne 0) { $bad++ }
exit $bad
