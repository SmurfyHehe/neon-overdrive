extends SceneTree

# Live exits (ring sites R1): every exit can be taken and rejoined, both ways.
#
# 1. The map: every act-1 ring site (not the tunnel district) has an exit per
#    carriageway, each RING_GORE before the ring in its own direction; the
#    ramp chunks are pinned level and the pad's straight; every district has
#    its signed U-turn at its start unless a crossing stands there; the ramp
#    never climbs more than 6 %.
# 2. Chunks: a ramp chunk built fresh, a pooled chunk rebuilt into it, and the
#    same chunk rebuilt again all hold the same things (ramp mesh, collision,
#    light pools, every MultiMesh's instance count); rebuilt into a plain
#    chunk, the ramps are gone. Exit gantries stand 400 m and 1 km before each
#    gore.
# 3. Driving, on the curved, hilly loop with no traffic: at every site and on
#    both carriageways a bot leaves the outside lane, drives up the ramp, turns
#    a full circle on the pad, comes down the other ramp and rejoins, heading
#    the way that carriageway flows. It never touches a wall, is never off the
#    deck, and the grade it climbs is never above 6 %.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/world/exits_live.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")

const L := 50.0
const START_V := 260.0      # the bot starts this far before the ring's centre
const END_V := 330.0        # and is done this far after it
const LANE_X := 11.6        # the outside lane's centre
const SLIP_X := RoadRamps.X_LANE + RoadRamps.HALF
const LOOP_R := RoadRamps.PAD_X - RoadRamps.X_TOP   # the circle on the pad
const RAMP_SPEED := 13.0
const PAD_SPEED := 6.5
const MAX_GRADE := 0.06
## The grade the bot is measured climbing, over 8 m at a time, may read this
## much over (its springs move a centimetre or two in 8 m).
const DRIVEN_SLACK := 0.005

var game: Node
var ticks := 0
var fails: Array[String] = []
var checks := 0

# the run in hand
var runs: Array = []        # [ring index, side]
var run_i := -1
var path: Array[Vector3] = []   # (x across, u along from the ring's centre, target speed)
var path_i := 0
var site_s := 0.0
var side := 1
var run_ticks := 0
var top_y := 0.0
var wall_hits := 0
var off_deck := 0
var worst_grade := 0.0
var _last_pos := Vector3.ZERO
var _grade_from := Vector3.ZERO
var done_runs := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		_fail(msg)

func _initialize() -> void:
	RoadFrame.align = null
	RoadFrame.layout = null
	RoadFrame.origin_index = 0
	RoadMap.use(0, 1)
	_map()
	_chunks()
	RoadMap.use(RoadMap.ENDLESS)
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_ROAD_SEED", "4242")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)

# ---------- 1. the map ----------

