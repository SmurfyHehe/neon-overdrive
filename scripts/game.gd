extends Node3D

# Neon Overdrive -- world-space rebuild.
# Milestone 1 (road-chunk foundation) + milestone 2 (real player physics,
# NOW a vendored raycast Vehicle/Wheel controller -- see player.gd header for
# why VehicleBody3D was replaced) per ROADMAP.md. Old scripts/main.gd is
# abandoned, not reused. car_builder.gd IS reused (pure mesh construction).
# This script owns the world (chunks, ground collision, camera)
# and the player instance.

const CHUNKS_AHEAD := 6
const CHUNKS_BEHIND := 1
const POOL_SIZE := CHUNKS_AHEAD + CHUNKS_BEHIND + 1

# Stage B step 3 (2026-10-05): a highway with 4 lanes per direction (ROADMAP
# stage B: "4 lanes per direction is now the spec"; stage A had capped it at 3
# our way, 2 oncoming, varying per chunk). Lane counts no longer change from
# chunk to chunk: lane-follow traffic holds one lane centre and never changes
# lane (milestone 3), so a lane that narrowed away would strand its cars. The
# builder's taper code and the per-chunk centre barrier are unchanged.
const OWN_LANES := 4
const ONC_LANES := 4

# RoadChunkBuilder, CarBuilder, PlayerCar, TrafficManager are all global via class_name.

var section_cache: Dictionary = {"-1": {"own_lanes": OWN_LANES, "onc_lanes": ONC_LANES, "barrier": false}}
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
var game_state: GameState

# Chase camera, its three smoothing modes (#31, C to cycle) and the stage A
# speed feel (FOV, dolly, shake) all live in chase_camera.gd.
var camera: ChaseCamera
var radio: RadioManager
var fx: FxPack  # effects pack v1: vignette, speed lines, skid marks, exhaust flames (fx_pack.gd)

func _ready() -> void:
	# Auto-Tune worker mode (exported game): no world, just the search.
	var worker_dir := AutoTuneJob.worker_dir_from_args()
	if worker_dir != "":
		set_process(false)
		set_physics_process(false)
		AutoTuneJob.run_worker(get_tree(), worker_dir)
		return
	AudioSettings.load_settings()
	TrafficSettings.load_settings()
	FxSettings.load_settings()   # cockpit mirrors on/off and quality ([fx] in settings.cfg)
	# NEON_TRAFFIC=<n> overrides the saved car count, like NEON_TICKS/NEON_MUTE:
	# tests/run_tests.bat sets 0 so the older drive-bot tests, which steer
	# across lanes blind, do not hit traffic (tests/traffic_*.gd clear it).
	var traffic_env := OS.get_environment("NEON_TRAFFIC")
	if traffic_env.is_valid_int():
		TrafficSettings.set_car_count(int(traffic_env))
	if OS.get_environment("NEON_MUTE") == "1":
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	# Benchmark mode (-- --benchmark, see benchmark.gd) drives a fixed road so
	# runs are comparable; normal play gets a fresh one each time.
	var benchmark := Benchmark.requested()
	if benchmark:
		seed(Benchmark.SEED)
	else:
		randomize()
	_setup_world()
	_setup_ground_collision()
	_setup_chunk_pool()
	_setup_player()
	_setup_traffic()
	_setup_camera()
	fx = FxPack.new(player, camera)
	add_child(fx)
	_setup_hud()
	_setup_game_state()
	if benchmark:
		add_child(Benchmark.new())

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
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.008, 0.01, 0.018)
	sky_mat.sky_horizon_color = Color(0.17, 0.095, 0.05)
	sky_mat.ground_bottom_color = Color(0.008, 0.008, 0.01)
	sky_mat.ground_horizon_color = Color(0.11, 0.065, 0.04)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.066, 0.042)
	env.fog_density = 0.009
	# NIGHT LIGHTING PASS (2026-09-29, RESEARCH-cheap-pretty.md item 1): the
	# gradient sky is also the ambient source (Godot's default under BG_SKY),
	# so its horizon glow fills the scene for free -- no extra light needed.
	# Dialled down from the default 1.0 because at full energy a bright horizon
	# lifts the near-black asphalt back toward grey and flattens the emissive
	# markings it is supposed to sit behind.
	env.ambient_light_energy = 0.3
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

	# NIGHT LIGHTING PASS (2026-09-29, RESEARCH-cheap-pretty.md item 1): this
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
	# BUG FIX (2026-10-06, tests/recenter_kick.gd): now an infinite plane. At
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

# ---------- section math (reused from old main.gd, keyed by chunk index instead of distance) ----------
func _section_at(idx: int) -> Dictionary:
	var key := str(idx)
	if section_cache.has(key):
		return section_cache[key]
	# Fixed lane counts since stage B step 3 (see OWN_LANES); only the centre
	# barrier still rolls per chunk.
	var barrier := randf() < 0.3
	var cfg := {"own_lanes": OWN_LANES, "onc_lanes": ONC_LANES, "barrier": barrier}
	section_cache[key] = cfg
	return cfg

