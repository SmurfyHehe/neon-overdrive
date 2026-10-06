extends SceneTree

# Traffic behaviour test (milestone 4, stage B step 3, 2026-10-06), at the
# game's 120 Hz tick in the real Game.tscn. Six scripted scenes, one after
# another; each places its cars by hand (TrafficCar.place), drives the player
# with the tests' lane-keeper (traffic_harness.gd), and checks what traffic did.
#
# A "follow": a 108 km/h car 60 m behind a 54 km/h car in lane 3, the only lane
#   traffic may use, so it cannot pass. It must brake, never touch the car
#   ahead, and settle at the slow car's speed.
# B "stop": a 108 km/h car 120 m behind a STOPPED car, again with nowhere to
#   go. It must stop behind it without touching it.
# C "round": the same, with lane 2 free. It must change lane and drive past
#   without touching anything.
# D "move over": the player at 150 km/h closes on a 90 km/h car 150 m ahead in
#   its lane (lane 1) with lane 2 free. The car must move over before the player gets
#   there; nothing touches the player.
# E "highway": Roy's case from the 2026-10-06 audit. The player at ~240 km/h,
#   full throttle, holding a middle own lane (lane 1) for 60 s, 16 cars (the
#   new default) with every lane open and the default 150 m draw distance.
#   Asserts 0 contacts with the player, no two cars touching, lane changes
#   happen, and no car ever crosses the centre line or targets a lane on the
#   other side.
# F "wreck": a car flipped onto its roof 60 m ahead in lane 3 while the player
#   drives past at 29 km/h in lane 0. It must be flagged wrecked, must stay
#   put (not recycled) while the camera can see it, and must be recycled once
#   it can't.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/traffic_behaviour.gd
# NEON_SCENES=highway,wreck (comma list) runs only those scenes.

const Harness := preload("res://tests/traffic_harness.gd")

const RATE := 120
const KMH := 1.0 / 3.6
const ALL_SCENES := ["follow", "stop", "round", "move_over", "highway", "wreck"]
var SCENES: Array = ALL_SCENES
const SCENE_SECONDS := {"follow": 20.0, "stop": 15.0, "round": 15.0, "move_over": 11.0, "highway": 60.0, "wreck": 15.0}
const TIMEOUT_TICKS := RATE * 260
const RECENTER := 8000.0

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var p: PlayerCar
var fails: Array[String] = []
var scene := -1
var scene_tick := 0
var lines: Array[String] = []

# Per-scene state.
var lead: TrafficCar
var follower: TrafficCar
var min_gap := INF
var max_brake := 0.0
var max_decel := 0.0
var last_speed := 0.0
var touched := 0
var player_contacts := 0
var pair_contacts := 0
var first_contact := ""
var lc_start := 0
var crossings := 0
var body_crossings := 0
var brake_ticks := 0
var speed_sum := 0.0
var speed_n := 0
var wreck_flag_tick := -1
var last_in_view := true
var last_pos := Vector3.ZERO
var recycled_tick := -1
var recycled_while_seen := false
var seen_wrecked_ticks := 0
var recycle_rel_z := 0.0
var wreck_count_start := 0
var spawns_start := 0
var ms_sum := 0.0
var ms_n := 0
var last_usec := 0
var min_player_gap := INF
var speed_hist: PackedFloat32Array = []
var first_hit := ""
var first_drift := ""
var max_player_err := 0.0

func _initialize() -> void:
	var only := OS.get_environment("NEON_SCENES")
	if only != "":
		SCENES = Array(only.split(","))
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	# Floating origin every 8 km instead of 1 km, so the whole run (about
	# 5.5 km) has no recenter. Not traffic's business: ~1 s after a recenter
	# at 240 km/h some of the player's wheel raycasts miss the ground for a
	# few ticks (force_vector zero on one side) and the car takes a 3-6 m/s^2
	# sideways kick, measured 2026-10-06 with no traffic at all (the open
	# "recenter at top speed" note on PR #113). The scripted player then
	# wanders into the next lane and the test would be measuring that bug.
	game = Harness.boot(self, 0, 300.0, 4242, RECENTER)

