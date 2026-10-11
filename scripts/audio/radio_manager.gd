extends Node
class_name RadioManager

# The in-game radio (Phase B, 2026-10-05; file stations 2026-10-06). N goes to
# the next of the five dial stations (a ring: after the last comes the first);
# V turns the radio off and on (R4, 2026-10-11). The music stations play the Ogg Vorbis tracks in assets/radio/ (RadioStations),
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
# Reception (2026-10-08, Roy's small ideas): under a bridge or in a tunnel
# (SoundZone) the signal fades; the music cuts out in short random drops and
# crackle and hiss come up, then it all comes back on the way out. `listener`
# is the player car (Game sets it).
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
const RECEPTION_RATE := 4.0     # 1/s, how fast the signal follows where you are
const CRACKLE_LEVEL := 0.22     # hiss at no signal
const DROP_FROM := 0.75         # below this reception the music starts dropping out
const SLIDE_SECS := 0.22        # the screen's ring moves one card (HeadUnit)
const SLIDE_QUEUED_SECS := 0.16 # a press that arrives while the ring is still moving
const TUNE_DELAY := 0.35        # the station tunes this long after the ring stops
## Radio off and Dave has an important line (an event, the weather change, a
## police warning): the radio switches itself on for that one line.
const AUTO_ON_FOR_ALERTS := true
const ALERT_GAIN := 0.4         # the alert's chime, quieter than a normal break
const ALERT_TAIL := 1.0         # s the radio stays on after the line's caption
const STATION_CAPTION_SECS := 2.5
const SONG_CAPTION_SECS := 3.0
const SONG_LATE_SECS := 20.0    # a song this far in gets no caption
const CHIME_NOTES := [76, 79, 83, 88]   # E5 G5 B5 E6, the stinger at the start of a break

## What is on air: -1 = off, else an index into RadioStations.STATIONS. It
## follows `card` TUNE_DELAY after the ring stops, so skipping past stations
## never loads their songs.
var station := -1
## The station the ring (the head unit's carousel) rests on; the radio comes back
## on at it. Always valid, even with the radio off.
var card := RadioStations.DEFAULT_STATION
## The ring's moves: how many N presses slid it, and how long the last one takes.
var slide_count := 0
var slide_secs := 0.0
var tune_count := 0           # how many times a station was tuned in after a slide
## Captions at the bottom of the outside view (cockpit: the head unit shows it).
var view_is_cockpit := true
## Set by Game: true while a police chase or a race is on (no song captions).
var busy_check := Callable()
var _retune_left := -1.0      # >= 0: the ring is moving or settling, tune when it hits 0
var _alert_left := 0.0
var _song_key := ""
var _song_pending := ""
var _song_t0 := 0.0
var _song_offset0 := 0.0
var _song_cap_left := 0.0
var _song_cap_text := ""
var _cap_label: Label
var static_left := 0.0
var toast_text := ""
var toast_left := 0.0
## Dave break (see RadioStations.break_state): true while the tuned station is in one.
var dj_active := false
var dj_text := ""
var chime_count := 0
var duck := 1.0                # current music gain, 1 = full
var reception := 1.0           # 0 no signal (tunnel) .. 1 clear
var dropout_count := 0
var listener: Node3D
var forced_reception := -1.0   # tests / listen pack: >= 0 overrides the zones
var _cut_left := 0.0           # s left in a drop-out
var _rx_rng := RandomNumberGenerator.new()
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
	# The caption for a station change or a new song, outside view only: the
	# same subtitle style as Dave's lines, a little lower.
	_cap_label = Label.new()
	_cap_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_cap_label.position = Vector2(-360, -104)
	_cap_label.custom_minimum_size = Vector2(720, 0)
	_cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))  # amber #FFC066
	UiTheme.subtitle(_cap_label, 20)
	_cap_label.visible = false
	layer.add_child(_cap_label)
	_dj_label = Label.new()
	_dj_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dj_label.position = Vector2(-360, -150)
	_dj_label.custom_minimum_size = Vector2(720, 0)
	_dj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dj_label.add_theme_color_override("font_color", Color(1.0, 0.54, 0.12))
	UiTheme.subtitle(_dj_label, 20)   # Dale: Subtitles role
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

## Straight to station s (-1 = off), quietly: a resumed run's radio.
## The title screen borrows the radio for its own station (borrow / give_back);
## saves keep the station the player chose (player_station, player_on).
var _lent_from := -2
var _lent_card := 0

func borrow(s: int) -> void:
	if _lent_from == -2:
		_lent_from = station
		_lent_card = card
	tune_to(s)

func give_back() -> void:
	if _lent_from != -2:
		var s := _lent_from
		var c := _lent_card
		_lent_from = -2
		tune_to(s)
		card = c

## The player's own ring station (saves), not the title's borrowed one.
func player_station() -> int:
	return card if _lent_from == -2 else _lent_card

## Whether the player's radio is on (saves).
func player_on() -> bool:
	return (station if _lent_from == -2 else _lent_from) >= 0

