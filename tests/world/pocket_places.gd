extends SceneTree

# The truck stop (exit 3a) and the drive-in diner (exit 3b): the pocket kit
# on both sides of one ring (ramps doc step 8; Roy 1553).
#
# Static: ring 3 has a spur on each side and 16 rim pieces open; each pocket
# builds, the diner's layout is the mirror of a +1 layout (every vertex on
# the -x side, the walls and pools too); the exit gantries' words are in the
# atlas; the arms' grades.
#
# Driven, on the curved, hilly loop: a bot takes exit 3b from the -1
# carriageway, a quarter round the ring, out the -1 spur, down the arm into
# the diner's lot, round it and back up to the spur; then exit 3a the same
# way from the +1 carriageway into the truck stop. On each it is "off the
# main road" as part "pocket" on that side, on the deck, never rescued;
# a save taken in the diner names ring 3 and side -1.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/world/pocket_places.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const RingSite := preload("res://scripts/world/ring_site.gd")
const PocketSite := preload("res://scripts/world/pocket_site.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")

const L := 50.0
const SITE := 2             # index into RoadMap.rings(): exit 3 (x3)
const LANE_X := 11.6
const SLIP_X := RoadRamps.X_LANE + RoadRamps.HALF
const RAMP_SPEED := 13.0
const RING_SPEED := 10.0
const ARM_SPEED := 11.0
const MOUTH_SPEED := 6.0
const LOT_SPEED := 9.0

var game: Node
var ticks := 0
var phase := 0
var phase_ticks := 0
var fails: Array[String] = []
var checks := 0
var path: Array[Vector3] = []
var path_i := 0
var site_s := 0.0
var runs: Array[Dictionary] = []   # the pockets to drive, diner first
var run_i := 0
var off_missing := 0
var part_wrong := 0
var side_wrong := 0
var below := 0
var above := 0
var saved := false
var lot_reached := false
var rescues := 0
var out_reports := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		_fail(msg)

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_ROAD_SEED", "4242")
	SaveStore.root = "user://test_pocket_places"
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveDirector.enabled = true
	SaveStore.select_slot(1)
	SaveStore.clear_run()
	SaveStore.load_meta()
	_static()
	game = Harness.boot(self, 4, 150.0, 7)

func _pk(id: String) -> Dictionary:
	for p in RoadMap.POCKETS:
		if String(p.id) == id:
			return p
	return {}

# ---------- static ----------

