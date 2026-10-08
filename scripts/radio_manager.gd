extends Node
class_name RadioManager

# The in-game radio (Phase B, 2026-10-05; file stations 2026-10-06). N cycles
# Drift Phonk, Dark Phonk, The Dave Show (Dave, talk only), Synthwave, off. The
# music stations play the Ogg Vorbis tracks in assets/radio/ (RadioStations),
# one shuffled playlist each (RadioPlaylist): no track twice in a row, the next
# one starts when a track ends.
#
# Every station has a running clock that advances all the time, so tuning back in
# lands mid-track like a real radio. Switching plays a short burst of static. The
# Music bus gets a low-pass so the music sounds like it comes from car speakers.
# Dave's lines come as captions with a chime (they would duck any music). The tree's pause
# stops _process, so the radio goes quiet in the pause menu (GameState also mutes
# the Music bus while paused to avoid a click).
#
# Two players on the Music bus: _music plays the tracks, _fx is a generator for the
# static and the chime. A station's tracks load in the background (ResourceLoader
# threaded requests) the first time you tune it, so there is no frame hitch; the
# music starts as soon as they are all in, at the place the station clock says.
#
# Tests run silent (Dummy audio driver) and assert on state: station, clock,
# playlist position, static, levels, bus effect.

const MIX_RATE := 22050.0   # the static / chime generator
const BUFFER_SECS := 0.12
const STATIC_SECS := 0.35
const TOAST_SECS := 3.0
const SPEAKER_CUTOFF_HZ := 7500.0
const GAIN := 0.8
const DUCK_DB := -11.0          # the music under the DJ
const DUCK_RATE := 6.0          # 1/s, how fast it ducks and comes back
const CHIME_NOTES := [76, 79, 83, 88]   # E5 G5 B5 E6, the stinger at the start of a break

## -1 = off, else an index into RadioStations.STATIONS.
var station := -1
var static_left := 0.0
var toast_text := ""
var toast_left := 0.0
## Dave break (see RadioStations.break_state): true while the tuned station is in one.
var dj_active := false
var dj_text := ""
var chime_count := 0
var duck := 1.0                # current music gain, 1 = full
## File name (no extension) of the track on air, "" when nothing plays.
var now_playing := ""
## The night clock's hour band (NightBands.Band, set by game.gd); -1 = none,
## Dave's plain rotation. His station adds a few lines that fit the band.
var band := -1
var _dj_label: Label
var _chime_left := 0.0
var _in_break_before := false
## A one-off line (Dave's time check) that overrides the rotation while it runs.
var _announce_text := ""
var _announce_left := 0.0

var _music: AudioStreamPlayer
var _player: AudioStreamPlayer      # the static / chime generator
var _playback: AudioStreamGeneratorPlayback
var _streams := []           # per station: Array of AudioStream, filled on first tune
var _lists := []             # per station: RadioPlaylist, or null (no music)
var _tracks := []            # per station: Array[String] of file names matching _streams
var _requested := []         # per station: true once the background load was asked for
var _playing_station := -1
var _playing_entry := -1
var _clock := 0.0            # seconds since the radio was built; every station runs on it
var _offsets := []           # per station: a fixed head start, so they are not all at bar 1 together
var _label: Label
var _static_lp := 0.0
var _rng := 777

func _ready() -> void:
	for i in RadioStations.station_count():
		_offsets.append(float(i) * 23.7)
		_streams.append([])
		_lists.append(null)
		_tracks.append([])
		_requested.append(false)
	_ensure_speaker_filter()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_SECS
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
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
	var count := RadioStations.station_count()
	station = station + 1 if station + 1 < count else -1
	static_left = STATIC_SECS
	if station >= 0:
		_request_load(station)
		toast_text = "RADIO  %s" % RadioStations.STATIONS[station].name
	else:
		toast_text = "RADIO OFF"
	toast_left = TOAST_SECS

## Asks for a music station's tracks to load on background threads, once.
func _request_load(s: int) -> void:
	if _requested[s] or not RadioStations.has_music(s):
		return
	_requested[s] = true
	for path in RadioStations.track_paths(s):
		ResourceLoader.load_threaded_request(path)

## True when every track of the station has finished loading (or it has none).
func _load_done(s: int) -> bool:
	if _lists[s] != null or not RadioStations.has_music(s):
		return true
	_request_load(s)
	for path in RadioStations.track_paths(s):
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
	return true

