# Sets up, or checks, the tools needed to build the game's C++ part
# (a GDExtension on top of godot-cpp).
#
#   powershell -File tools/setup-native.ps1 -Check     print versions, exit 1 if one is missing
#   powershell -File tools/setup-native.ps1 -Install   install what is missing (official packages only)
#
# Needs: Visual Studio 2022 Build Tools (C++ workload: cl, linker, Windows SDK),
# Python 3, SCons, git. Nothing else is installed. -Install raises one Windows
# admin prompt (UAC) for the Visual Studio installer; a Yes click is needed.
# It never reboots; if the installer asks for a reboot, do it yourself, then
# run -Check.
#
# godot-cpp is not in the repo. To fetch and build it once:
#   git clone --depth 1 -b 4.4 https://github.com/godotengine/godot-cpp native/godot-cpp
#   (in the VS x64 dev shell) cd native/godot-cpp; py -m SCons platform=windows target=template_debug
# native/godot-cpp is in .gitignore.

param(
	[switch]$Check,
	[switch]$Install
)

$ErrorActionPreference = "Continue"

# --- helpers -------------------------------------------------------------

function Find-VsInstall {
	$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (-not (Test-Path $vswhere)) { return $null }
	$path = & $vswhere -latest -products * `
		-requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
		-property installationPath
	if ($path) { return ($path | Select-Object -First 1) }
	return $null
}

# cl prints its version on stderr; run it inside the x64 build environment.
function Get-ClVersion($vsPath) {
	$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
	if (-not (Test-Path $vcvars)) { return $null }
	$out = cmd /c "`"$vcvars`" >nul 2>&1 && cl 2>&1"
	$line = $out | Where-Object { $_ -match "Version" } | Select-Object -First 1
	if ($line) { return ($line -replace "^.*Version\s+", "").Trim() }
	return $null
}

function Get-SdkVersion {
	$inc = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Include"
	if (-not (Test-Path $inc)) { return $null }
	$v = Get-ChildItem $inc -Directory | Where-Object { $_.Name -match "^10\." } |
		Sort-Object { [version]$_.Name } | Select-Object -Last 1
	if ($v) { return $v.Name }
	return $null
}

function Get-PyVersion {
	$out = & py --version 2>&1
	if ($LASTEXITCODE -eq 0 -and $out -match "Python") { return ($out -replace "Python\s+", "").Trim() }
	return $null
}

function Get-SconsVersion {
	$out = & py -m pip show scons 2>&1
	$line = $out | Where-Object { $_ -match "^Version:" } | Select-Object -First 1
	if ($line) { return ($line -replace "^Version:\s*", "").Trim() }
	return $null
}

function Get-GitVersion {
	$out = & git --version 2>&1
	if ($LASTEXITCODE -eq 0) { return ($out -replace "git version\s+", "").Trim() }
	return $null
}

function Show-Check {
	$vs = Find-VsInstall
	$rows = [ordered]@{
		"cl (MSVC)"   = $(if ($vs) { Get-ClVersion $vs } else { $null })
		"Windows SDK" = Get-SdkVersion
		"py (Python)" = Get-PyVersion
		"scons"       = Get-SconsVersion
		"git"         = Get-GitVersion
	}
	$missing = 0
	foreach ($k in $rows.Keys) {
		if ($rows[$k]) {
			Write-Host ("{0,-12} {1}" -f $k, $rows[$k])
		} else {
			Write-Host ("{0,-12} MISSING" -f $k)
			$missing++
		}
	}
	if ($vs) { Write-Host "VS install   $vs" }
	return $missing
}

# --- install -------------------------------------------------------------

function Invoke-Install {
	if (-not (Find-VsInstall)) {
		"Installing Visual Studio 2022 Build Tools (C++ workload). Click Yes on the Windows prompt."
		winget install --id Microsoft.VisualStudio.2022.BuildTools --accept-package-agreements --accept-source-agreements `
			--override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
	}
	if (-not (Get-PyVersion)) {
		"Installing Python 3.12."
		winget install --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
		"Open a new shell so py is on PATH, then run -Install again for SCons."
		return
	}
	if (-not (Get-SconsVersion)) {
		"Installing SCons."
		& py -m pip install --user scons
	}
}

if ($Install) {
	Invoke-Install
	"--- check after install ---"
}
if ($Check -or $Install) {
	$missing = Show-Check
	if ($missing -gt 0) { exit 1 }
	exit 0
}
"Use -Check or -Install."
exit 2
