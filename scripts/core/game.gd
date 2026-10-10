extends Node3D

# Neon Overdrive -- world-space rebuild.
# Milestone 1 (road-chunk foundation) + milestone 2 (real player physics,
# NOW a vendored raycast Vehicle/Wheel controller -- see player.gd header for
# why VehicleBody3D was replaced) per ROADMAP.md. Old scripts/main.gd is
# abandoned, not reused. car_builder.gd IS reused (pure mesh construction).
# This script owns the world (chunks, ground collision, camera)
# and the player instance.

const CHUNKS_AHEAD := 6
const CHUNKS_BEHIND := 4
## Road behind the player is rebuilt (it vanishes) only once no camera can see
## it (ViewGuard.chunk_seen: the rear mirror, the look-back and glance views),
## and by force CHUNKS_SPARE chunks later, 300 m back, where the fog has it.
const CHUNKS_SPARE := 2
## Fixed ambient light (night pass, 2026-10-10): what the Stage A gradient sky
## gave at ambient_light_energy 0.3, measured on the asphalt, so the asphalt
## stays dark whatever the sky does.
const AMBIENT_COLOR := Color(0.075, 0.048, 0.03)
const AMBIENT_ENERGY := 1.0
const POOL_SIZE := CHUNKS_AHEAD + CHUNKS_BEHIND + CHUNKS_SPARE + 1
## On a hilly road (#37) there is no ground plane under the world, only the
## chunks' own road: traffic lives and spawns up to 100 m behind the player
## (TrafficManager.recycle_behind, spawn_behind_max), so keep 150 m of road
## behind it, not 50.
const CHUNKS_BEHIND_HILLS := 4

# Stage B step 3 (2026-10-05): a highway with 4 lanes per direction (ROADMAP
# stage B: "4 lanes per direction is now the spec"; stage A had capped it at 3
# our way, 2 oncoming, varying per chunk). Lane counts no longer change from
# chunk to chunk: lane-follow traffic holds one lane centre and never changes
# lane (milestone 3), so a lane that narrowed away would strand its cars. The
# builder's taper code and the per-chunk centre barrier are unchanged.
const OWN_LANES := 4
const ONC_LANES := 4

# RoadChunkBuilder, CarBuilder, PlayerCar, TrafficManager are all global via class_name.

var section_cache: Dictionary = {"-1": {"own_lanes": OWN_LANES, "onc_lanes": ONC_LANES, "barrier": RoadBarriers.kind_at(-1)}}
var chunk_pool: Array = []  # Array of {root: Node3D, index: int}

# Floating origin (issue #26). Float32 positions lose precision far from
# (0,0,0) -- at 100 km a coordinate only resolves to ~8 mm, and the old 200 km
# ground slab was a hard wall. So the world is kept near the origin: once the
# car is RECENTER_DIST out, everything (car, chunks) moves back by a whole
# number of chunks in one physics step. origin_index is the logical chunk
# index that currently sits at world z=0; chunk indices (and the section
# layout keyed by them) keep counting up forever, only positions are shifted.
# A var, not a const, so tests can shift more often.
var recenter_dist := 1000.0
var origin_index := 0
var recenter_count := 0

var player: PlayerCar
var traffic: TrafficManager
## City lights (junction.gd): the one signalised crossing, or null when the
## switch is off.
var junction: Junction
var game_state: GameState

# Chase camera, its three smoothing modes (#31, C to cycle) and the stage A
# speed feel (FOV, dolly, shake) all live in chase_camera.gd.
var camera: ChaseCamera
var radio: RadioManager
var menu_sfx: MenuSfx   # clicks, ticks and the squelch for every menu (menu_sfx.gd)
var sky: Sky  # tonight's sky (NightSky), driven by SkyDirector
var night_clock: NightClock  # 8 p.m. to 6 a.m., saved (night_clock.gd); windows follow it
var race: RaceController  # race core RC1 (race_controller.gd)
var _bands := false  # hour bands drive traffic and Dave (bands_on)
var moments: MomentSpots  # roadside moment spots, dealt nightly (moment_spots.gd); null when off
var world_mood: WorldMood  # tonight's events: rule-breaker share, bar close, meets, crackdowns
var police_heat: PoliceHeat  # heat level + cop_can_see_player (police F0/F1)
var police: PolicePatrol     # the stand-in patrol car; null with NEON_POLICE=0 or a benchmark
var heat_icons: HeatIcons
const TestMode := preload("res://scripts/core/test_mode.gd")
var rescue: OffMapRescue  # off-map rescue (off_map_rescue.gd)
const Weather := preload("res://scripts/world/weather.gd")
var fx: FxPack  # effects pack v1: vignette, speed lines, skid marks, exhaust flames (fx_pack.gd)

