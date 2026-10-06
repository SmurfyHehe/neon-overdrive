extends Node
class_name CarAudio

# Speed-scaled wind, road and tyre sound (stage A, 2026-10-04). Sits next to
# EngineAudio on a Vehicle and reads its GEVP state every frame; audio stays
# out of the physics code, same as the engine.
#
# Four looping layers, each generated once from noise in code (no audio
# files, nothing to license) and shared by every car:
# - wind:    rushing air, louder and brighter with speed (World bus);
# - road:    the low roar of tyres rolling on asphalt, with speed (Tires bus);
# - squeal:  tyre squeal from real slip -- slide angle or wheelspin/lock --
#            weighted by how much load that tyre carries (Tires bus);
# - surface: kerb/sidewalk rumble while wheels are on the "Dirt" surface;
#            pitch, and so the rumble rate, follows speed (Tires bus).
# Volume and pitch move every frame through AudioStreamPlayer, so the mixing
# itself is engine code, not GDScript. Every curve is a starting value for
# Roy to judge by ear.

const MIX_RATE := 22050
const LOOP_SECS := 2.0
const FADE_SECS := 0.15  # crossfade baked into each loop so the seam is silent

# Speed curves, m/s.
const WIND_FULL := 68.0   # wind reaches full level here (68 m/s = 245 km/h, top speed)
const WIND_EXP := 1.5     # level = (v / WIND_FULL)^WIND_EXP. Was v^2 up to 45 m/s; a gentler exponent keeps everyday speeds from going quiet on the longer range.
const ROAD_FULL := 40.0
const SURFACE_FULL := 20.0

# Slip that starts / saturates the squeal. Lateral is the tyre's slide angle
# in radians (GEVP slip_vector.x), longitudinal its slip ratio (slip_vector.y).
const LAT_START := 0.10
const LAT_FULL := 0.35
const LON_START := 0.18
const LON_FULL := 0.6

# Peak gains per layer (linear) -- the mix against the engine (gain 0.5).
const WIND_GAIN := 0.55
const ROAD_GAIN := 0.45
const SQUEAL_GAIN := 0.5
const SURFACE_GAIN := 0.6

const SQUEAL_PARTIALS := [[820.0, 1.0], [1290.0, 0.55], [1910.0, 0.3]]  # Hz, gain
const SQUEAL_Q := 22.0  # resonator sharpness: higher = more tonal, lower = more hiss

const ATTACK := 18.0  # 1/s, how fast a layer rises
const RELEASE := 7.0  # 1/s, how fast it falls

# Current levels (0..1 before gain), readable by tests and a future HUD.
var wind_level := 0.0
var road_level := 0.0
var squeal_level := 0.0
var surface_level := 0.0

static var _streams := {}

var _vehicle: Vehicle
var _players := {}

func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	if _vehicle == null:
		push_error("CarAudio must be a child of a Vehicle")
		set_process(false)
		return
	_players.wind = _add_player("wind", &"World")
	_players.road = _add_player("road", &"Tires")
	_players.squeal = _add_player("squeal", &"Tires")
	_players.surface = _add_player("surface", &"Tires")

