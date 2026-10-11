extends SceneTree

# Compound gas station lots, grey boxes (2026-10-11). In the real game on
# Loop 1 a scripted driver takes the player car through each of the four
# act-1 lots, for real (no teleporting inside a lot):
# - from the kerb lane 150 m before the site at 60 km/h and again at
#   120 km/h, braking before the taper, in through the entry driveway;
# - "pump" runs stop at a pump (the pump menu opens once, and not again while
#   the car stays put), "row" runs stop in a parking bay and the air, phone,
#   wash and tow spots (each reports its kind, none opens the pump menu),
#   backing out of each;
# - out through the exit driveway and back onto the lane;
# - once more along the lane past the site at 120 km/h without turning in.
# All the way: the car's centre is never inside a box of the lot or behind
# its walls, never under the ground, never stuck (under 1 m in 3 s of
# throttle), and on the drive past it touches nothing.
# Also: no station shares a pinned chunk with a crossing or an exit in any
# act, the spot counts, and the lot's draw calls and triangles (counted from
# its own nodes: a headless run has no renderer to ask).
#   <godot> --headless --path . -s res://tests/world/station_lot.gd
# NEON_HILLS=1 runs the same on a hilly night. STATION_LOT_ONLY=fuel_7a runs
# one station, STATION_LOT_TRACE=1 prints where the car is twice a second.

const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const GasStation := preload("res://scripts/world/gas_station.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")

const ROOT := "user://test_station_lot"
const KMH := 1.0 / 3.6
## Lot x of the kerb lane's centre (half a lane inside the road edge).
const LANE_LX := -1.6
const TURN_IN_SPEED := 6.0
const LOT_SPEED := 4.5
const REACH := 3.0
const START_LA := -150.0
const END_LA := 130.0

var failures: Array[String] = []
var game: Node
var player: PlayerCar
var gs: GameState
var td := TestDriver.new()

# the station being driven
var st_id := ""
var ss := 0.0
var side := 1
var lot := {}
var label := ""

# what the driver is doing
var mode := "hold"
var path: Array = []
var path_i := 0
var path_speed := LOT_SPEED
var path_stop := false
var arrived := false
var lane_speed := 0.0
var brake_la := INF
var rev_steer := 0.0

# what the watch has seen this run
var contacts := 0
var _touching := false
var contact_names := {}
var _push_t := 0.0
var _push_from := Vector3.ZERO
var _said := {}
var pulled := 0
var _trace_t := 0.0
var trace := false

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.select_slot(1)
	SaveStore.chase_active = false
	trace = OS.get_environment("STATION_LOT_TRACE") == "1"
	_static()
	game = Harness.boot(self, 0, 300.0, 5)
	_run.call_deferred()

func _fail(msg: String) -> void:
	# one line per kind of failure per run
	var key := label + "|" + msg.left(12)
	if _said.has(key):
		return
	_said[key] = true
	failures.append("%s: %s" % [label, msg])
	printerr("FAIL: %s: %s" % [label, msg])

# ---------- checks that need no game ----------

