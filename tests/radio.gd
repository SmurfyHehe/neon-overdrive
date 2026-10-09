extends SceneTree

# Radio test (file stations, 2026-10-06), headless and silent (state and numbers only):
# - the stations: Drift Phonk, Dark Phonk, The Dave Show (Dave, talk only), Synthwave,
#   with 7 .ogg tracks in each music folder, and Dave lines
# - the playlist: deterministic, every track once per round, never the same track
#   twice in a row, positions line up end to end
# - the manager in the real game: N cycles the stations then off, a switch starts
#   static and a toast, every station clock keeps running while another is tuned,
#   tuning in starts the track the clock says, partway through, the next track
#   starts when one ends, Dave has no music but captions + a chime (and nothing to
#   duck; the duck target is unit-tested), the
#   Music bus has the speaker low-pass, and pausing muffles the radio (not mute;
#   menus A-list 2026-10-08) while the Tuner still mutes it
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/radio.gd

const TIMEOUT_TICKS := 60 * 40

enum Step { BOOT, CYCLE, RUN, AWAY, NEXT, NEXT2, DJ, DJ_OUT, PAUSE, DONE }

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
	_check(RadioStations.station_count() == 4, "expected 4 stations, got %d" % RadioStations.station_count())
	var want_counts := [7, 7, 0, 7]
	for s in RadioStations.station_count():
		var paths := RadioStations.track_paths(s)
		_check(paths.size() == want_counts[s], "station %d should have %d tracks, has %d" % [s, want_counts[s], paths.size()])
		for p in paths:
			var stream := load(p) as AudioStream
			_check(stream != null and stream.get_length() > 30.0, "%s should load as a track over 30 s" % p)
	_check(not RadioStations.has_music(2), "The Dave Show should be talk only")
	_check(RadioStations.STATIONS[2].dj.size() >= 4, "Dave needs lines")
	for s in [0, 1, 3]:
		_check(not RadioStations.break_state(s, 5.0).in_break, "music station %d has no breaks" % s)
	_check(RadioStations.break_state(2, 3.0).in_break, "Dave should talk at the start of his period")
	_check(not RadioStations.break_state(2, RadioStations.BREAK_SECS + 5.0).in_break, "Dave should be quiet between lines")
	_check(RadioStations.break_state(2, RadioStations.DAVE_PERIOD + 3.0).line != RadioStations.break_state(2, 3.0).line, "Dave should rotate his lines")
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
			for i in RadioStations.station_count() + 1:
				radio.next_station()
				seen.append(radio.station)
				_check(radio.static_left > 0.0, "switching should start static")
				_check(radio.toast_text != "", "switching should show a toast")
			var want: Array[int] = []
			for i in RadioStations.station_count():
				want.append(i)
			want.append(-1)
			_check(seen == want, "N should cycle every station then off, got %s" % str(seen))
			radio.next_station()  # tune station 0
			_go(Step.RUN)
		Step.RUN:
			# tuned in on station 0: its 7 tracks load on background threads, so the
			# radio's own _process starts the track a few frames later
			if radio.now_playing != "" or waited >= 180:
				var pos := radio.playlist_position(0)
				_check(radio.now_playing != "", "a music station should have a track on air")
				_check(radio._music.playing, "the music player should be playing")
				_check(radio._music.stream == radio._streams[0][pos.track], "the player should hold the track the playlist says")
				_check(radio.now_playing.begins_with("0"), "should be playing a numbered track file, got %s" % radio.now_playing)
				entry_before = pos.entry
				t_station0 = radio.station_time(0)
				_go(Step.AWAY)
		Step.AWAY:
			# all the way round (1, 2, 3, off) and back to 0: the clock kept going
			if waited >= 2:
				for i in RadioStations.station_count() + 1:
					radio.next_station()
				_check(radio.station == 0, "should be back on station 0")
				_check(radio.station_time(0) >= t_station0, "the station clock should have kept running")
				_check(radio.playlist_position(0).entry >= entry_before, "the playlist should not go backwards")
				_go(Step.NEXT)
		Step.NEXT:
			if waited >= 3:
				# put the clock 2 s before the end of the track on air, then past it
				var pos := radio.playlist_position(0)
				var length: float = radio._streams[0][pos.track].get_length()
				radio._clock += (length - pos.offset) - 2.0
				entry_before = radio.playlist_position(0).entry
				track_name_before = radio.now_playing
				_check(radio.playlist_position(0).offset > length - 2.5, "the clock should now be near the end of the track")
				radio._clock += 4.0
				_go(Step.NEXT2)
		Step.NEXT2:
			if radio.now_playing != track_name_before or waited >= 180:
				_check(radio.playlist_position(0).entry == entry_before + 1, "the next track should be on")
				_check(radio.now_playing != track_name_before, "the next track should differ from the last (%s)" % radio.now_playing)
				_check(radio._music.playing, "the music should still be playing")
				# Dave: tune station 2 (talk only), a second into one of his lines
				radio.station = 2
				radio._clock = RadioStations.DAVE_PERIOD * 3.0 - radio._offsets[2] + 1.0
				chimes_before = radio.chime_count
				_go(Step.DJ)
		Step.DJ:
			if waited == 40:
				_check(not radio._music.playing, "The Dave Show has no music")
				_check(radio.now_playing == "", "nothing should be on air on the talk station")
				_check(radio.dj_active, "Dave's line should be showing")
				_check(radio.dj_text.begins_with("Dave:"), "the caption should be Dave's, got '%s'" % radio.dj_text)
				_check(radio.chime_count == chimes_before + 1, "a line should play one chime")
				_check(radio.duck == 1.0, "Dave has no music, so nothing ducks (%.2f)" % radio.duck)
				radio._clock = RadioStations.DAVE_PERIOD * 3.0 - radio._offsets[2] + RadioStations.BREAK_SECS + 5.0  # between lines
				_go(Step.DJ_OUT)
		Step.DJ_OUT:
			if waited == 90:
				_check(not radio.dj_active, "the line should be over")
				_check(radio.duck > 0.9, "the music should come back up (%.2f)" % radio.duck)
				_go(Step.PAUSE)
				game.game_state.pause()
		Step.PAUSE:
			if waited >= 3:
				var mb := AudioServer.get_bus_index(&"Music")
				_check(not AudioServer.is_bus_mute(mb), "pausing should keep the radio playing")
				var look: PauseLook = null
				for c in game.get_children():
					if c is PauseLook:
						look = c
				_check(look != null and look.muffled(), "pausing should muffle the radio")
				game.game_state.resume()
				_check(look == null or not look.muffled(), "resuming should take the muffle off")
				game.game_state.toggle_tuning()
				_check(AudioServer.is_bus_mute(mb), "the Tuner should still mute the radio")
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
