extends SceneTree

# Anti-lag is turbo-only and on by default (exhaust sound option A, 2026-10-07),
# headless and silent:
# - a car preset has the switch on
# - a naturally aspirated car (turbo_boost_max 0): the synth sees anti-lag off,
#   and the Tuner's Exhaust switch is greyed out
# - give the car a turbo: the synth sees it on, the switch is live
# - turn the switch off on the turbo car: the synth sees it off
# - ExhaustTune.anti_lag_live() (also used by the traffic flame sim) agrees
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/anti_lag_turbo.gd

const TIMEOUT_TICKS := 60 * 20

var tick := 0
var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	if not p.is_ready:
		return tick > TIMEOUT_TICKS and _end("player car never became ready")
	var audio: EngineAudio = null
	for c in p.get_children():
		if c is EngineAudio:
			audio = c
	if audio == null:
		return _end("no EngineAudio on the player car")
	_run(p, audio)
	return _end("")

func _run(p: PlayerCar, audio: EngineAudio) -> void:
	_check(ExhaustTune.for_car("p1_coupe").anti_lag >= 0.5, "the car preset should have anti-lag on")

	var panel := ExhaustPanel.new(p)
	root.add_child(panel)

	# Naturally aspirated: switch on in the spec, off in the synth, greyed in the Tuner.
	CarSpec.set_param(p, p.spec, "turbo_boost_max", 0.0)
	CarSpec.set_param(p, p.spec, "exhaust/anti_lag", 1.0)
	audio.sync_tune()
	panel.refresh()
	print("NA: spec switch %.0f, synth %.0f, toggle disabled %s" % [p.spec.exhaust.anti_lag, audio.synth.tune.anti_lag, panel.anti_lag_check.disabled])
	_check(audio.synth.tune.anti_lag < 0.5, "NA car: the synth should see anti-lag off")
	_check(panel.anti_lag_check.disabled, "NA car: the anti-lag switch should be greyed out")
	_check(not ExhaustTune.anti_lag_live(p.spec), "NA car: anti_lag_live should be false")

	# Turbo: on by default, live switch.
	CarSpec.set_param(p, p.spec, "turbo_boost_max", 1.0)
	audio.sync_tune()
	panel.refresh()
	print("turbo: synth %.0f, toggle disabled %s, pressed %s" % [audio.synth.tune.anti_lag, panel.anti_lag_check.disabled, panel.anti_lag_check.button_pressed])
	_check(audio.synth.tune.anti_lag >= 0.5, "turbo car: the synth should see anti-lag on")
	_check(not panel.anti_lag_check.disabled, "turbo car: the anti-lag switch should be live")
	_check(panel.anti_lag_check.button_pressed, "turbo car: the anti-lag switch should show on")
	_check(ExhaustTune.anti_lag_live(p.spec), "turbo car: anti_lag_live should be true")

	# Turbo, switch flipped off in the Tuner.
	panel.anti_lag_check.button_pressed = false
	print("turbo, switch off: spec %.0f, synth %.0f" % [p.spec.exhaust.anti_lag, audio.synth.tune.anti_lag])
	_check(p.spec.exhaust.anti_lag < 0.5, "switching off should write the spec")
	_check(audio.synth.tune.anti_lag < 0.5, "turbo car, switch off: the synth should see anti-lag off")
	_check(not ExhaustTune.anti_lag_live(p.spec), "switch off: anti_lag_live should be false")
	panel.queue_free()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(fatal: String) -> bool:
	if fatal != "":
		failures.append(fatal)
	if failures.is_empty():
		print("PASS anti_lag_turbo")
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		quit(1)
	return true
