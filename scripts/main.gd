extends Node3D

# Neon Overdrive - Godot port of the Three.js browser prototype.
# Ported directly: variable-lane road generation, section/taper math, traffic
# spawn logic, gear/RPM tach, chase camera.
# Simplified for tonight's build (not ported): the detailed chrome/spoiler car
# model (see car_builder.gd), the police pursuit car, and the mesh-damage system
# -- none of those were wired into player-visible gameplay in the source yet either.

# CarBuilder is available globally via its `class_name` in car_builder.gd.

# ---------- tuning ----------
const LANE_W := 2.3
const SECTION_LEN := 100.0
const TRANSITION_LEN := 18.0
const ROAD_ROWS := 30
const ROAD_DEPTH := 150.0
const ROW_STEP := ROAD_DEPTH / float(ROAD_ROWS)

const SPEED_MIN := 3.0
const SPEED_MAX := 26.0
const ACCEL := 9.0
const BRAKE_RATE := 15.0
const COAST_DRAG := 3.0

const GEAR_TOP_SPEED := [7.0, 12.0, 17.5, 22.0, 26.0] # top speed reachable in each gear (1-5)
const RPM_MIN := 900.0
const RPM_MAX := 7200.0

const STEER_RATE := 6.0 # m/s of lateral speed at full lock

const DASH_SPACING := 4.0
const DASH_COUNT_PER_LINE := 24
const DASH_RUN := DASH_SPACING * DASH_COUNT_PER_LINE

const BARRIER_SEG_LEN := 10.0
const BARRIER_SEG_COUNT := 17 # ceil((ROAD_DEPTH + 20) / BARRIER_SEG_LEN), hardcoded to keep this a valid const

const BUILDING_SPAN := 340.0
const BUILDING_COUNT_PER_SIDE := 40

const TRAFFIC_KINDS := ["coupe", "coupe", "coupe", "coupe", "sedan", "sedan", "sedan", "van", "van"]
const TRAFFIC_COLORS := [Color(1, 0.18, 0.53), Color(1, 0.72, 0), Color(0.54, 0.36, 1), Color(0.18, 0.88, 0.63)]
const ONCOMING_COLOR := Color(1, 0.23, 0.23)

# ---------- runtime state ----------
var speed := 12.0
var distance := 0.0
var player_x := 0.0
var gear := 1
var rpm := RPM_MIN
var shift_flash_t := 0.0

var crashed := false
var crash_timer := 0.0
var msg_timer := 0.0

var section_cache := {"-1": {"own_lanes": 3, "onc_lanes": 2, "barrier": false}}
var current_cfg := {"own_lanes": 3, "onc_lanes": 2, "barrier": false}

var own_mesh: MeshInstance3D
var onc_mesh: MeshInstance3D
var shoulder_l_mesh: MeshInstance3D
var shoulder_r_mesh: MeshInstance3D
var rail_l_mesh: MeshInstance3D
var rail_r_mesh: MeshInstance3D

var dash_pool: Array = [] # {node, side, frac}  side: "center" | "own" | "onc"
var barrier_pool: Array = [] # MeshInstance3D, index i
var building_pool: Array = [] # {node, side}

var player: Node3D
var traffic_pool: Array = [] # {node, active, x, z, oncoming, speed_mult, half_w, half_l}

var camera: Camera3D
const CAM_DIST := 6.0
const CAM_HEIGHT := 3.2
const CAM_FOV := 62.0

var spawn_timer := 1.2

# ---------- HUD ----------
var lbl_gear: Label
var lbl_rpm: Label
var lbl_dist: Label
var lbl_section: Label
var lbl_msg: Label
var tach_bg: ColorRect
var tach_fill: ColorRect
var flash_rect: ColorRect

func _ready() -> void:
	randomize()
	_setup_world()
	_setup_road_meshes()
	_setup_dash_pool()
	_setup_barrier_pool()
	_setup_building_pool()
	_setup_player()
	_setup_traffic_pool()
	_setup_camera()
	_setup_hud()

# ---------- world ----------
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

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(60, 120, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.56, 0.7, 1.0)
	add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.04, 0.024, 0.078)
	ground.material_override = gmat
	ground.position = Vector3(0, -0.05, -150)
	add_child(ground)

# ---------- section / taper math (ported from widthsAheadOf / sectionAt) ----------
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

