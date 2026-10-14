extends SceneTree

# The Docks pier: the first pocket at the end of a ring's arm (ramps doc step
# 7, notes/better-ramps-and-destinations-2026-10-13.md; Roy 1505, 1539).
#
# Static: the arm's line, drop and grade, what the pocket covers, where the
# out-of-bounds wall stands beside it, the atlas word and the exit gantry's
# text, the ring's open spur, and the pocket node's cost (two draw calls).
#
# Driven, on the curved, hilly loop at exit 5's ring: a bot leaves the +1
# carriageway, goes up, a quarter round the ring, out along the spur, down
# the arm to the pier, round the lot by the ship and back up the arm to the
# ring. All the way from the spur it is "off the main road" as part
# "pocket", on the deck (never through it, never over a wall); the save
# taken on the pier names the pocket's ring; a put-back from the pier stands
# the car at the top of the arm facing the ring.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/world/pocket_pier.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const RingSite := preload("res://scripts/world/ring_site.gd")
const PocketSite := preload("res://scripts/world/pocket_site.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")

const L := 50.0
const SITE := 4             # index into RoadMap.rings(): exit 5 (x5, the "lot" ring)
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
var pk := {}
var off_missing := 0
var part_wrong := 0
var below := 0
var above := 0
var wall_hits := 0
var deepest := 0.0
var highest := 0.0
var saved_on_pier := false
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
	SaveStore.root = "user://test_pocket_pier"
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveDirector.enabled = true
	SaveStore.select_slot(1)
	SaveStore.clear_run()
	SaveStore.load_meta()
	_static()
	game = Harness.boot(self, 4, 150.0, 7)

# ---------- static ----------

func _static() -> void:
	# the arm's line: from the spur's end, a quarter turn, then along the road
	var a0: Dictionary = PocketSite.arm_at(0.0, 1.0)
	_check((a0.p as Vector2).is_equal_approx(Vector2(RingSite.SPUR_END, 0.0)) and (a0.t as Vector2).is_equal_approx(Vector2.RIGHT), "the arm starts at the spur's end heading out: %s" % [a0])
	var arc := PocketSite.ARC_R * PI * 0.5
	var a1: Dictionary = PocketSite.arm_at(arc, 1.0)
	_check((a1.t as Vector2).is_equal_approx(Vector2(0.0, 1.0)) and absf((a1.p as Vector2).x - (RingSite.SPUR_END + PocketSite.ARC_R)) < 0.01, "after the bend the arm runs along the road: %s" % [a1])
	var am: Dictionary = PocketSite.arm_at(arc, -1.0)
	_check((am.t as Vector2).is_equal_approx(Vector2(0.0, -1.0)), "turn -1 mirrors the bend: %s" % [am])
	var run: float = PocketSite.arm_len()
	_check(absf(PocketSite.arm_y(pk_of(), 0.0) - RoadRamps.RAMP_H) < 0.001 and absf(PocketSite.arm_y(pk_of(), run) - PocketSite.PIER_Y) < 0.001, "the arm drops from %.1f to %.1f" % [PocketSite.arm_y(pk_of(), 0.0), PocketSite.arm_y(pk_of(), run)])
	# the drop is smooth: no step of more than the grade in any metre, and never climbs
	var worst := 0.0
	var s := 0.0
	while s < run:
		var d: float = PocketSite.arm_y(pk_of(), s) - PocketSite.arm_y(pk_of(), s + 1.0)
		worst = maxf(worst, d)
		_check(d >= -0.0001, "the arm climbs at %.0f m" % s)
		s += 1.0
	_check(worst <= PocketSite.max_grade(pk_of()) + 0.001 and PocketSite.max_grade(pk_of()) < 0.065, "the arm's steepest metre drops %.3f (grade %.3f)" % [worst, PocketSite.max_grade(pk_of())])
	# the footprint: on the arm, on the lot, off both
	var mid: Dictionary = PocketSite.arm_at(run * 0.5, 1.0)
	var mp: Vector2 = mid.p
	_check(PocketSite.covers(pk_of(), mp.x, mp.y), "the arm's middle is not covered")
	_check(not PocketSite.covers(pk_of(), mp.x + PocketSite.ARM_HALF + 3.0, mp.y), "3 m off the arm's edge is covered")
	_check(PocketSite.covers(pk_of(), (PocketSite.LOT_X0 + PocketSite.LOT_X1) * 0.5, PocketSite.ARC_R + PocketSite.ARM_STRAIGHT + 50.0), "the lot's middle is not covered")
	_check(not PocketSite.covers(pk_of(), PocketSite.LOT_X1 + 5.0, PocketSite.ARC_R + PocketSite.ARM_STRAIGHT + 50.0), "the water is covered")
	_check(not PocketSite.covers(pk_of(), RoadRamps.X_TOP, 0.0), "the ring's lane is covered")
	# deck_y samples the arm's line every metre: within half a metre of grade
	_check(absf(PocketSite.deck_y(pk_of(), mp.x, mp.y) - (PocketSite.arm_y(pk_of(), run * 0.5) + RoadRamps.LIFT)) < 0.05, "deck_y on the arm's middle is %.2f" % PocketSite.deck_y(pk_of(), mp.x, mp.y))
	_check(is_inf(PocketSite.deck_y(pk_of(), 10.0, -100.0)), "deck_y off the pocket is %s" % PocketSite.deck_y(pk_of(), 10.0, -100.0))
	# the atlas has the pocket's word, within the texture array's cap
	var words: Array = PlaceNames.atlas_words()
	_check(words.has("PIER") and words.size() <= 60, "the atlas has %d words, PIER %s" % [words.size(), words.has("PIER")])

