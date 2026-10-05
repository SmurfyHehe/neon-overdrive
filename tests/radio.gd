extends SceneTree

# Radio test (Phase B, 2026-10-05), headless and silent (state and numbers only):
# - the sequencer: every station renders the same samples for the same position,
#   is audible (RMS 0.03-0.5), never clips or goes non-finite, the stations differ
#   from each other, and rendering is cheap (under 25 percent of real time)
# - the manager in the real game: N cycles the stations then off, a switch starts
#   static and a toast, every station clock keeps running while another is tuned,
#   tuning in lands where that clock says, the tuned station's cursor advances, the
#   Music bus has the speaker low-pass, and pausing mutes the Music bus
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/radio.gd

const TIMEOUT_TICKS := 60 * 40

enum Step { BOOT, CYCLE, RUN, RETUNE, PAUSE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var radio: RadioManager
var t_station0 := 0.0
var cursor_before := 0

func _initialize() -> void:
	_sequencer_tests()
	change_scene_to_file("res://Game.tscn")

func _sequencer_tests() -> void:
	var seq := RadioSequencer.new()
	var firsts := []
	for s in RadioSequencer.station_count():
		var a := seq.render(s, 400000, 4096)
		var b := seq.render(s, 400000, 4096)
		var same := true
		var sum := 0.0
		var peak := 0.0
		for i in a.size():
			if a[i] != b[i]:
				same = false
			if not is_finite(a[i].x):
				_check(false, "station %d has a non-finite sample" % s)
				break
			sum += a[i].x * a[i].x
			peak = maxf(peak, absf(a[i].x))
		var rms := sqrt(sum / a.size())
		_check(same, "station %d is not deterministic" % s)
		_check(rms > 0.03 and rms < 0.5, "station %d RMS %.3f outside 0.03-0.5" % [s, rms])
		_check(peak < 1.0, "station %d peaks at %.2f" % [s, peak])
		firsts.append(a)
	for i in firsts.size():
		for j in range(i + 1, firsts.size()):
			var diff := 0.0
			for k in 4096:
				diff += absf(firsts[i][k].x - firsts[j][k].x)
			_check(diff / 4096.0 > 0.02, "stations %d and %d sound the same" % [i, j])
	var t0 := Time.get_ticks_usec()
	var secs := 8.0
	var start := 0
	while start < int(secs * RadioSequencer.MIX_RATE):
		seq.render(0, start, 2048)
		start += 2048
	var cost := float(Time.get_ticks_usec() - t0) / 1e6 / secs
	print("sequencer cost: %.1f%% of real time" % (cost * 100.0))
	_check(cost < 0.25, "sequencer costs %.0f%% of real time" % (cost * 100.0))

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("radio") == null or game.get("game_state") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	radio = game.radio
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(radio.station == -1, "the radio should start off")
			var has_lp := false
			var bus := AudioServer.get_bus_index(&"Music")
			for i in AudioServer.get_bus_effect_count(bus):
				if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
					has_lp = true
			_check(has_lp, "the Music bus should have the speaker low-pass")
			_go(Step.CYCLE)
		Step.CYCLE:
			var seen: Array[int] = []
			for i in RadioSequencer.station_count() + 1:
				radio.next_station()
				seen.append(radio.station)
				_check(radio.static_left > 0.0, "switching should start static")
				_check(radio.toast_text != "", "switching should show a toast")
			var want: Array[int] = [0, 1, 2, -1]
			_check(seen == want, "N should cycle 0,1,2,off, got %s" % str(seen))
			t_station0 = radio.station_time(0)
			radio.next_station()  # tune station 0
			cursor_before = radio._cursor
			_go(Step.RUN)
		Step.RUN:
			if waited >= 60 * 3:
				_check(radio._cursor > cursor_before + 22050, "the tuned station should keep playing (cursor %d from %d)" % [radio._cursor, cursor_before])
				radio.next_station()  # station 1; 0 keeps running
				radio.next_station()  # station 2
				radio.next_station()  # off
				radio.next_station()  # station 0 again
				var expect := int(radio.station_time(0) * RadioSequencer.MIX_RATE)
				_check(absi(radio._cursor - expect) <= 2, "tuning in should land on the station clock (%d vs %d)" % [radio._cursor, expect])
				_check(radio.station_time(0) > t_station0 + 2.0, "the station clock should have kept running")
				_go(Step.PAUSE)
				game.game_state.pause()
		Step.PAUSE:
			if waited >= 3:
				_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "pausing should mute the Music bus")
				game.game_state.resume()
				return _end("")
	return false

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
	print("radio: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
