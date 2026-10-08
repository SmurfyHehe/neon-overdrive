extends Node
class_name DrivelineAudio

# Driveline and chassis sounds (Phase B, 2026-10-05), next to EngineAudio and
# CarAudio on a Vehicle. Like them: generated in code, no files, no licences,
# reads GEVP state, never touches physics. Every level is a starting value for
# Roy to judge by ear.
#
# - gear whine: a tone at the gear-mesh rate (follows engine rpm), louder under
#   load and in the lower gears, fading in with speed (Engine bus);
# - shifts (rebuilt 2026-10-08, sound research 1b: "the same sample every
#   time"): each completed change plays a gearbox clack and a low thump, each
#   picked at random from five variants with random pitch and volume. Upshifts
#   are a lower clack-thunk; downshifts a brighter clack twice, through neutral
#   and into gear, with a lighter thump (Engine bus);
# - driveline clunk: a short clack when the throttle is lifted or put back on at
#   speed, the lash in the driveline taking up (Engine bus);
# - landing thud: when the wheels touch down after airtime, scaled by how fast
#   the car was falling (Tires bus).
# thump_count (every shift), upshift_count, downshift_count, clunk_count and
# landing_count rise on each event so tests (which
# run with the silent Dummy audio driver) can assert on state, not on sound.

const MIX_RATE := 22050
const WHINE_BASE_HZ := 400.0
const WHINE_TEETH := 8.0          # gear-mesh rate = engine rev/s x this (about 930 Hz at 7000 rpm)
const WHINE_GAIN := 0.10
const THUMP_GAIN := 0.5
const CLACK_GAIN := 0.32
const VARIANTS := 5
const NEUTRAL_GAP := 0.075        # s between a downshift's two clacks
const CLUNK_GAIN := 0.35
const LANDING_GAIN := 0.7
const CLUNK_COOLDOWN := 0.35      # s
const AIR_MIN := 0.15             # s of airtime before a touchdown counts as a landing
const ATTACK := 12.0
const RELEASE := 6.0

var whine_level := 0.0
var thump_count := 0
var upshift_count := 0
var downshift_count := 0
var clunk_count := 0
var landing_count := 0

static var _streams := {}

var _vehicle: Vehicle
var _whine: AudioStreamPlayer
var _thump: AudioStreamPlayer
var _clunk: AudioStreamPlayer
var _landing: AudioStreamPlayer
var _clack_up: AudioStreamPlayer
var _clack_down: AudioStreamPlayer
var _second_clack := -1.0         # s until a downshift's second clack, < 0 = none
var _last_gear := 0
var _throttle_state := 0   # 1 = throttle was open (>0.6), -1 = was closed (<0.1), 0 = neither yet
var _clunk_wait := 0.0
var _air_time := 0.0
var _fall_speed := 0.0

func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	if _vehicle == null:
		push_error("DrivelineAudio must be a child of a Vehicle")
		set_process(false)
		return
	_whine = _add_player("whine", &"Engine", true)
	_thump = _add_player("thump", &"Engine", false)
	_thump.stream = variants("thump")
	_clack_up = _add_player("clack_up", &"Engine", false)
	_clack_up.stream = variants("clack_up")
	_clack_down = _add_player("clack_down", &"Engine", false)
	_clack_down.stream = variants("clack_down")
	_clack_down.max_polyphony = 2
	_clunk = _add_player("clunk", &"Engine", false)
	_landing = _add_player("landing", &"Tires", false)
	_last_gear = _vehicle.current_gear

