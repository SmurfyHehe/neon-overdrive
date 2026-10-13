extends SceneTree
# Cabin fit (2026-10-13, issue #686; method from
# notes/interior-clash-audit-2026-10-13.md): for every drivable car, boot the
# cockpit headless, turn every solid in the cabin into one collision shell and
# ask of each moving or held part "is this point inside some OTHER solid?" by
# counting ray crossings (face_index -> owning solid, own faces skipped; three
# skew rays vote, and a point counts only when all six axis rays leave through
# the same solid, which throws out sheets and skin contacts).
# Moving parts (door glass, crank, switch, both hands, the idle items, lever,
# handbrake, pedals, trinket, bobble, the vape cloud) are posed through their
# worst positions. The pane is a sheet, so hand-vs-pane is "points on both
# sides of the pane, within it". The window crank is tried on every car, not
# only the cars that have one, so a spec change cannot surprise.
#
# Pass rule: no probe point deeper than ALLOW inside another solid (the ray
# probe's own floor; hands, held items and the pane get nothing more), parts
# let into their mount on purpose get MOUNT_ALLOW, no glass above the belt with
# the window fully down, no glass inboard of the door card below its top, the
# trinket hung from the car's own mirror. The cabin's own boxes against each
# other (armrest let into its card, dash wedge into the firewall) are joints by
# design and not probed.
# Prints one FAIL line per probe/pose/part with the deepest point, car space.
# Exit code 1 on failure.
#
# Run: <godot> --headless --audio-driver Dummy --path . -s res://tests/fleet/cabin_fit.gd
# Env: NEON_FIT_CAR=<kind> for one car.
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RATE := 60
const LAYER := 1 << 19
const REACH := 4.0
const STEP := 0.0004
## Deeper than this inside another solid fails (m): the probe's floor, 1 mm
## above the depth a hand resting on a surface reads at (its skin points).
const MIN_DEPTH := 0.002
## A part let into its mount on purpose (switch bezel in the armrest, crank
## boss on the card, gauge pod foot, bobble base on the dash) may sit this deep.
const MOUNT_ALLOW := 0.0025
## The trinket's cord ties on under the car's own rear-view mirror, within this.
const TRINKET_FROM_MIRROR := 0.06
## The coupe's tie-on point (CabinSpots mirror_hang) from its rear_mirror.
const COUPE_HANG_FROM_MIRROR := Vector3(-0.07, -0.033, -0.015)
const BASE := Vector3(0.0, 500.0, 0.0)
const AXES := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
# three skew directions for the parity vote (never along a box edge or face)
const VOTE := [Vector3(0.31, 0.87, 0.39), Vector3(-0.73, 0.29, -0.62), Vector3(0.52, -0.41, 0.75)]


var game: Node
var logger := Harness.ErrorCounter.new()
var out_lines := PackedStringArray()
var proxy: StaticBody3D
var face_solid := PackedInt32Array()   # concave face index -> solid id
var solid_name := PackedStringArray()
var solid_aabb: Array[AABB] = []
var space: PhysicsDirectSpaceState3D
var findings := []                     # [kind, probe, pose, against, depth, n_inside, n_total, worst point]
var cabin_ids := {}                    # solid id -> true for the merged Cabin's own boxes
var fails := 0