func _map() -> void:
	var rings := RoadMap.rings()
	_check(rings.size() == 7, "act 1 has %d ring sites, expected 7 (8 districts, one a tunnel)" % rings.size())
	_check(RoadMap.exits().size() == rings.size() * 2, "%d exits for %d ring sites" % [RoadMap.exits().size(), rings.size()])
	for e in RoadMap.exits():
		_check(absf(float(e.s) - (float(e.centre) - float(e.side) * RoadMap.RING_GORE)) < 1e-6, "exit %s is not %.0f m before its ring" % [e.id, RoadMap.RING_GORE])
	var pins := RoadMap.pins()
	for r in rings.size():
		var rc := floori(float(rings[r].s) / L)
		_check(absf(float(rings[r].s) - float(rc) * L) < 1e-6, "ring %s is not on a chunk join" % rings[r].id)
		for k in range(-2, 2):
			_check(pins[rc + k] == RoadMap.PIN_STRAIGHT, "ring %s: chunk %d (the pad) is not pinned straight and level" % [rings[r].id, rc + k])
		for k in range(-RoadMap.RAMP_CHUNKS, RoadMap.RAMP_CHUNKS):
			_check(pins[rc + k] != 0, "ring %s: ramp chunk %d is not pinned level" % [rings[r].id, rc + k])
			_check(RoadMap.ramp_zone(rc + k) and RoadMap.ring_at(rc + k) == r and RoadMap.ring_k(rc + k) == k, "ring %s: chunk %d does not know its place at the site" % [rings[r].id, rc + k])
			_check(RoadMap.aux(rc + k) == Vector2.ZERO, "ring %s: a slip lane beside ramp chunk %d" % [rings[r].id, rc + k])
			_check(RoadMap.ramp_zone(rc + k + RoadMap.period), "ring %s: chunk %d is not a ramp chunk a lap on" % [rings[r].id, rc + k])
		_check(not RoadMap.ramp_zone(rc - RoadMap.RAMP_CHUNKS - 1) and not RoadMap.ramp_zone(rc + RoadMap.RAMP_CHUNKS), "ring %s: ramps past the gores" % rings[r].id)
		# the slip lane is whole at each gore and closed at its far end
		_check(absf(RoadMap.aux(rc - RoadMap.RAMP_CHUNKS - 1).y - RoadMap.AUX_W) < 1e-6, "ring %s: the slip lane is %.1f m wide at the first gore" % [rings[r].id, RoadMap.aux(rc - RoadMap.RAMP_CHUNKS - 1).y])
		_check(absf(RoadMap.aux(rc + RoadMap.RAMP_CHUNKS).x - RoadMap.AUX_W) < 1e-6, "ring %s: the slip lane is %.1f m wide at the second gore" % [rings[r].id, RoadMap.aux(rc + RoadMap.RAMP_CHUNKS).x])
		_check(RoadMap.aux(rc - RoadMap.RAMP_CHUNKS - RoadMap.AUX_CHUNKS).x == 0.0 and RoadMap.aux(rc + RoadMap.RAMP_CHUNKS + RoadMap.AUX_CHUNKS - 1).y == 0.0, "ring %s: the slip lane does not close" % rings[r].id)
	# a slip lane never changes width across a chunk join, and is shut at a crossing
	for c in RoadMap.period:
		var a := RoadMap.aux(c)
		var b := RoadMap.aux(c + 1)
		if not RoadMap.ramp_zone(c) and not RoadMap.ramp_zone(c + 1):
			_check(absf(a.y - b.x) < 1e-6, "the slip lane jumps from %.1f to %.1f m between chunks %d and %d" % [a.y, b.x, c, c + 1])
	for j in RoadMap.junctions():
		_check(RoadMap.aux(floori(j / L)) == Vector2.ZERO, "a slip lane runs through the crossing at %.0f m" % j)
	# gaps: one at each district's start, unless a crossing is within 100 m
	var gaps := RoadMap.gaps()
	var want := 0
	for d in RoadMap.district_count():
		var gs := RoadMap.district_start(d) + RoadMap.GAP_INSET
		var near := false
		for j in RoadMap.junctions():
			if absf(fposmod(j - gs + RoadMap.length() * 0.5, RoadMap.length()) - RoadMap.length() * 0.5) < RoadMap.GAP_CLEAR_OF_CROSSING:
				near = true
		if near:
			continue
		want += 1
		_check(RoadMap.gap_in(floori(gs / L)) and RoadBarriers.gap_kind(floori(gs / L)) == "uturn", "district %d has no signed U-turn at its start" % (d + 1))
	_check(gaps.size() == want and want >= 4, "%d gaps on the lap, expected %d" % [gaps.size(), want])
	for g in gaps:
		_check(not RoadMap.ramp_zone(floori(float(g.s) / L)), "gap %s is beside a ramp" % g.id)
	# the ramp's own shape
	var worst := 0.0
	var v := 0.0
	while v < RoadRamps.V_GORE:
		worst = maxf(worst, absf(RoadRamps.y_at(v) - RoadRamps.y_at(v + 0.25)) / 0.25)
		v += 0.25
	_check(worst <= MAX_GRADE and absf(worst - RoadRamps.max_grade()) < 0.002, "the ramp climbs at up to %.2f %% (limit 6)" % (worst * 100.0))
	_check(absf(RoadRamps.y_at(RoadRamps.V_TOP) - RoadRamps.RAMP_H) < 1e-4 and RoadRamps.y_at(RoadRamps.V_NOSE) == 0.0, "the ramp does not run from the road to the pad's height")
	_check(absf(RoadRamps.x_at(RoadRamps.V_GORE) - SLIP_X) < 1e-4 and absf(RoadRamps.x_at(0.0) - RoadRamps.X_TOP) < 1e-4, "the ramp does not run from the slip lane to the pad")
	# signs: 400 m and 1 km before each gore, on that exit's side
	var signs := 0
	for c in RoadMap.period:
		for sg in RoadMap.exit_signs(c):
			signs += 1
			var ring: Dictionary = rings[int(sg.ring)]
			var gore := float(ring.s) - float(sg.side) * RoadMap.RING_GORE
			var at := (float(c) * L + 2.5) if int(sg.side) > 0 else (float(c) * L + 47.5)
			var before := fposmod((gore - at) * float(sg.side), RoadMap.length())
			_check(absf(before - (1000.0 if sg.far else 400.0)) < 3.0, "an exit %d sign stands %.0f m before its gore" % [ring.number, before])
	_check(signs == rings.size() * 4, "%d exit signs for %d ring sites (expected 4 each)" % [signs, rings.size()])
	print("exits_live: %d ring sites, %d exits, %d gaps, %d exit signs, steepest %.2f %%" % [rings.size(), RoadMap.exits().size(), gaps.size(), signs, worst * 100.0])

