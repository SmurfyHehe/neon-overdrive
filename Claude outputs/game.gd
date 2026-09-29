extends Node3D

# Neon Overdrive -- world-space rebuild.
# Milestone 1 (road-chunk foundation) + milestone 2 (real VehicleBody3D
# player physics) per ROADMAP.md. Old scripts/main.gd is abandoned, not
# reused. car_builder.gd IS reused (pure mesh construction).
#
# Milestone 2 replaced the milestone-1 kinematic test rig entirely with
# scripts/player.gd (a real VehicleBody3D, real wheels, real suspension --
# see that file's header for why). This script now just owns the world
# (chunks, ground collision, camera, debug HUD) and the player instance.

const LANE_W := 2.3
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
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.004, 0.047)
	env.fog_enabled = true
	env.fog_light_color = Color(0.11, 0.05, 0.23)
	env.fog_density = 0.012
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.95, 0.86)
	add_child(sun)

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
		var cfg := _section_at(idx)
		var root := RoadChunkBuilder.build_chunk(idx, cfg)
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
			var cfg := _section_at(max_idx)
			RoadChunkBuilder.rebuild_chunk(c.root, max_idx, cfg)
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
	add_child(camera)
	camera.current = true

func _update_camera() -> void:
	var p := player.position
	camera.global_position = Vector3(p.x, p.y + CAM_HEIGHT, p.z + CAM_DIST)
	camera.look_at(Vector3(p.x, p.y + 1.1, p.z - 10.0), Vector3.UP)

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
	var controls := Label.new()
	controls.position = Vector2(16, 400)
	controls.add_theme_color_override("font_color", Color(0.71, 0.65, 0.84))
	controls.text = "A/D steer  ·  W/S throttle/brake  ·  Q/E shift down/up (R-N-1-2-3-4-5)"
	hud.add_child(controls)

func _update_debug_hud() -> void:
	var gear_name := "R" if player.gear == -1 else ("N" if player.gear == 0 else str(player.gear))
	lbl_gear.text = "GEAR %s" % gear_name
	lbl_speed.text = "%d units/s" % int(player.current_speed())

func _process(_delta: float) -> void:
	_update_chunk_pool(player.position.z)
	_update_camera()
	_update_debug_hud()