func pk_of() -> Dictionary:
	if pk.is_empty():
		for p in RoadMap.POCKETS:
			if String(p.id) == "pier":
				pk = p
	return pk

# ---------- driven ----------

func _z_of(w: float) -> float:
	return float(RoadFrame.origin_index) * L - (site_s + w)

## Up from the +1 carriageway, a quarter round, out the spur, down the arm,
## round the lot, back up the arm, onto the spur, and stop at the ring's rim.
func _line() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var w := -260.0
	while w < -RoadRamps.V_GORE - 1.0:
		out.append(Vector3(lerpf(LANE_X, SLIP_X, smoothstep(-250.0, -205.0, w)), w, RAMP_SPEED))
		w += 2.0
	w = -RoadRamps.V_GORE
	while w < 0.0:
		out.append(Vector3(RoadRamps.x_at(-w), w, RING_SPEED if w > -40.0 else RAMP_SPEED))
		w += 2.0
	# anticlockwise from -90 deg (the +1 ramp's top) to -40 deg, then peel
	# off through the rim's mouth onto the spur (a bezier that meets the rim
	# at about 2.5 m from the spur's centre line, inside its 3.4 m mouth)
	for i in range(0, 15):
		var a := -PI * 0.5 + deg_to_rad(50.0) * float(i) / 15.0
		out.append(Vector3(RoadRamps.X_TOP * cos(a), RoadRamps.X_TOP * sin(a), RING_SPEED))
	var a0 := deg_to_rad(-40.0)
	var b0 := Vector2(RoadRamps.X_TOP * cos(a0), RoadRamps.X_TOP * sin(a0))
	var b1 := b0 + Vector2(-sin(a0), cos(a0)) * 10.0
	var b2 := Vector2(31.0, 0.0)
	var b3 := Vector2(42.0, 0.0)
	for i in range(0, 13):
		var t := float(i) / 12.0
		var q := b0.bezier_interpolate(b1, b2, b3, t)
		out.append(Vector3(q.x, q.y, MOUTH_SPEED))
	var x := 44.0
	while x < RingSite.SPUR_END:
		out.append(Vector3(x, 0.0, RING_SPEED))
		x += 2.0
	var run: float = PocketSite.arm_len()
	var turn := float(pk_of().turn)
	var s := 0.0
	while s <= run:
		var a: Dictionary = PocketSite.arm_at(s, turn)
		var p: Vector2 = a.p
		out.append(Vector3(p.x, p.y, ARM_SPEED))
		s += 2.0
	# round the lot: in along the land side, across by the ship, back
	var v0 := (PocketSite.ARC_R + PocketSite.ARM_STRAIGHT) * turn
	var mouth := RingSite.SPUR_END + PocketSite.ARC_R
	var inner := PocketSite.LOT_X0 + 14.0
	var outer := PocketSite.LOT_X1 - 12.0
	var far := v0 + (PocketSite.LOT_LEN - 12.0) * turn
	var lot: Array[Vector2] = [Vector2(mouth, v0 + 12.0 * turn), Vector2(inner, v0 + 30.0 * turn), Vector2(inner, far),
		Vector2(outer, far), Vector2(outer, v0 + 30.0 * turn), Vector2(mouth, v0 + 12.0 * turn), Vector2(mouth, v0)]
	for i in lot.size() - 1:
		var n := ceili(lot[i].distance_to(lot[i + 1]) / 2.0)
		for j in n:
			var q := lot[i].lerp(lot[i + 1], float(j) / float(n))
			out.append(Vector3(q.x, q.y, LOT_SPEED))
	# back up the arm and onto the spur
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

