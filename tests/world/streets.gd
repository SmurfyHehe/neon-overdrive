extends SceneTree

# The service streets (ramps doc steps 9 and 11; Roy 1553): Shop Street
# (exit 1a to 2a), Diesel Row (4b to 5b) and the container lanes (7b to 8b),
# built by the pocket kit as a pocket with two arms (PocketSite kind
# "street", RoadMap.POCKETS).
#
# Static: each street has a start and an end entry on neighbouring rings,
# spans the 800 m between them, keeps every chunk between pinned straight,
# reaches the chunk bounds (OffMapRescue) out to STREET_BOUND along its lane
# while the arms' chunks alone are cleared (pocket_bound), leaves the step
# wall open where its lane crosses it, keeps its lane within what
# RoadFrame.unroll can read, builds on its own side within the node's pool
# capacity (the end entry builds nothing), and names its gantries.
#
# Driven, on the curved, hilly loop: a bot takes exit 1a, a lap of ring 1,
# out the spur, down the arm onto Shop Street, along the whole street, up
# the far arm onto ring 2's spur; then the container lanes the same way
# from exit 7b on the -1 carriageway, winding between the stacks. On each it
# is "off the main road" as part "pocket" the whole way, on the deck, never
# rescued; a save taken on the street names a ring and the side.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/world/streets.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const RingSite := preload("res://scripts/world/ring_site.gd")
const PocketSite := preload("res://scripts/world/pocket_site.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")

const L := 50.0
const LANE_X := 11.6
const SLIP_X := RoadRamps.X_LANE + RoadRamps.HALF
const RAMP_SPEED := 13.0
const RING_SPEED := 10.0
const ARM_SPEED := 11.0
const MOUTH_SPEED := 6.0
const STREET_SPEED := 14.0
const LANES_SPEED := 10.0

var game: Node
var ticks := 0
var phase := 0
var phase_ticks := 0
var fails: Array[String] = []
var checks := 0
var path: Array[Vector3] = []
var path_i := 0
var site_s := 0.0
var runs: Array[Dictionary] = []
var run_i := 0
var off_missing := 0
var part_wrong := 0
var side_wrong := 0
var below := 0
var above := 0
var saved := false
var street_reached := false
var far_reached := false
var stall_ticks := 0
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
	SaveStore.root = "user://test_streets"
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

func _ring_index(id: String) -> int:
	for i in RoadMap.rings().size():
		if String(RoadMap.rings()[i].id) == id:
			return i
	return -1

# ---------- static ----------

