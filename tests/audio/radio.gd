extends SceneTree

# Radio test (file stations, 2026-10-06), headless and silent (state and numbers only):
# - the stations: Drift Phonk, Dark Phonk, The Dave Show (Dave, talk only), Synthwave,
#   with 7 .ogg tracks in each music folder, and Dave lines
# - the playlist: deterministic, every track once per round, never the same track
#   twice in a row, positions line up end to end; with an overlap the next track
#   starts under the tail of the last (never silent between songs)
# - the manager in the real game: N cycles the stations then off, a switch starts
#   static and a toast, every station clock keeps running while another is tuned,
#   tuning in starts the track the clock says, partway through, the next track
#   starts when one ends, Dave has no music but captions + a chime (and nothing to
#   duck; the duck target is unit-tested), the
#   Music bus has the speaker low-pass, and pausing mutes the Music bus
# - memory (2026-10-10): only the song on air and the next one stay loaded; the
#   songs blend into each other on two players; RadioLengths matches the files
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/radio.gd

const TIMEOUT_TICKS := 60 * 40

enum Step { BOOT, CYCLE, RUN, AWAY, NEXT, NEXT2, XFADE_END, DJ, DJ_OUT, PAUSE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var radio: RadioManager
var t_station0 := 0.0
var entry_before := 0
var track_name_before := ""
var chimes_before := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	_station_tests()
	_playlist_tests()
	change_scene_to_file("res://Game.tscn")

func _station_tests() -> void:
	_check(RadioStations.station_count() == 5, "expected 5 stations, got %d" % RadioStations.station_count())
	# Dial order: Graveyard Radio (talk), Slipstream, Undertow, Afterglow, Grey Hour
	# (counts from the 2026-10-11 import).
	var want_counts := [0, 5, 6, 7, 5]
	var found := {}
	for s in RadioStations.station_count():
		var paths := RadioStations.track_paths(s)
		_check(paths.size() == want_counts[s], "station %d should have %d tracks, has %d" % [s, want_counts[s], paths.size()])
		for p in paths:
			var stream := load(p) as AudioStream
			_check(stream != null and stream.get_length() > 30.0, "%s should load as a track over 30 s" % p)
			if stream != null:
				found[p] = stream.get_length()
	for m in RadioLengths.stale_entries(found):
		_check(false, "song length table is stale (run tools/radio_lengths.gd): %s" % m)
	_check(not RadioStations.has_music(0), "Graveyard Radio should be talk only")
	_check(RadioStations.STATIONS[0].dj.size() >= 4, "Dave needs lines")
	for s in [1, 2, 3, 4]:
		_check(not RadioStations.break_state(s, 5.0).in_break, "music station %d has no breaks" % s)
	_check(RadioStations.break_state(0, 3.0).in_break, "Dave should talk at the start of his period")
	_check(not RadioStations.break_state(0, RadioStations.BREAK_SECS + 5.0).in_break, "Dave should be quiet between lines")
	_check(RadioStations.break_state(0, RadioStations.DAVE_PERIOD + 3.0).line != RadioStations.break_state(0, 3.0).line, "Dave should rotate his lines")
	# ducking: only a station with music has anything to duck, and it ducks hard
	_check(RadioManager.duck_target(true, true) < 0.4, "a break over music should duck it")
	_check(RadioManager.duck_target(true, false) == 1.0, "a break on a talk station has no music to duck")
	_check(RadioManager.duck_target(false, true) == 1.0, "no break, no duck")
	_check(FileAccess.file_exists("res://assets/radio/CREDITS.md"), "assets/radio/CREDITS.md is missing")

func _playlist_tests() -> void:
	var lengths := PackedFloat32Array([60.0, 75.5, 90.0, 66.0, 80.0, 70.0, 96.0])
	var a := RadioPlaylist.new(lengths, 1)
	var b := RadioPlaylist.new(lengths, 1)
	var last_track := -1
	var last_entry := -1
	var seen := {}
	var t := 0.0
	for i in 400:  # 400 entries is ~57 rounds
		var pos := a.locate(t + 0.5)
		_check(pos.offset >= 0.49 and pos.offset < lengths[pos.track], "offset %.2f outside track %d" % [pos.offset, pos.track])
		_check(pos.track != last_track, "track %d played twice in a row (entry %d)" % [pos.track, pos.entry])
		_check(pos.entry == last_entry + 1, "entries should count up one at a time")
		_check(b.locate(t + 0.5).track == pos.track, "the order should be deterministic")
		if pos.entry < 7:
			seen[pos.track] = true
		last_track = pos.track
		last_entry = pos.entry
		t += lengths[pos.track]
	_check(seen.size() == 7, "the first round should play every track once, saw %d" % seen.size())
	_check(a.locate(t * 0.37).track == a.locate(t * 0.37 + 0.001).track, "locate should be stable")
	_check(RadioPlaylist.new(PackedFloat32Array(), 1).locate(5.0).track == -1, "an empty playlist has no track")
	var one := RadioPlaylist.new(PackedFloat32Array([50.0]), 1)
	_check(one.locate(120.0).track == 0 and absf(one.locate(120.0).offset - 20.0) < 0.01, "a one-track playlist just repeats")
	# overlap: each track starts 3 s before the last one ends, and is never silent
	var c := RadioPlaylist.new(lengths, 1, 3.0)
	var overlaps := 0
	var last_c_entry := -1
	var tt := 0.0
	while tt < 3000.0:
		var pos := c.locate(tt)
		_check(pos.offset >= 0.0 and pos.offset < lengths[pos.track], "overlap: offset %.2f outside track %d" % [pos.offset, pos.track])
		_check(pos.entry >= last_c_entry and pos.entry <= last_c_entry + 1, "overlap: entries should count up one at a time")
		_check(pos.blend >= 0.0 and pos.blend <= 1.0, "overlap: blend %.2f out of range" % pos.blend)
		_check(c.entry_track(pos.entry) == pos.track, "overlap: entry_track should agree with locate")
		if pos.prev_track >= 0:
			overlaps += 1
			_check(pos.prev_track != pos.track, "overlap: the song before should be a different track")
			_check(pos.prev_offset >= 0.0 and pos.prev_offset < lengths[pos.prev_track], "overlap: the old song should still be playing (%.2f of %.1f)" % [pos.prev_offset, lengths[pos.prev_track]])
			_check(pos.blend < 1.0 and pos.offset < 3.0 + 0.001, "overlap: only the first 3 s of a track blend")
		else:
			_check(pos.blend == 1.0, "overlap: no old song, no blend")
		last_c_entry = pos.entry
		tt += 0.25
	_check(overlaps > 100, "overlap: expected many crossfades, saw %d samples" % overlaps)
	var d := RadioPlaylist.new(PackedFloat32Array([50.0, 50.0]), 1, 3.0)
	_check(absf(d.locate(0.0).offset) < 0.001 and d.locate(0.0).prev_track == -1, "overlap: the first track has nothing before it")
	_check(d.locate(47.5).entry == 1 and absf(d.locate(47.5).prev_offset - 47.5) < 0.01, "overlap: the second track should start 3 s early (prev_offset %.2f)" % d.locate(47.5).prev_offset)

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
			# off -> N turns it on at the card (no slide); then the ring runs round
			# the five stations and wraps back to the card
			var first := RadioStations.DEFAULT_STATION
			radio.next_station()
			_check(radio.station == first and radio.slide_count == 0, "N with the radio off should turn it on at the card")
			_check(radio.static_left > 0.0, "switching should start static")
			_check(radio.toast_text != "", "switching should show a caption")
			for i in RadioStations.station_count():
				radio.next_station()
				_check(radio.card == (first + i + 1) % RadioStations.station_count(), "the ring should go round in dial order")
				_check(radio.static_left > 0.0, "a slide should start static")
			_check(radio.card == first, "the ring should wrap back to the card")
			radio.tune_to(1)   # Slipstream
			_go(Step.RUN)
		Step.RUN:
			# tuned in on station 0: its 7 tracks load on background threads, so the
			# radio's own _process starts the track a few frames later
			if radio.now_playing != "" or waited >= 180:
				var pos := radio.playlist_position(1)
				_check(radio.now_playing != "", "a music station should have a track on air")
				var slot: int = radio._slot_key.find(Vector2i(1, pos.entry))
				_check(slot >= 0 and radio._slots[slot].playing, "the track on air should be on a playing player")
				_check(slot >= 0 and radio._slots[slot].stream == radio._streams[radio._paths[1][pos.track]], "the player should hold the track the playlist says")
				_check(radio._streams.size() <= 3, "only the song on air and the next should stay loaded, %d are" % radio._streams.size())
				_check(radio.now_playing.begins_with("0"), "should be playing a numbered track file, got %s" % radio.now_playing)
				entry_before = pos.entry
				t_station0 = radio.station_time(1)
				_go(Step.AWAY)
		Step.AWAY:
			# all the way round (1, 2, 3, off) and back to 0: the clock kept going
			if waited >= 2:
				radio.tune_to(2)
				radio.tune_to(3)
				radio.tune_to(1)
				_check(radio.station == 1, "should be back on station 1")
				_check(radio.station_time(1) >= t_station0, "the station clock should have kept running")
				_check(radio.playlist_position(1).entry >= entry_before, "the playlist should not go backwards")
				_go(Step.NEXT)
		Step.NEXT:
			if waited >= 3:
				# put the clock 5 s before the end of the track on air (2 s before the
				# crossfade starts), then 4 s on: 1 s into the crossfade
				var pos := radio.playlist_position(1)
				var length: float = radio._lengths[radio._paths[1][pos.track]]
				radio._clock += (length - pos.offset) - 5.0
				entry_before = radio.playlist_position(1).entry
				track_name_before = radio.now_playing
				_check(radio.playlist_position(1).offset > length - 5.5, "the clock should now be near the end of the track")
				_check(radio.playlist_position(1).prev_track == -1, "the crossfade should not have started yet")
				radio._clock += 4.0
				_go(Step.NEXT2)
		Step.NEXT2:
			if radio.now_playing != track_name_before or waited >= 180:
				_check(radio.playlist_position(1).entry == entry_before + 1, "the next track should be on")
				_check(radio.now_playing != track_name_before, "the next track should differ from the last (%s)" % radio.now_playing)
				var pos := radio.playlist_position(1)
				_check(pos.prev_track >= 0, "the clock should be inside the crossfade")
				_check(radio._music.playing and radio._music_b.playing, "both players should be on during the crossfade")
				_check(radio._streams.size() <= 3, "at most the two songs of the crossfade and the next should be loaded, %d are" % radio._streams.size())
				radio._clock += 4.0   # out of the crossfade (3 s long)
				_go(Step.XFADE_END)
		Step.XFADE_END:
			# The radio drops the faded player in its own _process; under CPU load
			# several physics ticks run per drawn frame, so wait for it (up to 1 s)
			# rather than a fixed 3 ticks.
			if (radio._music.playing != radio._music_b.playing and waited >= 3) or waited >= 60:
				_check(radio._music.playing != radio._music_b.playing, "after the crossfade one player should be left")
				_check(radio._streams.size() <= 2, "after the crossfade only the song on air and the next stay loaded, %d are" % radio._streams.size())
				_check(radio.now_playing != "", "the music should still be playing")
				# Dave: tune station 0 (talk only), a second into one of his lines
				radio.station = 0
				radio._clock = RadioStations.DAVE_PERIOD * 3.0 - radio._offsets[0] + 1.0
				chimes_before = radio.chime_count
				_go(Step.DJ)
		Step.DJ:
			if waited == 40:
				_check(not radio._music.playing and not radio._music_b.playing, "Graveyard Radio has no music")
				_check(radio._streams.is_empty(), "no music station is tuned, so no song should stay loaded (%d are)" % radio._streams.size())
				_check(radio.now_playing == "", "nothing should be on air on the talk station")
				_check(radio.dj_active, "Dave's line should be showing")
				_check(radio.dj_text.begins_with("Dave:"), "the caption should be Dave's, got '%s'" % radio.dj_text)
				_check(radio.chime_count == chimes_before + 1, "a line should play one chime")
				_check(radio.duck == 1.0, "Dave has no music, so nothing ducks (%.2f)" % radio.duck)
				radio._clock = RadioStations.DAVE_PERIOD * 3.0 - radio._offsets[0] + RadioStations.BREAK_SECS + 5.0  # between lines
				_go(Step.DJ_OUT)
		Step.DJ_OUT:
			if waited == 90:
				_check(not radio.dj_active, "the line should be over")
				_check(radio.duck > 0.9, "the music should come back up (%.2f)" % radio.duck)
				_go(Step.PAUSE)
				game.game_state.pause()
		Step.PAUSE:
			if waited >= 3:
				# The pause screen keeps the radio on, muffled (pause_look.gd); the Tuner mutes it.
				_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "pausing should keep the Music bus playing")
				game.game_state.resume()
				game.game_state.toggle_tuning()
				_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "the Tuner should mute the Music bus")
				game.game_state.close_tuning()
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