# Save system (run structure, 2026-10-09): auto-save into one of 3 slots, and a
# resume puts the run back where it was (scripts/save/). road_seed is kept so a
# saved run rebuilds the same road; run is what read_run() gave back ({} =
# a fresh start at the beginning of the road).
const SaveDirector := preload("res://scripts/save/save_director.gd")
const UserDirMigration := preload("res://scripts/save/user_dir_migration.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
# The shared test driver and the F9 drive recorder (2026-10-10). `bot` is the
# driver when the game was started with -- --bot=<mode> / NEON_BOT (watching
# the bot in a window uses the same switch the headless tests do), with
# --replay=<file>, or by the benchmark; null in normal play.
const TestDriver := preload("res://scripts/core/test_driver.gd")
const DriveRecorder := preload("res://scripts/core/drive_recorder.gd")
var bot: TestDriver
var recorder: DriveRecorder
var _replay := {}
var saver: SaveDirector
## Tonight's cash and the bank (F0, scripts/core/wallet.gd).
var wallet: Node
const Wallet := preload("res://scripts/core/wallet.gd")
## A hard hit ends the run: rules, crash screen, morning (scripts/core/run_end.gd).
var run_end: Node
const RunEnd := preload("res://scripts/core/run_end.gd")
## Gas stations on the road and the pump menu (stops, first slice).
var gas_station: Node3D
const GasStation := preload("res://scripts/world/gas_station.gd")
const PumpPanel := preload("res://scripts/ui/pump_panel.gd")
const WetReflections := preload("res://scripts/world/wet_reflections.gd")
const WeatherPlan := preload("res://scripts/world/weather_plan.gd")
## Real seconds into a night before Dave reads the forecast.
const FORECAST_DELAY := 8.0
# Weather's wetness drives the wet-road reflections; this is the `version` of
# Weather last pushed to them.
var _weather_seen := -1
var _wet_pinned := false
const StreetAnimals := preload("res://scripts/world/street_animals.gd")
var road_seed := 0
var run := {}
## Whether `run` puts the car back where it was: false for a fresh run, and for
## a save from a road this build does not have (or from before the map), which
## starts at the top of the default road and keeps only the clock and the radio.
var resume_place := false

func _ready() -> void:
	# Auto-Tune worker mode (exported game): no world, just the search.
	var worker_dir := AutoTuneJob.worker_dir_from_args()
	if worker_dir != "":
		set_process(false)
		set_physics_process(false)
		AutoTuneJob.run_worker(get_tree(), worker_dir)
		return
	# Before anything reads user://: a renamed build copies the old folder in.
	UserDirMigration.run()
	AudioSettings.load_settings()
	TrafficSettings.load_settings()
	FxSettings.load_settings()   # cockpit mirrors on/off and quality ([fx] in settings.cfg)
	ViewSettings.load_settings()
	CabinMods.load_settings()   # interior mods: trinket, shift knob, short shifter, strut bar ([interior])
	GraphicsSettings.load_settings()   # preset, edge smoothing, render scale ([graphics])
	DisplaySettings.load_settings()    # fullscreen, window size ([display]); applied below in a play session
	KeyBindings.load_settings()        # the player's rebound keys ([keys])
	GameSettings.load_settings()       # tips on/off ([game])
	# Benchmark mode (-- --benchmark, see benchmark.gd) drives a fixed road so
	# runs are comparable; normal play gets a fresh one each time. It also runs
	# the default traffic (car count and draw distance), not whatever the
	# pause menu last saved, so two machines or two days compare like for like.
	# --gfx=<low|medium|high> runs a graphics tier (its traffic and draw
	# distance become the defaults that --traffic/--detail override).
	var benchmark := Benchmark.requested()
	if benchmark:
		var tier: Dictionary = GraphicsSettings.PRESET_VALUES.get(Benchmark.opt("gfx"), GraphicsSettings.PRESET_VALUES.medium)
		if GraphicsSettings.PRESET_VALUES.has(Benchmark.opt("gfx")):
			GraphicsSettings.set_preset(Benchmark.opt("gfx"))
		TrafficSettings.set_detail_distance(Benchmark.opt_float("detail", tier.detail))
		TrafficSettings.set_car_count(int(Benchmark.opt_float("traffic", tier.traffic)))
	PlayerCars.load_settings()   # which car the player spawns in ([player] in settings.cfg)
	# NEON_TRAFFIC=<n> overrides the saved car count, like NEON_TICKS/NEON_MUTE:
	# tests/run_tests.bat sets 0 so the older drive-bot tests, which steer
	# across lanes blind, do not hit traffic (tests/traffic_*.gd clear it).
	var stages_env := OS.get_environment("NEON_REBUILD_STAGES")
	if stages_env.is_valid_int():
		rebuild_stages_per_frame = maxi(1, int(stages_env))
	var traffic_env := OS.get_environment("NEON_TRAFFIC")
	if traffic_env.is_valid_int():
		TrafficSettings.set_car_count(int(traffic_env))
	if OS.get_environment("NEON_MUTE") == "1":
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	# NEON_RNG_SEED=<n> fixes the global random stream (traffic spawns, junction
	# phases, garage rolls in the chunk builder). Tests set it through
	# Harness.boot so a failure can be rerun on the same draws; randomize()
	# below used to throw away the seed the test had just set.
	# NEON_SEED=<n> pins the global RNG too (tools/look_shot.gd: the same
	# frame twice, for before/after look checks).
	var rng_env := OS.get_environment("NEON_RNG_SEED")
	var seed_env := OS.get_environment("NEON_SEED")
	_setup_wet_reflections(benchmark)
	if benchmark:
		seed(Benchmark.SEED)
	elif rng_env.is_valid_int():
		seed(int(rng_env))
	elif seed_env.is_valid_int():
		seed(int(seed_env))
	else:
		randomize()
	saver = SaveDirector.new(self)
	# A bot or a replayed drive never resumes or overwrites Roy's saved run.
	var bot_mode := TestDriver.requested_mode()
	if TestDriver.requested_replay() != "":
		_replay = DriveRecorder.load_file(TestDriver.requested_replay())
		bot_mode = "replay"
	if bot_mode != "":
		SaveDirector.enabled = false
	if not _replay.is_empty():
		# The recording's road, car, tick rate and traffic count.
		run = _replay.run
		OS.set_environment("NEON_CAR", str(_replay.get("car", "")))
		Engine.physics_ticks_per_second = int(_replay.get("ticks_per_second", Engine.physics_ticks_per_second))
		TrafficSettings.set_car_count(int(_replay.get("traffic", TrafficSettings.car_count)))
	elif not benchmark:
		run = saver.read_run()
	# The clock first: the building window texture is painted for its time
	# when the first chunk is built.
	night_clock = NightClock.new()
	if benchmark:
		night_clock.fixed_minutes = NightClock.BENCHMARK_MINUTES  # same windows every run
	add_child(night_clock)
	if run.get("clock") is Dictionary:
		night_clock.set_time(run.clock.get("minutes", 0.0), run.clock.get("night", 1))
	wallet = Wallet.new()
	wallet.name = "Wallet"
	add_child(wallet)
	# City lights: before the first chunk, which leaves the crossing's mouth
	# open. Never in a benchmark run (same road every time).
	Junction.enabled = TrafficSettings.city_lights and not benchmark
	# Gas stations (stops, first slice): also before the first chunk, which
	# clears their lots. Not in a benchmark run either.
	GasStation.enabled = not benchmark
	_setup_road_shape()
	_setup_world()
	_setup_ground_collision()
	_setup_chunk_pool()
	_setup_player()
	_setup_traffic()
	_setup_camera()
	fx = FxPack.new(player, camera)
	add_child(fx)
	_setup_hud()
	# Off the map (fell off, outside the walls): fade and put the car back.
	rescue = OffMapRescue.new(self, player)
	add_child(rescue)
	_setup_game_state()
	_setup_police(benchmark)
	# Dynamic resolution holds the frame rate inside the tier; benchmark runs
	# keep a fixed scale (comparable numbers) unless --dynres=1.
	if not benchmark or Benchmark.opt("dynres") == "1":
		add_child(DynamicResolution.new())
	if GraphicsAutoPick.wanted():
		add_child(GraphicsAutoPick.new())   # first launch: time a few seconds, pick a tier
	GraphicsSettings.apply(get_tree())
	DisplaySettings.apply(get_window())   # only touches the window in a real play session
	if benchmark:
		add_child(Benchmark.new())
	elif bot_mode != "":
		_start_bot(bot_mode)
	if not benchmark:
		recorder = DriveRecorder.new(self)
		add_child(recorder)
	add_child(saver)

## Wet-road reflections (wet_reflections.gd). How wet the road is drawn:
## --wet=<0..1> (benchmark args) or NEON_WET=<0..1> pins it; otherwise
## Weather's wetness drives it (dry = nothing drawn).
func _setup_wet_reflections(benchmark: bool) -> void:
	var pin := Benchmark.opt("wet") if benchmark else ""
	if pin == "":
		pin = OS.get_environment("NEON_WET")
	if pin.is_valid_float():
		_wet_pinned = true
		WetReflections.set_wetness(float(pin))
		return
	_sync_wetness()

## Follows Weather's wetness, only when it has moved (its `version`).
func _sync_wetness() -> void:
	if _wet_pinned:
		return
	if Weather.version != _weather_seen:
		_weather_seen = Weather.version
		WetReflections.set_wetness(Weather.wetness)
func _start_bot(bot_mode: String) -> void:
	var opts := {"speed": TestDriver.requested_speed(150.0 * TestDriver.KMH) / TestDriver.KMH}
	if Benchmark.opt("seed").is_valid_int():
		opts.seed = int(Benchmark.opt("seed"))
	if not _replay.is_empty():
		opts.keys = PackedInt32Array(_replay.keys)
		player._steer_smooth = float(_replay.get("steer", 0.0))
	bot = TestDriver.start(self, bot_mode, opts)
	var layer := CanvasLayer.new()
	add_child(layer)
	var lbl := Label.new()
	lbl.position = Vector2(16, 56)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.54, 0.12))  # sodium #FF8A1F
	lbl.text = "BOT: %s" % bot_mode + ("" if bot_mode in ["replay", "fuzz", "hold"] else " at %d km/h" % roundi(bot.target_speed / TestDriver.KMH))
	layer.add_child(lbl)

