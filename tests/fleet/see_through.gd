extends SceneTree

# See-through and night-look checks (Roy, 2026-10-14: "you need to make a
# test like that"): the rear-view strip showed the road through the tuner's
# trunk, with its tail lamps floating on it (#763), and nothing in the test
# list could have caught it. Headless, every player car booted as the
# player's car, with the geometry the game actually draws:
#
#   mirror   from the rear-view camera (CockpitMirrors: the cabin's rear
#            mirror, looking back) no ray may reach one of the car's own
#            lamp faces, and no ray may leave the car without crossing a
#            face at all. The body is drawn single-sided (cull_back), so the
#            rays only count faces that face the camera, as the renderer
#            does; glass counts from either side (it is see-through on
#            purpose: the world through the rear window is right, the car's
#            own tail lamps are not).
#   outside  from six outside viewpoints (chase, front and rear three-quarter,
#            side, top, low front) every ray aimed at the car's core (a box
#            well inside the body) crosses a face before it gets there: no
#            hole in the shell, no panel facing the wrong way.
#   paint    the body wears CarPaint (sheet or parts variant); on Medium and
#            up it takes the street lamps (#755: seven cars wore the plain
#            shader and read as black blobs at night).
#   lamps    the lamp materials carry the light switch (`lamps`), and the
#            body carries its flare surface with a halo quad per head lamp
#            the car has (body.json for a parts car: the Bug has one tail)
#            and a flare quad per tail lamp (PR #753).
#
# KNOWN lists what the test found on its first run, each with its issue; a
# known failure prints and does not fail, a known one that is fixed fails so
# the line comes out and the issue closes. Never add a line here to make a
# change pass; fix the car.
#
#   godot --headless --audio-driver Dummy --path . -s res://tests/fleet/see_through.gd
# NEON_FIT_CAR=<id> checks one car. NEON_SEE_VERBOSE=1 prints every bad ray.
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
## Rays per mirror view (across x down) and per outside view (targets across
## the core box: x, y, z).
const MIRROR_GRID := Vector2i(13, 5)
const CORE_GRID := Vector3i(5, 3, 7)
## The core box: this share of the body's box, centred (y from 0.3 to 0.8 of
## the height: above the sills, under the roof skin). Over the bonnet and the
## boot, where the skin is lower than the roof, a target is kept CORE_UNDER
## below the skin found by a ray straight down (the top view), so the box
## never pokes out of the body; a column with no skin high enough over it (a
## pickup bed) is left out.
const CORE_XZ := 0.34
const CORE_Y := Vector2(0.3, 0.8)
const CORE_UNDER := 0.2
## Outside viewpoints, car space (-z forward): the game's chase camera, the
## review-shot cameras, straight down, and low at the nose.
const VIEWS := {
	"chase": Vector3(0.0, 1.8, 5.5),
	"front34": Vector3(-3.7, 1.55, -4.9),
	"rear34": Vector3(3.7, 1.55, 4.9),
	"side": Vector3(-7.2, 1.1, 0.0),
	"top": Vector3(0.3, 6.0, 0.2),
	"low_front": Vector3(0.6, 0.45, -6.0),
}
## Test collision layer for the car's faces (the game's own layers are low).
const LAYER_SOLID := 1 << 19
const LAYER_GLASS := 1 << 20
const LAYER_GLOW := 1 << 21
const OFFSET := Vector3(0.0, 800.0, 0.0)

## car -> {check: issue}
const KNOWN := {
	# #763: the rear-view camera sits inside the cabin and the body is drawn
	# single-sided, so the rear deck and trunk are not there from the inside;
	# every car's mirror strip shows the road behind through the car.
	"p0_beater": {"mirror_hole": 763},
	"p1_coupe": {"mirror_hole": 763},
	"p2_hothatch": {"mirror_hole": 763},
	"p7_wagon": {"mirror_hole": 763},
	"p3_tuner": {"mirror_hole": 763},
	"p4_kei": {"mirror_hole": 763},
	"p5_muscle": {"mirror_hole": 763},
	"p6_crossover": {"mirror_hole": 763},
	"p17_work_pickup": {"mirror_hole": 763},
	"p8_driftcoupe": {"mirror_hole": 763},
	"p10_truck": {"mirror_hole": 763},
	"m1_monster": {"mirror_hole": 763},
	"l1_lowrider": {"mirror_hole": 763},
}

