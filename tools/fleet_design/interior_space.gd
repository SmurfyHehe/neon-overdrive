extends SceneTree
# Cabin space audit (2026-10-09, Roy: "make sure that we actually have space
# in the interior", and "different body types, different heights"). Boots
# every player car as the player's car, builds collision proxies of the real
# body shell (all of it, and its opaque part without the glass) and of the
# real cabin (every CockpitFrame mesh except the driver), then sits a scaled
# manikin (tools/fleet_design/manikin.gd) of each stature in STATURES on the
# driver's seat and ray-tests it, headless:
#   headroom      cushion top to the roof liner and to the roof skin, against the head
#   shoulder room cabin width at shoulder height, against the shoulders
#   hip room      width at the hips (the seat's bolsters, or the door and console)
#   legs          hip to the throttle pedal against thigh + shin; where the knee lands
#   knee room     the knee to the wheel rim / dash underside above it
#   arms          shoulder to the wheel's 9 and 3 grips and to the gear knob
#   sightline     the clear band through the windshield from that stature's eye
#   rear          cabin length behind the front seatback, roof over a rear seat
#   strut bar     room between the seatback top and the rear bulkhead
# and reports the game's own DriverModel (its head top, as an equivalent
# stature). Works on a build where the cabin comes from CabinSpec (per-car
# CABIN) and on the older one where every car gets the coupe's cabin offset by
# PlayerCars.cabin_offset. Prints one block per car and writes
# user://interior_space/<kind>.json.
#
#   <godot> --headless --audio-driver Dummy --path . -s res://tools/fleet_design/interior_space.gd
#   NEON_FIT_CAR=p4_kei limits it to one car.
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Manikin := preload("res://tools/fleet_design/manikin.gd")

const RATE := 60
const STATURES := [1.55, 1.78, 1.95]
const SHELL_LAYER := 1 << 19      # the whole body, glass included
const OPAQUE_LAYER := 1 << 20     # the body without its glass surfaces
const CABIN_LAYER := 1 << 21      # the cabin's meshes
const BASE := Vector3(0.0, 500.0, 0.0)
const REACH := 4.0
const FOV_V := 62.0               # the cockpit camera's vertical FOV

var game: Node
var space: PhysicsDirectSpaceState3D
var logger := Harness.ErrorCounter.new()
var results := {}

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		if only != "" and String(k.id) != only:
			continue
		await _audit(String(k.id))
	OS.set_environment("NEON_CAR", "")
	var dir := ProjectSettings.globalize_path("user://interior_space")
	DirAccess.make_dir_recursive_absolute(dir)
	for kind in results:
		var f := FileAccess.open("%s/%s.json" % [dir, kind], FileAccess.WRITE)
		f.store_string(JSON.stringify(results[kind], "  "))
		f.close()
	print("interior_space: wrote %d cars to %s" % [results.size(), dir])
	if logger.errors.size() > 0:
		print("engine errors: %s" % str(logger.errors.slice(0, 5)))
	quit(0)