func _setup_world() -> void:
	var env := Environment.new()
	# BUG FIX (2026-09-13, road environment pass #2): a flat BG_COLOR behind
	# fog meant the road visually hit a hard, flat-colored wall at the fog
	# cutoff instead of fading out -- exactly the ugly "hard edge at the
	# horizon" Roy flagged in his screenshot. A gradient sky reads as an
	# actual horizon instead of a wall, and letting fog_density drop means
	# the gradient is doing more of the distance-fade work than a wall of fog.
	#
	# STAGE A (2026-10-04): repainted from the purple neon palette to the look
	# Roy picked (Look Board B, "Gritty PS2 night"): a near-black sky with a
	# dull sodium-orange city glow at the horizon, and a warm dark haze that
	# swallows the distance -- denser than before, so the rows of street lamps
	# fade into it (and the short draw distance is free, RESEARCH item 2).
	#
	# MOON (2026-10-07): the gradient now lives in NightSky's sky shader, which
	# adds a low phasing moon. And the fog no longer touches the sky: at the
	# default fog_sky_affect of 1.0 it painted the whole sky one flat colour
	# (measured: top, mid and horizon all ~RGB 24,16,10), hiding the gradient
	# above and anything drawn in the sky. Distant buildings still fade into
	# the fog colour, so they read as dark silhouettes against the horizon
	# glow. fog_aerial_perspective would blend them into the sky exactly but
	# cost ~0.16 ms on the i5-1235U (tests/world/sky_perf.gd), so it stays off.
	# NIGHT PASS (2026-10-10): the sky follows the clock's night number (moon
	# phase on a 29.5-night cycle, per-night stars and moon path) and the
	# district's glow dome; SkyDirector keeps it moving (added in _setup_nodes
	# once the player exists).
	env.background_mode = Environment.BG_SKY
	env.sky = NightSky.build(night_clock.night)
	sky = env.sky
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.066, 0.042)
	env.fog_density = 0.009
	env.fog_sky_affect = 0.0
	# NIGHT LIGHTING PASS (2026-09-29, docs/research/RESEARCH-cheap-pretty.md item 1): the
	# gradient sky is also the ambient source (Godot's default under BG_SKY),
	# so its horizon glow fills the scene for free -- no extra light needed.
	# Dialled down from the default 1.0 because at full energy a bright horizon
	# lifts the near-black asphalt back toward grey and flattens the emissive
	# markings it is supposed to sit behind.
	# NIGHT PASS (2026-10-10): pinned to a fixed colour instead of the sky, so
	# the brighter navy top and the per-district glow dome never lift the
	# asphalt. The colour and energy were matched to what the old sky gave
	# (road region in tests/world/sky_shots.gd, before and after).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	# GLOW (#25): a short, tight halo on the emissive markings -- Roy's pick
	# ("A - Tight") of four options compared in an exported benchmark. Only the
	# three smallest blur levels, so the halo hugs the lines instead of washing
	# the scene; threshold 1.0 keeps the dim, non-emissive geometry out of it.
	# Measured cost on the i5-1235U / Mobile renderer: ~0.05 ms/frame, inside
	# run-to-run noise, so the godot#98531 Mobile glow slowdown does not show
	# up here. Re-measure with benchmark.bat if these values change.
	env.glow_enabled = true
	for i in 7:
		env.set_glow_level(i, 1.0 if i <= 2 else 0.0)
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# Look B's "grainy filter" (stage A): a light, darken-only animated grain
	# over the 3D view, under the HUD.
	add_child(FilmGrain.new())

	# NIGHT LIGHTING PASS (2026-09-29, docs/research/RESEARCH-cheap-pretty.md item 1): this
	# was a warm white key at energy 1.1 -- i.e. a daylight sun sitting inside
	# a purple night palette and fighting it. road_chunk_builder.gd already
	# authors this world for night: near-black asphalt albedos, plus emissive
	# curbs, edge lines, lane dashes, barriers, building windows and
	# cyan/magenta pylons at energy 0.9-2.5. Those ARE the light you are meant
	# to see (and it's why the markings were made emissive in the first place
	# -- see that file's header). So this light's only remaining job is a dim
	# cool moonlight key: enough to give the car body and roadside geometry
	# form so they don't read as flat silhouettes, not enough to compete with
	# the neon. Renamed sun -> moon because that is now what it is.
	# Stage A (2026-10-04): the light you see is now sodium street lamps, their
	# pools on the road, windows and the player's headlight; the markings and
	# posts are dim paint, not neon. The moon keeps the same job.
	#
	# Shadows stay off (Godot's default) deliberately, not by oversight: a
	# shadow-casting directional light costs an entire extra pass, and at this
	# key energy the shadow would barely be visible anyway. A blob shadow under
	# the car is the cheap version if one is wanted later (RESEARCH item 5).
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -35, 0)
	moon.light_energy = 0.2
	moon.light_color = Color(0.6, 0.66, 1.0)
	add_child(moon)

