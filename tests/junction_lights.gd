extends SceneTree

# City lights test (Junction J0 + J1a, 2026-10-09), at the game's 120 Hz tick
# in the real Game.tscn with the "City lights" switch on. The player is parked
# in own lane 3 150 m short of the crossing, so the traffic around it runs the
# full sim, and traffic is kept to lanes 0-1 each way.
#
# timing  the cycle: main-road red is 22 s, the cross street is green only
#         while the main road is red, and amber sits between.
# place   J0: the chunks at the crossing have no building, street lamp or
#         delineator in its mouth, no centre barrier, no lane dash between
#         the stop lines, and the crossing's node sits on the road there.
# red     a 22 s red with 4 own-direction and 2 oncoming cars arriving at
#         72 km/h: every car stops behind its stop line (or behind the car
#         ahead), nobody touches anybody, no car is flagged stuck or wrecked
#         across the whole red (the 12 s stuck check vs the 22 s red), the
#         lights show red, and after green every car crosses the line.
# amber   amber starts with one car 25 m from the line at 90 km/h (can't stop
#         at 3 m/s^2: goes) and one 120 m back (can: stops).
# flash   after 1 a.m. the main road flashes amber, the cross street red,
#         and traffic drives through without stopping.
# off     with the switch off (Junction.enabled false) stop_gap never holds a
#         car, and the saved default is off.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/junction_lights.gd
# NEON_SCENES=red,amber (comma list) runs only those scenes.

const Harness := preload("res://tests/traffic_harness.gd")

const RATE := 120
const KMH := 1.0 / 3.6
const ALL_SCENES := ["timing", "place", "red", "amber", "flash", "off"]
var SCENES: Array = ALL_SCENES
const SCENE_SECONDS := {"timing": 0.1, "place": 0.5, "red": 40.0, "amber": 16.0, "flash": 14.0, "off": 0.1}
const TIMEOUT_TICKS := RATE * 120

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var junction: Junction
var p: PlayerCar
var fails: Array[String] = []
var lines: Array[String] = []
var scene := -1
var scene_tick := 0

var cars: Array[TrafficCar] = []
var min_d: Array[float] = []        # closest the front bumper got to the stop line before crossing it (m, + = short)
var crossed_tick: Array[int] = []
var red_d: Array[float] = []        # where it stood on the last red tick (m short of the line)
var red_v: Array[float] = []   # tick its front crossed the line (-1 = not yet)
var max_stuck := 0.0
var contacts := 0
var wrecked_seen := 0
var held_seen := 0
var red_lit_ticks := 0
var red_ticks := 0
var flash_on := 0
var flash_off := 0
var flash_cross_red := 0
var red_crossings := 0

func _initialize() -> void:
	var only := OS.get_environment("NEON_SCENES")
	if only != "":
		SCENES = Array(only.split(","))
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	# A flat, straight road unless asked otherwise: this tests the light, not
	# the road shape (the logic is all in road space either way).
	for k in ["NEON_CURVES", "NEON_HILLS"]:
		if OS.get_environment(k) == "":
			OS.set_environment(k, "0")
	OS.set_environment("NEON_CITY_LIGHTS", "")
	TrafficSettings.city_lights = true
	game = Harness.boot(self, 0, 300.0, 4343, 8000.0)

