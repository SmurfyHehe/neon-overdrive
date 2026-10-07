@echo off
rem Run every test in tests\ and print one pass/fail summary (GitHub #39).
rem
rem   tests\run_tests.bat          all tests; a game window opens for ~1 min
rem   tests\run_tests.bat quick    headless tests only, ~15 s, no window
rem
rem Godot is looked up in %GODOT%, then in Documents. Exit code 0 = all passed.
rem
rem Every test prints its start time and how many seconds it took, and the run
rem ends with a table of all of them. A test still running after
rem %TEST_TIMEOUT% seconds (default 600) is killed and counted as
rem "name(TIMEOUT)" in the FAILED list (see tests\run_one.ps1).
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
rem Most tests count physics ticks as sixtieths of a second, so they run at 60 Hz; the game itself runs at 120 (see tick_rate.gd and tests/tick_rate_120.gd).
if "%NEON_TICKS%"=="" set "NEON_TICKS=60"
if "%SOUND%"=="1" set "AUDIO="
rem No traffic for the older drive-bot tests (they steer across lanes blind); the traffic_* tests ignore this and spawn their own.
if "%NEON_TRAFFIC%"=="" set "NEON_TRAFFIC=0"

rem Per-test timeout in seconds. The slowest tests take about 2 minutes, so 10 is generous.
if "%TEST_TIMEOUT%"=="" set "TEST_TIMEOUT=600"
set "TIMES=%TEMP%\neon_test_times.log"
type nul > "%TIMES%"
echo Started %DATE% %TIME:~0,8%

set "FAILED="
set "CRASHED="
call :run smoke --headless
call :run palette --headless
call :run hud --headless
call :run car_loft_normals --headless
call :run test_car --headless
call :run p1_coupe --headless
call :run road_strip_winding --headless
call :run sidewalk_collision_taper --headless
call :run aero_draft_equivalence --headless
call :run camera_feel --headless
call :run car_audio --headless
call :run fleet_design_check --headless
call :run exhaust_tune --headless
call :run audio_master --headless
call :run phase_a_engine --headless
call :run tick_rate_120 "--headless --fixed-fps 120"
call :run cockpit --headless
call :run cockpit_interior --headless
call :run cockpit_isolation "--headless --fixed-fps 120"
call :run cockpit_head_motion --headless
call :run hud_rear_strip --headless
call :run look_back --headless
call :run mirror_glance --headless
call :run cockpit_driver --headless
call :run cockpit_shifter --headless
call :run cockpit_shifter_rnd --headless
call :run tyres "--headless --fixed-fps 60"
call :run clutch_model --headless
call :run driveline_audio --headless
call :run radio --headless
call :run view_settings --headless
call :run camera_smoothing_setting --headless
call :run powertrain_health "--headless --fixed-fps 60"
call :run turbo "--headless --fixed-fps 60"
call :run chassis_targets "--headless --fixed-fps 60"
call :run reverse_and_tabs --headless
call :run transmission_modes "--headless --fixed-fps 60"
call :run auto_tune_worker_mode --headless
call :run tune_params --headless
call :run auto_tune_rules --headless
call :run tune_slots --headless
call :run traffic_spawn "--headless --fixed-fps 60"
rem ~40 s: the traffic cars (stage B step 5) against their sheets, then a drive each at the game's 120 Hz.
call :run npc_cars "--headless --fixed-fps 120"
rem ~17 s: full throttle at ~245 km/h across floating-origin recenters (the old ground-slab kick), at the game's 120 Hz.
call :run recenter_kick "--headless --fixed-fps 120"
call :run fx_pack --headless
call :run exhaust_flames --headless
call :run boundary_walls --headless
call :run road_space --headless
if /i not "%~1"=="quick" (
	rem Headless, but ~2 min of simulated driving; --fixed-fps lets physics run faster than the clock.
	call :run tune_track "--headless --fixed-fps 60"
	rem ~40 s: tyre pressure and camber sweep on the same track (Tuner PR 1).
	call :run tyre_model "--headless --fixed-fps 60"
	rem ~60 s: every chassis setting at both ends on the same track (Tuner PR 2).
	call :run tuner_settings "--headless --fixed-fps 60"
	rem ~30 s: the new Tuner's presets on the track, every notch, the estimates (Tuner PR 3).
	call :run tuner_presets "--headless --fixed-fps 60"
	rem ~15 s: the stat panel's Test run through a worker process, the Mechanic's plain words (Tuner PR 4).
	call :run tuner_test_run "--headless --fixed-fps 60"
	rem Traffic (stage B step 3) at the game's 120 Hz tick: ~1 min of dense traffic, then the perf sweep.
	call :run traffic_stability "--headless --fixed-fps 120"
	call :run traffic_behaviour "--headless --fixed-fps 120"
	call :run traffic_perf "--headless --fixed-fps 120"
	call :run auto_tune_search "--headless --fixed-fps 60"
	call :run auto_tune_job "--headless --fixed-fps 60"
	rem Key-press tests run headless: a windowed run loses its held keys the moment the window loses focus (found 2026-10-05, it made chunk_drive and feel_pass_1 flaky).
	rem These need a real window: headless drops MultiMesh data.
	call :run chunk_drive
	rem Also a real window (it reads the interpolated camera); ~45 s of driving 500 km down the road.
	call :run floating_origin_drive
	call :run game_state --headless
	call :run tuning_panel --headless
	call :run auto_tune_panel --headless
	call :run tuner_screen --headless
	call :run tuner_typing --headless
	call :run roadside_detail
	rem ~10 s, real window (shaders): traffic tail lamps, brake lamps, distance flares, barrier reflectors.
	call :run night_lights
	call :run fleet_silhouette_sweep
	call :run fleet_budget_scene
	call :run mute --headless
	call :run feel_pass_1 --headless
)
echo.
echo Per-test times:
type "%TIMES%"
echo Finished %DATE% %TIME:~0,8%
rem A negative exit code is Godot crashing (often at shutdown, after the test printed PASS). The old script never counted those either; they are only listed.
if defined CRASHED echo CRASHED, not counted as failed:!CRASHED!
if defined FAILED (
	echo FAILED:!FAILED!
	exit /b 1
)
if defined CRASHED (echo No test failed, but see CRASHED above.) else echo All tests passed.
exit /b 0

:run
echo.
echo === %1  [%TIME:~0,8%]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_one.ps1" -Godot "%GODOT%" -Name %1 -Flags "%~2" -Audio "%AUDIO%" -TimeoutSec %TEST_TIMEOUT% -Log "%TIMES%"
set "RC=!errorlevel!"
if !RC! equ 124 (set "FAILED=!FAILED! %1(TIMEOUT)") else if !RC! gtr 0 (set "FAILED=!FAILED! %1") else if !RC! lss 0 (set "CRASHED=!CRASHED! %1(!RC!)")
exit /b 0