# ---------- ground collision (new for milestone 2 -- chunks are visual only, wheels need something real to hit) ----------
func _setup_ground_collision() -> void:
	# Hills (#37): the road has no single plane; each chunk carries its own
	# road collision instead (RoadChunkBuilder "RoadCol").
	if RoadFrame.has_hills():
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	# One flat ground under the whole play area instead of per-chunk
	# collision -- the road is flat, so a single static shape is simplest
	# and cheapest. Revisit if/when terrain height ever varies.
	#
	# History: it was a BoxShape3D slab. BUG FIX (2026-09-12): its edge once
	# sat exactly at the spawn point, so the rear axle hung over nothing and
	# the car backflipped off the map. Floating origin (issue #26) then cut it
	# down to recenter_dist plus margin either way.
	#
	# BUG FIX (2026-10-06, tests/world/recenter_kick.gd): now an infinite plane. At
	# ~240 km/h the rear-bottom edge of the chassis collision box rides on the
	# ground (aero downforce + squat), and box-vs-box with an edge lying flat
	# on a face is ill-conditioned: on some ticks Godot's separating-axis test
	# picks an edge-edge axis, the contact normal tilts 1-2 degrees and one
	# step throws the car up and sideways. The rear springs over-extend, GEVP
	# drops the rear tyre forces for a few ticks and the car weaves at 3-12
	# m/s^2. It showed up ~0.5-1.5 s after a floating-origin recenter because
	# recentering sends the car over the same stretch of slab again and again
	# at full speed and the bad ticks depend on float rounding at that spot;
	# with the slab moved along with the world on each recenter the run was
	# clean. A plane has no edges, so the contact normal is always straight up,
	# and it needs no size, so it no longer depends on recenter_dist.
	shape.shape = WorldBoundaryShape3D.new()  # the plane y=0, solid below
	body.add_child(shape)
	# Physics rewrite (2026-09-13): the vendored Wheel raycast identifies
	# surface type by the FIRST group on whatever collision body it hits
	# (see scripts/vendor/gevp/gevp_wheel.gd process_forces). This ground plane
	# is the road+shoulder+curb surface, so it's tagged "Road" -- the raised
	# sidewalk collision added per-chunk in road_chunk_builder.gd sits
	# slightly higher and is tagged "Dirt", so a wheel over the sidewalk hits
	# that closer box first regardless of this plane extending underneath it.
	body.add_to_group("Road")
	add_child(body)

# ---------- road shape (#37 curves) ----------
## How bendy the road is, 0 (straight) to 1 (mostly bends); NEON_CURVES=<x>
## overrides it (tests/run_tests.bat sets 0 for the older drive tests, which
## steer blind down world -Z). Benchmark runs stay straight so they compare
## with every earlier run. NEON_ROAD_SEED=<n> fixes the road for tests.
@export var curviness := 0.5
## How hilly, 0 (flat) to 1 (rolling the whole way); NEON_HILLS=<x> overrides
## it (run_tests.bat sets 0). NEON_KICKERS=<x> is the chance a crest is a
## jump: 0, for the R6 playtest preset only. Benchmark runs stay flat.
@export var hilliness := 0.5
@export var kicker_chance := 0.0

## The map (road_map.gd): which road this run is on. A resumed run stays on its
## own; otherwise NEON_ROAD=<id> picks one ("endless" = the road from before
## the map), else the default loop. A loop has its own fixed seed, so the city
## is the same every run; NEON_ROAD_SEED still overrides it.
func _pick_road() -> String:
	if not run.is_empty():
		var saved := str(run.road.get("id", ""))
		if RoadMap.knows(saved):
			resume_place = true
			return saved
		print("save: this run was on road '%s', which this build does not have; starting at the top of %s" % [saved, RoadMap.DEFAULT])
	var env := OS.get_environment("NEON_ROAD")
	return env if RoadMap.knows(env) else RoadMap.DEFAULT

func _chunks_behind() -> int:
	return CHUNKS_BEHIND_HILLS if RoadFrame.has_hills() else CHUNKS_BEHIND

func _setup_road_shape() -> void:
	var env := OS.get_environment("NEON_CURVES")
	if env.is_valid_float():
		curviness = float(env)
	var hills_env := OS.get_environment("NEON_HILLS")
	if hills_env.is_valid_float():
		hilliness = float(hills_env)
	var kick_env := OS.get_environment("NEON_KICKERS")
	if kick_env.is_valid_float():
		kicker_chance = float(kick_env)
	if Benchmark.requested():
		curviness = Benchmark.opt_float("curves", 0.0)
		hilliness = Benchmark.opt_float("hills", 0.0)
	var seed_env := OS.get_environment("NEON_ROAD_SEED")
	# A benchmark run with --curves or --hills gets a fixed road, so runs compare.
	road_seed = int(seed_env) if seed_env.is_valid_int() else (Benchmark.SEED if Benchmark.requested() else randi())
	RoadMap.use(_pick_road())
	if RoadMap.is_loop() and not seed_env.is_valid_int():
		road_seed = RoadMap.seed_of(RoadMap.road_id)
	if resume_place:
		# A resumed run: its own road, and the floating origin where it was.
		road_seed = int(run.road.seed)
		curviness = float(run.road.curviness)
		hilliness = float(run.road.hilliness)
		kicker_chance = float(run.road.kicker_chance)
		# On a loop only the place on the lap matters: laps driven are dropped.
		origin_index = RoadMap.lap_chunk(int(run.origin_index))
		recenter_count = int(run.get("recenter_count", 0))
		if run.get("sections") is Dictionary:
			for k in run.sections:
				if run.sections[k] is Dictionary and str(k).is_valid_int():
					section_cache[str(RoadMap.lap_chunk(int(k)))] = {"own_lanes": OWN_LANES, "onc_lanes": ONC_LANES,
						"barrier": run.sections[k].get("barrier", false) == true}
	RoadFrame.origin_index = origin_index
	RoadFrame.align = RoadAlignment.new(road_seed, curviness, hilliness, kicker_chance, RoadMap.period) if curviness > 0.0 or hilliness > 0.0 else null
	# Lane adds and drops, median splits and exits (road lane proposal): a
	# third stream from the same seed. NEON_LAYOUT=0 keeps the plain 4+4,
	# NEON_LAYOUT=<metres> forces a change that often (the tests' sweep).
	var busy_env := OS.get_environment("NEON_LAYOUT")
	var busy := float(busy_env) if busy_env.is_valid_float() else 1.0
	if Benchmark.requested():
		busy = 0.0
	RoadFrame.layout = RoadLayout.new(road_seed, RoadFrame.align, busy)
	RoadBarriers.reset()  # dents and crumples last one run

