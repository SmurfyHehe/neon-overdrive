extends SceneTree

# Skeleton-car spike, step 1 (2026-10-10): a jet force pushes the real player
# car to 400 km/h on the real road, with traffic, the junction crossing and
# the floating origin all live, and the run reports what holds and what
# breaks first. Nothing about the car itself changes: the stock coupe's
# gearing tops out near 245 km/h, so above JET_FROM the gearbox goes to
# neutral and a speed-held thrust force does the rest.
#
# Measured, per physics tick: the car's numbers stay finite, it stays on the
# ground, how many wheels touch, how far the springs compress under the
# downforce, hull-to-road and hull-to-traffic contacts, distance travelled
# against velocity, recenter ticks against ordinary ticks, how much built
# road is ahead of the car, and when the junction chunks were built relative
# to the car.
# Per rendered frame: every chunk sits where its index says, no node is
# orphaned or duplicated, chunk recycles are counted, and each
# RoadChunkBuilder.rebuild_chunk is timed by game.gd (rebuild_us_*).
# Traffic: spawn/recycle/deferred counts and whether any car goes non-finite.
#
# Env:
#   NEON_JET_KMH=400   target speed (fallbacks 360, 320)
#   NEON_CCD=1         continuous collision on the player's body (0 = off)
#   NEON_CHUNKS_AHEAD_EXTRA=1  one more chunk built ahead (read by game.gd)
#   NEON_JET_SECS=60   run length in simulated seconds
#   NEON_JET_CARS=16   traffic cars
#   NEON_JET_DOWNFORCE=1  scale on the car's aero downforce coefficients (0 = none);
#                      the stock coupe bottoms its springs under its own downforce
# Run (headless, the game's own 120 Hz tick):
#   godot --headless --fixed-fps 120 --audio-driver Dummy --path . -s res://tests/world/jet_drive.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const TICK_HZ := 120
const JET_FROM := 50.0        # m/s: engine does the work below this, thrust above
const JET_KP := 1500.0        # N per m/s of speed error
const JET_MAX := 40000.0      # N, about 3 g on the coupe
const SETTLE_SECS := 1.0
const DETAIL := 300.0

var target_kmh := 400.0
var target := 0.0
var run_secs := 60.0
var cars := 16
var ccd := true
var downforce := 1.0

var game: Node
var t := 0.0
var fails := 0
var hooked := false
var notes: Array[String] = []

# physics samples
var ticks := 0
var last_origin := 0
var prev := {}
var normal_max := {"speed": 0.0, "lin": 0.0}
var shift_max := {"speed": 0.0, "lin": 0.0}
var worst_travel_err := 0.0
var max_speed := 0.0
var reached_tick := -1
var held_ticks := 0
var ticks_after_reach := 0
var min_held_speed := INF
var airborne_ticks := 0
var min_wheels := 4
var min_spring := INF
var hull_road_ticks := 0
var hull_traffic_ticks := 0
var min_ahead_m := INF
var road_s_start := NAN
var road_s := 0.0
var max_abs_z := 0.0
var junction_s_built := {}   # chunk idx -> car road s when it was (re)built
var junction_passed := false
var traffic_nonfinite := 0
var max_y_pitch := 0.0
var max_over_road := -INF
var first_bottom_kmh := -1.0
var first_hull_road_kmh := -1.0
var first_hull_traffic_kmh := -1.0
var recenter_frame_ms := 0.0
var overlap_no_contact_ticks := 0
var tunnel_ticks := 0
var min_lane_gap := INF
var last_recenters := 0

# frame samples
var frames := 0
var last_frame_usec := 0
var worst_frame_ms := 0.0
var worst_rebuild_frame_ms := 0.0
var worst_plain_frame_ms := 0.0
var frames_with_rebuild := 0
var frames_multi_rebuild := 0
var child_count0 := -1
var recycles := 0
var seen_index := {}
var last_rebuild_count := 0

func _env_f(name: String, dflt: float) -> float:
	var v := OS.get_environment(name)
	return v.to_float() if v.is_valid_float() else dflt

