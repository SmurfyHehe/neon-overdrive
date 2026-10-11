extends SceneTree

# Radio power, alerts and captions (R4, 2026-10-11), headless, stepped by hand:
# - V (set_power / toggle_power): off stops music and Dave, no captions, the
#   card is kept; on again comes back on the same station
# - the station caption "102.5 Afterglow." at the bottom outside the cockpit
# - the song caption "Title · Artist": once per song, never in a chase or a
#   race, never with the Settings > Sound switch off, never in the cockpit
# - an important Dave line with the radio off switches it on for that line (at
#   low volume, on Graveyard Radio) and back off; an ordinary line does not
# - saves: the on/off flag, and an old save's index lands on Afterglow
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --audio-driver Dummy -s res://tests/audio/radio_power.gd

const DT := 1.0 / 60.0

var failures: Array[String] = []
var radio: RadioManager
var started := false

func _initialize() -> void:
	AudioSettings.path = "user://test_radio_power_settings.cfg"
	radio = RadioManager.new()
	root.add_child(radio)
	radio.set_process(false)

func _process(_delta: float) -> bool:
	if started:
		return false
	started = true
	_run()
	return true

func _step(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		radio._process(DT)

## Steps (with a real-time wait for the threaded track loads) until a song is on air.
func _until_song(limit_ms := 20000) -> bool:
	var t0 := Time.get_ticks_msec()
	while radio.now_playing == "" and Time.get_ticks_msec() - t0 < limit_ms:
		radio._process(DT)
		OS.delay_msec(5)
	return radio.now_playing != ""

## Jumps the station clock to just after the end of the song on air: the next
## one starts from its beginning (a tune-in mid-song would be past the 20 s).
func _next_song() -> void:
	var pos := radio.playlist_position(radio.station)
	# songs are keyed by path since 507e27a (only the song on air and the next are loaded)
	var length: float = radio._lengths[radio._paths[radio.station][pos.track]]
	radio._clock += (length - pos.offset) + 0.3
	radio._process(DT)
	radio._process(DT)
	_until_song()   # the next song may still be loading on its thread

func _cap() -> String:
	return radio._cap_label.text if radio._cap_label.visible else ""

func _run() -> void:
	radio.view_is_cockpit = false
	# on at the card: station caption
	radio.set_power(true)
	var st: Dictionary = RadioStations.STATIONS[radio.card]
	_step(0.1)
	_check(radio.station == radio.card and radio.station == RadioStations.DEFAULT_STATION, "power on lands on the card")
	_check(_cap() == "%s %s." % [st.dial, st.name], "the station caption outside the cockpit: '%s'" % _cap())
	_step(RadioManager.STATION_CAPTION_SECS + 0.2)
	_check(_cap() == "", "the station caption goes after 2.5 s")

	# song caption: once per song
	_check(_until_song(), "a song comes on")
	_step(RadioManager.STATION_CAPTION_SECS)
	_next_song()
	_step(0.1)
	var info := RadioStations.song_info(radio.station, radio.now_playing)
	var want := "%s · %s" % [info.title, info.artist]
	var seen := _cap() == want
	for i in 60 * 5:
		if seen:
			break
		radio._process(DT)
		seen = _cap() == want
	_check(seen, "the song caption shows 'Title · Artist' (want '%s', got '%s')" % [want, _cap()])
	_step(RadioManager.SONG_CAPTION_SECS + 0.3)
	_check(_cap() == "", "the song caption goes after 3 s and does not come back for the same song (%s)" % _cap())

	# V: off
	radio.toggle_power()
	_step(0.2)
	_check(radio.station == -1 and radio.card == RadioStations.DEFAULT_STATION, "V turns the radio off and keeps the card")
	_check(not radio._music.playing and radio.now_playing == "", "off: the music stops")
	_check(_cap() == "" and not radio.dj_active, "off: no captions, no Dave")
	_check(not radio.lit(), "off: the screen is not lit")
	radio.next_station()   # N while off: on at the card
	_check(radio.station == radio.card and radio.slide_count == 0, "N while off turns it on at the card, no slide")
	radio.toggle_power()
	radio.toggle_power()
	_check(radio.station == RadioStations.DEFAULT_STATION, "V again: back on at the same station")
	radio.toggle_power()

	# an ordinary line does nothing with the radio off; an important one switches it on
	_check(not radio.announce("Dave: Nine o'clock."), "an ordinary line is not read with the radio off")
	var chimes := radio.chime_count
	_check(radio.announce("Dave: Police up ahead.", true), "an important line is read")
	_step(0.3)
	_check(radio.station == -1 and radio.lit() and radio.on_air() == RadioStations.TALK_STATION, "the radio switched itself on, on Graveyard Radio")
	_check(radio.dj_active and radio.dj_text == "Dave: Police up ahead.", "the line is up (%s)" % radio.dj_text)
	_check(radio.chime_count == chimes + 1, "one chime")
	_step(RadioStations.BREAK_SECS + RadioManager.ALERT_TAIL + 0.5)
	_check(radio.station == -1 and not radio.lit() and not radio.dj_active and radio.on_air() == -1, "after the line the radio is off again")
	_check(radio.card == RadioStations.DEFAULT_STATION, "the alert did not move the card")

	# no song captions in the cockpit, in a chase or a race, or with the setting off
	radio.set_power(true)
	radio.view_is_cockpit = true
	radio.tune_to(2)
	_step(0.1)
	_check(_until_song(), "a song comes on (cockpit)")
	_next_song()
	_step(1.0)
	_check(_cap() == "", "no caption in the cockpit")
	radio.view_is_cockpit = false
	radio.busy_check = func() -> bool: return true
	radio.tune_to(1)
	_step(0.1)
	_check(_until_song(), "a song comes on (chase)")
	_step(RadioManager.STATION_CAPTION_SECS)
	_next_song()
	_step(1.0)
	_check(_cap() == "" or _cap() == "%s %s." % [RadioStations.STATIONS[1].dial, RadioStations.STATIONS[1].name], "no song caption in a chase or a race (%s)" % _cap())
	_step(4.0)
	_check(_cap() == "", "still none (%s)" % _cap())
	radio.busy_check = Callable()
	AudioSettings.song_names = false
	radio.tune_to(3)
	_step(0.1)
	_check(_until_song(), "a song comes on (setting off)")
	_step(RadioManager.STATION_CAPTION_SECS)
	_next_song()
	_step(1.0)
	_check(_cap() == "", "Song names off: no caption (%s)" % _cap())
	AudioSettings.song_names = true

	# saves
	radio.restore({"radio": 6})   # an old index (Slipstream/Undertow/Grey Hour in the old list)
	_check(radio.station == RadioStations.DEFAULT_STATION, "an old save's index lands on Afterglow (%d)" % radio.station)
	radio.restore({"radio": -1})
	_check(radio.station == -1, "an old save with the radio off stays off")
	radio.restore({"radio": 1, "radio_id": "undertow", "radio_on": false})
	_check(radio.station == -1 and radio.card == 2 and radio.player_station() == 2 and not radio.player_on(), "a new save keeps the station id and the on/off flag")
	radio.set_power(true)
	_check(radio.player_on(), "player_on follows the power")

	for f in failures:
		printerr("FAIL: ", f)
	print("radio_power: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