func _physics_process(_delta: float) -> bool:
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		printerr("FAIL: timed out after ", Engine.get_physics_frames(), " ticks")
		quit(1)
		return true
	if traffic == null:
		if game.get("player") == null:
			return false
		traffic = game.get("traffic")
		junction = game.get("junction")
		p = game.get("player")
		if junction == null:
			return _end("the game built no Junction with city lights on")
		_park_player()
		_next_scene()
		return false
	for car in traffic.cars:
		if not Harness.finite(car):
			return _end("non-finite traffic state in scene %s" % SCENES[scene])
	scene_tick += 1
	if has_method("_tick_" + SCENES[scene]):
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
	traffic.detail_distance = 300.0
	traffic.recycle_behind = 2000.0
	traffic.own_lanes_used = [0, 1]
	traffic.onc_lanes_used = [0, 1]
	junction.force_flash = 0
	cars.clear()
	min_d.clear()
	crossed_tick.clear()
	red_d.clear()
	red_v.clear()
	max_stuck = 0.0
	contacts = 0
	wrecked_seen = 0
	held_seen = 0
	red_lit_ticks = 0
	red_ticks = 0
	red_crossings = 0
	if has_method("_setup_" + SCENES[scene]):
		call("_setup_" + SCENES[scene])

## Parks the player, brakes on, in own lane 3, 150 m short of the crossing's
## centre, so every test car is inside the draw distance. Not past it: a
## teleport further than the chunk pool skips a chunk (game.gd's
## _update_chunk_pool numbers recycled chunks from the player's, not the
## pool's), and this distance keeps the crossing's two chunks in the pool.
func _park_player() -> void:
	var target := RoadFrame.roll(Vector3(Harness.lane_x(3), p.global_position.y, Junction.centre_z() + 150.0))
	target.y = p.global_position.y
	var offset := target - p.global_position
	p.global_position += offset
	p.previous_global_position += offset
	for w in p.wheel_array:
		w.previous_global_position += offset
		w.last_collision_point += offset
	p.linear_velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p.driver = func(c: Vehicle) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 1.0
		c.steering_input = 0.0

## Stop line (its upstream edge) in road space for a car driving along dir.
func _line(dir: float) -> float:
	return Junction.centre_z() - dir * Junction.STOP_OFF

## Front bumper to the stop line, + = short of it.
func _d(car: TrafficCar) -> float:
	return (_line(car.direction) - RoadFrame.unroll(car.global_position).z) * car.direction - car.half_l

## A car `back` m (front bumper) short of its stop line, in lane `lane` on
## its side, at `speed` m/s cruising at `target`.
func _add(lane: int, oncoming: bool, back: float, speed: float, target: float) -> TrafficCar:
	var car: TrafficCar = traffic.cars[cars.size()]
	var dir := 1.0 if oncoming else -1.0
	car.target_speed = target
	car.set_detailed(true)
	car.place(TrafficManager.lane_centre(lane, oncoming), dir, _line(dir) + dir * (-back - car.half_l), car.rest_y, speed)
	cars.append(car)
	min_d.append(INF)
	crossed_tick.append(-1)
	red_d.append(INF)
	red_v.append(0.0)
	return car

func _watch() -> void:
	for i in cars.size():
		var c := cars[i]
		var d := _d(c)
		if crossed_tick[i] < 0:
			min_d[i] = minf(min_d[i], d)
		if d < 0.0 and crossed_tick[i] < 0:
			crossed_tick[i] = scene_tick
			if junction.main_state() == Junction.RED:
				red_crossings += 1
		max_stuck = maxf(max_stuck, c._stuck_t)
		if c.wrecked or c.hazard:
			wrecked_seen += 1
		if c.signal_held:
			held_seen += 1
		if junction.main_state() == Junction.RED:
			red_d[i] = d
			red_v[i] = c.current_speed()
		for j in range(i + 1, cars.size()):
			if Harness.overlaps(c, cars[j], 1.5, 3.0):
				contacts += 1
		if Harness.overlaps(p, c, 1.5, 3.0):
			contacts += 1

# ---------- timing ----------