func _static() -> void:
	var truck := _pk("truck")
	var diner := _pk("diner")
	_check(not truck.is_empty() and not diner.is_empty() and int(truck.side) == 1 and int(diner.side) == -1, "the truck stop and the diner are not on opposite sides of exit 3: %s / %s" % [truck, diner])
	# every pocket's arm is driveable
	for pk in RoadMap.POCKETS:
		_check(PocketSite.max_grade(pk) < 0.065, "%s: the arm's grade is %.3f" % [pk.id, PocketSite.max_grade(pk)])
		_check(PocketSite.reach_v(pk) <= float(RoadMap.POCKET_CHUNKS) * L, "%s reaches %.0f m, past the %d pinned chunks" % [pk.id, PocketSite.reach_v(pk), RoadMap.POCKET_CHUNKS])
		_check(PocketSite.LOT_X1 < 100.0, "the lot reaches %.0f m out (RoadFrame.unroll stops at 100)" % PocketSite.LOT_X1)
	# the gantries' words have atlas layers
	var words: Array = PlaceNames.atlas_words()
	for pk in RoadMap.POCKETS:
		_check(words.has(String(pk.word)), "the atlas has no layer for '%s'" % pk.word)
	_check(words.size() <= 56, "the atlas has %d words" % words.size())
	# the truck stop builds on the +1 side, the diner is its mirror on the -1 side
	var made_t: Dictionary = PocketSite.build(truck)
	var made_d: Dictionary = PocketSite.build(diner)
	for made: Dictionary in [made_t, made_d]:
		var sgn := 1.0 if made == made_t else -1.0
		var verts: PackedVector3Array = (made.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var wrong := 0
		var far := 0.0
		for v in verts:
			if v.x * sgn < RoadRamps.RING_OUT - 1.0:
				wrong += 1
			far = maxf(far, v.x * sgn)
		_check(wrong == 0 and far < PocketSite.BOUND + 25.0, "side %d: %d of %d vertices on the wrong side, farthest %.0f m out" % [int(sgn), wrong, verts.size(), far])
		var faces: PackedVector3Array = made.faces
		var fwrong := 0
		for f in faces:
			if f.x * sgn < RoadRamps.RING_OUT - 1.0:
				fwrong += 1
		_check(fwrong == 0 and faces.size() > 200, "side %d: %d of %d collision points on the wrong side" % [int(sgn), fwrong, faces.size()])
		var bwrong := 0
		for b in made.boxes:
			var xf: Transform3D = b[0]
			if xf.origin.x * sgn < RoadRamps.RING_OUT - 1.0 or absf(xf.basis.determinant() - 1.0) > 0.01:
				bwrong += 1
		_check(bwrong == 0 and (made.boxes as Array).size() > 40, "side %d: %d of %d wall boxes wrong (side or handedness)" % [int(sgn), bwrong, (made.boxes as Array).size()])
		var pwrong := 0
		for pxf in made.pools:
			if (pxf as Transform3D).origin.x * sgn < RoadRamps.RING_OUT:
				pwrong += 1
		_check(pwrong == 0 and (made.pools as Array).size() > 5 and (made.pools as Array).size() <= PocketSite.POOL_CAPACITY, "side %d: %d of %d pools wrong" % [int(sgn), pwrong, (made.pools as Array).size()])
	# the mirrored deck faces keep the +1 layout's winding (a plain reflection
	# would turn every triangle over); compared with the same layout and turn
	# laid out on the +1 side
	var made_p: Dictionary = PocketSite.build({"id": "diner_plus", "side": 1, "turn": diner.turn, "kind": "diner"})
	var ways := []
	for made: Dictionary in [made_p, made_d]:
		var up := 0
		var faces: PackedVector3Array = made.faces
		@warning_ignore("integer_division")
		for t in faces.size() / 3:
			var n := (faces[t * 3 + 1] - faces[t * 3]).cross(faces[t * 3 + 2] - faces[t * 3])
			if n.y > 0.0:
				up += 1
		@warning_ignore("integer_division")
		ways.append([up, faces.size() / 3])
	_check(ways[0][0] == ways[1][0] and ways[0][1] == ways[1][1] and (ways[0][0] == 0 or ways[0][0] == ways[0][1]), "deck winding: the +1 layout %s up, the mirrored one %s up" % [ways[0], ways[1]])
	print("pocket_places: truck stop %d verts, %d boxes, %d pools; diner %d verts, %d boxes, %d pools" % [
		((made_t.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (made_t.boxes as Array).size(), (made_t.pools as Array).size(),
		((made_d.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (made_d.boxes as Array).size(), (made_d.pools as Array).size()])

# ---------- driven ----------

func _z_of(w: float) -> float:
	return float(RoadFrame.origin_index) * L - (site_s + w)

## The +1 side line into a pocket whose arm turns `turn` (in a frame where
## the carriageway is driven toward +w), from the highway to the lot and
## back to the spur. For the -1 side the whole line is turned 180 degrees
## (x, w) -> (-x, -w), which keeps anticlockwise anticlockwise.
func _line(pk: Dictionary) -> Array[Vector3]:
	var side := float(pk.side)
	var turn := float(pk.turn) * side
	var out: Array[Vector3] = []
	var w := -260.0
	while w < -RoadRamps.V_GORE - 1.0:
		out.append(Vector3(lerpf(LANE_X, SLIP_X, smoothstep(-250.0, -205.0, w)), w, RAMP_SPEED))
		w += 2.0
	w = -RoadRamps.V_GORE
	while w < 0.0:
		out.append(Vector3(RoadRamps.x_at(-w), w, RING_SPEED if w > -40.0 else RAMP_SPEED))
		w += 2.0
	for i in range(0, 15):
		var a := -PI * 0.5 + deg_to_rad(50.0) * float(i) / 15.0
		out.append(Vector3(RoadRamps.X_TOP * cos(a), RoadRamps.X_TOP * sin(a), RING_SPEED))
	var a0 := deg_to_rad(-40.0)
	var b0 := Vector2(RoadRamps.X_TOP * cos(a0), RoadRamps.X_TOP * sin(a0))
	var b1 := b0 + Vector2(-sin(a0), cos(a0)) * 10.0
	var b2 := Vector2(31.0, 0.0)
	var b3 := Vector2(42.0, 0.0)
	for i in range(0, 13):
		var q := b0.bezier_interpolate(b1, b2, b3, float(i) / 12.0)
		out.append(Vector3(q.x, q.y, MOUTH_SPEED))
	var x := 44.0
	while x < RingSite.SPUR_END:
		out.append(Vector3(x, 0.0, RING_SPEED))
		x += 2.0
	var run: float = PocketSite.arm_len()
	var s := 0.0
	while s <= run:
		var a: Dictionary = PocketSite.arm_at(s, turn)
		var p: Vector2 = a.p
		out.append(Vector3(p.x, p.y, ARM_SPEED))
		s += 2.0
	var v0 := (PocketSite.ARC_R + PocketSite.ARM_STRAIGHT) * turn
	var mouth := RingSite.SPUR_END + PocketSite.ARC_R
	var len: float = PocketSite.lot_len(pk)
	# round the lot along its road-side drive lane and back along the far end
	var inner := PocketSite.LOT_X0 + 7.0
	var outer := PocketSite.LOT_X1 - 10.0 if String(pk.kind) == "truck" else PocketSite.LOT_X1 - 12.0
	var far := v0 + (len - 8.0) * turn
	var lot: Array[Vector2] = [Vector2(mouth, v0 + 10.0 * turn), Vector2(inner, v0 + 24.0 * turn), Vector2(inner, far),
		Vector2(outer, far), Vector2(outer, v0 + 60.0 * turn), Vector2(mouth, v0 + 10.0 * turn), Vector2(mouth, v0)]
	for i in lot.size() - 1:
		var n := ceili(lot[i].distance_to(lot[i + 1]) / 2.0)
		for j in n:
			var q := lot[i].lerp(lot[i + 1], float(j) / float(n))
			out.append(Vector3(q.x, q.y, LOT_SPEED))
	s = run
	while s >= 0.0:
		var a: Dictionary = PocketSite.arm_at(s, turn)
		var p: Vector2 = a.p
		out.append(Vector3(p.x, p.y, ARM_SPEED))
		s -= 2.0
	x = RingSite.SPUR_END
	while x > RoadRamps.RING_OUT + 4.0:
		out.append(Vector3(x, 0.0, RING_SPEED))
		x -= 2.0
	if side < 0.0:
		for i in out.size():
			out[i] = Vector3(-out[i].x, -out[i].y, out[i].z)
	return out

func _stand(p: PlayerCar, t: Transform3D) -> void:
	game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", RoadFrame.unroll(p.global_position).z)
	game.call("flush_rebuilds")

func _drive(p: PlayerCar) -> void:
	p.driver = func(c: Vehicle) -> void:
		if path.is_empty() or path_i >= path.size() - 1:
			c.throttle_input = 0.0
			c.brake_input = 1.0
			return
		var u := RoadFrame.unroll(c.global_position)
		var best := INF
		for i in range(path_i, mini(path_i + 12, path.size())):
			var d := Vector2(path[i].x - u.x, _z_of(path[i].y) - u.z).length()
			if d < best:
				best = d
				path_i = i
		var speed := c.linear_velocity.length()
		var look := clampf(speed * 0.6, 4.0, 9.0)
		var j := path_i
		var run := 0.0
		while j < path.size() - 1 and run < look:
			run += Vector2(path[j + 1].x - path[j].x, path[j + 1].y - path[j].y).length()
			j += 1
		var target := RoadFrame.roll(Vector3(path[j].x, 0.0, _z_of(path[j].y)))
		var fwd := -c.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP)
		var to := target - c.global_position
		var alpha := atan2(to.dot(right), to.dot(fwd))
		var dist := maxf(Vector2(to.dot(right), to.dot(fwd)).length(), 0.5)
		var want := clampf(atan(2.6 * 2.0 * sin(alpha) / dist) / c.max_steering_angle, -1.0, 1.0)
		c.steering_input = -signf(want) * pow(absf(want), 1.0 / maxf(c.steering_exponent, 0.1))
		var goal := path[path_i].z
		c.throttle_input = clampf((goal - speed) * 0.5, 0.0, 1.0)
		c.brake_input = clampf((speed - goal - 1.0) * 0.4, 0.0, 1.0)
		if c.current_gear < 1:
			c.current_gear = 1

func _next(to_phase: int) -> void:
	phase = to_phase
	phase_ticks = 0

func _start_run(p: PlayerCar) -> void:
	var pk := runs[run_i]
	path = _line(pk)
	path_i = 0
	off_missing = 0
	part_wrong = 0
	side_wrong = 0
	below = 0
	above = 0
	lot_reached = false
	saved = false
	out_reports = 0
	_stand(p, RoadFrame.pose(path[0].x, 0.45, _z_of(path[0].y), 0.0 if int(pk.side) > 0 else PI))
	_drive(p)

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	phase_ticks += 1
	if ticks < 3:
		return false
	var p: PlayerCar = game.get("player")
	var hz := Engine.physics_ticks_per_second
	var u := RoadFrame.unroll(p.global_position)
	var w := RoadFrame.s_at(u.z) - site_s
	var place: Dictionary = game.off_main
	if phase_ticks > hz * 300:
		_fail("timed out in phase %d, %.0f m from the ring's centre, %.1f m out" % [phase, w, u.x])
		_finish()
		return true
	match phase:
		0:
			_check(RoadMap.is_loop(), "no loop")
			_check(String(RoadMap.rings()[SITE].id) == "x3" and RoadMap.pockets_of_ring(SITE).size() == 2, "ring %d is %s with %d pockets" % [SITE, RoadMap.rings()[SITE].id, RoadMap.pockets_of_ring(SITE).size()])
			_check(RoadMap.pocket_at(SITE, 1).get("id") == "truck" and RoadMap.pocket_at(SITE, -1).get("id") == "diner", "exit 3's pockets by side: %s / %s" % [RoadMap.pocket_at(SITE, 1), RoadMap.pocket_at(SITE, -1)])
			var sides := RoadMap.ring_spur_sides(SITE)
			_check(sides.has(1) and sides.has(-1) and sides.size() == 2, "ring 3's spur sides: %s" % [sides])
			site_s = float(RoadMap.rings()[SITE].s)
			var rc := floori(site_s / L)
			_check(RoadRamps.pocket_bound(rc + 3, 1) == PocketSite.BOUND and RoadRamps.pocket_bound(rc + 3, -1) == 0.0, "truck stop's bound beside chunk 3: %.0f own, %.0f oncoming" % [RoadRamps.pocket_bound(rc + 3, 1), RoadRamps.pocket_bound(rc + 3, -1)])
			_check(RoadRamps.pocket_bound(rc - 3, -1) == PocketSite.BOUND and RoadRamps.pocket_bound(rc - 3, 1) == 0.0, "diner's bound beside chunk -3: %.0f oncoming, %.0f own" % [RoadRamps.pocket_bound(rc - 3, -1), RoadRamps.pocket_bound(rc - 3, 1)])
			_check(RoadMap.pins()[RoadMap.lap_chunk(rc + 5)] == RoadMap.PIN_STRAIGHT and RoadMap.pins()[RoadMap.lap_chunk(rc - 5)] == RoadMap.PIN_STRAIGHT, "the pockets' chunks are not pinned straight")
			var look: Dictionary = RingSite.look_of(SITE)
			var open := 0
			for i in RingSite.SEGS:
				if RingSite.rim_open(i, look.spurs):
					open += 1
			_check(open == 16 and (look.spurs as Array).size() == 2, "ring 3: %d rim pieces open, spurs %s" % [open, look.spurs])
			var nodes := 0
			for c in game.get_children():
				if String(c.name).begins_with("Pocket_"):
					nodes += 1
			_check(nodes == RoadMap.POCKETS.size(), "%d pocket nodes for %d pockets" % [nodes, RoadMap.POCKETS.size()])
			runs = [_pk("diner"), _pk("truck")]
			run_i = 0
			game.rescue.rescued.connect(func(_r: String) -> void: rescues += 1)
			_start_run(p)
			_next(1)
		1:
			if phase_ticks < 30:
				return false
			var pk := runs[run_i]
			var side := float(pk.side)
			var rc: Array = game.rescue.call("check")
			if String(rc[0]) != "" and out_reports < 3:
				out_reports += 1
				print("pocket_places: %s: out of bounds (%s) at %.1f m out, %.0f m from the centre, %.1f m up; bounds %s" % [pk.id, rc[0], u.x, w, u.y, game.rescue.call("_bounds_at", u.z)])
			var px := u.x * side
			var on_pocket := px > RoadRamps.SPUR_REACH + 0.5 and PocketSite.covers(pk, px, w, -1.0)
			if on_pocket and p.linear_velocity.length() > 2.0:
				if place.is_empty():
					off_missing += 1
					if off_missing <= 3:
						_fail("%s: not off the main road, %.0f m from the centre (%.1f m out, %.1f m up)" % [pk.id, w, u.x, u.y])
				elif String(place.part) != "pocket":
					part_wrong += 1
					if part_wrong <= 3:
						_fail("%s: on the pocket as part %s, %.0f m from the centre (%.1f m out)" % [pk.id, place.part, w, u.x])
				elif int(place.side) != int(pk.side):
					side_wrong += 1
				var dy: float = PocketSite.deck_y(pk, px, w)
				if not is_inf(dy):
					var over := u.y - dy
					if over < -0.3:
						below += 1
					if over > 1.6:
						above += 1
				if px > PocketSite.LOT_X0 and w * float(pk.turn) > PocketSite.ARC_R + PocketSite.ARM_STRAIGHT and not lot_reached:
					lot_reached = true
					print("pocket_places: %s: in the lot, %.0f m from the ring's centre, %.1f m out, %.2f m up" % [pk.id, w, u.x, u.y])
				if lot_reached and not saved:
					saved = true
					var run: Dictionary = game.saver.capture()
					var off: Dictionary = run.road.get("off", {})
					_check(off.get("part") == "pocket" and off.get("id") == "x3" and int(off.get("side", 0)) == int(pk.side), "%s: the save taken in the lot says %s" % [pk.id, off])
			if path_i >= path.size() - 3:
				_check(lot_reached, "%s: the bot never reached the lot" % pk.id)
				_check(off_missing == 0, "%s: off the main road was not set on %d ticks" % [pk.id, off_missing])
				_check(part_wrong == 0, "%s: the part was not 'pocket' on %d ticks" % [pk.id, part_wrong])
				_check(side_wrong == 0, "%s: the place's side was wrong on %d ticks" % [pk.id, side_wrong])
				_check(below == 0 and above == 0, "%s: under the deck on %d ticks, over it on %d" % [pk.id, below, above])
				_check(rescues == 0, "%s: the rescue put the car back %d times" % [pk.id, rescues])
				_check(saved, "%s: never saved in the lot" % pk.id)
				_check(not place.is_empty() and String(place.part) == "spur" and int(place.side) == int(pk.side), "%s: back on the spur the place is %s" % [pk.id, place])
				print("pocket_places: %s: down the arm, round the lot and back: %d off-main misses, %d wrong parts, %d wrong sides, %d under, %d over" % [pk.id, off_missing, part_wrong, side_wrong, below, above])
				run_i += 1
				if run_i < runs.size():
					_start_run(p)
					_next(1)
				else:
					_finish()
					return true
	return false

func _finish() -> void:
	SaveStore.clear_run()
	print("pocket_places: %d checks, %d failed" % [checks, fails.size()])
	quit(1 if not fails.is_empty() else 0)
