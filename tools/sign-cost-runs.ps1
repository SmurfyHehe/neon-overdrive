# Runs tools/sign_cost_bench.gd for several NEON_SIGNS variants, interleaved
# and in both orders (A B C, C B A, A B C, ...), because this laptop is shared
# and frame times swing with whatever else is running. One result line per run
# is appended to -Out (JSON lines); Godot's own output goes to a log beside it.
#
#   powershell -File tools\sign-cost-runs.ps1 -VariantList "off;asis;hide" -Repeats 6 -Out C:\temp\drive.jsonl
#   ... -Headless          CPU-only (no draw calls)
#   ... -Mode build        chunk rebuild timing, all variants inside one process per repeat
param(
	[string] $VariantList = "off;asis",   # ";" between variants: a variant is itself a comma list
	[int] $Repeats = 4,
	[Parameter(Mandatory)] [string] $Out,
	[switch] $Headless,
	[string] $Mode = "drive",
	[string] $Godot = "$env:USERPROFILE\Documents\Godot_v4.7.2-stable_win64_console.exe"
)
$Variants = $VariantList.Split(';')
Set-Location (Join-Path $PSScriptRoot "..")
$log = [IO.Path]::ChangeExtension($Out, ".log")
$env:NEON_TEST = "1"
$env:SIGN_BENCH_MODE = $Mode
$env:SIGN_BENCH_OUT = $Out
$flags = @("--audio-driver", "Dummy", "--fixed-fps", "60", "--path", ".", "-s", "res://tools/sign_cost_bench.gd")
if ($Headless) { $flags = @("--headless") + $flags }
if ($Mode -eq "build") {
	$env:SIGN_BENCH_VARIANTS = ($Variants -join ";")
	for ($r = 0; $r -lt $Repeats; $r++) {
		$env:SIGN_BENCH_LABEL = "build rep$r"
		$env:NEON_SIGNS = "asis"
		cmd /c "`"$Godot`" --headless $($flags -join ' ') >> `"$log`" 2>&1"
		Write-Host "build rep $r done"
	}
	exit 0
}
for ($r = 0; $r -lt $Repeats; $r++) {
	$order = @($Variants)
	if ($r % 2 -eq 1) { [array]::Reverse($order) }
	foreach ($v in $order) {
		$env:NEON_SIGNS = $v
		$env:SIGN_BENCH_LABEL = "rep$r"
		cmd /c "`"$Godot`" $($flags -join ' ') >> `"$log`" 2>&1"
		Write-Host ("{0} rep {1} {2} done" -f (Get-Date).ToString("HH:mm:ss"), $r, $v)
	}
}