func _end_timing() -> void:
	var red := 0.0
	var cross_green_while_main_not_red := 0
	var amber := 0.0
	var dt := 0.01
	var tt := 0.0
	while tt < Junction.CYCLE:
		var m := Junction.main_state_at(tt)
		if m == Junction.RED:
			red += dt
		elif m == Junction.AMBER:
			amber += dt
		if Junction.cross_state_at(tt) != Junction.RED and m != Junction.RED:
			cross_green_while_main_not_red += 1
		tt += dt
	lines.append("timing: cycle %.0f s, main red %.2f s, main amber %.2f s" % [Junction.CYCLE, red, amber])
	_check(absf(red - 22.0) < 0.05, "timing: main-road red lasts %.2f s, not 22" % red)
	_check(absf(amber - Junction.AMBER_S) < 0.05, "timing: amber lasts %.2f s" % amber)
	_check(cross_green_while_main_not_red == 0, "timing: the cross street is not red while the main road is green/amber")
	_check(Junction.MAIN_RED_S > TrafficCar.STUCK_SECONDS, "timing: expected the red to outlast the stuck check (that is the case this test is for)")

# ---------- place (J0) ----------

func _end_place() -> void:
	var touched := 0
	var problems: Array[String] = []
	var counts: Array[String] = []
	var ref: Node3D
	for c in game.get("chunk_pool"):
		if not Junction.touches(c.index):
			ref = c.root
	for c in game.get("chunk_pool"):
		var idx: int = c.index
		if not Junction.touches(idx):
			continue
		touched += 1
		var root: Node3D = c.root
		var jc := Junction.local_centre(idx)
		# buildings: no visible one overlapping the cleared corner
		var k := 0
		while root.has_node(NodePath("BuildingMesh%d" % k)):
			var mi: MeshInstance3D = root.get_node(NodePath("BuildingMesh%d" % k))
			var body: StaticBody3D = root.get_node(NodePath("BuildingBody%d" % k))
			var shape: CollisionShape3D = body.get_node(^"Shape")
			var box: BoxShape3D = shape.shape
			var lz := root.to_local(mi.global_position).z
			if mi.visible and absf(lz - jc) < Junction.CLEAR_HALF + box.size.z / 2.0 - 0.01:
				problems.append("chunk %d building %d at z %.1f in the corner (centre %.1f)" % [idx, k, lz, jc])
			if mi.visible == shape.disabled:
				problems.append("chunk %d building %d drawn %s but collision %s" % [idx, k, mi.visible, not shape.disabled])
			k += 1
		# Instance positions are not readable headless (the dummy renderer
		# keeps no MultiMesh data), so count them against a chunk away from
		# the crossing: each of these loses the instances in the mouth / box.
		for mm_name in ["Lamps", "PylonsOwn", "PylonsOnc", "LaneDashes"]:
			var n := (root.get_node(NodePath(mm_name)) as MultiMeshInstance3D).multimesh.visible_instance_count
			var n_ref := (ref.get_node(NodePath(mm_name)) as MultiMeshInstance3D).multimesh.visible_instance_count
			counts.append("%d %s %d/%d" % [idx, mm_name, n, n_ref])
			if n >= n_ref:
				problems.append("chunk %d keeps all %d %s (reference %d)" % [idx, n, mm_name, n_ref])
		if (root.get_node(^"Barrier") as Node3D).visible:
			problems.append("chunk %d has a centre barrier" % idx)
	var want := RoadFrame.roll(Vector3(0.0, 0.0, Junction.centre_z()))
	var off := junction.global_position.distance_to(want)
	lines.append("place: %d chunks touch the crossing, %d problems, node %.2f m from the road centre there, %d meshes" % [
		touched, problems.size(), off, junction.get_child_count()])
	lines.append("  instances (here/reference): " + ", ".join(counts))
	for s in problems.slice(0, 8):
		lines.append("  " + s)
	_check(touched >= 1, "place: no pooled chunk touches the crossing (player at %.0f, centre %.0f)" % [RoadFrame.unroll(p.global_position).z, Junction.centre_z()])
	_check(problems.is_empty(), "place: %d layout problems at the crossing" % problems.size())
	_check(off < 0.05, "place: the crossing's node is %.2f m off the road" % off)
	_check(junction.get_child_count() >= 12, "place: the crossing has %d meshes" % junction.get_child_count())

