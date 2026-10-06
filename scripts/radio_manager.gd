extends Node
class_name RadioManager

# The in-game radio (Phase B, 2026-10-05). N cycles Neon FM, Night Drive, Open
# Road, off. Three generated stations from RadioSequencer (no licences, no
# files); a licensed or recorded station slots in later as another entry once its
# row is in docs/audio-licences.md.
#
# One AudioStreamGenerator on the Music bus plays whichever station is tuned.
# Every station has a running clock that advances all the time, so tuning back in
# lands mid-song like a real radio. Switching plays a short burst of static. The
# Music bus gets a low-pass so the music sounds like it comes from car speakers.
# The tree's pause stops _process, so the radio goes quiet in the pause menu
# (GameState also mutes the Music bus while paused to avoid a click).
#
# Tests run silent (Dummy audio driver) and assert on state: station, clock,
# static, levels, bus effect.

const MIX_RATE := 22050.0
const BUFFER_SECS := 0.12
const STATIC_SECS := 0.35
const TOAST_SECS := 3.0
const SPEAKER_CUTOFF_HZ := 7500.0
const GAIN := 0.8
const DUCK_DB := -11.0          # the music under the DJ
const DUCK_RATE := 6.0          # 1/s, how fast it ducks and comes back
const CHIME_NOTES := [76, 79, 83, 88]   # E5 G5 B5 E6, the stinger at the start of a break

## -1 = off, else an index into RadioSequencer.STATIONS.
var station := -1
var static_left := 0.0
var toast_text := ""
var toast_left := 0.0
## DJ break (see RadioSequencer.break_state): true while the tuned station is in one.
var dj_active := false
var dj_text := ""
var chime_count := 0
var duck := 1.0                # current music gain, 1 = full
var _dj_label: Label
var _chime_left := 0.0
var _in_break_before := false

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _sequencer := RadioSequencer.new()
var _clock := 0.0            # seconds since the radio was built; every station runs on it
var _offsets := []           # per station: a fixed head start, so they are not all at bar 1 together
var _cursor := 0             # absolute sample index of the tuned station's next block
var _label: Label
var _static_lp := 0.0
var _rng := 777

func _ready() -> void:
	for i in RadioSequencer.station_count():
		_offsets.append(float(i) * 23.7)
	_ensure_speaker_filter()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_SECS
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = &"Music"
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 40)
	_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))  # amber #FFC066
	_label.visible = false
	layer.add_child(_label)
	_dj_label = Label.new()
	_dj_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dj_label.position = Vector2(-360, -150)
	_dj_label.custom_minimum_size = Vector2(720, 0)
	_dj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dj_label.add_theme_color_override("font_color", Color(1.0, 0.54, 0.12))
	_dj_label.add_theme_font_size_override("font_size", 20)
	_dj_label.visible = false
	layer.add_child(_dj_label)

## Music bus: a gentle low-pass, once, so the radio sounds like a car stereo.
func _ensure_speaker_filter() -> void:
	var bus := AudioServer.get_bus_index(&"Music")
	if bus < 0:
		return
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			return
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = SPEAKER_CUTOFF_HZ
	AudioServer.add_bus_effect(bus, lp)

## N: next station, with off after the last one.
func next_station() -> void:
	var count := RadioSequencer.station_count()
	station = station + 1 if station + 1 < count else -1
	static_left = STATIC_SECS
	if station >= 0:
		_cursor = int(station_time(station) * MIX_RATE)
		toast_text = "RADIO  %s  %d BPM" % [RadioSequencer.STATIONS[station].name, int(RadioSequencer.STATIONS[station].bpm)]
	else:
		toast_text = "RADIO OFF"
	toast_left = TOAST_SECS

## DJ break bookkeeping for the tuned station: caption, ducking, and the chime when a
## break begins (also when you tune in mid-break, so you hear it start).
func _update_dj(delta: float) -> void:
	var in_break := false
	if station >= 0:
		var st := RadioSequencer.break_state(station, station_time(station))
		in_break = st.in_break
		if in_break:
			var lines: Array = RadioSequencer.STATIONS[station].dj
			dj_text = "%s: %s" % [RadioSequencer.STATIONS[station].name, lines[st.line]]
	if in_break and not _in_break_before:
		chime_count += 1
		_chime_left = 1.2
	_in_break_before = in_break
	dj_active = in_break
	var want := db_to_linear(DUCK_DB) if in_break else 1.0
	duck = lerpf(duck, want, 1.0 - exp(-DUCK_RATE * delta))
	_dj_label.visible = in_break
	_dj_label.text = dj_text

## A short rising chime (four sine pings) mixed into a block.
func _add_chime(block: PackedVector2Array, n: int) -> void:
	for i in n:
		var t := 1.2 - _chime_left + float(i) / MIX_RATE
		var note := clampi(int(t / 0.25), 0, CHIME_NOTES.size() - 1)
		var local := t - note * 0.25
		var env := exp(-7.0 * local) * clampf(local * 200.0, 0.0, 1.0)
		var v := sin(TAU * RadioSequencer.midi_hz(CHIME_NOTES[note]) * t) * env * 0.35
		block[i] += Vector2(v, v)
	_chime_left = maxf(_chime_left - float(n) / MIX_RATE, 0.0)

## Where a station is in its song right now, in seconds on its own clock.
func station_time(s: int) -> float:
	return _clock + _offsets[s]

func _process(delta: float) -> void:
	_clock += delta
	toast_left = maxf(toast_left - delta, 0.0)
	_label.visible = toast_left > 0.0
	_label.text = toast_text
	static_left = maxf(static_left - delta, 0.0)
	_update_dj(delta)
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var block := PackedVector2Array()
	if station >= 0:
		block = _sequencer.render(station, _cursor, n)
		_cursor += n
		for i in n:
			block[i] *= GAIN * duck
		if _chime_left > 0.0:
			_add_chime(block, n)
	else:
		block.resize(n)
	if static_left > 0.0:
		var level := clampf(static_left / STATIC_SECS, 0.0, 1.0) * 0.35
		for i in n:
			_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
			var nz := _rng / 1073741823.5 - 1.0
			_static_lp += 0.5 * (nz - _static_lp)
			var v := (nz - _static_lp) * level
			block[i] += Vector2(v, v)
	_playback.push_buffer(block)