func _physics_process(_delta: float) -> bool:
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		printerr("FAIL: timed out after ", Engine.get_physics_frames(), " ticks")
		quit(1)
		return true
	if traffic == null:
		if game.get("player") == null:
			return false
		traffic = game.get("traffic")
		p = game.get("player")
		_next_scene()
		return false
	for car in traffic.cars:
		if not Harness.finite(car):
			return _end("non-finite traffic state in scene %s" % SCENES[scene])
	if not Harness.finite(p):
		return _end("non-finite player state in scene %s" % SCENES[scene])
	scene_tick += 1
	call("_tick_" + SCENES[scene])
	if scene_tick >= int(SCENE_SECONDS[SCENES[scene]] * RATE):
		call("_end_" + SCENES[scene])
		_next_scene()
		if scene >= SCENES.size():
			return _end("")
	return false

func _next_scene() -> void:
	scene += 1
	scene_tick = 0
	if scene >= SCENES.size():
		return
	traffic.set_car_count(0)
	traffic.react_to_player = true
	traffic.detail_distance = 300.0
	traffic.own_lanes_used = []
	traffic.onc_lanes_used = []
	min_gap = INF
	max_brake = 0.0
	max_decel = 0.0
	touched = 0
	player_contacts = 0
	pair_contacts = 0
	first_contact = ""
	crossings = 0
	body_crossings = 0
	brake_ticks = 0
	speed_sum = 0.0
	speed_n = 0
	min_player_gap = INF
	speed_hist.clear()
	first_hit = ""
	first_drift = ""
	max_player_err = 0.0
	lc_start = traffic.lane_change_count
	call("_setup_" + SCENES[scene])

## Player on own lane `lane`, moving at `speed` m/s, full throttle up to `cap`.
func _drive_player(lane: int, speed: float, cap: float) -> void:
	Harness.move_player_to_lane(p, Harness.lane_x(lane))
	Harness.launch_player(p, speed)
	p.driver = Harness.lane_driver(Harness.lane_x(lane), 1.0, cap)

## Puts traffic car `car` in own lane `lane`, `ahead` m ahead of the player.
func _put(car: TrafficCar, lane: int, ahead: float, speed: float, target: float) -> void:
	car.target_speed = target
	car.set_detailed(true)
	car.place(Harness.lane_x(lane), -1.0, p.global_position.z - ahead, TrafficManager.REST_Y, speed)

func _two_cars(lanes: Array[int]) -> void:
	traffic.own_lanes_used = lanes
	traffic.onc_lanes_used = [3]
	traffic.set_car_count(2)
	lead = traffic.cars[0]
	follower = traffic.cars[1]

## Gap / brake / contact bookkeeping between `follower` and `lead`.
func _watch_pair() -> void:
	var gap := absf(lead.global_position.z - follower.global_position.z) - 2.0 * follower.half_l
	if absf(lead.global_position.x - follower.global_position.x) < 2.0:
		min_gap = minf(min_gap, gap)
	max_brake = maxf(max_brake, follower.brake_input)
	# Deceleration over 0.25 s windows (tick to tick is noisy).
	var v := follower.current_speed()
	if scene_tick % 30 == 0:
		if scene_tick > 30:
			max_decel = maxf(max_decel, (last_speed - v) * RATE / 30.0)
		last_speed = v
	if Harness.overlaps(follower, lead, 1.5, 3.0):
		touched += 1
	_watch_player()

func _watch_player() -> void:
	for car in traffic.cars:
		if car.detailed and Harness.overlaps(p, car, 1.5, 3.0):
			player_contacts += 1
			if first_contact == "":
				first_contact = "%.1f s: %s car lane_x %.2f at x %.2f, player x %.2f, %.0f km/h" % [
					float(scene_tick) / RATE, "own" if car.direction < 0 else "oncoming", car.lane_x,
					car.global_position.x, p.global_position.x, Harness.kmh(p.current_speed())]
			break

# ---------- A: follow ----------

