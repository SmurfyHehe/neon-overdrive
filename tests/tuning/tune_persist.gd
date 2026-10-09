extends SceneTree

# The player's tune survives a reset and a relaunch (2026-10-07, Roy: a reset
# threw away the tune he had made). GameState.restart() reloads the whole
# scene, so this boots Game.tscn, tunes the car, frees the game (what a reload
# or a quit does) and boots it again.
#
# Asserts (exit code 1 on failure):
# - the tune is written while driving, before any reset (the 1 s check)
# - after the reboot the car's spec AND the live car carry the tune: the Grip
#   preset plus one hand-moved setting
# - the Tuner header reads "Grip (modified)", not "Stock"
# - the exhaust tune (its own save file) comes back too
# - picking Stock goes back to stock and stays stock after another reboot
# - a car built from a given spec (test track, Auto-Tune worker) ignores the
#   saved tune
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tuning/tune_persist.gd

const PlayerTune := preload("res://scripts/car/player_tune.gd")
const ARB := "rear_arb_ratio"

var game: Node
var phase := 0
var wait := 0
var fails: Array[String] = []
var expected := {}
var exhaust_loud := 0.0

func _initialize() -> void:
	PlayerTune.path = "user://test_tune_persist.json"
	PlayerTune.enabled = true
	ExhaustTune.save_path = "user://test_tune_persist_exhaust.json"
	# Start from stock: overwrite whatever an earlier run left (never deleted).
	PlayerTune.save(CarSpec.coupe_default())
	ExhaustTune.save_car(EngineAudio.START_PRESET, ExhaustTune.for_car(EngineAudio.START_PRESET).to_dict())
	_boot()

func _boot() -> void:
	if game != null:
		# Gone before the new one is built, as reload_current_scene() does; its
		# player's _exit_tree saves the tune.
		root.remove_child(game)
		game.free()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)
	wait = 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _tuner_model() -> TunerModel:
	var stack: Array[Node] = [game]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var m: Variant = n.get("model")
		if m is TunerModel:
			return m
		stack.append_array(n.get_children())
	return null

func _differs(spec: Dictionary, want: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for p in want:
		if absf(TuneParams.get_value(spec, p) - float(want[p])) > 0.0005:
			out.append("%s %.4f, want %.4f" % [p, TuneParams.get_value(spec, p), want[p]])
	return out

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	wait += 1
	if wait < 10:
		return false
	var p: PlayerCar = game.get("player")
	match phase:
		0:
			# Tune the live car the way the Tuner does: Grip, then the rear bar by hand.
			var model := TunerModel.new(p, p.spec, CarSpec.coupe_default())
			model.apply_preset("Grip")
			CarSpec.set_param(p, p.spec, ARB, TuneParams.get_value(p.spec, ARB) + 0.07)
			# Roy's named settings, set by hand so each is checked on its own:
			# camber, pressure, toe and the Semi-slick compound.
			CarSpec.set_param(p, p.spec, "front_static_camber", -2.75)
			CarSpec.set_param(p, p.spec, "rear_tyre_pressure", 2.45)
			CarSpec.set_param(p, p.spec, "front_toe", -0.008)
			var semi: Dictionary = model.choice_values("compound", 2)
			for path in semi:
				CarSpec.set_param(p, p.spec, path, semi[path])
			exhaust_loud = 0.83
			CarSpec.set_param(p, p.spec, "exhaust/loudness", exhaust_loud)
			expected = PlayerTune.values_from(p.spec)
			phase = 1
			wait = 0
		1:
			# 1.5 s of driving: the periodic check must have saved it by now.
			if wait < 10 + 180:
				return false
			var on_disk := PlayerTune.load_values()
			var d := _differs(_spec_from(on_disk), expected) if not on_disk.is_empty() else ["nothing saved"]
			if not d.is_empty():
				_fail("tune not saved while driving: %s" % ", ".join(d.slice(0, 3)))
			phase = 2
			_boot()
		2:
			var d := _differs(p.spec, expected)
			if not d.is_empty():
				_fail("spec after reset: %s" % ", ".join(d.slice(0, 3)))
			if absf(float(p.get(ARB)) - float(expected[ARB])) > 0.0005:
				_fail("live car %s is %.4f, want %.4f" % [ARB, p.get(ARB), expected[ARB]])
			var m := _tuner_model()
			var label := m.preset_label() if m != null else "(no Tuner screen)"
			print("after reset: %d values match, Tuner reads \"%s\"" % [expected.size() - d.size(), label])
			if label != "Grip (modified)":
				_fail("Tuner reads \"%s\", want \"Grip (modified)\"" % label)
			var loud := TuneParams.get_value(p.spec, "exhaust/loudness")
			if absf(loud - exhaust_loud) > 0.001:
				_fail("exhaust loudness after reset %.3f, want %.3f" % [loud, exhaust_loud])
			# Back to stock through the Tuner's preset.
			var model := TunerModel.new(p, p.spec, CarSpec.coupe_default())
			model.apply_preset("Stock")
			expected = PlayerTune.values_from(p.spec)
			phase = 3
			_boot()
		3:
			var d := _differs(p.spec, PlayerTune.values_from(CarSpec.coupe_default()))
			if not d.is_empty():
				_fail("not stock after picking Stock and resetting: %s" % ", ".join(d.slice(0, 3)))
			var m := _tuner_model()
			var label := m.preset_label() if m != null else "(no Tuner screen)"
			print("after Stock + reset: Tuner reads \"%s\"" % label)
			if label != "Stock":
				_fail("Tuner reads \"%s\", want \"Stock\"" % label)
			# A car given its own spec keeps it, whatever is saved.
			PlayerTune.save(_spec_from({ARB: 0.9}))
			var own := PlayerCar.new()
			own.sim_only = true
			own.spec = CarSpec.coupe_default()
			root.add_child(own)
			if absf(TuneParams.get_value(own.spec, ARB) - TuneParams.get_value(CarSpec.coupe_default(), ARB)) > 0.0005:
				_fail("a car built from a given spec picked up the saved tune")
			own.queue_free()
			PlayerTune.save(CarSpec.coupe_default())
			print("tune_persist: %s" % ("PASS" if fails.is_empty() else "%d failure(s)" % fails.size()))
			quit(0 if fails.is_empty() else 1)
			return true
	return false

func _spec_from(values: Dictionary) -> Dictionary:
	var s := CarSpec.coupe_default()
	for k in values:
		TuneParams.set_value(s, k, float(values[k]))
	return s