# ---------- 2. chunks ----------

func _cfg(c: int) -> Dictionary:
	var a := RoadMap.aux(c)
	return {"own_lanes": 4, "onc_lanes": 4, "barrier": "concrete", "gap": RoadMap.gap_in(c), "gap_kind": RoadBarriers.gap_kind(c), "aux": [a.x, a.y, a.x, a.y]}

## Everything countable about a built chunk.
func _census(chunk: Node3D) -> Dictionary:
	var out: Dictionary = RoadRamps.counts(chunk)
	for n in chunk.get_children():
		if n is MultiMeshInstance3D:
			out[String(n.name)] = (n as MultiMeshInstance3D).multimesh.visible_instance_count
		for m in n.get_children():
			if m is MultiMeshInstance3D:
				out["%s/%s" % [n.name, m.name]] = (m as MultiMeshInstance3D).multimesh.visible_instance_count
	var lots := 0
	for i in B._building_slots() * 2:
		if (chunk.get_node(NodePath("BuildingMesh%d" % i)) as MeshInstance3D).visible:
			lots += 1
	out["buildings"] = lots
	out["bounds"] = B.bounds(chunk)
	return out

func _chunks() -> void:
	var rc := floori(float(RoadMap.rings()[1].s) / L)   # exit 2: no crossing on its ramps
	var plain := rc + 24   # the tunnel-free middle of a later district's start
	while RoadMap.ring_at(plain) >= 0:
		plain += 1
	var pooled := B.build_chunk(plain, _cfg(plain - 1), _cfg(plain))
	var none := _census(pooled)
	_check(none.verts == 0 and none.faces == 0 and none.boxes == 0 and none.pools == 0, "a chunk with no ring site has ramp parts: %s" % [none])
	_check(not (pooled.get_node(^"Ramps") as MeshInstance3D).visible, "a chunk with no ring site shows its ramp mesh")
	for k in range(-RoadMap.RAMP_CHUNKS - 1, RoadMap.RAMP_CHUNKS + 1):
		var c := rc + k
		var fresh := B.build_chunk(c, _cfg(c - 1), _cfg(c))
		var want := _census(fresh)
		B.rebuild_chunk(pooled, c, _cfg(c - 1), _cfg(c))
		var got := _census(pooled)
		_check(str(got) == str(want), "chunk %d (k %d) rebuilt from the pool differs from a fresh one:\n  pool  %s\n  fresh %s" % [c, k, got, want])
		B.rebuild_chunk(pooled, c, _cfg(c - 1), _cfg(c))
		_check(str(_census(pooled)) == str(want), "chunk %d (k %d) rebuilt twice differs" % [c, k])
		var ramp := k >= -RoadMap.RAMP_CHUNKS and k < RoadMap.RAMP_CHUNKS
		if ramp:
			_check(want.verts > 0 and want.faces > 0 and want.boxes > 0 and want.pools > 0, "ramp chunk %d (k %d) is missing parts: %s" % [c, k, want])
			_check(want.buildings == 0, "ramp chunk %d (k %d) still has %d buildings" % [c, k, want.buildings])
			_check((want.bounds as Vector2).x == RoadRamps.bound(c) and (want.bounds as Vector2).y == RoadRamps.bound(c), "ramp chunk %d: walls at %s, expected %.0f" % [c, want.bounds, RoadRamps.bound(c)])
		else:
			_check(want.faces == 0 and want.boxes == 0, "slip-lane chunk %d (k %d) has ramp collision" % [c, k])
			_check(want.verts > 0, "slip-lane chunk %d (k %d) has no lane line" % [c, k])
		fresh.free()
	B.rebuild_chunk(pooled, plain, _cfg(plain - 1), _cfg(plain))
	_check(str(_census(pooled)) == str(none), "a ramp chunk rebuilt into a plain one keeps ramp parts:\n  %s\n  %s" % [_census(pooled), none])
	# a gantry chunk draws the gantry: post, arm, panel, three lines, two lamps
	for c in RoadMap.period:
		if RoadMap.exit_signs(c).is_empty():
			continue
		var sign_root := B.build_chunk(c, _cfg(c - 1), _cfg(c))
		var n := (sign_root.get_node(^"NameSigns") as MultiMeshInstance3D).multimesh.visible_instance_count
		_check(n >= 8 * RoadMap.exit_signs(c).size(), "chunk %d draws %d sign parts for %d exit gantries" % [c, n, RoadMap.exit_signs(c).size()])
		sign_root.free()
		break
	pooled.free()

