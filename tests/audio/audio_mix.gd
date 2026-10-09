extends SceneTree

# The whole-game audio mix (2026-10-09), headless and silent: it sweeps the camera
# view x radio use x window position x head direction in the real game and reads
# back what is on the audio buses (low-pass cutoffs, panners, volumes), never sound.
#
# - outside sources (Engine, Tires, World, Traffic, Sirens): open and at the slider
#   level in the chase view whatever the window; in the cockpit muffled and quieter
#   with the window up, opening steadily as it goes down
# - inside sources (Music, Scanner): clearer and louder in the cockpit; from the
#   chase cam brighter and louder with the window open (the stereo leaks out)
# - the radio (off, on, a station change, its volume slider) never moves another
#   bus, and its slider moves the Music bus by exactly its own dB; an open scanner
#   squelch ducks the music and nothing else
# - the head: in the cockpit, turning left puts the radio in the right ear, looking
#   back darkens it; the open driver's window pulls the wind left; the chase view
#   is centred
# - window_openness() is the one window value
# - buffeting: none with the window up or in the chase view, growing with the
#   window and with speed
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/audio_mix.gd

const TIMEOUT_TICKS := 60 * 60
const VIEWS := [0.0, 1.0]
const WINDOWS := [0.0, 0.25, 0.5, 1.0]
const RADIO := ["off", "on", "quiet", "scanner"]
const YAWS := [0.0, 90.0, -90.0, 180.0]
const SETTLE := 3   # ticks per combination
const ALL_BUSES: Array[StringName] = [&"Engine", &"Tires", &"World", &"Traffic", &"Sirens", &"Music", &"Scanner"]

