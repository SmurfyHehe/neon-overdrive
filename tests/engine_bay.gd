extends SceneTree

# Engine bay under the coupe's hood (car-parts plan 8b item 2, 2026-10-09):
#   - the player car carries an EngineBay with the six parts as separate nodes
#     (engine, intake, turbo, hoses, battery, fan) plus the hood panel, all on
#     the car's render layer, all inside the hood's footprint;
#   - shut by default: hidden, body mesh untouched;
#   - photo mode with the car stopped opens it: the hood swings to OPEN_ANGLE
#     while the tree is paused, the body shows with the hood cut out;
#   - a crash (impulse) never opens it, and request_open() while moving is refused;
#   - driving off shuts it again and puts the full body back.
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/engine_bay.gd

const TIMEOUT_TICKS := 60 * 20
const SETTLE_TICKS := 90

var tick := 0
var phase := 0
var phase_tick := 0
var failures: Array[String] = []
var game: Node
var p: PlayerCar
var bay: EngineBay
var body: MeshInstance3D
var closed_mesh: ArrayMesh
var closed_tris := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_TEST_CAR", "")
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _tris(mi: MeshInstance3D, surface_name := "body") -> int:
	var m := mi.mesh as ArrayMesh
	for i in m.get_surface_count():
		if m.surface_get_name(i) == surface_name:
			return m.surface_get_array_len(i) / 3
	return -1

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick > TIMEOUT_TICKS:
		return _end("timed out in phase %d" % phase)
	if game == null:
		game = current_scene
		if game == null or game.get("player") == null:
			game = null
			return false
		p = game.player
	if not p.is_ready:
		return false
	if bay == null:
		bay = p.engine_bay
		if bay == null:
			return _end("the player car has no EngineBay")
		body = p.chassis_visual.get_node("Body")
		closed_mesh = body.mesh
		closed_tris = _tris(body)
		_static_checks()
	phase_tick += 1
	match phase:
		0:   # let the car settle on its springs, then make sure it is shut
			if phase_tick < SETTLE_TICKS:
				return false
			_check(bay.is_stopped(), "the car should count as stopped at spawn (speed %.2f)" % p.linear_velocity.length())
			_check(not bay.visible and not bay.is_open and body.mesh == closed_mesh, "the bay should start shut and hidden")
			# a crash never opens the hood
			p.apply_central_impulse(Vector3(0, 0, 1) * p.mass * 6.0)
			_next()
		1:   # the impulse: moving, hood shut, request refused
			if phase_tick == 2:
				_check(p.linear_velocity.length() > bay.DRIVE_OFF_SPEED, "the impulse should move the car (speed %.2f)" % p.linear_velocity.length())
				_check(not bay.request_open(), "request_open() while moving should be refused")
				_check(not bay.is_open and not bay.visible, "a crash must not open the hood")
			if phase_tick == 30:   # brake to a halt: the shove was the point, not the roll
				p.linear_velocity = Vector3.ZERO
				p.angular_velocity = Vector3.ZERO
			if phase_tick > 60 * 6:
				return _end("the car never came to rest after the impulse (speed %.2f)" % p.linear_velocity.length())
			if phase_tick > 30 and bay.is_stopped():
				_check(not bay.is_open and body.mesh == closed_mesh, "the hood should still be shut after the crash")
				game.game_state.toggle_photo()
				_next()
		2:   # photo mode while stopped opens it; the swing runs through the pause
			if phase_tick == 1:
				_check(get_root().get_tree().paused, "photo mode should pause the tree")
				_check(bay.is_open and bay.visible, "photo mode with the car stopped should open the hood")
				_check(body.mesh != closed_mesh, "the body should swap to the cut-out mesh when the hood opens")
				var cut := closed_tris - _tris(body)
				_check(cut > 40 and cut < closed_tris / 3, "the cut should remove the hood only, removed %d of %d body triangles" % [cut, closed_tris])
				_check(_tris(body, "glass") == _tris(closed_mesh_instance(), "glass"), "the glass surface should be untouched by the cut")
			if phase_tick > 60 * 3:
				_check(is_equal_approx(bay.angle, bay.OPEN_ANGLE), "the hood should be fully open after 3 s, angle %.1f" % bay.angle)
				_check(is_equal_approx(bay.hinge.rotation.x, deg_to_rad(bay.OPEN_ANGLE)), "the hinge should carry the hood angle")
				game.game_state.toggle_photo()
				_next()
		3:   # back to driving: still open until the car moves
			if phase_tick == 2:
				_check(not get_root().get_tree().paused, "leaving photo mode should unpause")
				_check(bay.is_open and bay.visible, "the hood stays open after photo mode until the car drives off")
				p.linear_velocity = Vector3(0, 0, -4.0)
			if phase_tick > 60 * 3:
				_check(not bay.is_open, "driving off should shut the hood")
				_check(is_equal_approx(bay.angle, 0.0), "the hood should be back down, angle %.1f" % bay.angle)
				_check(not bay.visible, "the bay should hide once shut")
				_check(body.mesh == closed_mesh, "the full body mesh should be back once shut")
				return _end("")
	return false