# ---------- 3. driving ----------

## The bot's line for one exit, in the site's own terms: x metres out on its
## side, w metres along the road past the ring's centre in ITS direction of
## travel, and the speed to hold.
func _line() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var w := -START_V
	while w < -RoadRamps.V_GORE - 1.0:
		# the outside lane, moving onto the slip lane over the last 45 m
		out.append(Vector3(lerpf(LANE_X, SLIP_X, smoothstep(-250.0, -205.0, w)), w, RAMP_SPEED))
		w += 2.0
	w = -RoadRamps.V_GORE
	while w < 0.0:
		out.append(Vector3(RoadRamps.x_at(-w), w, PAD_SPEED if w > -40.0 else RAMP_SPEED))
		w += 2.0
	# a full circle on the pad, starting and ending on the ramps' line
	for i in range(0, 48):
		var a := TAU * float(i) / 48.0
		out.append(Vector3(RoadRamps.PAD_X - LOOP_R * cos(a), LOOP_R * sin(a), PAD_SPEED))
	w = 0.0
	while w <= RoadRamps.V_GORE:
		out.append(Vector3(RoadRamps.x_at(w), w, PAD_SPEED if w < 30.0 else RAMP_SPEED))
		w += 2.0
	while w < END_V:
		out.append(Vector3(lerpf(SLIP_X, LANE_X, smoothstep(205.0, 250.0, w)), w, RAMP_SPEED))
		w += 2.0
	return out

## Road-space z of the site point w metres past the ring's centre in the
## bot's direction of travel.
func _z_of(w: float) -> float:
	return float(RoadFrame.origin_index) * L - (site_s + float(side) * w)

func _world(pt: Vector3, y: float) -> Vector3:
	return RoadFrame.roll(Vector3(float(side) * pt.x, y, _z_of(pt.y)))

func _next_run(p: PlayerCar) -> bool:
	run_i += 1
	if run_i >= runs.size():
		return false
	var ring: Dictionary = RoadMap.rings()[int(runs[run_i][0])]
	side = int(runs[run_i][1])
	# the lap the car is on now, so the pool only has to move, not jump laps
	var here := RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)
	site_s = float(ring.s) + roundf((here - float(ring.s)) / RoadMap.length()) * RoadMap.length()
	path = _line()
	path_i = 0
	run_ticks = 0
	top_y = 0.0
	var t := RoadFrame.pose(float(side) * path[0].x, 0.0, _z_of(path[0].y), 0.0 if side > 0 else PI)
	t.origin.y += 0.45
	game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", RoadFrame.unroll(p.global_position).z)
	game.call("flush_rebuilds")
	_last_pos = p.global_position
	_grade_from = p.global_position
	return true

func _drive(p: PlayerCar) -> void:
	p.driver = func(c: Vehicle) -> void:
		if path.is_empty():
			return
		# the nearest point of the line ahead of where the bot has got to
		var u := RoadFrame.unroll(c.global_position)
		var best := INF
		for i in range(path_i, mini(path_i + 12, path.size())):
			var d := Vector2(float(side) * path[i].x - u.x, _z_of(path[i].y) - u.z).length()
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
		var target := _world(path[j], 0.0)
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

func _watch(p: PlayerCar) -> void:
	var u := RoadFrame.unroll(p.global_position)
	var w := (RoadFrame.s_at(u.z) - site_s) * float(side)
	top_y = maxf(top_y, u.y)
	for body in p.get_colliding_bodies():
		if body is CollisionObject3D and ((body as CollisionObject3D).collision_layer & (1 << (CarSpec.WALL_LAYER - 1))) != 0:
			wall_hits += 1
			if wall_hits <= 3:
				_fail("exit %s: touched a wall (%s) %.0f m from the ring's centre, %.1f m out, %.1f m up" % [_name(), body.name, w, u.x * float(side), u.y])
	# on the ramps and the pad the car rides the deck: its height is the deck's
	if absf(w) < RoadRamps.V_NOSE - 5.0:
		var deck := RoadRamps.RAMP_H if u.x * float(side) > RoadRamps.X_TOP + RoadRamps.HALF else RoadRamps.y_at(absf(w))
		if absf(u.y - deck) > 0.9 or p.global_basis.y.y < 0.8:
			off_deck += 1
			if off_deck <= 3:
				_fail("exit %s: off the deck %.0f m from the ring's centre (%.1f m out, %.2f m up, deck at %.2f, up %.2f)" % [_name(), w, u.x * float(side), u.y, deck, p.global_basis.y.y])
	# the grade it climbs, over each 8 m of ground covered
	var flat := Vector2(p.global_position.x - _grade_from.x, p.global_position.z - _grade_from.z).length()
	if flat >= 8.0:
		var g := absf(p.global_position.y - _grade_from.y) / flat
		worst_grade = maxf(worst_grade, g)
		if g > MAX_GRADE + DRIVEN_SLACK:
			_fail("exit %s: a %.1f %% grade %.0f m from the ring's centre" % [_name(), g * 100.0, w])
		_grade_from = p.global_position