func tune_to(s: int) -> void:
	_retune_left = -1.0
	station = s if s >= 0 and s < RadioStations.station_count() else -1
	if station >= 0:
		card = station
		_request_load(station)

## A saved run's radio (R1, 2026-10-11): `radio` is the ring station, `radio_on`
## whether it was on, `radio_id` the station's name on the dial. A save from
## before the dial (an index into the old eight stations, -1 = off) lands on
## Afterglow; its -1 stays "off".
func restore(run: Dictionary) -> void:
	var idx := int(run.get("radio", -1))
	var s := RadioStations.migrate_saved(idx, str(run.get("radio_id", "")))
	var on: bool = bool(run.radio_on) if run.has("radio_on") else idx >= 0
	if s >= 0:
		card = s
	tune_to(card if on else -1)

## N: the next station. The ring slides one card and the station tunes
## TUNE_DELAY after it stops. With the radio off it only turns it on, at the
## station on the card, no slide.
func next_station() -> void:
	if station < 0:
		set_power(true)
		return
	slide_secs = SLIDE_QUEUED_SECS if _retune_left > TUNE_DELAY else SLIDE_SECS
	slide_count += 1
	card = (card + 1) % RadioStations.station_count()
	_retune_left = slide_secs + TUNE_DELAY
	static_left = _retune_left + 0.1   # static from the first slide until the tune

## V: the radio off (music and Dave stop, no captions) and on again at the card.
func set_power(on: bool) -> void:
	_alert_left = 0.0
	if on == (station >= 0):
		return
	if on:
		station = card
		_retune_left = -1.0
		static_left = STATIC_SECS
		_request_load(station)
		_show_station_caption()
	else:
		station = -1
		_retune_left = -1.0
		static_left = 0.0
		toast_left = 0.0
		_song_cap_left = 0.0
		_song_pending = ""
		_song_key = ""

func toggle_power() -> void:
	set_power(station < 0)

## True while the ring is moving or settling (nothing is on air yet).
func retuning() -> bool:
	return _retune_left >= 0.0

## The station on air for captions, music and Dave: the tuned one, or Graveyard
## Radio during an alert that switched the radio on for a line.
func on_air() -> int:
	if retuning():
		return -1
	if station >= 0:
		return station
	return RadioStations.TALK_STATION if _alert_left > 0.0 else -1

## True while the screen shows the radio lit: on, or an alert's moment.
func lit() -> bool:
	return station >= 0 or _alert_left > 0.0

## The card the head unit's ring rests on (Graveyard during an alert).
func shown_card() -> int:
	return RadioStations.TALK_STATION if station < 0 and _alert_left > 0.0 else card

## The station caption, "102.5 Afterglow.", at the bottom of the outside view.
func _show_station_caption() -> void:
	toast_text = "%s %s." % [RadioStations.STATIONS[station].dial, RadioStations.STATIONS[station].name]
	toast_left = STATION_CAPTION_SECS

## The caption rule: any view that is not the cockpit shows it.
func show_radio_caption() -> bool:
	return not view_is_cockpit

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
	if station >= 0 and not retuning() and _load_done(station):
		pos = playlist_position(station)
	if pos.is_empty():
		if _music.playing:
			_music.stop()
		_playing_station = -1
		_playing_entry = -1
		now_playing = ""
		_song_key = ""
		return
	if station != _playing_station or pos.entry != _playing_entry or not _music.playing:
		_music.stream = _streams[station][pos.track]
		_music.play(pos.offset)
		_playing_station = station
		_playing_entry = pos.entry
		now_playing = _tracks[station][pos.track]
		_song_pending = "%d:%s" % [station, now_playing]
		_song_t0 = _clock
		_song_offset0 = pos.offset
	_music.volume_db = linear_to_db(maxf(GAIN * duck * signal_gain(), 0.00001))

## DJ break bookkeeping for the tuned station: caption, ducking, and the chime when a
## break begins (also when you tune in mid-break, so you hear it start).
func _update_dj(delta: float) -> void:
	var in_break := false
	var air := on_air()
	_announce_left = maxf(_announce_left - delta, 0.0)
	if _alert_left > 0.0 and station < 0:
		_alert_left = maxf(_alert_left - delta, 0.0)   # the line's caption, then off again
	if air >= 0 and _announce_left > 0.0:
		in_break = true
		dj_text = _announce_text
	elif air >= 0 and station >= 0:
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
	var want := duck_target(in_break, air >= 0 and RadioStations.has_music(air))
	duck = lerpf(duck, want, 1.0 - exp(-DUCK_RATE * delta))
	_dj_label.visible = in_break
	_dj_label.text = dj_text

## The hour struck on the night clock: on Dave's station he reads the time out
## (a caption with the chime, like his other lines). Other stations and the
## radio off say nothing. True when Dave spoke.
func announce_hour(hour24: int) -> bool:
	return announce(RadioStations.time_line(hour24))