func _static() -> void:
	label = "static"
	var RM := GasStation.RoadMap
	for act in range(1, RM.MAX_ACT + 1):
		RM.use(0, act)
		var pins := RM.pins()
		var taken := {}
		for e in RM.exits():
			for c in range(floori(float(e.s) / RM.L) - RM.PIN_APPROACH, floori(float(e.s) / RM.L) + RM.PIN_APPROACH + 1):
				taken[posmod(c, RM.period)] = "exit %s" % e.id
		for j in RM.junctions():
			for c in range(floori(j / RM.L) - RM.PIN_APPROACH, floori(j / RM.L) + RM.PIN_APPROACH + 1):
				taken[posmod(c, RM.period)] = "the crossing at %.0f" % j
		for st in RM.STOPS:
			if String(st.kind) != "station":
				continue
			var mid := floori(float(st.s) / RM.L)
			for c in range(mid - 1, mid + 2):
				if pins[posmod(c, RM.period)] != 1:
					_fail("act %d: chunk %d of %s is not pinned" % [act, c, st.id])
				if taken.has(posmod(c, RM.period)):
					_fail("act %d: %s shares chunk %d with %s" % [act, st.id, c, taken[posmod(c, RM.period)]])
	RM.use(0, 1)
	GasStation.first_s = GasStation.DEFAULT_FIRST_S
	for st in RM.STOPS:
		if String(st.kind) != "station":
			continue
		var l := GasStation.lot_of(float(st.s), int(st.side))
		if l.is_empty():
			_fail("%s has no lot" % st.id)
			continue
		var n := {}
		for sp in l.spots:
			n[sp.kind] = int(n.get(sp.kind, 0)) + 1
		var want_pumps := 12 if int(l.pumps) >= 6 else 8
		if int(n.get("pump", 0)) != want_pumps or int(n.get("park", 0)) < 10 or int(n.get("park", 0)) > 14 \
				or int(n.get("wash", 0)) != 1 or int(n.get("air", 0)) != 1 or int(n.get("phone", 0)) > 1 or int(n.get("tow", 0)) != 1:
			_fail("%s spot counts %s" % [st.id, str(n)])
		# no spot inside a box, across a driveway or outside the walls
		for sp in l.spots:
			var r: Rect2 = sp.r
			for sd in l.solids:
				if (sd.r as Rect2).intersects(r):
					_fail("%s: a %s spot overlaps a box" % [st.id, sp.kind])
			if r.position.x < 12.0 and absf(absf(r.get_center().y) - GasStation.DRIVE_AT) < GasStation.DRIVE_HALF + r.size.y / 2.0:
				_fail("%s: a %s spot lies across a driveway" % [st.id, sp.kind])
			if r.end.x > GasStation.LOT_DEPTH or absf(r.position.y) > GasStation.LOT_HALF or absf(r.end.y) > GasStation.LOT_HALF:
				_fail("%s: a %s spot is outside the lot" % [st.id, sp.kind])
		print("station_lot: %s (s %.0f, side %d): %d dispensers, store %s, wash %s, spots %s" % [st.id, st.s, st.side, l.pumps, l.store, l.wash, str(n)])
	RM.use(RM.ENDLESS)

# ---------- the driver (PlayerCar.driver) ----------

func _q() -> Vector2:
	return GasStation.lot_pos(GasStation.road_pos(player), ss, side)

func _world(q: Vector2) -> Vector3:
	var rp := GasStation.lot_to_road(q, ss, side)
	var z := float(RoadFrame.origin_index) * RoadFrame.L - rp.y
	return RoadFrame.pose(rp.x, 0.0, z, 0.0).origin

## The car's nose in lot space (x away from the road, y along the lot).
func _heading() -> Vector2:
	var p := player.global_position
	var f := -player.global_transform.basis.z
	var a := GasStation.lot_pos(GasStation.road_pos(player), ss, side)
	var u := RoadFrame.unroll(p + f * 2.0)
	var b := GasStation.lot_pos(Vector2(u.x, RoadFrame.s_at(u.z)), ss, side)
	return (b - a).normalized()

func _pedals(c: PlayerCar, want: float) -> void:
	var v := c.linear_velocity.length()
	c.handbrake_input = 0.0
	if v > want + 0.5:
		c.throttle_input = 0.0
		c.brake_input = clampf((v - want) * 0.35, 0.1, 1.0)
	else:
		c.throttle_input = clampf((want - v) * 0.4, 0.0, 1.0)
		c.brake_input = 0.0

func _drive(c: PlayerCar) -> void:
	var q := _q()
	match mode:
		"hold":
			c.throttle_input = 0.0
			c.brake_input = 1.0
			c.handbrake_input = 0.0
			c.steering_input = 0.0
		"lane":
			var v := c.linear_velocity.length()
			# aimed a little short of the lane by its own sideways speed: plain
			# pursuit swings wider and wider at 120 km/h after a kick (a hill)
			var side_v := (_heading() * v).x
			c.steering_input = td.steer_at(c, _world(Vector2(LANE_LX - clampf(side_v * 1.5, -2.5, 2.5), q.y + maxf(12.0, v * 1.2))))
			var want := lane_speed
			if not is_inf(brake_la):
				want = minf(want, sqrt(TURN_IN_SPEED * TURN_IN_SPEED + 2.0 * 5.5 * maxf(0.0, brake_la - q.y)))
			_pedals(c, want)
		"path":
			while path_i < path.size() - 1 and q.distance_to(path[path_i]) < REACH:
				path_i += 1
			var wp: Vector2 = path[path_i]
			var d := q.distance_to(wp)
			c.steering_input = td.steer_at(c, _world(wp))
			var want := path_speed
			if path_stop and path_i == path.size() - 1:
				want = minf(want, sqrt(2.0 * 1.5 * maxf(d - 0.4, 0.0)) + 0.4)
				if d < 0.7 or (d < 3.0 and (wp - q).dot(_heading()) < 0.0):
					arrived = true
					mode = "hold"
			elif not path_stop and path_i == path.size() - 1 and d < REACH:
				arrived = true
			_pedals(c, want)
		"reverse":
			c.steering_input = TestDriver._wheel(c, rev_steer)
			c.throttle_input = 0.4 if c.linear_velocity.length() < 2.5 else 0.0
			c.brake_input = 0.0
			c.handbrake_input = 0.0

