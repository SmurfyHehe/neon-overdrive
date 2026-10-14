extends SceneTree

# The totalled look on EVERY car you can drive (Roy 2026-10-14: "it's not just
# cars, it's everything in the game"): loops over PlayerCars.KINDS and checks
# what the look does on each, with no game booted.
# - a car built from parts (a body.glb): has a front bumper and a hood with
#   its hinge, so the bumper hangs and the hood buckles; part_mesh builds both
#   with triangles; the bumper's box is wider than it is tall and sits at the
#   nose (-z); the hinge is behind the hood's front edge
# - a sheet car (no glb): has_car is false, so WreckParts leaves it alone and
#   the smoke, sparks, dark lamp and rattle still come from the meter
# - the pure rules are the same for every kind (nothing per car in WreckLook)
# Prints one line per car. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/wreck_parts_cars.gd

const WreckLook := preload("res://scripts/car/wreck_look.gd")
const WreckParts := preload("res://scripts/car/wreck_parts.gd")

var failures: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _initialize() -> void:
	var parts_cars := 0
	var sheet_cars := 0
	for k in PlayerCars.KINDS:
		var id: String = k.id
		if CarAssembler.has_car(id):
			parts_cars += 1
			_parts_car(id)
		else:
			sheet_cars += 1
			print("%-16s sheet car: smoke, sparks, dark lamp and rattle only (no parts to hang)" % id)
		# the look rules do not depend on the car
		_check(WreckLook.stage(0.95) == 3 and WreckLook.smoke_rate(3, 1.0) > 0.0 and WreckLook.spark_rate(3, 80.0) > 0.0, "%s: the meter look applies" % id)
	print("%d cars: %d built from parts, %d sheet" % [PlayerCars.KINDS.size(), parts_cars, sheet_cars])
	_check(parts_cars >= 8, "every parts-built car was seen (%d)" % parts_cars)
	print("wreck_parts_cars: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)

func _parts_car(id: String) -> void:
	var names := CarAssembler.part_names(id)
	var hinges := CarAssembler.hinges(id)
	var has_bumper := names.has(WreckParts.BUMPER)
	var has_hood := names.has(WreckParts.HOOD) and hinges.has(WreckParts.HOOD_HINGE)
	_check(has_bumper, "%s: has a front bumper to hang" % id)
	_check(has_hood, "%s: has a hood on its hinge to buckle" % id)
	var line := "%-16s parts car:" % id
	if has_bumper:
		var box := CarAssembler.part_aabb(id, WreckParts.BUMPER)
		var mesh := CarAssembler.part_mesh(id, WreckParts.BUMPER, Vector3(box.end.x, box.end.y, box.get_center().z))
		var tris := _tris(mesh)
		line += " bumper %d tris, %.2f m wide at z %.2f;" % [tris, box.size.x, box.get_center().z]
		_check(mesh != null and tris > 0, "%s: the loose bumper mesh builds" % id)
		_check(box.size.x > box.size.y and box.size.x > 1.0, "%s: the bumper is a wide part (%.2f x %.2f)" % [id, box.size.x, box.size.y])
		_check(box.get_center().z < 0.0, "%s: the front bumper is at the nose (z %.2f)" % [id, box.get_center().z])
	if has_hood:
		var h: Dictionary = hinges[WreckParts.HOOD_HINGE]
		var hb := CarAssembler.part_aabb(id, WreckParts.HOOD)
		var mesh := CarAssembler.part_mesh(id, WreckParts.HOOD, h.origin)
		var tris := _tris(mesh)
		line += " hood %d tris, hinge z %.2f, front edge z %.2f" % [tris, (h.origin as Vector3).z, hb.position.z]
		_check(mesh != null and tris > 0, "%s: the buckled hood mesh builds" % id)
		_check((h.origin as Vector3).z > hb.position.z + 0.3, "%s: the hood hinge is behind its front edge, so a lift raises the front" % id)
	print(line)

func _tris(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for i in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n
