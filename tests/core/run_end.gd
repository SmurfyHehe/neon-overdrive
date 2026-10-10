extends SceneTree

# Ending a run on a crash (decided 2026-10-10): scripts/car/wreck_rules.gd,
# wreck_sensor.gd, scripts/core/run_end.gd, scripts/ui/crash_screen.gd.
#
# Part 1, the rules on their own: wall speed from closing speed and the other
# car's mass, the three outcomes, and what a wreck takes from tonight's cash.
#
# Part 2, the sensor in the real game (its own sensor on the player's car, the
# game's own one switched off so nothing ends halfway):
# - a wall at 30 km/h is a bump; a wall at 80 km/h is a wreck, measured near 80;
# - a wall met at 30 degrees at 90 km/h is a bump: only the speed INTO the
#   wall counts, not the speed along it;
# - a standing 800 kg car hit at 60 km/h is a bump, and it gets pushed;
# - closing at 110 km/h on a 2100 kg car is a wreck, on an 800 kg one a bump:
#   same closing speed, the other car's mass decides.
#
# Part 3, the whole thing: the first wreck (free), then a paid one, bad cops,
# and a huge crash, each through every step of the crash screen.
#   <godot> --headless --fixed-fps 120 --path . -s res://tests/core/run_end.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const WreckRules := preload("res://scripts/car/wreck_rules.gd")
const WreckSensor := preload("res://scripts/car/wreck_sensor.gd")
const RunEnd := preload("res://scripts/core/run_end.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const ROOT := "user://test_run_end"
const KMH := 1.0 / 3.6

enum Step { BOOT, WALL_30, WALL_80, WALL_GLANCE, CAR_LIGHT, CAR_HEAVY, CAR_LIGHT_FAST, FIRST, PAID, BAD_COPS, HUGE, DONE }

var failures: Array[String] = []
var game: Node
var step := Step.BOOT
var tick := 0
var t := 0
var hz := 120
var rest: Transform3D
var sensor: WreckSensor
var prop: Node3D
var hits_before := 0
var wrecks: Array = []       # outcomes my sensor reported
var run_end: Node            # the RunEnd under test in part 3
var started: Array = []      # wreck_started args
var done: Array = []         # finished args
var seen := {}               # what the crash screen showed, by phase
var night_before := 0
var held := false

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	_rules()
	SaveStore.select_slot(1)
	game = Harness.boot(self, 0, 300.0, 77)

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
		d.remove(sub)

# ---------- part 1 ----------
func _rules() -> void:
	var R := WreckRules
	_check(is_equal_approx(R.wall_speed(80.0, 1200.0, 0.0), 80.0), "a wall counts the whole closing speed")
	_check(is_equal_approx(R.wall_speed(100.0, 1200.0, 1200.0), 50.0), "two equal cars share the closing speed")
	_check(R.wall_speed(100.0, 900.0, 2100.0) > R.wall_speed(100.0, 2100.0, 900.0), "the lighter car gets the worse hit")
	_check(R.wall_speed(-5.0, 1200.0, 0.0) == 0.0, "moving apart is no hit")
	_check(R.outcome(R.WRECK_KMH - 0.1) == R.Outcome.BUMP, "just under the line is a bump")
	_check(R.outcome(R.WRECK_KMH) == R.Outcome.WRECK, "the line is a wreck")
	_check(R.outcome(R.NIGHT_END_KMH) == R.Outcome.NIGHT_END, "a huge crash ends the night")
	_check(R.cash_loss(500, false, false) == 250, "a wreck costs half")
	_check(R.cash_loss(501, false, false) == 251, "the odd dollar goes too")
	_check(R.cash_loss(500, true, false) == 500, "bad cops take it all")
	_check(R.cash_loss(500, true, true) == 0 and R.cash_loss(500, false, true) == 0, "the first wreck is free")
	_check(R.cash_loss(0, true, false) == 0, "nothing to take from empty pockets")
	_check(not SaveStore.first_wreck_used(), "a new save has its free wreck")

# ---------- helpers ----------
static func _coast(c: Vehicle) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.steering_input = 0.0
	c.handbrake_input = 0.0

func _clear_prop() -> void:
	if prop != null:
		prop.queue_free()
		prop = null

func _launch(p: PlayerCar, kmh: float) -> void:
	p.global_transform = rest
	p.angular_velocity = Vector3.ZERO
	TrafficCar.set_moving(p, kmh * KMH)
	p.reset_physics_interpolation()
	p.driver = _coast
	p.damage.garage_repair(null)
	p.health.repair()
	hits_before = sensor.hits
	wrecks.clear()
	t = 0

## A wall across the road, `ahead` metres in front of the resting car, turned
## `yaw_deg` from square-on.
func _wall(ahead: float, yaw_deg: float = 0.0) -> void:
	_clear_prop()
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 4.0, 1.0)
	col.shape = box
	body.add_child(col)
	CarSpec.make_wall(body)
	root.add_child(body)
	body.global_transform = Transform3D(rest.basis * Basis(Vector3.UP, deg_to_rad(yaw_deg)), rest.origin - rest.basis.z * (ahead + 0.5))
	prop = body