# ---------- one physics tick, with the watch ----------

func _tick() -> void:
	await physics_frame
	if player == null or lot.is_empty():
		return
	var q := _q()
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	if trace:
		_trace_t += dt
		if _trace_t >= 0.5:
			_trace_t = 0.0
			var h := _heading()
			print("  %s  %s i%d  lx %.1f la %.1f  v %.1f  head (%.2f, %.2f)  gear %d" % [label, mode, path_i, q.x, q.y, player.linear_velocity.length(), h.x, h.y, player.current_gear])
	if RoadFrame.unroll(player.global_position).y < -0.3:
		_fail("under the ground at lx %.1f la %.1f" % [q.x, q.y])
	if q.x > GasStation.KNEE_X + GasStation.KNEE_T and (absf(q.y) > GasStation.LOT_HALF or q.x > GasStation.LOT_DEPTH - GasStation.LOT_WALL_T):
		_fail("behind a wall at lx %.1f la %.1f" % [q.x, q.y])
	for sd in lot.solids:
		if (sd.r as Rect2).has_point(q):
			_fail("inside a box at lx %.1f la %.1f" % [q.x, q.y])
	var touch := false
	for b in (player.get_colliding_bodies() if player.get_contact_count() > 0 else []):
		if b is CollisionObject3D and b.collision_layer & (1 << (CarSpec.WALL_LAYER - 1)):
			touch = true
			contact_names["%s/%s" % [b.get_parent().name, b.name]] = "lx %.1f la %.1f" % [q.x, q.y]
	if touch and not _touching:
		contacts += 1
	_touching = touch
	# stuck: throttle held, the brake off, and the car goes nowhere
	if not paused and player.throttle_input > 0.2 and player.brake_input < 0.05:
		if _push_t == 0.0:
			_push_from = player.global_position
		_push_t += dt
		if _push_t >= 3.0:
			if player.global_position.distance_to(_push_from) < 1.0:
				_fail("stuck at lx %.1f la %.1f (%s)" % [q.x, q.y, mode])
			_push_t = 0.0
	else:
		_push_t = 0.0

func _ticks(n: int) -> void:
	for i in n:
		await _tick()

## Runs until `done` says so; false (and a failure) after `secs` seconds.
func _until(done: Callable, secs: float, what: String) -> bool:
	for i in int(secs * float(Engine.physics_ticks_per_second)):
		if done.call():
			return true
		await _tick()
	var q := _q()
	_fail("%s took over %.0f s (car at lx %.1f la %.1f, %s)" % [what, secs, q.x, q.y, mode])
	return false

# ---------- the moves ----------

## Puts the car on the kerb lane at `la`, doing `speed` m/s along the road.
func _put_on_lane(la: float, speed: float) -> void:
	mode = "hold"
	var yaw := 0.0 if side == 1 else PI
	for pass_i in 2:
		var rp := GasStation.lot_to_road(Vector2(LANE_LX, la), ss, side)
		var z := float(RoadFrame.origin_index) * RoadFrame.L - rp.y
		var y := maxf(RoadFrame.unroll(player.global_position).y, 0.3)
		var t := RoadFrame.pose(rp.x, y, z, yaw)
		# along the road as it runs there (it may climb)
		var ahead := RoadFrame.pose(rp.x, y, z - (1.0 if side == 1 else -1.0), yaw).origin - t.origin
		var vel := ahead.normalized() * (speed if pass_i == 1 else 0.0)
		game.saver.restore_car(player, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [vel.x, vel.y, vel.z],
			"ang_vel": [0.0, 0.0, 0.0], "gear": 4 if speed > 25.0 else 3})
		if pass_i == 0:
			# build the road round the new place (the origin may move), then
			# place the car again where that left the road
			game.call("_update_chunk_pool", z)
			game.call("flush_rebuilds")
			for i in 20:
				player.linear_velocity = Vector3.ZERO
				await physics_frame
	player.fuel.litres = FuelTank.CAPACITY_L
	# a touch from the place it left is still reported for a tick
	for i in 3:
		await physics_frame
	contacts = 0
	_touching = false
	contact_names = {}
	_push_t = 0.0
	pulled = 0

