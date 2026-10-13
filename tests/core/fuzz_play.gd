extends SceneTree

# Stress layer B (notes/stress-test-and-readiness-2026-10-13.md): one long
# fuzz run of the whole game, not just the car. Real key events go in through
# Input.parse_input_event, so every key in the keyboard map reaches the code a
# player's key press reaches: driving, gears, lights, horn, F6 fix, F camera,
# F7 put-back, pause and the menus behind it (arrows, Enter, Esc), map, tuner,
# photo mode, radio, F9 bug folder. The difficulty and damage settings also
# change mid-run. Traffic and police are on, on the hilly, bendy loop.
#
#   FUZZ_SEED=<n> godot --headless --path . -s res://tests/core/fuzz_play.gd
#
# One seed per process (tools/fuzz_runs.py runs many side by side). The seed
# picks the car, the place on the loop, the act, the traffic count, the
# start (straight onto the road, or title screen and garage first, or a
# minute before dawn) and every key press: the key stream is a function of
# the seed alone, so the same seed presses the same keys at the same ticks.
# FUZZ_SECS (default 60) is the game time of key presses.
#
# After the key presses, a recovery check: back to driving (Esc / Enter
# through whatever screen is open), F6, gas for a few seconds; the car has
# to move. A run that cannot get back is a stuck state.
#
# Fails on: an engine error, a NaN in the player's, a cop's or a traffic
# car's state, the player under the road, a stuck state. Prints one line
# "FUZZ_RESULT {json}" with what happened and the memory (Godot's own and
# the process's RSS) at the start and end, for tools/fuzz_runs.py.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const DamageDifficulty := preload("res://scripts/car/damage_difficulty.gd")
const RATE := 120

## Held driving keys (by action): a new set every 0.05-1.2 s, as drive_fuzz.
const HOLD_ACTIONS := [&"accelerate", &"brake", &"steer_left", &"steer_right", &"handbrake", &"clutch"]
const HOLD_CHANCE := [0.7, 0.2, 0.3, 0.3, 0.1, 0.05]
## Menu keys besides the mapped ones (pause menu, settings, tuner, garage).
const NAV_KEYS := [KEY_ESCAPE, KEY_ENTER, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_SPACE, KEY_BACKSPACE]
const MENU_NAV := [KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_TAB, KEY_SPACE]

var logger := Harness.ErrorCounter.new()
var seed_value := 1
var secs := 60.0
var rng := RandomNumberGenerator.new()
var setup := {}
var game: Node
var tick := 0             # ticks since the key presses began
var started := false
var schedule: Array = []  # [tick, keycode, pressed] sorted by tick; settings changes as [tick, -1, {..}]
var next_event := 0
var held := {}            # keycode -> true
var fails: Array[String] = []
var info := {"states": {}, "reloads": 0, "top_kmh": 0.0, "keys": 0, "settings_changes": 0}
var mem := {}
var _last_game_id := 0
var _phase := "fuzz"      # fuzz -> recover -> drive -> done
var _phase_tick := 0
var _drive_from := Vector3.ZERO
var _drive_moved := 0.0
var _boot_ticks := 0

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	var s := OS.get_environment("FUZZ_SEED")
	seed_value = int(s) if s.is_valid_int() else 1
	var sec := OS.get_environment("FUZZ_SECS")
	secs = float(sec) if sec.is_valid_float() else 60.0
	rng.seed = hash("fuzz_play:%d" % seed_value)
	_pick_setup()
	game = Harness.boot(self, setup.traffic, 300.0, seed_value)
	# Restart night and Quit to title reload the current scene, as in the game.
	current_scene = game

## What this seed plays: car, place, act, traffic, how the run starts.
func _pick_setup() -> void:
	var cars := PlayerCars.ids()
	setup.car = cars[rng.randi_range(0, cars.size() - 1)]
	setup.act = rng.randi_range(1, 3)
	setup.traffic = rng.randi_range(6, 20)
	var r := rng.randf()
	setup.start = "road" if r < 0.6 else ("title" if r < 0.8 else "dawn")
	setup.district = rng.randi_range(1, 8 * setup.act if setup.act < 3 else 16)
	setup.start_s = (setup.district - 1) * 800.0 + rng.randf_range(0.0, 790.0)
	setup.difficulty = rng.randi_range(0, DamageDifficulty.NAMES.size() - 1)
	setup.damage = rng.randi_range(0, GameSettings.DAMAGE_NAMES.size() - 1)
	OS.set_environment("NEON_CAR", setup.car)
	OS.set_environment("NEON_ACT", str(setup.act))
	OS.set_environment("NEON_START_S", "%.1f" % setup.start_s)
	OS.set_environment("NEON_POLICE", "1")
	OS.set_environment("NEON_CURVES", "")
	OS.set_environment("NEON_HILLS", "")
	OS.set_environment("NEON_MUTE", "1")
	OS.set_environment("NEON_TITLE", "1" if setup.start == "title" else "0")
	OS.set_environment("NEON_GARAGE", "0" if setup.start == "road" else "1")
	GameSettings.set_difficulty(setup.difficulty)
	GameSettings.set_damage(setup.damage)