func _add_player(layer: String, bus_name: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = layer.capitalize() + "Audio"
	p.stream = stream(layer)
	p.bus = bus_name
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p

func _process(delta: float) -> void:
	var speed := _vehicle.speed  # GEVP: length of the body's local velocity
	var grounded := 0
	var rough := 0
	var slip := 0.0
	var static_load := _vehicle.mass * 9.81 / 4.0
	for w in _vehicle.wheel_array:
		if not w.is_colliding():
			continue
		grounded += 1
		if w.surface_type != "Road":
			rough += 1
			continue
		var lat := smoothstep(LAT_START, LAT_FULL, absf(w.slip_vector.x))
		var lon := smoothstep(LON_START, LON_FULL, absf(w.slip_vector.y))
		var load := clampf(w.spring_force / static_load, 0.0, 1.5)
		slip = maxf(slip, maxf(lat, lon) * minf(load, 1.0))
	var on_road := float(grounded - rough) / 4.0
	var on_rough := float(rough) / 4.0

	wind_level = _approach(wind_level, minf(1.0, pow(speed / WIND_FULL, WIND_EXP)), delta)
	road_level = _approach(road_level, pow(clampf(speed / ROAD_FULL, 0.0, 1.0), 1.2) * on_road, delta)
	# A tyre sliding at walking pace doesn't scream; fade squeal in by 3 m/s
	# unless the wheel itself is spinning (a burnout squeals standing still).
	var spinning := absf(_vehicle.get_drivetrain_spin() * _vehicle.average_drive_wheel_radius) > 3.0
	var squeal_gate := 1.0 if spinning else clampf(speed / 3.0, 0.0, 1.0)
	squeal_level = _approach(squeal_level, slip * squeal_gate, delta)
	surface_level = _approach(surface_level, on_rough * clampf(speed / SURFACE_FULL, 0.0, 1.0), delta)

	_drive_layer(_players.wind, wind_level * WIND_GAIN, 0.55 + 0.9 * clampf(speed / 50.0, 0.0, 1.3))
	_drive_layer(_players.road, road_level * ROAD_GAIN, 0.6 + 0.8 * clampf(speed / 45.0, 0.0, 1.2))
	_drive_layer(_players.squeal, squeal_level * SQUEAL_GAIN, 0.85 + 0.25 * squeal_level + 0.1 * clampf(speed / 40.0, 0.0, 1.0))
	_drive_layer(_players.surface, surface_level * SURFACE_GAIN, 0.5 + clampf(speed / 30.0, 0.0, 1.5))

func _approach(current: float, target: float, delta: float) -> float:
	var rate := ATTACK if target > current else RELEASE
	return lerpf(current, target, 1.0 - exp(-rate * delta))

func _drive_layer(p: AudioStreamPlayer, amplitude: float, pitch: float) -> void:
	p.volume_db = linear_to_db(amplitude) if amplitude > 0.0005 else -80.0
	p.pitch_scale = pitch

## The shared loop for one layer, generated on first use.
static func stream(layer: String) -> AudioStreamWAV:
	if not _streams.has(layer):
		_streams[layer] = _make_loop(layer)
	return _streams[layer]

## Builds LOOP_SECS of mono 16-bit audio for a layer. Each layer is its own
## small recipe over white noise; the tail is crossfaded into the head so the
## loop point can't click.
static func _make_loop(layer: String) -> AudioStreamWAV:
	var n := int(LOOP_SECS * MIX_RATE)
	var fade := int(FADE_SECS * MIX_RATE)
	var total := n + fade
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layer)
	var s := PackedFloat32Array()
	s.resize(total)
	var lp1 := 0.0
	var lp2 := 0.0
	var brown := 0.0
	# Band-pass resonators for the squeal: [b0, a1, a2, x2, y1, y2, x1] each
	# (RBJ constant-skirt band-pass, the same form EngineSynth uses).
	var res: Array[PackedFloat32Array] = []
	for k in 3:
		var w0 := TAU * float(SQUEAL_PARTIALS[k][0]) / MIX_RATE
		var alpha := sin(w0) / (2.0 * SQUEAL_Q)
		res.append(PackedFloat32Array([alpha / (1.0 + alpha), -2.0 * cos(w0) / (1.0 + alpha), (1.0 - alpha) / (1.0 + alpha), 0.0, 0.0, 0.0, 0.0]))
	for i in total:
		var white := rng.randf_range(-1.0, 1.0)
		var t := float(i) / MIX_RATE
		var v := 0.0
		match layer:
			"wind":
				# pinkish rush: two one-pole low-passes (~1.6 kHz, ~600 Hz) mixed,
				# with a slow swell so it breathes instead of hissing flat
				lp1 += 0.36 * (white - lp1)
				lp2 += 0.16 * (white - lp2)
				v = (0.6 * lp1 + 0.9 * lp2) * (0.8 + 0.2 * sin(TAU * 0.5 * t))
			"road":
				# brown noise: low rumble, then a low-pass to take the edge off
				brown = clampf(brown * 0.995 + white * 0.08, -1.0, 1.0)
				lp1 += 0.12 * (brown - lp1)
				v = lp1 * 2.2
			"squeal":
				# rubber stick-slip: noise rung through three narrow resonators
				# (a noisy screech with a pitch centre, not pure synth tones),
				# with a fast shudder on top
				for k in 3:
					var c: PackedFloat32Array = res[k]
					var y := c[0] * white - c[0] * c[3] - c[1] * c[4] - c[2] * c[5]
					c[3] = c[6]
					c[6] = white
					c[5] = c[4]
					c[4] = y
					res[k] = c  # packed arrays are copy-on-write: store the new state
					v += SQUEAL_PARTIALS[k][1] * y
				v *= 0.75 + 0.25 * sin(TAU * 23.0 * t)
			"surface":
				# rumble strip: noise gated in ~32 Hz bursts, plus some grit
				lp1 += 0.25 * (white - lp1)
				var gate := 1.0 if fmod(t * 32.0, 1.0) < 0.45 else 0.25
				v = lp1 * gate * 1.6 + white * 0.08
		s[i] = v
	# Crossfade the extra tail into the head, then drop the tail.
	for i in fade:
		var k := float(i) / fade
		s[i] = s[i] * k + s[n + i] * (1.0 - k)
	s.resize(n)
	# Normalise to a 0.8 peak so every layer starts from the same loudness.
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	var g := 0.8 / peak if peak > 0.0 else 0.0
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(s[i] * g, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav
