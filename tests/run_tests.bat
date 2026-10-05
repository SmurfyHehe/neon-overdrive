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
rem Tests are silent unless you set SOUND=1 (the Dummy audio driver plays nothing).
set "AUDIO=--audio-driver Dummy"
if "%SOUND%"=="1" set "AUDIO="

set "FAILED="
call :run smoke --headless
call :run car_loft_normals --headless
call :run test_car --headless
call :run road_strip_winding --headless
call :run sidewalk_collision_taper --headless
call :run aero_draft_equivalence --headless
call :run camera_feel --headless
call :run car_audio --headless
call :run fleet_design_check --headless
call :run exhaust_tune --headless
call :run audio_master --headless
call :run phase_a_engine --headless
call :run cockpit --headless
call :run tyres "--headless --fixed-fps 60"
call :run clutch_model --headless
call :run driveline_audio --headless
call :run radio --headless
call :run powertrain_health "--headless --fixed-fps 60"
call :run turbo "--headless --fixed-fps 60"
call :run chassis_targets "--headless --fixed-fps 60"
call :run reverse_and_tabs --headless
call :run auto_tune_worker_mode --headless
call :run tune_params --headless
call :run auto_tune_rules --headless
call :run tune_slots --headless
if /i not "%~1"=="quick" (
	rem Headless, but ~2 min of simulated driving; --fixed-fps lets physics run faster than the clock.
	call :run tune_track "--headless --fixed-fps 60"
	call :run auto_tune_search "--headless --fixed-fps 60"
	call :run auto_tune_job "--headless --fixed-fps 60"
	rem Key-press tests run headless: a windowed run loses its held keys the moment the window loses focus (found 2026-10-05, it made chunk_drive and feel_pass_1 flaky).
	rem These need a real window: headless drops MultiMesh data.
	call :run chunk_drive
	call :run game_state --headless
	call :run tuning_panel --headless
	call :run auto_tune_panel --headless
	call :run roadside_detail
	call :run fleet_silhouette_sweep
	call :run fleet_budget_scene
	call :run exhaust_keys --headless
	call :run mute --headless
	call :run feel_pass_1 --headless
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
"%GODOT%" %AUDIO% %~2 --path . -s res://tests/%1.gd

if errorlevel 1 set "FAILED=!FAILED! %1"
exit /b 0