## A car-sized box of `mass` kg in the car's path, coming at `kmh` (0 = standing).
func _car(ahead: float, mass: float, kmh: float) -> RigidBody3D:
	_clear_prop()
	var body := RigidBody3D.new()
	body.mass = mass
	body.gravity_scale = 0.0
	body.axis_lock_angular_x = true
	body.axis_lock_angular_z = true
	body.collision_layer = 1 << (CarSpec.CAR_LAYER - 1)
	body.collision_mask = 1 << (CarSpec.CAR_LAYER - 1)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.2, 4.2)
	col.shape = box
	body.add_child(col)
	root.add_child(body)
	body.global_transform = Transform3D(rest.basis, rest.origin - rest.basis.z * (ahead + 2.1) + Vector3.UP * 0.2)
	body.linear_velocity = rest.basis.z * kmh * KMH
	prop = body
	return body

func _hit_seen() -> bool:
	return sensor.hits > hits_before

func _settle(game_state: GameState) -> void:
	if game_state.state != GameState.State.PLAYING:
		game_state._set_state(GameState.State.PLAYING)

## A fresh RunEnd on the booted game, as game.gd wires its own.
func _new_run_end(p: PlayerCar, cash: int) -> void:
	if run_end != null:
		run_end.queue_free()
	_clear_prop()
	_settle(game.game_state)
	game.wallet.take_cash(game.wallet.cash)
	game.wallet.add_cash(cash)
	run_end = RunEnd.new()
	run_end.player = p
	run_end.camera = game.camera
	run_end.wallet = game.wallet
	run_end.night_clock = game.night_clock
	run_end.game_state = game.game_state
	run_end.restart_on_finish = false
	game.add_child(run_end)
	started.clear()
	done.clear()
	seen.clear()
	held = false
	run_end.wreck_started.connect(func(o: int, loss: int, free: bool) -> void: started.append([o, loss, free]))
	run_end.finished.connect(func(night: bool) -> void: done.append(night))
	night_before = game.night_clock.night
	p.driver = _coast
	(game.camera as ChaseCamera).set_view(ChaseCamera.View.CHASE)
	t = 0

## Notes what the crash screen shows in each phase, and checks the rules that
## hold all the way through.
func _watch() -> void:
	var ph: int = run_end.phase
	var s: Node = run_end.screen
	if ph == RunEnd.Phase.DRIVING:
		return
	_check(Engine.time_scale == 1.0, "no slow motion")
	_check(not paused, "the tree is never paused")
	_check(game.camera.current and (game.camera as ChaseCamera).view == ChaseCamera.View.COCKPIT, "the view stays in the driver's seat")
	if not seen.has(ph):
		seen[ph] = {"cracked": s.is_cracked(), "black": s.is_black(), "line": s.line_text(), "card": s.card_texts(),
			"scrape": s.scrape_playing(), "trauma": (game.camera as ChaseCamera).trauma,
			"engine_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Engine"))}

