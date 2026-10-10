@echo off
rem Run every test in tests\ and print one pass/fail summary (GitHub #39).
rem
rem   tests\run_tests.bat          all tests; a game window opens for ~1 min
rem   tests\run_tests.bat quick    headless tests only, no window: about 15 min of test
rem                                time over 85 tests (CI wall clock about 23 of its 30)
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
rem Most tests count physics ticks as sixtieths of a second, so they run at 60 Hz; the game itself runs at 120 (see tick_rate.gd and tests/core/tick_rate_120.gd).
if "%NEON_TICKS%"=="" set "NEON_TICKS=60"
if "%SOUND%"=="1" set "AUDIO="
rem No traffic for the older drive-bot tests (they steer across lanes blind); the traffic_* tests ignore this and spawn their own.
if "%NEON_TRAFFIC%"=="" set "NEON_TRAFFIC=0"
rem No patrol car (police F1) in the older drive tests; tests/traffic/police_*.gd set their own.
if "%NEON_POLICE%"=="" set "NEON_POLICE=0"
rem Straight road for the older drive tests (they steer blind down -Z); the curve tests set their own.
if "%NEON_CURVES%"=="" set "NEON_CURVES=0"
if "%NEON_HILLS%"=="" set "NEON_HILLS=0"

rem Per-test timeout in seconds. The slowest tests take about 2 minutes, so 10 is generous.
if "%TEST_TIMEOUT%"=="" set "TEST_TIMEOUT=600"
set "TIMES=%TEMP%\neon_test_times.log"
type nul > "%TIMES%"
echo Started %DATE% %TIME:~0,8%

set "FAILED="
set "CRASHED="
call :run low_fps_watch --headless
call :run core/smoke --headless
call :run core/game_info --headless
call :run core/palette --headless
call :run ui/fonts --headless
call :run world/names --headless
call :run ui/hud --headless
call :run ui/settings_screen --headless
call :run ui/title_and_pause --headless
call :run ui/pause_look --headless
call :run audio/menu_sfx --headless
call :run core/key_bindings --headless
call :run fleet/car_loft_normals --headless
call :run fleet/test_car --headless
call :run fleet/p1_coupe --headless
call :run car/undercarriage --headless
call :run world/road_strip_winding --headless
call :run world/sidewalk_collision_taper --headless
call :run world/kerb_profile --headless
call :run world/cross_section --headless
call :run world/side_streets --headless
call :run car/kerb_strike --headless
call :run car/aero_draft_equivalence --headless
call :run view/camera_feel --headless
call :run audio/car_audio --headless
call :run fleet/fleet_design_check --headless
rem Car pipeline step 1: the P1 body.glb from tools/car_pipeline/build_car.py loads, splits into panels, sits on the sheet's numbers.
call :run fleet/car_pipeline_p1 --headless
call :run audio/exhaust_tune --headless
call :run audio/exhaust_pops --headless
rem Engine loops: baked rpm x load bank is seamless, the player stays under its voice cap and never swaps a stream under a sounding voice, events stay live, in-game hand-over.
call :run audio/engine_loops --headless
call :run audio/engine_loops_live --headless
call :run car/anti_lag_turbo --headless
call :run audio/audio_master --headless
call :run car/phase_a_engine --headless
call :run core/tick_rate_120 "--headless --fixed-fps 120"
rem Dirt and wash (pre-reorganisation branch: its files still sit in the tests\ and scripts\ roots).
call :run car_dirt --headless
call :run car_wash_scene --headless
call :run view/cockpit --headless
call :run view/cockpit_interior --headless
call :run view/dash_trinket --headless
call :run view/cabin_mods --headless
call :run view/cockpit_isolation "--headless --fixed-fps 120"
call :run view/cockpit_head_motion --headless
call :run ui/hud_rear_strip --headless
call :run view/look_back --headless
call :run view/look_around --headless
call :run view/cockpit_driver --headless
call :run view/cockpit_window --headless
call :run view/gauge_pod --headless
call :run view/gauge_layout --headless
call :run view/cockpit_steering_hands --headless
call :run view/cockpit_shifter --headless
call :run view/cockpit_shifter_rnd --headless
call :run ui/touch_radio --headless
call :run car/tyres "--headless --fixed-fps 60"
call :run car/clutch_model --headless
call :run audio/driveline_audio --headless
call :run audio/sound_fixes --headless
call :run audio/road_sounds --headless
call :run audio/crash_variety --headless
call :run audio/audio_mix --headless
call :run audio/radio --headless
call :run world/person_body --headless
call :run world/night_clock --headless
call :run world/night_bands "--headless --fixed-fps 60"
call :run world/world_mood "--headless --fixed-fps 60"
call :run world/moment_spots "--headless --fixed-fps 60"
rem Water (rain, puddles): the rules and their CPU cost, no game boot.
call :run world/water_rules --headless
rem Weather plan (W1): deck per act, storms, fronts, mid-night change, numbers.
call :run world/weather_plan --headless
call :run world/weather_plan_game "--headless --fixed-fps 60"
call :run core/view_settings --headless
call :run view/camera_smoothing_setting --headless
call :run core/log_folder --headless
call :run car/powertrain_health "--headless --fixed-fps 60"
call :run car/car_parts --headless
call :run car/car_detail --headless
call :run car/turbo "--headless --fixed-fps 60"
call :run car/forced_induction "--headless --fixed-fps 60"
call :run car/bolt_ons --headless
call :run car/bolt_on_worth "--headless --fixed-fps 60"
call :run car/mod_tree "--headless --fixed-fps 60"
call :run car/chassis_targets "--headless --fixed-fps 60"
call :run car/gearbox_per_car "--headless --fixed-fps 60"
call :run car/reverse_and_tabs --headless
call :run car/transmission_modes "--headless --fixed-fps 60"
rem Realistic automatic (2026-10-10), at the game's 120 Hz: the shift keys do nothing in AUTO (~20 s);
rem the converter: creep, flare, power-on shift, lock-up, hill (~3 min); the shift brain: no hunting, kickdown, corner hold, brake downshift (~3 min).
call :run car/auto_ignores_shift_keys "--headless --fixed-fps 120"
call :run car/auto_converter "--headless --fixed-fps 120"
call :run car/auto_shift_brain "--headless --fixed-fps 120"
call :run tuning/auto_tune_worker_mode --headless
call :run tuning/tune_params --headless
call :run tuning/gear_count --headless
call :run tuning/auto_tune_rules --headless
call :run tuning/tune_slots --headless
rem The player's tune survives a reset and a relaunch (PlayerTune).
call :run tuning/tune_persist --headless
call :run core/settings_safety --headless
call :run core/setting_danger --headless
rem Save system: atomic files, 3 slots, chases, rename migration (scripts/save/).
call :run core/save_system --headless
rem F0: cash and bank through reloads, chases and 6 a.m. (and the HUD and pause screen).
call :run core/wallet --headless
rem Police F0/F1: heat levels and icons, cop_can_see_player, headlights off hides, night one lines.
call :run traffic/police_heat --headless
rem Ending a run on a crash: the rules, the hit sensor, the crash screen; then the real restart.
call :run core/run_end "--headless --fixed-fps 120"
call :run core/run_end_restart "--headless --fixed-fps 120"
call :run world/gas_station --headless
call :run traffic/traffic_spawn "--headless --fixed-fps 60"
rem Near-band traffic: hand-overs between the 60 m physics band and the rails, both ways, no visible jump.
call :run traffic/traffic_near_band "--headless --fixed-fps 120"
rem ~45 s: race core (RC1): win across a recenter, lose, give up from the pause menu.
call :run core/race_core "--headless --fixed-fps 60"
rem ~40 s: the traffic cars (stage B step 5) against their sheets, then a drive each at the game's 120 Hz.
rem npc_cars drives every kind (14 since the player and cop cars joined), about 16 min: give it 20.
set "TT_SAVED=%TEST_TIMEOUT%"
if %TEST_TIMEOUT% LSS 1200 set "TEST_TIMEOUT=1200"
call :run traffic/npc_cars "--headless --fixed-fps 120"
set "TEST_TIMEOUT=%TT_SAVED%"
rem Player cars (stage D): every PlayerCars.KINDS car boots as the player and gets a drive test.
call :run fleet/player_cars "--headless --fixed-fps 120"
call :run fleet/interior_fit --headless
call :run car/special_s0 "--headless --fixed-fps 120"
call :run car/m1_monster "--headless --fixed-fps 120"
rem ~17 s: full throttle at ~245 km/h across floating-origin recenters (the old ground-slab kick), at the game's 120 Hz.
call :run world/recenter_kick "--headless --fixed-fps 120"
call :run fx/fx_pack --headless
call :run fx/tyre_smoke --headless
call :run core/graphics_settings --headless
call :run core/graphics_tiers --headless
call :run fx/exhaust_flames --headless
call :run world/boundary_walls --headless
rem Roadside kit: where hydrants, bins, dumpsters, cones, jersey runs and kerb rails land, per district; collision; determinism.
call :run world/roadside_kit --headless
rem ~1 min: the player into the out-of-bounds wall at 16 speeds and angles, at the game's 120 Hz.
call :run car/wall_hit "--headless --fixed-fps 120"
rem ~4 min: off the map (under the road, outside or over the walls, off the road's end): faded and put back, free.
call :run world/off_map_rescue "--headless --fixed-fps 120"
call :run car/car_scrape "--headless --fixed-fps 120"
call :run car/car_scrape_tunes "--headless --fixed-fps 120"
rem ~4 min each: every player car stock and at the Tuner's lowest suspension corners.
call :run car/car_scrape_cars "--headless --fixed-fps 120"
call :run car/car_scrape_cars_b "--headless --fixed-fps 120"
call :run world/road_space --headless
call :run world/chunk_builder_equivalence --headless
rem World step 1: roof shapes, facade wear, one skyline landmark per district run.
call :run world/building_tops --headless
call :run world/shop_fronts --headless
call :run world/district_kinds --headless
call :run world/chunk_rebuild_perf --headless
call :run world/road_frame --headless
call :run world/road_centerline --headless
call :run world/road_alignment --headless
call :run world/road_layout --headless
rem ~1 min: the median barriers (R1): each type at 9 speeds and angles, crash cushions head-on, crossover rules.
call :run world/barrier_hit "--headless --fixed-fps 120"
rem Lamp-post life (world step 2): moths and a bat, banners, steam, litter. Placement, caps, meshes and the wind number; chunk instances are checked when a window is open.
call :run world/lamp_life --headless
if /i not "%~1"=="quick" (
	rem Headless, but ~2 min of simulated driving; --fixed-fps lets physics run faster than the clock.
	call :run tuning/tune_track "--headless --fixed-fps 60"
	rem ~40 s: tyre pressure and camber sweep on the same track (Tuner PR 1).
	call :run car/tyre_model "--headless --fixed-fps 60"
	rem ~60 s: every chassis setting at both ends on the same track (Tuner PR 2).
	call :run tuning/tuner_settings "--headless --fixed-fps 60"
	rem ~30 s: the new Tuner's presets on the track, every notch, the estimates (Tuner PR 3).
	call :run tuning/tuner_presets "--headless --fixed-fps 60"
	rem ~15 s: the stat panel's Test run through a worker process, the Mechanic's plain words (Tuner PR 4).
	call :run tuning/tuner_test_run "--headless --fixed-fps 60"
	call :run tuning/tuner_safety_net "--headless --fixed-fps 60"
	rem Traffic (stage B step 3) at the game's 120 Hz tick: ~1 min of dense traffic, then the perf sweep.
	call :run traffic/traffic_stability "--headless --fixed-fps 120"
	call :run traffic/traffic_behaviour "--headless --fixed-fps 120"
	rem ~50 s: staggered traffic controller (every 2nd tick, cars alternate) and hidden cars skip wheel visuals.
	call :run traffic/ai_stagger "--headless --fixed-fps 120"
	rem ~70 s: City lights, the signalised crossing (J0/J1a): red queue, amber, 1 a.m. flash.
	call :run world/junction_lights "--headless --fixed-fps 120"
	rem ~100 s: the map, loop 1: the road repeats each lap, drives both ways, and the save names the road.
	call :run world/loop_road "--headless --fixed-fps 60"
	call :run traffic/traffic_perf "--headless --fixed-fps 120"
	call :run world/curve_drive "--headless --fixed-fps 120"
	call :run world/hill_drive "--headless --fixed-fps 120"
	rem ~4 min: 10 km of the default hilly, bending road at 120 and 200 km/h, watching the springs for bumps.
	call :run world/hill_bumps "--headless --fixed-fps 120"
	call :run world/hill_park "--headless --fixed-fps 60"
	rem ~40 s: a downpour at 120 Hz: player and traffic tyres in the wet, NPC wet speed, step() cost.
	call :run world/water_drive "--headless --fixed-fps 120"
	rem ~8 s: brake + throttle from a stop holds the fronts only (line lock burnout).
	call :run car/burnout_line_lock "--headless --fixed-fps 120"
	rem ~3 min: fuel burn calibration, a dry tank in every gearbox, limp causes (slowest wins), refuel from the bank.
	call :run car/fuel_limp "--headless --fixed-fps 60"
	rem ~25 s: damage slice 1: hits by direction, crash pull, rear sag, dead engine, lamps, steam, rattle, garage/station/tow.
	call :run car/car_damage "--headless --fixed-fps 120"
	rem No car or road chunk pops in or out where a camera can see it (Roy, 2026-10-09): flat road, then the hilly one.
	call :run traffic/no_visible_spawn "--headless --fixed-fps 60"
	set "NEON_HILLS=1"
	set "NEON_CURVES=1"
	call :run traffic/no_visible_spawn "--headless --fixed-fps 60"
	set "NEON_HILLS=0"
	set "NEON_CURVES=0"
	call :run tuning/auto_tune_search "--headless --fixed-fps 60"
	call :run tuning/auto_tune_job "--headless --fixed-fps 60"
	rem Key-press tests run headless: a windowed run loses its held keys the moment the window loses focus (found 2026-10-05, it made chunk_drive and feel_pass_1 flaky).
	rem These need a real window: headless drops MultiMesh data.
	call :run world/chunk_drive
	rem Tyre smoke draw cost: a burnout in front of the chase camera, smoke on vs off (budget 0.5 ms).
	call :run fx/tyre_smoke_perf
	rem Also a real window (it reads the interpolated camera); ~45 s of driving 500 km down the road.
	call :run world/floating_origin_drive
	call :run core/game_state --headless
	rem Save system in the game: resume exactly after a quit, quit mid-chase busts.
	call :run core/save_resume --headless
	rem Police F1 in the game: the stand-in patrol car spawns unseen, spots a lit car, not a dark one.
	call :run traffic/police_patrol --headless
	call :run tuning/tuning_panel --headless
	call :run tuning/auto_tune_panel --headless
	call :run tuning/tuner_screen --headless
	call :run tuning/tuner_typing --headless
	call :run world/roadside_detail
	call :run world/floating_structures
	rem Real window: signs read back from the screen (dropped columns, mirrored text), then every sign's placement.
	call :run world/sign_legibility
	call :run world/sign_audit
	rem Same file as the headless run above, with a window: the chunk instances (moths, banners, vents, litter) and the recycle path.
	call :run world/lamp_life
	call :run world/wet_reflections
	rem Wet asphalt shader + visible puddles (S1a): placement needs a window.
	call :run world/road_wet
	rem ~10 s, real window (shaders): traffic tail lamps, brake lamps, distance flares, barrier reflectors.
	call :run traffic/night_lights
	rem ~25 s, real window: low/high beam, flash, auto-dip, cut-off on a wall, cops see by beam.
	call :run car/headlight_beams
	call :run fleet/fleet_silhouette_sweep
	call :run fleet/fleet_budget_scene
	rem The underside's worst-case chase (you + 3 rivals + 4 cops): draw calls per car, real renderer.
	call :run view/chase_undercarriage
	rem Real window: reads rendered sky and moon pixels.
	call :run world/sky_probe
	call :run world/sky_dawn
	call :run world/sky_clouds --headless
	call :run audio/mute --headless
	call :run car/feel_pass_1 --headless
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
