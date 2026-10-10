extends SceneTree

# Median barrier test (R1, police build plan 2026-10-09 section 3d: "hit each
# type at three speeds and three angles, check no car passes through, flips
# on a cable, or gets stuck on a cushion").
#
# Part 1, the rules (no physics):
# - type by district: concrete downtown and industrial, guardrail in the
#   residential and strip districts, cable where a live median split opens
#   the middle wider than RoadBarriers.CABLE_MEDIAN;
# - at most one crossover per district, on a straight chunk, clear of the
#   district's first and blend chunks and of planned layout changes; most
#   districts get one;
# - a gap chunk's collision: the open stations disabled, every other piece
#   enabled, two cushions; a plain chunk: every piece, no cushions.
#
# Part 2, the hits (the real game, one boot): the player's car launched from
# the lane next to the barrier into it, for each type at SPEEDS x ANGLES
# with full throttle and the wheel straight, then head-on into a crossover's
# crash cushion at CUSHION_SPEEDS. Each run:
# - it reached the barrier (a real hit), never got through or over it (the
#   car's centre never crosses the centre line, never rises over MAX_RISE);
# - it stays near upright (tilt under MAX_TILT) and gains no speed from the
#   barrier (MAX_KICK in one tick);
# - it ends on its wheels (END_TILT, three wheels down at some tick), so the
#   player drives off without a reset;
# - cable: it is slower after the run than the same run against concrete;
# - guardrail: a hit over DENT_FROM sideways dents the piece it hit;
# - cushion: the car is stopped (under CUSHION_STOP m/s) at the end of the
#   run, the cushion crumpled, and the car is not stuck on top of it.
# NEON_BARRIER_ONLY="cable" runs one family; NEON_BARRIER_LOG=1 prints ticks.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/barrier_hit.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Districts := preload("res://scripts/world/districts.gd")

const SPEEDS := [10.0, 25.0, 45.0]  # m/s (36 to 162 km/h)
const ANGLES := [10.0, 30.0, 60.0]  # degrees toward the barrier
const CUSHION_SPEEDS := [10.0, 20.0, 30.0]
const RUN_SECS := 3.0
const MAX_TILT := 30.0
const MAX_KICK := 1.5
const MAX_RISE := 0.8  # m above its resting height
const END_TILT := 15.0
const END_SECS := 0.5
const CUSHION_STOP := 3.0

var rate := 120
var logger := Harness.ErrorCounter.new()
var game: Node
var tick := 0
var fails: Array[String] = []
var log_ticks := false

var scenarios: Array = []  # [kind, speed, angle]; kind "cushion" is head-on
var index := -1
var run_tick := 0
var rest_y := 0.0
var prev_speed := 0.0
var s := {}
var concrete_end := {}  # "speed,angle" -> end speed against concrete
var cushion_root: Node3D

func _initialize() -> void:
	OS.add_logger(logger)
	ExhaustTune.save_path = "user://autotune/test_barrier_hit_exhaust.json"
	Engine.physics_ticks_per_second = rate
	log_ticks = OS.get_environment("NEON_BARRIER_LOG") == "1"
	_check_rules()
	var only := OS.get_environment("NEON_BARRIER_ONLY")
	for kind in [RoadBarriers.CONCRETE, RoadBarriers.GUARDRAIL, RoadBarriers.CABLE]:
		if only != "" and only != kind and not (only == "cable" and kind == RoadBarriers.CONCRETE):
			continue
		for v in SPEEDS:
			for a in ANGLES:
				scenarios.append([kind, v, a])
	if only == "" or only == "cushion":
		for v in CUSHION_SPEEDS:
			scenarios.append(["cushion", v, 0.0])
	# A straight, flat road: the hits are measured across world x.
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_LAYOUT", "0")
	RoadBarriers.force_kind = scenarios[0][0]
	game = Harness.boot(self, 0, 300.0, 4242)

# ---------- part 1 ----------