func _widths_ahead_of(total_dist: float) -> Dictionary:
	var idx := int(floor(total_dist / SECTION_LEN))
	var pos_in_section := total_dist - idx * SECTION_LEN
	var cfg := _section_at(idx)
	var own: float = float(cfg.own_lanes) * LANE_W
	var onc: float = float(cfg.onc_lanes) * LANE_W
	var window_start := SECTION_LEN - TRANSITION_LEN
	if pos_in_section <= window_start:
		return {"own": own, "onc": onc, "barrier": cfg.barrier}
	var nxt := _section_at(idx + 1)
	var n_own: float = float(nxt.own_lanes) * LANE_W
	var n_onc: float = float(nxt.onc_lanes) * LANE_W
	var t := (pos_in_section - window_start) / TRANSITION_LEN
	t = t * t * (3.0 - 2.0 * t)
	return {"own": lerp(own, n_own, t), "onc": lerp(onc, n_onc, t), "barrier": cfg.barrier}

func _width_at_z(z: float) -> Dictionary:
	return _widths_ahead_of(distance - z)

# ---------- road strip meshes ----------
func _make_strip_mesh() -> ArrayMesh:
	return ArrayMesh.new()

func _update_strip(mi: MeshInstance3D, y: float, left_fn: Callable, right_fn: Callable) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for r in range(ROAD_ROWS + 1):
		var z := -float(r) * ROW_STEP
		verts.append(Vector3(left_fn.call(z), y, z))
		verts.append(Vector3(right_fn.call(z), y, z))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for r in range(ROAD_ROWS):
		var a := r * 2
		var b := r * 2 + 1
		var c := (r + 1) * 2
		var d := (r + 1) * 2 + 1
		indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = am

