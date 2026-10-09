extends Node
class_name PerspectiveAudio

# The whole mix by where you are listening from (Phase C, 2026-10-05; every bus,
# radio and head direction 2026-10-09, Roy: "all audio should change according to
# camera angle used, radio usage and window up/down slider").
#
# Three inputs, each eased so nothing clicks:
# - the view: `blend` 0 in the chase view .. 1 in the cockpit (BLEND_SECS)
# - the side window: `window` 0 closed .. 1 open (Z: hold to roll down, tap to
#   roll up; the one openness value the window glass and CarAudio read too, see
#   window_openness())
# - the head: `head_yaw_deg` (+ = left), set by the camera from look back and
#   the mirror glance (and free look when it lands). Cockpit only.
# and the radio: `scanner_open` (the police scanner's squelch, when that lands)
# ducks the music. Radio on/off, station and volume never move another bus, so
# the cabin sounds the same whatever is playing.
#
# Two kinds of bus:
# - outside sources (engine, tyres and road, wind, traffic, sirens): open in the
#   chase view; in the cockpit low-passed and a little quieter by the cabin. The
#   open window lets most of it back in (WINDOW_OPEN_SHARE).
# - inside sources (the radio's Music and the Scanner): clear in the cockpit; from
#   the chase cam you hear the car's stereo from outside, thin and far. The open
#   window lets some of it out (WINDOW_LEAK_SHARE).
# Each bus carries one always-on low-pass (never toggled, so it can't click);
# Music, Scanner and World also carry a panner for the head direction: turn your
# head left and the radio moves to your right ear; the driver's window (left-hand
# drive) is on your left.
#
# The volume sliders (AudioSettings) set each bus's base level; this adds the
# offsets on top every frame. Tests run on the silent Dummy driver and assert on
# cutoffs, pans and levels (mix() is the pure table, tests/audio/audio_mix.gd sweeps it).

const BLEND_SECS := 0.3
const OPEN_HZ := 20000.0
## Outside sources: cutoff_hz and volume offset (dB) in the cockpit, window up.
const COCKPIT_HZ := {&"Engine": 3600.0, &"Tires": 2800.0, &"World": 1800.0, &"Traffic": 1400.0, &"Sirens": 2400.0}
const COCKPIT_DB := {&"Engine": -2.0, &"Tires": -3.0, &"World": 0.0, &"Traffic": -8.0, &"Sirens": -5.0}
## Inside sources: [cockpit cutoff, heard-from-outside cutoff, heard-from-outside dB].
const INSIDE := {&"Music": [7500.0, 3200.0, -7.0], &"Scanner": [3400.0, 1800.0, -10.0]}
const MUSIC_COCKPIT_HZ := 7500.0   # RadioManager's speaker filter
const MUSIC_CHASE_HZ := 3200.0     # outside the car the music is thin
const MUSIC_CHASE_DB := -7.0       # and quieter

const WINDOW_DOWN_SECS := 2.5     # closed to fully open while Z is held
const WINDOW_UP_SECS := 1.2       # a tap rolls it all the way up in this long
const WINDOW_TAP_SECS := 0.25     # a press shorter than this is a tap
const WINDOW_OPEN_SHARE := 0.85   # fully open is this much of the way to outside sound
const WINDOW_LEAK_SHARE := 0.5    # fully open, the stereo is this much less "outside" from the chase cam
const WINDOW_MUSIC_DB := -2.0     # the radio against the wind, window fully down (cockpit)

const SCANNER_DUCK_DB := -8.0     # the music under an open scanner squelch
const SCANNER_DUCK_RATE := 8.0    # 1/s
const HEAD_PAN := 0.5             # a source 90 degrees to one side pans this far
const HEAD_BEHIND_HZ := 4500.0    # the radio's cutoff with your head turned right round
const WINDOW_AZIMUTH_DEG := 90.0  # the driver's window, + = left (left-hand drive)
const WIND_PAN := 0.4             # how far the open window pulls the wind to its side

const OUTSIDE_BUSES: Array[StringName] = [&"Engine", &"Tires", &"World", &"Traffic", &"Sirens"]
const INSIDE_BUSES: Array[StringName] = [&"Music", &"Scanner"]
const PANNED_BUSES: Array[StringName] = [&"World", &"Music", &"Scanner"]

## The one in the game, for window_openness() (the window glass reads it).
static var current: PerspectiveAudio

var blend := 0.0
var target := 0.0
## THE window openness, 0 closed .. 1 fully down. One value, three readers:
## CarAudio (the wind and the seal whistle, via _process), the CockpitFrame
## (the glass slides, the crank or switch moves, the driver's left hand works
## it; ChaseCamera hands it over every physics tick) and the pause-menu
## slider. ChaseCamera.window_openness() is the public read of it.
var window := 0.0
var head_yaw_deg := 0.0
var scanner_open := false
var scanner_duck := 0.0   # eased 0..1
## The car's CarAudio: gets `cabin` and `window` every frame (set by the camera).
var car_audio: CarAudio
var _window_held := 0.0
var _window_closing := false
var _window_pressed := false
var _filters := {}   # bus name -> AudioEffectLowPassFilter
var _panners := {}   # bus name -> AudioEffectPanner

