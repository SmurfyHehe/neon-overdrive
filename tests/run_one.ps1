# Runs one test script for tests\run_tests.bat, with a start time, the elapsed
# seconds and a timeout. A test that runs past the timeout has its whole
# process tree killed and counts as a failure ("TIMEOUT"); on 2026-10-06 one
# test hung for about two hours and nothing in the output said which.
#
# Exit code: the test's own exit code, or 124 on timeout.
# Appends "<seconds> <PASS|FAIL|TIMEOUT> <name>" to -Log when one is given.
param(
	[Parameter(Mandatory)] [string] $Godot,
	[Parameter(Mandatory)] [string] $Name,
	[string] $Flags = "",        # extra Godot flags for this test, e.g. "--headless --fixed-fps 60"
	[string] $Audio = "",        # "--audio-driver Dummy" unless SOUND=1
	[int] $TimeoutSec = 600,
	[string] $Log = ""
)

$all = @()
foreach ($part in ($Audio + " " + $Flags).Split(" ", [StringSplitOptions]::RemoveEmptyEntries)) { $all += $part }
$all += @("--path", ".", "-s", "res://tests/$Name.gd")

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Godot
$psi.Arguments = ($all -join " ")
$psi.UseShellExecute = $false  # no redirect: the test's output goes straight to this console

$start = Get-Date
Write-Host ("started {0}" -f $start.ToString("HH:mm:ss"))
$p = [System.Diagnostics.Process]::Start($psi)
$done = $p.WaitForExit($TimeoutSec * 1000)
$status = "PASS"
$code = 0
if (-not $done) {
	taskkill /T /F /PID $p.Id | Out-Null
	$p.WaitForExit(10000) | Out-Null
	$status = "TIMEOUT"
	$code = 124
	Write-Host ("TIMEOUT: {0} killed after {1} s" -f $Name, $TimeoutSec)
} else {
	$code = $p.ExitCode
	if ($code -ne 0) { $status = "FAIL" }
}
$secs = [int][math]::Round(((Get-Date) - $start).TotalSeconds)
# The exit code is printed on a failure: a test that printed PASS but exited non-zero
# (a crash while shutting down) otherwise looks like a mystery.
$note = ""
if ($status -eq "FAIL") { $note = "  (exit code $code)" }
Write-Host ("finished {0}  {1} s  {2}{3}" -f (Get-Date).ToString("HH:mm:ss"), $secs, $status, $note)
if ($Log -ne "") { Add-Content -Path $Log -Value ("{0,5} s  {1,-8} {2}" -f $secs, $status, $Name) }
exit $code