func _setup_follow() -> void:
	_drive_player(0, 12.0, 12.0)  # slower than both, so they stay ahead (not recycled)
	_two_cars([3])
	_put(lead, 3, 100.0, 15.0, 15.0)
	_put(follower, 3, 40.0, 30.0, 30.0)

func _tick_follow() -> void:
	_watch_pair()

func _end_follow() -> void:
	var dv := follower.current_speed() - lead.current_speed()
	var gap := absf(lead.global_position.z - follower.global_position.z) - 2.0 * follower.half_l
	var want := TrafficCar.S0 + TrafficCar.T_GAP * follower.current_speed()
	lines.append("A follow: 108 -> 54 km/h, min gap %.1f m, max brake %.2f, max decel %.1f m/s^2, end gap %.1f m (wants %.1f), end speed diff %.2f m/s, touching ticks %d, lane changes %d" % [
		min_gap, max_brake, max_decel, gap, want, dv, touched, follower.lane_changes])
	_check(touched == 0 and min_gap > 1.0, "A: the follower reached the car ahead (min gap %.2f m, %d ticks touching)" % [min_gap, touched])
	_check(max_brake > 0.05, "A: the follower never braked (max brake %.2f)" % max_brake)
	_check(absf(dv) < 1.5, "A: the follower ended %.2f m/s off the leader's speed" % dv)
	_check(follower.lane_changes == 0, "A: changed lane into a lane traffic may not use")

# ---------- B: stop ----------

func _setup_stop() -> void:
	_drive_player(0, 5.0, 5.0)  # crawling, so it does not pass the cars and get them recycled
	_two_cars([3])
	_put(lead, 3, 140.0, 0.0, 0.0)
	_put(follower, 3, 20.0, 30.0, 30.0)

func _tick_stop() -> void:
	_watch_pair()

func _end_stop() -> void:
	var v := follower.current_speed()
	lines.append("B stop: 108 km/h -> stopped car 120 m ahead, min gap %.1f m, max brake %.2f, max decel %.1f m/s^2, end speed %.2f m/s, touching ticks %d" % [
		min_gap, max_brake, max_decel, v, touched])
	_check(touched == 0 and min_gap > 0.5, "B: the follower hit the stopped car (min gap %.2f m)" % min_gap)
	_check(absf(v) < 0.5, "B: the follower did not stop (%.2f m/s)" % v)

# ---------- C: round ----------

func _setup_round() -> void:
	_drive_player(0, 5.0, 5.0)
	_two_cars([2, 3])
	_put(lead, 3, 140.0, 0.0, 0.0)
	_put(follower, 3, 20.0, 30.0, 30.0)

func _tick_round() -> void:
	_watch_pair()

func _end_round() -> void:
	var passed := follower.global_position.z < lead.global_position.z
	lines.append("C round: stopped car with lane 2 free, lane changes %d, passed it %s, min gap while in its lane %.1f m, max brake %.2f, touching ticks %d" % [
		follower.lane_changes, passed, min_gap, max_brake, touched])
	_check(touched == 0, "C: the follower touched the stopped car")
	_check(follower.lane_changes >= 1 and passed, "C: the follower did not go round the stopped car (changes %d, passed %s)" % [follower.lane_changes, passed])

# ---------- D: move over ----------

func _setup_move_over() -> void:
	_drive_player(1, 150.0 * KMH, 150.0 * KMH)
	_two_cars([1, 2])
	_put(lead, 1, 150.0, 25.0, 25.0)
	_put(follower, 2, 400.0, 25.0, 25.0)  # far away, out of the way

func _tick_move_over() -> void:
	_watch_player()
	min_player_gap = minf(min_player_gap, absf(lead.global_position.z - p.global_position.z) - lead.half_l - TrafficManager.PLAYER_HALF_L)

func _end_move_over() -> void:
	var passed := p.global_position.z < lead.global_position.z
	lines.append("D move over: player 150 km/h behind a 90 km/h car in its lane, car lane changes %d (now lane %d), player passed it %s, contacts %d" % [
		lead.lane_changes, lead.lane_i, passed, player_contacts])
	_check(player_contacts == 0, "D: the player hit the car (%s)" % first_contact)
	_check(lead.lane_changes >= 1 and lead.lane_i == 2, "D: the car did not move over (changes %d, lane %d)" % [lead.lane_changes, lead.lane_i])