func _check_rules() -> void:
	var saved_align := RoadFrame.align
	var saved_layout := RoadFrame.layout
	# Crash sounds (CrashAudio.classify): a barrier follows the same rules as
	# any wall. A side hit is a crash; the car touching it with a mostly
	# vertical normal (its underside on the barrier top or a cushion) is the
	# underbody, which has its own sound and never triggers a crash.
	for kind in [RoadBarriers.CONCRETE, RoadBarriers.GUARDRAIL, RoadBarriers.CABLE, "cushion"]:
		var wall := StaticBody3D.new()
		CarSpec.make_wall(wall)
		wall.set_meta("barrier", kind)
		if CrashAudio.classify(wall, Vector3(1.0, 0.0, 0.0)) != "concrete":
			_fail("crash sounds: a side hit on %s is not a crash surface" % kind)
		if CrashAudio.classify(wall, Vector3(0.1, 0.99, 0.0)) != "underbody":
			_fail("crash sounds: the underside on %s is not underbody" % kind)
		wall.free()
	# Districts -> types.
	for c in range(0, 400):
		var want: String = RoadBarriers.BY_DISTRICT[Districts.name_at(c)]
		if RoadBarriers.kind_at(c) != want:
			_fail("rules: chunk %d (%s) has %s, expected %s" % [c, Districts.name_at(c), RoadBarriers.kind_at(c), want])
			break
	# Cable where a live split is wide.
	RoadFrame.align = null
	var lay := RoadLayout.new(7, null, 600.0)
	lay.splits_live = true
	RoadFrame.layout = lay
	var cables := 0
	var wide := 0
	for c in range(0, 600):
		var w := lay.median_extra((float(c) + 0.5) * RoadChunkBuilder.CHUNK_LEN)
		var is_cable := RoadBarriers.kind_at(c) == RoadBarriers.CABLE
		if w > RoadBarriers.CABLE_MEDIAN:
			wide += 1
			if not is_cable:
				_fail("rules: chunk %d median +%.1f m is not cable" % [c, w])
				break
		elif is_cable:
			_fail("rules: chunk %d is cable with a +%.1f m median" % [c, w])
			break
		if is_cable:
			cables += 1
	if wide == 0:
		_fail("rules: no wide median in 30 km of splits every 600 m")
	print("rules: cable on %d of %d chunks with a split wider than %.0f m" % [cables, wide, RoadBarriers.CABLE_MEDIAN])
	# Gaps, on a curvy road with the normal layout plan.
	var runs := 60
	var with_gap := 0
	for seed_value in [11, 4242]:
		RoadFrame.align = RoadAlignment.new(seed_value, 1.0, 0.0, 0.0)
		RoadFrame.layout = RoadLayout.new(seed_value, RoadFrame.align, 1.0)
		for run in runs:
			var g := RoadBarriers.gap_chunk(run)
			var n := 0
			for c in range(run * Districts.RUN, (run + 1) * Districts.RUN):
				if RoadBarriers.has_gap(c):
					n += 1
			if n > 1:
				_fail("rules: district %d has %d crossovers" % [run, n])
			if g < 0:
				continue
			with_gap += 1
			var into := g - run * Districts.RUN
			if into < RoadBarriers.GAP_FIRST or into > RoadBarriers.GAP_LAST:
				_fail("rules: district %d crossover in its chunk %d" % [run, into])
			for i in [g - 1, g, g + 1]:
				if absf(RoadFrame.curvature(i)) > RoadBarriers.GAP_MAX_K:
					_fail("rules: crossover at chunk %d on a bend (radius %.0f m)" % [g, 1.0 / absf(RoadFrame.curvature(i))])
			var s0 := float(g) * RoadChunkBuilder.CHUNK_LEN
			if not RoadFrame.layout.changes_between(s0 - RoadBarriers.GAP_CLEAR, s0 + RoadChunkBuilder.CHUNK_LEN + RoadBarriers.GAP_CLEAR).is_empty():
				_fail("rules: crossover at chunk %d next to a layout change" % g)
	var share := float(with_gap) / float(runs * 2)
	print("rules: %d of %d districts have a crossover (%.0f%%)" % [with_gap, runs * 2, share * 100.0])
	if share < 0.7:
		_fail("rules: only %.0f%% of districts have a crossover (about one per district)" % (share * 100.0))
	RoadFrame.align = null
	RoadFrame.layout = null
	# Collision of a gap chunk and a plain one.
	for gap in [false, true]:
		var root := RoadChunkBuilder.build_chunk(5, {"own_lanes": 4, "onc_lanes": 4, "barrier": "guardrail"}, {"own_lanes": 4, "onc_lanes": 4, "barrier": "guardrail", "gap": gap}, 0)
		var body := root.get_node(^"BarrierCol")
		var on := 0
		for k in RoadChunkBuilder.STATIONS:
			var col := body.get_node(NodePath("Shape%d" % k)) as CollisionShape3D
			if col.disabled != (gap and RoadBarriers.is_open(k)):
				_fail("rules: gap=%s station %d collision %s" % [gap, k, "off" if col.disabled else "on"])
			if not col.disabled:
				on += 1
		var cushions := 0
		for i in 2:
			if not (root.get_node(^"CushionCol").get_node(NodePath("Shape%d" % i)) as CollisionShape3D).disabled:
				cushions += 1
		var shown := (root.get_node(^"Barrier") as MultiMeshInstance3D).multimesh.visible_instance_count
		if shown != on or cushions != (2 if gap else 0) or (root.get_node(^"Cushions") as MultiMeshInstance3D).multimesh.visible_instance_count != cushions:
			_fail("rules: gap=%s shows %d pieces for %d boxes, %d cushions" % [gap, shown, on, cushions])
		print("rules: gap=%s: %d barrier pieces, %d cushions" % [gap, on, cushions])
		root.free()
	RoadFrame.align = saved_align
	RoadFrame.layout = saved_layout

