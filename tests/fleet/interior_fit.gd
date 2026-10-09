extends SceneTree
# Interior fit (Roy, 2026-10-09: "the VW beater has half its interior sticking
# OUTSIDE the body"): every player car boots as the player's car (NEON_CAR)
# and its cabin (CockpitFrame, the driver, the mirrors) is checked against its
# own body shell, headless:
#   - every cabin vertex must be enclosed by the shell: a ray from the vertex
#     up, left and right must each hit the body within 3 m, and the vertex
#     must be inside the body's length (the floor is open on every car, so
#     no ray goes down, and a few bodies have an open grille, so no ray goes
#     forward); vertices at the floor skin's own height are the carpet's
#     underside and are skipped, as are the door mirror panes (they sit in
#     the housings outside the shell by design);
#   - the undercarriage must stay under the body's footprint and above the
#     ground (Undercarriage.GROUND_MARGIN);
#   - the cockpit eye must be under the roof and inside the glass.
# Prints one line per cabin part that pokes out (how many of its vertices, and
# how far), so the per-car interior data can be fixed from the numbers.
# Exit code 1 on failure.
#
# NEON_FIT_REPORT=1 prints every part's bounds too (the design pass tool).
# Run: <godot> --headless --audio-driver Dummy --path . -s res://tests/fleet/interior_fit.gd
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
## Collision layer used for the shell proxy only (nothing else in the game is on it).
const SHELL_LAYER := 1 << 19
const REACH := 3.0
## A vertex this far outside the shell (or less) is a seam, not a problem:
## door cards and the headliner sit against the skin on purpose, and the
## skin is one surface with no thickness of its own.
const TOLERANCE := 0.02
## Rays from a vertex, car space.
const DIRS := [Vector3.UP, Vector3.RIGHT, Vector3.LEFT]
## Vertices this close to the body's lowest skin are the floor's own underside.
const FLOOR_SKIP := 0.06

var fails := 0
var game: Node
var logger := Harness.ErrorCounter.new()
var report := OS.get_environment("NEON_FIT_REPORT") == "1"

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		if only != "" and String(k.id) != only:
			continue
		await _fit(String(k.id))
	OS.set_environment("NEON_CAR", "")
	_finish()