func _report(label: String) -> void:
	print("%s: outcome %s loss %s free %s, night ended %s, cash %d bank %d" % [label,
		started[0][0] if not started.is_empty() else "-", started[0][1] if not started.is_empty() else "-",
		started[0][2] if not started.is_empty() else "-", done, game.wallet.cash, game.wallet.bank])
	for ph in seen:
		print("   %s: %s" % [RunEnd.Phase.keys()[ph], seen[ph]])

func _common_screen_checks(label: String) -> void:
	var P := RunEnd.Phase
	_check(seen.has(P.HIT) and seen[P.HIT].cracked and not seen[P.HIT].black, label + ": the hit shows cracked glass, not black")
	_check(seen.has(P.HIT) and seen[P.HIT].trauma > 0.8, label + ": the hit shakes the camera")
	_check(seen.has(P.HIT) and not seen[P.HIT].engine_muted, label + ": the sound carries on through the hit")
	_check(seen.has(P.BLACK) and seen[P.BLACK].black and not seen[P.BLACK].cracked and seen[P.BLACK].line == "", label + ": then a hard cut to black, no line yet")
	_check(seen.has(P.BLACK) and seen[P.BLACK].scrape and seen[P.BLACK].engine_muted, label + ": the black has the scrape tail and nothing else")
	_check(seen.has(P.LINE) and seen[P.LINE].line != "" and not seen[P.LINE].scrape, label + ": then Dave's line, the scrape gone")