## The whole key stream, from the seed alone (the codes come from the
## InputMap, sorted, so they are the same every run of this build).
func _build_schedule() -> void:
	var holds := {}
	for a in HOLD_ACTIONS:
		holds[a] = _first_key(a)
	var taps := {}
	for a in KeyBindings.game_actions():
		if KeyBindings.context(a) != "play" or a in HOLD_ACTIONS:
			continue
		for c in KeyBindings.keys(a):
			taps[c] = true
	for c in NAV_KEYS:
		taps[c] = true
	taps.erase(KEY_ESCAPE)   # Esc comes with the menu visits below, or the run is mostly paused
	var tap_keys: Array = taps.keys()
	tap_keys.sort()
	setup.tap_keys = tap_keys.size()
	var end := int(secs * RATE)
	# Held driving keys.
	var t := 0
	var down := {}
	while t < end:
		var want := {}
		for i in HOLD_ACTIONS.size():
			if holds[HOLD_ACTIONS[i]] != 0 and rng.randf() < HOLD_CHANCE[i]:
				want[holds[HOLD_ACTIONS[i]]] = true
		for c in down:
			if not want.has(c):
				schedule.append([t, c, false])
		for c in want:
			if not down.has(c):
				schedule.append([t, c, true])
		down = want
		t += maxi(1, int(rng.randf_range(0.05, 1.2) * RATE))
	for c in down:
		schedule.append([end, c, false])
	# Single taps of any other key, about one every 1.5 s.
	t = 0
	while true:
		t += maxi(1, int(rng.randf_range(0.1, 3.0) * RATE))
		if t >= end:
			break
		_tap(t, tap_keys[rng.randi_range(0, tap_keys.size() - 1)])
	# Menu visits, about one every 10 s: open something (Esc, M, T, P...),
	# poke around it, usually back out with Esc.
	var openers: Array = [KEY_ESCAPE, KEY_ESCAPE, KEY_ESCAPE]
	for a in [&"map", &"tuning_panel", &"photo_mode", &"put_back", &"fix_car"]:
		var c := _first_key(a)
		if c != 0:
			openers.append(c)
	t = 0
	while true:
		t += maxi(1, int(rng.randf_range(3.0, 17.0) * RATE))
		if t >= end:
			break
		_tap(t, openers[rng.randi_range(0, openers.size() - 1)])
		var u := t
		for i in rng.randi_range(0, 12):
			u += maxi(4, int(rng.randf_range(0.1, 0.7) * RATE))
			_tap(u, MENU_NAV[rng.randi_range(0, MENU_NAV.size() - 1)])
		if rng.randf() < 0.85:
			u += maxi(4, int(rng.randf_range(0.2, 1.0) * RATE))
			_tap(u, KEY_ESCAPE)
		t = u
	# Difficulty / damage changes mid-run, about one every 20 s.
	t = 0
	while true:
		t += maxi(1, int(rng.randf_range(5.0, 35.0) * RATE))
		if t >= end:
			break
		schedule.append([t, -1, {"difficulty": rng.randi_range(0, DamageDifficulty.NAMES.size() - 1),
				"damage": rng.randi_range(0, GameSettings.DAMAGE_NAMES.size() - 1)}])
	schedule.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	info.keys = schedule.size()

func _tap(t: int, code: int) -> void:
	schedule.append([t, code, true])
	schedule.append([t + maxi(3, int(rng.randf_range(0.03, 0.25) * RATE)), code, false])

func _first_key(action: StringName) -> int:
	var k := KeyBindings.keys(action)
	return k[0] if not k.is_empty() else 0

func _key(code: int, pressed: bool) -> void:
	if code == 0 or pressed == held.has(code):
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	if pressed:
		held[code] = true
	else:
		held.erase(code)

func _release_all() -> void:
	for c in held.keys():
		_key(c, false)