# ---------- section math (reused from old main.gd, keyed by chunk index instead of distance) ----------
func _section_at(idx: int) -> Dictionary:
	idx = RoadMap.lap_chunk(idx)  # a loop: the same chunk every lap
	var key := str(idx)
	if section_cache.has(key):
		return section_cache[key]
	# Fixed lane counts since stage B step 3 (see OWN_LANES) until the road
	# layout's lane changes go live (road lane proposal step 3); only the
	# centre barrier follows the district, with one crossover gap per district
	# (RoadBarriers, R1).
	var own := OWN_LANES
	var onc := ONC_LANES
	var lay := RoadFrame.layout
	if lay != null and lay.lanes_live:
		var p := lay.lanes_pair(float(idx) * RoadChunkBuilder.CHUNK_LEN)
		own = p.x
		onc = p.y
	var cfg := {"own_lanes": own, "onc_lanes": onc, "barrier": RoadBarriers.kind_at(idx), "gap": RoadBarriers.has_gap(idx)}
	section_cache[key] = cfg
	return cfg

# ---------- chunk pool ----------
func _setup_chunk_pool() -> void:
	# The chunk the car starts on: 0 for a fresh run, the saved car's for a
	# resumed one (its index counts from origin_index, like _update_chunk_pool).
	if MomentSpots.enabled():
		moments = MomentSpots.new()
		moments.name = "MomentSpots"
		moments.road_seed = road_seed
		moments.night_clock = night_clock
		moments.pool = chunk_pool
		add_child(moments)
	var start := 0
	if resume_place:
		var z := RoadFrame.unroll(SaveDirector.v3(run.car.xform.slice(9, 12))).z
		start = int(floor(-z / RoadChunkBuilder.CHUNK_LEN)) + origin_index
	for i in range(CHUNKS_AHEAD + chunks_ahead_extra + _chunks_behind() + CHUNKS_SPARE + 1):
		var idx := start + i - _chunks_behind() - CHUNKS_SPARE
		var prev_cfg := _section_at(idx - 1)
		var cfg := _section_at(idx)
		var root := RoadChunkBuilder.build_chunk(idx, prev_cfg, cfg, origin_index)
		add_child(root)
		chunk_pool.append({"root": root, "index": idx})
		if moments != null:
			moments.dress_chunk(root, idx)
	_pool_centre = start

## Tests: called as (chunk_root, gap) just before a chunk is rebuilt (it vanishes
## from where it stands); gap is how many chunks behind the player it is.
var chunk_event_hook: Callable = Callable()
## Chunk rebuilds in flight (RoadChunkBuilder.rebuild_begin), oldest first.
## A recycled chunk used to be rewritten whole in the frame it fell behind,
## ~3 ms (tests/world/chunk_rebuild_perf.gd) landing in one frame every 50 m of
## road: a visible hitch at speed. Now each frame runs rebuild_stages_per_frame
## stages (about 1 ms; a count, not a wall-clock budget, so a run is the same
## on a loaded machine and the physics tests stay reproducible), and a job
## takes three or four frames. The chunk is parked out of the way and not solid until it
## is done; it is 250-350 m ahead, in the fog, where it appeared from nothing
## before too.
var _rebuild_jobs: Array = []
## NEON_REBUILD_STAGES=<n> overrides it (a huge value rebuilds a chunk whole
## in one frame again, to bisect a test against the spreading).
var rebuild_stages_per_frame := 3

## The chunk the pool is centred on: the player's, held until the car is
## POOL_HYSTERESIS metres into the next one, so a car sitting on a join does
## not rebuild a chunk at each end of the pool every time it rolls across.
var _pool_centre := 0
const POOL_HYSTERESIS := 5.0

## Both directions (the map, 2026-10-10): the pool is the same number of
## chunks either side of the player (CHUNKS_AHEAD = CHUNKS_BEHIND +
## CHUNKS_SPARE, 300 m, where the fog has the road), so the road is there
## whichever way the car goes or turns. A chunk that falls off one end is
## rebuilt at the other; it is 350 m away when it goes.

## Extra chunks kept built ahead of the player, on top of CHUNKS_AHEAD (the
## pool grows by the same number). Skeleton-car spike (2026-10-10): at
## 400 km/h the stock 300 m look-ahead is 2.7 s of road, so the junction chunk
## is shown one chunk earlier. NEON_CHUNKS_AHEAD_EXTRA=<n> sets it for one run;
## tests set it before the pool is built.
var chunks_ahead_extra := int(OS.get_environment("NEON_CHUNKS_AHEAD_EXTRA")) if OS.get_environment("NEON_CHUNKS_AHEAD_EXTRA").is_valid_int() else 0

## Chunk rebuild timing (skeleton-car spike): wall-clock microseconds of the
## last RoadChunkBuilder.rebuild_chunk, the slowest one, the running total,
## how many, and the most rebuilt in one frame. Read by tests/world/jet_drive.gd.
var rebuild_us_last := 0
var rebuild_us_max := 0
var rebuild_us_total := 0
var rebuild_count := 0
var rebuilds_in_frame_max := 0
## Slowest _shift_origin (floating-origin recenter), microseconds.
var recenter_us_max := 0