# ---------- E: highway ----------

func _setup_highway() -> void:
	_drive_player(1, 230.0 * KMH, INF)
	traffic.detail_distance = TrafficSettings.DETAIL_DEFAULT
	traffic.log_spawns = true
	spawns_start = traffic.spawn_log.size()
	wreck_count_start = traffic.wreck_recycle_count
	traffic.set_car_count(TrafficSettings.CAR_COUNT_DEFAULT)
	last_usec = Time.get_ticks_usec()
	ms_sum = 0.0
	ms_n = 0

func _tick_highway() -> void:
	var now := Time.get_ticks_usec()
	ms_sum += float(now - last_usec) / 1000.0
	ms_n += 1
	last_usec = now
	_watch_player()
	speed_sum += p.current_speed()
	speed_n += 1
	# The first sudden speed loss of the player (2 m/s in 0.25 s at full
	# throttle is a hit), with what was nearest, for reading a failure.
	var err := absf(p.global_position.x - Harness.lane_x(1))
	max_player_err = maxf(max_player_err, err)
	if first_drift == "" and err > 0.5:
		first_drift = "%.1f s: player %.2f m off its lane at %.0f km/h, origin shifts so far %d, %s" % [
			float(scene_tick) / RATE, err, Harness.kmh(p.current_speed()), game.get("recenter_count"), _nearest_note()]
	speed_hist.append(p.current_speed())
	var n := speed_hist.size()
	if first_hit == "" and n > 30 and speed_hist[n - 31] - speed_hist[n - 1] > 2.0:
		var near: TrafficCar = null
		for car in traffic.cars:
			if near == null or car.global_position.distance_to(p.global_position) < near.global_position.distance_to(p.global_position):
				near = car
		first_hit = "%.1f s: player lost %.1f m/s, x %.2f; nearest car %s lane %d at dx %.2f dz %.2f, %.0f km/h, changing %s, detailed %s" % [
			float(scene_tick) / RATE, speed_hist[n - 31] - speed_hist[n - 1], p.global_position.x,
			"own" if near.direction < 0 else "oncoming", near.lane_i, near.global_position.x - p.global_position.x,
			near.global_position.z - p.global_position.z, Harness.kmh(near.current_speed()), near.changing, near.detailed]
	for car in traffic.cars:
		if car.brake_input > 0.1:
			brake_ticks += 1
		var own := car.direction < 0.0
		# Never across the centre line: the lane it targets and its path (what
		# the controller decides), and its centre (what it actually does).
		if (car.lane_x > 0.0) != own or (car.path_x() > 0.0) != own:
			crossings += 1
		if car.detailed and (car.global_position.x > 0.0) != own:
			body_crossings += 1
	if scene_tick % 10 == 0:
		var cars := traffic.cars
		for i in cars.size():
			if not cars[i].detailed:
				continue
			for j in range(i + 1, cars.size()):
				if cars[j].detailed and Harness.overlaps(cars[i], cars[j], 1.5, 3.0):
					pair_contacts += 1