func _name() -> String:
	return "%s%s" % [RoadMap.rings()[int(runs[run_i][0])].id, "a" if side > 0 else "b"]

func _end_run(p: PlayerCar) -> void:
	var u := RoadFrame.unroll(p.global_position)
	var at := RoadMap.where(u.z, -p.global_transform.basis.z)
	_check(top_y > RoadRamps.RAMP_H - 0.3, "exit %s: the bot only got %.1f m up" % [_name(), top_y])
	_check(absf(u.y) < 0.6, "exit %s: the bot ends %.1f m above the road" % [_name(), u.y])
	_check(int(at.dir) == side, "exit %s: the bot rejoined heading %d on the %d carriageway" % [_name(), at.dir, side])
	_check(u.x * float(side) > 0.4 and u.x * float(side) < RoadRamps.X_LANE + RoadMap.AUX_W, "exit %s: the bot rejoined %.1f m out" % [_name(), u.x * float(side)])
	_check(p.linear_velocity.length() > 5.0, "exit %s: the bot is stopped at the end" % _name())
	done_runs += 1
	print("exit %s: up %.2f m, rejoined at %.0f m heading %d, %.1f s" % [_name(), top_y, at.s, at.dir, float(run_ticks) / float(Engine.physics_ticks_per_second)])

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	var p: PlayerCar = game.get("player")
	if ticks < 3:
		return false
	if ticks == 3:
		_check(RoadMap.is_loop() and RoadFrame.layout != null and RoadFrame.layout.exits_live, "the game is not on the loop with live exits")
		# the whole lap is tilted a little so it ends at the height it began:
		# the ramp's own grade plus that tilt is what a car climbs
		var tilt := absf(RoadFrame.start_grade(floori(float(RoadMap.rings()[0].s) / L)))
		_check(RoadRamps.max_grade() + tilt <= MAX_GRADE, "the ramp's %.2f %% on the lap's %.2f %% tilt is over 6 %%" % [RoadRamps.max_grade() * 100.0, tilt * 100.0])
		print("exits_live: ramp %.2f %%, lap tilt %.2f %%" % [RoadRamps.max_grade() * 100.0, tilt * 100.0])
		for r in RoadMap.rings().size():
			runs.append([r, 1])
			runs.append([r, -1])
		_drive(p)
		if not _next_run(p):
			_finish()
			return true
		return false
	run_ticks += 1
	if run_ticks == 30:   # the car has settled on its wheels
		_grade_from = p.global_position
	if run_ticks > 30:
		_watch(p)
	var hz := Engine.physics_ticks_per_second
	var timed_out := run_ticks > hz * 150
	if timed_out:
		_fail("exit %s: timed out %.0f m from the ring's centre" % [_name(), (RoadFrame.s_at(RoadFrame.unroll(p.global_position).z) - site_s) * float(side)])
	if path_i >= path.size() - 3 or timed_out:
		if not timed_out:
			_end_run(p)
		if not _next_run(p):
			_finish()
			return true
	return false

func _finish() -> void:
	_check(done_runs == runs.size(), "%d of %d exits were driven to the end" % [done_runs, runs.size()])
	_check(wall_hits == 0, "the bot touched a wall on %d ticks" % wall_hits)
	_check(off_deck == 0, "the bot was off the deck on %d ticks" % off_deck)
	print("exits_live: %d of %d exits driven, steepest grade driven %.2f %%, %d wall ticks, %d off-deck ticks" % [done_runs, runs.size(), worst_grade * 100.0, wall_hits, off_deck])
	print("exits_live: %d checks, %d failed" % [checks, fails.size()])
	quit(1 if not fails.is_empty() else 0)