func _flat_mat(color: Color, emissive: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	return m

func _setup_road_meshes() -> void:
	own_mesh = MeshInstance3D.new()
	own_mesh.material_override = _flat_mat(Color(0.047, 0.067, 0.125))
	add_child(own_mesh)
	onc_mesh = MeshInstance3D.new()
	onc_mesh.material_override = _flat_mat(Color(0.07, 0.047, 0.094))
	add_child(onc_mesh)
	shoulder_l_mesh = MeshInstance3D.new()
	shoulder_l_mesh.material_override = _flat_mat(Color(0.11, 0.016, 0.086))
	add_child(shoulder_l_mesh)
	shoulder_r_mesh = MeshInstance3D.new()
	shoulder_r_mesh.material_override = _flat_mat(Color(0.11, 0.016, 0.086))
	add_child(shoulder_r_mesh)
	rail_l_mesh = MeshInstance3D.new()
	rail_l_mesh.material_override = _flat_mat(Color(0, 0.96, 1), true, 1.4)
	add_child(rail_l_mesh)
	rail_r_mesh = MeshInstance3D.new()
	rail_r_mesh.material_override = _flat_mat(Color(0, 0.96, 1), true, 1.4)
	add_child(rail_r_mesh)

func _update_road_geometry() -> void:
	_update_strip(own_mesh, 0.0, Callable(self, "_zero"), func(z): return _width_at_z(z).own)
	_update_strip(onc_mesh, 0.0, func(z): return -_width_at_z(z).onc, Callable(self, "_zero"))
	_update_strip(shoulder_l_mesh, -0.01, func(z): return -_width_at_z(z).onc - 20.0, func(z): return -_width_at_z(z).onc)
	_update_strip(shoulder_r_mesh, -0.01, func(z): return _width_at_z(z).own, func(z): return _width_at_z(z).own + 20.0)
	_update_strip(rail_l_mesh, 0.2, func(z): return -_width_at_z(z).onc - 0.06, func(z): return -_width_at_z(z).onc + 0.06)
	_update_strip(rail_r_mesh, 0.2, func(z): return _width_at_z(z).own - 0.06, func(z): return _width_at_z(z).own + 0.06)

	for d in dash_pool:
		var w = _width_at_z(d.node.position.z)
		if d.side == "own":
			d.node.position.x = d.frac * w.own
		elif d.side == "onc":
			d.node.position.x = -d.frac * w.onc

func _zero(_z: float) -> float:
	return 0.0

# ---------- lane dashes ----------
func _setup_dash_pool() -> void:
	var center_mat := _flat_mat(Color(1, 0.72, 0))
	var dash_mat := _flat_mat(Color(0, 0.9, 0.94))
	for n in range(DASH_COUNT_PER_LINE):
		var node := CarBuilder._box(Vector3(0.14, 0.05, 1.6), center_mat)
		node.position = Vector3(0, 0.01, -float(n) * DASH_SPACING)
		add_child(node)
		dash_pool.append({"node": node, "side": "center", "frac": 0.0})
	# own-lane dividers (up to 3 interior lines for 4 lanes)
	for i in range(1, 4):
		var frac := float(i) / 4.0
		for n in range(DASH_COUNT_PER_LINE):
			var node := CarBuilder._box(Vector3(0.12, 0.05, 1.6), dash_mat)
			node.position = Vector3(0, 0.01, -float(n) * DASH_SPACING)
			node.visible = false
			add_child(node)
			dash_pool.append({"node": node, "side": "own", "frac": frac, "lane_idx": i})
	for i in range(1, 3):
		var frac := float(i) / 2.0
		for n in range(DASH_COUNT_PER_LINE):
			var node := CarBuilder._box(Vector3(0.12, 0.05, 1.6), dash_mat)
			node.position = Vector3(0, 0.01, -float(n) * DASH_SPACING)
			node.visible = false
			add_child(node)
			dash_pool.append({"node": node, "side": "onc", "frac": frac, "lane_idx": i})

func _update_dash_visibility() -> void:
	for d in dash_pool:
		if d.side == "own":
			d.node.visible = d.lane_idx < current_cfg.own_lanes
		elif d.side == "onc":
			d.node.visible = d.lane_idx < current_cfg.onc_lanes and not current_cfg.barrier
		elif d.side == "center":
			d.node.visible = not current_cfg.barrier

func _scroll_dashes(delta: float) -> void:
	for d in dash_pool:
		d.node.position.z += speed * delta
		if d.node.position.z > 4.0:
			d.node.position.z -= DASH_RUN

# ---------- barrier segments (fixed grid, visibility driven by distance-ahead lookup) ----------
func _setup_barrier_pool() -> void:
	var bmat := _flat_mat(Color(1, 0.72, 0))
	for i in range(BARRIER_SEG_COUNT):
		var seg := CarBuilder._box(Vector3(0.2, 0.65, BARRIER_SEG_LEN + 0.6), bmat)
		seg.visible = false
		var z_mid := -float(i) * BARRIER_SEG_LEN - BARRIER_SEG_LEN / 2.0
		seg.position = Vector3(0, 0.32, z_mid)
		add_child(seg)
		barrier_pool.append(seg)

func _update_barrier() -> void:
	for i in range(barrier_pool.size()):
		var seg: MeshInstance3D = barrier_pool[i]
		var z_mid := seg.position.z
		var ahead_dist := distance - z_mid
		var cfg := _section_at(int(floor(ahead_dist / SECTION_LEN)))
		seg.visible = cfg.barrier

# ---------- skyline ----------
func _setup_building_pool() -> void:
	var mats := [_flat_mat(Color(0.078, 0.039, 0.141)), _flat_mat(Color(0.11, 0.059, 0.19))]
	var neon_mat := _flat_mat(Color(1, 0.18, 0.53), true, 1.6)
	for side in [-1, 1]:
		for i in range(BUILDING_COUNT_PER_SIDE):
			var w := 3.0 + randf() * 5.0
			var h := 6.0 + randf() * 24.0
			var d := 3.0 + randf() * 5.0
			var b := CarBuilder._box(Vector3(w, h, d), mats[i % 2])
			var x_base := float(side) * (26.0 + randf() * 46.0)
			var z := -randf() * BUILDING_SPAN
			b.position = Vector3(x_base, h / 2.0 - 0.3, z)
			add_child(b)
			var entry := {"node": b, "x_base": x_base}
			if randf() < 0.25:
				var stripe := CarBuilder._box(Vector3(0.15, h * 0.75, 0.15), neon_mat)
				stripe.position = Vector3(x_base + sign(x_base) * (w / 2.0 + 0.05), h / 2.0 - 0.3, z)
				add_child(stripe)
				entry["stripe"] = stripe
			building_pool.append(entry)

func _update_skyline(delta: float) -> void:
	var dz := speed * delta * 0.7
	for b in building_pool:
		b.node.position.z += dz
		if b.has("stripe"):
			b.stripe.position.z += dz
		if b.node.position.z > 20.0:
			b.node.position.z -= BUILDING_SPAN
			if b.has("stripe"):
				b.stripe.position.z = b.node.position.z

# ---------- player + traffic ----------
func _setup_player() -> void:
	player = CarBuilder.build_car("coupe", Color(0, 0.96, 1))
	player.position = Vector3(0, 0, 0)
	add_child(player)

func _setup_traffic_pool() -> void:
	for i in range(TRAFFIC_KINDS.size()):
		var kind: String = TRAFFIC_KINDS[i]
		var color: Color = TRAFFIC_COLORS[i % TRAFFIC_COLORS.size()]
		var car := CarBuilder.build_car(kind, color)
		car.visible = false
		add_child(car)
		traffic_pool.append({
			"node": car, "active": false, "x": 0.0, "z": 0.0, "oncoming": false,
			"speed_mult": 1.0, "base_color": color,
			"half_w": car.get_meta("half_w"), "half_l": car.get_meta("half_l"),
		})

func _spawn_wave(far_z: float) -> void:
	var own_lanes: int = current_cfg.own_lanes
	var onc_lanes: int = current_cfg.onc_lanes
	var total_lanes := own_lanes + onc_lanes
	var barrier_up: bool = current_cfg.barrier

	var reachable: Array = []
	for i in range(total_lanes):
		if i < onc_lanes and barrier_up:
			continue
		reachable.append(i)
	if reachable.is_empty():
		return
	var open_count := 2 if randf() < 0.6 else 1
	reachable.shuffle()
	var open_set := {}
	for i in range(min(open_count, reachable.size() - 1)):
		open_set[reachable[i]] = true

	for i in range(total_lanes):
		var oncoming := i < onc_lanes
		var behind_barrier := oncoming and barrier_up
		if not behind_barrier and open_set.has(i):
			continue
		if behind_barrier and randf() < 0.35:
			continue
		var free = null
		for o in traffic_pool:
			if not o.active:
				free = o
				break
		if free == null:
			continue
		var x: float
		if oncoming:
			x = -(float(onc_lanes - i) - 0.5) * LANE_W
		else:
			x = (float(i - onc_lanes) + 0.5) * LANE_W
		free.active = true
		free.oncoming = oncoming
		free.speed_mult = (1.3 + randf() * 0.5) if oncoming else ((0.5 + randf() * 0.3) if randf() < 0.5 else (1.2 + randf() * 0.4))
		free.x = x
		free.z = far_z
		free.node.visible = true
		free.node.position = Vector3(x, 0, far_z)
		free.node.rotation.y = PI if oncoming else 0.0
		CarBuilder.recolor(free.node, ONCOMING_COLOR if oncoming else free.base_color)

func _update_traffic(delta: float) -> void:
	for t in traffic_pool:
		if not t.active:
			continue
		var z_delta: float
		if t.oncoming:
			z_delta = (speed + speed * t.speed_mult) * delta
		else:
			z_delta = (speed - speed * t.speed_mult) * delta
		t.z += z_delta
		t.node.position.z = t.z
		if t.z > 6.0 or t.z < -(ROAD_DEPTH + 30.0):
			t.active = false
			t.node.visible = false
			continue
		if not crashed and abs(t.z) < (t.half_l + 1.05):
			var overlap: bool = abs(t.x - player_x) < (t.half_w + 0.85)
			if overlap:
				_trigger_crash()

func _trigger_crash() -> void:
	crashed = true
	crash_timer = 1.0
	msg_timer = 1.0
	speed = max(SPEED_MIN, speed * 0.4)

# ---------- camera ----------
func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	camera.far = 400.0
	add_child(camera)
	camera.current = true

func _update_camera() -> void:
	camera.global_position = Vector3(player_x, CAM_HEIGHT, CAM_DIST)
	camera.look_at(Vector3(player_x, 1.1, -10.0), Vector3.UP)

# ---------- HUD ----------
func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)

	var font_color := Color(0, 0.96, 1)

	lbl_section = Label.new()
	lbl_section.position = Vector2(16, 12)
	lbl_section.add_theme_color_override("font_color", Color(1, 0.72, 0))
	hud.add_child(lbl_section)

	lbl_dist = Label.new()
	lbl_dist.position = Vector2(16, 34)
	lbl_dist.add_theme_color_override("font_color", font_color)
	hud.add_child(lbl_dist)

	lbl_gear = Label.new()
	lbl_gear.position = Vector2(16, 56)
	lbl_gear.add_theme_color_override("font_color", font_color)
	hud.add_child(lbl_gear)

	lbl_rpm = Label.new()
	lbl_rpm.position = Vector2(16, 78)
	lbl_rpm.add_theme_color_override("font_color", font_color)
	hud.add_child(lbl_rpm)

	tach_bg = ColorRect.new()
	tach_bg.position = Vector2(16, 104)
	tach_bg.size = Vector2(160, 12)
	tach_bg.color = Color(1, 1, 1, 0.12)
	hud.add_child(tach_bg)

	tach_fill = ColorRect.new()
	tach_fill.position = Vector2(16, 104)
	tach_fill.size = Vector2(0, 12)
	tach_fill.color = font_color
	hud.add_child(tach_fill)

	lbl_msg = Label.new()
	lbl_msg.position = Vector2(0, 260)
	lbl_msg.size = Vector2(900, 60)
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_color_override("font_color", Color(1, 0.18, 0.53))
	lbl_msg.add_theme_font_size_override("font_size", 28)
	lbl_msg.text = "CRASH"
	lbl_msg.visible = false
	hud.add_child(lbl_msg)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 0.17, 0.3, 0.0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash_rect)

	var controls := Label.new()
	controls.position = Vector2(16, 400)
	controls.add_theme_color_override("font_color", Color(0.71, 0.65, 0.84))
	controls.text = "A/D or ←/→ steer  ·  W/S or ↑/↓ throttle/brake  ·  Q/E shift down/up"
	hud.add_child(controls)

