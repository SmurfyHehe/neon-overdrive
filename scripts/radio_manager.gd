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

## -1 = off, else an index into RadioSequencer.STATIONS.
var station := -1
var static_left := 0.0
var toast_text := ""
var toast_left := 0.0

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
	_label.position = Vector2(16, 104)
	_label.add_theme_color_override("font_color", Color(0.0, 0.96, 1.0))
	_label.visible = false
	layer.add_child(_label)

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

## Where a station is in its song right now, in seconds on its own clock.
func station_time(s: int) -> float:
	return _clock + _offsets[s]

func _process(delta: float) -> void:
	_clock += delta
	toast_left = maxf(toast_left - delta, 0.0)
	_label.visible = toast_left > 0.0
	_label.text = toast_text
	static_left = maxf(static_left - delta, 0.0)
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
			block[i] *= GAIN
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