# ---------- red ----------

func _setup_red() -> void:
	junction.t = Junction.GREEN_S + Junction.AMBER_S  # red just began: 22 s of it
	traffic.set_car_count(6)
	_add(0, false, 70.0, 20.0, 25.0)
	_add(0, false, 95.0, 20.0, 25.0)
	_add(1, false, 80.0, 20.0, 25.0)
	_add(1, false, 105.0, 20.0, 25.0)
	_add(0, true, 75.0, 20.0, 25.0)
	_add(1, true, 90.0, 20.0, 25.0)

func _tick_red() -> void:
	_watch()
	if junction.main_state() == Junction.RED:
		red_ticks += 1
		if junction.lit(false) == "red":
			red_lit_ticks += 1

func _end_red() -> void:
	var red_s := float(red_ticks) / RATE
	var heads: Array[String] = []
	var worst := INF
	for i in cars.size():
		heads.append("%.1f m at %.1f km/h" % [red_d[i], Harness.kmh(red_v[i])])
		worst = minf(worst, min_d[i])
	var crossed := 0
	var last_cross := 0.0
	for i in cars.size():
		if crossed_tick[i] >= 0:
			crossed += 1
			last_cross = maxf(last_cross, float(crossed_tick[i]) / RATE)
	lines.append("red: %.1f s of red (lamp red %.1f s), end of red per car (short of the line) %s, crossed on red %d, max stuck timer %.1f s, wreck/hazard ticks %d, contacts %d, all %d crossed by %.1f s" % [
		red_s, float(red_lit_ticks) / RATE, ", ".join(heads), red_crossings, max_stuck, wrecked_seen, contacts, crossed, last_cross])
	_check(red_s > 21.5, "red: the light was red for only %.1f s" % red_s)
	_check(red_lit_ticks >= red_ticks - 2, "red: the main-road lamp showed red for %d of %d red ticks" % [red_lit_ticks, red_ticks])
	_check(red_crossings == 0, "red: %d cars crossed the stop line on red" % red_crossings)
	_check(worst > -Junction.PAST_LINE, "red: a car's front got %.2f m past the stop line" % -worst)
	_check(wrecked_seen == 0, "red: %d car-ticks flagged wrecked/hazard while queueing (stuck check)" % wrecked_seen)
	_check(max_stuck < 1.0, "red: a queued car's stuck timer reached %.1f s" % max_stuck)
	_check(contacts == 0, "red: %d ticks of cars touching" % contacts)
	_check(held_seen > 0, "red: no car was ever held by the light")
	for i in [0, 2, 4, 5]:  # the first car in each lane stops at the line
		_check(red_d[i] > -Junction.PAST_LINE and red_d[i] < 3.0 and red_v[i] < 0.5, "red: lane head %d ended the red %.1f m short of the line at %.1f km/h" % [i, red_d[i], Harness.kmh(red_v[i])])
	for i in [1, 3]:  # the second queues behind it
		_check(red_d[i] > red_d[i - 1] + 2.0 * cars[i].half_l and red_d[i] < red_d[i - 1] + 2.0 * cars[i].half_l + 8.0 and red_v[i] < 0.5,
			"red: car %d queued %.1f m short of the line, the car ahead %.1f m" % [i, red_d[i], red_d[i - 1]])
	_check(crossed == cars.size(), "red: only %d of %d cars crossed after green" % [crossed, cars.size()])

# ---------- amber ----------

func _setup_amber() -> void:
	junction.t = Junction.GREEN_S - 0.02  # amber in 2 ticks
	traffic.set_car_count(2)
	_add(0, false, 25.0, 25.0, 25.0)   # 12.5 m/s^2 to stop: goes
	_add(1, false, 120.0, 25.0, 25.0)  # 2.6 m/s^2: stops

func _tick_amber() -> void:
	_watch()