func _initialize() -> void:
	target_kmh = _env_f("NEON_JET_KMH", 400.0)
	target = target_kmh / 3.6
	run_secs = _env_f("NEON_JET_SECS", 60.0)
	cars = int(_env_f("NEON_JET_CARS", 16.0))
	ccd = OS.get_environment("NEON_CCD") != "0"
	downforce = _env_f("NEON_JET_DOWNFORCE", 1.0)
	if OS.get_environment("NEON_ROAD_SEED").is_empty():
		OS.set_environment("NEON_ROAD_SEED", "4242")  # the same bends and hills every run
	if OS.get_environment("NEON_CITY_LIGHTS").is_empty():
		OS.set_environment("NEON_CITY_LIGHTS", "1")  # the 600 m junction crossing exists
	Engine.physics_ticks_per_second = TICK_HZ
	Engine.max_fps = 0
	game = Harness.boot(self, cars, DETAIL, 4242)
	game.set("chunk_event_hook", _on_chunk_recycled)
	print("jet_drive: target=%.0f km/h ccd=%s downforce=x%.2f extra_ahead=%d cars=%d tick=%d Hz secs=%.0f" % [
		target_kmh, str(ccd), downforce, int(game.get("chunks_ahead_extra")), cars, TICK_HZ, run_secs])

# ---- the jet ----
## Own-direction lane the driver aims for. At 400 km/h a car that moves over
## 200 m ahead is 1.8 s away, so the driver looks DODGE_LOOK m up the road and
## moves to the own lane with the longest clear gap when its own drops under
## DODGE_GAP m (a jet car that never steers hits traffic in every run).
const DODGE_LOOK := 600.0
const DODGE_GAP := 250.0
const DODGE_HOLD_TICKS := 60
var lane_target := 1
var lane_hold := 0
var lane_changes := 0

func _lane_gaps(p: Vehicle) -> Array[float]:
	var gaps: Array[float] = []
	for i in 4:  # game.gd OWN_LANES
		gaps.append(DODGE_LOOK)
	var tm: TrafficManager = game.get("traffic")
	if tm == null:
		return gaps
	var ps := _road_s_of(p.global_position)
	for c in tm.cars:
		var cs := _road_s_of(c.global_position)
		var ahead := cs - ps
		if ahead < -5.0 or ahead > DODGE_LOOK:
			continue
		var cx := RoadFrame.unroll(c.global_position).x
		for i in 4:
			if absf(cx - Harness.lane_x(i)) < 2.2:
				gaps[i] = minf(gaps[i], maxf(ahead, 0.0))
	return gaps

func _pick_lane(p: Vehicle) -> void:
	lane_hold -= 1
	var gaps := _lane_gaps(p)
	if gaps[lane_target] >= DODGE_GAP or lane_hold > 0:
		return
	var best := lane_target
	for i in 4:
		if gaps[i] > gaps[best] + 20.0:
			best = i
	if best != lane_target:
		# One lane at a time towards the best one.
		lane_target += signi(best - lane_target)
		lane_hold = DODGE_HOLD_TICKS
		lane_changes += 1

func _jet_driver(c: Vehicle) -> void:
	_pick_lane(c)
	var lane_x := Harness.lane_x(lane_target)
	var side_v := RoadFrame.dir_to_road(RoadFrame.unroll(c.global_position).z, c.linear_velocity).x
	c.steering_input = TrafficCar.lane_steer(c, lane_x - side_v * Harness.LAT_DAMP_T, -1.0, 2.5, Harness.PLAYER_UNDERSTEER_FF)
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	var v: float = c.current_speed()
	if v < JET_FROM and reached_tick < 0:
		c.throttle_input = 1.0
		return
	c.throttle_input = 0.0
	if c.current_gear != 0:
		c.current_gear = 0  # neutral: the 7000 rpm engine would otherwise brake through the clutch
	var f := clampf(JET_KP * (target - v), -JET_MAX * 0.25, JET_MAX)
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	c.apply_central_force(fwd.normalized() * f)

# ---- helpers ----
func _road_s_of(pos: Vector3) -> float:
	return float(game.get("origin_index")) * RoadChunkBuilder.CHUNK_LEN - RoadFrame.unroll(pos).z

func _on_chunk_recycled(_root: Node3D, _gap: int) -> void:
	pass  # the rebuild itself is timed in game.gd; this hook only confirms the path runs

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _note(msg: String) -> void:
	notes.append(msg)
	print("NOTE ", msg)