func _static() -> void:
	RoadMap.use(0)
	var streets := []
	for pk in RoadMap.POCKETS:
		if String(pk.kind) == "street":
			streets.append(pk)
	_check(streets.size() == 3, "%d streets, 3 wanted" % streets.size())
	var words: Array = PlaceNames.atlas_words()
	_check(words.size() <= 60, "the atlas has %d words" % words.size())
	for st: Dictionary in streets:
		var id := String(st.id)
		var end := {}
		for pk in RoadMap.POCKETS:
			if String(pk.kind) == "street_end" and String(pk.get("of", "")) == id:
				end = pk
		_check(not end.is_empty() and int(end.side) == int(st.side) and String(end.ring) == String(st.to) and String(end.word) == String(st.word), "%s: its end entry is %s" % [id, end])
		_check(RoadMap.street_main(end) == st and RoadMap.street_main(st) == st, "%s: street_main does not find it from its end" % id)
		var span := RoadMap.pocket_span(st)
		_check(absf(span - 800.0) < 0.01 and absf(RoadMap.pocket_span(end) - span) < 0.01, "%s spans %.0f m (end %.0f)" % [id, span, RoadMap.pocket_span(end)])
		_check(PocketSite.max_grade(st) < 0.065, "%s: the arm's grade is %.3f" % [id, PocketSite.max_grade(st)])
		_check(absf(PocketSite.reach_v(st) - (span * 0.5 + 5.0)) < 0.01 and PocketSite.clear_v(st) == PocketSite.STREET_CLEAR_V, "%s: reach %.0f, clear %.0f" % [id, PocketSite.reach_v(st), PocketSite.clear_v(st)])
		_check(words.has(String(st.word)), "the atlas has no layer for '%s'" % st.word)
		var ra := _ring_index(String(st.ring))
		var rb := _ring_index(String(st.to))
		_check(ra >= 0 and rb == ra + 1, "%s: rings %d to %d" % [id, ra, rb])
		_check(RoadMap.pocket_at(ra, int(st.side)) == st and RoadMap.pocket_at(rb, int(st.side)) == end, "%s: pocket_at does not give its entries" % id)
		_check(RoadMap.ring_spur_sides(ra).has(int(st.side)) and RoadMap.ring_spur_sides(rb).has(int(st.side)), "%s: the rings have no spur on side %d" % [id, int(st.side)])
		var rc := floori(float(RoadMap.rings()[ra].s) / L)
		var rcb := floori(float(RoadMap.rings()[rb].s) / L)
		# every chunk between the rings is straight; the arms' chunks are
		# cleared and the lane's chunks reach the bounds out without clearing
		var unpinned := 0
		var bounds_ok := true
		var cleared_ok := true
		var side := int(st.side)
		for c in range(rc, rcb + 1):
			if RoadMap.pins()[RoadMap.lap_chunk(c)] != RoadMap.PIN_STRAIGHT:
				unpinned += 1
			var k := c - rc
			var lane_here := k >= 2 and k <= 13
			if (RoadRamps.street_bound(c, side) == PocketSite.STREET_BOUND) != lane_here:
				bounds_ok = false
			var arm_here := k <= 2 or k >= 13
			if (RoadRamps.pocket_bound(c, side) == PocketSite.BOUND) != arm_here:
				cleared_ok = false
		_check(unpinned == 0, "%s: %d chunks between the rings are not pinned straight" % [id, unpinned])
		_check(bounds_ok, "%s: the street bound is not on chunks 2 to 13 only" % id)
		_check(cleared_ok, "%s: the arms' chunks (0 to 2, 13 to 16) are not the cleared ones" % id)
		_check(RoadRamps.street_bound(rc + 6, side) == PocketSite.STREET_BOUND and RoadRamps.street_bound(rc + 6, -side) == 0.0, "%s: the street bound leaks to the other side" % id)
		# the step wall where the arm's cleared chunks end leaves the lane open
		var gap_a := RoadRamps.street_gap(rc + 3, side)
		var gap_b := RoadRamps.street_gap(rcb - 3, side)
		var lx_a: float = PocketSite.lane_x(st, 150.0)
		var lx_b: float = PocketSite.lane_x(st, span - 150.0)
		_check(gap_a.x < lx_a - PocketSite.STREET_HALF and gap_a.y > lx_a + PocketSite.STREET_HALF, "%s: the gap at chunk 3 is %s, lane at %.1f" % [id, gap_a, lx_a])
		_check(gap_b.x < lx_b - PocketSite.STREET_HALF and gap_b.y > lx_b + PocketSite.STREET_HALF, "%s: the gap at chunk -3 is %s, lane at %.1f" % [id, gap_b, lx_b])
		_check(RoadRamps.street_gap(rc + 1, side) == Vector2.ZERO, "%s: a gap where the lane has not started" % id)
		# the lane keeps within what unroll() reads, and joins the arms at STREET_X
		var far := 0.0
		var near := INF
		var v := PocketSite.STREET_V0
		while v <= span - PocketSite.STREET_V0:
			var lx: float = PocketSite.lane_x(st, v)
			far = maxf(far, lx + PocketSite.STREET_HALF + PocketSite.WALK_W)
			near = minf(near, lx - PocketSite.STREET_HALF - PocketSite.WALK_W)
			v += 5.0
		_check(far < PocketSite.STREET_BOUND and near > RoadRamps.BOUND_RING, "%s: the lane and pavements reach from %.1f to %.1f m out" % [id, near, far])
		_check(absf(PocketSite.lane_x(st, PocketSite.STREET_V0) - PocketSite.STREET_X) < 0.01 and absf(PocketSite.lane_x(st, span - PocketSite.STREET_V0) - PocketSite.STREET_X) < 0.01, "%s: the lane does not meet the arms at STREET_X" % id)
		# the footprint: the arms, the lane, nothing between; the end entry
		# reads the same ground in its own frame
		var g: float = PocketSite.GROUND_Y + RoadRamps.LIFT
		_check(PocketSite.covers(st, 52.0, 2.0) and absf(PocketSite.deck_y(st, 52.0, 2.0) - RoadRamps.RAMP_H - RoadRamps.LIFT) < 0.05, "%s: the first arm's top is not on the footprint" % id)
		_check(PocketSite.covers(end, 52.0, -2.0) and absf(PocketSite.deck_y(end, 52.0, -2.0) - RoadRamps.RAMP_H - RoadRamps.LIFT) < 0.05, "%s: the far arm's top is not on the footprint (end entry)" % id)
		_check(absf(PocketSite.deck_y(st, PocketSite.lane_x(st, 400.0), 400.0) - g) < 0.01 and absf(PocketSite.deck_y(end, PocketSite.lane_x(st, 400.0), -400.0) - g) < 0.01, "%s: the lane's middle does not read as ground from both ends" % id)
		_check(not PocketSite.covers(st, 80.0, 2.0) and not PocketSite.covers(st, PocketSite.lane_x(st, 400.0) + 12.0, 400.0), "%s: covers off the footprint" % id)
		# builds on its own side, right-handed, within the pool capacity; the end builds nothing
		var made: Dictionary = PocketSite.build(st)
		var sgn := float(st.side)
		var verts: PackedVector3Array = (made.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var wrong := 0
		var farthest := 0.0
		var vmin := INF
		var vmax := -INF
		for p in verts:
			if p.x * sgn < RoadRamps.RING_OUT - 1.0:
				wrong += 1
			farthest = maxf(farthest, p.x * sgn)
			vmin = minf(vmin, -p.z)
			vmax = maxf(vmax, -p.z)
		var bwrong := 0
		for b in made.boxes:
			var xf: Transform3D = b[0]
			if xf.origin.x * sgn < RoadRamps.RING_OUT - 1.0 or absf(xf.basis.determinant() - 1.0) > 0.01:
				bwrong += 1
		var pwrong := 0
		for pxf in made.pools:
			if (pxf as Transform3D).origin.x * sgn < RoadRamps.RING_OUT:
				pwrong += 1
		_check(wrong == 0 and bwrong == 0 and pwrong == 0, "%s: %d of %d vertices, %d of %d boxes, %d of %d pools on the wrong side or left-handed" % [id, wrong, verts.size(), bwrong, (made.boxes as Array).size(), pwrong, (made.pools as Array).size()])
		_check((made.boxes as Array).size() > 100 and (made.pools as Array).size() > 5 and (made.pools as Array).size() <= PocketSite.pool_capacity(st), "%s: %d boxes, %d pools (capacity %d)" % [id, (made.boxes as Array).size(), (made.pools as Array).size(), PocketSite.pool_capacity(st)])
		_check(farthest < PocketSite.BOUND + 10.0 and vmin > -5.0 and vmax < span + 5.0, "%s: the build reaches %.0f m out, v %.0f to %.0f" % [id, farthest, vmin, vmax])
		var made_end: Dictionary = PocketSite.build(end)
		_check((made_end.mesh as ArrayMesh).get_surface_count() == 0 and (made_end.boxes as Array).is_empty() and (made_end.faces as PackedVector3Array).is_empty(), "%s: the end entry builds something" % id)
		print("streets: %s: %d verts, %d boxes, %d pools, %d face points, v %.0f to %.0f" % [id, verts.size(), (made.boxes as Array).size(), (made.pools as Array).size(), (made.faces as PackedVector3Array).size(), vmin, vmax])
	# the lay-by moved to exit 8a so the container lanes get exit 7b and 8b
	var layby := _pk("layby")
	_check(String(layby.ring) == "x8" and int(layby.side) == 1, "the lay-by is at %s side %d" % [layby.ring, int(layby.side)])
	# the container lanes wind: the lane leaves STREET_X by more than 8 m both ways
	var lanes := _pk("lanes")
	var lo := INF
	var hi := -INF
	var v := PocketSite.STREET_V0
	while v <= 800.0 - PocketSite.STREET_V0:
		lo = minf(lo, PocketSite.lane_x(lanes, v))
		hi = maxf(hi, PocketSite.lane_x(lanes, v))
		v += 5.0
	_check(lo < PocketSite.STREET_X - 8.0 and hi > PocketSite.STREET_X + 8.0, "the container lanes run from %.1f to %.1f m out" % [lo, hi])
	_check(absf(PocketSite.lane_x(_pk("shop_st"), 400.0) - PocketSite.STREET_X) < 0.01 and absf(PocketSite.lane_x(_pk("diesel"), 300.0) - PocketSite.STREET_X) < 0.01, "Shop Street or Diesel Row is not straight")

# ---------- driven ----------

func _z_of(w: float) -> float:
	return float(RoadFrame.origin_index) * L - (site_s + w)

## The +1 side line through a street (in a frame where the carriageway is
## driven toward +w): the highway, the ring, the spur, the first arm, the
## lane, the far arm up and the far spur. For the -1 side the whole line is
## turned 180 degrees (x, w) -> (-x, -w).
func _line(pk: Dictionary) -> Array[Vector3]:
	var side := float(pk.side)
	var turn := float(pk.turn) * side
	var span := RoadMap.pocket_span(pk)
	var out: Array[Vector3] = []
	var w := -260.0
	while w < -RoadRamps.V_GORE - 1.0:
		out.append(Vector3(lerpf(LANE_X, SLIP_X, smoothstep(-250.0, -205.0, w)), w, RAMP_SPEED))
		w += 2.0
	w = -RoadRamps.V_GORE
	while w < 0.0:
		out.append(Vector3(RoadRamps.x_at(-w), w, RING_SPEED if w > -40.0 else RAMP_SPEED))
		w += 2.0
	for i in range(0, 65):
		var a := deg_to_rad(5.0 * float(i))
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
	var speed := LANES_SPEED if String(pk.street) == "lanes" else STREET_SPEED
	var va: float = PocketSite.STREET_V0
	while va <= span - PocketSite.STREET_V0:
		out.append(Vector3(PocketSite.lane_x(pk, va), va * turn, speed))
		va += 4.0
	s = run
	while s >= 0.0:
		var a: Dictionary = PocketSite.arm_at(s, 1.0)
		var p: Vector2 = a.p
		out.append(Vector3(p.x, (span - p.y) * turn, ARM_SPEED))
		s -= 2.0
	x = RingSite.SPUR_END
	while x > RoadRamps.RING_OUT + 4.0:
		out.append(Vector3(x, span * turn, RING_SPEED))
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
	site_s = float(RoadMap.rings()[_ring_index(String(pk.ring))].s)
	path = _line(pk)
	path_i = 0
	off_missing = 0
	part_wrong = 0
	side_wrong = 0
	below = 0
	above = 0
	street_reached = false
	far_reached = false
	stall_ticks = 0
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
	if phase_ticks > hz * 420:
		_fail("timed out in phase %d, %.0f m from the ring's centre, %.1f m out" % [phase, w, u.x])
		_finish()
		return true
	match phase:
		0:
			_check(RoadMap.is_loop(), "no loop")
			for id in ["x1", "x2", "x4", "x5", "x7", "x8"]:
				var ri := _ring_index(id)
				var look: Dictionary = RingSite.look_of(ri)
				var open := 0
				for i in RingSite.SEGS:
					if RingSite.rim_open(i, look.spurs):
						open += 1
				_check(open == 12 + 2 * (look.spurs as Array).size() and (look.spurs as Array).size() == 2, "ring %s: %d rim pieces open, spurs %s" % [id, open, look.spurs])
			var nodes := []
			for c in game.get_children():
				if String(c.name).begins_with("Pocket_"):
					nodes.append(String(c.name))
			_check(nodes.has("Pocket_shop_st") and nodes.has("Pocket_diesel") and nodes.has("Pocket_lanes") and not nodes.has("Pocket_shop_st_end"), "pocket nodes: %s" % [nodes])
			runs = []
			for pk in RoadMap.POCKETS:
				if String(pk.kind) == "street":
					runs.append(pk)
			var only := OS.get_environment("NEON_STREET_ONLY")
			if only != "":
				runs = [_pk(only)]
			run_i = 0
			game.rescue.rescued.connect(func(_r: String) -> void: rescues += 1)
			_start_run(p)
			_next(1)
		1:
			if phase_ticks < 30:
				return false
			var pk := runs[run_i]
			var side := float(pk.side)
			var span := RoadMap.pocket_span(pk)
			var rc: Array = game.rescue.call("check")
			if String(rc[0]) != "" and out_reports < 3:
				out_reports += 1
				print("streets: %s: out of bounds (%s) at %.1f m out, %.0f m from the centre, %.1f m up; bounds %s" % [pk.id, rc[0], u.x, w, u.y, game.rescue.call("_bounds_at", u.z)])
			var px := u.x * side
			if OS.get_environment("NEON_STREET_TRACE") != "" and phase_ticks % hz == 0:
				print("trace %s: x %.1f w %.0f y %.2f v %.1f place %s" % [pk.id, u.x, w, u.y, p.linear_velocity.length(), place.get("part", "-")])
			if p.linear_velocity.length() < 0.4 and path_i < path.size() - 3:
				stall_ticks += 1
				if stall_ticks == hz * 3:
					var q := PhysicsShapeQueryParameters3D.new()
					var box := BoxShape3D.new()
					box.size = Vector3(7.0, 3.0, 9.0)
					q.shape = box
					q.transform = p.global_transform
					q.exclude = [p.get_rid()]
					q.collision_mask = 0xFFFFFFFF
					var hits := p.get_world_3d().direct_space_state.intersect_shape(q, 8)
					var names: Array = []
					for h in hits:
						var col: CollisionObject3D = h.collider
						var owner_node: Node3D = col.shape_owner_get_owner(col.shape_find_owner(int(h.shape))) as Node3D
						var shape_res: Shape3D = col.shape_owner_get_shape(col.shape_find_owner(int(h.shape)), 0)
						var where := RoadFrame.unroll(owner_node.global_position)
						var size: Variant = (shape_res as BoxShape3D).size if shape_res is BoxShape3D else shape_res.get_class()
						names.append("%s/%s at x %.1f w %.0f y %.1f size %s" % [col.get_parent().name if col.get_parent() != null else "", col.name, where.x, RoadFrame.s_at(where.z) - site_s, where.y, size])
					_fail("%s: stalled 3 s at %.1f m out, %.0f m from the centre, %.2f m up, heading %s; bodies near: %s" % [pk.id, u.x, w, u.y, RoadFrame.dir_to_road(u.z, -p.global_transform.basis.z), names])
			else:
				stall_ticks = 0
			# on the street: the first ring's frame covers the whole street
			var on_street := px > RoadRamps.SPUR_REACH + 0.5 and w > -5.0 and w < span + 5.0 and PocketSite.covers(pk, px, w, -1.0)
			if on_street and p.linear_velocity.length() > 2.0:
				if place.is_empty():
					off_missing += 1
					if off_missing <= 3:
						_fail("%s: not off the main road, %.0f m from the centre (%.1f m out, %.1f m up)" % [pk.id, w, u.x, u.y])
				elif String(place.part) != "pocket":
					part_wrong += 1
					if part_wrong <= 3:
						_fail("%s: on the street as part %s, %.0f m from the centre (%.1f m out)" % [pk.id, place.part, w, u.x])
				elif int(place.side) != int(pk.side):
					side_wrong += 1
				var dy: float = PocketSite.deck_y(pk, px, w)
				if not is_inf(dy):
					var over := u.y - dy
					if over < -0.3:
						below += 1
					if over > 1.6:
						above += 1
				if w > PocketSite.STREET_V0 + 10.0 and not street_reached:
					street_reached = true
					print("streets: %s: on the street, %.0f m from the first ring's centre, %.1f m out, %.2f m up" % [pk.id, w, u.x, u.y])
				if w > span - PocketSite.STREET_V0 - 10.0 and not far_reached:
					far_reached = true
					print("streets: %s: at the far arm, %.0f m from the first ring's centre, %.1f m out, %.2f m up" % [pk.id, w, u.x, u.y])
				if w > span * 0.5 + 20.0 and street_reached and not saved:
					saved = true
					var run: Dictionary = game.saver.capture()
					var off: Dictionary = run.road.get("off", {})
					_check(off.get("part") == "pocket" and off.get("id") == String(pk.to) and int(off.get("side", 0)) == int(pk.side), "%s: the save taken past the middle says %s" % [pk.id, off])
			if path_i >= path.size() - 3:
				_check(street_reached, "%s: the bot never got onto the street" % pk.id)
				_check(far_reached, "%s: the bot never reached the far arm" % pk.id)
				_check(off_missing == 0, "%s: off the main road was not set on %d ticks" % [pk.id, off_missing])
				_check(part_wrong == 0, "%s: the part was not 'pocket' on %d ticks" % [pk.id, part_wrong])
				_check(side_wrong == 0, "%s: the place's side was wrong on %d ticks" % [pk.id, side_wrong])
				_check(below == 0 and above == 0, "%s: under the deck on %d ticks, over it on %d" % [pk.id, below, above])
				_check(rescues == 0, "%s: the rescue put the car back %d times" % [pk.id, rescues])
				_check(saved, "%s: never saved on the street" % pk.id)
				_check(not place.is_empty() and String(place.part) == "spur" and int(place.side) == int(pk.side) and String(place.id) == String(pk.to), "%s: on the far spur the place is %s" % [pk.id, place])
				print("streets: %s: down the arm, along the street and up the far arm: %d off-main misses, %d wrong parts, %d wrong sides, %d under, %d over" % [pk.id, off_missing, part_wrong, side_wrong, below, above])
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
	print("streets: %d checks, %d failed" % [checks, fails.size()])
	quit(1 if not fails.is_empty() else 0)