func _end_highway() -> void:
	var changes := traffic.lane_change_count - lc_start
	var behind := 0
	for k in range(spawns_start, traffic.spawn_log.size()):
		if traffic.spawn_log[k].behind:
			behind += 1
	traffic.log_spawns = false
	lines.append("E highway: 60 s, 16 cars, draw 150 m, player lane 1 full throttle, mean %.0f km/h, contacts with the player %d%s, car pairs touching %d, lane changes %d, centre-line crossings %d planned / %d driven, car-ticks braking %d, spawns %d (%d behind), wrecks recycled %d, mean %.2f ms/tick" % [
		Harness.kmh(speed_sum / maxi(speed_n, 1)), player_contacts, "" if first_contact == "" else " (first " + first_contact + ")",
		pair_contacts, changes, crossings, body_crossings, brake_ticks, traffic.spawn_log.size() - spawns_start, behind,
		traffic.wreck_recycle_count - wreck_count_start, ms_sum / maxi(ms_n, 1)])
	lines.append("E highway: player max lane error %.2f m" % max_player_err)
	if first_drift != "":
		lines.append("E highway: first drift " + first_drift)
	if first_hit != "":
		lines.append("E highway: first hit " + first_hit)
	_check(player_contacts == 0, "E: %d ticks with traffic touching the player (first %s)" % [player_contacts, first_contact])
	_check(pair_contacts == 0, "E: two traffic cars touched (%d samples)" % pair_contacts)
	_check(changes > 0, "E: no lane changes in 60 s")
	_check(crossings == 0, "E: %d car-ticks with a lane or path across the centre line" % crossings)
	_check(body_crossings == 0, "E: %d car-ticks with a car centre across the centre line" % body_crossings)
	_check(Harness.kmh(speed_sum / maxi(speed_n, 1)) > 220.0, "E: the player averaged under 220 km/h")

func _nearest_note() -> String:
	var near: TrafficCar = null
	for car in traffic.cars:
		if near == null or car.global_position.distance_to(p.global_position) < near.global_position.distance_to(p.global_position):
			near = car
	if near == null:
		return "no cars"
	return "nearest car %s lane %d at dx %.2f dz %.2f, %.0f km/h, changing %s" % [
		"own" if near.direction < 0 else "oncoming", near.lane_i, near.global_position.x - p.global_position.x,
		near.global_position.z - p.global_position.z, Harness.kmh(near.current_speed()), near.changing]

# ---------- F: wreck ----------

func _setup_wreck() -> void:
	_drive_player(0, 8.0, 8.0)
	traffic.own_lanes_used = [3]
	traffic.onc_lanes_used = [3]
	traffic.set_car_count(1)
	lead = traffic.cars[0]
	_put(lead, 3, 60.0, 0.0, 0.0)
	# On its roof, a little above the road so it drops onto it.
	var t := lead.global_transform
	t.basis = Basis(Vector3.BACK, PI)
	t.origin.y = 1.6
	lead.global_transform = t
	lead.reset_physics_interpolation()
	wreck_count_start = traffic.wreck_recycle_count
	wreck_flag_tick = -1
	recycled_tick = -1
	recycled_while_seen = false
	seen_wrecked_ticks = 0
	last_in_view = traffic.in_view(lead.global_position)

func _tick_wreck() -> void:
	if recycled_tick < 0 and traffic.wreck_recycle_count > wreck_count_start:
		recycled_tick = scene_tick
		recycled_while_seen = last_in_view
		recycle_rel_z = p.global_position.z - last_pos.z
	if recycled_tick < 0:
		if lead.wrecked and wreck_flag_tick < 0:
			wreck_flag_tick = scene_tick
		last_pos = lead.global_position
		last_in_view = traffic.in_view(last_pos)
		if lead.wrecked and last_in_view:
			seen_wrecked_ticks += 1

func _end_wreck() -> void:
	lines.append("F wreck: flagged after %.1f s, left in place %.1f s while in view, recycled after %.1f s (%.1f m ahead of the player then, out of view), recycled while in view %s" % [
		float(wreck_flag_tick) / RATE, float(seen_wrecked_ticks) / RATE, float(recycled_tick) / RATE, recycle_rel_z, recycled_while_seen])
	_check(wreck_flag_tick > 0, "F: the flipped car was never flagged as wrecked")
	_check(seen_wrecked_ticks > RATE, "F: the wreck was not left in place while in view (%.2f s)" % (float(seen_wrecked_ticks) / RATE))
	_check(recycled_tick > 0, "F: the wreck was never recycled")
	_check(not recycled_while_seen, "F: the wreck was recycled while the camera could see it")

func _check(ok: bool, msg: String) -> void:
	if not ok and fails.size() < 50:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	for l in lines:
		print("traffic_behaviour: ", l)
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	print("traffic_behaviour: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
	return true
