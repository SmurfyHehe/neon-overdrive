extends SceneTree
# Sight line, every player car (Roy, 2026-10-10; the rule of 2026-10-06 was
# only ever checked on the coupe, tests/view/cockpit_interior.gd): from the
# cockpit eye, nothing in the cabin may stand above the line 8 degrees below
# eye level within 20 degrees either side of straight ahead, except the
# steering wheel's rim. So the dash top, the cluster, the gauges, the boost
# pod, the hands at rest and the trinket all stay out of the road band.
# The windscreen pillars are the body's own frame, not something fitted in
# the cabin: where a narrow car's pillar reaches inside 20 degrees it is
# printed as a note, not failed (PILLAR_R round the car's a_pillar line).
#
# Each car boots as the player's car (NEON_CAR) in the cockpit view, at rest,
# wheel straight, with the bolt-on boost pod fitted (any car can get one from
# its first boost setup). Rays leave the cockpit camera's eye (the car's
# CABIN.eye moved up and forward, CabinSpec.arcade_eye, #737) across
# yaw -20..+20 and pitch -8..+8 degrees (above +8 is the header's and the
# rear-view mirror's business, not the road's) and are tested against every
# visible, solid cabin, driver and pod triangle.
#
# Prints one line per part that blocks the band: how many rays, the highest
# and lowest blocked pitch and the yaw span, so the car's CABIN can be fixed
# from the numbers. Exit code 1 on failure.
#
# NEON_FIT_CAR=p5_muscle limits the run to one car. NEON_FIT_REPORT=1 prints
# the band as a map (a row per half degree of pitch, a column per degree of
# yaw, a letter per part: '.' clear, 'p' pillar).
# Run: <godot> --headless --audio-driver Dummy --path . -s res://tests/fleet/sight_line.gd
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
const YAW_MAX := 20.0
const PITCH_LOW := -8.0
const PITCH_HIGH := 8.0
const YAW_STEP := 1.0
const PITCH_STEP := 0.5
## The rim: WheelBody triangles this far from the hub or more (the spokes and
## the hub are inside it and do count).
const RIM_INNER := 0.13
## A hit this close to the pillar trim's centre line (CockpitFrame builds it
## from the car's a_pillar, tucked in from the skin) is the pillar.
const PILLAR_R := 0.07

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
		await _sight(String(k.id))
	OS.set_environment("NEON_CAR", "")
	if logger.errors.size() > 0:
		print("FAIL %d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += logger.errors.size()
	print("sight_line: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _sight(kind: String) -> void:
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
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	if frame.pod == null:
		frame.pod = GaugePod.new(kind, 1.0)
		frame.add_child(frame.pod)
	for i in RATE:
		await physics_frame
	var eye := CabinSpec.arcade_eye(frame.cab)   # where the cockpit camera sits (#737): what the player sees
	var to_car := p.global_transform.affine_inverse()
	var wheel_inv: Transform3D = (to_car * frame.wheel.global_transform).affine_inverse()
	var yaw_lim := deg_to_rad(YAW_MAX)
	var blocked := {}   # part path -> [rays, highest pitch, lowest pitch, yaw min, yaw max]
	var pillar_rays := 0
	var pillar_yaw := INF   # the smallest |yaw| a pillar reaches
	var rows := {}      # pitch -> the map row
	var foot: Vector3 = frame.cab.a_pillar[0]
	var top: Vector3 = frame.cab.a_pillar[1]
	var rays := 0
	var tris := 0
	# Triangles that can reach the band at all (by the angles of their corners,
	# with a margin), per part, so the ray loop is short.
	var parts := {}
	for m in frame.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _see_through(mi):
			continue   # the head and torso are hidden in the cockpit view; glass is clear
		var xf: Transform3D = to_car * mi.global_transform
		var faces := mi.mesh.get_faces()
		var keep := PackedVector3Array()
		var t := 0
		while t + 2 < faces.size():
			var a := xf * faces[t]
			var b := xf * faces[t + 1]
			var c := xf * faces[t + 2]
			t += 3
			if _may_reach(eye, a, b, c):
				keep.append(a)
				keep.append(b)
				keep.append(c)
		if keep.size() > 0:
			parts[String(frame.get_path_to(mi))] = [mi, keep]
			tris += keep.size() / 3
	var yaw := -YAW_MAX
	while yaw <= YAW_MAX + 0.001:
		var pitch := PITCH_LOW
		while pitch <= PITCH_HIGH + 0.001:
			rays += 1
			var mark := "."
			var dir := Vector3(0, 0, -1).rotated(Vector3.RIGHT, deg_to_rad(pitch)).rotated(Vector3.UP, -deg_to_rad(yaw))
			for path in parts:
				var mi: MeshInstance3D = parts[path][0]
				var keep: PackedVector3Array = parts[path][1]
				var hit_part := false
				var t := 0
				while t + 2 < keep.size() and not hit_part:
					var hit = Geometry3D.ray_intersects_triangle(eye, dir, keep[t], keep[t + 1], keep[t + 2])
					t += 3
					if hit == null:
						continue
					if mi.name == "WheelBody":
						var local: Vector3 = wheel_inv * hit
						if Vector2(local.x, local.y).length() >= RIM_INNER:
							continue   # the rim is allowed
					var on_pillar := false
					for sx in [-1.0, 1.0]:
						var q: Vector3 = Geometry3D.get_closest_point_to_segment(hit, Vector3(sx * (foot.x - 0.04), foot.y, foot.z + 0.02), Vector3(sx * (top.x - 0.13), top.y - 0.09, top.z + 0.03))
						on_pillar = on_pillar or q.distance_to(hit) < PILLAR_R
					if on_pillar:
						pillar_rays += 1
						pillar_yaw = minf(pillar_yaw, absf(yaw))
						if mark == ".":
							mark = "p"
						break
					hit_part = true
				if hit_part:
					mark = String(path).get_file().left(1).to_upper()
					if not blocked.has(path):
						blocked[path] = [0, pitch, pitch, yaw, yaw]
					var e: Array = blocked[path]
					e[0] += 1
					e[1] = maxf(e[1], pitch)
					e[2] = minf(e[2], pitch)
					e[3] = minf(e[3], yaw)
					e[4] = maxf(e[4], yaw)
			rows[pitch] = String(rows.get(pitch, "")) + mark
			pitch += PITCH_STEP
		yaw += YAW_STEP
	print("%s: eye %s, %d rays, %d triangles near the band, %d parts in it" % [kind, str(eye), rays, tris, blocked.size()])
	if report:
		var keys := rows.keys()
		keys.sort()
		keys.reverse()
		for k in keys:
			print("  %+5.1f %s" % [k, rows[k]])
	if pillar_rays > 0:
		print("  note: a windscreen pillar reaches in to %.0f degrees of yaw (%d rays), not counted" % [pillar_yaw, pillar_rays])
	for path in blocked:
		var e: Array = blocked[path]
		print("  BLOCKS %-34s %4d rays, pitch %+.1f..%+.1f deg, yaw %+.0f..%+.0f deg" % [path, e[0], e[2], e[1], e[3], e[4]])
	_check(blocked.is_empty(), "%s: %d cabin parts stand in the road band: %s" % [kind, blocked.size(), str(blocked.keys())])
	# The boost pod's two faces: the eye sees both (nothing of the cabin, the
	# pillar included, in front of a face's centre or its rim).
	var pod_xf: Transform3D = to_car * frame.pod.global_transform
	var hidden := []
	for c in frame.pod.gauge_centres():
		for off in [Vector3.ZERO, Vector3(GaugePod.GAUGE_R, 0, 0), Vector3(-GaugePod.GAUGE_R, 0, 0), Vector3(0, GaugePod.GAUGE_R, 0), Vector3(0, -GaugePod.GAUGE_R, 0)]:
			var target: Vector3 = pod_xf * (c + off)
			var by := _occluder(frame, to_car, eye, target)
			if by != "" and not hidden.has(by):
				hidden.append(by)
	_check(hidden.is_empty(), "%s: the boost pod's faces are hidden from the eye by %s" % [kind, str(hidden)])
	game.queue_free()
	await process_frame
	await process_frame

## The cabin part between the eye and a point on the pod, or "".
func _occluder(frame: CockpitFrame, to_car: Transform3D, eye: Vector3, target: Vector3) -> String:
	var dist := eye.distance_to(target)
	var dir := (target - eye) / dist
	for m in frame.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _see_through(mi) or frame.pod.is_ancestor_of(mi):
			continue
		var xf: Transform3D = to_car * mi.global_transform
		var faces := mi.mesh.get_faces()
		var t := 0
		while t + 2 < faces.size():
			var hit = Geometry3D.ray_intersects_triangle(eye, dir, xf * faces[t], xf * faces[t + 1], xf * faces[t + 2])
			t += 3
			if hit != null and eye.distance_to(hit) < dist - 0.003:
				return String(frame.get_path_to(mi))
	return ""

## Whether a triangle's corners come anywhere near the band, by their angles
## from the eye (a few degrees of margin; a triangle behind the eye is out).
func _may_reach(eye: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var yaw_lo := INF
	var yaw_hi := -INF
	var pitch_lo := INF
	var pitch_hi := -INF
	for v in [a, b, c]:
		var d: Vector3 = v - eye
		if d.z > -0.02:
			return d.length() < 0.6   # beside or behind the eye: only a near, large part could matter
		var yw := rad_to_deg(atan2(d.x, -d.z))
		var pt := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
		yaw_lo = minf(yaw_lo, yw)
		yaw_hi = maxf(yaw_hi, yw)
		pitch_lo = minf(pitch_lo, pt)
		pitch_hi = maxf(pitch_hi, pt)
	return yaw_hi >= -YAW_MAX - 1.0 and yaw_lo <= YAW_MAX + 1.0 and pitch_hi >= PITCH_LOW - 1.0 and pitch_lo <= PITCH_HIGH + 1.0

static func _see_through(mi: MeshInstance3D) -> bool:
	var m := mi.material_override
	if m == null and mi.mesh.get_surface_count() > 0:
		m = mi.mesh.surface_get_material(0)
	return m is StandardMaterial3D and (m as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