var tick := 0
var failures: Array[String] = []
var persp: PerspectiveAudio
var radio: RadioManager
var car: CarAudio
var combos: Array = []
var combo := -1
var wait := 0
var recorded := true
var results := {}   # key -> bus -> {hz, db, pan}
var buffeting := {}
var buff_plan: Array = []
var buff_i := -1
var phase := "boot"
var frames := 0    # rendered frames, where the mix is applied
var frames_at_set := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	AudioSettings.path = "user://audio_mix_test.cfg"
	for v in VIEWS:
		for w in WINDOWS:
			for r in RADIO:
				for y in YAWS:
					combos.append([v, w, r, y])
	# [view, window, speed]
	buff_plan = [[1.0, 0.0, 40.0], [1.0, 0.25, 40.0], [1.0, 0.5, 40.0], [1.0, 1.0, 40.0],
			[1.0, 0.5, 15.0], [1.0, 0.5, 60.0], [0.0, 1.0, 60.0]]
	change_scene_to_file("res://Game.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	return false

## Waited out SETTLE ticks and at least two mix updates since the last change.
func _settled() -> bool:
	if wait > 0:
		wait -= 1
	return wait == 0 and frames - frames_at_set >= 2

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("camera") == null or game.get("radio") == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick > TIMEOUT_TICKS:
		return _end("timed out in phase " + phase)
	match phase:
		"boot":
			persp = (game.camera as ChaseCamera).perspective
			# the test drives the view, window and head itself
			(game.camera as Node).set_physics_process(false)
			radio = game.radio
			for c in (game.player as Node).get_children():
				if c is CarAudio:
					car = c
			_check(persp != null and radio != null and car != null, "missing PerspectiveAudio, RadioManager or CarAudio")
			if persp != null:
				persp.car_audio = car   # the camera hands it over on its tick, which is off
			for b in ALL_BUSES:
				_check(AudioServer.get_bus_index(b) >= 0, "no %s bus" % b)
				_check(_lp(b) > 0.0, "no low-pass on the %s bus" % b)
			for b in PerspectiveAudio.PANNED_BUSES:
				_check(_has_panner(b), "no panner on the %s bus" % b)
			if not failures.is_empty():
				return _end("")
			phase = "sweep"
		"sweep":
			if combo >= 0 and not recorded:
				if not _settled():
					return false
				_record(combos[combo])
				recorded = true
			combo += 1
			if combo >= combos.size():
				_assert_sweep()
				_print_table()
				phase = "buffeting"
				return false
			_apply_state(combos[combo])
			wait = SETTLE
			recorded = false
		"buffeting":
			if buff_i >= 0 and not recorded:
				if not _settled():
					return false
				buffeting[buff_i] = car.buffeting_level
				recorded = true
			buff_i += 1
			if buff_i >= buff_plan.size():
				_assert_buffeting()
				return _end("")
			var b: Array = buff_plan[buff_i]
			_apply_state([b[0], b[1], "off", 0.0])
			car.forced = {"speed": b[2], "on_road": 1.0}
			wait = 90   # 1.5 s for the level to settle
			recorded = false
	return false

func _apply_state(c: Array) -> void:
	frames_at_set = frames
	persp.target = c[0]
	persp.blend = c[0]
	persp.window = c[1]
	persp.head_yaw_deg = c[3]
	var want_station := -1 if c[2] == "off" else 0
	var guard := 0
	while radio.station != want_station and guard < 10:
		radio.next_station()
		guard += 1
	AudioSettings.set_volume("Music", 0.3 if c[2] == "quiet" else 1.0)
	persp.scanner_open = c[2] == "scanner"
	persp.scanner_duck = 1.0 if c[2] == "scanner" else 0.0

func _key(c: Array) -> String:
	return "%s|%s|%s|%s" % [c[0], c[1], c[2], c[3]]

func _record(c: Array) -> void:
	_check(is_equal_approx(PerspectiveAudio.window_openness(), c[1]), "window_openness() %.2f should be the window %.2f" % [PerspectiveAudio.window_openness(), c[1]])
	var row := {}
	for b in ALL_BUSES:
		var i := AudioServer.get_bus_index(b)
		row[b] = {
			"hz": _lp(b),
			"db": AudioServer.get_bus_volume_db(i) - AudioSettings.volume_db_for(AudioSettings.channel_of(b)),
			"abs_db": AudioServer.get_bus_volume_db(i),
			"pan": _pan(b),
		}
	results[_key(c)] = row

func _r(v: float, w: float, radio_state: String, y: float) -> Dictionary:
	return results[_key([v, w, radio_state, y])]

func _assert_sweep() -> void:
	for c in combos:
		var row: Dictionary = results[_key(c)]
		var v: float = c[0]
		var w: float = c[1]
		var y: float = c[3]
		# the live buses match the mix table
		var want := PerspectiveAudio.mix(v, w, y, 1.0 if c[2] == "scanner" else 0.0)
		for b in ALL_BUSES:
			_check(absf(row[b].hz - want[b].hz) < 1.0, "%s %s: cutoff %.0f, mix says %.0f" % [_key(c), b, row[b].hz, want[b].hz])
			_check(absf(row[b].db - want[b].db) < 0.05, "%s %s: offset %.2f dB, mix says %.2f" % [_key(c), b, row[b].db, want[b].db])
		# the radio never moves an outside bus
		var ref := _r(v, w, "off", y)
		for b in PerspectiveAudio.OUTSIDE_BUSES:
			_check(absf(row[b].hz - ref[b].hz) < 0.5 and absf(row[b].abs_db - ref[b].abs_db) < 0.01 and absf(row[b].pan - ref[b].pan) < 0.001,
					"%s: the radio moved the %s bus" % [_key(c), b])
	for w in WINDOWS:
		for y in YAWS:
			var chase := _r(0.0, w, "off", y)
			var cock := _r(1.0, w, "off", y)
			for b in PerspectiveAudio.OUTSIDE_BUSES:
				# chase view: open and at the slider, whatever the window
				_check(chase[b].hz > PerspectiveAudio.OPEN_HZ - 1.0 and absf(chase[b].db) < 0.01, "chase w=%.2f: %s should be open (%.0f Hz, %.1f dB)" % [w, b, chase[b].hz, chase[b].db])
				_check(cock[b].hz < chase[b].hz, "cockpit w=%.2f: %s should be muffled" % [w, b])
			for b in PerspectiveAudio.INSIDE_BUSES:
				if y == 0.0:
					_check(cock[b].hz > chase[b].hz and cock[b].db > chase[b].db + 1.0, "w=%.2f: %s should be clearer and louder inside (%.0f/%.1f vs %.0f/%.1f)" % [w, b, cock[b].hz, cock[b].db, chase[b].hz, chase[b].db])
			# radio slider: the Music bus moves by exactly the slider's dB
			var quiet := _r(1.0, w, "quiet", y)
			_check(absf((cock[&"Music"].abs_db - quiet[&"Music"].abs_db) - (0.0 - linear_to_db(0.3))) < 0.05, "w=%.2f: the radio slider should move Music by its own dB only" % w)
			_check(absf(cock[&"Music"].hz - quiet[&"Music"].hz) < 0.5, "w=%.2f: the radio slider should not move the Music filter" % w)
			# scanner squelch ducks the music
			var scan := _r(1.0, w, "scanner", y)
			_check(absf(scan[&"Music"].db - cock[&"Music"].db - PerspectiveAudio.SCANNER_DUCK_DB) < 0.05, "w=%.2f: an open scanner should duck the music by %.0f dB" % [w, PerspectiveAudio.SCANNER_DUCK_DB])
	# window: each step down opens the cockpit further and quietens it less
	for i in WINDOWS.size() - 1:
		var a := _r(1.0, WINDOWS[i], "on", 0.0)
		var b2 := _r(1.0, WINDOWS[i + 1], "on", 0.0)
		for b in PerspectiveAudio.OUTSIDE_BUSES:
			_check(b2[b].hz > a[b].hz, "%s: the cutoff should rise as the window goes from %.2f to %.2f" % [b, WINDOWS[i], WINDOWS[i + 1]])
			_check(b2[b].db >= a[b].db, "%s: the cabin offset should not drop as the window opens" % b)
		var ca := _r(0.0, WINDOWS[i], "on", 0.0)
		var cb := _r(0.0, WINDOWS[i + 1], "on", 0.0)
		_check(cb[&"Music"].hz > ca[&"Music"].hz and cb[&"Music"].db > ca[&"Music"].db, "chase: the stereo should leak out more as the window opens")
	var closed := _r(1.0, 0.0, "on", 0.0)
	for b in PerspectiveAudio.OUTSIDE_BUSES:
		_check(absf(closed[b].hz - PerspectiveAudio.COCKPIT_HZ[b]) < 1.0, "cockpit closed: %s cutoff should be %.0f" % [b, PerspectiveAudio.COCKPIT_HZ[b]])
	_check(_r(1.0, 1.0, "on", 0.0)[&"Engine"].hz > 10000.0, "cockpit open: the engine should be nearly outside-bright")
	# head direction
	_check(_r(1.0, 0.0, "on", 90.0)[&"Music"].pan > 0.3, "head left: the radio should be in the right ear")
	_check(_r(1.0, 0.0, "on", -90.0)[&"Music"].pan < -0.3, "head right: the radio should be in the left ear")
	_check(absf(_r(1.0, 0.0, "on", 0.0)[&"Music"].pan) < 0.01, "facing ahead: the radio should be centred")
	_check(_r(1.0, 0.0, "on", 180.0)[&"Music"].hz < closed[&"Music"].hz - 1000.0, "looking back should darken the radio")
	_check(_r(1.0, 1.0, "on", 0.0)[&"World"].pan < -0.2, "window down: the wind should come from the left")
	_check(absf(_r(1.0, 0.0, "on", 0.0)[&"World"].pan) < 0.01, "window up: the wind should be centred")
	for y in YAWS:
		for b in PerspectiveAudio.PANNED_BUSES:
			_check(absf(_r(0.0, 1.0, "on", y)[b].pan) < 0.01, "chase view: %s should be centred" % b)

func _assert_buffeting() -> void:
	print("buffeting: closed %.2f, 25%% %.2f, 50%% %.2f, open %.2f at 40 m/s; 50%% at 15 m/s %.2f, at 60 m/s %.2f; chase open 60 m/s %.2f"
			% [buffeting[0], buffeting[1], buffeting[2], buffeting[3], buffeting[4], buffeting[5], buffeting[6]])
	_check(buffeting[0] < 0.01, "no buffeting with the window up")
	_check(buffeting[1] > 0.05 and buffeting[2] > buffeting[1] and buffeting[3] > buffeting[2], "buffeting should grow as the window opens")
	_check(buffeting[4] < buffeting[2] and buffeting[5] > buffeting[2], "buffeting should grow with speed")
	_check(buffeting[6] < 0.01, "no cabin buffeting in the chase view")

func _print_table() -> void:
	print("mix (offset dB / cutoff Hz), radio on, facing ahead:")
	for v in VIEWS:
		for w in [0.0, 0.5, 1.0]:
			var row := _r(v, w, "on", 0.0)
			var line := "%-7s window %3d%%:" % ["cockpit" if v == 1.0 else "chase", int(w * 100)]
			for b in ALL_BUSES:
				line += "  %s %+.1f/%.0f" % [b, row[b].db, row[b].hz]
			print(line)

func _lp(bus_name: StringName) -> float:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return -1.0
	for k in AudioServer.get_bus_effect_count(i):
		var e := AudioServer.get_bus_effect(i, k)
		if e is AudioEffectLowPassFilter and AudioServer.is_bus_effect_enabled(i, k):
			return e.cutoff_hz
	return -1.0

func _has_panner(bus_name: StringName) -> bool:
	var i := AudioServer.get_bus_index(bus_name)
	for k in AudioServer.get_bus_effect_count(i):
		if AudioServer.get_bus_effect(i, k) is AudioEffectPanner:
			return true
	return false

func _pan(bus_name: StringName) -> float:
	var i := AudioServer.get_bus_index(bus_name)
	for k in AudioServer.get_bus_effect_count(i):
		var e := AudioServer.get_bus_effect(i, k)
		if e is AudioEffectPanner:
			return e.pan
	return 0.0

func _check(ok: bool, msg: String) -> void:
	if not ok and failures.size() < 40:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	AudioSettings.set_volume("Music", 1.0)
	print("audio_mix: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
