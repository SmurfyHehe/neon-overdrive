@echo off
rem Bolt-on worth sweep: every bolt-on fitted on the Bug after Service, run on
rem the hidden test track, printed as a worth table against the estimates
rem (scripts\car\bolt_on_worth.gd has what each column means). A few minutes.
rem
rem   tools\bolt_on_worth.bat
rem
rem Optional environment: BOLT_CAR (default p0_beater), BOLT_ONLY (comma list
rem of item ids), BOLT_OUT (a path to also write the table to). Godot is looked
rem up in %GODOT%, then in Documents, like tests\run_tests.bat.
setlocal
if "%GODOT%"=="" set "GODOT=%USERPROFILE%\Documents\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
	echo Godot not found at "%GODOT%". Set GODOT to the console exe.
	exit /b 2
)
cd /d "%~dp0.."
if not exist ".godot" "%GODOT%" --headless --path . --import >nul 2>&1
set "NEON_TICKS=60"
set "NEON_TRAFFIC=0"
set "NEON_CURVES=0"
set "NEON_HILLS=0"
"%GODOT%" --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/bolt_on_worth.gd
