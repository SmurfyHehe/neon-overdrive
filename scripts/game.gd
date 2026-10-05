extends Node3D

# Neon Overdrive -- world-space rebuild.
# Milestone 1 (road-chunk foundation) + milestone 2 (real player physics,
# NOW a vendored raycast Vehicle/Wheel controller -- see player.gd header for
# why VehicleBody3D was replaced) per ROADMAP.md. Old scripts/main.gd is
# abandoned, not reused. car_builder.gd IS reused (pure mesh construction).
# This script owns the world (chunks, ground collision, camera, debug HUD)
# and the player instance.

const CHUNKS_AHEAD := 6
const CHUNKS_BEHIND := 1
const POOL_SIZE := CHUNKS_AHEAD + CHUNKS_BEHIND + 1

# RoadChunkBuilder, CarBuilder, PlayerCar are all global via class_name.

var section_cache: Dictionary = {"-1": {"own_lanes": 3, "onc_lanes": 2, "barrier": false}}
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
var game_state: GameState

var camera: Camera3D
const CAM_DIST := 6.0
const CAM_HEIGHT := 3.2
const CAM_FOV := 62.0
# Issue #31: C cycles camera modes in-game. Roy kept all three for now
# (2026-09-29) and will tune them later.
# 0 = hard snap (old), 1 = light smoothing, 2 = smoothing + eased reverse swing.
const CAM_MODE_NAMES := ["A: hard snap", "B: light smoothing", "C: smoothing + reverse swing"]
const CAM_FOLLOW_RATE := 6.0  # 1/s, how fast the camera catches up sideways/vertically
const CAM_SWING_RATE := 5.0   # 1/s, how fast it swings round for reverse (~0.6 s)
var cam_mode := 0
var cam_follow := Vector2.ZERO  # smoothed (x, y) the camera tracks
var cam_yaw := 0.0              # 0 = behind for forward, PI = mirrored for reverse
var cam_started := false
var lbl_cam: Label

var lbl_gear: Label
var lbl_speed: Label

func _ready() -> void:
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
	_setup_camera()
	_setup_debug_hud()
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
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.004, 0.08)
	sky_mat.sky_horizon_color = Color(0.35, 0.08, 0.55)
	sky_mat.ground_bottom_color = Color(0.02, 0.004, 0.047)
	sky_mat.ground_horizon_color = Color(0.25, 0.05, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_enabled = true
	env.fog_light_color = Color(0.11, 0.05, 0.23)
	env.fog_density = 0.006
	# NIGHT LIGHTING PASS (2026-09-29, RESEARCH-cheap-pretty.md item 1): the
	# gradient sky is also the ambient source (Godot's default under BG_SKY),
	# so its purple horizon fills the scene for free -- no extra light needed.
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
	var box := BoxShape3D.new()
	# One big flat slab under the whole play area instead of per-chunk
	# collision -- the road is flat, so a single static shape is simplest
	# and cheapest. Revisit if/when terrain height ever varies.
	#
	# BUG FIX (2026-09-12): this slab used to run from z=-200000 to z=0,
	# which put its edge EXACTLY at the player's spawn point. The rear axle
	# (at local z=+1.05) sat past that edge over empty space from frame one
	# -- there's even a real visual road chunk back there (chunk index -1,
	# CHUNKS_BEHIND=1, spans z=0 to +CHUNK_LEN=50) that the ground never
	# covered. Only the front wheels ever found ground; the ungrounded rear
	# axle torqued the car into a slow backflip and off the map every time.
	# Shifting the slab forward by CHUNK_LEN covers that behind-chunk with
	# margin to spare.
	#
	# Floating origin (issue #26): the car never gets more than
	# recenter_dist from z=0 now, so the slab only has to cover that range
	# plus margin either way (ahead, and behind for reversing) -- it never
	# moves, and there is no far wall any more.
	var ahead := recenter_dist + 500.0
	var behind := recenter_dist + 100.0
	box.size = Vector3(200.0, 2.0, ahead + behind)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, (behind - ahead) / 2.0)
	body.add_child(shape)
	# Physics rewrite (2026-09-13): the vendored Wheel raycast identifies
	# surface type by the FIRST group on whatever collision body it hits
	# (see scripts/vendor/gevp/gevp_wheel.gd process_forces). This base slab
	# is the road+shoulder+curb surface, so it's tagged "Road" -- the raised
	# sidewalk collision added per-chunk in road_chunk_builder.gd sits
	# slightly higher and is tagged "Dirt", so a wheel over the sidewalk hits
	# that closer box first regardless of this slab extending underneath it.
	body.add_to_group("Road")
	add_child(body)

# ---------- section math (reused from old main.gd, keyed by chunk index instead of distance) ----------
func _section_at(idx: int) -> Dictionary:
	var key := str(idx)
	if section_cache.has(key):
		return section_cache[key]
	var prev: Dictionary = section_cache.get(str(idx - 1), {"own_lanes": 3, "onc_lanes": 2, "barrier": false})
	var own_roll := randf()
	var own_delta := 0
	if own_roll >= 0.55:
		own_delta = 1 if own_roll < 0.78 else -1
	var own_lanes: int = clampi(int(prev.own_lanes) + own_delta, 2, 4)
	var onc_roll := randf()
	var onc_delta := 0
	if onc_roll >= 0.7:
		onc_delta = 1 if onc_roll < 0.85 else -1
	var onc_lanes: int = clampi(int(prev.onc_lanes) + onc_delta, 1, 2)
	var barrier := randf() < 0.3
	var cfg := {"own_lanes": own_lanes, "onc_lanes": onc_lanes, "barrier": barrier}
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
	_poll_camera_input()

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
	# The ground slab stays put: it is centred on the origin by design.
	# The camera follows the car's interpolated position in _process, so it
	# needs nothing here.

