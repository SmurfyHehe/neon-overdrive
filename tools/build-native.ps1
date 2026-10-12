# Builds the game's C++ library (native/neon_sim) for Windows, debug and
# release, into addons/neon_sim/. Check the tools first:
#   powershell -File tools/setup-native.ps1 -Check
#
#   powershell -File tools/build-native.ps1 -GodotCpp C:\Users\Roy\gcpp10
#
# -GodotCpp is a godot-cpp checkout at 10.0.0-stable (commit 507ed9d; see
# native/neon_sim/SConstruct). Keep it on a short path: from deep inside a
# worktree the compiler runs out of path length (error C1083). Default:
# $env:GODOT_CPP, then native/neon_sim/godot-cpp. The first build also compiles
# godot-cpp itself there (about 15 minutes each for debug and release); after
# that a build takes seconds.
# Close every Godot that has this project open first: a loaded DLL cannot be
# overwritten.
param(
	[string] $GodotCpp = $env:GODOT_CPP,
	[string[]] $Targets = @("template_debug", "template_release"),
	[int] $Jobs = 5
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "native\neon_sim"
if (-not $GodotCpp) { $GodotCpp = Join-Path $src "godot-cpp" }
if (-not (Test-Path (Join-Path $GodotCpp "SConstruct"))) {
	Write-Host "godot-cpp not found at $GodotCpp (see the top of native/neon_sim/SConstruct)."
	exit 2
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
if (-not $vs) {
	Write-Host "Visual Studio C++ tools not found: run tools/setup-native.ps1 -Check."
	exit 2
}
$vcvars = Join-Path $vs "VC\Auxiliary\Build\vcvars64.bat"
$env:GODOT_CPP = (Resolve-Path $GodotCpp).Path -replace "\\", "/"
$failed = 0
foreach ($t in $Targets) {
	Write-Host "--- $t"
	cmd /c "`"$vcvars`" >nul 2>&1 && cd /d `"$src`" && py -m SCons platform=windows target=$t arch=x86_64 -j$Jobs"
	if ($LASTEXITCODE -ne 0) { $failed++ }
}
Get-ChildItem (Join-Path $root "addons\neon_sim\*.dll") | ForEach-Object {
	"{0}  {1,8} bytes  {2}  sha256 {3}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), (Get-FileHash $_ -Algorithm SHA256).Hash
}
exit $failed
