extends Node
class_name PerspectiveAudio

# Cockpit vs chase sound (Phase C, 2026-10-05). Inside the car the engine, tyres and
# wind are muffled by the cabin and the radio is right there; behind the car the
# music is thin and far and the engine is open. Each affected bus carries one
# low-pass filter that is always enabled (never toggled, so it can't click); the
# cutoff and the Music volume ease between the two views over BLEND_SECS.
#
# `blend` is 0 in the chase view and 1 in the cockpit (readable by tests, which run
# on the silent Dummy driver and assert on cutoffs and levels, not on sound).
#
# The side window (2026-10-08, Roy: Z, hold to roll down, tap to roll up) is a
# second dial inside the cockpit: `window` 0 closed .. 1 open. Opening it lifts
# the cabin filters most of the way back to the outside sound and turns the
# radio down a little against the noise; CarAudio adds the wind, the throb of a
# cracked window and the seal whistle. The chase view ignores the window.

const BLEND_SECS := 0.3
const OPEN_HZ := 20000.0
# cutoff_hz when fully in the cockpit, by bus
const COCKPIT_HZ := {&"Engine": 3600.0, &"Tires": 2800.0, &"World": 1800.0}
const MUSIC_CHASE_HZ := 3200.0     # outside the car the music is thin
const MUSIC_COCKPIT_HZ := 7500.0   # RadioManager's speaker filter
const MUSIC_CHASE_DB := -7.0       # and quieter

const WINDOW_DOWN_SECS := 2.5     # closed to fully open while Z is held
const WINDOW_UP_SECS := 1.2       # a tap rolls it all the way up in this long
const WINDOW_TAP_SECS := 0.25     # a press shorter than this is a tap
const WINDOW_OPEN_SHARE := 0.85   # fully open is this much of the way to outside sound
const WINDOW_MUSIC_DB := -2.0     # the radio against the wind, window fully down

var blend := 0.0
var target := 0.0
## THE window openness, 0 closed .. 1 fully down. One value, three readers:
## CarAudio (the wind and the seal whistle, via _process), the CockpitFrame
## (the glass slides, the crank or switch moves, the driver's left hand works
## it; ChaseCamera hands it over every physics tick) and the pause-menu
## slider. ChaseCamera.window_openness() is the public read of it.
var window := 0.0
## The car's CarAudio: gets `cabin` and `window` every frame (set by the camera).
var car_audio: CarAudio
var _window_held := 0.0
var _window_closing := false
var _window_pressed := false
var _filters := {}   # bus name -> AudioEffectLowPassFilter

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in COCKPIT_HZ:
		_filters[bus_name] = _filter_on(bus_name, OPEN_HZ)
	_filters[&"Music"] = _filter_on(&"Music", MUSIC_CHASE_HZ)
	_apply()

## The bus's low-pass, added if the bus has none yet.
func _filter_on(bus_name: StringName, hz: float) -> AudioEffectLowPassFilter:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return null
	for i in AudioServer.get_bus_effect_count(bus):
		var e := AudioServer.get_bus_effect(bus, i)
		if e is AudioEffectLowPassFilter:
			return e
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = hz
	AudioServer.add_bus_effect(bus, lp)
	return lp

func set_cockpit(on: bool) -> void:
	target = 1.0 if on else 0.0

## The window key, once per physics tick: held rolls it down; a short tap rolls
## it all the way back up.
func window_key(pressed: bool, delta: float) -> void:
	_window_pressed = pressed
	if pressed:
		_window_held += delta
		_window_closing = false
		window = minf(1.0, window + delta / WINDOW_DOWN_SECS)
		return
	if _window_held > 0.0 and _window_held < WINDOW_TAP_SECS:
		_window_closing = true
	_window_held = 0.0
	if _window_closing:
		window = maxf(0.0, window - delta / WINDOW_UP_SECS)
		_window_closing = window > 0.0

## Which way the window is being worked this tick, for the cockpit animation:
## +1 rolling down (the key is held, even at the stop), -1 rolling up after a
## tap, 0 at rest. The driver's hand stays on the crank or switch while this
## is non-zero.
func window_direction() -> int:
	if _window_pressed:
		return 1
	return -1 if _window_closing else 0

## How far each bus is towards its cockpit filter: the view, less what the
## open window lets back in.
func cabin_amount() -> float:
	return blend * (1.0 - WINDOW_OPEN_SHARE * window)

func _process(delta: float) -> void:
	# applied every frame: the volume sliders set the Music bus too, and this adds
	# the view's offset back on top of them
	blend = move_toward(blend, target, delta / BLEND_SECS)
	_apply()
	if is_instance_valid(car_audio):
		car_audio.cabin = blend
		car_audio.window = window

func _apply() -> void:
	for bus_name in COCKPIT_HZ:
		var lp: AudioEffectLowPassFilter = _filters.get(bus_name)
		if lp != null:
			# interpolate in log frequency so the sweep sounds even
			lp.cutoff_hz = exp(lerpf(log(OPEN_HZ), log(COCKPIT_HZ[bus_name]), cabin_amount()))
	var music: AudioEffectLowPassFilter = _filters.get(&"Music")
	if music != null:
		music.cutoff_hz = exp(lerpf(log(MUSIC_CHASE_HZ), log(MUSIC_COCKPIT_HZ), blend))
	var mb := AudioServer.get_bus_index(&"Music")
	if mb >= 0:
		AudioServer.set_bus_volume_db(mb, AudioSettings.volume_db_for("Music") + lerpf(MUSIC_CHASE_DB, 0.0, blend) + WINDOW_MUSIC_DB * window * blend)

func cutoff(bus_name: StringName) -> float:
	var lp: AudioEffectLowPassFilter = _filters.get(bus_name)
	return lp.cutoff_hz if lp != null else -1.0