# ---------- player ----------
func _setup_player() -> void:
	player = PlayerCar.new()
	player.position = Vector3(0, 0.0, 0)
	add_child(player)

# ---------- camera ----------
func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	camera.far = 400.0
	# Moved in _process every rendered frame, so it must not be
	# physics-interpolated itself (ISSUES B7).
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.current = true

func _update_camera(delta: float) -> void:
	# The interpolated position, not player.position: the car only moves on
	# the 60 Hz physics tick, and with vsync off the camera updates several
	# times per tick. Following the raw position made car and road judder.
	var p := player.get_global_transform_interpolated().origin
	# BUG FIX (2026-09-13): camera never rotated for reverse, so you couldn't
	# see what you were backing into. Reversing flips the chase cam to the
	# opposite side of the car looking the opposite way -- it still trails
	# "behind" relative to the current direction of travel, just mirrored.
	var reversing := player.gear == -1
	var target_yaw := PI if reversing else 0.0
	if cam_mode == 0 or not cam_started:
		cam_follow = Vector2(p.x, p.y)
		cam_yaw = target_yaw
		cam_started = true
	else:
		# Frame-rate independent ease: the same feel at 60 or 300 fps.
		var k := 1.0 - exp(-CAM_FOLLOW_RATE * delta)
		cam_follow = cam_follow.lerp(Vector2(p.x, p.y), k)
		if cam_mode == 2:
			cam_yaw = lerpf(cam_yaw, target_yaw, 1.0 - exp(-CAM_SWING_RATE * delta))
		else:
			cam_yaw = target_yaw
	# Distance along the road stays locked to the car, so speed never pulls
	# the camera further back; only sideways and height motion is smoothed.
	var fx := cam_follow.x
	var fy := cam_follow.y
	var back := Vector3(0, 0, CAM_DIST).rotated(Vector3.UP, cam_yaw)
	var ahead := Vector3(0, 0, -10.0).rotated(Vector3.UP, cam_yaw)
	camera.global_position = Vector3(fx + back.x, fy + CAM_HEIGHT, p.z + back.z)
	camera.look_at(Vector3(fx + ahead.x, fy + 1.1, p.z + ahead.z), Vector3.UP)

# Polled from _physics_process like all game input (#30), not an event handler.
func _poll_camera_input() -> void:
	if Input.is_action_just_pressed("camera_cycle"):
		cam_mode = (cam_mode + 1) % CAM_MODE_NAMES.size()

# ---------- temporary debug readout (real HUD is milestone 5) ----------
func _setup_debug_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var font_color := Color(0, 0.96, 1)
	lbl_gear = Label.new()
	lbl_gear.position = Vector2(16, 12)
	lbl_gear.add_theme_color_override("font_color", font_color)
	hud.add_child(lbl_gear)
	lbl_speed = Label.new()
	lbl_speed.position = Vector2(16, 34)
	lbl_speed.add_theme_color_override("font_color", font_color)
	hud.add_child(lbl_speed)
	lbl_cam = Label.new()
	lbl_cam.position = Vector2(16, 56)
	lbl_cam.add_theme_color_override("font_color", font_color)
	hud.add_child(lbl_cam)
	var controls := Label.new()
	controls.position = Vector2(16, 400)
	controls.add_theme_color_override("font_color", Color(0.71, 0.65, 0.84))
	controls.text = "A/D steer  ·  W/S throttle/brake  ·  Space handbrake  ·  Q/E shift down/up (R-N-1-2-3-4-5)  ·  Esc pause  ·  T tuning  ·  Y auto-tune"
	hud.add_child(controls)

func _update_debug_hud() -> void:
	var gear_name := "R" if player.gear == -1 else ("N" if player.gear == 0 else str(player.gear))
	lbl_gear.text = "GEAR %s" % gear_name
	lbl_speed.text = "%d units/s" % int(player.current_speed())
	lbl_cam.text = "CAMERA %s  (C to switch)" % CAM_MODE_NAMES[cam_mode]
	# BUG FIX (2026-09-13): shift_flash_t was tracked on the player since
	# milestone 2 but nothing ever read it -- shifting had zero feedback.
	# Wired it to actually punch the gear label (bright flash + scale pop)
	# for its ~0.2s window.
	if player.shift_flash_t > 0.0:
		lbl_gear.add_theme_color_override("font_color", Color(1, 1, 1))
		lbl_gear.scale = Vector2(1.3, 1.3)
	else:
		lbl_gear.add_theme_color_override("font_color", Color(0, 0.96, 1))
		lbl_gear.scale = Vector2(1.0, 1.0)

# ---------- game state (pause / restart / quit, issue #27) ----------
func _setup_game_state() -> void:
	game_state = GameState.new()
	add_child(game_state)
	add_child(PauseMenu.new(game_state))
	add_child(TuningPanel.new(player, game_state))
	add_child(AutoTunePanel.new(player, game_state))

func _process(delta: float) -> void:
	_update_chunk_pool(player.position.z)
	_update_camera(delta)
	_update_debug_hud()
