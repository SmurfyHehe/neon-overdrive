extends SceneTree

# Dash bobble head (interiors build step 10, 2026-10-11). Headless and silent:
# - the catalogue: every id builds, "none" builds nothing, an unknown id falls
#   back to none, every figure is under MAX_TRIS triangles, about 7 cm tall,
#   one mesh with one surface (one draw call), each with a name
# - the slot, for every player car: dash_pass sits on that car's dash top,
#   more than 20 degrees right of straight ahead from the driver's eye, inside
#   the dash, under the glass line, at least 8 degrees below eye level, and
#   well clear of the passenger door mirror's line of sight
# - the spring: cornering leans the head outward, braking pitches it forward,
#   a launch pins it back, it settles upright, it is capped, and the shader's
#   number pair follows
# - CabinMods saves and reloads the pick per car; an unknown id reads as none
# - in the real game (Game.tscn): the figure is built in the cockpit view and
#   not in the chase view; it stands on the dash under a ray from above; in
#   the car's own drive a launch moves the bob; frozen outside the cockpit
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/bobble_head.gd

const CFG := "user://bobble_head_test.cfg"
const MAX_TRIS := 600
const MIN_YAW_DEG := 20.0
const MIN_BELOW_EYE_DEG := 8.0
const MIN_MIRROR_SEP_DEG := 15.0
const DT := 1.0 / 120.0
const TIMEOUT_TICKS := 60 * 40

enum Step { BOOT, DRIVE, CHASE, DONE }

var failures: Array[String] = []
var step := Step.BOOT
var step_start := 0
var tick := 0
var throttle := 0.0
var bob_before := Vector2.ZERO
var tallest := 0.0   # the tallest figure in the catalogue (m), set by _catalogue

