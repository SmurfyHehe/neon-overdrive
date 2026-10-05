extends Node
class_name DrivelineAudio

# Driveline and chassis sounds (Phase B, 2026-10-05), next to EngineAudio and
# CarAudio on a Vehicle. Like them: generated in code, no files, no licences,
# reads GEVP state, never touches physics. Every level is a starting value for
# Roy to judge by ear.
#
# - gear whine: a tone at the gear-mesh rate (follows engine rpm), louder under
#   load and in the lower gears, fading in with speed (Engine bus);
# - shift thump: a low thud each time a gear change completes (Engine bus);
# - driveline clunk: a short clack when the throttle is lifted or put back on at
#   speed, the lash in the driveline taking up (Engine bus);
# - landing thud: when the wheels touch down after airtime, scaled by how fast
#   the car was falling (Tires bus).
# thump_count, clunk_count and landing_count rise on each event so tests (which
# run with the silent Dummy audio driver) can assert on state, not on sound.

const MIX_RATE := 22050
const WHINE_BASE_HZ := 400.0
const WHINE_TEETH := 8.0          # gear-mesh rate = engine rev/s x this (about 930 Hz at 7000 rpm)
const WHINE_GAIN := 0.10
const THUMP_GAIN := 0.5
const CLUNK_GAIN := 0.35
const LANDING_GAIN := 0.7
const CLUNK_COOLDOWN := 0.35      # s
const AIR_MIN := 0.15             # s of airtime before a touchdown counts as a landing
const ATTACK := 12.0
const RELEASE := 6.0

var whine_level := 0.0
var thump_count := 0
var clunk_count := 0
var landing_count := 0

static var _streams := {}

var _vehicle: Vehicle
var _whine: AudioStreamPlayer
var _thump: AudioStreamPlayer
var _clunk: AudioStreamPlayer
var _landing: AudioStreamPlayer
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
	_clunk = _add_player("clunk", &"Engine", false)
	_landing = _add_player("landing", &"Tires", false)
	_last_gear = _vehicle.current_gear

func _add_player(layer: String, bus_name: StringName, looping: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = layer.capitalize() + "Audio"
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
			thump_count += 1
			_one_shot(_thump, THUMP_GAIN * clampf(v.speed / 25.0, 0.3, 1.0))
		_last_gear = v.current_gear

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

func _one_shot(p: AudioStreamPlayer, gain: float) -> void:
	p.volume_db = linear_to_db(clampf(gain, 0.001, 1.0))
	p.play()

## The shared stream for one layer, generated on first use.
static func stream(layer: String) -> AudioStreamWAV:
	if not _streams.has(layer):
		_streams[layer] = _make(layer)
	return _streams[layer]

static func _make(layer: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
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
				s = sin(TAU * 55.0 * t) * 0.9 + lp * 1.5
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