func _go(points: Array, speed: float, stop: bool, secs: float, what: String) -> bool:
	path = points
	path_i = 0
	path_speed = speed
	path_stop = stop
	arrived = false
	mode = "path"
	return await _until(func() -> bool: return arrived, secs, what)

## From the lane at START_LA down to turn-in speed and in through the entry.
func _enter(speed: float) -> bool:
	await _put_on_lane(START_LA, speed)
	lane_speed = speed
	brake_la = -58.0
	mode = "lane"
	if not await _until(func() -> bool: return _q().y > -55.5, 30.0, "the approach"):
		return false
	return await _go([Vector2(-0.2, -50.5), Vector2(GasStation.KNEE_X + 0.25, -GasStation.DRIVE_AT + 0.5)], TURN_IN_SPEED, false, 15.0, "turning in")

## Out through the exit from wherever the car is, and back onto the lane.
func _leave(points: Array) -> void:
	points.append_array([Vector2(GasStation.KNEE_X + 0.25, GasStation.DRIVE_AT), Vector2(-0.6, GasStation.DRIVE_AT + 5.5), Vector2(LANE_LX, GasStation.DRIVE_AT + 17.0)])
	if not await _go(points, LOT_SPEED, false, 40.0, "leaving by the exit"):
		return
	lane_speed = 15.0
	brake_la = INF
	mode = "lane"
	if not await _until(func() -> bool: return _q().y > END_LA, 30.0, "rejoining the lane"):
		return
	var q := _q()
	if absf(q.x - LANE_LX) > 1.3 or _heading().y < 0.95:
		_fail("not back on the lane after the exit (lx %.1f, heading %.2f)" % [q.x, _heading().y])

func _stopped() -> bool:
	return player.linear_velocity.length() < 0.3

## Stops at lot position `at`, coming through `via`, and checks the spot.
func _visit(kind: String, via: Array, at: Vector2) -> bool:
	var pts := via.duplicate()
	pts.append(at)
	if not await _go(pts, LOT_SPEED, true, 40.0, "driving to the %s spot" % kind):
		return false
	if not await _until(_stopped, 6.0, "stopping in the %s spot" % kind):
		return false
	var node: Node = game.get("gas_station") if side == 1 else game.get("gas_station_onc")
	var before := pulled
	await _ticks(int((GasStation.HOLD_S + 0.6) * float(Engine.physics_ticks_per_second)))
	var found := GasStation.spot_at(GasStation.road_pos(player))
	var q := _q()
	if String(found.get("kind", "")) != kind:
		_fail("stopped for the %s spot at lx %.1f la %.1f, spot_at says '%s'" % [kind, q.x, q.y, found.get("kind", "")])
		return false
	if String(node.get("spot_kind")) != kind:
		_fail("the station reports '%s' in the %s spot" % [node.get("spot_kind"), kind])
	if kind == "pump":
		if gs.state != GameState.State.STATION:
			_fail("the pump menu did not open at lx %.1f la %.1f" % [q.x, q.y])
			return false
		gs.close_station()
		await _ticks(int(1.5 * float(Engine.physics_ticks_per_second)))
		if gs.state == GameState.State.STATION or pulled - before != 1:
			_fail("the pump spot opened %d times without the car leaving it" % (pulled - before))
			if gs.state == GameState.State.STATION:
				gs.close_station()
	elif gs.state == GameState.State.STATION or pulled != before:
		_fail("the %s spot opened the pump menu" % kind)
		if gs.state == GameState.State.STATION:
			gs.close_station()
	return true

