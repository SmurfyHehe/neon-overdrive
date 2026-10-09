@echo off
rem Balance sweep: every car on the hidden test track, across presets, driver
rem skill and assists, printed as tables (tools\balance_sweep.gd has the details).
rem
rem   tools\balance_sweep.bat          the whole grid, about 15 minutes
rem   tools\balance_sweep.bat quick    Stock / pro / assists on only, under a minute
rem
rem Set SWEEP_OUT to a CSV path to keep every number. Godot is looked up in
rem %GODOT%, then in Documents, like tests\run_tests.bat.
setlocal
if "%GODOT%"=="" set "GODOT=%USERPROFILE%\Documents\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
	echo Godot not found at "%GODOT%". Set GODOT to the console exe.
	exit /b 2
)
cd /d "%~dp0.."
if not exist ".godot" "%GODOT%" --headless --path . --import >nul 2>&1
if /i "%1"=="quick" set "SWEEP_QUICK=1"
set "NEON_TICKS=60"
set "NEON_TRAFFIC=0"
set "NEON_CURVES=0"
set "NEON_HILLS=0"
"%GODOT%" --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tools/balance_sweep.gd
