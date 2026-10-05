extends SceneTree

# Turbo test (Phase B, 2026-10-05), headless and silent:
# - naturally aspirated (turbo_boost_max 0): boost stays 0
# - with boost: it lags (small after 0.1 s, large after ~3 s), then falls when the
#   throttle lifts, and exactly one blow-off fires
# - the boost speeds the car up (0-100 faster on TuneTrack) and the default car is
#   unchanged
# - EngineSynth: the whistle and the blow-off add sound only when asked
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/turbo.gd

const TIMEOUT_TICKS := 60 * 40

enum Step { BOOT, NA, SPOOL, LIFT, TRACK, SYNTH, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var early := -1.0
var blow_offs_before := 0

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(is_zero_approx(p.turbo_boost_max), "the default car should be naturally aspirated")
			throttle = 1.0
			_go(Step.NA)
		Step.NA:
			if waited >= 120:
				_check(is_zero_approx(p.boost), "boost should stay 0 without a turbo, is %.2f" % p.boost)
				p.turbo_boost_max = 1.0
				p.boost = 0.0
				_go(Step.SPOOL)
		Step.SPOOL:
			if waited == 6:
				early = p.boost
			if waited >= 240:
				_check(early < 0.3, "boost should lag: %.2f after 0.1 s" % early)
				_check(p.boost > 0.5, "boost should have spooled after 4 s at full throttle, is %.2f" % p.boost)
				blow_offs_before = p.blow_off_count
				throttle = 0.0
				_go(Step.LIFT)
		Step.LIFT:
			if waited >= 90:
				_check(p.boost < 0.3, "boost should fall after lifting, is %.2f" % p.boost)
				_check(p.blow_off_count - blow_offs_before == 1, "lift should fire one blow-off, fired %d" % (p.blow_off_count - blow_offs_before))
				_go(Step.TRACK)
				_track()
	return false

func _track() -> void:
	var track := TuneTrack.new()
	root.add_child(track)
	await process_frame
	var na := CarSpec.coupe_default()
	var boosted := CarSpec.coupe_default()
	boosted["turbo_boost_max"] = 1.0
	var res: Array = await track.evaluate([na, boosted])
	var t_na: float = res[0].t_0_100
	var t_turbo: float = res[1].t_0_100
	print("0-100: NA %.2f s, turbo %.2f s" % [t_na, t_turbo])
	_check(t_turbo < t_na * 0.97, "turbo should be faster (%.2f vs %.2f)" % [t_turbo, t_na])
	_synth()

func _synth() -> void:
	var quiet := _render(0.0, false)
	var whistle := _render(1.0, false)
	var vent := _render(0.0, true)
	print("synth rms: quiet %.4f whistle %.4f vent %.4f" % [quiet, whistle, vent])
	_check(whistle > quiet * 1.02, "the whistle should add sound")
	_check(vent > quiet * 1.02, "the blow-off should add sound")
	_end("")

func _render(boost: float, vent: bool) -> float:
	var s := EngineSynth.new()
	s.tune = ExhaustTune.new(0.5, 0.3, 0.0, 0.0)
	s.boost = boost
	if vent:
		s.blow_off(1.0)
	var sum := 0.0
	var n := 0
	for i in 4:
		for f in s.render(512, 4000.0, 0.6, false):
			sum += f.x * f.x
			n += 1
	return sqrt(sum / n)

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("turbo: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