func _update_chunk_pool(ref_z: float) -> void:
	var at := -ref_z / RoadChunkBuilder.CHUNK_LEN + float(origin_index)
	var slack := POOL_HYSTERESIS / RoadChunkBuilder.CHUNK_LEN
	if floori(at - slack) > _pool_centre:
		_pool_centre = floori(at - slack)
	elif floori(at + slack) < _pool_centre:
		_pool_centre = floori(at + slack)
	@warning_ignore("integer_division")
	var half := (chunk_pool.size() - 1) / 2
	var lo := _pool_centre - half
	var have := {}
	var spare: Array = []
	for c in chunk_pool:
		if absi(c.index - _pool_centre) > half or have.has(c.index):
			spare.append(c)
		else:
			have[c.index] = true
	if spare.is_empty():
		_run_rebuild_jobs()
		return
	var rebuilt_now := 0
	for idx in range(lo, lo + chunk_pool.size()):
		if have.has(idx) or spare.is_empty():
			continue
		var c: Dictionary = spare.pop_back()
		if chunk_event_hook.is_valid():
			chunk_event_hook.call(c.root, absi(c.index - _pool_centre))
		var prev_cfg := _section_at(idx - 1)
		var cfg := _section_at(idx)
		# A chunk recycled again before its last rebuild finished: that job is dropped.
		for j in _rebuild_jobs:
			if j.root == c.root:
				_rebuild_jobs.erase(j)
				break
		# Staged (chunk rebuild budget, #314): begun here, run a few stages a
		# frame by _run_rebuild_jobs; the finish stage resets its interpolation.
		_rebuild_jobs.append(RoadChunkBuilder.rebuild_begin(c.root, idx, prev_cfg, cfg, origin_index))
		rebuilt_now += 1
		rebuilds_in_frame_max = maxi(rebuilds_in_frame_max, rebuilt_now)
		c.index = idx
	_run_rebuild_jobs()

func _run_rebuild_jobs() -> void:
	if _rebuild_jobs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	for i in rebuild_stages_per_frame:
		if _rebuild_jobs.is_empty():
			break
		if RoadChunkBuilder.rebuild_step(_rebuild_jobs[0]):
			_rebuilt(_rebuild_jobs.pop_front())
	# Skeleton-car spike counters: the cost of this frame's slice of rebuild work.
	rebuild_us_last = Time.get_ticks_usec() - t0
	rebuild_us_max = maxi(rebuild_us_max, rebuild_us_last)
	rebuild_us_total += rebuild_us_last
	SpikeLog.mark("chunk_rebuild", SpikeLog.since(t0))

## A staged rebuild has just finished: the chunk is in its new place and solid.
## Only now can the night's moments dress it: a trap's patrol car is placed
## against the chunk's own transform, and before the finish that was still the
## place the chunk was recycled from (the car then stood, solid, wherever the
## difference between the two put it, the road included).
func _rebuilt(job: RoadChunkBuilder.RebuildJob) -> void:
	rebuild_count += 1
	if moments != null and is_instance_valid(job.root):
		moments.dress_chunk(job.root, job.index)

## Finishes every rebuild in flight now (tests that walk the pool by hand).
func flush_rebuilds() -> void:
	while not _rebuild_jobs.is_empty():
		if RoadChunkBuilder.rebuild_step(_rebuild_jobs[0]):
			_rebuilt(_rebuild_jobs.pop_front())

# ---------- floating origin (issue #26) ----------
func _physics_process(_delta: float) -> void:
	# Runs before the car's own _physics_process (parent before child), so
	# GEVP computes this step's velocity from positions that are already
	# shifted consistently.
	# Road-space z (RoadFrame, #37): distance along the road, which is what
	# the whole-chunk shift counts in.
	var z := RoadFrame.unroll(player.global_position).z
	if absf(z) >= recenter_dist:
		var t0 := Time.get_ticks_usec()
		_shift_origin(int(floor(-z / RoadChunkBuilder.CHUNK_LEN)))
		recenter_us_max = maxi(recenter_us_max, Time.get_ticks_usec() - t0)
	Weather.step(_delta)  # before the cars: they read this tick's wetness
	_sync_wetness()
	if Input.is_action_just_pressed("mute"):
		toggle_mute()
	if Input.is_action_just_pressed("radio_next") and radio != null:
		request_next_station()

## Next station (N): with the cockpit built the driver's hand reaches the touch
## screen and the station changes on the tap (CockpitFrame.request_radio), in
## every view; with no cockpit (NEON_COCKPIT=0) it changes at once.
func request_next_station() -> void:
	var f: CockpitFrame = camera.frame if camera != null else null
	if f != null and f.driver != null:
		f.request_radio()
	else:
		radio.next_station()

## Moves the world back by shift_chunks whole chunks (positive = the car had
## driven forward, -z). Whole chunks keep chunk positions exact integers x 50.
func _shift_origin(shift_chunks: int) -> void:
	if shift_chunks == 0:
		return
	var t0 := Time.get_ticks_usec()
	# The world moves so the new origin chunk's start lands on (0, 0, 0): on a
	# straight road that is +shift_chunks * 50 along z; on a curved one
	# (RoadFrame, #37) x moves too. Nothing is rotated.
	var offset := -RoadFrame.chunk_xf(origin_index + shift_chunks, origin_index).origin
	origin_index += shift_chunks
	RoadFrame.origin_index = origin_index
	recenter_count += 1

	# The car. Velocity and spin carry over untouched (they are not
	# positions). GEVP derives speed from the position it saved on the last
	# step, on the body and on every wheel; left unshifted, the next step
	# would read the 1 km move as a 60 km/s burst and wreck the tire model.
	player.global_position += offset
	player.previous_global_position += offset
	for w in player.wheel_array:
		w.previous_global_position += offset
		w.last_collision_point += offset
	# Physics interpolation is on (ISSUES B7): without a reset the car would
	# be drawn sliding 1 km across one tick.
	player.reset_physics_interpolation()

	# A chunk mid-rebuild stays parked out of the way; its finish stage places
	# it from the job's origin, which moves with the shift here.
	for j in _rebuild_jobs:
		j.origin_index = origin_index
	for c in chunk_pool:
		if RoadChunkBuilder.is_rebuilding(c.root):
			continue
		# Re-derived from the index, not +=, so error can never accumulate.
		c.root.transform = RoadFrame.chunk_xf(c.index, origin_index)
		c.root.reset_physics_interpolation()
		# Now, not at the next transform flush: a stale chunk collider is
		# invisible on a straight road but lies across a curved one (#37).
		RoadChunkBuilder.sync_collision(c.root)
	# Traffic (milestone 3): every car gets the same bookkeeping as the player.
	traffic.shift_world(offset)
	if police != null:
		police.shift_world(offset)
	fx.shift_world(offset)  # skid marks are laid in world space
	SpikeLog.mark("recenter", SpikeLog.since(t0))
	# The ground plane stays put: it is infinite.
	# The camera follows the car's interpolated position in _process, so it
	# needs nothing here.