# ---- physics ----
func _physics_process(delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	if p == null or not p.is_ready:
		return false
	if not hooked:
		# The player is built in game.gd's _ready, after boot returns.
		hooked = true
		p.continuous_cd = ccd
		p.driver = _jet_driver
		p.aero_downforce_coefficient_front *= downforce
		p.aero_downforce_coefficient_rear *= downforce
		var cam: ChaseCamera = game.get("camera")
		if cam != null:
			cam.shake_enabled = false
	ticks += 1
	var origin: int = game.get("origin_index")
	road_s = _road_s_of(p.global_position)
	if is_nan(road_s_start):
		road_s_start = road_s
	max_abs_z = maxf(max_abs_z, absf(p.global_position.z))

	if not Harness.finite(p):
		_fail("player went non-finite at tick %d (s=%.0f m)" % [ticks, road_s])
		_report(p)
		quit(1)
		return true
	# Height over the road surface (RoadFrame.pose follows the hills): below
	# it by more than a car is through the road; well above it is flight.
	var road_y: float = RoadFrame.pose(0.0, 0.0, RoadFrame.unroll(p.global_position).z, 0.0).origin.y
	var over := p.global_position.y - road_y
	max_over_road = maxf(max_over_road, over)
	if over < -1.5:
		_fail("car fell through the road at s=%.0f m, %.0f km/h (%.1f m under the surface)" % [road_s, p.current_speed() * 3.6, -over])
		_report(p)
		quit(1)
		return true

	var v: float = p.current_speed()
	max_speed = maxf(max_speed, v)
	if reached_tick < 0 and v >= target * 0.95:
		reached_tick = ticks
		_note("reached %.0f km/h (95%% of target) after %.1f s at s=%.0f m" % [v * 3.6, float(ticks) / TICK_HZ, road_s])
	if reached_tick >= 0:
		ticks_after_reach += 1
		if v >= target * 0.9:
			held_ticks += 1
		min_held_speed = minf(min_held_speed, v)

	# wheels, springs, hull contacts (from the settle point on)
	if ticks > SETTLE_SECS * TICK_HZ:
		var grounded := 0
		for w in p.wheel_array:
			if w.is_colliding():
				grounded += 1
			min_spring = minf(min_spring, w.spring_current_length)
		min_wheels = mini(min_wheels, grounded)
		if grounded == 0:
			airborne_ticks += 1
		var road_hit := false
		var traffic_hit := false
		for b in p.get_colliding_bodies():
			if b is TrafficCar:
				traffic_hit = true
			else:
				road_hit = true
		if road_hit:
			hull_road_ticks += 1
			if first_hull_road_kmh < 0.0:
				first_hull_road_kmh = v * 3.6
				_note("hull first touched the road at %.0f km/h, s=%.0f m, min spring so far %.3f m" % [v * 3.6, road_s, min_spring])
		if traffic_hit:
			hull_traffic_ticks += 1
			if first_hull_traffic_kmh < 0.0:
				first_hull_traffic_kmh = v * 3.6
				_note("hull first touched a traffic car at %.0f km/h, s=%.0f m" % [v * 3.6, road_s])
		if min_spring <= 0.0005 and first_bottom_kmh < 0.0:
			first_bottom_kmh = v * 3.6
			_note("a spring first bottomed out at %.0f km/h, s=%.0f m" % [v * 3.6, road_s])
		max_y_pitch = maxf(max_y_pitch, absf(p.global_rotation.x))

	# how much built road is ahead of the car
	var max_idx := 0
	for c in game.get("chunk_pool"):
		max_idx = maxi(max_idx, c.index)
	var ahead_m := float(max_idx + 1) * RoadChunkBuilder.CHUNK_LEN - road_s
	min_ahead_m = minf(min_ahead_m, ahead_m)

	if not junction_passed and road_s >= Junction.CENTRE_S:
		junction_passed = true
		_note("crossed the junction (s=%.0f m) at %.0f km/h, hull/road contacts so far %d" % [Junction.CENTRE_S, v * 3.6, hull_road_ticks])

	# recenter vs ordinary ticks, and travel vs velocity (floating_origin_drive's checks)
	var cur := {"speed": p.speed, "lin": p.linear_velocity.length(), "s": road_s,
		"vs": -RoadFrame.dir_to_road(RoadFrame.unroll(p.global_position).z, p.linear_velocity).z}
	if not prev.is_empty() and ticks > SETTLE_SECS * TICK_HZ:
		var bucket: Dictionary = shift_max if origin != last_origin else normal_max
		bucket.speed = maxf(bucket.speed, absf(cur.speed - prev.speed))
		bucket.lin = maxf(bucket.lin, absf(cur.lin - prev.lin))
		var travel: float = cur.s - prev.s
		var expected: float = (cur.vs + prev.vs) / 2.0 * delta
		worst_travel_err = maxf(worst_travel_err, absf(travel - expected))
	prev = cur
	last_origin = origin

	var tm: TrafficManager = game.get("traffic")
	if tm != null:
		var touching := p.get_colliding_bodies().size() > 0
		for c in tm.cars:
			if not Harness.finite(c):
				traffic_nonfinite += 1
			if ticks <= SETTLE_SECS * TICK_HZ:
				continue
			# A traffic car's centre inside the player's box with no contact
			# reported is the body passing through it (Harness.overlaps/tunnelled).
			if Harness.overlaps(p, c, 1.5, 3.0) and not touching:
				overlap_no_contact_ticks += 1
			if Harness.tunnelled(p, c):
				tunnel_ticks += 1
			var l := p.to_local(c.global_position)
			if absf(l.x) < 1.8 and l.z < 0.0:
				min_lane_gap = minf(min_lane_gap, -l.z)
	return false

# ---- frames ----
func _process(delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	if p == null or not p.is_ready:
		return false
	t += delta
	frames += 1
	var now := Time.get_ticks_usec()
	var origin: int = game.get("origin_index")

	# chunk placement, recycles, rebuild timing
	var rc: int = game.get("rebuild_count")
	var rebuilt_this_frame := rc - last_rebuild_count
	last_rebuild_count = rc
	for c in game.get("chunk_pool"):
		var want := RoadFrame.chunk_xf(c.index, origin).origin
		if c.root.position.distance_to(want) > 0.001:
			_fail("chunk %d at %s, expected %s" % [c.index, str(c.root.position), str(want)])
		var id: int = c.root.get_instance_id()
		if seen_index.has(id) and seen_index[id] != c.index:
			recycles += 1
		seen_index[id] = c.index
		if Junction.touches(c.index) and not junction_s_built.has(c.index) and c.index > 0:
			junction_s_built[c.index] = road_s
	if child_count0 < 0:
		child_count0 = game.get_child_count()
	elif game.get_child_count() != child_count0 and frames > 10:
		_fail("game child count changed %d -> %d (orphan or duplicate nodes)" % [child_count0, game.get_child_count()])
		child_count0 = game.get_child_count()

	var rcnt: int = game.get("recenter_count")
	var recentered := rcnt != last_recenters
	last_recenters = rcnt
	if last_frame_usec > 0 and frames > 10:
		var ms := float(now - last_frame_usec) / 1000.0
		worst_frame_ms = maxf(worst_frame_ms, ms)
		if recentered:
			recenter_frame_ms = maxf(recenter_frame_ms, ms)
		elif rebuilt_this_frame > 0:
			frames_with_rebuild += 1
			worst_rebuild_frame_ms = maxf(worst_rebuild_frame_ms, ms)
			if rebuilt_this_frame > 1:
				frames_multi_rebuild += 1
		else:
			worst_plain_frame_ms = maxf(worst_plain_frame_ms, ms)
	last_frame_usec = now

	if t >= run_secs:
		_report(p)
		quit(0 if fails == 0 else 1)
		return true
	return false

func _report(p: PlayerCar) -> void:
	var tm: TrafficManager = game.get("traffic")
	var driven := road_s - road_s_start
	var secs := float(ticks) / TICK_HZ
	print("---- jet_drive report: target %.0f km/h, ccd=%s, extra_ahead=%d ----" % [target_kmh, str(ccd), int(game.get("chunks_ahead_extra"))])
	print("driven=%.0f m in %.1f s  top=%.0f km/h  reached=%s  held>=90%%: %d/%d ticks  min held=%.0f km/h" % [
		driven, secs, max_speed * 3.6, ("%.1f s" % (float(reached_tick) / TICK_HZ)) if reached_tick >= 0 else "never",
		held_ticks, ticks_after_reach, (min_held_speed * 3.6) if min_held_speed < INF else 0.0])
	print("car: min wheels down=%d airborne ticks=%d (%.2f s) max height over road=%.2f m min spring=%.3f m (rest %.3f) max |pitch|=%.1f deg hull/road ticks=%d hull/traffic ticks=%d max|z|=%.0f" % [
		min_wheels, airborne_ticks, float(airborne_ticks) / TICK_HZ, max_over_road, min_spring, p.wheel_array[0].spring_length if p.wheel_array.size() > 0 else 0.0,
		rad_to_deg(max_y_pitch), hull_road_ticks, hull_traffic_ticks, max_abs_z])
	print("road shape: curviness=%s hilliness=%s seed=%s" % [str(game.get("curviness")), str(game.get("hilliness")), str(game.get("road_seed"))])
	print("physics: ordinary tick max dspeed=%.3f dlin=%.3f | recenter tick max dspeed=%.3f dlin=%.3f | recenters=%d | travel-vs-velocity err=%.4f m" % [
		normal_max.speed, normal_max.lin, shift_max.speed, shift_max.lin, int(game.get("recenter_count")), worst_travel_err])
	var rc: int = game.get("rebuild_count")
	var avg_ms := (float(game.get("rebuild_us_total")) / 1000.0 / rc) if rc > 0 else 0.0
	print("road: recycles seen=%d rebuilds=%d avg=%.2f ms max=%.2f ms most in one frame=%d | recenter max %.2f ms | frames=%d with rebuild=%d multi=%d | worst frame %.2f ms (recenter frames %.2f, rebuild frames %.2f, plain %.2f) | min road ahead=%.0f m (%.2f s at target)" % [
		recycles, rc, avg_ms, float(game.get("rebuild_us_max")) / 1000.0, int(game.get("rebuilds_in_frame_max")),
		float(game.get("recenter_us_max")) / 1000.0,
		frames, frames_with_rebuild, frames_multi_rebuild, worst_frame_ms, recenter_frame_ms, worst_rebuild_frame_ms, worst_plain_frame_ms,
		min_ahead_m, min_ahead_m / target])
	var jb := []
	for k in junction_s_built:
		jb.append("chunk %d built %.0f m ahead" % [k, float(k) * RoadChunkBuilder.CHUNK_LEN - junction_s_built[k]])
	print("junction: enabled=%s passed=%s %s" % [str(Junction.enabled), str(junction_passed), ", ".join(jb)])
	var fog_d := 0.009  # game.gd _setup_world, exponential fog
	var ahead_chunks: int = int(game.get_script().get_script_constant_map()["CHUNKS_AHEAD"]) + int(game.get("chunks_ahead_extra"))
	var fog_300 := 1.0 - exp(-fog_d * 300.0)
	print("fog: density %.3f -> %.0f%% fogged at 300 m, %.0f%% at 350 m; road horizon %d m = %.2f s at %.0f km/h" % [
		fog_d, fog_300 * 100.0, (1.0 - exp(-fog_d * 350.0)) * 100.0,
		int(ahead_chunks * RoadChunkBuilder.CHUNK_LEN), float(ahead_chunks) * RoadChunkBuilder.CHUNK_LEN / target, target_kmh])
	if tm != null:
		var visible := 0
		var ahead := 0
		for c in tm.cars:
			if c.visible:
				visible += 1
			if _road_s_of(c.global_position) > road_s:
				ahead += 1
		print("traffic: cars=%d visible=%d ahead=%d spawns=%d recycles=%d deferred=%d wreck_recycles=%d nonfinite ticks=%d reveal=%.0f m (%.2f s at target)" % [
			tm.cars.size(), visible, ahead, tm.spawn_count, tm.recycle_count, tm.deferred_count, tm.wreck_recycle_count,
			traffic_nonfinite, tm.reveal_distance(), tm.reveal_distance() / target])
		print("traffic vs player: lane changes by the driver=%d overlap-without-contact ticks=%d concentric (tunnelled) ticks=%d closest car ahead in own lane=%.1f m" % [
			lane_changes, overlap_no_contact_ticks, tunnel_ticks, min_lane_gap])

	# pass/fail
	if reached_tick < 0:
		_fail("never reached 95%% of %.0f km/h (top %.0f)" % [target_kmh, max_speed * 3.6])
	elif ticks_after_reach > 0 and float(held_ticks) / ticks_after_reach < 0.9:
		_fail("held >= 90%% of target for only %.0f%% of the ticks after reaching it" % (100.0 * held_ticks / ticks_after_reach))
	if min_ahead_m <= 0.0:
		_fail("ran off the end of the built road (min ahead %.0f m)" % min_ahead_m)
	if min_wheels == 0:
		_fail("all four wheels left the ground for %d ticks" % airborne_ticks)
	if tunnel_ticks > 0:
		_fail("the player passed through a traffic car (%d concentric ticks)" % tunnel_ticks)
	if traffic_nonfinite > 0:
		_fail("traffic cars went non-finite on %d car-ticks" % traffic_nonfinite)
	if worst_travel_err > 0.05:
		_fail("distance travelled drifted from velocity by %.4f m in one tick" % worst_travel_err)
	for k in ["speed", "lin"]:
		if shift_max[k] > normal_max[k] * 1.5 + 0.05:
			_fail("%s jumps on recenter: %.4f vs %.4f on ordinary ticks" % [k, shift_max[k], normal_max[k]])
	if hull_road_ticks > 0:
		_note("hull touched the road on %d ticks (downforce bottoming or seam catch); not a failure for the spike" % hull_road_ticks)
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
