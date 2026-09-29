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

var player: PlayerCar

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
	randomize()
	_setup_world()
	_setup_ground_collision()
	_setup_chunk_pool()
	_setup_player()
	_setup_camera()
	_setup_debug_hud()

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
	box.size = Vector3(200.0, 2.0, 200000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, -100000.0 + RoadChunkBuilder.CHUNK_LEN)
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
		var root := RoadChunkBuilder.build_chunk(idx, prev_cfg, cfg)
		add_child(root)
		chunk_pool.append({"root": root, "index": idx})

func _update_chunk_pool(ref_z: float) -> void:
	var current_idx := int(floor(-ref_z / RoadChunkBuilder.CHUNK_LEN))
	var max_idx := current_idx
	for c in chunk_pool:
		max_idx = max(max_idx, c.index)
	for c in chunk_pool:
		if c.index < current_idx - CHUNKS_BEHIND:
			max_idx += 1
			var prev_cfg := _section_at(max_idx - 1)
			var cfg := _section_at(max_idx)
			RoadChunkBuilder.rebuild_chunk(c.root, max_idx, prev_cfg, cfg)
			# Physics interpolation is on (ISSUES B7): without this reset the
			# recycled chunk would slide from its old spot to the new one
			# over a frame instead of jumping there.
			c.root.reset_physics_interpolation()
			c.index = max_idx

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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
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
	controls.text = "A/D steer  ·  W/S throttle/brake  ·  Space handbrake  ·  Q/E shift down/up (R-N-1-2-3-4-5)"
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

func _process(delta: float) -> void:
	_update_chunk_pool(player.position.z)
	_update_camera(delta)
	_update_debug_hud()