# ---------- player ----------
## Where the player starts: in a lane, not on the centre line (x=0) as before
## stage B step 3, now that the oncoming lanes carry traffic. Lane 1 of 4.
const PLAYER_SPAWN_LANE := 1

func _setup_player() -> void:
	player = PlayerCar.new()
	player.position = RoadFrame.roll(Vector3(TrafficManager.lane_centre(PLAYER_SPAWN_LANE, false), 0.0, 0))
	if resume_place:
		player.transform = SaveDirector.array_to_xform(run.car.xform)
	add_child(player)
	if resume_place:
		saver.restore_car(player, run.car)
	# Interior mods batch 1 (2026-10-09): the fitted parts' sim effects (short
	# shifter, strut bar) held on the built car, and the bar itself under the hood.
	CabinMods.attach(player)
	StrutBar.sync(player)

# ---------- traffic (milestone 3, stage B step 3) ----------
# Lane-follow traffic: the same raycast Vehicle as the player, see
# traffic_car.gd / traffic_manager.gd. Count and draw distance come from the
# pause menu's Traffic sliders (TrafficSettings). Added after the player, so
# its cars' _physics_process runs after the player's.
func _setup_traffic() -> void:
	if moments != null:
		moments.player = player
	traffic = TrafficManager.new()
	traffic.player = player
	traffic.own_lanes = OWN_LANES
	traffic.onc_lanes = ONC_LANES
	traffic.car_count = TrafficSettings.car_count
	traffic.detail_distance = TrafficSettings.detail_distance
	traffic.add_to_group(GraphicsSettings.GROUP)   # a graphics tier sets count and distance
	add_child(traffic)
	# Auto-dip: the high beam drops to low when a car is in its way.
	player.beams.dip_probe = traffic.beam_blocked
	if Junction.enabled:
		junction = Junction.new()
		junction.night_clock = night_clock
		# A random point in the cycle, so the first arrival is not always green.
		junction.t = randf() * Junction.CYCLE
		add_child(junction)
		traffic.junction = junction

# ---------- camera ----------
func _setup_camera() -> void:
	camera = ChaseCamera.new(player)
	add_child(camera)

## M mutes all game audio (master bus). Setting NEON_MUTE=1 starts muted, for
## test runs and late-night testing.
func toggle_mute() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, not AudioServer.is_bus_mute(bus))

# ---------- HUD (scripts/ui/hud.gd) ----------
func _setup_hud() -> void:
	var hud := Hud.new(player, camera, traffic)
	hud.night_clock = night_clock
	var sky_director := SkyDirector.new()
	sky_director.sky = sky
	sky_director.night_clock = night_clock
	sky_director.game = self
	add_child(sky_director)
	hud.wallet = wallet
	add_child(hud)

# ---------- game state (pause / restart / quit, issue #27) ----------
func _setup_game_state() -> void:
	game_state = GameState.new()
	# Real play sessions only (tests and benchmarks keep running): alt-tab and a
	# stalled frame pause the game and say why on the pause screen.
	var real_play: bool = DisplaySettings.player_run() and not Benchmark.requested()
	game_state.pause_on_focus_loss = real_play
	game_state.stall_secs = GameState.STALL_SECS if real_play else 0.0
	add_child(game_state)
	CarDetail.bind_state(game_state)  # photo mode shows the cars' detail parts
	# Before the pause menu, which reads it for the race button.
	race = RaceController.new(player, traffic, night_clock, game_state)
	add_child(race)
	# The pause screen's "Quit race" row (title/pause branch) gives the race up.
	game_state.race_quit_requested.connect(race.give_up)
	var pause := PauseMenu.new(game_state)
	pause.wallet = wallet
	pause.night_clock = night_clock
	add_child(pause)
	add_child(TunerScreen.new(player, game_state))
	add_child(WarningLights.new(player))
	add_child(PhotoMode.new(game_state, camera))
	gas_station = GasStation.new()
	gas_station.player = player
	add_child(gas_station)
	add_child(PumpPanel.new(game_state, player, wallet, night_clock))
	gas_station.pulled_up.connect(func(_s: float) -> void: game_state.open_station())
	add_child(WashScreen.new(game_state))
	# Special vehicles: a flip ends the run (SpecialRunEnd). A restart is the
	# stand-in until the run loop (stage C) owns what "ends the night" means.
	var kind := PlayerCar.chassis_kind()
	if SpecialRunEnd.has_limit(kind):
		var special_end := SpecialRunEnd.new(player, kind)
		special_end.run_ended.connect(func(_why: String) -> void: game_state.restart())
		add_child(special_end)
	radio = RadioManager.new()
	radio.listener = player  # reception follows the car (tunnels, bridges)
	radio.process_mode = Node.PROCESS_MODE_ALWAYS   # plays on, muffled, while paused (PauseLook)
	add_child(radio)
	add_child(PauseLook.new(game_state, player, camera))
	add_child(TitleScreen.new(game_state))
	menu_sfx = MenuSfx.new()
	add_child(menu_sfx)
	if run.get("radio") is float or run.get("radio") is int:
		radio.tune_to(int(run.radio))
	if GameState.wants_title():
		game_state.enter_title()   # the title shows over the frozen world; Drive is instant
	game_state.state_changed.connect(saver.on_state_changed)
	game_state.restarting.connect(saver.on_restart)
	game_state.quitting.connect(saver.save_now)
	# 6 a.m.: tonight's cash goes into the bank (F0).
	night_clock.night_ended.connect(func(_n: int) -> void: wallet.bank_night())
	night_clock.night_ended.connect(func(_n: int) -> void: saver.save_now.call_deferred())
	run_end = RunEnd.new()
	run_end.player = player
	run_end.camera = camera
	run_end.wallet = wallet
	run_end.night_clock = night_clock
	run_end.game_state = game_state
	add_child(run_end)
	run_end.sensor.enabled = wrecks_on()
	if moments != null:
		moments.announce = radio.announce
	world_mood = WorldMood.new()
	add_child(world_mood)
	_start_weather()
	world_mood.event_started.connect(_on_event)
	if OS.get_environment("NEON_CRACKDOWN") == "1":
		world_mood.start_crackdown(night_clock.minutes)
	_bands = bands_on()
	night_clock.hour_changed.connect(_on_hour)
	night_clock.night_ended.connect(func(_n: int) -> void: radio.announce_hour(NightClock.END_HOUR))