func _update_hud() -> void:
	lbl_section.text = "%d+%d lanes%s" % [current_cfg.own_lanes, current_cfg.onc_lanes, " • BARRIER" if current_cfg.barrier else ""]
	lbl_dist.text = "DIST %dm" % int(distance)
	lbl_gear.text = "GEAR %d" % gear
	lbl_rpm.text = "%d RPM" % int(rpm)

	var rpm_frac: float = clamp((rpm - RPM_MIN) / (RPM_MAX - RPM_MIN), 0.0, 1.0)
	tach_fill.size.x = 160.0 * rpm_frac
	if rpm_frac > 0.92:
		tach_fill.color = Color(1, 0.18, 0.53)
	elif rpm_frac > 0.75:
		tach_fill.color = Color(1, 0.72, 0)
	else:
		tach_fill.color = Color(0, 0.96, 1)

	if msg_timer > 0.0:
		lbl_msg.visible = true
		flash_rect.color.a = clamp(msg_timer, 0.0, 1.0) * 0.7
	else:
		lbl_msg.visible = false
		flash_rect.color.a = 0.0

# ---------- input / driving ----------
func _handle_input(delta: float) -> void:
	var steer := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer += 1.0
	var speed_frac: float = clamp(speed / SPEED_MAX, 0.35, 1.0)
	player_x += steer * STEER_RATE * speed_frac * delta
	var max_x: float = current_cfg.own_lanes * LANE_W - 0.6
	var min_x: float = -(current_cfg.onc_lanes * LANE_W - 0.6)
	player_x = clamp(player_x, min_x, max_x)
	player.position.x = player_x
	player.rotation.y = -steer * 0.12

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		speed += ACCEL * delta
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		speed -= BRAKE_RATE * delta
	else:
		speed -= COAST_DRAG * delta
	speed = clamp(speed, SPEED_MIN, SPEED_MAX)