# ---------- chunk pool ----------
func _setup_chunk_pool() -> void:
	for i in range(POOL_SIZE):
		var idx := i - CHUNKS_BEHIND
		var prev_cfg := _section_at(idx - 1)
		var cfg := _section_at(idx)
		var root := RoadChunkBuilder.build_chunk(idx, prev_cfg, cfg, origin_index)
		add_child(root)
		chunk_pool.append({"root": root, "index": idx})

func _update_chunk_pool(ref_z: float) -> void:
	var current_idx := int(floor(-ref_z / RoadChunkBuilder.CHUNK_LEN)) + origin_index
	var max_idx := current_idx
	for c in chunk_pool:
		max_idx = max(max_idx, c.index)
	for c in chunk_pool:
		if c.index < current_idx - CHUNKS_BEHIND:
			max_idx += 1
			var prev_cfg := _section_at(max_idx - 1)
			var cfg := _section_at(max_idx)
			RoadChunkBuilder.rebuild_chunk(c.root, max_idx, prev_cfg, cfg, origin_index)
			# Physics interpolation is on (ISSUES B7): without this reset the
			# recycled chunk would slide from its old spot to the new one
			# over a frame instead of jumping there.
			c.root.reset_physics_interpolation()
			c.index = max_idx

# ---------- floating origin (issue #26) ----------
func _physics_process(_delta: float) -> void:
	# Runs before the car's own _physics_process (parent before child), so
	# GEVP computes this step's velocity from positions that are already
	# shifted consistently.
	var z := player.global_position.z
	if absf(z) >= recenter_dist:
		_shift_origin(int(floor(-z / RoadChunkBuilder.CHUNK_LEN)))
	if Input.is_action_just_pressed("mute"):
		toggle_mute()
	if Input.is_action_just_pressed("radio_next") and radio != null:
		radio.next_station()

## Moves the world back by shift_chunks whole chunks (positive = the car had
## driven forward, -z). Whole chunks keep chunk positions exact integers x 50.
func _shift_origin(shift_chunks: int) -> void:
	if shift_chunks == 0:
		return
	origin_index += shift_chunks
	recenter_count += 1
	var offset := Vector3(0.0, 0.0, float(shift_chunks) * RoadChunkBuilder.CHUNK_LEN)

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

	for c in chunk_pool:
		# Re-derived from the index, not +=, so error can never accumulate.
		c.root.position = Vector3(0, 0, -float(c.index - origin_index) * RoadChunkBuilder.CHUNK_LEN)
		c.root.reset_physics_interpolation()
	# Traffic (milestone 3): every car gets the same bookkeeping as the player.
	traffic.shift_world(offset)
	fx.shift_world(offset)  # skid marks are laid in world space
	# The ground plane stays put: it is infinite.
	# The camera follows the car's interpolated position in _process, so it
	# needs nothing here.

# ---------- player ----------
## Where the player starts: in a lane, not on the centre line (x=0) as before
## stage B step 3, now that the oncoming lanes carry traffic. Lane 1 of 4.
const PLAYER_SPAWN_LANE := 1

func _setup_player() -> void:
	player = PlayerCar.new()
	player.position = Vector3(TrafficManager.lane_centre(PLAYER_SPAWN_LANE, false), 0.0, 0)
	add_child(player)

# ---------- traffic (milestone 3, stage B step 3) ----------
# Lane-follow traffic: the same raycast Vehicle as the player, see
# traffic_car.gd / traffic_manager.gd. Count and draw distance come from the
# pause menu's Traffic sliders (TrafficSettings). Added after the player, so
# its cars' _physics_process runs after the player's.
func _setup_traffic() -> void:
	traffic = TrafficManager.new()
	traffic.player = player
	traffic.own_lanes = OWN_LANES
	traffic.onc_lanes = ONC_LANES
	traffic.car_count = TrafficSettings.car_count
	traffic.detail_distance = TrafficSettings.detail_distance
	add_child(traffic)

# ---------- camera ----------
func _setup_camera() -> void:
	camera = ChaseCamera.new(player)
	add_child(camera)

## M mutes all game audio (master bus). Setting NEON_MUTE=1 starts muted, for
## test runs and late-night testing.
func toggle_mute() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, not AudioServer.is_bus_mute(bus))

# ---------- HUD (scripts/hud.gd) ----------
func _setup_hud() -> void:
	add_child(Hud.new(player, camera, traffic))

# ---------- game state (pause / restart / quit, issue #27) ----------
func _setup_game_state() -> void:
	game_state = GameState.new()
	add_child(game_state)
	add_child(PauseMenu.new(game_state))
	add_child(TunerScreen.new(player, game_state))
	add_child(WarningLights.new(player))
	radio = RadioManager.new()
	add_child(radio)

func _process(_delta: float) -> void:
	_update_chunk_pool(player.position.z)