## Backs out of a nose-in spot into the aisle and turns the nose along it;
## then on back down the aisle until the next stop (at `next_la`) is far
## enough ahead to turn into.
func _back_out(next_la := INF) -> bool:
	mode = "hold"
	if not await _until(_stopped, 5.0, "stopping before reverse"):
		return false
	if not await _until(func() -> bool: return player.current_gear == -1 or player.toggle_reverse(), 4.0, "selecting reverse"):
		return false
	await _until(func() -> bool: return player.current_gear == -1 and not player.is_shifting, 3.0, "reverse engaging")
	rev_steer = 0.0
	mode = "reverse"
	# straight back until the nose is clear of the bay, then swing the nose
	# toward the exit end of the aisle
	if not await _until(func() -> bool: return _q().x < 35.4, 12.0, "backing out"):
		return false
	var along := player.global_transform.basis.inverse() * (_world(_q() + Vector2(0.0, 5.0)) - _world(_q()))
	rev_steer = -1.0 if along.x > 0.0 else 1.0
	await _until(func() -> bool: return _heading().y > 0.93 or _q().x < 29.6, 12.0, "swinging round in reverse")
	rev_steer = 0.0
	if _heading().y > 0.9 and _q().y > next_la - 12.0:
		await _until(func() -> bool: return _q().y < next_la - 12.0 or _q().y < -46.0, 12.0, "backing down the aisle")
	mode = "hold"
	if not await _until(_stopped, 5.0, "stopping after reverse"):
		return false
	if not await _until(func() -> bool: return player.current_gear != -1 or player.toggle_reverse(), 4.0, "leaving reverse"):
		return false
	await _until(func() -> bool: return player.current_gear != -1 and not player.is_shifting, 3.0, "drive engaging")
	return true

func _spot_la(kind: String, nth := 0) -> Vector2:
	for sp in lot.spots:
		if String(sp.kind) == kind:
			if nth == 0:
				return (sp.r as Rect2).get_center()
			nth -= 1
	return Vector2.INF

## In, stop at a pump, out. `island` and `far` pick the pump lane.
func _pump_run(speed_kmh: float, island: int, far: bool) -> void:
	label = "%s %s pump run, %.0f km/h" % [st_id, _night(), speed_kmh]
	if not await _enter(speed_kmh * KMH):
		return
	var cc: float = (lot.canopy as Rect2).get_center().y
	var lane_x := GasStation.ISLAND_X0 + GasStation.ISLAND_STEP * float(island) + (2.0 if far else -2.0)
	var at := Vector2(lane_x, cc - GasStation.DISPENSER_AT)
	if await _visit("pump", [Vector2(lane_x, cc - 24.0)], at):
		await _leave([Vector2(lane_x, cc + 17.0), Vector2(8.0, GasStation.DRIVE_AT - 8.0)])
	_report()

## In, stop in every other kind of spot (backing out of each), out.
func _row_run(speed_kmh: float) -> void:
	label = "%s %s row run, %.0f km/h" % [st_id, _night(), speed_kmh]
	if not await _enter(speed_kmh * KMH):
		return
	# the row's spots in the order they come along the aisle; the parking bay
	# is the one with the most room to the other stops
	var stops := []
	for k in ["air", "phone", "wash", "tow"]:
		var c := _spot_la(k)
		if c.is_finite():
			stops.append([k, c])
	var park := Vector2.INF
	var room := -1.0
	for i in 14:
		var c := _spot_la("park", i)
		if not c.is_finite():
			break
		if c.y < -30.0 or c.y > GasStation.WASH_LA.x - 8.0:
			continue
		var gap := INF
		for stop in stops:
			gap = minf(gap, absf((stop[1] as Vector2).y - c.y))
		if gap > room:
			room = gap
			park = c
	stops.append(["park", park])
	stops.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Vector2).y < (b[1] as Vector2).y)
	var first_la: float = (stops[0][1] as Vector2).y
	# up the entry side of the lot to the aisle
	var via := [Vector2(12.0, -42.0), Vector2(21.0, -41.5), Vector2(28.5, minf(-36.0, first_la - 11.0))]
	var ok := true
	for n in stops.size():
		var c: Vector2 = stops[n][1]
		var kind: String = stops[n][0]
		via.append_array([Vector2(29.5, c.y - 9.0), Vector2(33.0, c.y - 2.2)])
		var at := Vector2(36.4, c.y)
		if kind == "wash":
			via.append(Vector2(37.0, c.y - 0.2))
			at = Vector2(43.5, c.y)
		if not await _visit(kind, via, at) or not await _back_out((stops[n + 1][1] as Vector2).y if n + 1 < stops.size() else INF):
			ok = false
			break
		via = []
	if ok:
		await _leave([Vector2(21.0, GasStation.DRIVE_AT - 4.0), Vector2(11.0, GasStation.DRIVE_AT)])
	_report()