func _physics_process(_delta: float) -> bool:
	# Restart and Quit to title swap the Game node for a new one.
	if not is_instance_valid(game) or game.is_queued_for_deletion() or not game.is_inside_tree():
		game = current_scene
		if game == null or not is_instance_valid(game) or not game.is_inside_tree():
			return false
	if game.get_instance_id() != _last_game_id:
		if _last_game_id != 0:
			info.reloads += 1
		_last_game_id = game.get_instance_id()
	var p: PlayerCar = game.get("player")
	if not started:
		_boot_ticks += 1
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			if _boot_ticks > 60 * RATE:
				fails.append("seed %d: the game never got ready" % seed_value)
				return _end()
			return false
		started = true
		_build_schedule()
		if setup.start == "dawn":
			var clock: NightClock = game.get("night_clock")
			clock.set_time(NightClock.NIGHT_MINUTES - 0.5, 1)   # 30 game s (2 s) before 6 a.m.
		if setup.start == "road":
			TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, 25.0)
		mem.start = _memory()
		return false
	tick += 1
	var gs: GameState = game.get("game_state")
	if gs != null:
		var st: String = GameState.State.keys()[gs.state]
		info.states[st] = int(info.states.get(st, 0)) + 1
	var heat: Variant = game.get("police_heat")
	if heat != null and is_instance_valid(heat):
		info.heat_max = maxi(int(info.get("heat_max", 0)), int(heat.level))
	if p != null and is_instance_valid(p) and p.is_ready:
		info.top_kmh = maxf(info.top_kmh, p.linear_velocity.length() * 3.6)
		var bad := TestDriver.sanity(p)
		if bad != "":
			fails.append("seed %d, tick %d (%s): %s" % [seed_value, tick, _phase, bad])
			return _end()
	var other := _check_others()
	if other != "":
		fails.append("seed %d, tick %d (%s): %s" % [seed_value, tick, _phase, other])
		return _end()
	if not logger.errors.is_empty():
		fails.append("seed %d, tick %d (%s): %d engine error(s), first: %s" % [seed_value, tick, _phase, logger.errors.size(), logger.errors[0]])
		return _end()
	match _phase:
		"fuzz":
			while next_event < schedule.size() and schedule[next_event][0] <= tick:
				var e: Array = schedule[next_event]
				next_event += 1
				if e[1] == -1:
					GameSettings.set_difficulty(e[2].difficulty)
					GameSettings.set_damage(e[2].damage)
					info.settings_changes += 1
				else:
					_key(e[1], e[2])
			if tick >= int(secs * RATE):
				_release_all()
				mem.end_fuzz = _memory()
				_phase = "recover"
				_phase_tick = 0
		"recover":
			return _recover(gs, p)
		"drive":
			return _drive_check(gs, p)
	return false

## Back to driving the way a keyboard player would, 20 s of game time at most:
## Esc out of what Esc closes; on a screen it does not (garage, dawn card,
## title, a confirm box), arrows through the buttons and Enter on the one that
## leads back to the road. A screen with no keyboard focus is stuck.
const LEAVE_BUTTONS := ["resume", "go out", "continue", "new game", "drive", "no", "back"]
const RECOVER_STEP := RATE / 4

func _recover(gs: GameState, p: PlayerCar) -> bool:
	_phase_tick += 1
	if gs != null and gs.state == GameState.State.PLAYING and p != null and p.is_ready:
		_release_all()
		_phase = "drive"
		_phase_tick = 0
		return false
	var focus := root.gui_get_focus_owner()
	if _phase_tick > 20 * RATE:
		fails.append("seed %d: stuck in %s, 20 s of Esc / arrows / Enter did not get back to the road (focus on %s)" % [seed_value,
				GameState.State.keys()[gs.state] if gs != null else "no game state",
				"nothing" if focus == null else "%s '%s', visible %s, disabled %s" % [focus.get_path(), focus.get("text"), focus.is_visible_in_tree(), focus.get("disabled")]])
		for c in game.get_children():
			if c.get_script() != null and str(c.get_script().resource_path).ends_with("title_screen.gd"):
				fails.append("title: panel %s, welcome %s, confirm open %s, splash %s, lists main %s load %s" % [c.panel.visible, c.welcome.visible,
						c.confirm.is_open(), c.splash_running(), c.main_list.visible, c.load_list.visible])
		return _end()
	var step := _phase_tick % RECOVER_STEP
	if step == 0:
		var n := _phase_tick / RECOVER_STEP
		var esc_closes := gs != null and gs.state in [GameState.State.PAUSED, GameState.State.TUNING,
				GameState.State.AUTOTUNE, GameState.State.PHOTO, GameState.State.STATION, GameState.State.WASH]
		var on_leave: bool = focus is BaseButton and focus.is_visible_in_tree() and not focus.disabled and str(focus.get("text")).to_lower() in LEAVE_BUTTONS
		if on_leave:
			_key(KEY_ENTER, true)
		elif esc_closes and gs.state != GameState.State.PAUSED:
			_key(KEY_ESCAPE, true)
		elif focus == null:
			# A screen with its own selection and no focus (Walt's board, the
			# job's timing bar): Enter works it, arrows move, Esc backs out.
			_key([KEY_ENTER, KEY_ENTER, KEY_DOWN, KEY_ESCAPE][n % 4], true)
		elif n % 6 == 0:
			_key(KEY_ESCAPE, true)   # a sub-page (Settings, a tab) backs out with Esc
		else:
			_key(KEY_DOWN if (n / 8) % 2 == 0 else KEY_UP, true)   # walk the buttons to a way out, down then up
	elif step == 6:
		_release_all()
	return false