func _add_player(layer: String, bus_name: StringName, looping: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = layer.to_pascal_case() + "Audio"
	p.stream = stream(layer)
	p.bus = bus_name
	p.volume_db = -80.0
	add_child(p)
	if looping:
		p.play()
	return p

func _process(delta: float) -> void:
	var v := _vehicle
	# --- gear whine
	var in_gear := v.current_gear != 0 and not v.is_shifting
	var speed_gate := smoothstep(4.0, 30.0, v.speed)
	var gear_weight := 1.0 - 0.5 * clampf(float(absi(v.current_gear) - 1) / 4.0, 0.0, 1.0)
	var load := 0.3 + 0.7 * clampf(v.throttle_amount, 0.0, 1.0)
	var target := speed_gate * gear_weight * load if in_gear else 0.0
	var rate := ATTACK if target > whine_level else RELEASE
	whine_level = lerpf(whine_level, target, 1.0 - exp(-rate * delta))
	_whine.volume_db = linear_to_db(whine_level * WHINE_GAIN) if whine_level > 0.002 else -80.0
	_whine.pitch_scale = clampf(v.motor_rpm / 60.0 * WHINE_TEETH / WHINE_BASE_HZ, 0.3, 4.0)

	# --- shift thump: when a gear change completes
	if v.current_gear != _last_gear:
		if v.current_gear != 0 and v.speed > 1.0:
			_shift_sound(absi(v.current_gear) > absi(_last_gear) and _last_gear != 0, clampf(v.speed / 25.0, 0.3, 1.0))
		_last_gear = v.current_gear
	if _second_clack >= 0.0:
		_second_clack -= delta
		if _second_clack < 0.0:
			_one_shot(_clack_down, CLACK_GAIN * 0.8)

	# --- driveline clunk: lift or tip-in at speed
	_clunk_wait = maxf(_clunk_wait - delta, 0.0)
	# The throttle ramps, so watch for it crossing from open to closed (or back)
	# rather than for one big jump between frames.
	var t := v.throttle_amount
	var crossed := false
	if t > 0.6:
		crossed = _throttle_state == -1
		_throttle_state = 1
	elif t < 0.1:
		crossed = _throttle_state == 1
		_throttle_state = -1
	if crossed and v.speed > 2.0 and v.current_gear != 0 and not v.is_shifting and _clunk_wait <= 0.0:
		clunk_count += 1
		_clunk_wait = CLUNK_COOLDOWN
		_one_shot(_clunk, CLUNK_GAIN * clampf(v.speed / 20.0, 0.3, 1.0))

	# --- landing thud
	if v.get_wheel_contact_count() == 0:
		_air_time += delta
		_fall_speed = maxf(_fall_speed, -v.linear_velocity.y)
	else:
		if _air_time >= AIR_MIN and _fall_speed > 1.0:
			landing_count += 1
			_one_shot(_landing, LANDING_GAIN * clampf(_fall_speed / 8.0, 0.2, 1.0))
		_air_time = 0.0
		_fall_speed = 0.0

## One completed gear change: clack and thump, up and down sounding different.
func _shift_sound(up: bool, level: float) -> void:
	thump_count += 1
	if up:
		upshift_count += 1
		_one_shot(_clack_up, CLACK_GAIN * level)
		_one_shot(_thump, THUMP_GAIN * level)
	else:
		downshift_count += 1
		_one_shot(_clack_down, CLACK_GAIN * level)
		_second_clack = NEUTRAL_GAP
		_one_shot(_thump, THUMP_GAIN * 0.7 * level)

func _one_shot(p: AudioStreamPlayer, gain: float) -> void:
	p.volume_db = linear_to_db(clampf(gain, 0.001, 1.0))
	p.play()

## The shared stream for one layer, generated on first use. "thump",
## "clack_up" and "clack_down" are variant 0; "thump3" etc. pick a variant.
static func stream(layer: String) -> AudioStreamWAV:
	if not _streams.has(layer):
		_streams[layer] = AudioDsp.cached("res://scripts/driveline_audio.gd", layer, _clack.bind(layer) if layer.begins_with("clack") else _make.bind(layer))
	return _streams[layer]

## Every variant of a shift layer, picked at random per shift.
static func variants(layer: String) -> AudioStreamRandomizer:
	var list: Array[AudioStream] = []
	for k in VARIANTS:
		list.append(stream(layer if k == 0 else "%s%d" % [layer, k]))
	return AudioDsp.randomizer(list, 1.06, 1.5)

## A gearbox clack: a click and the ring of hard steel, over a knock. Upshifts
## sit lower and knock harder (into a taller gear); downshifts are brighter.
static func _clack(layer: String) -> AudioStreamWAV:
	var r := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layer)
	var up := layer.begins_with("clack_up")
	var lift := 1.0 if up else 1.3
	var n := int(0.16 * r)
	var res: Array[AudioDsp.Biquad] = [
		AudioDsp.bp(r, rng.randf_range(1600.0, 2200.0) * lift, 25.0),
		AudioDsp.bp(r, rng.randf_range(2700.0, 3400.0) * lift, 25.0),
		AudioDsp.bp(r, rng.randf_range(4100.0, 4600.0) * minf(lift, 1.15), 28.0),
	]
	var knock_hz := rng.randf_range(200.0, 260.0) * (1.0 if up else 1.2)
	var knock := 1.0 if up else 0.55
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / r
		var w := rng.randf_range(-1.0, 1.0)
		var click := w * exp(-t * 900.0)
		var ring := 0.0
		for f in res:
			ring += f.step(click)
		s[i] = ring * 6.0 * exp(-t * 45.0) + click * 0.5 + knock * sin(TAU * knock_hz * t) * exp(-t * 35.0)
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.9), MIX_RATE, false)

static func _make(layer: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# thump1..thump4: other seeds and a slightly different body note
	var variant := 0
	if layer.begins_with("thump") and layer.length() > 5:
		variant = int(layer.substr(5))
		rng.seed = 11 + variant * 97
		layer = "thump"
	var thump_hz: float = 55.0 * [1.0, 0.92, 1.08, 0.96, 1.05][variant]
	var secs := 0.2
	match layer:
		"whine": secs = 0.5     # 0.5 s of WHINE_BASE_HZ: 200 whole cycles, so it loops cleanly
		"thump": secs = 0.22
		"clunk": secs = 0.12
		"landing": secs = 0.35
	var n := int(secs * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := 1.0
		var s := 0.0
		match layer:
			"whine":
				s = sin(TAU * WHINE_BASE_HZ * t) * 0.8 + sin(TAU * WHINE_BASE_HZ * 2.0 * t) * 0.25
			"thump":
				env = exp(-t * 22.0)
				lp += 0.08 * (rng.randf_range(-1.0, 1.0) - lp)
				s = sin(TAU * thump_hz * t) * 0.9 + lp * 1.5
			"clunk":
				env = exp(-t * 45.0)
				lp += 0.35 * (rng.randf_range(-1.0, 1.0) - lp)
				s = (rng.randf_range(-1.0, 1.0) - lp) * 0.7 + sin(TAU * 140.0 * t) * 0.6
			"landing":
				env = exp(-t * 13.0)
				lp += 0.05 * (rng.randf_range(-1.0, 1.0) - lp)
				s = sin(TAU * 42.0 * t) * 0.9 + lp * 1.8
		samples[i] = s * env
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if layer == "whine":
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav
