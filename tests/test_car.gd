extends SceneTree

# Test car checks (GitHub #63):
#   - body is about 4.4 x 1.8 x 1.3 m (within 5 cm; wheels excluded)
#   - headlights at the nose (-Z), tail lights at the tail (+Z)
#   - every body/cabin loft triangle faces outward (same rule as car_loft_normals)
#   - the player's wheels carry the test-car wheel visual, sit at the physics
#     wheel positions, and the visual's radius matches the physics tyre radius
#
# The player drives the P1 coupe by default (tests/p1_coupe.gd); this test sets
# NEON_TEST_CAR=1 for itself so the player it builds is the test car.
#
# Run (headless is fine):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_car.gd

const TOL := 0.05
var fails := 0

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails += 1

func _initialize() -> void:
	var car := TestCarBuilder.build_chassis_visual()
	var box := AABB()
	var first := true
	var heads := []
	var tails := []
	var lofts := 0
	for child in car.get_children():
		var mi := child as MeshInstance3D
		var aabb := mi.transform * mi.mesh.get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
		var mat := mi.material_override as StandardMaterial3D
		if mi.mesh is BoxMesh and mat.emission_enabled:
			(heads if mat.albedo_color.g > 0.5 else tails).append(mi.position.z)
		# Body and cabin only: the stripes are thin skins on a slope, so the
		# centre-of-AABB test below does not apply to them.
		if mi.mesh is ArrayMesh:
			lofts += 1
			if lofts <= 2:
				_check_loft(mi.mesh)
	print("body size %s" % box.size)
	for axis in [["length", box.size.z, TestCarBuilder.LENGTH], ["width", box.size.x, TestCarBuilder.WIDTH], ["height (ground to roof)", box.end.y, TestCarBuilder.HEIGHT]]:
		if absf(axis[1] - axis[2]) > TOL:
			_fail("%s %.3f, want %.2f" % axis)
	if heads.size() != 2 or tails.size() != 2:
		_fail("want 2 headlights and 2 tail lights, got %d and %d" % [heads.size(), tails.size()])
	for z in heads:
		if z > box.position.z + 0.1:
			_fail("headlight at z %.2f is not at the nose" % z)
	for z in tails:
		if z < box.end.z - 0.1:
			_fail("tail light at z %.2f is not at the tail" % z)
	car.free()

	OS.set_environment("NEON_TEST_CAR", "1")
	var player: PlayerCar = load("res://scripts/player.gd").new()
	root.add_child(player)
	await process_frame  # let the player's _ready build its wheels
	var cfg: Dictionary = PlayerCar.CFG
	var wheels := {
		"FL": [player.front_left_wheel, Vector3(-cfg.wheel_x, 0, -cfg.axle_z)],
		"FR": [player.front_right_wheel, Vector3(cfg.wheel_x, 0, -cfg.axle_z)],
		"RL": [player.rear_left_wheel, Vector3(-cfg.wheel_x, 0, cfg.axle_z)],
		"RR": [player.rear_right_wheel, Vector3(cfg.wheel_x, 0, cfg.axle_z)],
	}
	for name in wheels:
		var w: Wheel = wheels[name][0]
		var want: Vector3 = wheels[name][1]
		if Vector2(w.position.x, w.position.z).distance_to(Vector2(want.x, want.z)) > 1e-4:
			_fail("%s wheel at %s, want x/z of %s" % [name, w.position, want])
		var tyre := w.wheel_node.get_child(0) as MeshInstance3D
		var r: float = (tyre.mesh as CylinderMesh).top_radius
		if absf(r - w.tire_radius) > 1e-4:
			_fail("%s visual radius %.3f, physics %.3f" % [name, r, w.tire_radius])
	print("wheelbase %.2f m, track %.2f m" % [cfg.axle_z * 2.0, cfg.wheel_x * 2.0])
	player.free()

	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _check_loft(mesh: ArrayMesh) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var center := mesh.get_aabb().get_center()
	for t in verts.size() / 3:
		var a := verts[t * 3]
		var b := verts[t * 3 + 1]
		var c := verts[t * 3 + 2]
		var face := (c - a).cross(b - a)
		if face.length() < 1e-9:
			_fail("zero-area loft triangle %s %s %s" % [a, b, c])
		elif face.dot((a + b + c) / 3.0 - center) <= 0.0:
			_fail("loft triangle faces inward %s %s %s" % [a, b, c])