func _end_amber() -> void:
	lines.append("amber: near car %s, far car %.1f m short of the line at %.1f km/h, contacts %d" % [
		"went through" if crossed_tick[0] >= 0 else "stopped", red_d[1], Harness.kmh(red_v[1]), contacts])
	_check(crossed_tick[0] >= 0 and float(crossed_tick[0]) / RATE < 2.0, "amber: the car that could not stop did not go through")
	_check(crossed_tick[1] < 0 and red_d[1] > -Junction.PAST_LINE and red_d[1] < 3.0 and red_v[1] < 0.5, "amber: the car that could stop did not stop at the line (%.1f m short at %.1f km/h)" % [red_d[1], Harness.kmh(red_v[1])])
	_check(contacts == 0, "amber: %d ticks of cars touching" % contacts)

# ---------- flash ----------

func _setup_flash():
	junction.force_flash = 1
	junction.t = Junction.GREEN_S + Junction.AMBER_S + 5.0  # would be red
	traffic.set_car_count(3)
	_add(0, false, 120.0, 20.0, 20.0)
	_add(1, false, 150.0, 20.0, 20.0)
	_add(0, true, 120.0, 20.0, 20.0)

func _tick_flash() -> void:
	_watch()
	match junction.lit(false):
		"amber":
			flash_on += 1
		"":
			flash_off += 1
	if junction.lit(true) == "red":
		flash_cross_red += 1

func _end_flash() -> void:
	var crossed := 0
	for i in cars.size():
		if crossed_tick[i] >= 0:
			crossed += 1
	lines.append("flash: main amber lit %.1f s / dark %.1f s, cross red lit %.1f s, held ticks %d, %d of %d crossed" % [
		float(flash_on) / RATE, float(flash_off) / RATE, float(flash_cross_red) / RATE, held_seen, crossed, cars.size()])
	_check(flash_on > 0 and flash_off > 0, "flash: the main road's amber is not flashing")
	_check(flash_cross_red > 0, "flash: the cross street's red is not flashing")
	_check(held_seen == 0, "flash: traffic was held %d car-ticks under a flashing amber" % held_seen)
	_check(crossed == cars.size(), "flash: only %d of %d cars drove through" % [crossed, cars.size()])
	# The real switch-over: the night clock at 1 a.m. flashes with no override.
	junction.force_flash = -1
	var clock: NightClock = game.get("night_clock")
	var keep := clock.minutes
	clock.minutes = Junction.FLASH_FROM - 1.0
	var before := junction.flashing()
	clock.minutes = Junction.FLASH_FROM + 1.0
	var after := junction.flashing()
	clock.minutes = keep
	_check(not before and after, "flash: the clock does not switch the flash on at 1 a.m. (before %s, after %s)" % [before, after])

# ---------- off ----------

func _end_off() -> void:
	Junction.enabled = false
	var g := junction.stop_gap(_line(-1.0) + 30.0, -1.0, 2.0, 10.0)
	Junction.enabled = true
	_check(g == INF, "off: with the switch off a red light still holds traffic")
	_check(TrafficSettings.CITY_LIGHTS_DEFAULT == false, "off: City lights is on by default")
	var keep := AudioSettings.path
	AudioSettings.path = "user://junction_missing_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.path))
	TrafficSettings.load_settings()
	var loaded := TrafficSettings.city_lights
	AudioSettings.path = keep
	_check(not loaded, "off: a fresh settings file turns City lights on")
	lines.append("off: stop_gap with the switch off %s, default %s, fresh file %s" % [g, TrafficSettings.CITY_LIGHTS_DEFAULT, loaded])

# ---------- end ----------

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _end(err: String) -> bool:
	if err != "":
		fails.append(err)
	for e in logger.errors:
		fails.append("engine error: " + e)
	for l in lines:
		print(l)
	if fails.is_empty():
		print("PASS: junction_lights")
		quit(0)
	else:
		for f in fails:
			printerr("FAIL: ", f)
		quit(1)
	return true