func _fit(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	_check(p != null and cam != null and cam.frame != null, "%s: the game should boot with a cockpit frame" % kind)
	if p == null or cam == null or cam.frame == null:
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	for i in RATE:
		await physics_frame
	var inv := p.global_transform.affine_inverse()
	# The shell: every body mesh (not the undercarriage, not the cabin).
	var shell := PackedVector3Array()
	var body_aabb := AABB()
	var first := true
	for mi in p.chassis_visual.find_children("*", "MeshInstance3D", true, false):
		if _under(mi, Undercarriage.NODE_NAME) or mi.name == Undercarriage.PLATE_NAME:
			continue
		var faces := _faces(mi, inv)
		shell.append_array(faces)
		for v in faces:
			if first:
				body_aabb = AABB(v, Vector3.ZERO)
				first = false
			else:
				body_aabb = body_aabb.expand(v)
	_check(shell.size() > 0, "%s: the body should have a mesh" % kind)
	var proxy := StaticBody3D.new()
	proxy.collision_layer = SHELL_LAYER
	proxy.collision_mask = 0
	var shape := CollisionShape3D.new()
	var poly := ConcavePolygonShape3D.new()
	poly.backface_collision = true
	poly.set_faces(shell)
	shape.shape = poly
	proxy.add_child(shape)
	# Away from the road and the car, in car space at a fixed offset.
	var base := Vector3(0.0, 500.0, 0.0)
	proxy.position = base
	root.add_child(proxy)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	print("%s: body x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f (%d shell tris)" % [kind,
		body_aabb.position.x, body_aabb.end.x, body_aabb.position.y, body_aabb.end.y,
		body_aabb.position.z, body_aabb.end.z, shell.size() / 3])
	# The cabin: every mesh under the frame, by part name.
	var frame: CockpitFrame = cam.frame
	var open_top: bool = frame.cab.open_top
	var belt_y := float(frame.cab.belt_y)
	var open_half := float(frame.cab.door_x) + 0.10   # above the belt an open car has no skin: stay within the doors
	var worst := {}
	for mi in frame.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var path := String(frame.get_path_to(mi))
		if path == "Mirrors/LeftGlass" or path == "Mirrors/RightGlass" or path.ends_with("BlindSpotDot"):
			continue
		var verts := _faces(mi, inv)
		var out := 0
		var max_d := 0.0
		var seen := {}
		var cells := {}   # 10 cm cell -> worst distance, so the report says which part of the mesh
		var part_aabb := AABB()
		var pfirst := true
		for v in verts:
			if pfirst:
				part_aabb = AABB(v, Vector3.ZERO)
				pfirst = false
			else:
				part_aabb = part_aabb.expand(v)
			var key := Vector3i((v * 200.0).round())
			if seen.has(key):
				continue
			seen[key] = true
			if v.y < body_aabb.position.y + FLOOR_SKIP:
				continue
			var d: float
			if open_top and v.y > belt_y - 0.08:
				d = maxf(0.0, absf(v.x) - open_half)
			else:
				d = _outside(space, base + v, open_top)
			if v.z < body_aabb.position.z or v.z > body_aabb.end.z:
				d = maxf(d, minf(body_aabb.position.z - v.z, v.z - body_aabb.end.z))
			if d > TOLERANCE:
				out += 1
				max_d = maxf(max_d, d)
				var cell := Vector3i((v * 10.0).floor())
				if not cells.has(cell) or cells[cell] < d:
					cells[cell] = d
		if out > 0:
			worst[path] = [out, seen.size(), max_d, part_aabb, cells]
		elif report:
			print("  ok   %-40s x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % [path, part_aabb.position.x, part_aabb.end.x,
				part_aabb.position.y, part_aabb.end.y, part_aabb.position.z, part_aabb.end.z])
	for path in worst:
		var w: Array = worst[path]
		var a: AABB = w[3]
		print("  OUT  %-40s %d/%d verts, up to %.3f m out; x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % [path, w[0], w[1], w[2],
			a.position.x, a.end.x, a.position.y, a.end.y, a.position.z, a.end.z])
		var cells: Dictionary = w[4]
		var keys := cells.keys()
		keys.sort_custom(func(p, q): return cells[p] > cells[q])
		var where := ""
		for i in mini(8, keys.size()):
			var c: Vector3i = keys[i]
			where += " (%.1f,%.1f,%.1f):%.2f" % [c.x / 10.0, c.y / 10.0, c.z / 10.0, cells[c]]
		print("       worst cells:%s" % where)
	_check(worst.is_empty(), "%s: %d cabin parts poke out of the body" % [kind, worst.size()])
	# The eye: under the roof, inside the shell.
	var eye: Vector3 = cam.eye
	var eye_out := _outside(space, base + eye)
	_check(eye_out <= 0.0 or bool(frame.cab.open_top), "%s: the cockpit eye %s is outside the body (%.3f m)" % [kind, str(eye), eye_out])
	var roof := space.intersect_ray(_ray(base + eye, Vector3.UP))
	if roof.is_empty():
		_check(open_top, "%s: no roof above the eye" % kind)
		print("  eye %s, open top" % str(eye))
	else:
		var head: float = (roof.position - base).y - eye.y
		_check(head >= 0.20, "%s: only %.2f m of roof above the eye (spec: at least 0.20)" % [kind, head])
		print("  eye %s, roof %.2f m above it" % [str(eye), head])
	_check(CabinSpec.missing(frame.cab).is_empty(), "%s: CABIN is missing %s" % [kind, str(CabinSpec.missing(frame.cab))])
	# The underside: under the footprint, above the ground.
	var under := p.chassis_visual.find_child(Undercarriage.NODE_NAME, true, false)
	if under != null:
		var ua := AABB()
		var ufirst := true
		for mi in under.find_children("*", "MeshInstance3D", true, false):
			if report:
				var ma: AABB = mi.transform * mi.mesh.get_aabb()
				print("  under part %s z %.2f..%.2f" % [mi.name, ma.position.z, ma.end.z])
			for v in _faces(mi, inv):
				if ufirst:
					ua = AABB(v, Vector3.ZERO)
					ufirst = false
				else:
					ua = ua.expand(v)
		var zmax_v := Vector3.ZERO
		if under is MeshInstance3D:
			for v in _faces(under, inv):
				ua = AABB(v, Vector3.ZERO) if ufirst else ua.expand(v)
				ufirst = false
				if v.z > zmax_v.z:
					zmax_v = v
		if report:
			print("  under rearmost vertex %s" % str(zmax_v))
		var ground := -float(p.lift.y) if p.get("lift") != null else body_aabb.position.y
		print("  under x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f (body floor %.2f)" % [ua.position.x, ua.end.x, ua.position.y, ua.end.y, ua.position.z, ua.end.z, body_aabb.position.y])
		_check(ua.position.x >= body_aabb.position.x - 0.01 and ua.end.x <= body_aabb.end.x + 0.01, "%s: the undercarriage is wider than the body" % kind)
		_check(ua.position.z >= body_aabb.position.z - 0.01 and ua.end.z <= body_aabb.end.z + 0.01, "%s: the undercarriage is longer than the body" % kind)
	else:
		print("  (no undercarriage node)")
	proxy.queue_free()
	game.queue_free()
	await process_frame
	await process_frame

static func _under(n: Node, parent_name: String) -> bool:
	var q := n
	while q != null:
		if q.name == parent_name:
			return true
		q = q.get_parent()
	return false

## The mesh's triangles in car space.
static func _faces(mi: MeshInstance3D, inv: Transform3D) -> PackedVector3Array:
	var xf := inv * mi.global_transform
	var out := PackedVector3Array()
	if mi.mesh == null:
		return out
	for v in mi.mesh.get_faces():
		out.append(xf * v)
	return out

func _ray(from: Vector3, dir: Vector3) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH, SHELL_LAYER)
	q.hit_back_faces = true
	q.hit_from_inside = false
	return q

## 0 when the point is enclosed by the shell; else the smallest distance the
## point would have to move to be enclosed, estimated from the directions that
## miss (the shortest reach back to the shell in the opposite direction).
func _outside(space: PhysicsDirectSpaceState3D, at: Vector3, open_top := false) -> float:
	var missed := []
	for d in DIRS:
		if open_top and d == Vector3.UP:
			continue   # no roof to hit
		if space.intersect_ray(_ray(at, d)).is_empty():
			missed.append(d)
	if missed.is_empty():
		return 0.0
	# how far past the shell: look back the other way
	var worst := REACH
	for d in missed:
		var back := space.intersect_ray(_ray(at, -d))
		if not back.is_empty():
			worst = minf(worst, (back.position - at).length())
	return worst

func _finish() -> void:
	if logger.errors.size() > 0:
		print("FAIL %d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += logger.errors.size()
	print("interior_fit: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
