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

const BLEND_SECS := 0.3
const OPEN_HZ := 20000.0
# cutoff_hz when fully in the cockpit, by bus
const COCKPIT_HZ := {&"Engine": 3600.0, &"Tires": 2800.0, &"World": 1800.0}
const MUSIC_CHASE_HZ := 3200.0     # outside the car the music is thin
const MUSIC_COCKPIT_HZ := 7500.0   # RadioManager's speaker filter
const MUSIC_CHASE_DB := -7.0       # and quieter

var blend := 0.0
var target := 0.0
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

func _process(delta: float) -> void:
	# applied every frame: the volume sliders set the Music bus too, and this adds
	# the view's offset back on top of them
	blend = move_toward(blend, target, delta / BLEND_SECS)
	_apply()

func _apply() -> void:
	for bus_name in COCKPIT_HZ:
		var lp: AudioEffectLowPassFilter = _filters.get(bus_name)
		if lp != null:
			# interpolate in log frequency so the sweep sounds even
			lp.cutoff_hz = exp(lerpf(log(OPEN_HZ), log(COCKPIT_HZ[bus_name]), blend))
	var music: AudioEffectLowPassFilter = _filters.get(&"Music")
	if music != null:
		music.cutoff_hz = exp(lerpf(log(MUSIC_CHASE_HZ), log(MUSIC_COCKPIT_HZ), blend))
	var mb := AudioServer.get_bus_index(&"Music")
	if mb >= 0:
		AudioServer.set_bus_volume_db(mb, AudioSettings.volume_db_for("Music") + lerpf(MUSIC_CHASE_DB, 0.0, blend))

func cutoff(bus_name: StringName) -> float:
	var lp: AudioEffectLowPassFilter = _filters.get(bus_name)
	return lp.cutoff_hz if lp != null else -1.0
