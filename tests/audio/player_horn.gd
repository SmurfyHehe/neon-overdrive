extends SceneTree

# The player's horn on J (key map K2), headless:
# - the action `horn` exists and is on J, bound by position
# - J down: a stream is playing within one frame; J up: it stops once the tail
#   has run out, not before
# - a held horn is a looping take (it does not run out)
# - the horn goes by the car: three cars against the table, and a badly
#   damaged car is sour
# - player_horn says "toot" for a tap, "hey" for a second tap within 0.4 s,
#   "lean" for a hold over 1 s (and no "toot" when that hold ends)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/player_horn.gd

const CARS := {"p4_kei": "beep", "p1_coupe": "sharp", "p17_work_pickup": "blare", "p0_beater": "sour", "p3_tuner": "sharp", "n1_commuter": "two_tone", "no_such_car": "two_tone"}

var failures: Array[String] = []
var heard: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

## A stand-in for the car: all PlayerHorn reads from its parent is `damage`.
class FakeCar extends Node3D:
	var damage := CarDamage.new()

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait(secs: float) -> void:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame

func _tap() -> void:
	Input.action_press(&"horn")
	await _frames(2)
	Input.action_release(&"horn")

func _run() -> void:
	KeyBindings.ensure_defaults()
	KeyBindings.reset_defaults()
	# the key
	_check(InputMap.has_action(&"horn"), "there is no horn action")
	_check(KeyBindings.keys(&"horn").size() == 1 and KeyBindings.keys(&"horn")[0] == KEY_J, "horn is not on J: %s" % [KeyBindings.keys(&"horn")])
	for ev in InputMap.action_get_events(&"horn"):
		if ev is InputEventKey:
			_check(ev.physical_keycode == KEY_J and ev.keycode == 0, "horn is bound by letter, not by position")
	# the table
	for kind in CARS:
		_check(TrafficHorns.horn_for(kind) == CARS[kind], "%s should sound %s, sounds %s" % [kind, CARS[kind], TrafficHorns.horn_for(kind)])
	_check(TrafficHorns.horn_for("p1_coupe", true) == "sour", "a sour coupe is not sour")
	# three cars, each with its own horn node
	var listener := Camera3D.new()
	root.add_child(listener)
	listener.make_current()
	var horns := {}
	var cars := {}
	for kind in ["p1_coupe", "p4_kei", "p17_work_pickup"]:
		var car := FakeCar.new()
		root.add_child(car)
		var h := PlayerHorn.new()
		h.kind = kind
		h.set_process(false)
		car.add_child(h)
		horns[kind] = h
		cars[kind] = car
		_check(h.horn_name() == CARS[kind], "%s: its horn node says %s" % [kind, h.horn_name()])
	var t0 := Time.get_ticks_msec()
	while not TrafficHorns.ready() and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	_check(TrafficHorns.ready(), "the horns were never built")
	print("player_horn: horns built in %d ms" % (Time.get_ticks_msec() - t0))
	var horn: PlayerHorn = horns["p1_coupe"]
	var voice := horn.get_node(^"HornVoice") as Sound3D
	horn.set_process(true)
	horn.player_horn.connect(func(p: String) -> void: heard.append(p))
	await _frames(2)
	_check(not voice.playing and not horn.is_sounding(), "the horn sounds before J is pressed")

	# tap: sounds within a frame, stops after the tail
	Input.action_press(&"horn")
	await _frames(1)
	_check(voice.playing and horn.is_sounding(), "J down: nothing is playing one frame later")
	_check(horn.horn == "sharp", "the coupe sounded %s" % horn.horn)
	_check(voice.stream == TrafficHorns.hold_stream("sharp"), "the coupe is not playing the sharp take")
	_check(PlayerGain.target(voice) == &"Traffic", "the horn is on the %s bus" % PlayerGain.target(voice))
	var take := voice.stream as AudioStreamWAV
	_check(take != null and take.loop_mode == AudioStreamWAV.LOOP_FORWARD and take.loop_begin > 0, "the held take does not loop")
	await _frames(1)
	Input.action_release(&"horn")
	var up := Time.get_ticks_msec()
	await _frames(1)
	_check(voice.playing, "a tap was cut off the moment J came up (no tail)")
	while voice.playing and Time.get_ticks_msec() - up < 2000:
		await process_frame
	var took := (Time.get_ticks_msec() - up) / 1000.0
	_check(not voice.playing and not horn.is_sounding(), "the horn is still sounding 2 s after J came up")
	_check(took < PlayerHorn.TAP_S + PlayerHorn.TAIL_S + 0.25, "the tap rang on for %.2f s" % took)
	_check(heard == ["toot"], "a tap said %s, wanted [toot]" % [heard])

	# two taps within 0.4 s
	await _wait(0.8)
	heard.clear()
	await _tap()
	await _wait(0.15)
	await _tap()
	await _frames(2)
	_check(heard == ["toot", "hey"], "two quick taps said %s, wanted [toot, hey]" % [heard])
	# two taps too far apart are two toots
	await _wait(0.8)
	heard.clear()
	await _tap()
	await _wait(0.7)
	await _tap()
	await _frames(2)
	_check(heard == ["toot", "toot"], "two slow taps said %s, wanted [toot, toot]" % [heard])

	# hold: still sounding well past the take's own length, "lean" once
	await _wait(0.8)
	heard.clear()
	Input.action_press(&"horn")
	await _wait(TrafficHorns.HOLD_HEAD_S + TrafficHorns.HOLD_LOOP_S + 0.6)
	_check(voice.playing, "a held horn ran out")
	_check(heard == ["lean"], "a long hold said %s, wanted [lean]" % [heard])
	Input.action_release(&"horn")
	await _frames(1)
	_check(voice.playing, "a held horn was cut off the moment J came up (no tail)")
	await _wait(PlayerHorn.TAIL_S + 0.2)
	_check(not voice.playing, "a held horn is still sounding after its tail")
	_check(heard == ["lean"], "after the hold ended it said %s, wanted [lean]" % [heard])

	# the other two cars, and a wrecked body
	horn.set_process(false)
	for kind in ["p4_kei", "p17_work_pickup"]:
		var h: PlayerHorn = horns[kind]
		h.set_process(true)
		Input.action_press(&"horn")
		await _frames(1)
		var v := h.get_node(^"HornVoice") as Sound3D
		_check(v.playing and h.horn == CARS[kind] and v.stream == TrafficHorns.hold_stream(CARS[kind]), "%s played %s" % [kind, h.horn])
		Input.action_release(&"horn")
		await _wait(0.5)
		_check(not v.playing, "%s: still sounding after J came up" % kind)
		h.set_process(false)
	(cars["p4_kei"] as FakeCar).damage.parts[CarDamage.Part.BODY] = 0.8
	_check((horns["p4_kei"] as PlayerHorn).horn_name() == "sour", "a badly damaged kei still sounds %s" % (horns["p4_kei"] as PlayerHorn).horn_name())

	for kind in cars:
		(cars[kind] as Node).queue_free()
	listener.queue_free()
	await _frames(2)
	print("player_horn: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