# ---------- police (F0/F1, scripts/traffic/police_heat.gd) ----------
## Heat always exists (it is the hook police systems ask); the patrol car only
## when PolicePatrol.enabled. Night one's lines go to Dave when his station is
## on, else to the heat caption.
func _setup_police(benchmark: bool) -> void:
	police_heat = PoliceHeat.new()
	police_heat.name = "PoliceHeat"
	police_heat.player = player
	police_heat.night_clock = night_clock
	add_child(police_heat)
	heat_icons = HeatIcons.new(police_heat)
	add_child(heat_icons)
	police_heat.line_said.connect(func(text: String) -> void:
		if not radio.announce(text):
			heat_icons.say(text))
	game_state.restarting.connect(police_heat.reset)
	if PolicePatrol.enabled(benchmark):
		police = PolicePatrol.new()
		police.name = "Police"
		police.player = player
		police.traffic = traffic
		police.heat = police_heat
		add_child(police)

## Dave reads the hour out. 8 p.m. only ever comes from the roll into the next
## night, right after his 6 a.m. sign-off, so it is skipped.
func _on_hour(hour24: int) -> void:
	if hour24 == NightClock.START_HOUR:
		_begin_night(false)  # the night has already counted up (night_clock.gd)
	else:
		_weather_change(hour24)
	if hour24 != NightClock.START_HOUR:
		if hour24 == 2 and world_mood.crackdown_until < 0.0:
			radio.announce(WorldMood.BAR_CLOSE_LINE)  # bar close starts on the hour
		else:
			radio.announce_hour(hour24)

## A hard hit ends the run (run_end.gd). Off in the benchmark, and in tests
## unless the test asks with NEON_WRECK=1: the older drive tests crash on
## purpose and must not be restarted halfway. NEON_WRECK=0 turns it off in play.
func wrecks_on() -> bool:
	var env := OS.get_environment("NEON_WRECK")
	if Benchmark.requested() or env == "0":
		return false
	return not TestMode.active() or env == "1"

## Tonight's weather (weather.gd, planned by weather_plan.gd): NEON_WEATHER
## pins it; otherwise the benchmark and tests stay dry, so their numbers keep
## matching earlier runs, and a real run follows the act's weather deck
## (Weather.ROLL_ON) and starts already wet if it was raining before you got
## in the car.
func _start_weather() -> void:
	var pinned := Weather.env_level()
	if pinned >= 0:
		Weather.set_level(pinned, true)
	elif _plan_active():
		_begin_night(true)
	else:
		Weather.reset()

## The deck runs when rolling is on, or NEON_WEATHER=plan asks for it (the
## tests, a look at the plan with rain still off). Pinned weather, the
## benchmark and plain tests never run it.
func _plan_active() -> bool:
	var forced := OS.get_environment("NEON_WEATHER").to_lower() == "plan"
	if Weather.env_level() >= 0 or Benchmark.requested():
		return false
	return forced or (Weather.ROLL_ON and not TestMode.active())

## A night starts (8 p.m., or the game booting into one): take tonight's entry
## from the deck. The road wets or dries gradually, except on boot.
func _begin_night(boot: bool) -> void:
	if not _plan_active():
		return
	var e := WeatherPlan.entry(night_clock.night, road_seed)
	Weather.tonight = e
	Weather.set_level(WeatherPlan.level_at(e, night_clock.minutes), boot)
	# Dave gives the forecast a few seconds into the night (not over his own
	# 6 a.m. sign-off), only when the night is just beginning.
	if night_clock.minutes < 30.0:
		var night := night_clock.night
		get_tree().create_timer(FORECAST_DELAY, false).timeout.connect(func() -> void:
			if night_clock.night == night and radio != null:
				radio.announce(WeatherPlan.forecast_line(e)))

## The hour struck: the night's one mid-night change lands on its hour.
func _weather_change(hour24: int) -> void:
	var e: Dictionary = Weather.tonight
	if e.is_empty() or not _plan_active() or int(e.change_hour) != hour24:
		return
	Weather.set_level(int(e.change_to))
	var line := WeatherPlan.change_line(e)
	if line != "" and radio != null:
		radio.announce(line)

## Hour bands (living world step 2, night_bands.gd): the clock sets how much
## of the Traffic slider is on the road and which lines Dave adds. Off in the
## benchmark (its traffic must match earlier runs) and, in tests, unless the
## test pins the start time with NEON_CLOCK (the test clock file is shared, so
## any other test would get whatever time the last one left behind).
func bands_on() -> bool:
	if Benchmark.requested():
		return false
	return not TestMode.active() or OS.get_environment("NEON_CLOCK") != ""

func _update_bands() -> void:
	if not _bands:
		return
	var m := night_clock.minutes
	world_mood.update(m)
	var crackdown := world_mood.crackdown_until >= 0.0
	traffic.active_share = minf(NightBands.traffic_share(m) + WorldMood.traffic_bonus(m), 1.0) * Weather.traffic_factor()
	traffic.rule_breaker_share = WorldMood.rule_breaker_share(m, world_mood.meet_night, crackdown)
	traffic.weave_share = WorldMood.weave_share(m, crackdown)
	radio.band = NightBands.band_of(m)

## Tonight's events (world_mood.gd): Dave mentions a meet or a crackdown as it
## starts, and in a crackdown everyone already on the road starts behaving.
func _on_event(e: int) -> void:
	if e == WorldMood.Event.CRACKDOWN:
		traffic.reform_all()
	if WorldMood.EVENT_LINES.has(e):
		radio.announce(WorldMood.EVENT_LINES[e])

func _process(delta: float) -> void:
	_update_bands()
	var pz := RoadFrame.unroll(player.position).z
	Junction.focus_z = pz
	_update_chunk_pool(pz)
	# eyes in the headlights (world step 6, A1): one angle check per animal
	# on the chunks round the car
	StreetAnimals.step(chunk_pool, player, delta)
