@echo off
rem Run every test in tests\ and print one pass/fail summary (GitHub #39).
rem
rem   tests\run_tests.bat          all tests; a game window opens for ~1 min
rem   tests\run_tests.bat quick    headless tests only, ~15 s, no window
rem
rem Godot is looked up in %GODOT%, then in Documents. Exit code 0 = all passed.
setlocal enabledelayedexpansion
if "%GODOT%"=="" set "GODOT=%USERPROFILE%\Documents\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
	echo Godot not found at "%GODOT%". Set GODOT to the console exe.
	exit /b 2
)
cd /d "%~dp0.."
rem A fresh checkout has no import cache yet; scripts fail to load without it.
if not exist ".godot" "%GODOT%" --headless --path . --import >nul 2>&1

set "FAILED="
call :run smoke --headless
call :run car_loft_normals --headless
call :run road_strip_winding --headless
call :run sidewalk_collision_taper --headless
call :run aero_draft_equivalence --headless
if /i not "%~1"=="quick" (
	rem These need a real window: headless drops MultiMesh data.
	call :run chunk_drive
	call :run game_state
	call :run tuning_panel
)
echo.
if defined FAILED (
	echo FAILED:%FAILED%
	exit /b 1
)
echo All tests passed.
exit /b 0

:run
echo.
echo === %1
"%GODOT%" %2 --path . -s res://tests/%1.gd
if errorlevel 1 set "FAILED=!FAILED! %1"
exit /b 0
