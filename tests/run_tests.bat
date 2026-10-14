@echo off
rem Run every test in tests\ and print one pass/fail summary (GitHub #39).
rem
rem   tests\run_tests.bat          all tests; a game window opens for ~1 min
rem   tests\run_tests.bat ci       the GitHub check: ~100 fast headless tests, about 12 min
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
rem Tests get their own user folder, so their saves, logs and shader pipeline
rem cache stay out of the player's (the cache had grown to 277 MB, #608).
if "%NEON_TEST_APPDATA%"=="" set "NEON_TEST_APPDATA=%LOCALAPPDATA%\BoostSimcadeTests"
if not exist "%NEON_TEST_APPDATA%" mkdir "%NEON_TEST_APPDATA%"
set "APPDATA=%NEON_TEST_APPDATA%"
rem Tests are silent unless you set SOUND=1 (the Dummy audio driver plays nothing).
set "AUDIO=--audio-driver Dummy"
rem Most tests count physics ticks as sixtieths of a second, so they run at 60 Hz; the game itself runs at 120 (see tick_rate.gd and tests/core/tick_rate_120.gd).
if "%NEON_TICKS%"=="" set "NEON_TICKS=60"
if "%SOUND%"=="1" set "AUDIO="
rem No traffic for the older drive-bot tests (they steer across lanes blind); the traffic_* tests ignore this and spawn their own.
if "%NEON_TRAFFIC%"=="" set "NEON_TRAFFIC=0"
rem No work board (Walt's orders at 6 a.m.) in the older tests that cross dawn; tests/core/shop_day.gd and tests/ui/work_board.gd set their own.
if "%NEON_SHOP%"=="" set "NEON_SHOP=0"
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
if /i "%~1"=="ci" goto ci
call :run low_fps_watch --headless
call :run core/perf_ladder --headless
call :run core/smoke --headless
call :run core/game_info --headless
call :run core/palette --headless
call :run ui/fonts --headless
call :run world/names --headless
call :run world/uturn_signs --headless
call :run ui/hud --headless
call :run ui/settings_screen --headless
call :run ui/key_map --headless
call :run ui/key_map_drive --headless
call :run ui/title_and_pause --headless
call :run ui/pause_map --headless
call :run ui/title_kerbside --headless
call :run ui/pause_look --headless
call :run ui/mod_tree_panel --headless
call :run audio/menu_sfx --headless
call :run audio/player_horn --headless
call :run audio/player_gain --headless
call :run core/key_bindings --headless
call :run fleet/car_loft_normals --headless
call :run fleet/test_car --headless
call :run fleet/p1_coupe --headless
call :run car/undercarriage --headless
rem Under a second: the sat-nav's route finder on the map's numbers (no game): exits, turn-rounds at gaps only, the lap seam, acts 2-3, a made-up interchange, missed turns.
call :run car/sat_nav_route --headless
call :run car/cabin_dirt "--headless --fixed-fps 60 --audio-driver Dummy"
call :run world/road_strip_winding --headless
call :run world/sidewalk_collision_taper --headless
call :run world/kerb_profile --headless
call :run world/cross_section --headless
call :run world/side_streets --headless
call :run car/kerb_strike --headless
call :run car/damage_offsets --headless
rem ~1 min: wheel-corner damage (DP1+DP2): the table, the caps, the fade, auto-trim drift and brake pull on the road.
call :run car/damage_handling "--headless --fixed-fps 120"
call :run car/aero_draft_equivalence --headless
call :run view/camera_feel --headless
call :run audio/car_audio --headless
call :run fleet/fleet_design_check --headless
rem Car pipeline step 1: the P1 body.glb from tools/car_pipeline/build_car.py loads, splits into panels, sits on the sheet's numbers.
call :run fleet/car_pipeline_p1 --headless
call :run car/car_assembler --headless
rem Cars from parts after the pilot (kits.py): the Bug's and the wagon's required parts, gaps, symmetry, triangles, draw calls.
call :run fleet/car_parts_kits --headless
rem Engine bays B0 (#642, #644): bay parts out of the driving body, and nothing on a car from parts clashes (bay, lids, doors, glass).
call :run car/engine_bay_budget --headless
call :run car/part_fit --headless
rem Engine bays B1+B2: the hood and trunk open on Y when stopped, the bay-view camera, hazards.
call :run car/car_lids --headless
call :run car/bay_dirt --headless
call :run car/hood_panel --headless
call :run car/bay_mods --headless
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
call :run view/limit_tick --headless
call :run view/cockpit_interior --headless
call :run view/wheel_screen --headless
call :run view/cabin_clearance --headless
call :run view/dash_trinket --headless
call :run view/bobble_head --headless
call :run view/bobble_figures --headless
call :run view/cabin_mods --headless
call :run view/cockpit_isolation "--headless --fixed-fps 120"
call :run view/cockpit_head_motion --headless
call :run ui/hud_rear_strip --headless
call :run view/look_back --headless
call :run view/look_around --headless
call :run view/chase_orbit "--headless --fixed-fps 60"
call :run view/hood_view "--headless --fixed-fps 60"
call :run view/cockpit_horizon --headless
call :run view/cockpit_eye_inside --headless
call :run view/cockpit_shake_rotation_only --headless
call :run view/look_into_corner --headless
call :run view/look_tap_hold "--headless --fixed-fps 60"
call :run view/camera_rate_independent --headless
call :run view/fov_step_limit --headless
call :run view/cockpit_driver --headless
call :run view/cockpit_window --headless
call :run view/gesture_flip_off "--headless --fixed-fps 60"
call :run view/idle_actions "--headless --fixed-fps 60"
call :run view/gauge_pod --headless
call :run view/gauge_layout --headless
call :run view/cockpit_steering_hands --headless
call :run view/cockpit_shifter "--headless --fixed-fps 60"
call :run view/cockpit_shifter_rnd "--headless --fixed-fps 60"
rem the shift animation runs on the frame clock, so the gate test (every
rem player car) and the shifter tests get a fixed 60 fps headless
for %%c in (p0_beater p1_coupe p2_hothatch p3_tuner p4_kei p5_muscle p6_crossover p10_truck) do (
	set "NEON_CAR=%%c"
	call :run view/cockpit_shift_gate "--headless --fixed-fps 60"
)
set "NEON_CAR="
call :run ui/touch_radio --headless
call :run car/tyres "--headless --fixed-fps 60"
call :run car/surface_feel "--headless --fixed-fps 60"
call :run car/clutch_model --headless
call :run audio/driveline_audio --headless
call :run audio/sound_fixes --headless
call :run audio/road_sounds --headless
call :run audio/crash_variety --headless
call :run audio/crash_timbre --headless
call :run audio/cabin_life --headless
call :run audio/audio_mix --headless
call :run audio/radio --headless
call :run audio/radio_power --headless
call :run audio/song_names --headless
call :run ui/radio_carousel --headless
call :run world/person_body --headless
call :run world/night_clock --headless
call :run world/night_bands "--headless --fixed-fps 60"
call :run world/world_mood "--headless --fixed-fps 60"
call :run world/moment_spots "--headless --fixed-fps 60"
rem Water (rain, puddles): the rules and their CPU cost, no game boot.
call :run world/water_rules --headless
rem Weather plan (W1): deck per act, storms, fronts, mid-night change, numbers.
call :run world/season_calendar --headless
call :run world/weather_plan --headless
call :run world/weather_plan_game "--headless --fixed-fps 60"
call :run core/view_settings --headless
call :run core/discord_presence --headless
call :run view/camera_smoothing_setting --headless
call :run core/log_folder --headless
rem Errors and warnings into errors.log (scrubbed, capped), and a crashed last run makes a crash folder.
call :run core/error_log --headless
call :run car/powertrain_health "--headless --fixed-fps 60"
call :run car/fix_car "--headless --fixed-fps 60"
call :run ui/fix_car_button --headless
call :run car/car_parts --headless
call :run car/car_detail --headless
call :run car/car_paint --headless
call :run fleet/car_symmetry --headless
call :run car/required_slots --headless
call :run car/wipers_and_flap --headless
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
rem ~1 min: a speed held by tapping the throttle key does not make the box hunt.
call :run car/auto_key_hold "--headless --fixed-fps 120"
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
rem ~15 s: a saved run brings back the gearbox mode, the gear, and the automatic as it was.
call :run core/save_gearbox "--headless --fixed-fps 120"
call :run core/garage_g0 --headless
rem Save core S1: one save per slot (career + night + meta), the commit order, a kill at every step, tunes per slot, wear and damage kept.
call :run save/save_core --headless
rem Save core S2: old saves upgrade (frozen fixtures in tests/save/fixtures); fails when the save version is bumped without an upgrade step.
call :run save/save_upgrade --headless
rem Build 3 + save core: a fresh slot boots, and the frozen build 3 save (shop day, receipts, weather seed, known stops, gearbox) boots into its night.
call :run save/save_build3_boot --headless
rem Free mode F0: the flag, the night 30 dawn, whole city open, plate lines.
call :run core/freemode --headless
rem F0: cash and bank through reloads, chases and 6 a.m. (and the HUD and pause screen).
call :run core/wallet --headless
rem Work board W0: pay rules, the daily draw, shop pay into the bank once.
call :run core/work_orders --headless
rem Work board W4: lint for data/work_orders.json.
call :run core/work_orders_data --headless
rem Work board W1: the timing bar (4 styles, miss + redo, one press per key).
call :run ui/timing_bar --headless
rem Work board W2: the day step (shop_day: S1-S8) and the board screens (work_board).
call :run core/shop_day --headless
call :run ui/work_board --headless
rem Police F0/F1: heat levels and icons, cop_can_see_player, headlights off hides, night one lines.
call :run traffic/police_heat --headless
rem Police P1/P2: the rulebook table, sight, offences, warning step, heat times.
call :run traffic/police_rules --headless
rem More-alive MA4 (T8): the oncoming warning flash before a speed trap, once per trap.
call :run traffic/trap_warning_flash --headless
rem W0: wrong way = travelling against the flow (8 cases, shoulder, spin); heat with a mocked cop; the flow flip hold.
call :run traffic/wrong_way_pure --headless
call :run traffic/police_wrong_way --headless
call :run traffic/flow_flip --headless
call :run traffic/free_driver_pure --headless
call :run traffic/cop_brain_pure --headless
rem Test build sandbox: free money and fuel, no run-ending, parked start, X start, put back on the road.
call :run core/test_build_sandbox "--headless --fixed-fps 120"
rem The key: X starts the engine and switches it off; starter, catch and shutdown sounds.
call :run car/engine_key "--headless --fixed-fps 120"
rem The start itself: per-engine starter rendered offline (length, coughs, catch, level, weight), fast idle curve.
call :run audio/starter_render "--headless"
rem After the key start in the game: cabin shake, coughs, rev blip, 20 s fast idle.
call :run car/fast_idle "--headless --fixed-fps 120"
rem Delete a save: the store, and the title's Load > Delete a save with its question.
call :run core/save_delete --headless
rem Test build: every player car with everything its mod tree offers fitted.
call :run car/test_build_mods --headless
rem Hard hits and the end of the night: the rules, the hit sensor, the crash screen; then the real restart.
call :run core/run_end "--headless --fixed-fps 120"
call :run core/run_end_restart "--headless --fixed-fps 120"
rem Totalled meter (TM1): no single hit ends a run; the meter, the free first total, bad cops, the tow row, the test build setting.
call :run car/totalled_meter --headless
call :run core/totalled_run_end "--headless --fixed-fps 120"
rem No roll ends a run (TM2): a car on its side or roof rights itself after 3 s and the roll costs meter. Three game boots, about 2 min of driving time.
call :run car/roll_righting "--headless --fixed-fps 120"
call :run world/gas_station --headless
call :run world/gas_station_sides --headless
rem ~4-5 min: the four compound station lots driven for real (in, every spot kind, out) at 60 and 120 km/h.
call :run world/station_lot "--headless --fixed-fps 60"
call :run traffic/traffic_spawn "--headless --fixed-fps 60"
rem Near-band traffic: hand-overs between the 60 m physics band and the rails, both ways, no visible jump.
call :run traffic/traffic_near_band "--headless --fixed-fps 120"
rem ~45 s: race core (RC1): win across a recenter, lose, give up from the pause menu.
call :run core/race_core "--headless --fixed-fps 60"
rem Rival driver (step 1): the plan and line maths; then, each a few minutes on the real game at 120 Hz:
rem same inputs whether the player is behind or ahead, the racing line through four bends, pace against the grip bot.
call :run traffic/rival_plan_pure --headless
call :run traffic/rival_no_rubber_band "--headless --fixed-fps 120"
call :run traffic/rival_line "--headless --fixed-fps 120"
call :run traffic/rival_pace "--headless --fixed-fps 120"
rem The race as the game runs it: traffic, bends and hills, the rival handed back to traffic at the end.
call :run traffic/rival_race "--headless --fixed-fps 120"
call :run core/race_retry "--headless --fixed-fps 60"
rem ~40 s: the traffic cars (stage B step 5) against their sheets, then a drive each at the game's 120 Hz.
rem npc_cars drives every kind (15 since the player and cop cars joined), about 17 min: give it 20.
set "TT_SAVED=%TEST_TIMEOUT%"
if %TEST_TIMEOUT% LSS 1200 set "TEST_TIMEOUT=1200"
call :run traffic/npc_cars "--headless --fixed-fps 120"
set "TEST_TIMEOUT=%TT_SAVED%"
rem Player cars (stage D): every PlayerCars.KINDS car boots as the player and gets a drive test.
call :run fleet/player_cars "--headless --fixed-fps 120"
call :run fleet/interior_fit --headless
rem every player car's cabin: its own look, the road band clear, the driver fits
call :run fleet/interior_unique --headless
call :run fleet/sight_line --headless
call :run fleet/driver_fit --headless
call :run car/special_s0 "--headless --fixed-fps 120"
rem ~17 s: full throttle at ~245 km/h across floating-origin recenters (the old ground-slab kick), at the game's 120 Hz.
call :run world/recenter_kick "--headless --fixed-fps 120"
call :run fx/fx_pack --headless
call :run fx/tyre_smoke --headless
call :run core/graphics_settings --headless
call :run core/graphics_tiers --headless
call :run core/shader_warmup --headless
call :run fx/exhaust_flames --headless
call :run world/boundary_walls --headless
rem Roadside kit: where hydrants, bins, dumpsters, cones, jersey runs and kerb rails land, per district; collision; determinism.
call :run world/roadside_kit --headless
call :run world/prop_ghosts "--headless --fixed-fps 60"
call :run world/prop_hit "--headless --fixed-fps 120"
call :run world/hydrant_break "--headless --fixed-fps 120"
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
call :run world/graffiti --headless
rem The quick driving set (shared test driver, scripts/core/test_driver.gd; docs/TEST_DRIVER.md),
rem at the game's 120 Hz: a clean run at 150 and 300 km/h in traffic plus spin recovery, crashes
rem on purpose, seeded random keys, spawning at 0 to 400 km/h, and record-then-replay.
call :run core/drive_clean "--headless --fixed-fps 120"
call :run core/drive_crash "--headless --fixed-fps 120"
call :run core/drive_fuzz "--headless --fixed-fps 120"
call :run core/drive_spawn "--headless --fixed-fps 120"
call :run core/drive_replay "--headless --fixed-fps 120"
rem F9 saves one bug-report folder: the four files, the recording loads, the 21st folder removes the oldest.
call :run core/bug_bundle "--headless --fixed-fps 120"
if /i not "%~1"=="quick" (
	rem The long driving set, for before a big merge: the same tests with more of everything.
	set "DRIVE_SECS=90"
	set "DRIVE_CARS=40"
	call :run core/drive_clean "--headless --fixed-fps 120"
	rem The clean run on bends and hills: the bot has to slow for the bends.
	call :run core/drive_bends "--headless --fixed-fps 120"
	set "DRIVE_SECS=30"
	set "DRIVE_CARS=24"
	set "DRIVE_FUZZ_SEEDS=1,2,3,4,5,6,7,8"
	call :run core/drive_fuzz "--headless --fixed-fps 120"
	set "DRIVE_SECS="
	set "DRIVE_CARS="
	set "DRIVE_FUZZ_SEEDS="
	set "DRIVE_CRASH_SPEEDS=60,150,250,350"
	call :run core/drive_crash "--headless --fixed-fps 120"
	set "DRIVE_CRASH_SPEEDS="
	set "DRIVE_CURVES=1"
	set "DRIVE_HILLS=1"
	call :run core/drive_spawn "--headless --fixed-fps 120"
	set "DRIVE_CURVES="
	set "DRIVE_HILLS="
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
	rem ~15 s: the near-miss log (kinds, who moved, what the car was doing, the file, cost per tick). The weave baseline (near_miss_weave, 90 s a seed) is run by hand, one seed at a time.
	call :run traffic/near_miss_log "--headless --fixed-fps 120"
	rem ~60 s: the near-miss fix's staged cases (pull-out, no flash, flash, blind spot, abort, edge away, rule breakers, cut-off, swerve, horns, siren). The flow checks (near_miss_flow: spawn safety 5 min, blinker 60 s), the before/after bots (near_miss_scenarios) and the script-cost check (near_miss_cost) are run by hand, one at a time.
	call :run traffic/near_miss_cases "--headless --fixed-fps 120"
call :run traffic/more_alive_traffic "--headless --fixed-fps 120"
	rem ~50 s: staggered traffic controller (every 2nd tick, cars alternate) and hidden cars skip wheel visuals.
	call :run traffic/ai_stagger "--headless --fixed-fps 120"
	rem ~70 s: City lights, the signalised crossing (J0/J1a): red queue, amber, 1 a.m. flash.
	call :run world/junction_lights "--headless --fixed-fps 120"
	call :run world/junction_uturn "--headless --fixed-fps 120"
	rem ~100 s: the map, loop 1: the road repeats each lap, drives both ways, and the save names the road.
	call :run world/loop_road "--headless --fixed-fps 60"
	call :run world/exits_live "--headless --fixed-fps 60"
	call :run world/ring_drive "--headless --fixed-fps 60"
	rem ~3 min: the road both ways: 2 km out, 3 km back across the lap seam, ten turns; road under the car every tick, no chunk rebuilt in view.
	call :run world/two_way_drive "--headless --fixed-fps 60"
	call :run traffic/traffic_perf "--headless --fixed-fps 120"
	call :run world/curve_drive "--headless --fixed-fps 120"
	call :run world/hill_drive "--headless --fixed-fps 120"
	rem ~4 min: 10 km of the default hilly, bending road at 120 and 200 km/h, watching the springs for bumps.
	call :run world/hill_bumps "--headless --fixed-fps 120"
	rem The tunnel under Downtown (TN1): map, dip profile, a pass with traffic at 200 km/h and one at 250.
	call :run world/tunnel "--headless --fixed-fps 120"
	rem ~3 min: more than a lap of the default loop at 140 km/h: no step in the road and no launch at any of 140 chunk borders.
	call :run world/chunk_border_launch "--headless --fixed-fps 120"
	call :run world/hill_park "--headless --fixed-fps 60"
	rem ~40 s: a downpour at 120 Hz: player and traffic tyres in the wet, NPC wet speed, step() cost.
	call :run world/water_drive "--headless --fixed-fps 120"
	rem ~8 s: brake + throttle from a stop holds the fronts only (line lock burnout).
	call :run car/burnout_line_lock "--headless --fixed-fps 120"
	rem ~3 min: fuel burn calibration, a dry tank in every gearbox (the engine starves, 50 km/h or more), dry + hot, refuel from the bank.
	call :run car/fuel_limp "--headless --fixed-fps 60"
	rem ~5 s: every start is a full tank (START_FULL_TANK), two player cars.
	call :run car/fuel_start "--headless --fixed-fps 60"
	rem ~1 min: limp by physics: multipliers per cause, worst wins, the stumble pattern, a wheel on its rim, and each cause's top speed (50 km/h or more).
	rem This runs the selected car; for the per-car table set NEON_CAR=<kind> and run it once per car.
	call :run car/limp_physics "--headless --fixed-fps 60"
	rem ~40 s: tyres (DP3): slow leaks and their timing, the air machine, bent rims, flat spots, the pull and the wobble on the car.
	call :run car/tyre_damage "--headless --fixed-fps 120"
	rem ~25 s: damage slice 1: hits by direction, crash pull, rear sag, dead engine, lamps, steam, rattle, garage/station/tow.
	call :run car/car_damage "--headless --fixed-fps 120"
	rem ~2 min: the Damage setting (Full / Light / Looks only), difficulty, and the radiator heat window per difficulty.
	call :run car/damage_settings "--headless --fixed-fps 60"
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
	rem P1 proof in the real game: 10 min at the traffic flow = 0 heat (about 3 min of test).
	call :run traffic/police_flow "--headless --fixed-fps 60"
	rem P3 proof in the real game: city traffic keeps the city pace, cars change pace at the area line (about 1 min).
	call :run traffic/city_pace "--headless --fixed-fps 60"
	rem P4 proof: the free driver chases the weave bot 5 min through 40 cars: no flips, never stuck, no touches (about 3.5 min).
	call :run traffic/free_driver_chase "--headless --fixed-fps 60"
	rem P5: the cop brain in the game: warning to pursuit, the bust ring, lost and search, called off (about 2 min).
	call :run traffic/police_chase "--headless --fixed-fps 60"
	rem P6 proof: never more than 3 cops, no cop put on the road in view, blocker and flanker get into place, box-in busts (about 1.5 min).
	call :run traffic/police_dispatch "--headless --fixed-fps 60"
	rem (traffic/police_escape_rate is a measurement, about 2 min a trial: run it by hand.)
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
	call :run world/moon_path --headless
	call :run audio/mute --headless
	call :run car/feel_pass_1 --headless
)
:report
echo.
echo Per-test times:
type "%TIMES%"
echo Finished %DATE% %TIME:~0,8%
rem A negative exit code is Godot crashing (often at shutdown, after the test printed PASS). The old script never counted those either; they are only listed.
if defined CRASHED echo CRASHED, not counted as failed:!CRASHED!
if defined CRASHED if defined GITHUB_ACTIONS echo ::warning::CRASHED:!CRASHED!
if defined FAILED (
	echo FAILED:!FAILED!
	rem On GitHub, also as an annotation: the job log is not readable from every client.
	if defined GITHUB_ACTIONS echo ::error::FAILED:!FAILED!
	exit /b 1
)
if defined CRASHED (echo No test failed, but see CRASHED above.) else echo All tests passed.
exit /b 0

rem The GitHub check (.github/workflows/test.yml): about 100 of the fastest quick tests,
rem one or more from every area, so it finishes inside the runner's 30 minutes. The full
rem quick and window sets still run before every merge.
:ci
call :run core/work_orders_data --headless
call :run audio/song_names --headless
call :run car/bolt_ons --headless
call :run car/damage_offsets --headless
call :run car/kerb_strike --headless
call :run core/discord_presence --headless
call :run core/perf_ladder --headless
call :run core/save_system --headless
call :run core/view_settings --headless
call :run fleet/car_loft_normals --headless
call :run fleet/interior_unique --headless
call :run low_fps_watch --headless
call :run traffic/cop_brain_pure --headless
call :run traffic/flow_flip --headless
call :run traffic/free_driver_pure --headless
call :run traffic/police_heat --headless
call :run traffic/police_wrong_way --headless
call :run traffic/trap_warning_flash --headless
call :run traffic/wrong_way_pure --headless
call :run ui/radio_carousel --headless
call :run ui/timing_bar --headless
call :run world/person_body --headless
call :run world/side_streets --headless
call :run world/water_rules --headless
call :run audio/exhaust_pops --headless
call :run audio/menu_sfx --headless
call :run audio/radio_power --headless
call :run car/car_assembler --headless
call :run car/fix_car "--headless --fixed-fps 60"
call :run car/sat_nav_route --headless
call :run car/totalled_meter --headless
call :run car_dirt --headless
call :run core/error_log --headless
call :run core/key_bindings --headless
call :run core/setting_danger --headless
call :run core/work_orders --headless
call :run fleet/car_pipeline_p1 --headless
call :run traffic/police_rules --headless
call :run traffic/rival_plan_pure --headless
call :run view/cabin_mods --headless
call :run view/dash_trinket --headless
call :run world/road_frame --headless
call :run world/season_calendar --headless
call :run world/uturn_signs --headless
call :run world/weather_plan --headless
call :run car/chassis_targets "--headless --fixed-fps 60"
call :run car/test_build_mods --headless
call :run car/undercarriage --headless
call :run core/game_info --headless
call :run core/log_folder --headless
call :run core/save_gearbox "--headless --fixed-fps 120"
call :run core/settings_safety --headless
call :run fleet/car_parts_kits --headless
call :run car/engine_bay_budget --headless
call :run car/part_fit --headless
call :run car/car_lids --headless
call :run car/bay_dirt --headless
call :run car/hood_panel --headless
call :run car/bay_mods --headless
call :run tuning/auto_tune_rules --headless
call :run ui/fonts --headless
call :run ui/key_map --headless
call :run ui/settings_screen --headless
call :run world/cross_section --headless
call :run world/graffiti --headless
call :run world/kerb_profile --headless
call :run world/lamp_life --headless
call :run world/names --headless
call :run world/sidewalk_collision_taper --headless
call :run audio/exhaust_tune --headless
call :run core/palette --headless
call :run view/wheel_screen --headless
call :run world/road_strip_winding --headless
call :run fleet/fleet_design_check --headless
call :run world/road_space --headless
call :run car/car_paint --headless
call :run tuning/tune_params --headless
call :run ui/mod_tree_panel --headless
call :run world/chunk_builder_equivalence --headless
call :run world/district_kinds --headless
call :run world/road_alignment --headless
call :run world/road_centerline --headless
call :run audio/starter_render --headless
call :run fleet/p1_coupe --headless
call :run fleet/test_car --headless
call :run world/chunk_rebuild_perf --headless
call :run world/road_layout --headless
call :run view/camera_rate_independent --headless
call :run world/roadside_kit --headless
call :run audio/audio_master --headless
call :run car/anti_lag_turbo --headless
call :run car/car_parts --headless
call :run car_wash_scene --headless
call :run save/save_upgrade --headless
call :run ui/hud_rear_strip --headless
call :run ui/work_board --headless
call :run audio/crash_timbre --headless
call :run car/car_detail --headless
call :run core/shop_day --headless
call :run fleet/car_symmetry --headless
call :run tuning/tune_slots --headless
call :run view/camera_smoothing_setting --headless
call :run view/cockpit_shake_rotation_only --headless
call :run world/boundary_walls --headless
call :run world/night_bands "--headless --fixed-fps 60"
call :run car/auto_key_hold "--headless --fixed-fps 120"
call :run core/freemode --headless
goto report

:run
echo.
echo === %1  [%TIME:~0,8%]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_one.ps1" -Godot "%GODOT%" -Name %1 -Flags "%~2" -Audio "%AUDIO%" -TimeoutSec %TEST_TIMEOUT% -Log "%TIMES%"
set "RC=!errorlevel!"
if !RC! equ 124 (set "FAILED=!FAILED! %1(TIMEOUT)") else if !RC! gtr 0 (set "FAILED=!FAILED! %1") else if !RC! lss 0 (set "CRASHED=!CRASHED! %1(!RC!)")
exit /b 0
