extends SceneTree

# Radio carousel (R2, 2026-10-11), headless, stepped by hand at 60 Hz so the
# times are exact (+/- one frame):
# - one N moves the ring one card; the slide takes SLIDE_SECS (0.22 s)
# - the viewport renders every frame while the ring moves, then update-once
# - three quick N: the ring ends on the third card, one tune, TUNE_DELAY (0.35 s)
#   after the ring stops, and only the landing station's songs are requested
# - the ring wraps from the last station to the first
# - at rest (4 s after the last change) the side cards fade and the card shrinks
# - the radio off: the card shows OFF; N turns it on at the card, no slide
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --audio-driver Dummy -s res://tests/ui/radio_carousel.gd

const DT := 1.0 / 60.0

var failures: Array[String] = []
var radio: RadioManager
var head: HeadUnit
var started := false

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_radio_carousel_exhaust.json"
	radio = RadioManager.new()
	root.add_child(radio)
	radio.set_process(false)   # stepped by hand below
	head = HeadUnit.new("p1_coupe")
	root.add_child(head)

func _process(_delta: float) -> bool:
	if started:
		return false
	started = true
	_run()
	return true

func _step(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		_tick()

func _tick() -> void:
	radio._process(DT)
	head.show_ring(radio.shown_card(), radio.slide_count, radio.slide_secs, DT, radio.lit(), radio.band)

## Steps until the ring stops; returns the seconds it took (-1 on timeout).
func _until_still(limit := 2.0) -> float:
	var t := 0.0
	while t < limit:
		_tick()
		t += DT
		if not head.animating and head.ring_pos == float(head.ring_target):
			return t
	return -1.0

func _run() -> void:
	var n := RadioStations.station_count()
	_check(n == 5, "five stations on the dial, got %d" % n)
	var dials := []
	for st in RadioStations.STATIONS:
		dials.append(float(st.dial))
	var sorted := dials.duplicate()
	sorted.sort()
	_check(dials == sorted, "the ring runs in dial order %s" % str(dials))
	_check(RadioStations.STATIONS[RadioStations.DEFAULT_STATION].name == "Afterglow", "Afterglow is the default station")

	# power on at the card, no slide
	_check(radio.station == -1, "the radio starts off")
	radio.next_station()
	_check(radio.station == RadioStations.DEFAULT_STATION and radio.slide_count == 0, "N with the radio off turns it on at the card, no slide")
	_step(0.3)
	_check(head.centre_card() == RadioStations.DEFAULT_STATION, "the ring rests on the card")
	_check(head.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "the viewport is update-once at rest")
	_step(0.5)

	# one N
	var start := radio.card
	radio.next_station()
	_tick()
	_check(head.animating and head.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "the viewport renders every frame while the ring moves")
	var took := _until_still() + DT
	_check(absf(took - RadioManager.SLIDE_SECS) <= DT * 1.5, "one slide takes 0.22 s (%.3f s)" % took)
	_check(head.centre_card() == (start + 1) % n and radio.card == (start + 1) % n, "the ring moved one card")
	_check(head.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "update-once again after the slide")
	_step(0.6)
	_check(radio.station == radio.card, "the station tuned to the card after the slide")

	# three quick N
	var tunes := radio.tune_count
	var c0 := radio.card
	var skipped := (c0 + 2) % n
	var landing := (c0 + 3) % n
	for i in 3:
		radio.next_station()
	_check(radio.station == c0, "the station does not change while the ring moves")
	var ring_stop := -1.0
	var tune_at := -1.0
	var t := 0.0
	while t < 2.0 and (ring_stop < 0.0 or tune_at < 0.0):
		_tick()
		t += DT
		if ring_stop < 0.0 and not head.animating and head.ring_pos == float(head.ring_target):
			ring_stop = t
		if tune_at < 0.0 and radio.tune_count > tunes:
			tune_at = t
	_check(ring_stop > 0.0 and tune_at > 0.0, "the ring stopped and the radio tuned")
	_check(radio.tune_count == tunes + 1, "three quick presses give one tune (%d)" % (radio.tune_count - tunes))
	_check(absf((tune_at - ring_stop) - RadioManager.TUNE_DELAY) <= DT * 2.5, "the tune comes 0.35 s after the ring stops (%.3f s)" % (tune_at - ring_stop))
	_check(radio.station == landing and head.centre_card() == landing, "the ring ended on the third station")
	if RadioStations.has_music(skipped):
		_check(not radio._requested[skipped], "a skipped station's songs were not requested")
	_check(not RadioStations.has_music(landing) or radio._requested[landing], "the landing station's songs were requested")

	# wrap
	radio.tune_to(n - 1)
	_step(0.1)
	radio.next_station()
	_until_still()
	_step(0.7)
	_check(radio.station == 0 and head.centre_card() == 0, "the ring wraps from the last station to the first (%d)" % radio.station)

	# rest state
	_step(3.0)
	_check(head.rest == 0.0 and not head.animating, "side cards still up 3 s after the last change (rest %.2f)" % head.rest)
	_step(1.8)
	_check(head.rest > 0.99 and not head.animating, "at rest 4 s after the last change (rest %.2f)" % head.rest)
	_check(head.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "update-once at rest")
	radio.next_station()
	_tick()
	_step(0.2)
	_check(head.rest < 0.5, "a press brings the side cards back (rest %.2f)" % head.rest)

	# off
	_step(0.8)
	radio.toggle_power()
	_step(0.1)
	_check(radio.station == -1 and not radio.lit() and not head.lit, "V turns the radio off")
	var slides := radio.slide_count
	radio.next_station()
	_check(radio.slide_count == slides and radio.station == radio.card, "N while off turns it on at the card without a slide")

	for f in failures:
		printerr("FAIL: ", f)
	print("radio_carousel: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