## F6, engine on, automatic, gas: the car has to move 10 m. Forward first;
## a car nosed into a wall or a building gets reverse (R) and the wheel, the
## way a player shuffles out of a tight spot. Stuck only if none of it works.
const DRIVE_STAGE_TICKS := 5 * RATE
## [reverse?, steer: -1 left, 0 straight, +1 right]
const DRIVE_STAGES := [[false, 0], [true, 0], [false, -1], [true, 1], [false, 1], [true, -1], [false, 0]]
var _drive_stage := 0
var _stage_tick := 0

func _drive_check(gs: GameState, p: PlayerCar) -> bool:
	_phase_tick += 1
	_stage_tick += 1
	if _phase_tick == 1:
		_drive_stage = 0
		_stage_tick = 1
		_key(_first_key(&"fix_car"), true)
	elif _phase_tick == 6:
		_release_all()
		p.set_transmission_mode(PlayerCar.Transmission.AUTO)
		_drive_from = p.global_position
	elif _phase_tick > 6 and not p.engine_running and _stage_tick < 3 * RATE:
		_key(_first_key(&"starter"), true)   # X cranks a stopped engine
	elif _phase_tick > 6:
		if held.has(_first_key(&"starter")):
			_key(_first_key(&"starter"), false)
		_key(_first_key(&"accelerate"), true)
		var steer: int = DRIVE_STAGES[_drive_stage][1]
		if steer != 0:
			_key(_first_key(&"steer_left" if steer < 0 else &"steer_right"), true)
	if _phase_tick > 6:
		_drive_moved = maxf(_drive_moved, p.global_position.distance_to(_drive_from))
	if gs != null and gs.state != GameState.State.PLAYING:
		# A cop got him, a wreck, dawn: back to the recovery step.
		_release_all()
		_phase = "recover"
		_phase_tick = 0
		return false
	if _drive_moved > 10.0:
		_release_all()
		info.drive_check = "moved %.0f m (try %d)" % [_drive_moved, _drive_stage + 1]
		return _end()
	if _phase_tick > 6 and _stage_tick > DRIVE_STAGE_TICKS:
		if _drive_stage == DRIVE_STAGES.size() - 1:
			fails.append("seed %d: after the fuzz the car will not drive: under 10 m on each of %d tries of 5 s (forward, reverse, with and without steering) (engine %s, gear %d, speed %.1f km/h; %s)" % [
					seed_value, DRIVE_STAGES.size(), "on" if p.engine_running else "off", p.current_gear, p.current_speed() * 3.6, _car_state(p)])
			return _end()
		_release_all()
		_drive_stage += 1
		_stage_tick = 0
		_drive_moved = 0.0
		_drive_from = p.global_position
		if DRIVE_STAGES[_drive_stage][0] != (p.current_gear == -1) and not p.toggle_reverse():
			info.reverse_refused = int(info.get("reverse_refused", 0)) + 1
	return false

