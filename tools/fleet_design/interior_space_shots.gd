extends SceneTree
# Pictures for the cabin space audit (2026-10-09): for every player car, the
# cockpit view from the game's own eye and from the eye of a 1.55, 1.78 and
# 1.95 m driver sat on the cushion (tools/fleet_design/manikin.gd), and a side
# cutaway: the camera on the driver's side with its near plane just inside
# the door, so the door and its glass are clipped away and the seat, wheel,
# pedals, the built driver and three translucent manikins (silver 1.55 m,
# amber 1.78 m, sodium 1.95 m) show against the roof and the dash. Needs the
# real renderer (no --headless) and the numbers from interior_space.gd
# (user://interior_space/<kind>.json: cushion height, seat position, pedal).
# Writes PNGs to user://interior_space/shots/<kind>_<view>.png.
#
#   <godot> --path . -s res://tools/fleet_design/interior_space_shots.gd
#   NEON_FIT_CAR=p4_kei limits it to one car.
const Manikin := preload("res://tools/fleet_design/manikin.gd")

const STATURES := {1.55: Color("#C9CED6"), 1.78: Color("#FFC066"), 1.95: Color("#FF8A1F")}
const FOV := 62.0

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://interior_space_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	var dir := ProjectSettings.globalize_path("user://interior_space/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		if only != "" and kind != only:
			continue
		var f := FileAccess.open("user://interior_space/%s.json" % kind, FileAccess.READ)
		if f == null:
			print("%s: no interior_space json, run interior_space.gd first" % kind)
			continue
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		f.close()
		await _shoot(kind, dir, data)
	print("interior_space_shots: wrote to %s" % dir)
	quit(0)

static func _vec(s) -> Vector3:
	# JSON turns Vector3 into "(x, y, z)" strings
	var t := String(s).trim_prefix("(").trim_suffix(")").split(",")
	return Vector3(float(t[0]), float(t[1]), float(t[2]))

func _shoot(kind: String, dir: String, data: Dictionary) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false   # no HUD or mirror panel over the pictures
	for i in 90:
		await physics_frame
	var seat_x := float(data.seat_x)
	var seat_z := float(data.seat_z)
	var cushion_y := float(data.cushion_y)
	var pedal := _vec(data.pedal)
	var ankle := pedal + Vector3(0.0, -0.12, 0.05)
	var shot := Camera3D.new()
	shot.near = 0.03
	shot.far = 400.0
	root.add_child(shot)
	var xf: Transform3D = p.global_transform
	# Cockpit views: the game's eye, then each stature's eye.
	cam.set_view(ChaseCamera.View.COCKPIT)
	for i in 4:
		await physics_frame
	shot.cull_mask = cam.cull_mask
	shot.fov = FOV
	var eyes := {"eye_game": _vec(data.game_eye)}
	for s in STATURES:
		eyes["eye_%d" % int(round(s * 100.0))] = Manikin.pose(s, seat_x, cushion_y, seat_z).eye
	for view in eyes:
		var eye: Vector3 = eyes[view]
		shot.global_position = xf * eye
		shot.look_at(xf * (eye + Vector3(0.0, -0.05, -10.0)))
		shot.make_current()
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, kind, view])
	# The cutaway: chase view (the driver's head and torso are drawn), manikins added.
	cam.set_view(ChaseCamera.View.CHASE)
	for i in 4:
		await physics_frame
	var manikins := Node3D.new()
	manikins.name = "AuditManikins"
	p.add_child(manikins)
	for s in STATURES:
		_draw_manikin(manikins, Manikin.pose(s, seat_x, cushion_y, seat_z), ankle, STATURES[s])
	shot.cull_mask = cam.cull_mask
	var lamp := OmniLight3D.new()   # a work light in the cabin: nothing lights an interior at night
	lamp.light_energy = 2.5
	lamp.omni_range = 3.0
	lamp.light_color = Color(1.0, 0.92, 0.8)
	lamp.position = Vector3(0.0, cushion_y + 0.55, seat_z - 0.2)
	p.add_child(lamp)
	var door := float(data.hip_left)   # from the seat centre to the door card
	var cam_x := -3.2
	var at := Vector3(seat_x, cushion_y + 0.40, seat_z + 0.05)
	for view in ["cutaway", "cutaway_wide"]:
		shot.fov = 34.0 if view == "cutaway" else 50.0
		shot.near = absf(cam_x) - (absf(seat_x) + door - 0.03)   # clip the door away, keep the seat
		shot.global_position = xf * Vector3(cam_x, cushion_y + 0.45, seat_z + (0.05 if view == "cutaway" else 0.25))
		shot.look_at(xf * at)
		shot.make_current()
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, kind, view])
	print("%s: shots written" % kind)
	shot.queue_free()
	game.queue_free()
	for i in 4:
		await process_frame

func _draw_manikin(parent: Node3D, m: Dictionary, ankle: Vector3, colour: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(colour, 0.55)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# head
	_box(parent, m.head_centre, m.head_half * 2.0, mat)
	# torso: hip to shoulder, a slab
	_segment(parent, m.hip, m.shoulder, 0.05, mat)
	# eye mark
	_box(parent, m.eye, Vector3(0.05, 0.02, 0.02), mat)
	# shoulder bar
	_box(parent, m.shoulder, Vector3(m.shoulder_half * 2.0, 0.04, 0.04), mat)
	# leg
	var lg := Manikin.leg(m.hip, ankle, m.thigh, m.shin)
	_segment(parent, m.hip, lg[0], 0.06, mat)
	_segment(parent, lg[0], lg[1], 0.05, mat)
	# reach: a line from the shoulder, the comfortable reach, pointing at the wheel's grip
	_box(parent, lg[0], Vector3(0.09, 0.09, 0.09), mat)   # knee

func _box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)

func _segment(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thick, (b - a).length(), thick)
	mi.mesh = box
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	var up := (b - a).normalized()
	var side := up.cross(Vector3.RIGHT)
	if side.length_squared() < 1e-6:
		side = up.cross(Vector3.FORWARD)
	side = side.normalized()
	mi.basis = Basis(side.cross(up).normalized(), up, side)
	parent.add_child(mi)