func _initialize() -> void:

	OS.add_logger(logger)
	_run()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		if only != "" and only != kind:
			continue
		await _car(kind)
	OS.set_environment("NEON_CAR", "")
	print("")
	var per_car := {}
	for f in findings:
		per_car[f[0]] = int(per_car.get(f[0], 0)) + 1
		print("FAIL %s: %s (%s) %.1f mm in %s, %d/%d points, worst at (%.3f, %.3f, %.3f)" % [f[0], f[1], f[2], f[4] * 1000.0, f[3], f[5], f[6], f[7].x, f[7].y, f[7].z])
		fails += 1
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		if only == "" or only == kind:
			print("cabin_fit %-18s %s" % [kind, "ok" if not per_car.has(kind) else "%d clashes" % per_car[kind]])
	if logger.errors.size() > 0:
		print("FAIL engine errors: %d: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += 1
	print("cabin_fit: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)

func _say(s: String) -> void:
	print(s)
	out_lines.append(s)

# ---------- one car ----------

func _car(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	if p == null or cam == null or cam.frame == null:
		_say("%s: no cockpit frame, skipped" % kind)
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	for i in RATE:
		await physics_frame
	var frame: CockpitFrame = cam.frame
	var driver: DriverModel = frame.driver
	frame.set_process(false)
	frame.set_physics_process(false)
	driver.set_process(false)
	var cab: Dictionary = frame.cab
	_say("")
	_say("=== %s: door_x %.3f glass_x %.3f belt %.3f seat_h %.3f eye %s control %s" % [kind, cab.door_x, cab.glass_x, cab.belt_y, cab.seat_h, cab.eye, frame.window_control])
	frame.set_window(0.0, 0)
	frame.wheel.set_angle(0.0)
	for i in 30:
		driver._process(1.0 / RATE)
	await _build_shell(frame, driver)
	# 1. static solids against each other (cabin components, pocket, boss, bezel, mirrors, head unit, pod, handbrake, pedals, wheel, lever at rest)
	var t0 := Time.get_ticks_msec()
	_static_vs_static(kind)
	_say("  static done %d ms" % (Time.get_ticks_msec() - t0)); t0 = Time.get_ticks_msec()
	# 2. the glass pane through its travel
	_glass(kind, frame)
	_say("  glass done %d ms" % (Time.get_ticks_msec() - t0)); t0 = Time.get_ticks_msec()
	# 3. the window crank (forced on every car) and the switch
	await _window_controls(kind, frame, driver)
	_say("  window controls done %d ms" % (Time.get_ticks_msec() - t0)); t0 = Time.get_ticks_msec()
	# 4. the left hand: window hold, flip-off open and shut, idle items
	_left_hand(kind, frame, driver)
	_say("  left hand done %d ms" % (Time.get_ticks_msec() - t0)); t0 = Time.get_ticks_msec()
	# 5. the right hand: knob per gear, handbrake, radio
	_right_hand(kind, frame, driver)
	_say("  right hand done %d ms" % (Time.get_ticks_msec() - t0)); t0 = Time.get_ticks_msec()
	# 6. the lever per gear, the handbrake pulled, the pedals pressed
	_lever_and_pedals(kind, frame)
	_say("  lever/pedals done %d ms" % (Time.get_ticks_msec() - t0)); t0 = Time.get_ticks_msec()
	# 7. the trinket and the bobble at their largest swing
	_trinket_and_bobble(kind, frame)
	_say("  trinket/bobble done %d ms" % (Time.get_ticks_msec() - t0))
	_drop_shell()
	game.queue_free()
	await process_frame
	await process_frame

# ---------- the shell ----------

## Paths under the frame that are probes, sheets or not solids: never shell.
## The window control is probed on its own (it is swapped crank/switch during
## the run, and the hand is meant to touch it).
const NOT_SHELL := ["WindowGlass", "Backlight", "Lamps", "LampText", "Driver", "Lever", "Trinket", "Bobble", "ThrottlePedal", "BrakePedal", "ClutchPedal", "CabinLight", "WindowControl"]
## Assemblies let into the dash or console where they are mounted (the head
## unit in its slot, the needles in the cluster, the levers in their boots):
## not probed at rest; the levers are probed for what moves in when they move.
const MOUNTED_ASSEMBLY := ["radio", "speedoneedle", "tachneedle", "handbrake", "gear lever"]

func _build_shell(frame: CockpitFrame, driver: DriverModel) -> void:
	cabin_ids = {}
	face_solid = PackedInt32Array()
	solid_name = PackedStringArray()
	solid_aabb = []
	var faces := PackedVector3Array()
	var inv := frame.global_transform.affine_inverse()
	for mi in frame.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var path := String(frame.get_path_to(m))
		var top := path.get_slice("/", 0)
		if NOT_SHELL.has(top):
			continue
		if path.begins_with("Mirrors/") and path.ends_with("Glass"):
			continue
		var tris := _faces(m, inv)
		if path == "Cabin" or path == "Shelf":
			_add_components(faces, tris, frame.cab)
		else:
			_add_solid(faces, tris, _nice(path))
	# the driver's pocket is under Driver: add it as a solid of its own
	var pocket: MeshInstance3D = driver.props.pocket
	_add_solid(faces, _faces(pocket, inv), "door pocket")
	# the lever at rest, as a solid
	for mi in frame.lever.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and mi.is_visible_in_tree():
			_add_solid(faces, _faces(mi, inv), "gear lever")
	proxy = StaticBody3D.new()
	proxy.collision_layer = LAYER
	proxy.collision_mask = 0
	var cs := CollisionShape3D.new()
	var poly := ConcavePolygonShape3D.new()
	poly.backface_collision = true
	poly.set_faces(faces)
	cs.shape = poly
	proxy.add_child(cs)
	proxy.position = BASE
	root.add_child(proxy)
	await physics_frame
	await physics_frame
	space = root.get_world_3d().direct_space_state
	_say("shell: %d solids, %d triangles" % [solid_name.size(), faces.size() / 3])

func _drop_shell() -> void:
	proxy.queue_free()
	proxy = null

static func _faces(mi: MeshInstance3D, inv: Transform3D) -> PackedVector3Array:
	var xf := inv * mi.global_transform
	var out := PackedVector3Array()
	for v in mi.mesh.get_faces():
		out.append(xf * v)
	return out

func _add_solid(faces: PackedVector3Array, tris: PackedVector3Array, label: String) -> int:
	var id := solid_name.size()
	solid_name.append(label)
	var box := AABB(tris[0], Vector3.ZERO) if tris.size() > 0 else AABB()
	for v in tris:
		box = box.expand(v)
	solid_aabb.append(box)
	faces.append_array(tris)
	for i in tris.size() / 3:
		face_solid.append(id)
	return id

## The one merged Cabin mesh split into its closed solids (the kit's boxes
## never share a vertex), each named from where it sits in the cabin.
func _add_components(faces: PackedVector3Array, tris: PackedVector3Array, cab: Dictionary) -> void:
	var n := tris.size() / 3
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	var first := {}
	for i in n:
		for j in 3:
			var v := tris[i * 3 + j]
			var key := Vector3i(roundi(v.x * 5000.0), roundi(v.y * 5000.0), roundi(v.z * 5000.0))
			if first.has(key):
				_union(parent, i, first[key])
			else:
				first[key] = i
	var groups := {}
	for i in n:
		var r := _find(parent, i)
		if not groups.has(r):
			groups[r] = PackedVector3Array()
		var g: PackedVector3Array = groups[r]
		g.append(tris[i * 3])
		g.append(tris[i * 3 + 1])
		g.append(tris[i * 3 + 2])
		groups[r] = g
	for r in groups:
		var g: PackedVector3Array = groups[r]
		var box := AABB(g[0], Vector3.ZERO)
		for v in g:
			box = box.expand(v)
		cabin_ids[_add_solid(faces, g, _place_name(box, cab))] = true

func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i

func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb

## A readable name for a cabin solid from its box and the cabin's numbers.
func _place_name(box: AABB, cab: Dictionary) -> String:
	var c := box.get_center()
	var s := box.size
	var door := float(cab.door_x)
	var belt := float(cab.belt_y)
	var seat_h := float(cab.seat_h)
	var eye: Vector3 = cab.eye
	var roof := float(cab.roof_y)
	var side := "left " if c.x < 0.0 else ("right " if c.x > 0.0 else "")
	var dims := " %dx%dx%d" % [roundi(s.x * 100.0), roundi(s.y * 100.0), roundi(s.z * 100.0)]
	if absf(c.z - float(cab.b_pillar_z)) < 0.08 and c.y > belt - 0.02 and absf(c.x) > door - 0.25:
		return side + "B-pillar" + dims
	if absf(c.x) > door - 0.09:
		if c.y > belt + 0.08:
			return side + "pillar/belt trim" + dims
		if absf(s.x - 0.05) < 0.011 and absf(s.z - 0.12) < 0.011:
			return side + "door pull" + dims
		if absf(s.x - 0.12) < 0.011 and absf(s.z - 0.32) < 0.011:
			return side + "armrest" + dims
		if c.y < seat_h + 0.05:
			return side + "sill" + dims
		if absf(c.y - (belt - 0.015)) < 0.03 and s.y < 0.05:
			return side + "belt pad" + dims
		if absf(s.x - 0.06) < 0.005 and s.y > 0.2:
			return side + "door card" + dims
		return side + "door part" + dims
	if c.y > roof - 0.12 and s.y < 0.08:
		return "roof liner/header" + dims
	if c.z < eye.z - 0.45 and c.y > seat_h + 0.25:
		return "dash" + dims
	if absf(c.x) < 0.2 and c.y < seat_h + 0.32 and c.z > eye.z - 0.5:
		return "console/tunnel" + dims
	if c.z > eye.z + 0.3:
		return "rear seat/shelf" + dims
	if c.y < seat_h + 0.05 and s.y < 0.05:
		return "floor" + dims
	return side + "seat/other" + dims

func _nice(path: String) -> String:
	var top := path.get_slice("/", 0)
	match top:
		"WindowControl":
			return path.get_file().to_lower().replace("crankboss", "crank boss").replace("switchbezel", "switch bezel")
		"Mirrors":
			return "mirror " + path.get_file().to_lower()
		"WheelMount":
			return "steering wheel"
		"Handbrake":
			return "handbrake"
		"HeadUnit":
			return "head unit"
		"Pod":
			return "gauge pod"
		"Clutter":
			return "clutter " + path.get_file().to_lower()
	return path.to_lower()

# ---------- the inside test ----------

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from + BASE, to + BASE, LAYER)
	q.hit_back_faces = true
	q.hit_from_inside = false
	return space.intersect_ray(q)

## Crossings of other solids' faces along one direction, parity = inside.
func _crossings(p: Vector3, d: Vector3, skip: int) -> int:
	var from := p
	var count := 0
	for i in 96:
		var hit := _ray(from, p + d * REACH)
		if hit.is_empty():
			break
		var fi := int(hit.get("face_index", -1))
		if fi >= 0 and fi < face_solid.size() and not _same(face_solid[fi], skip):
			count += 1
		from = (hit.position as Vector3) - BASE + d * STEP
	return count

func _same(a: int, b: int) -> bool:
	return a == b or (b >= 0 and a >= 0 and solid_name[a] == solid_name[b])

## Which other solid encloses p, or -1. Majority of three skew rays; the
## solid named is the nearest face hit by the first odd ray.
func _inside(p: Vector3, skip: int) -> int:
	var odd := 0
	for d in VOTE:
		if _crossings(p, d, skip) % 2 == 1:
			odd += 1
	if odd < 2:
		return -1
	# name the solid: the nearest hit in any axis direction that is not skip
	var best := REACH
	var who := -1
	for d in AXES:
		var from := p
		for i in 16:
			var hit := _ray(from, p + d * REACH)
			if hit.is_empty():
				break
			var fi := int(hit.get("face_index", -1))
			var dist := ((hit.position as Vector3) - BASE - p).length()
			if fi >= 0 and not _same(face_solid[fi], skip):
				if dist < best:
					best = dist
					who = face_solid[fi]
				break
			from = (hit.position as Vector3) - BASE + d * STEP
	return who

## Depth: the shortest way out of the solid `who` from p, or -1 when some
## axis never leaves through `who` (p is not enclosed by it: a sheet, a
## mislabel, or a point on its skin).
func _depth(p: Vector3, who: int) -> float:
	var best := REACH
	for d in AXES:
		var from := p
		var found := false
		for i in 24:
			var hit := _ray(from, p + d * REACH)
			if hit.is_empty():
				break
			var fi := int(hit.get("face_index", -1))
			if fi >= 0 and face_solid[fi] == who:
				best = minf(best, ((hit.position as Vector3) - BASE - p).length())
				found = true
				break
			from = (hit.position as Vector3) - BASE + d * STEP
		if not found:
			return -1.0
	return best

## Probes `pts` (frame space) against every solid but `skip`; one finding per
## solid hit, with the deepest point.
func _probe(kind: String, probe: String, pose: String, pts: PackedVector3Array, skip: int = -1, allow := MIN_DEPTH) -> void:
	var per := {}   # solid -> [depth, count, worst]
	for p in pts:
		var who := _inside(p, skip)
		if who < 0:
			continue
		var d := _depth(p, who)
		if d < 0.0:
			continue
		if not per.has(who):
			per[who] = [d, 1, p]
		else:
			var e: Array = per[who]
			e[1] += 1
			if d > e[0]:
				e[0] = d
				e[2] = p
	for who in per:
		var e: Array = per[who]
		if e[0] > allow:
			findings.append([kind, probe, pose, solid_name[who], e[0], e[1], pts.size(), e[2]])

## A part on a pivot whose foot lives in its boot (lever, handbrake): only the
## points that were clear at rest count, so the boot joint is not a clash but
## the lever's end swinging into the console is. `rest` and `pts` pair up.
func _probe_moved(kind: String, probe: String, pose: String, rest: PackedVector3Array, pts: PackedVector3Array, skip: int) -> void:
	var moved := PackedVector3Array()
	for i in mini(rest.size(), pts.size()):
		if _inside(rest[i], skip) < 0:
			moved.append(pts[i])
	_probe(kind, probe, pose, moved, skip)

## Vertices plus face centroids and edge midpoints of a mesh, frame space.
static func _points(mi: MeshInstance3D, inv: Transform3D, dense := true) -> PackedVector3Array:
	var xf := inv * mi.global_transform
	var f := mi.mesh.get_faces()
	var out := PackedVector3Array()
	var i := 0
	while i + 2 < f.size():
		var a := xf * f[i]
		var b := xf * f[i + 1]
		var c := xf * f[i + 2]
		out.append(a)
		if dense:
			out.append((a + b + c) / 3.0)
			out.append((a + b) * 0.5)
		i += 3
	return out

static func _unique(pts: PackedVector3Array) -> PackedVector3Array:
	var seen := {}
	var out := PackedVector3Array()
	for p in pts:
		var key := Vector3i(roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0))
		if not seen.has(key):
			seen[key] = true
			out.append(p)
	return out

# ---------- 1. static vs static ----------

## Parts let into what they are mounted on (MOUNT_ALLOW).
const MOUNTED := ["switch bezel", "crank boss", "gauge pod", "door pocket", "mirror", "head unit"]

func _static_vs_static(kind: String) -> void:
	# each solid's own faces, re-read from the shape, probed against the rest
	var poly := (proxy.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D
	var faces := poly.get_faces()
	var by_solid := {}
	for i in faces.size() / 3:
		var s := face_solid[i]
		if not by_solid.has(s):
			by_solid[s] = PackedVector3Array()
		var g: PackedVector3Array = by_solid[s]
		var a := faces[i * 3]
		var b := faces[i * 3 + 1]
		var c := faces[i * 3 + 2]
		g.append(a)
		g.append((a + b + c) / 3.0)
		by_solid[s] = g
	for s in by_solid:
		if cabin_ids.has(s):
			continue   # the cabin's own boxes meet each other on purpose
		if MOUNTED_ASSEMBLY.any(func(m: String) -> bool: return solid_name[s].begins_with(m)):
			continue
		var allow := MOUNT_ALLOW if MOUNTED.any(func(m: String) -> bool: return solid_name[s].begins_with(m)) else MIN_DEPTH
		_probe(kind, solid_name[s], "static", _unique(by_solid[s]), s, allow)

# ---------- 2. glass ----------

func _glass(kind: String, frame: CockpitFrame) -> void:
	if frame.glass == null or not frame.glass.visible:
		_say("%s: no door glass (open car)" % kind)
		return
	var cab: Dictionary = frame.cab
	var door := float(cab.door_x)
	var belt := float(cab.belt_y)
	var card_top := belt - 0.02
	for w in [0.0, 0.25, 0.5, 0.75, 1.0]:
		frame.set_window(w, 0)
		var tris := _pane_tris(frame)
		if tris.is_empty():
			continue
		var grid := PackedVector3Array()
		var worst_in := 0.0   # the pane inboard of the door card's face, below the card's top
		var worst_pt := Vector3.ZERO
		var top := -INF
		var top_pt := Vector3.ZERO
		for t in range(0, tris.size(), 3):
			for i in 9:
				for j in 9 - i:
					var u := float(i) / 8.0
					var v := float(j) / 8.0
					var pnt := tris[t] + (tris[t + 1] - tris[t]) * u + (tris[t + 2] - tris[t]) * v
					grid.append(pnt)
					if pnt.y > top:
						top = pnt.y
						top_pt = pnt
					if pnt.y < card_top and -pnt.x < door:
						var inboard := door + pnt.x
						if inboard > worst_in:
							worst_in = inboard
							worst_pt = pnt
		grid = _unique(grid)
		_probe(kind, "door glass", "window %.2f" % w, grid)
		if w == 1.0 and top > belt:
			findings.append([kind, "door glass", "window 1.00", "air above the belt line (pane still up)", top - belt, 1, grid.size(), top_pt])
		if worst_in > MIN_DEPTH:
			findings.append([kind, "door glass", "window %.2f" % w, "cabin, inboard of the door card face below its top", worst_in, 1, grid.size(), worst_pt])
	frame.set_window(0.0, 0)

## The pane's drawn triangles, frame space (none when it is all in the door).
func _pane_tris(frame: CockpitFrame) -> PackedVector3Array:
	if frame.glass == null or not frame.glass.visible or frame.glass.mesh == null:
		return PackedVector3Array()
	if frame.glass.mesh.get_surface_count() == 0:
		return PackedVector3Array()
	return _faces(frame.glass, frame.global_transform.affine_inverse())

## Points of a probe on both sides of the pane, within it: a sheet cutting
## through a part. Returns the cut depth (the smaller side).
func _pane_cut(frame: CockpitFrame, pts: PackedVector3Array) -> float:
	var tris := _pane_tris(frame)
	if tris.size() < 3:
		return 0.0
	var plane := Plane(tris[0], tris[1], tris[2])
	var pos := 0.0
	var neg := 0.0
	for p in pts:
		var q := plane.project(p)
		var inside := false
		for t in range(0, tris.size(), 3):
			if Geometry3D.ray_intersects_triangle(p - plane.normal, plane.normal, tris[t], tris[t + 1], tris[t + 2]) != null or Geometry3D.ray_intersects_triangle(p + plane.normal, -plane.normal, tris[t], tris[t + 1], tris[t + 2]) != null:
				inside = true
				break
		if not inside:
			continue
		var s := plane.distance_to(p)
		pos = maxf(pos, s)
		neg = maxf(neg, -s)
	return minf(pos, neg)

# ---------- 3. window controls ----------

func _window_controls(kind: String, frame: CockpitFrame, driver: DriverModel) -> void:
	var inv := frame.global_transform.affine_inverse()
	var original := frame.window_control
	for control in ["crank", "switch"]:
		frame.set_window_control(control)
		await process_frame
		if control == "crank":
			_probe(kind, "window crank boss", "static", _points(frame.crank.get_parent().get_node("CrankBoss") as MeshInstance3D, inv), -1, MOUNT_ALLOW)
			# the arm through a full turn, with the pane where the window is
			for i in 12:
				var w := float(i) / 12.0
				frame.set_window(w, 0)
				var arm := frame.crank.get_node("Arm") as MeshInstance3D
				var pts := _points(arm, inv)
				_probe(kind, "crank arm", "window %.2f" % w, pts)
				var cut := _pane_cut(frame, pts)
				if cut >= MIN_DEPTH:
					findings.append([kind, "crank arm", "window %.2f" % w, "door glass (pane cuts it)", cut, 1, pts.size(), pts[0]])
			# the hand on the crank, half way down, where the arm sweeps the pocket
			frame.set_window(0.5, 1)
			driver._start_left(DriverModel.LeftAct.WINDOW_HOLD)
			driver._left_xf = driver._crank_hand_transform()
			driver._place_hands()
			_probe(kind, "left hand on crank", "window 0.5", _hand_points(driver, inv))
		else:
			var parts: Node = frame.window_switch.get_parent()
			for part in ["Switch/Rocker", "SwitchBezel"]:
				_probe(kind, "window switch " + part.get_file().to_lower(), "static", _points(parts.get_node(part) as MeshInstance3D, inv), -1, MOUNT_ALLOW)
			frame.set_window(0.5, 1)
			driver._start_left(DriverModel.LeftAct.WINDOW_HOLD)
			driver._left_xf = driver._switch_hand_transform(1.0)
			driver._place_hands()
			var pts := _hand_points(driver, inv)
			_probe(kind, "left hand on switch", "window 0.5", pts)
			var cut := _pane_cut(frame, pts)
			if cut >= MIN_DEPTH:
				findings.append([kind, "left hand on switch", "window 0.5", "door glass (pane cuts it)", cut, 1, pts.size(), pts[0]])
		frame.set_window(0.0, 0)
	frame.set_window_control(original)
	await process_frame
	driver._start_left(DriverModel.LeftAct.GRIP)
	driver._left_xf = driver._grip_transform(-1)
	driver._place_hands()

## The visible left-hand meshes and anything held, frame space.
func _hand_points(driver: DriverModel, inv: Transform3D, side := -1) -> PackedVector3Array:
	var out := PackedVector3Array()
	var names := ["HandL", "HandLFinger"] if side < 0 else ["HandR"]
	for mi in driver.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var nm := String(m.name)
		if names.has(nm) or (side < 0 and nm.begins_with("HandLHold")):
			out.append_array(_points(m, inv))
	if side < 0 and driver._idle_holding:   # an item standing in the pocket is probed on its own
		for m in [driver.props.vape, driver.props.can, driver.props.cig]:
			var mi := m as MeshInstance3D
			if mi.is_visible_in_tree():
				out.append_array(_points(mi, inv))
				for ch in mi.find_children("*", "MeshInstance3D", true, false):
					if (ch as MeshInstance3D).is_visible_in_tree() and (ch as MeshInstance3D).mesh != null:
						out.append_array(_points(ch, inv))
	return out

# ---------- 4. left hand ----------

func _left_hand(kind: String, frame: CockpitFrame, driver: DriverModel) -> void:
	var inv := frame.global_transform.affine_inverse()
	var grip := driver._grip_transform(-1)
	# flip-off, window shut (hand inside the glass) and open (hand out)
	for open in [false, true]:
		if not open and not driver.has_door_glass():
			continue   # an open car always gestures out over the door (DriverModel._window_is_open)
		frame.set_window(1.0 if open else 0.0, 0)
		driver._gesture_open = open
		for aim in [DriverModel.AIM_AHEAD, DriverModel.AIM_LEFT, DriverModel.AIM_BACK]:
			driver._gesture_aim = aim
			var to := driver._gesture_transform(0.0)
			var label := "flip-off %s aim %d" % ["open" if open else "shut", aim]
			for e in [0.25, 0.5, 0.75]:
				driver._start_left(DriverModel.LeftAct.GESTURE_REACH)
				driver.left_t = DriverModel.GESTURE_REACH_SECS * float(e)
				driver._left_xf = driver._gesture_path(grip, to, float(e))
				driver._place_hands()
				var pts := _hand_points(driver, inv)
				_probe(kind, "left hand", label + " reach %.2f" % e, pts)
				var cut := _pane_cut(frame, pts)
				if cut >= MIN_DEPTH:
					findings.append([kind, "left hand", label + " reach %.2f" % e, "door glass (pane cuts it)", cut, 1, pts.size(), pts[0]])
			for pump in [0.0, 1.0]:
				driver._start_left(DriverModel.LeftAct.GESTURE_HOLD)
				driver._left_xf = driver._gesture_transform(pump)
				driver._place_hands()
				var pts := _hand_points(driver, inv)
				_probe(kind, "left hand (finger)", label + " pump %.0f" % pump, pts)
				var cut := _pane_cut(frame, pts)
				if cut >= MIN_DEPTH:
					findings.append([kind, "left hand (finger)", label + " pump %.0f" % pump, "door glass (pane cuts it)", cut, 1, pts.size(), pts[0]])
	frame.set_window(0.0, 0)
	# idle items: at rest in the pocket, the reach, the lift to the mouth, the sip
	for item in [IdleActions.VAPE, IdleActions.BEER, IdleActions.CIGARETTE]:
		IdleActions.item = item
		driver._idle_item = item
		driver._idle_holding = false
		driver._start_left(DriverModel.LeftAct.GRIP)
		driver._left_xf = grip
		driver._place_hands()
		# the item standing in the pocket
		var rest := PackedVector3Array()
		var mi: MeshInstance3D = {IdleActions.VAPE: driver.props.vape, IdleActions.BEER: driver.props.can, IdleActions.CIGARETTE: driver.props.cig}[item]
		rest.append_array(_points(mi, inv))
		for ch in mi.find_children("*", "MeshInstance3D", true, false):
			if (ch as MeshInstance3D).is_visible_in_tree():
				rest.append_array(_points(ch, inv))
		var pocket_id := -1
		for i in solid_name.size():
			if solid_name[i] == "door pocket":
				pocket_id = i
		_probe(kind, item + " in pocket", "rest", rest)
		var low := INF
		for p in rest:
			low = minf(low, p.y)
		var rim := float(solid_aabb[pocket_id].end.y) if pocket_id >= 0 else 0.0
		_say("%s: %s rests with its bottom %.1f cm %s the pocket rim" % [kind, item, absf(low - rim) * 100.0, "above" if low > rim else "below"])
		if low > rim + 0.005:
			findings.append([kind, item + " in pocket", "rest", "floats above the pocket rim", low - rim, 1, rest.size(), Vector3(0, low, 0)])
		# the reach from the rim to the pocket
		for e in [0.33, 0.66, 1.0]:
			driver._idle_holding = e >= 1.0   # the hand closes round the item as it lands (DriverModel IDLE_REACH)
			driver._start_left(DriverModel.LeftAct.IDLE_REACH if e < 1.0 else DriverModel.LeftAct.IDLE_USE)
			driver._left_xf = driver._idle_reach_transform(grip, driver.props.holder_xf(), float(e))
			driver._place_hands()
			_probe(kind, "left hand", item + " reach %.2f" % e, _hand_points(driver, inv))
		# holding it: lift 0..1 and the sip
		driver._idle_holding = true
		driver._start_left(DriverModel.LeftAct.IDLE_USE)
		for e in [0.2, 0.4, 0.6, 0.8, 1.0]:
			for draw in [0.0, 1.0]:
				if draw > 0.0 and e < 1.0:
					continue
				driver._draw = draw
				driver._left_xf = driver._idle_transform(float(e), draw)
				driver._place_hands()
				var pts := _hand_points(driver, inv)
				_probe(kind, "left hand + " + item, "lift %.1f draw %.0f" % [e, draw], pts)
				var cut := _pane_cut(frame, pts)
				if cut >= MIN_DEPTH:
					findings.append([kind, "left hand + " + item, "lift %.1f draw %.0f" % [e, draw], "door glass (pane cuts it)", cut, 1, pts.size(), pts[0]])
		# the shut-window cloud
		if item != IdleActions.BEER:
			driver.props.exhale(false)
			for i in 40:
				driver.props._process(1.0 / RATE)
			var puff_pts := PackedVector3Array()
			for pr in driver.props.puffs():
				var c: Vector3 = pr[0]
				var r: float = pr[1]
				puff_pts.append(c)
				for d in AXES:
					puff_pts.append(c + (d as Vector3) * r)
			_probe(kind, item + " cloud (window shut)", "0.7 s", puff_pts)
		driver._idle_holding = false
		driver._draw = 0.0
	IdleActions.item = IdleActions.VAPE
	driver._idle_item = IdleActions.VAPE
	driver._start_left(DriverModel.LeftAct.GRIP)
	driver._left_xf = grip
	driver._place_hands()

# ---------- 5. right hand ----------

func _right_hand(kind: String, frame: CockpitFrame, driver: DriverModel) -> void:
	var inv := frame.global_transform.affine_inverse()
	var gears: int = frame.player.gear_ratios.size()
	for g in range(-1, gears + 1):
		frame._apply_lever(frame._slot_of(g))
		driver._hand_xf = driver._lever_hand_transform()
		driver._place_hands()
		_probe(kind, "right hand on knob", "gear %d" % g, _hand_points(driver, inv, 1))
	frame._apply_lever(frame._slot_of(frame.player.gear))
	for deg in [0.0, DriverModel.HANDBRAKE_PULL_DEG]:
		frame.handbrake.rotation_degrees = Vector3(deg, 0.0, 0.0)
		driver._hand_xf = driver._brake_hand_transform()
		driver._place_hands()
		_probe(kind, "right hand on handbrake", "lever at %.0f deg" % deg, _hand_points(driver, inv, 1))
	frame.handbrake.rotation_degrees = Vector3.ZERO
	driver._hand_xf = driver._radio_hand_transform(1.0)
	driver._place_hands()
	_probe(kind, "right hand on head unit", "press", _hand_points(driver, inv, 1))
	driver._hand_xf = driver._grip_transform(1)
	driver._place_hands()

# ---------- 6. lever, handbrake, pedals ----------

func _lever_and_pedals(kind: String, frame: CockpitFrame) -> void:
	var inv := frame.global_transform.affine_inverse()
	var lever_id := -1
	for i in solid_name.size():
		if solid_name[i] == "gear lever":
			lever_id = i
	var gears: int = frame.player.gear_ratios.size()
	frame._apply_lever(frame._slot_of(0))
	var lever_rest := PackedVector3Array()
	for mi in frame.lever.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and mi.is_visible_in_tree():
			lever_rest.append_array(_points(mi, inv))
	for g in range(-1, gears + 1):
		frame._apply_lever(frame._slot_of(g))
		var pts := PackedVector3Array()
		for mi in frame.lever.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh != null and mi.is_visible_in_tree():
				pts.append_array(_points(mi, inv))
		_probe_moved(kind, "gear lever", "gear %d" % g, lever_rest, pts, lever_id)
	frame._apply_lever(frame._slot_of(frame.player.gear))
	var hb_id := -1
	for i in solid_name.size():
		if solid_name[i] == "handbrake":
			hb_id = i
	var hb_rest := PackedVector3Array()
	for mi in frame.handbrake.find_children("*", "MeshInstance3D", true, false):
		hb_rest.append_array(_points(mi, inv))
	frame.handbrake.rotation_degrees = Vector3(DriverModel.HANDBRAKE_PULL_DEG, 0.0, 0.0)
	var hb := PackedVector3Array()
	for mi in frame.handbrake.find_children("*", "MeshInstance3D", true, false):
		hb.append_array(_points(mi, inv))
	_probe_moved(kind, "handbrake", "pulled", hb_rest, hb, hb_id)
	frame.handbrake.rotation_degrees = Vector3.ZERO
	for key in frame.pedals:
		var pivot: Node3D = frame.pedals[key]
		for travel in [0.0, 1.0]:
			pivot.rotation_degrees = Vector3(CockpitFrame.PEDAL_TRAVEL_DEG * float(travel), 0.0, 0.0)
			var pts := PackedVector3Array()
			for mi in pivot.find_children("*", "MeshInstance3D", true, false):
				pts.append_array(_points(mi, inv))
			_probe(kind, String(key) + " pedal", "travel %.0f" % travel, pts)
		pivot.rotation_degrees = Vector3.ZERO

# ---------- 7. trinket and bobble ----------

func _trinket_and_bobble(kind: String, frame: CockpitFrame) -> void:
	var inv := frame.global_transform.affine_inverse()
	var tr: DashTrinket = frame.trinket
	var sw := DashTrinket.SWING_MAX
	var swings := [Vector2(0, 0), Vector2(sw, 0), Vector2(-sw, 0), Vector2(0, sw), Vector2(0, -sw), Vector2(sw, sw), Vector2(-sw, -sw), Vector2(sw, -sw), Vector2(-sw, sw)]
	for id in DashTrinket.IDS:
		if id == DashTrinket.NONE:
			continue
		tr.set_design(id)
		var charm := tr.get_node_or_null("Pivot/Charm") as MeshInstance3D
		if charm == null:
			continue
		for sv in swings:
			tr.phi = (sv as Vector2).x
			tr.psi = (sv as Vector2).y
			tr._apply_pose()
			_probe(kind, "trinket " + id, "swing (%.2f, %.2f)" % [sv.x, sv.y], _points(charm, inv, false))
	tr.set_design(DashTrinket.NONE)
	# the cord ties on under this car's own rear-view mirror, where the coupe's does under its own
	var want: Vector3 = (frame.cab.rear_mirror as Vector3) + COUPE_HANG_FROM_MIRROR
	var off := tr.position.distance_to(want)
	if off > TRINKET_FROM_MIRROR:
		findings.append([kind, "trinket cord", "tie-on", "air, %.0f cm from its own mirror's tie-on point" % (off * 100.0), off, 1, 1, tr.position])
	frame.bobble.set_active(true)
	var t: float = frame.bobble.tilt_max
	var d := t * 0.7071
	var combos := [Vector2(0, 0), Vector2(t, 0), Vector2(-t, 0), Vector2(0, t), Vector2(0, -t), Vector2(d, d), Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d)]
	for id in BobbleFigures.IDS:
		if id == BobbleFigures.NONE:
			continue
		frame.bobble.set_figure(id)
		var mi := frame.bobble.mesh_instance()
		if mi == null:
			continue
		var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var xf := inv * mi.global_transform
		for bob in combos:
			var pts := PackedVector3Array()
			for i in range(0, verts.size(), 3):
				var uv := uvs[i]
				var q := verts[i] - Vector3(0.0, uv.y, 0.0)
				var s: float = (bob as Vector2).x * uv.x
				var f: float = (bob as Vector2).y * uv.x
				q = Vector3(q.x * cos(s) + q.y * sin(s), -q.x * sin(s) + q.y * cos(s), q.z)
				q = Vector3(q.x, q.y * cos(f) - q.z * sin(f), q.z * cos(f) + q.y * sin(f))
				pts.append(xf * (q + Vector3(0.0, uv.y, 0.0)))
			_probe(kind, "bobble " + id, "tilt (%.2f, %.2f)" % [bob.x, bob.y], _unique(pts), -1, MOUNT_ALLOW)
	frame.bobble.set_figure(BobbleFigures.NONE)
	frame.bobble.set_active(false)