var fails := 0
var logger := Harness.ErrorCounter.new()
var _seen := {}
var _verbose := false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

## A counted problem (0 = none): fails unless KNOWN lists it, and fails when
## a KNOWN one has gone (fixed: take it out).
func _count(car: String, check: String, bad: int, what: String) -> void:
	var issue: int = int((KNOWN.get(car, {}) as Dictionary).get(check, 0))
	if issue == 0:
		_check(bad == 0, "%s: %s" % [car, what])
		return
	_seen[car + "|" + check] = true
	if bad == 0:
		_check(false, "%s %s is fixed: take it out of KNOWN and close #%d" % [car, check, issue])
	else:
		print("  known #%d: %s: %s" % [issue, car, what])

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_verbose = OS.get_environment("NEON_SEE_VERBOSE") == "1"
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		var car := String(k.id)
		if only != "" and car != only:
			continue
		await _car_checks(car)
	OS.set_environment("NEON_CAR", "")
	for car in KNOWN:
		if only != "" and car != only:
			continue
		for check in KNOWN[car]:
			_check(_seen.has(car + "|" + check), "%s %s is in KNOWN but was not measured" % [car, check])
	_check(logger.errors.is_empty(), "%d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
	print("see_through: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _car_checks(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	var game := Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	if p == null or p.chassis_visual == null or cam == null:
		_check(false, "%s: the game should boot with the car" % kind)
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	for i in RATE:
		await physics_frame
	var vis := p.chassis_visual
	var body := vis.get_node_or_null(^"Body") as MeshInstance3D
	_check(body != null, "%s: no Body" % kind)
	if body == null:
		game.queue_free()
		await process_frame
		return
	var car_xf := vis.global_transform
	var inv := car_xf.affine_inverse()

	# ---- the faces the game draws, car space, sorted by how they are drawn
	var solid := PackedVector3Array()   # single-sided: body, trim, wheels, cabin pieces the mirror sees
	var glass := PackedVector3Array()   # two-sided for the test
	var glow := PackedVector3Array()    # the lamps
	var box := AABB()
	var first := true
	var nodes: Array = [vis]
	if cam.frame != null:
		nodes.append(cam.frame)
	for root_node in nodes:
		for n in root_node.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			if root_node != vis and (mi.layers & CockpitFrame.MIRROR_ONLY_BIT) == 0:
				continue   # cabin pieces only count where the mirror draws them
			var to_car := inv * mi.global_transform
			var mesh := mi.mesh
			for s in mesh.get_surface_count():
				var sname := (mesh as ArrayMesh).surface_get_name(s) if mesh is ArrayMesh else ""
				if sname == CarAssembler.FLARE_SURFACE:
					continue   # camera-facing quads, sized by the shader
				var arrays := mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				var faces := PackedVector3Array()
				if idx != null and (idx as PackedInt32Array).size() > 0:
					for i in (idx as PackedInt32Array):
						faces.append(to_car * verts[i])
				else:
					for v in verts:
						faces.append(to_car * v)
				var into := solid
				if sname == "glass" or _is_glass(mi, s):
					into = glass
				elif sname == "glow":
					into = glow
				into.append_array(faces)
				if root_node == vis:
					for v in faces:
						if first:
							box = AABB(v, Vector3.ZERO)
							first = false
						else:
							box = box.expand(v)
	for w in p.wheel_array:
		if w.wheel_node == null:
			continue
		for n in w.wheel_node.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var to_car := inv * mi.global_transform
			for v in mi.mesh.get_faces():
				solid.append(to_car * v)
	_check(solid.size() >= 300 and glow.size() >= 6, "%s: %d solid and %d lamp vertices (expected a body and lamps)" % [kind, solid.size(), glow.size()])
	if _verbose:
		var gb := AABB()
		for i in glow.size():
			gb = AABB(glow[i], Vector3.ZERO) if i == 0 else gb.expand(glow[i])
		print("  %s body box %s, lamps box %s, %d glass vertices" % [kind, box, gb, glass.size()])
	var bodies := [_shape(solid, false, LAYER_SOLID), _shape(glass, true, LAYER_GLASS), _shape(glow, false, LAYER_GLOW)]
	# A sheet car's lamps are drawn from both sides (GLOW_SHADER cull_disabled);
	# a parts car's from the front only.
	(bodies[2].get_child(0) as CollisionShape3D).shape.backface_collision = not NpcCarBuilder.uses_parts(String(vis.get_meta("kind", kind)))
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state

	# ---- mirror: the rear-view camera must not see the car's own lamps or through the shell
	var mirror_pos := CockpitMirrors.REAR_POS
	var mirror_fov := CockpitMirrors.REAR_FOV
	if cam.frame != null and cam.frame.mirrors != null and not cam.frame.mirrors.views.is_empty():
		var v: Dictionary = cam.frame.mirrors.views[0]
		mirror_pos = (v.local as Transform3D).origin
		mirror_fov = (v.cam as Camera3D).fov
	elif cam.frame != null and cam.frame.cab.has("rear_mirror"):
		mirror_pos = cam.frame.cab.rear_mirror
	var aspect := float(CockpitMirrors.REAR_SIZE.x) / float(CockpitMirrors.REAR_SIZE.y)
	var half_v := deg_to_rad(mirror_fov * 0.5)
	var half_h := atan(tan(half_v) * aspect)
	var pitch := deg_to_rad(CockpitMirrors.REAR_PITCH)
	if _verbose:
		print("  %s mirror at %s, fov %.1f" % [kind, mirror_pos, mirror_fov])
	var lamps_seen := 0
	var holes := 0
	var mirror_rays := 0
	for iy in MIRROR_GRID.y:
		for ix in MIRROR_GRID.x:
			var yaw := lerpf(-half_h, half_h, (ix + 0.5) / MIRROR_GRID.x)
			var up := pitch + lerpf(half_v, -half_v, (iy + 0.5) / MIRROR_GRID.y)
			var dir := Vector3(sin(yaw) * cos(up), sin(up), cos(yaw) * cos(up))   # +z = the car's rear
			var exit := _exit(box.grow(0.05), mirror_pos, dir)
			if exit <= 0.0:
				continue
			mirror_rays += 1
			var hit_solid := _ray(space, mirror_pos, dir, exit, LAYER_SOLID)
			var hit_glass := _ray(space, mirror_pos, dir, exit, LAYER_GLASS)
			var hit_glow := _ray(space, mirror_pos, dir, exit, LAYER_GLOW)
			var nearest := minf(hit_solid, hit_glass)
			if hit_glow < nearest:
				lamps_seen += 1
				if _verbose:
					print("  %s mirror ray %d,%d sees a lamp at %.2f m" % [kind, ix, iy, hit_glow])
			elif nearest == INF and _face(space, mirror_pos, dir, exit) == INF:
				holes += 1
				if _verbose:
					print("  %s mirror ray %d,%d leaves the car with no face (dir %s)" % [kind, ix, iy, dir])
	_count(kind, "mirror_lamps", lamps_seen, "the rear-view mirror sees the car's own tail lamps (%d of %d rays)" % [lamps_seen, mirror_rays])
	_count(kind, "mirror_hole", holes, "the rear-view mirror looks out through the shell with no face in the way (%d of %d rays)" % [holes, mirror_rays])

	# ---- outside: every ray to the core crosses a face first
	var core := AABB(
		Vector3(box.position.x + box.size.x * (0.5 - CORE_XZ), box.position.y + box.size.y * CORE_Y.x, box.position.z + box.size.z * (0.5 - CORE_XZ)),
		Vector3(box.size.x * 2.0 * CORE_XZ, box.size.y * (CORE_Y.y - CORE_Y.x), box.size.z * 2.0 * CORE_XZ))
	if OS.get_environment("NEON_SEE_PROBE") == "1":
		# A 2 cm map of the skin seen from above: where the core box is, a
		# miss is a hole. Prints the misses over the core box only.
		var step := 0.02
		var misses := 0
		var x := core.position.x
		while x <= core.end.x:
			var z := core.position.z
			while z <= core.end.z:
				var from := Vector3(x, box.end.y + 1.0, z)
				var reach := from.y - core.position.y
				var hit := _face(space, from, Vector3.DOWN, reach)
				if hit == INF:
					misses += 1
					if misses <= 200:
						print("  %s probe: open from above at x %.2f z %.2f" % [kind, x, z])
				z += step
			x += step
		print("  %s probe: %d open cells over the core" % [kind, misses])

	# The body's skin height over each (x, z) column of the core grid: a ray
	# straight down from above. A column with no skin at all is a hole in the
	# roof, bonnet or boot (or a panel wound inside out) seen from above.
	var see_in := 0
	var rays := 0
	var tops := {}
	for iz in CORE_GRID.z:
		for ix in CORE_GRID.x:
			var cx := core.position.x + core.size.x * (ix + 0.5) / CORE_GRID.x
			var cz := core.position.z + core.size.z * (iz + 0.5) / CORE_GRID.z
			var from := Vector3(cx, box.end.y + 1.0, cz)
			var reach := from.y - core.position.y
			rays += 1
			var hit := _face(space, from, Vector3.DOWN, reach)
			if hit == INF:
				see_in += 1
				tops[Vector2i(ix, iz)] = -INF
				if _verbose:
					print("  %s: nothing over the core at x %.2f z %.2f (open from above)" % [kind, cx, cz])
			else:
				tops[Vector2i(ix, iz)] = from.y - hit
	for view in VIEWS:
		var from: Vector3 = VIEWS[view]
		for iz in CORE_GRID.z:
			for iy in CORE_GRID.y:
				for ix in CORE_GRID.x:
					var target := core.position + Vector3(
						core.size.x * (ix + 0.5) / CORE_GRID.x,
						core.size.y * (iy + 0.5) / CORE_GRID.y,
						core.size.z * (iz + 0.5) / CORE_GRID.z)
					var top: float = tops[Vector2i(ix, iz)]
					if top - CORE_UNDER < core.position.y:
						continue   # no body over this column (a pickup bed)
					target.y = minf(target.y, top - CORE_UNDER)
					var d := target - from
					var dist := d.length()
					var dir := d / dist
					rays += 1
					var nearest := _face(space, from, dir, dist)
					if nearest == INF:
						see_in += 1
						if _verbose:
							print("  %s %s view reaches the core at %s with no face" % [kind, view, target])
	_count(kind, "shell", see_in, "the shell has holes or inside-out panels: %d of %d rays from outside reach the core" % [see_in, rays])

	# ---- paint: CarPaint, with the street lamps on Medium and up
	var paint_mat := vis.get_meta("body_mat") as ShaderMaterial if vis.has_meta("body_mat") else null
	if paint_mat == null:
		var bi := CarPaint_surface(body.mesh as ArrayMesh, "body")
		paint_mat = body.get_active_material(bi) as ShaderMaterial if bi >= 0 else null
	var paint_ok := paint_mat != null and (paint_mat.shader == CarPaint.body_shader(true) or paint_mat.shader == CarPaint.body_shader(false) or paint_mat.shader == CarPaint.parts_body_shader())
	_check(paint_ok, "%s: the body is not painted by CarPaint (%s)" % [kind, paint_mat.shader.resource_path if paint_mat != null and paint_mat.shader != null else "no material"])
	if paint_ok and CarPaint.tier() >= CarPaint.TIER_MEDIUM:
		_check(paint_mat.shader.code.contains("#define LAMPS"), "%s: the paint has no street-lamp light at tier %d" % [kind, CarPaint.tier()])

	# ---- lamps: the switch on the lamp materials, a halo and a flare per side
	var mesh := body.mesh as ArrayMesh
	var gi := CarPaint_surface(mesh, "glow")
	var glow_mat := body.get_active_material(gi) as ShaderMaterial if gi >= 0 else null
	_check(glow_mat != null and glow_mat.shader.code.contains("instance uniform float lamps"), "%s: the lamp glow has no light switch" % kind)
	var fi := CarPaint_surface(mesh, "flare")
	var heads := 0
	var tails := 0
	if fi >= 0:
		var normals: PackedVector3Array = mesh.surface_get_arrays(fi)[Mesh.ARRAY_NORMAL]
		for i in range(0, normals.size(), 6):
			if normals[i].z < 0.0:
				heads += 1
			else:
				tails += 1
		var fmat := body.get_active_material(fi) as ShaderMaterial
		_check(fmat != null and fmat.shader.code.contains("instance uniform float lamps") and fmat.shader.code.contains("halo_r"), "%s: the flare material has no light switch or no halo" % kind)
	# A parts car's body.json says which lamps it has (the Bug has one working
	# tail lamp, the other is a rusted socket); a sheet car always has a pair.
	var want_heads := 2
	var want_tails := 2
	var json_path := "res://assets/cars/%s/body.json" % kind
	if NpcCarBuilder.uses_parts(kind) and FileAccess.file_exists(json_path):
		var car: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if car is Dictionary and car.has("lamps"):
			want_heads = (car.lamps.get("head", {}) as Dictionary).size()
			want_tails = (car.lamps.get("tail", {}) as Dictionary).size()
	_check(heads == want_heads and tails == want_tails, "%s: want a halo quad per head lamp (%d) and a flare quad per tail lamp (%d), got %d halos and %d flares" % [kind, want_heads, want_tails, heads, tails])

	for b in bodies:
		b.queue_free()
	game.queue_free()
	await process_frame
	await process_frame

static func CarPaint_surface(mesh: ArrayMesh, sname: String) -> int:
	if mesh == null:
		return -1
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == sname:
			return i
	return -1

## A sheet body's glass is a surface named "glass"; a cabin window piece or
## any other mesh whose material is CarPaint's glass shader counts too.
static func _is_glass(mi: MeshInstance3D, s: int) -> bool:
	var m := mi.get_active_material(s) as ShaderMaterial
	return m != null and (m.shader == CarPaint.glass_shader(true) or m.shader == CarPaint.glass_shader(false))

func _shape(faces: PackedVector3Array, two_sided: bool, layer: int) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = two_sided
	sh.set_faces(faces if faces.size() >= 3 else PackedVector3Array([Vector3(0, -900, 0), Vector3(1, -900, 0), Vector3(0, -900, 1)]))
	cs.shape = sh
	sb.add_child(cs)
	sb.position = OFFSET
	root.add_child(sb)
	return sb

## Distance to the nearest drawn face of any kind (body, glass or lamp), INF
## for none. A ray that threads the exact seam between two triangles can slip
## through Godot's triangle test, so a miss is tried twice more from 5 mm to
## either side: a real hole lets all three through, a seam lets none.
func _face(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_d: float) -> float:
	var d := _face_once(space, from, dir, max_d)
	if d < INF:
		return d
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized() * 0.005
	for off in [side, dir.cross(side).normalized() * 0.005]:
		d = _face_once(space, from + off, dir, max_d)
		if d < INF:
			return d
	return INF

func _face_once(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_d: float) -> float:
	return minf(_ray(space, from, dir, max_d, LAYER_SOLID), minf(_ray(space, from, dir, max_d, LAYER_GLASS), _ray(space, from, dir, max_d, LAYER_GLOW)))

## Distance along the ray (car space) to the nearest face on `layer`, INF for none.
func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_d: float, layer: int) -> float:
	var q := PhysicsRayQueryParameters3D.create(from + OFFSET, from + OFFSET + dir * max_d, layer)
	q.hit_back_faces = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return ((hit.position as Vector3) - OFFSET - from).length()

## Where a ray from inside `box` leaves it (distance), 0 if it starts outside.
static func _exit(box: AABB, from: Vector3, dir: Vector3) -> float:
	if not box.has_point(from):
		return 0.0
	var t := INF
	for axis in 3:
		if absf(dir[axis]) < 1e-6:
			continue
		var face := box.end[axis] if dir[axis] > 0.0 else box.position[axis]
		t = minf(t, (face - from[axis]) / dir[axis])
	return t