## Collects a music station's tracks and builds its playlist, once. Blocks for any
## track still loading, so the game loop only calls it after _load_done.
func _ensure_loaded(s: int) -> void:
	if _lists[s] != null or not RadioStations.has_music(s):
		return
	_request_load(s)
	var lengths := PackedFloat32Array()
	for path in RadioStations.track_paths(s):
		var stream := ResourceLoader.load_threaded_get(path) as AudioStream
		if stream == null or stream.get_length() <= 0.0:
			push_warning("radio: could not load %s" % path)
			continue
		_streams[s].append(stream)
		_tracks[s].append(path.get_file().get_basename())
		lengths.append(stream.get_length())
	_lists[s] = RadioPlaylist.new(lengths, 777 + s)

## The tuned station's playlist position right now, or {} (off / talk only / no tracks).
func playlist_position(s: int) -> Dictionary:
	_ensure_loaded(s)
	if _lists[s] == null or _lists[s].track_count() == 0:
		return {}
	return _lists[s].locate(station_time(s))

## Plays the tuned station's current track, starting the next one when a track ends.
## Tuning in starts the track partway through, where the station clock says.
func _update_music() -> void:
	var pos := {}
	if station >= 0 and _load_done(station):
		pos = playlist_position(station)
	if pos.is_empty():
		if _music.playing:
			_music.stop()
		_playing_station = -1
		_playing_entry = -1
		now_playing = ""
		return
	if station != _playing_station or pos.entry != _playing_entry or not _music.playing:
		_music.stream = _streams[station][pos.track]
		_music.play(pos.offset)
		_playing_station = station
		_playing_entry = pos.entry
		now_playing = _tracks[station][pos.track]
	_music.volume_db = linear_to_db(GAIN * duck)

## DJ break bookkeeping for the tuned station: caption, ducking, and the chime when a
## break begins (also when you tune in mid-break, so you hear it start).
func _update_dj(delta: float) -> void:
	var in_break := false
	_announce_left = maxf(_announce_left - delta, 0.0)
	if station >= 0 and _announce_left > 0.0:
		in_break = true
		dj_text = _announce_text
	elif station >= 0:
		var st := RadioStations.break_state(station, station_time(station), band)
		in_break = st.in_break
		if in_break:
			var lines: Array = RadioStations.dj_lines(station, band)
			dj_text = lines[st.line]
	if in_break and not _in_break_before:
		chime_count += 1
		_chime_left = 1.2
	_in_break_before = in_break
	dj_active = in_break
	var want := duck_target(in_break, station >= 0 and RadioStations.has_music(station))
	duck = lerpf(duck, want, 1.0 - exp(-DUCK_RATE * delta))
	_dj_label.visible = in_break
	_dj_label.text = dj_text

## The hour struck on the night clock: on Dave's station he reads the time out
## (a caption with the chime, like his other lines). Other stations and the
## radio off say nothing. True when Dave spoke.
func announce_hour(hour24: int) -> bool:
	if station < 0 or RadioStations.STATIONS[station].kind != "talk":
		return false
	_announce_text = RadioStations.time_line(hour24)
	_announce_left = RadioStations.BREAK_SECS
	_in_break_before = false   # a new line: chime even if a rotation line was up
	return true

## The music gain a DJ break aims for: ducked while a line is on and there is music
## to duck, else full. Dave's station has no music, so nothing ducks under him.
static func duck_target(in_break: bool, has_music: bool) -> float:
	return db_to_linear(DUCK_DB) if in_break and has_music else 1.0

## A short rising chime (four sine pings) mixed into a block.
func _add_chime(block: PackedVector2Array, n: int) -> void:
	for i in n:
		var t := 1.2 - _chime_left + float(i) / MIX_RATE
		var note := clampi(int(t / 0.25), 0, CHIME_NOTES.size() - 1)
		var local := t - note * 0.25
		var env := exp(-7.0 * local) * clampf(local * 200.0, 0.0, 1.0)
		var v := sin(TAU * midi_hz(CHIME_NOTES[note]) * t) * env * 0.35
		block[i] += Vector2(v, v)
	_chime_left = maxf(_chime_left - float(n) / MIX_RATE, 0.0)

static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)

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
	_update_music()
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var block := PackedVector2Array()
	block.resize(n)
	if _chime_left > 0.0:
		_add_chime(block, n)
	if static_left > 0.0:
		var level := clampf(static_left / STATIC_SECS, 0.0, 1.0) * 0.35
		for i in n:
			_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
			var nz := _rng / 1073741823.5 - 1.0
			_static_lp += 0.5 * (nz - _static_lp)
			var v := (nz - _static_lp) * level
			block[i] += Vector2(v, v)
	_playback.push_buffer(block)