func _audit(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	if p == null or cam == null or cam.frame == null:
		print("%s: no cockpit frame" % kind)
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 0.0
		c.steering_input = 0.0
	cam.set_view(ChaseCamera.View.CHASE)   # the driver's head and torso are drawn in the chase view
	for i in RATE:
		await physics_frame
	var inv := p.global_transform.affine_inverse()
	var frame: CockpitFrame = cam.frame
	# Proxies.
	var shell := PackedVector3Array()
	var opaque := PackedVector3Array()
	for mi in p.chassis_visual.find_children("*", "MeshInstance3D", true, false):
		if _under(mi, Undercarriage.NODE_NAME) or mi.name == Undercarriage.PLATE_NAME:
			continue
		shell.append_array(_faces(mi, inv))
		opaque.append_array(_faces(mi, inv, true))
	var cabin := PackedVector3Array()
	var driver: DriverModel = frame.driver
	for mi in frame.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or (driver != null and _under(mi, driver.name)):
			continue
		var path := String(frame.get_path_to(mi))
		if path == "Mirrors/LeftGlass" or path == "Mirrors/RightGlass" or path.ends_with("BlindSpotDot"):
			continue
		cabin.append_array(_faces(mi, inv))
	_proxy(shell, SHELL_LAYER)
	_proxy(opaque, OPAQUE_LAYER)
	_proxy(cabin, CABIN_LAYER)
	await physics_frame
	await physics_frame
	space = root.get_world_3d().direct_space_state
	# The seat.
	var seat_x: float
	var seat_z: float
	var eye: Vector3 = cam.eye
	var open_top := false
	if "cab" in frame and frame.cab is Dictionary and not frame.cab.is_empty():
		seat_x = float(frame.cab.seat_x)
		seat_z = float(frame.cab.seat_z)
		open_top = bool(frame.cab.open_top)
	else:
		# the coupe's cabin, moved by the frame's own offset in car space
		var off: Vector3 = (inv * frame.global_transform).origin
		seat_x = CockpitFrame.SEAT_X + off.x
		seat_z = 0.36 + off.z
	var cushion := _hit(Vector3(seat_x, eye.y - 0.25, seat_z), Vector3.DOWN, CABIN_LAYER)
	var cushion_y: float = cushion.y if cushion.y > -INF else eye.y - 0.62
	var floor_y := _hit(Vector3(seat_x, cushion_y - 0.12, seat_z), Vector3.DOWN, CABIN_LAYER | SHELL_LAYER).y
	# The parts the arms and legs reach.
	var pedal: Node3D = frame.pedals.get("throttle")
	var pedal_pos: Vector3 = inv * pedal.global_position if pedal != null else Vector3.INF
	var hub: Vector3 = inv * frame.wheel_mount.global_position
	var hub_basis: Basis = (inv * frame.wheel_mount.global_transform).basis
	var knob_node: Node3D = frame.find_child("Knob", true, false)
	var knob: Vector3 = inv * knob_node.global_position if knob_node != null else Vector3.INF
	var rim_r := 0.18
	if "wheel" in frame and frame.wheel != null and "RIM_RADIUS" in frame.wheel:
		rim_r = float(frame.wheel.RIM_RADIUS)
	var grip_l := hub + hub_basis * Vector3(-rim_r, 0.0, 0.0)
	var grip_r := hub + hub_basis * Vector3(rim_r, 0.0, 0.0)
	# The game's own driver.
	var built := {}
	if driver != null:
		var head_mesh: MeshInstance3D = driver.find_child("HeadMesh", true, false)
		if head_mesh != null:
			var top := -INF
			for v in _faces(head_mesh, inv):
				top = maxf(top, v.y)
			built["head_top_over_cushion"] = top - cushion_y
			built["equivalent_stature"] = (top - cushion_y) / Manikin.fractions().head_top
		var pelvis: Vector3 = driver.get("pelvis") if driver.get("pelvis") != null else DriverModel.PELVIS + (inv * frame.global_transform).origin
		built["pelvis_over_cushion"] = pelvis.y - cushion_y
		built["thigh_shin"] = DriverModel.THIGH + DriverModel.SHIN
		if pedal_pos.is_finite():
			built["hip_to_pedal"] = (pedal_pos + Vector3(0.0, -0.12, 0.05) - pelvis).length()
	# Fixed facts of the cabin.
	var roof_liner := _hit(Vector3(seat_x, cushion_y + 0.30, seat_z + Manikin.HIP_AHEAD), Vector3.UP, CABIN_LAYER).y
	var roof_skin := _hit(Vector3(seat_x, cushion_y + 0.30, seat_z + Manikin.HIP_AHEAD), Vector3.UP, SHELL_LAYER).y
	var hip_l := _dist(Vector3(seat_x, cushion_y + 0.10, seat_z), Vector3.LEFT, CABIN_LAYER | SHELL_LAYER)
	var hip_r := _dist(Vector3(seat_x, cushion_y + 0.10, seat_z), Vector3.RIGHT, CABIN_LAYER | SHELL_LAYER)
	var behind := Vector3(seat_x, cushion_y + 0.12, seat_z + 0.36)   # just behind the front seatback
	var rear_len := _dist(behind, Vector3.BACK, CABIN_LAYER | SHELL_LAYER)
	var rear_roof := _hit(behind + Vector3(0.0, 0.0, 0.55), Vector3.UP, CABIN_LAYER | SHELL_LAYER).y
	var rear_floor := _hit(behind + Vector3(0.0, 0.0, 0.55), Vector3.DOWN, CABIN_LAYER | SHELL_LAYER).y
	var strut_gap := _dist(Vector3(0.0, cushion_y + 0.58, seat_z + 0.34), Vector3.BACK, CABIN_LAYER | SHELL_LAYER)
	var r := {
		"kind": kind, "seat_x": seat_x, "seat_z": seat_z, "cushion_y": cushion_y, "floor_y": floor_y,
		"cushion_over_floor": cushion_y - floor_y, "open_top": open_top,
		"roof_liner_over_cushion": roof_liner - cushion_y, "roof_skin_over_cushion": roof_skin - cushion_y,
		"hip_width": hip_l + hip_r, "hip_left": hip_l, "hip_right": hip_r,
		"pedal": pedal_pos, "hub": hub, "knob": knob,
		"seat_to_pedal_z": seat_z - pedal_pos.z, "cushion_to_pedal_y": pedal_pos.y - cushion_y,
		"rear_length_behind_seatback": rear_len, "rear_roof_over_floor": rear_roof - rear_floor,
		"strut_bar_gap": strut_gap,
		"game_eye": eye, "game_eye_over_cushion": eye.y - cushion_y,
		"built_driver": built, "bodies": {},
	}
	r["game_sightline"] = _sightline(eye)
	if OS.get_environment("NEON_SPACE_DEBUG") == "1":
		for pitch in [-20.0, -15.0, -12.0, -10.0, -8.0, -6.0, -3.0, 0.0, 10.0, 20.0, 28.0]:
			var dir := Vector3(0.0, sin(deg_to_rad(pitch)), -cos(deg_to_rad(pitch)))
			var q := PhysicsRayQueryParameters3D.create(BASE + eye, BASE + eye + dir * REACH, CABIN_LAYER | OPAQUE_LAYER)
			q.hit_back_faces = true
			var h := space.intersect_ray(q)
			if h.is_empty():
				print("     pitch %+.0f: clear" % pitch)
			else:
				print("     pitch %+.0f: %s at %s" % [pitch, (h.collider as Node).name, _v(h.position - BASE)])
	print("== %s ==  cushion %.3f (%.2f over the floor), liner %.2f / skin %.2f over the cushion%s, hip width %.2f (door %.2f, console %.2f)" % [
		kind, cushion_y, cushion_y - floor_y, roof_liner - cushion_y, roof_skin - cushion_y, " (open top)" if open_top else "", hip_l + hip_r, hip_l, hip_r])
	print("   pedal %s  hub %s  knob %s  seat->pedal %.2f m" % [_v(pedal_pos), _v(hub), _v(knob), seat_z - pedal_pos.z])
	print("   game eye %.2f over the cushion: %s" % [eye.y - cushion_y, _sight_str(r.game_sightline)])
	if not built.is_empty():
		print("   built driver: head top %.2f over the cushion = a %.2f m person; hip->pedal %.2f vs legs %.2f" % [
			built.get("head_top_over_cushion", NAN), built.get("equivalent_stature", NAN), built.get("hip_to_pedal", NAN), built.thigh_shin])
	print("   behind the seatback %.2f m, rear roof %.2f over the rear floor; strut bar gap %.2f" % [rear_len, rear_roof - rear_floor, strut_gap])
	for s in STATURES:
		var m := Manikin.pose(s, seat_x, cushion_y, seat_z)
		var b := {}
		# Head and headroom.
		b["headroom_liner"] = roof_liner - m.head_top.y
		b["headroom_skin"] = roof_skin - m.head_top.y
		b["head_outside_shell"] = _outside(m.head_centre + Vector3(0.0, m.head_half.y, 0.0), open_top)
		# Shoulders: rays from the shoulder point outward.
		var sh_l := _dist(m.shoulder, Vector3.LEFT, CABIN_LAYER | SHELL_LAYER)
		var sh_r := _dist(m.shoulder, Vector3.RIGHT, CABIN_LAYER | SHELL_LAYER)
		b["shoulder_width"] = sh_l + sh_r
		b["shoulder_clear_door"] = sh_l - m.shoulder_half
		b["shoulder_clear_inboard"] = sh_r - m.shoulder_half
		b["hip_clear"] = minf(hip_l, hip_r) - m.hip_half
		# Legs to the throttle: ankle a little below and behind the pedal's pivot.
		var ankle: Vector3 = pedal_pos + Vector3(0.0, -0.12, 0.05)
		var lg := Manikin.leg(m.hip, ankle, m.thigh, m.shin)
		var knee: Vector3 = lg[0]
		b["leg_shortfall"] = lg[2]
		b["hip_to_pedal"] = (ankle - m.hip).length()
		b["leg_length"] = m.thigh + m.shin
		b["leg_fraction"] = (ankle - m.hip).length() / (m.thigh + m.shin)
		# how far the seat would have to slide (+ forward) for the leg to sit at 85% of its length
		b["slide_for_legs"] = (ankle - m.hip).length() - 0.85 * (m.thigh + m.shin)
		# and for the wheel's grip to sit at the comfortable reach
		var sh_r0: Vector3 = m.shoulder + Vector3(m.shoulder_half - 0.03, 0.0, 0.0)
		b["slide_for_wheel"] = (grip_r - sh_r0).length() - m.reach_easy
		b["knee"] = knee
		b["knee_room_up"] = _dist(knee, Vector3.UP, CABIN_LAYER) - 0.07
		b["knee_room_fwd"] = _dist(knee, Vector3.FORWARD, CABIN_LAYER) - 0.07
		# Arms.
		var sh_left: Vector3 = m.shoulder + Vector3(-m.shoulder_half + 0.03, 0.0, 0.0)
		var sh_right: Vector3 = m.shoulder + Vector3(m.shoulder_half - 0.03, 0.0, 0.0)
		b["reach_wheel_left"] = (grip_l - sh_left).length()
		b["reach_wheel_right"] = (grip_r - sh_right).length()
		b["reach_knob"] = (knob - sh_right).length() if knob.is_finite() else NAN
		b["reach_easy"] = m.reach_easy
		b["reach_max"] = m.reach_max
		b["wheel_to_thigh"] = _dist(hub + hub_basis * Vector3(0.0, -rim_r, 0.0), Vector3.DOWN, CABIN_LAYER)
		# Sightline from this body's eye.
		b["eye"] = m.eye
		b["eye_over_cushion"] = m.eye.y - cushion_y
		b["sightline"] = _sightline(m.eye)
		b["eye_under_roof_skin"] = roof_skin - m.eye.y
		r.bodies[str(s)] = b
		print("   %.2f m: head %+.2f to liner, %+.2f to skin%s | shoulders %.2f wide, %+.2f to door, %+.2f inboard | hips %+.2f | legs %.2f of %.2f (%s) knee up %+.2f fwd %+.2f | wheel L %.2f R %.2f knob %.2f (easy %.2f, max %.2f) | eye %.2f under skin, %s" % [
			s, b.headroom_liner, b.headroom_skin, " HEAD OUT %.2f" % b.head_outside_shell if b.head_outside_shell > 0.02 else "",
			b.shoulder_width, b.shoulder_clear_door, b.shoulder_clear_inboard, b.hip_clear,
			b.hip_to_pedal, b.leg_length, "SHORT %.2f" % b.leg_shortfall if b.leg_shortfall > 0.0 else "%.0f%%" % (b.leg_fraction * 100.0),
			b.knee_room_up, b.knee_room_fwd, b.reach_wheel_left, b.reach_wheel_right, b.reach_knob, b.reach_easy, b.reach_max,
			b.eye_under_roof_skin, _sight_str(b.sightline)])
	results[kind] = r
	for n in root.get_children():
		if n.name.begins_with("AuditProxy"):
			n.queue_free()
	game.queue_free()
	await process_frame
	await process_frame

## The clear band through the windshield from `eye`: rays in the vertical plane
## through the eye, straight ahead, pitch -40..+40 in half degrees, 4 m long,
## against the cabin and the opaque body. Returns the lowest and highest clear
## pitch of the band that holds 0 (or the nearest clear band), and the clear
## fraction of a FOV_V screen.
func _sightline(eye: Vector3) -> Dictionary:
	var clear := {}
	var step := 0.5
	var n := int(80.0 / step)
	for i in n + 1:
		var pitch := -40.0 + i * step
		var dir := Vector3(0.0, sin(deg_to_rad(pitch)), -cos(deg_to_rad(pitch)))
		var q := PhysicsRayQueryParameters3D.create(BASE + eye, BASE + eye + dir * REACH, CABIN_LAYER | OPAQUE_LAYER)
		q.hit_back_faces = true
		clear[i] = space.intersect_ray(q).is_empty()
	# the band around straight ahead (pitch 0), or if that is blocked, the widest clear band
	var zero := int(40.0 / step)
	var lo := zero
	var hi := zero
	if clear[zero]:
		while lo > 0 and clear[lo - 1]:
			lo -= 1
		while hi < n and clear[hi + 1]:
			hi += 1
	else:
		var best := [zero, zero - 1]
		var i := 0
		while i <= n:
			if clear[i]:
				var j := i
				while j < n and clear[j + 1]:
					j += 1
				if j - i > best[1] - best[0]:
					best = [i, j]
				i = j + 1
			else:
				i += 1
		lo = best[0]
		hi = best[1]
	var lo_deg := -40.0 + lo * step
	var hi_deg := -40.0 + hi * step
	var half := FOV_V * 0.5
	var frac := maxf(0.0, minf(hi_deg, half) - maxf(lo_deg, -half)) / FOV_V if hi >= lo else 0.0
	return {"low_deg": lo_deg, "high_deg": hi_deg, "clear_fraction": frac, "ahead_clear": clear[zero]}

static func _sight_str(s: Dictionary) -> String:
	return "clear %+.1f..%+.1f deg, %.0f%% of the screen%s" % [s.low_deg, s.high_deg, s.clear_fraction * 100.0, "" if s.ahead_clear else " (STRAIGHT AHEAD BLOCKED)"]

static func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _proxy(faces: PackedVector3Array, layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = "AuditProxy%d" % layer
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var poly := ConcavePolygonShape3D.new()
	poly.backface_collision = true
	poly.set_faces(faces)
	shape.shape = poly
	body.add_child(shape)
	body.position = BASE
	root.add_child(body)

func _ray(from: Vector3, dir: Vector3, mask: int) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(BASE + from, BASE + from + dir * REACH, mask)
	q.hit_back_faces = true
	q.hit_from_inside = false
	return q

## The first hit point (car space) along `dir`, or (-INF, -INF, -INF).
func _hit(from: Vector3, dir: Vector3, mask: int) -> Vector3:
	var h := space.intersect_ray(_ray(from, dir, mask))
	if h.is_empty():
		return Vector3(-INF, -INF, -INF)
	return h.position - BASE

## Distance to the first hit along `dir`, or REACH when nothing is there.
func _dist(from: Vector3, dir: Vector3, mask: int) -> float:
	var h := space.intersect_ray(_ray(from, dir, mask))
	if h.is_empty():
		return REACH
	return (h.position - BASE - from).length()

## 0 when the point is enclosed by the shell (rays up, left, right all hit), else
## how far past the shell it is (the way interior_fit.gd estimates it).
func _outside(at: Vector3, open_top: bool) -> float:
	var missed := []
	for d in [Vector3.UP, Vector3.LEFT, Vector3.RIGHT]:
		if open_top and d == Vector3.UP:
			continue
		if space.intersect_ray(_ray(at, d, SHELL_LAYER)).is_empty():
			missed.append(d)
	if missed.is_empty():
		return 0.0
	var worst := REACH
	for d in missed:
		var back := space.intersect_ray(_ray(at, -d, SHELL_LAYER))
		if not back.is_empty():
			worst = minf(worst, (back.position - BASE - at).length())
	return worst

static func _under(n: Node, parent_name: String) -> bool:
	var q := n
	while q != null:
		if q.name == parent_name:
			return true
		q = q.get_parent()
	return false

## The mesh's triangles in car space; with `skip_glass` the surfaces named
## "glass" are left out (ArrayMesh only; other meshes are taken whole).
static func _faces(mi: MeshInstance3D, inv: Transform3D, skip_glass := false) -> PackedVector3Array:
	var xf := inv * mi.global_transform
	var out := PackedVector3Array()
	if mi.mesh == null:
		return out
	if skip_glass and mi.mesh is ArrayMesh:
		var am: ArrayMesh = mi.mesh
		for s in am.get_surface_count():
			if am.surface_get_name(s) == "glass":
				continue
			var arrays := am.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				for v in verts:
					out.append(xf * v)
			else:
				for i in idx:
					out.append(xf * verts[i])
		return out
	for v in mi.mesh.get_faces():
		out.append(xf * v)
	return out