func _update_drivetrain(_delta: float) -> void:
	var top: float = GEAR_TOP_SPEED[gear - 1]
	var frac: float = clamp(speed / top, 0.0, 1.15)
	rpm = RPM_MIN + frac * (RPM_MAX - RPM_MIN)

func _process(delta: float) -> void:
	if crash_timer > 0.0:
		crash_timer -= delta
		if crash_timer <= 0.0:
			crashed = false
	if msg_timer > 0.0:
		msg_timer -= delta

	_handle_input(delta)
	_update_drivetrain(delta)

	distance += speed * delta
	var idx := int(floor(distance / SECTION_LEN))
	current_cfg = _section_at(idx)

	_update_road_geometry()
	_update_dash_visibility()
	_scroll_dashes(delta)
	_update_barrier()
	_update_skyline(delta)

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_wave(-ROAD_DEPTH - 10.0)
		spawn_timer = clamp(2.2 - speed * 0.04, 0.55, 2.2)

	_update_traffic(delta)
	_update_camera()
	_update_hud()

func _unhandled_input(_event: InputEvent) -> void:
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			gear = max(1, gear - 1)
			shift_flash_t = 0.2
		elif event.keycode == KEY_E:
			gear = min(GEAR_TOP_SPEED.size(), gear + 1)
			shift_flash_t = 0.2