## The side window, 0 closed .. 1 open, for anything that shows or plays it.
## 0 before the game has a camera.
static func window_openness() -> float:
	return current.window if is_instance_valid(current) else 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = self
	for bus_name in OUTSIDE_BUSES:
		_filters[bus_name] = _filter_on(bus_name, OPEN_HZ)
	for bus_name in INSIDE_BUSES:
		_filters[bus_name] = _filter_on(bus_name, INSIDE[bus_name][1])
	for bus_name in PANNED_BUSES:
		_panners[bus_name] = _panner_on(bus_name)
	_apply()

func _exit_tree() -> void:
	if current == self:
		current = null

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

func _panner_on(bus_name: StringName) -> AudioEffectPanner:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return null
	for i in AudioServer.get_bus_effect_count(bus):
		var e := AudioServer.get_bus_effect(bus, i)
		if e is AudioEffectPanner:
			return e
	var p := AudioEffectPanner.new()
	AudioServer.add_bus_effect(bus, p)
	return p

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

## How far each outside bus is towards its cockpit filter: the view, less what
## the open window lets back in.
func cabin_amount() -> float:
	return blend * (1.0 - WINDOW_OPEN_SHARE * window)

## The mix for one moment, as plain numbers: bus -> {hz, db, pan}. `db` is the
## offset on top of the volume slider. Pure, so tests can sweep it.
static func mix(view: float, win: float, yaw_deg: float, duck: float) -> Dictionary:
	var out := {}
	var cabin := view * (1.0 - WINDOW_OPEN_SHARE * win)
	for bus_name in OUTSIDE_BUSES:
		out[bus_name] = {
			"hz": _log_lerp(OPEN_HZ, COCKPIT_HZ[bus_name], cabin),
			"db": COCKPIT_DB[bus_name] * cabin,
			"pan": 0.0,
		}
	# heard from outside: the chase cam, less what the open window lets out
	var outside := (1.0 - view) * (1.0 - WINDOW_LEAK_SHARE * win)
	var yaw := deg_to_rad(yaw_deg)
	var behind := (1.0 - cos(yaw)) * 0.5 * view   # 0 facing the dash .. 1 facing the back seat
	for bus_name in INSIDE_BUSES:
		var spec: Array = INSIDE[bus_name]
		var inside_hz := _log_lerp(spec[0], minf(spec[0], HEAD_BEHIND_HZ), behind)
		out[bus_name] = {
			"hz": _log_lerp(inside_hz, spec[1], outside),
			"db": spec[2] * outside + WINDOW_MUSIC_DB * win * view,
			# the dash is straight ahead: head left (+) puts it in the right ear (+)
			"pan": _pan_for(0.0, yaw) * view,
		}
	out[&"Music"]["db"] += SCANNER_DUCK_DB * duck
	# the open driver's window pulls the wind to its side
	out[&"World"]["pan"] = _pan_for(deg_to_rad(WINDOW_AZIMUTH_DEG), yaw) * (WIND_PAN / HEAD_PAN) * pow(win, 0.7) * view
	return out

## Pan of a source at `azimuth` (+ = left of the car's nose) heard with the head
## turned `yaw` (+ = left): -1 left ear .. +1 right ear, at most HEAD_PAN.
static func _pan_for(azimuth: float, yaw: float) -> float:
	return -sin(azimuth - yaw) * HEAD_PAN

static func _log_lerp(a: float, b: float, t: float) -> float:
	# in log frequency, so the sweep sounds even
	return exp(lerpf(log(a), log(b), t))

func _process(delta: float) -> void:
	# applied every frame: the volume sliders set the buses too, and this adds
	# the offsets back on top of them
	blend = move_toward(blend, target, delta / BLEND_SECS)
	scanner_duck = move_toward(scanner_duck, 1.0 if scanner_open else 0.0, delta * SCANNER_DUCK_RATE)
	_apply()
	if is_instance_valid(car_audio):
		car_audio.cabin = blend
		car_audio.window = window

func _apply() -> void:
	var m := mix(blend, window, head_yaw_deg, scanner_duck)
	for bus_name in m:
		var lp: AudioEffectLowPassFilter = _filters.get(bus_name)
		if lp != null:
			lp.cutoff_hz = m[bus_name].hz
		var pn: AudioEffectPanner = _panners.get(bus_name)
		if pn != null:
			pn.pan = m[bus_name].pan
		var b := AudioServer.get_bus_index(bus_name)
		if b >= 0:
			AudioServer.set_bus_volume_db(b, AudioSettings.volume_db_for(AudioSettings.channel_of(bus_name)) + m[bus_name].db)

func cutoff(bus_name: StringName) -> float:
	var lp: AudioEffectLowPassFilter = _filters.get(bus_name)
	return lp.cutoff_hz if lp != null else -1.0

func pan(bus_name: StringName) -> float:
	var p: AudioEffectPanner = _panners.get(bus_name)
	return p.pan if p != null else 0.0