## Along the lane past the site at 120 km/h without turning in.
func _pass_by() -> void:
	label = "%s %s drive past, 120 km/h" % [st_id, _night()]
	await _put_on_lane(START_LA, 120.0 * KMH)
	lane_speed = 120.0 * KMH
	brake_la = INF
	mode = "lane"
	var worst := 0.0
	for i in int(20.0 * float(Engine.physics_ticks_per_second)):
		await _tick()
		worst = maxf(worst, absf(_q().x - LANE_LX))
		if _q().y > END_LA:
			break
	if _q().y <= END_LA:
		_fail("did not get past the site")
	if contacts > 0:
		_fail("touched %s driving past" % str(contact_names))
	if worst > 1.0:
		_fail("left the lane by %.1f m driving past" % worst)
	_report()

func _night() -> String:
	return "hilly" if RoadFrame.has_hills() else "flat"

func _report() -> void:
	var bad := 0
	for f in failures:
		if f.begins_with(label + ":"):
			bad += 1
	print("station_lot: %s: %s, %d wall touches%s" % [label, "ok" if bad == 0 else "FAIL (%d)" % bad, contacts,
		"" if contact_names.is_empty() else " " + str(contact_names)])
	mode = "hold"

## Draw calls and triangles of the station's own nodes (near view, no cars).
func _cost(node: Node3D) -> void:
	var draws := 0
	var tris := 0
	var shapes := 0
	for n in node.find_children("*", "", true, false):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m: Mesh = (n as MeshInstance3D).mesh
			draws += m.get_surface_count()
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		elif n is Label3D:
			draws += 1
			tris += 2
		elif n is CollisionShape3D:
			shapes += 1
	print("station_lot: %s cost: %d draw calls, %d triangles, 1 static body with %d boxes" % [st_id, draws, tris, shapes])
	if draws > 7:
		_fail("%d draw calls, the target is 7" % draws)
	# the lot is one flat plate: the road beside it must be flat with it
	var off := 0.0
	for la in [-GasStation.LOT_HALF, -25.0, 25.0, GasStation.LOT_HALF]:
		off = maxf(off, absf(node.to_local(_world(Vector2(0.0, la))).y))
	print("station_lot: %s %s night: the road edge is within %.1f cm of the lot's plane along its front" % [st_id, _night(), off * 100.0])
	if off > 0.03:
		_fail("the road leaves the lot's plane by %.1f cm" % (off * 100.0))

func _run() -> void:
	for i in 40:
		await physics_frame
	player = game.get("player")
	gs = game.get("game_state")
	label = "boot"
	if GasStation.RoadMap.period <= 0:
		_fail("the game is not on a loop")
		return _end()
	player.set("driver", _drive)
	for n in [game.get("gas_station"), game.get("gas_station_onc")]:
		(n as Node).connect("pulled_up", func(_s: float) -> void: pulled += 1)
	var only := OS.get_environment("STATION_LOT_ONLY")
	for st in GasStation.RoadMap.STOPS:
		if String(st.kind) != "station" or (only != "" and only != String(st.id)):
			continue
		st_id = String(st.id)
		ss = float(st.s)
		side = int(st.side)
		lot = GasStation.lot_of(ss, side)
		label = st_id
		# the same road width all the way past the site, or the lane and the
		# lot's front would not line up
		for d in [-150.0, -75.0, 75.0, 150.0]:
			if not is_equal_approx(GasStation.own_edge(ss + d, side), GasStation.own_edge(ss, side)):
				_fail("the road is %.1f m wide at %+.0f m, %.1f at the station" % [GasStation.own_edge(ss + d, side), d, GasStation.own_edge(ss, side)])
		await _put_on_lane(-60.0, 0.0)
		_cost(game.get("gas_station") if side == 1 else game.get("gas_station_onc"))
		await _pump_run(60.0, 0, false)
		await _row_run(60.0)
		await _pump_run(120.0, 1, false)
		await _row_run(120.0)
		await _pass_by()
	_end()

func _end() -> void:
	print("station_lot (%s night): %s" % [_night(), "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()])
	quit(0 if failures.is_empty() else 1)

func _wipe(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for f in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(f))
	for d in DirAccess.get_directories_at(dir_path):
		_wipe(dir_path.path_join(d))
	DirAccess.remove_absolute(dir_path)