var _closed_mi: MeshInstance3D
func closed_mesh_instance() -> MeshInstance3D:
	if _closed_mi == null:
		_closed_mi = MeshInstance3D.new()
		_closed_mi.mesh = closed_mesh
	return _closed_mi

func _next() -> void:
	phase += 1
	phase_tick = 0

func _static_checks() -> void:
	_check(bay.get_parent() == p, "the bay should hang on the car")
	_check(bay.process_mode == Node.PROCESS_MODE_ALWAYS, "the bay must process while the tree is paused")
	var layer := 1 << (CarFx.CAR_LAYER - 1)
	for slot in EngineBay.PART_SLOTS:
		var part: MeshInstance3D = bay.parts.get(slot)
		_check(part != null, "missing part %s" % slot)
		if part == null:
			continue
		_check(part.get_parent() == bay and part.get_meta("part_slot", "") == slot, "part %s should be its own child of the bay, tagged with its slot" % slot)
		_check(part.mesh.get_surface_count() == 1 and part.mesh.surface_get_array_len(0) >= 36, "part %s should carry a mesh" % slot)
		_check(part.layers == layer, "part %s should be on the car's render layer" % slot)
		var aabb := part.get_aabb()
		var lo := aabb.position + bay.position
		var hi := aabb.end + bay.position
		_check(lo.z >= EngineBay.NOSE_Z + EngineBay.HOOD_S0 - 0.01 and hi.z <= EngineBay.NOSE_Z + EngineBay.HOOD_S1 + 0.01,
			"part %s should sit between the nose cap and the firewall (z %.2f..%.2f)" % [slot, lo.z, hi.z])
		_check(absf(lo.x) <= 0.8 and absf(hi.x) <= 0.8, "part %s should sit inside the fenders (x %.2f..%.2f)" % [slot, lo.x, hi.x])
		_check(hi.y <= 0.72 + P1CoupeBuilder.BODY_LIFT, "part %s should fit under the hood (top %.2f)" % [slot, hi.y])
		_check(lo.y >= 0.2, "part %s should sit above the floor (bottom %.2f)" % [slot, lo.y])
	_check(bay.hood != null and bay.hood.layers == layer and bay.hood.get_meta("part_slot", "") == "hood", "the hood panel should be a tagged part on the car layer")
	_check(bay.hood.get_surface_override_material(0) == null and bay.hood.mesh.surface_get_material(0) == p.chassis_visual.get_meta("body_mat"), "the hood should use the body's paint material")
	var hood_aabb := bay.hood.get_aabb()
	_check(hood_aabb.size.z > 1.1 and hood_aabb.size.x > 1.4, "the hood panel should cover the hood (size %s)" % hood_aabb.size)
	# the cut region matches the hood sticker slot and misses the lamps and doors
	_check(EngineBay.in_hood_region(Vector3(0.0, 0.7327, -1.34)), "the hood sticker centre should be in the cut region")
	_check(not EngineBay.in_hood_region(Vector3(0.5, 0.6, -2.0)), "the pop-up lamps should not be cut")
	_check(not EngineBay.in_hood_region(Vector3(0.9, 0.5, -1.2)), "the fenders should not be cut")
	_check(not EngineBay.in_hood_region(Vector3(0.0, 0.9, -0.3)), "the windshield should not be cut")
	# a swapped part takes the slot
	var dummy := MeshInstance3D.new()
	bay.swap_part("battery", dummy)
	_check(bay.parts.battery == dummy and dummy.get_parent() == bay and dummy.layers == layer, "swap_part should replace the slot")

func _end(fatal: String) -> bool:
	if fatal != "":
		failures.append(fatal)
	if _closed_mi != null:
		_closed_mi.free()
	if failures.is_empty():
		print("PASS engine_bay")
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		quit(1)
	return true