func _initialize() -> void:
	AudioSettings.path = CFG
	DirAccess.remove_absolute(CFG)
	_catalogue()
	_slots()
	_spring()
	_settings()
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CABIN_MODS", "bobble=pike")
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end() -> bool:
	DirAccess.remove_absolute(CFG)
	print("bobble_head: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return true

# ---------- no scene ----------

func _catalogue() -> void:
	_check(BobbleFigures.IDS[0] == BobbleFigures.NONE, "index 0 should be none")
	_check(BobbleFigures.IDS.size() >= 30, "want 29 figures plus none, got %d ids" % BobbleFigures.IDS.size())
	var b := BobbleHead.new(null, "p1_coupe")
	root.add_child(b)
	var biggest := 0
	for id in BobbleFigures.IDS:
		b.set_figure(id)
		if id == BobbleFigures.NONE:
			_check(not b.is_shown() and b.triangle_count() == 0, "none should draw nothing")
			continue
		_check(BobbleFigures.FIGURES.has(id) and BobbleFigures.name_of(id) != id, "%s needs a display name" % id)
		_check(b.is_shown() and b.triangle_count() > 100, "%s should build a figure, got %d tris" % [id, b.triangle_count()])
		_check(b.triangle_count() <= MAX_TRIS, "%s is %d tris, over the %d budget" % [id, b.triangle_count(), MAX_TRIS])
		var mi := b.mesh_instance()
		var mesh := mi.mesh as ArrayMesh if mi != null else null
		_check(mesh != null and mesh.get_surface_count() == 1, "%s should be one surface (one draw call)" % id)
		if mesh != null:
			var box := mesh.get_aabb()
			tallest = maxf(tallest, box.size.y)
			biggest = maxi(biggest, b.triangle_count())
			_check(box.size.y > 0.055 and box.size.y < 0.085, "%s should stand about 7 cm, is %.3f m" % [id, box.size.y])
			_check(box.size.x < 0.058 and box.size.z < 0.058, "%s footprint too wide: %s" % [id, box.size])
			var uv: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
			var heavy := 0
			for u in uv:
				if u.x > 0.99:
					heavy += 1
			_check(heavy >= 12, "%s needs a head that tilts (weighted vertices), got %d" % [id, heavy])
		_check(mi != null and mi.material_override is ShaderMaterial, "%s should use the bob shader" % id)
	b.set_figure("no-such-figure")
	_check(b.figure == BobbleFigures.NONE, "unknown id should fall back to none, got %s" % b.figure)
	print("bobble figures: %d ids, tallest %.1f cm, most triangles %d" % [BobbleFigures.IDS.size() - 1, tallest * 100.0, biggest])
	b.free()

func _slots() -> void:
	var kinds := ["p0_beater", "p1_coupe", "p2_hothatch", "p3_tuner", "p4_kei", "p5_muscle", "p6_crossover", "p10_truck"]
	for kind in kinds:
		var cab := CabinSpec.for_kind(kind)
		var spot := CabinSpots.dash_pass(kind)
		_check(CabinSpots.cabin(kind, "dash_pass").is_equal_approx(spot), "%s: cabin(dash_pass) should be dash_pass()" % kind)
		var eye: Vector3 = cab.eye
		var cowl: Vector2 = cab.cowl
		var cl: Vector2 = cab.cluster
		var face_z := float(cab.dash_face_z)
		var yaw := rad_to_deg(atan2(spot.x - eye.x, eye.z - spot.z))
		var scale := CabinSpots.dash_pass_scale(kind)
		_check(yaw > MIN_YAW_DEG, "%s: figure is %.1f deg right of straight ahead, needs more than %.0f" % [kind, yaw, MIN_YAW_DEG])
		# on the dash top: between the cowl and the driver's face, on the slope
		_check(spot.z > cowl.y and spot.z < face_z, "%s: z %.3f is off the dash (%.3f .. %.3f)" % [kind, spot.z, cowl.y, face_z])
		var dash_y := lerpf(cowl.x, cl.x, (spot.z - cowl.y) / (face_z - cowl.y))
		_check(absf(spot.y - dash_y) < 0.005, "%s: foot at y %.3f, dash top %.3f" % [kind, spot.y, dash_y])
		# the fit box: foot radius inside the dash both ways, head under the glass line
		var door_x := float(cab.door_x)
		var pillar_foot: Vector3 = cab.a_pillar[0]
		var dash_half := minf(float(cab.get("door_x_front", door_x)) + 0.04, pillar_foot.x - 0.03)
		_check(spot.x + BobbleHead.BASE_R * scale < dash_half, "%s: base runs off the dash side (x %.3f, half width %.3f)" % [kind, spot.x, dash_half])
		_check(spot.z - BobbleHead.BASE_R * scale > cowl.y - 0.02, "%s: base runs into the cowl" % kind)
		var header: Vector2 = cab.header
		var slope := (header.x - cowl.x - 0.086) / maxf(header.y - cowl.y, 0.1)
		var glass_y := header.x - (header.y - spot.z) * slope - 0.008   # the screen at that depth (CockpitFrame's rear mirror line)
		var top := spot.y + tallest * scale
		_check(top < glass_y + 0.005, "%s: tallest figure's top %.3f pokes through the screen at %.3f" % [kind, top, glass_y])
		_check(top < float(cab.roof_y), "%s: head top %.3f reaches the roof" % [kind, top])
		print("  glass margin %.3f (%s)" % [glass_y - top, kind])
		var below := rad_to_deg(atan2(eye.y - (spot.y + tallest * scale), maxf(eye.z - spot.z, 0.05)))
		_check(below >= MIN_BELOW_EYE_DEG, "%s: crown is only %.1f deg below eye level, needs %.0f" % [kind, below, MIN_BELOW_EYE_DEG])
		# clear of the passenger door mirror (the mirror is seen through the side glass)
		var dm: Vector3 = cab.door_mirror
		var mirror_yaw := rad_to_deg(atan2(dm.x - eye.x, eye.z - dm.z))
		_check(mirror_yaw - yaw >= MIN_MIRROR_SEP_DEG, "%s: figure %.1f deg, door mirror %.1f deg: too close" % [kind, yaw, mirror_yaw])
		print("slot %s: %.1f deg right, crown %.1f deg below eye, mirror %.1f deg" % [kind, yaw, below, mirror_yaw])

func _run(b: BobbleHead, accel: Vector3, secs: float) -> void:
	for i in int(secs / DT):
		b.step(DT, accel)

func _spring() -> void:
	var b := BobbleHead.new(null, "p1_coupe")
	_run(b, Vector3.ZERO, 2.0)
	_check(b.bob.length() < 0.01, "a steady car should leave it upright, got %s" % b.bob)
	# right-hand corner: the car accelerates toward +x, the head leans to -x
	var side := 0.0
	for i in int(0.8 / DT):
		b.step(DT, Vector3(6.0, 0.0, 0.0))
		side = minf(side, b.bob.x)
	_check(side < -0.25, "a 6 m/s^2 right corner should lean it to -x, peak %.3f" % side)
	_run(b, Vector3.ZERO, 5.0)
	_check(b.bob.length() < 0.02, "should settle upright after the corner, got %s" % b.bob)
	# braking: acceleration toward +z, the head pitches forward (-z)
	var fore := 0.0
	for i in int(0.6 / DT):
		b.step(DT, Vector3(0.0, 0.0, 8.0))
		fore = minf(fore, b.bob.y)
	_check(fore < -0.25, "hard braking should pitch it forward (y < 0), peak %.3f" % fore)
	_run(b, Vector3.ZERO, 5.0)
	# launch: acceleration toward -z, the head pins back (+z)
	var back := 0.0
	for i in int(0.6 / DT):
		b.step(DT, Vector3(0.0, 0.0, -8.0))
		back = maxf(back, b.bob.y)
	_check(back > 0.25, "a launch should pin it back (y > 0), peak %.3f" % back)
	_run(b, Vector3.ZERO, 5.0)
	# a bump nods it
	var nod := 0.0
	for i in int(0.3 / DT):
		b.step(DT, Vector3(0.0, 12.0, 0.0))
		nod = minf(nod, b.bob.y)
	_check(nod < -0.05, "a jolt up should nod it forward, peak %.3f" % nod)
	# the cap
	_run(b, Vector3(80.0, 0.0, 0.0), 2.0)
	_check(b.bob.length() <= BobbleHead.TILT_MAX + 1e-5, "tilt should be capped at %.2f, got %.3f" % [BobbleHead.TILT_MAX, b.bob.length()])
	b.free()

func _settings() -> void:
	CabinMods.bobbles.clear()
	CabinMods.set_bobble("p1_coupe", "ledger")
	CabinMods.set_bobble("p4_kei", "nodding_dog")
	_check(CabinMods.save_settings(), "save_settings failed")
	CabinMods.set_bobble("p1_coupe", "none")
	CabinMods.set_bobble("p4_kei", "none")
	CabinMods.load_settings()
	_check(CabinMods.bobble_for("p1_coupe") == "ledger", "coupe pick should reload, got %s" % CabinMods.bobble_for("p1_coupe"))
	_check(CabinMods.bobble_for("p4_kei") == "nodding_dog", "kei pick should reload, got %s" % CabinMods.bobble_for("p4_kei"))
	_check(CabinMods.bobble_for("p2_hothatch") == "none", "a car with no pick has none, got %s" % CabinMods.bobble_for("p2_hothatch"))
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value(CabinMods.SECTION, "bobble_p1_coupe", "not-a-figure")
	cfg.save(CFG)
	CabinMods.load_settings()
	_check(CabinMods.bobble_for("p1_coupe") == "none", "unknown saved id should read as none, got %s" % CabinMods.bobble_for("p1_coupe"))
	CabinMods.bobbles.clear()
	DirAccess.remove_absolute(CFG)

# ---------- in the game ----------

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _fail_boot()
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = throttle
		c.brake_input = 0.0
		c.steering_input = 0.0
	var frame: CockpitFrame = cam.frame
	var waited := tick - step_start
	match step:
		Step.BOOT:
			if frame == null:
				return false
			if not frame.cockpit and waited < 10:
				return false
			if not frame.cockpit:
				cam.set_view(ChaseCamera.View.COCKPIT)
				return false
			var b := frame.bobble
			_check(b != null and b.get_parent() == frame, "the frame should carry a BobbleHead")
			if b == null:
				return _end()
			_check(b.is_active() and b.is_shown(), "the figure should stand in the cockpit view")
			_check(b.figure == "pike", "NEON_CABIN_MODS bobble=pike should pick pike, got %s" % b.figure)
			_check(b.position.is_equal_approx(CabinSpots.dash_pass(PlayerCar.chassis_kind())), "the figure should stand at dash_pass")
			_check(b.triangle_count() <= MAX_TRIS, "figure over %d tris: %d" % [MAX_TRIS, b.triangle_count()])
			var meshes := b.find_children("*", "MeshInstance3D", true, false)
			_check(meshes.size() == 1, "the figure should be exactly one mesh instance, got %d" % meshes.size())
			_check(frame.find_children("*", "BobbleHead", true, false).size() == 1, "at most one bobble head")
			_check_on_dash(p, frame, b)
			throttle = 1.0
			step = Step.DRIVE
			step_start = tick
		Step.DRIVE:
			if waited == 40:
				bob_before = frame.bobble.bob
			if waited == 120:
				var moved := frame.bobble.bob.length()
				_check(moved > 0.02, "a launch should move the head, bob %s (accel %s)" % [frame.bobble.bob, frame.bobble.accel_local])
				_check(frame.bobble.accel_local.z < -0.5, "the filtered acceleration should read the launch (-z), got %s" % frame.bobble.accel_local)
				var mat := frame.bobble.mesh_instance().material_override as ShaderMaterial
				var sent: Vector2 = mat.get_shader_parameter("bob")
				_check(sent.is_equal_approx(frame.bobble.bob), "the shader should receive the spring's pair, got %s vs %s" % [sent, frame.bobble.bob])
				throttle = 0.0
				cam.set_view(ChaseCamera.View.CHASE)
				step = Step.CHASE
				step_start = tick
		Step.CHASE:
			if waited == 6:
				var b := frame.bobble
				_check(not b.is_active() and not b.is_shown(), "back in the chase view nothing is built")
				_check(b.bob == Vector2.ZERO and not b.is_physics_processing(), "back in the chase view the spring is frozen at rest")
				return _end()
	return false

func _fail_boot() -> bool:
	failures.append("Game never became ready")
	return _end()

## A ray from above the foot hits the cabin's dash within a few mm of the
## foot's height, so the figure stands on the dash and not in the air.
func _check_on_dash(p: PlayerCar, frame: CockpitFrame, b: BobbleHead) -> void:
	var to_car := p.global_transform.affine_inverse()
	var from := b.position + Vector3(0.0, 0.25, 0.0)
	var best := -INF
	for m in frame.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.get_parent() == b or not mi.mesh is ArrayMesh or not mi.is_visible_in_tree():
			continue
		var xf: Transform3D = to_car * mi.global_transform
		var mesh := mi.mesh as ArrayMesh
		for si in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var t := 0
			while t + 2 < verts.size():
				var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, xf * verts[t], xf * verts[t + 1], xf * verts[t + 2])
				t += 3
				if hit != null and hit.y <= b.position.y + 0.02:
					best = maxf(best, hit.y)
	print("dash under the figure: foot y %.3f, surface %.3f" % [b.position.y, best])
	_check(best > -INF and absf(best - b.position.y) < 0.01, "the figure should stand on the dash: foot %.3f, surface under it %.3f" % [b.position.y, best])
