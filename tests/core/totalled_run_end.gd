extends SceneTree

# The totalled meter in the real game (TM1, 2026-10-11): scripts/core/run_end.gd
# on the booted game, hits fed through RunEnd.hit() with their wall speeds (the
# sensor's own measuring is tests/core/run_end.gd).
#
# - FREE: three 80 km/h hits (0.30 each): still driving, no cash taken, the
#   controls never taken (the driver is still the test's), the camera shakes on
#   each, the glass only from a 0.60 step; the same object twice is one hit;
#   the fourth totals the car. It is the first total of the save: free, the
#   meter back to 0, and Moose and Walt are in the morning card.
# - PAID: after the free one, three hits and a fourth: half of tonight's cash
#   goes, the other half is banked at dawn, the bank is not touched, the
#   night ends, the car is still at 1.0 (no Walt), the morning is the tow.
# - BAD COPS: all of tonight's cash.
# - TOW: the pause menu's tow row is offered at 0.60 on the meter, not at
#   0.55, not in a chase; the tow banks tonight's cash and loses none, and
#   keeps the meter.
# - TEST BUILD: with Wrecks = Meter the game's own sensor is on, and nothing
#   is taken from cash.
# - LINES: data/totalled_lines.json has the Dave, Moose, Walt and Ferris keys
#   and the same line is never said twice in a row.
#   <godot> --headless --fixed-fps 120 --path . -s res://tests/core/totalled_run_end.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const RunEnd := preload("res://scripts/core/run_end.gd")
const TotalledMeter := preload("res://scripts/car/totalled_meter.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const ROOT := "user://test_totalled_run_end"

enum Step { BOOT, FREE, PAID, BAD_COPS, TOW, TEST_BUILD, LINES, DONE }

var failures: Array[String] = []
var game: Node
var step := Step.BOOT
var tick := 0
var t := 0
var hz := 120
var run_end: Node
var started: Array = []
var done: Array = []
var seen := {}
var night_before := 0
var bank_before := 0
var pause_menu: Node

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveStore.select_slot(1)
	game = Harness.boot(self, 0, 300.0, 78)

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

static func _coast(c: Vehicle) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.steering_input = 0.0
	c.handbrake_input = 0.0

func _settle() -> void:
	if game.game_state.state != GameState.State.PLAYING:
		game.game_state._set_state(GameState.State.PLAYING)

## A fresh RunEnd on the booted game, as game.gd wires its own, with the meter
## at `meter`, `cash` in the pocket. Its sensor is off: hits come from hit().
func _new_run_end(p: PlayerCar, cash: int, meter: float = 0.0) -> void:
	if run_end != null:
		run_end.queue_free()
	_settle()
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
	run_end.sensor.enabled = false
	started.clear()
	done.clear()
	seen.clear()
	run_end.totalled_started.connect(func(loss: int, free: bool) -> void: started.append([loss, free]))
	run_end.finished.connect(func(night: bool) -> void: done.append(night))
	night_before = game.night_clock.night
	bank_before = game.wallet.bank
	p.damage.garage_repair(null)
	p.damage.totalled = meter
	p.driver = _coast
	(game.camera as ChaseCamera).trauma = 0.0
	(game.camera as ChaseCamera).set_view(ChaseCamera.View.CHASE)
	t = 0

func _watch() -> void:
	var ph: int = run_end.phase
	if ph == RunEnd.Phase.DRIVING or seen.has(ph):
		return
	var s: Node = run_end.screen
	seen[ph] = {"cracked": s.is_cracked(), "black": s.is_black(), "line": s.line_text(), "card": s.card_texts()}

## Three hits of 0.30 and the checks that the car is still the player's.
func _three_hits(p: PlayerCar, label: String) -> void:
	var cash: int = game.wallet.cash
	for i in 3:
		var total: bool = run_end.hit(80.0, Node.new())
		_check(not total, "%s: hit %d does not total the car" % [label, i + 1])
		_check(run_end.phase == RunEnd.Phase.DRIVING, "%s: still driving after hit %d" % [label, i + 1])
		_check(game.wallet.cash == cash, "%s: no cash taken after hit %d" % [label, i + 1])
		_check(p.driver == _coast, "%s: the controls are never taken (hit %d)" % [label, i + 1])
		_check(not run_end.screen.is_black() and game.game_state.state == GameState.State.PLAYING, "%s: no cut, no state change (hit %d)" % [label, i + 1])
		_check((game.camera as ChaseCamera).trauma >= RunEnd.DAZE_TRAUMA - 0.001, "%s: the camera shakes on hit %d" % [label, i + 1])
		_check((game.camera as ChaseCamera).view == ChaseCamera.View.CHASE, "%s: the view is not taken either (hit %d)" % [label, i + 1])
	_check(is_equal_approx(p.damage.totalled, 0.9), "%s: three 0.30 hits are 0.90 (is %.3f)" % [label, p.damage.totalled])
	_check(TotalledMeter.stage(p.damage.totalled) == 3, "%s: that is stage 3" % label)
	_check(not run_end.screen.is_cracked(), "%s: 0.30 steps do not crack the glass" % label)

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
				print("car: %s" % PlayerCar.chassis_kind())
				_check(game.run_end != null and not game.run_end.sensor.enabled, "in a test the game's own sensor is off unless asked for")
				_new_run_end(p, 500)
				# the same object twice in one tick is one hit
				var wall := Node.new()
				run_end.hit(80.0, wall)
				run_end.hit(80.0, wall)
				_check(is_equal_approx(p.damage.totalled, 0.30), "the same object twice is one hit")
				_check(not run_end.hit(54.0, Node.new()) and is_equal_approx(p.damage.totalled, 0.30), "a 54 km/h hit adds nothing")
				_new_run_end(p, 500)
				_three_hits(p, "free")
				_check(run_end.hit(80.0, Node.new()), "the fourth hit totals the car")
				_check(run_end.phase == RunEnd.Phase.TOTALLED and run_end.ends_night, "the sequence begins, the night is ending")
				_check(started == [[0, true]], "it is the first total of the save: free")
				_check(is_equal_approx(p.damage.totalled, 0.0), "Walt's fix puts the meter back to 0")
				_check(game.wallet.cash == 500, "nothing was taken")
				step = Step.FREE
		Step.FREE:
			_watch()
			if not done.is_empty() or t > hz * 40:
				_check(done == [true] and game.night_clock.night == night_before + 1, "the night ended")
				var card := " ".join(seen.get(RunEnd.Phase.MORNING, {}).get("card", []))
				_check("Moose" in card and "Walt" in card, "the morning card has Moose and Walt")
				_check(SaveStore.first_wreck_used(), "the free total is used up")
				_check(game.wallet.cash == 0 and game.wallet.bank == bank_before + 500, "all of tonight's cash is banked at dawn")
				# paid
				_new_run_end(p, 500)
				_three_hits(p, "paid")
				_check(run_end.hit(80.0, Node.new()), "a fourth hit totals the car (paid)")
				_check(started == [[250, false]] and game.wallet.cash == 250, "half of tonight's cash is gone")
				_check(game.wallet.bank == bank_before, "the bank is untouched")
				_check(is_equal_approx(p.damage.totalled, 1.0), "no Walt: the meter stays at 1.0")
				step = Step.PAID
		Step.PAID:
			_watch()
			if not done.is_empty() or t > hz * 40:
				_check(done == [true] and game.night_clock.night == night_before + 1, "a paid total ends the night too")
				var card := " ".join(seen.get(RunEnd.Phase.MORNING, {}).get("card", []))
				_check("hook" in card and "$250" in card, "the morning says the tow and what was lost")
				_check(game.wallet.cash == 0 and game.wallet.bank == bank_before + 250, "the other half is banked at dawn")
				# bad cops
				_new_run_end(p, 400)
				run_end.bad_cops = true
				_three_hits(p, "bad cops")
				_check(run_end.hit(80.0, Node.new()), "a fourth hit totals the car (bad cops)")
				_check(started == [[400, false]] and game.wallet.cash == 0 and game.wallet.bank == bank_before, "bad cops take all of it, never the bank")
				step = Step.BAD_COPS
		Step.BAD_COPS:
			_watch()
			if run_end.phase >= RunEnd.Phase.LINE or t > hz * 12:
				_check(run_end.phase >= RunEnd.Phase.LINE, "the sequence reached the line")
				_check(seen.get(RunEnd.Phase.LINE, {}).get("line", "").begins_with(Dictionary(JSON.parse_string(FileAccess.get_file_as_string(RunEnd.LINES_PATH)))["Dave"]["bad_cops"][0]), "Dave says who took it")
				_new_run_end(p, 300)  # cuts the sequence short: only the settlement mattered here
				pause_menu = null
				for c in game.get_children():
					if c is PauseMenu:
						pause_menu = c
				_check(pause_menu != null, "the game has a pause menu")
				step = Step.TOW
		Step.TOW:
			if pause_menu != null:
				p.damage.totalled = 0.55
				_check(not pause_menu._tow_offered(), "no tow row at 0.55 on a healthy car")
				p.damage.totalled = 0.60
				_check(pause_menu._tow_offered(), "the tow row is offered at 0.60")
				SaveStore.chase_active = true
				_check(not pause_menu._tow_offered(), "no tow in a chase")
				SaveStore.chase_active = false
				var cash: int = game.wallet.cash
				var bank: int = game.wallet.bank
				var night: int = game.night_clock.night
				pause_menu._call_tow()
				_check(game.night_clock.night == night + 1, "the tow ends the night")
				_check(game.wallet.cash == 0 and game.wallet.bank == bank + cash, "no cash lost: tonight's cash is banked")
				_check(is_equal_approx(p.damage.totalled, 0.60), "the meter stays for the bill")
			t = 0
			step = Step.TEST_BUILD
		Step.TEST_BUILD:
			_test_build()
			step = Step.LINES
		Step.LINES:
			_lines()
			step = Step.DONE
		Step.DONE:
			if run_end != null:
				run_end.queue_free()
			return _end("")
	return false

## The test build's "Wrecks" row: Meter turns the game's sensor on; money is
## never taken there. The settings go to a scratch file (AudioSettings.path).
func _test_build() -> void:
	ProjectSettings.set_setting("neon/test_build", true)
	_check(GameSettings.test_build(), "the test build is on")
	GameSettings.reset_defaults()
	_check(GameSettings.wrecks_meter and GameSettings.wrecks_enabled(), "Meter is the default in the test build")
	GameSettings.set_wrecks_meter(false)
	_check(not GameSettings.wrecks_enabled(), "Off leaves the sensor off in the test build")
	GameSettings.set_wrecks_meter(true)
	GameSettings.save_settings()
	GameSettings.set_wrecks_meter(false)
	GameSettings.load_settings()
	_check(GameSettings.wrecks_meter, "the Wrecks choice is saved with the other game settings")
	# the game's own sensor follows the setting (a test would not turn it on by itself)
	OS.set_environment("NEON_WRECK", "")
	game.apply_wrecks_setting()
	# TestMode.active() is true here, so wrecks_on() stays off in a plain test:
	# NEON_WRECK=1 is the test switch. The setting itself is what is checked.
	OS.set_environment("NEON_WRECK", "1")
	game.apply_wrecks_setting()
	_check(game.run_end.sensor.enabled, "Wrecks = Meter: the game's sensor is on")
	# nothing is taken from cash in the test build
	var p: PlayerCar = game.get("player")
	_new_run_end(p, 500, 0.9)
	SaveStore.mark_first_wreck()
	_check(run_end.hit(80.0, Node.new()), "a hit totals the car in the test build")
	_check(started == [[0, false]] and game.wallet.cash == 500, "the test build takes nothing from cash")
	run_end.queue_free()
	run_end = null
	_settle()
	OS.set_environment("NEON_WRECK", "")
	ProjectSettings.set_setting("neon/test_build", false)
	_check(not GameSettings.test_build() and GameSettings.wrecks_enabled(), "outside the test build the sensor is always on")
	GameSettings.reset_defaults()

func _lines() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RunEnd.LINES_PATH))
	_check(parsed is Dictionary, "data/totalled_lines.json is a JSON object")
	if not parsed is Dictionary:
		return
	for who in ["Dave", "Moose", "Walt", "Ferris"]:
		_check(parsed.has(who), "the lines file has " + who)
	_check(parsed["Dave"].get("total", []).size() == 3, "Dave has 3 total lines")
	_check(parsed["Dave"].get("bad_cops", []).size() == 1, "Dave has 1 bad-cop line")
	_check(parsed["Moose"].get("first_total_morning", []).size() == 1 and parsed["Walt"].get("first_total_morning", []).size() == 1, "the first-total morning has a Moose line and a Walt line")
	_check(parsed["Ferris"].get("morning", []).size() == 1, "one ordinary morning line")
	var r := RunEnd.new()
	var last := ""
	var repeats := 0
	for i in 40:
		var l: String = r._pick("Dave", "total")
		if l == last:
			repeats += 1
		last = l
	_check(repeats == 0, "the same line is never said twice in a row (%d repeats)" % repeats)
	r.free()

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	print("totalled_run_end: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