## What a car that will not drive is doing, for the failure line.
func _car_state(p: PlayerCar) -> String:
	var ground := 0
	for w in p.wheel_array:
		if w.is_colliding():
			ground += 1
	var u := RoadFrame.unroll(p.global_position)
	return "throttle %.2f brake %.2f handbrake %.2f clutch %.2f keys %d, rpm %.0f, fuel %.1f l, %d wheels down, road x %.1f y %.1f, up %.2f, held %s" % [
			p.throttle_input, p.brake_input, p.handbrake_input, p.clutch_input, p.last_keys, p.motor_rpm,
			p.fuel.litres, ground, u.x, u.y, p.global_transform.basis.y.y, held.keys()] \
			+ ", freeze %s sleeping %s, spins %s, trans %d, tree paused %s, limp %s" % [p.freeze, p.sleeping,
			p.wheel_array.map(func(w: Variant) -> float: return snappedf(w.spin, 0.1)), p.transmission_mode(),
			p.get_tree().paused, str(p.get("limp"))] \
			+ ", Input: accel %s handbrake %s W %s, handbrake keys %s" % [Input.is_action_pressed(&"accelerate"),
			Input.is_action_pressed(&"handbrake"), Input.is_physical_key_pressed(KEY_W), KeyBindings.keys(&"handbrake")] \
			+ ", physics %s can_process %s mode %d driver %s time_scale %.2f, garage_flow %s" % [p.is_physics_processing(), p.can_process(), p.process_mode,
			p.driver.is_valid(), Engine.time_scale, game.get("garage_flow")] \
			+ ", springs %s, colliders %s, touching %s, road s %.0f" % [p.wheel_array.map(func(w: Variant) -> float: return snappedf(w.spring_current_length, 0.01)),
			p.wheel_array.map(func(w: Variant) -> String: return str(w.get_collider().name) if w.get_collider() != null else "-"),
			_touching(p), RoadFrame.s_at(p.global_position.z)] \
			+ ", heading %.0f deg, rescue count %d" % [rad_to_deg(TestDriver.heading_error(p)), game.rescue.count]

## What the car's body is touching (a box a little bigger than the body).
func _touching(p: PlayerCar) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.6, 5.0)
	q.shape = box
	q.transform = p.global_transform
	q.exclude = [p.get_rid()]
	var out: Array = []
	for hit in p.get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c: Object = hit.collider
		var where := ""
		if c is CollisionObject3D:
			var owner_id: int = (c as CollisionObject3D).shape_find_owner(hit.shape)
			var sh: Shape3D = (c as CollisionObject3D).shape_owner_get_shape(owner_id, 0)
			var xf: Transform3D = (c as Node3D).global_transform * (c as CollisionObject3D).shape_owner_get_transform(owner_id)
			var u := RoadFrame.unroll(xf.origin)
			where = " at x %.1f y %.1f s %.1f size %s" % [u.x, u.y, RoadFrame.s_at(u.z), str((sh as BoxShape3D).size) if sh is BoxShape3D else sh.get_class()]
		out.append("%s(%s)%s" % [c.get("name"), c.get_class(), where])
	var b: Vector2 = game.rescue._bounds_at(RoadFrame.unroll(p.global_position).z)
	out.append("walls at +%.1f / -%.1f" % [b.x, b.y])
	return out

## A cop or a traffic car with a NaN in its state.
func _check_others() -> String:
	var police: Variant = game.get("police")
	if police != null and is_instance_valid(police):
		for u in police.units:
			if is_instance_valid(u.car) and not Harness.finite(u.car):
				return "NaN in a police car's state"
	var traffic: Variant = game.get("traffic")
	if traffic != null and is_instance_valid(traffic) and tick % 30 == 0:
		for c in traffic.cars:
			if is_instance_valid(c) and c.is_inside_tree() and not (c.global_position.is_finite() and c.linear_velocity.is_finite()):
				return "NaN in a traffic car's state"
	return ""

func _memory() -> Dictionary:
	var rss := 0
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("VmRSS:"):
				rss = int(line.split(":")[1].strip_edges().split(" ")[0]) / 1024
	return {"tick": tick, "static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"rss_mb": rss, "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))}

## QUIT on the title (or anything else that ends the game) ends the run
## early: what was played still counts, and it is not a failure by itself.
func _finalize() -> void:
	if _ended:
		return
	fails.append_array([] if logger.errors.is_empty() else ["seed %d, tick %d: %d engine error(s) before the game quit, first: %s" % [seed_value, tick, logger.errors.size(), logger.errors[0]]])
	info.quit_by_game = true
	_end()

var _ended := false

func _end() -> bool:
	_ended = true
	_release_all()
	mem.end = _memory()
	var out := setup.duplicate()
	out.seed = seed_value
	out.pass = fails.is_empty()
	out.fails = fails
	out.errors = logger.errors.slice(0, 5)
	out.error_count = logger.errors.size()
	out.ticks = tick
	out.phase = _phase
	out.merge(info)
	out.mem = mem
	out.native = CarSimSwitch.active()
	print("FUZZ_RESULT " + JSON.stringify(out))
	for f in fails:
		printerr("FAIL: " + f)
	print("fuzz_play seed %d: %s" % [seed_value, "PASS" if fails.is_empty() else "FAIL"])
	quit(1 if not fails.is_empty() else 0)
	return true