# ---------- part 2 ----------

## Rebuilds every chunk in the pool for the current RoadBarriers.force_kind.
func _rebuild_all() -> void:
	game.section_cache.clear()
	for c in game.chunk_pool:
		RoadChunkBuilder.rebuild_chunk(c.root, c.index, game._section_at(c.index - 1), game._section_at(c.index), game.origin_index)

func _chunk_root(idx: int) -> Node3D:
	for c in game.chunk_pool:
		if c.index == idx:
			return c.root
	return null

func _start(p: PlayerCar) -> void:
	var kind: String = scenarios[index][0]
	var v: float = scenarios[index][1]
	var a: float = scenarios[index][2]
	if kind != "cushion" and RoadBarriers.force_kind != kind:
		RoadBarriers.force_kind = kind
		_rebuild_all()
	var pos: Vector3
	var basis := Basis()
	if kind == "cushion":
		if RoadBarriers.force_kind != RoadBarriers.CONCRETE:
			RoadBarriers.force_kind = RoadBarriers.CONCRETE
			_rebuild_all()
		# The car sits in the crossover, just past the near cushion, and drives
		# straight down the centre line into the far one (its nose faces +z,
		# toward traffic on our side, which drives toward -z).
		# The district's own crossover may be out of the pool's reach, so
		# the chunk two ahead of the car is rebuilt as one.
		var g := int(floor(-p.global_position.z / RoadChunkBuilder.CHUNK_LEN)) + int(game.origin_index) + 2
		var cfg: Dictionary = game._section_at(g).duplicate()
		cfg.gap = true
		game.section_cache[str(g)] = cfg
		cushion_root = _chunk_root(g)
		if cushion_root != null:
			RoadChunkBuilder.rebuild_chunk(cushion_root, g, game._section_at(g - 1), cfg, game.origin_index)
		if cushion_root == null:
			_fail("cushion: no crossover chunk in the pool")
			index = scenarios.size()
			return
		var seg := RoadChunkBuilder.CHUNK_LEN / RoadChunkBuilder.STATIONS
		var z0 := -seg * float(RoadBarriers.GAP_FROM) - RoadBarriers.CUSHION_LEN - 2.5
		pos = cushion_root.to_global(Vector3(0.0, 0.0, z0))
		pos.y = rest_y
	else:
		# One lane-width run-up across the gap between lane 0 and the barrier,
		# arriving about 0.6 s after launch.
		var gap := clampf(v * sin(deg_to_rad(a)) * 0.6, 1.4, Harness.lane_x(1))
		pos = Vector3(gap, rest_y, p.global_position.z)
		basis = Basis(Vector3.UP, deg_to_rad(a))  # yawed toward -x, the barrier
	p.global_transform = Transform3D(basis, pos)
	p.angular_velocity = Vector3.ZERO
	TrafficCar.set_moving(p, v)
	p.reset_physics_interpolation()
	run_tick = 0
	prev_speed = v
	s = {"kind": kind, "speed": v, "angle": a, "hit": false, "through": false, "rise": 0.0, "tilt": 0.0,
		"kick": 0.0, "end_tilt": 0.0, "end_wheels": 0, "finite": true, "end_speed": 0.0,
		"dents": _count(RoadBarriers.dents), "crumpled": _count(RoadBarriers.crumpled), "x0": pos.x, "z0": pos.z}