# ---------- the drive ----------
func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	hz = Engine.physics_ticks_per_second
	if tick > hz * 240:
		return _end("timed out in %s" % Step.keys()[step])
	var p: PlayerCar = game.get("player") if game != null else null
	if p == null:
		return tick > hz * 10 and _end("Game never became ready")
	match step:
		Step.BOOT:
			if t >= hz:
				rest = p.global_transform
				_check(game.run_end != null and not game.run_end.sensor.enabled, "in a test the game's own wrecks are off unless asked for")
				sensor = WreckSensor.new(p)
				sensor.wrecked.connect(func(o: int, _w: float, _c: float, _obj: Object) -> void: wrecks.append(o))
				root.add_child(sensor)
				print("car: %s, %.0f kg" % [PlayerCar.chassis_kind(), p.mass])
				_wall(14.0)
				_launch(p, 30.0)
				step = Step.WALL_30
		Step.WALL_30:
			if _hit_seen() or t > hz * 6:
				print("wall at 30 km/h: closing %.1f, wall speed %.1f km/h" % [sensor.last_closing_kmh, sensor.last_wall_kmh])
				_check(_hit_seen() and absf(sensor.last_wall_kmh - 30.0) < 6.0, "a 30 km/h wall hit is measured near 30")
				_check(wrecks.is_empty(), "a 30 km/h wall hit is a bump")
				_wall(14.0)
				_launch(p, 80.0)
				step = Step.WALL_80
		Step.WALL_80:
			if _hit_seen() or t > hz * 6:
				print("wall at 80 km/h: closing %.1f, wall speed %.1f km/h" % [sensor.last_closing_kmh, sensor.last_wall_kmh])
				_check(_hit_seen() and absf(sensor.last_wall_kmh - 80.0) < 10.0, "an 80 km/h wall hit is measured near 80")
				_check(wrecks == [WreckRules.Outcome.WRECK], "an 80 km/h wall hit is a wreck")
				_wall(14.0, 60.0)  # turned 60 degrees: the car meets it at 30
				_launch(p, 90.0)
				step = Step.WALL_GLANCE
		Step.WALL_GLANCE:
			if _hit_seen() or t > hz * 6:
				print("wall at 90 km/h, 30 degrees: closing %.1f, wall speed %.1f km/h (straight in would be %.1f)" % [sensor.last_closing_kmh, sensor.last_wall_kmh, 90.0 * sin(deg_to_rad(30.0))])
				_check(_hit_seen() and absf(sensor.last_wall_kmh - 45.0) < 8.0, "a glancing hit counts only the speed into the wall")
				_check(wrecks.is_empty(), "a 90 km/h glancing hit is a bump")
				_car(10.0, 800.0, 0.0)
				_launch(p, 60.0)
				step = Step.CAR_LIGHT
		Step.CAR_LIGHT:
			if (_hit_seen() and t > hz) or t > hz * 6:
				var want := WreckRules.wall_speed(60.0, p.mass, 800.0)
				var pushed := (prop as RigidBody3D).linear_velocity.length() * 3.6
				print("standing 800 kg car at 60 km/h: closing %.1f, wall speed %.1f km/h (rule says %.1f); it left at %.1f km/h" % [sensor.last_closing_kmh, sensor.last_wall_kmh, want, pushed])
				_check(_hit_seen() and absf(sensor.last_closing_kmh - 60.0) < 8.0, "the closing speed on a standing car is the player's speed")
				_check(wrecks.is_empty(), "a light standing car at 60 km/h is a bump")
				_check(pushed > 15.0, "the bumped car is pushed along")
				_car(12.0, 2100.0, 50.0)
				_launch(p, 60.0)
				step = Step.CAR_HEAVY
		Step.CAR_HEAVY:
			if _hit_seen() or t > hz * 6:
				var want := WreckRules.wall_speed(110.0, p.mass, 2100.0)
				print("2100 kg car, closing 110 km/h: closing %.1f, wall speed %.1f km/h (rule says %.1f)" % [sensor.last_closing_kmh, sensor.last_wall_kmh, want])
				_check(_hit_seen() and absf(sensor.last_closing_kmh - 110.0) < 12.0, "head-on, both speeds add up")
				_check(wrecks.size() == 1 and wrecks[0] != WreckRules.Outcome.BUMP, "closing at 110 on a heavy car is a wreck")
				_car(12.0, 800.0, 50.0)
				_launch(p, 60.0)
				step = Step.CAR_LIGHT_FAST
		Step.CAR_LIGHT_FAST:
			if _hit_seen() or t > hz * 6:
				var want := WreckRules.wall_speed(110.0, p.mass, 800.0)
				print("800 kg car, closing 110 km/h: closing %.1f, wall speed %.1f km/h (rule says %.1f)" % [sensor.last_closing_kmh, sensor.last_wall_kmh, want])
				_check(_hit_seen() and absf(sensor.last_closing_kmh - 110.0) < 12.0, "head-on on the light car, both speeds add up")
				_check(wrecks.is_empty() == (want < WreckRules.WRECK_KMH), "the same closing speed on a light car follows the rule for its mass")
				sensor.enabled = false
				# Part 3. The first wreck: a real wall, the game-wired sensor.
				_new_run_end(p, 500)
				_wall(14.0)
				_launch(p, 80.0)
				step = Step.FIRST
		Step.FIRST:
			_watch()
			if run_end.phase == RunEnd.Phase.MORNING and t > 0 and not held and seen.has(RunEnd.Phase.MORNING):
				held = true
				Input.action_press(&"brake")  # hold S
				t = 0
			if not done.is_empty() or t > hz * 40:
				Input.action_release(&"brake")
				_report("first wreck, wall at 80 km/h")
				_common_screen_checks("first wreck")
				_check(started.size() == 1 and started[0] == [WreckRules.Outcome.WRECK, 0, true], "the first wreck is free")
				_check(SaveStore.first_wreck_used(), "the free wreck is used up in the save")
				_check(seen.has(RunEnd.Phase.MORNING) and "Moose" in " ".join(seen[RunEnd.Phase.MORNING].card) and "Walt" in " ".join(seen[RunEnd.Phase.MORNING].card), "the morning card has Moose and Walt")
				_check(done == [true] and held and t < hz * 3, "holding S skips the morning (it took %d ticks)" % t)
				_check(game.night_clock.night == night_before + 1, "the first wreck ends the night")
				_check(game.wallet.cash == 0 and game.wallet.bank == 500, "all of tonight's cash is banked at dawn")
				_check(game.game_state.state == GameState.State.WRECKED, "the game stays in the wrecked state until the restart")
				var bank: int = game.wallet.bank
				_new_run_end(p, 501)
				_check(run_end.begin(WreckRules.Outcome.WRECK), "a second wreck starts")
				seen["bank"] = bank
				step = Step.PAID
		Step.PAID:
			_watch()
			if not done.is_empty() or t > hz * 40:
				var bank: int = seen["bank"]
				seen.erase("bank")
				_report("paid wreck")
				_common_screen_checks("paid wreck")
				_check(started.size() == 1 and started[0] == [WreckRules.Outcome.WRECK, 251, false], "a paid wreck takes half of $501")
				_check("$251" in seen.get(RunEnd.Phase.LINE, {}).get("line", ""), "the line says what was lost")
				_check(not seen.has(RunEnd.Phase.MORNING) and done == [false], "a plain wreck has no morning")
				_check(game.night_clock.night == night_before, "a plain wreck leaves the night going")
				_check(game.wallet.cash == 250 and game.wallet.bank == bank, "the other half stays in the pocket, the bank untouched")
				_check(not run_end.begin(WreckRules.Outcome.WRECK), "a finished wreck cannot start again")
				_new_run_end(p, 400)
				run_end.bad_cops = true
				_check(run_end.begin(WreckRules.Outcome.WRECK), "a wreck with bad cops starts")
				seen["bank"] = bank
				step = Step.BAD_COPS
		Step.BAD_COPS:
			_watch()
			if not done.is_empty() or t > hz * 40:
				var bank: int = seen["bank"]
				seen.erase("bank")
				_report("wreck with bad cops")
				_check(started.size() == 1 and started[0][1] == 400, "bad cops take all of tonight's cash")
				_check(game.wallet.cash == 0 and game.wallet.bank == bank, "and never the bank")
				_check(seen.get(RunEnd.Phase.LINE, {}).get("line", "").begins_with(RunEnd.BAD_COP_LINE), "Dave says who took it")
				_new_run_end(p, 300)
				_check(not run_end.begin(WreckRules.Outcome.BUMP), "a bump ends nothing")
				game.game_state.pause()
				_check(not run_end.begin(WreckRules.Outcome.WRECK), "no wreck starts from the pause menu")
				game.game_state.resume()
				_check(run_end.begin(WreckRules.Outcome.NIGHT_END), "a huge crash starts")
				_check(game.game_state.state == GameState.State.WRECKED, "a wreck puts the game in the wrecked state")
				game.game_state.toggle_pause()
				_check(game.game_state.state == GameState.State.WRECKED and not paused, "Esc does nothing on the crash screen")
				seen["bank"] = bank
				step = Step.HUGE
		Step.HUGE:
			_watch()
			if not done.is_empty() or t > hz * 40:
				var bank: int = seen["bank"]
				seen.erase("bank")
				_report("huge crash")
				_common_screen_checks("huge crash")
				_check(started.size() == 1 and started[0] == [WreckRules.Outcome.NIGHT_END, 150, false], "a huge crash takes half too")
				_check(seen.has(RunEnd.Phase.MORNING) and done == [true], "a huge crash has a morning, which ends by itself")
				_check(game.night_clock.night == night_before + 1, "a huge crash ends the night")
				_check(game.wallet.cash == 0 and game.wallet.bank == bank + 150, "what was left is banked")
				run_end.queue_free()
				run_end = null
				step = Step.DONE
				t = 0
		Step.DONE:
			if t > 2:
				_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Tires")), "the sound comes back when the crash screen goes")
				return _end("")
	return false

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	print("run_end: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