## A one-off Dave line (time checks, tonight's events): on his station only,
## with the chime, over the rotation. True when Dave spoke. With the radio off,
## an `important` line (event, weather change, police warning) switches it on
## for that one line, at low volume, on Graveyard Radio (AUTO_ON_FOR_ALERTS).
func announce(text: String, important := false) -> bool:
	if station < 0:
		if not (important and AUTO_ON_FOR_ALERTS):
			return false
		_alert_left = RadioStations.BREAK_SECS + ALERT_TAIL
	elif RadioStations.STATIONS[station].kind != "talk":
		return false
	_announce_text = text
	_announce_left = RadioStations.BREAK_SECS
	_in_break_before = false   # a new line: chime even if a rotation line was up
	return true

## The music gain a DJ break aims for: ducked while a line is on and there is music
## to duck, else full. Dave's station has no music, so nothing ducks under him.
static func duck_target(in_break: bool, has_music: bool) -> float:
	return db_to_linear(DUCK_DB) if in_break and has_music else 1.0

## The bottom caption outside the cockpit: the station change (always) and a
## new song's "Title · Artist" (once per song, never in a chase or a race or
## over a Dave line, and not for a song more than SONG_LATE_SECS in).
func _update_captions(delta: float) -> void:
	_song_cap_left = maxf(_song_cap_left - delta, 0.0)
	if _song_pending != "" and station >= 0:
		var into := _song_offset0 + (_clock - _song_t0)
		if into > SONG_LATE_SECS or not AudioSettings.song_names:
			_song_pending = ""
		elif show_radio_caption() and toast_left <= 0.0 and not dj_active and not (busy_check.is_valid() and bool(busy_check.call())):
			var info := RadioStations.song_info(station, now_playing)
			_song_cap_text = "%s · %s" % [info.title, info.artist]
			_song_cap_left = SONG_CAPTION_SECS
			_song_pending = ""
		elif not show_radio_caption():
			_song_pending = ""   # in the cockpit the head unit shows it
	var text := ""
	if toast_left > 0.0 and show_radio_caption() and station >= 0:
		text = toast_text
	elif _song_cap_left > 0.0 and show_radio_caption() and station >= 0 and not dj_active:
		text = _song_cap_text
	_cap_label.visible = text != ""
	_cap_label.text = text

## Follows the zone the car is in; rolls the dice for a drop-out.
func _update_reception(delta: float) -> void:
	var want := 1.0
	if forced_reception >= 0.0:
		want = forced_reception
	elif is_instance_valid(listener):
		want = SoundZone.reception_at(listener.global_position)
	reception = lerpf(reception, want, 1.0 - exp(-RECEPTION_RATE * delta))
	_cut_left = maxf(_cut_left - delta, 0.0)
	if station >= 0 and reception < DROP_FROM and _cut_left <= 0.0 and _rx_rng.randf() < (DROP_FROM - reception) * 5.0 * delta:
		_cut_left = _rx_rng.randf_range(0.06, 0.35)
		dropout_count += 1

## The music's share of the signal: nothing during a drop-out, fading with
## bad reception.
func signal_gain() -> float:
	return 0.0 if _cut_left > 0.0 else smoothstep(0.05, 0.6, reception)

## A short rising chime (four sine pings) mixed into a block.
func _add_chime(block: PackedVector2Array, n: int) -> void:
	for i in n:
		var t := 1.2 - _chime_left + float(i) / MIX_RATE
		var note := clampi(int(t / 0.25), 0, CHIME_NOTES.size() - 1)
		var local := t - note * 0.25
		var env := exp(-7.0 * local) * clampf(local * 200.0, 0.0, 1.0)
		var v := sin(TAU * midi_hz(CHIME_NOTES[note]) * t) * env * 0.35 * (ALERT_GAIN if station < 0 else 1.0)
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
	if _retune_left >= 0.0:
		_retune_left -= delta
		if _retune_left <= 0.0:
			_retune_left = -1.0
			station = card
			tune_count += 1
			_request_load(station)
			_show_station_caption()
	static_left = maxf(static_left - delta, 0.0)
	_update_dj(delta)
	_update_reception(delta)
	_update_music()
	_update_captions(delta)
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var block := PackedVector2Array()
	block.resize(n)
	if _chime_left > 0.0:
		_add_chime(block, n)
	# bad reception: hiss (louder in a drop-out) and crackle clicks
	var crackle := (1.0 - reception) * CRACKLE_LEVEL * (1.6 if _cut_left > 0.0 else 1.0) if station >= 0 else 0.0
	if static_left > 0.0 or crackle > 0.002:
		var level := clampf(static_left / STATIC_SECS, 0.0, 1.0) * 0.35 + crackle
		var clicks := (1.0 - reception) * 0.0015
		for i in n:
			_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
			var nz := _rng / 1073741823.5 - 1.0
			_static_lp += 0.5 * (nz - _static_lp)
			var v := (nz - _static_lp) * level
			if crackle > 0.0 and _rx_rng.randf() < clicks:
				v += _rx_rng.randf_range(-0.5, 0.5)
			block[i] += Vector2(v, v)
	_playback.push_buffer(block)