func _count(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += (d[k] as Dictionary).size()
	return n

func _physics_process(_delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	tick += 1
	if tick < rate:
		return false
	if tick == rate:
		rest_y = p.global_position.y
		p.driver = func(c: Vehicle) -> void:
			c.steering_input = 0.0
			c.throttle_input = 1.0
			c.brake_input = 0.0
			c.handbrake_input = 0.0
		index = 0
		_start(p)
		return false
	if index >= scenarios.size():
		return _end()
	run_tick += 1
	if not Harness.finite(p):
		s.finite = false
	else:
		var b := p.global_transform.basis
		var tilt := rad_to_deg(b.y.angle_to(Vector3.UP))
		s.tilt = maxf(s.tilt, tilt)
		s.rise = maxf(s.rise, p.global_position.y - rest_y)
		var speed := p.linear_velocity.length()
		if s.hit:
			s.kick = maxf(s.kick, speed - prev_speed)
		elif p.get_contact_count() > 0:
			for i in p.get_colliding_bodies():
				if (i as Node).has_meta("barrier"):
					s.hit = true
		prev_speed = speed
		if s.kind != "cushion" and p.global_position.x < -0.3:
			s.through = true
		if s.kind == "cushion" and cushion_root != null:
			var seg := RoadChunkBuilder.CHUNK_LEN / RoadChunkBuilder.STATIONS
			var local := cushion_root.to_local(p.global_position)
			if local.z < -seg * float(RoadBarriers.GAP_TO + 1):
				s.through = true
		if log_ticks:
			print("  %s t=%.2f x=%.2f y=%.2f z=%.1f tilt=%.0f v=%.1f" % ["H" if s.hit else "-", run_tick / float(rate), p.global_position.x, p.global_position.y, p.global_position.z, tilt, speed])
	if s.finite and run_tick > int((RUN_SECS - END_SECS) * rate):
		s.end_tilt = maxf(s.end_tilt, rad_to_deg(p.global_transform.basis.y.angle_to(Vector3.UP)))
		var down := 0
		for w in p.wheel_array:
			if (w as Wheel).is_colliding():
				down += 1
		s.end_wheels = maxi(s.end_wheels, down)
	if run_tick >= int(RUN_SECS * rate) or not s.finite:
		s.end_speed = p.linear_velocity.length()
		_report()
		index += 1
		if index >= scenarios.size():
			return _end()
		_start(p)
	return false

func _report() -> void:
	var name := "%-9s %2.0f m/s at %2.0f deg" % [s.kind, s.speed, s.angle]
	var bad: Array[String] = []
	if not s.finite:
		bad.append("non-finite state")
	if not s.hit:
		bad.append("never reached the barrier")
	if s.through:
		bad.append("went through")
	if s.rise > MAX_RISE:
		bad.append("rose %.1f m (over the top)" % s.rise)
	if s.tilt > MAX_TILT:
		bad.append("rolled to %.0f deg" % s.tilt)
	if s.kick > MAX_KICK:
		bad.append("gained %.1f m/s in one tick" % s.kick)
	if s.end_tilt > END_TILT or s.end_wheels < 3:
		bad.append("not back on its wheels (tilt %.0f deg, %d wheels down)" % [s.end_tilt, s.end_wheels])
	var key := "%d,%d" % [s.speed, s.angle]
	match s.kind:
		RoadBarriers.CONCRETE:
			concrete_end[key] = s.end_speed
		RoadBarriers.CABLE:
			# Concrete that stopped the car dead (a wedge, not a rank to beat) is no yardstick.
			if concrete_end.has(key) and concrete_end[key] > 3.0 and s.end_speed >= concrete_end[key] - 0.5:
				bad.append("the cable did not slow it (%.1f m/s, concrete %.1f)" % [s.end_speed, concrete_end[key]])
		RoadBarriers.GUARDRAIL:
			var sideways: float = s.speed * sin(deg_to_rad(s.angle))
			if sideways > RoadBarriers.DENT_FROM + 2.0 and _count(RoadBarriers.dents) <= s.dents:
				bad.append("hit at %.0f m/s sideways and left no dent" % sideways)
		"cushion":
			if s.end_speed > CUSHION_STOP:
				bad.append("not stopped (%.1f m/s)" % s.end_speed)
			if s.speed > RoadBarriers.CRUMPLE_FROM + 2.0 and _count(RoadBarriers.crumpled) <= s.crumpled:
				bad.append("the cushion did not crumple")
	var extra := "end %4.1f m/s" % s.end_speed
	print("%s: peak tilt %5.1f deg, rise %4.2f m, kick %4.2f m/s, %s, end tilt %4.1f deg, %d wheels down  %s" % [name, s.tilt, s.rise, s.kick, extra, s.end_tilt, s.end_wheels, "ok" if bad.is_empty() else "FAIL " + ", ".join(bad)])
	for b in bad:
		fails.append("%s: %s" % [name, b])

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails.append(msg)

func _end() -> bool:
	if logger.errors.size() > 0:
		fails.append("%d engine error(s): %s" % [logger.errors.size(), logger.errors[0]])
	print("barrier_hit: %s" % ("PASS" if fails.is_empty() else "%d failure(s)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
	return true