func _pocket_node() -> Node3D:
	for c in game.get_children():
		if String(c.name) == "Pocket_pier":
			return c as Node3D
	return null

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
			_check(String(RoadMap.rings()[SITE].id) == "x5" and RoadMap.pocket_of_ring(SITE).get("id") == "pier", "ring %d is %s, pocket %s" % [SITE, RoadMap.rings()[SITE].id, RoadMap.pocket_of_ring(SITE)])
			_check(RoadMap.pocket_at(SITE, -1).get("kind") == "street_end" and RoadMap.pockets_of_ring(SITE).size() == 2, "ring %d has %d pockets, -1 side %s" % [SITE, RoadMap.pockets_of_ring(SITE).size(), RoadMap.pocket_at(SITE, -1)])
			site_s = float(RoadMap.rings()[SITE].s)
			var rc := floori(site_s / L)
			# the wall stands out past the pocket on its side only, along its reach
			_check(RoadRamps.pocket_bound(rc + 2, 1) == PocketSite.BOUND and RoadRamps.pocket_bound(rc + 4, 1) == PocketSite.BOUND, "the pocket's bound beside chunks 2 and 4: %.0f, %.0f" % [RoadRamps.pocket_bound(rc + 2, 1), RoadRamps.pocket_bound(rc + 4, 1)])
			_check(RoadRamps.pocket_bound(rc + 2, -1) == 0.0 and RoadRamps.pocket_bound(rc - 2, 1) == 0.0 and RoadRamps.pocket_bound(rc + 5, 1) == 0.0, "the pocket's bound where it has none: %.0f, %.0f, %.0f" % [RoadRamps.pocket_bound(rc + 2, -1), RoadRamps.pocket_bound(rc - 2, 1), RoadRamps.pocket_bound(rc + 5, 1)])
			_check(RoadMap.pins()[RoadMap.lap_chunk(rc + 5)] == RoadMap.PIN_STRAIGHT, "chunk 5 past the ring is not pinned straight")
			# the ring's spur is open at its end: no nose box at SPUR_END
			var look: Dictionary = RingSite.look_of(SITE)
			_check(String(look.pocket).begins_with("pier") and int(look.spur) == 1 and (look.pocket_sides as Array).has(1), "the ring's look: %s" % [look])
			path = _line()
			path_i = 0
			_stand(p, RoadFrame.pose(path[0].x, 0.45, _z_of(path[0].y), 0.0))
			_drive(p)
			game.rescue.rescued.connect(func(r: String) -> void:
				rescues += 1
				var uu := RoadFrame.unroll(p.global_position)
				print("pocket_pier: rescued (%s) at %.1f m out, %.0f m from the centre, %.1f m up; bounds %s" % [r, uu.x, RoadFrame.s_at(uu.z) - site_s, uu.y, game.rescue.call("_bounds_at", uu.z)]))
			_next(1)
		1:
			if phase_ticks < 30:
				return false
			if phase_ticks == 30:
				# standing near the ring, the pocket node is up and solid
				var node := _pocket_node()
				_check(node != null, "no pocket node in the game")
				if node != null:
					var counts: Dictionary = node.call("counts")
					_check(node.visible and int(counts.draws) == 2 and int(counts.faces) > 60 and int(counts.boxes) > 10 and int(counts.pools) > 6, "the pocket node: %s, visible %s" % [counts, node.visible])
					print("pocket_pier: the pocket node %s" % [counts])
			var rc: Array = game.rescue.call("check")
			if String(rc[0]) != "" and out_reports < 3:
				out_reports += 1
				print("pocket_pier: out of bounds (%s) at %.1f m out, %.0f m from the centre, %.1f m up; bounds %s" % [rc[0], u.x, w, u.y, game.rescue.call("_bounds_at", u.z)])
			var px := u.x * float(pk_of().side)
			var on_pocket := px > RoadRamps.SPUR_REACH + 0.5 and PocketSite.covers(pk_of(), px, w, -1.0)
			if on_pocket and p.linear_velocity.length() > 2.0:
				if place.is_empty():
					off_missing += 1
					if off_missing <= 3:
						_fail("not off the main road on the pocket, %.0f m from the centre (%.1f m out, %.1f m up)" % [w, u.x, u.y])
				elif String(place.part) != "pocket":
					part_wrong += 1
					if part_wrong <= 3:
						_fail("on the pocket as part %s, %.0f m from the centre (%.1f m out)" % [place.part, w, u.x])
				var dy: float = PocketSite.deck_y(pk_of(), px, w)
				if not is_inf(dy):
					var over := u.y - dy
					if over < -0.3:
						below += 1
						deepest = minf(deepest, over)
					if over > 1.6:
						above += 1
						highest = maxf(highest, over)
				if px > PocketSite.LOT_X0 and w * float(pk_of().turn) > PocketSite.ARC_R + PocketSite.ARM_STRAIGHT and not lot_reached:
					lot_reached = true
					print("pocket_pier: on the pier, %.0f m from the ring's centre, %.1f m out, %.2f m up" % [w, u.x, u.y])
				if not saved_on_pier and lot_reached:
					saved_on_pier = true
					var run: Dictionary = game.saver.capture()
					var off: Dictionary = run.road.get("off", {})
					_check(off.get("part") == "pocket" and off.get("id") == "x5", "the save taken on the pier says %s" % [off])
			if path_i >= path.size() - 3:
				_check(lot_reached, "the bot never reached the pier")
				_check(off_missing == 0, "off the main road was not set on %d ticks on the pocket" % off_missing)
				_check(part_wrong == 0, "the part was not 'pocket' on %d ticks" % part_wrong)
				_check(below == 0, "the car was under the pocket's deck on %d ticks (deepest %.2f m)" % [below, deepest])
				_check(above == 0, "the car was over the pocket's deck on %d ticks (highest %.2f m)" % [above, highest])
				_check(rescues == 0, "the rescue put the car back %d times on the pocket" % rescues)
				_check(saved_on_pier, "the bot never got to the save point on the pier")
				_check(not place.is_empty() and String(place.part) == "spur", "back on the spur the place is %s" % [place])
				print("pocket_pier: down the arm, round the pier and back: %d off-main misses, %d wrong parts, %d under, %d over" % [off_missing, part_wrong, below, above])
				_next(2)
		2:
			if phase_ticks < 20:
				return false
			# put-back from the pier: stand on the lot, let the rescue see it, then ask
			path = []
			var turn := float(pk_of().turn)
			var lv := (PocketSite.ARC_R + PocketSite.ARM_STRAIGHT + 50.0) * turn
			_stand(p, RoadFrame.pose(PocketSite.LOT_X0 + 20.0, PocketSite.PIER_Y + 0.5, _z_of(lv), PI * 0.5))
			_next(3)
		3:
			if phase_ticks < 60:
				return false
			if phase_ticks == 60:
				_check(not place.is_empty() and String(place.part) == "pocket", "a car stood on the pier is at %s" % [place])
				game.rescue.call("_put_back")
				return false
			# put back half a metre over the deck: let it settle before reading it
			if phase_ticks < 90 or (p.linear_velocity.length() > 0.3 and phase_ticks < 60 + hz * 6):
				return false
			var fwd := RoadFrame.dir_to_road(u.z, -p.global_transform.basis.z)
			_check(not place.is_empty() and (String(place.part) == "spur" or String(place.part) == "pocket") and absf(w) < 4.0 and u.x > RoadRamps.RING_OUT and u.x < RingSite.SPUR_END, "put back %.0f m from the centre, %.1f m out, at %s" % [w, u.x, place])
			_check(fwd.x < -0.9, "put back facing %.2f across (-1 = toward the ring)" % fwd.x)
			_check(p.linear_velocity.length() < 1.0 and absf(u.y - RoadRamps.RAMP_H) < 1.0, "put back moving at %.1f m/s, %.1f m up" % [p.linear_velocity.length(), u.y])
			print("pocket_pier: put back from the pier at the top of the arm, %.1f m out, facing %.2f toward the ring" % [u.x, -fwd.x])
			_finish()
			return true
	return false

func _finish() -> void:
	SaveStore.clear_run()
	print("pocket_pier: %d checks, %d failed" % [checks, fails.size()])
	quit(1 if not fails.is_empty() else 0)
