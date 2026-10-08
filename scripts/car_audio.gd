extends Node
class_name CarAudio

# Speed-scaled wind, road and tyre sound. Sits next to EngineAudio on a Vehicle
# and reads its GEVP state every frame; audio stays out of the physics code,
# same as the engine. Stage A (2026-10-04); rebuilt 2026-10-08 after Roy found
# the tyres, wind and road thin (docs/planning/sound-research-2026-10-08.md 1b).
#
# Every loop is generated once in code (AudioDsp, no files, nothing to license)
# and shared by every car:
# - tyres: four kinds, picked per wheel from what the physics reports --
#     scrub   (moderate sideways slip: understeer, a car pushing wide),
#     squeal  (big sideways slip: a drift or a slide),
#     spin    (the wheel turning faster than the road: launch, burnout),
#     lock    (the wheel turning slower: locked brakes, the handbrake).
#   Each kind has a left and a right player, built from two different takes of
#   different lengths, so a slide on the left is heard on the left and the two
#   loops never line up into an audible repeat. A short chirp fires when
#   wheelspin snaps on (launches, hard shifts).
# - road: two rolling loops, dark and bright. Speed raises the level and fades
#   towards the bright one -- the filter opens -- instead of pitching one loop
#   up like a tape speeding up.
# - wind: a low buffet and a brighter rush, both louder with speed, the rush
#   taking over as speed climbs; slow random gusts; a mirror whistle above
#   about 150 km/h. Pitch barely moves.
# - surface: kerb/sidewalk rumble on the "Dirt" surface.
# - cabin: PerspectiveAudio feeds `cabin` (0 chase .. 1 cockpit) and `window`
#   (0 closed .. 1 open). In the cockpit with the window up the wind is a
#   sealed hush plus a seal whistle at speed; cracked open, the low "throb" a
#   real car makes; fully open, the full buffet. The chase view is always
#   outside sound.
# Volume and pitch move every frame through AudioStreamPlayer, so the mixing
# itself is engine code, not GDScript. Every curve is a starting value for Roy
# to judge by ear (the listen pack: tests/sound_listen_pack.gd).

const MIX_RATE := 32000
const LOOP_SECS := 2.0
const FADE_SECS := 0.15  # crossfade baked into each loop so the seam is silent
const TAKE_B_SECS := 2.6 # the right-hand tyre take: a different length, so L and R drift apart

# Speed curves, m/s.
const WIND_FULL := 68.0   # wind reaches full level here (68 m/s = 245 km/h, top speed)
const WIND_EXP := 1.5     # level = (v / WIND_FULL)^WIND_EXP
const ROAD_FULL := 40.0
const SURFACE_FULL := 20.0
const WHISTLE_FROM := 38.0  # m/s (137 km/h): the mirror whistle starts
const WHISTLE_FULL := 62.0

# Tyre kinds. Lateral is the tyre's slide angle in radians (GEVP
# slip_vector.x); longitudinal is its slip ratio (slip_vector.y): positive when
# the wheel turns slower than the road (braking, locked), negative when faster
# (wheelspin).
const SCRUB_START := 0.06
const SCRUB_FULL := 0.16
const SQUEAL_START := 0.14
const SQUEAL_FULL := 0.38
const SPIN_START := 0.15
const SPIN_FULL := 0.5
const LOCK_START := 0.2
const LOCK_FULL := 0.6
const KINDS := ["scrub", "squeal", "spin", "lock"]
# Stage A's single-squeal thresholds. Skid marks (skid_marks.gd) still start
# from these, so they are kept as they were.
const LAT_START := 0.10
const LAT_FULL := 0.35
const LON_START := 0.18
const LON_FULL := 0.6

# Peak gains per layer (linear) -- the mix against the engine (gain 0.5).
const TYRE_GAIN := {"scrub": 0.32, "squeal": 0.5, "spin": 0.5, "lock": 0.42}
const CHIRP_GAIN := 0.45
const BUFFET_GAIN := 1.0
const RUSH_GAIN := 0.8
const WHISTLE_GAIN := 0.16
const THROB_GAIN := 0.4
const ROAD_GAIN := 0.45
const SURFACE_GAIN := 0.6

# Cabin: how much of the outside wind gets in with the window up, and how much
# louder the buffet is with it fully down (the opening is next to your ear).
const SEALED_WIND := 0.18
const OPEN_BUFFET := 2.6

const ATTACK := 18.0  # 1/s, how fast a layer rises
const RELEASE := 7.0  # 1/s, how fast it falls
const CHIRP_COOLDOWN := 0.5

# Current levels (0..1 before gain), readable by tests and a future HUD.
var wind_level := 0.0
var road_level := 0.0
var squeal_level := 0.0  # all tyre noise together: the loudest kind on either side
var surface_level := 0.0
var whistle_level := 0.0
var throb_level := 0.0
var gust := 1.0
var tyre := {}           # kind -> [left, right] level, 0..1
var chirp_count := 0

# Set by PerspectiveAudio every frame: 0 chase .. 1 cockpit, and the window.
var cabin := 0.0
var window := 0.0

## Listen pack and tests: keys here replace what the car reports
## ("speed", "on_road", "on_rough", and per kind "<kind>_l" / "<kind>_r").
var forced := {}

static var _streams := {}

var _vehicle: Vehicle
var _players := {}
var _rng := RandomNumberGenerator.new()
var _gust_target := 1.0
var _gust_wait := 0.0
var _chirp_wait := 0.0
var _spin_prev := 0.0

func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	if _vehicle == null:
		push_error("CarAudio must be a child of a Vehicle")
		set_process(false)
		return
	_rng.seed = 4242
	for kind in KINDS:
		tyre[kind] = [0.0, 0.0]
		_players[kind + "_l"] = _add_player(kind + "_l", &"Tires")
		_players[kind + "_r"] = _add_player(kind + "_r", &"Tires")
	_players.buffet = _add_player("buffet", &"World")
	_players.rush = _add_player("rush", &"World")
	_players.whistle = _add_player("whistle", &"World")
	_players.throb = _add_player("throb", &"World")
	_players.road_dark = _add_player("road_dark", &"Tires")
	_players.road_bright = _add_player("road_bright", &"Tires")
	_players.surface = _add_player("surface", &"Tires")
	_players.chirp = _add_player("chirp", &"Tires", false)

func _add_player(layer: String, bus_name: StringName, looping := true) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = layer.to_pascal_case() + "Audio"
	p.stream = stream(layer)
	p.bus = bus_name
	p.volume_db = -80.0
	add_child(p)
	if looping:
		p.play()
	return p

## What the car is doing this frame, as plain numbers (so the listen pack can
## set them directly).
func _read_car() -> Dictionary:
	var st := {"speed": 0.0, "on_road": 0.0, "on_rough": 0.0}
	for kind in KINDS:
		st[kind + "_l"] = 0.0
		st[kind + "_r"] = 0.0
	if _vehicle == null:
		return st
	st.speed = _vehicle.speed  # GEVP: length of the body's local velocity
	var grounded := 0
	var rough := 0
	var static_load := _vehicle.mass * 9.81 / 4.0
	for w in _vehicle.wheel_array:
		if not w.is_colliding():
			continue
		grounded += 1
		if w.surface_type != "Road":
			rough += 1
			continue
		var side := "_l" if _vehicle.to_local(w.global_position).x < 0.0 else "_r"
		var load := minf(clampf(w.spring_force / static_load, 0.0, 1.5), 1.0)
		var lat := absf(w.slip_vector.x)
		var lon := w.slip_vector.y
		var amounts := {
			# scrub fades out as the slide grows into a squeal
			"scrub": smoothstep(SCRUB_START, SCRUB_FULL, lat) * (1.0 - 0.8 * smoothstep(SQUEAL_START, SQUEAL_FULL, lat)),
			"squeal": smoothstep(SQUEAL_START, SQUEAL_FULL, lat),
			"spin": smoothstep(SPIN_START, SPIN_FULL, -lon),
			"lock": smoothstep(LOCK_START, LOCK_FULL, lon),
		}
		for kind in KINDS:
			st[kind + side] = maxf(st[kind + side], amounts[kind] * load)
	st.on_road = float(grounded - rough) / 4.0
	st.on_rough = float(rough) / 4.0
	return st

func _process(delta: float) -> void:
	var st := _read_car()
	for k in forced:
		st[k] = forced[k]
	var speed: float = st.speed

	wind_level = _approach(wind_level, minf(1.0, pow(speed / WIND_FULL, WIND_EXP)), delta)
	road_level = _approach(road_level, pow(clampf(speed / ROAD_FULL, 0.0, 1.0), 1.2) * st.on_road, delta)
	surface_level = _approach(surface_level, st.on_rough * clampf(speed / SURFACE_FULL, 0.0, 1.0), delta)

	# --- tyres. A tyre sliding at walking pace doesn't scream: fade the sliding
	# kinds in by 3 m/s. Wheelspin needs no gate (a burnout squeals standing still).
	var slide_gate := clampf(speed / 3.0, 0.0, 1.0)
	squeal_level = 0.0
	var spin_now := 0.0
	for kind in KINDS:
		var gate := 1.0 if kind == "spin" else slide_gate
		var lv: Array = tyre[kind]
		lv[0] = _approach(lv[0], st[kind + "_l"] * gate, delta)
		lv[1] = _approach(lv[1], st[kind + "_r"] * gate, delta)
		squeal_level = maxf(squeal_level, maxf(lv[0], lv[1]))
		var pitch := _tyre_pitch(kind, maxf(lv[0], lv[1]), speed)
		_drive_layer(_players[kind + "_l"], lv[0] * TYRE_GAIN[kind], pitch)
		_drive_layer(_players[kind + "_r"], lv[1] * TYRE_GAIN[kind], pitch * 1.01)
		if kind == "spin":
			spin_now = maxf(st.spin_l, st.spin_r)
	# Chirp: wheelspin snapping on (a launch, a hard shift).
	_chirp_wait = maxf(_chirp_wait - delta, 0.0)
	if spin_now > 0.5 and _spin_prev < 0.15 and _chirp_wait <= 0.0:
		chirp_count += 1
		_chirp_wait = CHIRP_COOLDOWN
		var c: AudioStreamPlayer = _players.chirp
		c.volume_db = linear_to_db(CHIRP_GAIN)
		c.pitch_scale = 0.95 + _rng.randf() * 0.12
		c.play()
	_spin_prev = spin_now

	# --- road: louder and brighter, barely higher
	var bright := smoothstep(4.0, 45.0, speed)
	_drive_layer(_players.road_dark, road_level * ROAD_GAIN * (1.0 - 0.55 * bright), 0.92 + 0.1 * clampf(speed / 45.0, 0.0, 1.2))
	_drive_layer(_players.road_bright, road_level * ROAD_GAIN * bright, 0.94 + 0.1 * clampf(speed / 45.0, 0.0, 1.2))
	_drive_layer(_players.surface, surface_level * SURFACE_GAIN, 0.5 + clampf(speed / 30.0, 0.0, 1.5))

	# --- wind
	_update_gust(speed, delta)
	var opening := pow(window, 0.7)
	var inside := lerpf(1.0, SEALED_WIND + (1.0 - SEALED_WIND) * opening, cabin)  # how much outside wind reaches you
	var buffet_boost := lerpf(1.0, lerpf(1.0, OPEN_BUFFET, opening), cabin)
	var rush_mix := smoothstep(6.0, 55.0, speed)  # the filter opening: rush takes over with speed
	var outside_whistle := smoothstep(WHISTLE_FROM, WHISTLE_FULL, speed)
	var seal_whistle := cabin * (1.0 - smoothstep(0.0, 0.1, window)) * smoothstep(25.0, 45.0, speed) * 0.7
	whistle_level = maxf(outside_whistle * inside, seal_whistle)
	# Throb: loudest with the window just cracked, gone when closed or fully down.
	var crack := smoothstep(0.02, 0.12, window) * (1.0 - smoothstep(0.3, 0.65, window))
	throb_level = _approach(throb_level, cabin * crack * smoothstep(10.0, 30.0, speed), delta)
	var wind_pitch := 0.96 + 0.08 * clampf(speed / WIND_FULL, 0.0, 1.2)
	_drive_layer(_players.buffet, pow(wind_level, 0.8) * gust * inside * buffet_boost * BUFFET_GAIN * (1.0 - 0.35 * rush_mix), wind_pitch)
	_drive_layer(_players.rush, wind_level * (0.6 + 0.4 * gust) * inside * lerpf(1.0, buffet_boost, 0.6) * RUSH_GAIN * (0.35 + 0.65 * rush_mix), wind_pitch)
	_drive_layer(_players.whistle, whistle_level * gust * WHISTLE_GAIN, 0.97 + 0.12 * clampf((speed - WHISTLE_FROM) / 30.0, 0.0, 1.0))
	_drive_layer(_players.throb, throb_level * THROB_GAIN, 0.9 + 0.2 * clampf(speed / 50.0, 0.0, 1.0))

## Gusts: a slow random wander of the wind level, quicker and wider at speed.
func _update_gust(speed: float, delta: float) -> void:
	var depth := 0.3 * smoothstep(8.0, 50.0, speed)
	_gust_wait -= delta
	if _gust_wait <= 0.0:
		_gust_target = 1.0 + _rng.randf_range(-depth, depth)
		_gust_wait = _rng.randf_range(0.4, 1.6)
	gust = lerpf(gust, _gust_target, 1.0 - exp(-2.5 * delta))

static func _tyre_pitch(kind: String, level: float, speed: float) -> float:
	var v := clampf(speed / 40.0, 0.0, 1.2)
	match kind:
		"scrub":
			return 0.9 + 0.15 * v
		"squeal":
			return 0.88 + 0.2 * level + 0.08 * v
		"spin":
			return 0.85 + 0.3 * level + 0.1 * v
		_:  # lock
			return 0.9 + 0.12 * v
	return 1.0

func _approach(current: float, target: float, delta: float) -> float:
	var rate := ATTACK if target > current else RELEASE
	return lerpf(current, target, 1.0 - exp(-rate * delta))

func _drive_layer(p: AudioStreamPlayer, amplitude: float, pitch: float) -> void:
	p.volume_db = linear_to_db(amplitude) if amplitude > 0.0005 else -80.0
	p.pitch_scale = pitch

## The shared stream for one layer, generated on first use.
static func stream(layer: String) -> AudioStreamWAV:
	if not _streams.has(layer):
		_streams[layer] = AudioDsp.cached("res://scripts/car_audio.gd", layer, _make.bind(layer))
	return _streams[layer]

static func _make(layer: String) -> AudioStreamWAV:
	if layer == "chirp":
		return AudioDsp.to_wav(_chirp(), MIX_RATE, false)
	var parts := layer.split("_")
	if parts.size() == 2 and parts[0] in KINDS:
		# left player: take A; right player: take B (other seed, other length)
		var left := parts[1] == "l"
		var take := _loop(parts[0], hash(layer), LOOP_SECS if left else TAKE_B_SECS, 1.0 if left else 1.04)
		return AudioDsp.panned(take, MIX_RATE, -1 if left else 1)
	return AudioDsp.to_wav(_loop(layer, hash(layer), LOOP_SECS, 1.0), MIX_RATE, true)

## `secs` of one layer, looping seamlessly, peak 0.8. `tune` shifts a tyre
## take's centre frequency so the two sides are not the same note.
static func _loop(layer: String, seed: int, secs: float, tune: float) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var n := int(secs * r)
	var fade := int(FADE_SECS * r)
	var total := n + fade
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s := PackedFloat32Array()
	s.resize(total)
	match layer:
		"scrub":
			# rubber grinding across the road: broad bands, gated in irregular
			# stick-slip bursts
			var f1 := AudioDsp.bp(r, 420.0 * tune, 2.5)
			var f2 := AudioDsp.bp(r, 760.0 * tune, 3.0)
			var f3 := AudioDsp.bp(r, 1500.0 * tune, 4.0)
			var env := 0.0
			var wait := 0
			for i in total:
				var w := rng.randf_range(-1.0, 1.0)
				wait -= 1
				if wait <= 0:
					env = rng.randf_range(0.6, 1.0)
					wait = int(rng.randf_range(0.018, 0.032) * r)
				env *= 0.9985
				s[i] = (f1.step(w) + 0.7 * f2.step(w) + 0.3 * f3.step(w)) * (0.45 + 0.55 * env)
		"squeal":
			# the drift scream: a tonal core with its harmonics, wandering in
			# pitch, rung from noise so it stays rubbery, with a slow flutter
			var f0 := 1000.0 * tune
			var res := [AudioDsp.bp(r, f0, 30.0), AudioDsp.bp(r, f0 * 1.52, 30.0), AudioDsp.bp(r, f0 * 2.2, 26.0)]
			var gains := [1.0, 0.5, 0.28]
			var ph := 0.0
			var cur_f := f0
			var wander := 0.0
			var wander_to := 0.0
			for i in total:
				var t := float(i) / r
				if i % 64 == 0:
					if rng.randf() < 0.01:
						wander_to = rng.randf_range(-0.025, 0.025)
					wander = lerpf(wander, wander_to, 0.05)
					var f := f0 * (1.0 + 0.03 * sin(TAU * 0.6 * t + float(seed % 7)) + wander)
					(res[0] as AudioDsp.Biquad).set_bp(r, f, 30.0)
					(res[1] as AudioDsp.Biquad).set_bp(r, f * 1.52, 30.0)
					(res[2] as AudioDsp.Biquad).set_bp(r, f * 2.2, 26.0)
					cur_f = f
				ph = fmod(ph + TAU * cur_f / r, TAU)
				var w := rng.randf_range(-1.0, 1.0)
				var v := 0.0
				for k in 3:
					v += gains[k] * (res[k] as AudioDsp.Biquad).step(w)
				v += 0.012 * sin(ph)  # a hint of pure tone holds the pitch centre
				s[i] = v * (0.78 + 0.22 * sin(TAU * 17.0 * t) * sin(TAU * 1.3 * t))
		"spin":
			# wheelspin: higher and more frantic, a fast chatter with hiss on top
			var f0 := 1400.0 * tune
			var res := [AudioDsp.bp(r, f0, 16.0), AudioDsp.bp(r, f0 * 1.43, 16.0), AudioDsp.bp(r, f0 * 2.07, 14.0)]
			var gains := [1.0, 0.6, 0.35]
			var hiss := AudioDsp.hp(r, 3000.0)
			var chatter := 0.0
			for i in total:
				var t := float(i) / r
				if i % 32 == 0:
					chatter = 0.55 + 0.45 * signf(sin(TAU * 46.0 * t)) * rng.randf_range(0.5, 1.0)
				var w := rng.randf_range(-1.0, 1.0)
				var v := 0.0
				for k in 3:
					v += gains[k] * (res[k] as AudioDsp.Biquad).step(w)
				s[i] = v * chatter + 0.05 * hiss.step(w)
		"lock":
			# locked tyre: a lower, harsher groan with an ABS-like judder
			var f0 := 650.0 * tune
			var res := [AudioDsp.bp(r, f0, 9.0), AudioDsp.bp(r, f0 * 1.6, 9.0), AudioDsp.bp(r, f0 * 2.5, 8.0)]
			var gains := [1.0, 0.55, 0.3]
			var grind := AudioDsp.bp(r, 220.0, 2.0)
			for i in total:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				var v := 0.0
				for k in 3:
					v += gains[k] * (res[k] as AudioDsp.Biquad).step(w)
				var judder := 0.45 + 0.55 * absf(sin(TAU * 5.5 * t + 0.3 * sin(TAU * 0.9 * t)))
				s[i] = v * judder + 0.4 * grind.step(w)
		"buffet":
			# the low body of the wind: dark noise swelling in uneven waves
			var f1 := AudioDsp.lp(r, 180.0)
			var f2 := AudioDsp.lp(r, 70.0, 1.2)
			var phases := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
			for i in total:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				var swell := (sin(TAU * 0.9 * t + phases[0]) + 0.6 * sin(TAU * 1.7 * t + phases[1]) + 0.4 * sin(TAU * 2.9 * t + phases[2])) / 2.0
				s[i] = (f1.step(w) + 1.5 * f2.step(w)) * (0.62 + 0.38 * swell)
		"rush":
			# the bright air: two wide bands, breathing slowly
			var f1 := AudioDsp.bp(r, 900.0, 0.5)
			var f2 := AudioDsp.bp(r, 2500.0, 0.6)
			for i in total:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				s[i] = (0.7 * f1.step(w) + 0.5 * f2.step(w)) * (0.85 + 0.15 * sin(TAU * 0.5 * t))
		"whistle":
			# air past the mirrors and pillars: two narrow, drifting tones
			var f1 := AudioDsp.bp(r, 1250.0, 45.0)
			var f2 := AudioDsp.bp(r, 2480.0, 50.0)
			for i in total:
				var t := float(i) / r
				if i % 64 == 0:
					var drift := 1.0 + 0.02 * sin(TAU * 0.5 * t)
					f1.set_bp(r, 1250.0 * drift, 45.0)
					f2.set_bp(r, 2480.0 * drift, 50.0)
				var w := rng.randf_range(-1.0, 1.0)
				s[i] = (f1.step(w) + 0.5 * f2.step(w)) * (0.6 + 0.4 * sin(TAU * 1.0 * t))
		"throb":
			# a cracked window: low pressure pulsing about 7 times a second
			var f1 := AudioDsp.lp(r, 90.0, 1.0)
			for i in total:
				var t := float(i) / r
				var pulse := pow(0.5 + 0.5 * sin(TAU * 7.0 * t), 2.0)
				s[i] = (f1.step(rng.randf_range(-1.0, 1.0)) * 2.0 + 0.5 * sin(TAU * 55.0 * t)) * pulse
		"road_dark":
			# tyres rolling on asphalt, heard through the car: a low roar
			var brown := 0.0
			var f1 := AudioDsp.lp(r, 160.0)
			for i in total:
				brown = clampf(brown * 0.995 + rng.randf_range(-1.0, 1.0) * 0.08, -1.0, 1.0)
				s[i] = f1.step(brown)
		"road_bright":
			# the same roar with the filter open: more body and the tread's hiss
			var brown := 0.0
			var f1 := AudioDsp.lp(r, 420.0)
			var f2 := AudioDsp.bp(r, 1800.0, 0.8)
			for i in total:
				var w := rng.randf_range(-1.0, 1.0)
				brown = clampf(brown * 0.995 + w * 0.08, -1.0, 1.0)
				s[i] = 0.6 * f1.step(brown) + 0.08 * f2.step(w)
		"surface":
			# rumble strip: noise gated in ~32 Hz bursts, plus some grit
			var lp1 := 0.0
			for i in total:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				lp1 += 0.18 * (w - lp1)
				var gate := 1.0 if fmod(t * 32.0, 1.0) < 0.45 else 0.25
				s[i] = lp1 * gate * 1.6 + w * 0.06
	return AudioDsp.normalise(AudioDsp.seamless(s, n, fade))

## A short squeal that dies away: one chirp of rubber.
static func _chirp() -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var n := int(0.18 * r)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var f1 := AudioDsp.bp(r, 1300.0, 20.0)
	var f2 := AudioDsp.bp(r, 1980.0, 20.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / r
		if i % 64 == 0:
			var f := lerpf(1300.0, 1080.0, t / 0.18)
			f1.set_bp(r, f, 20.0)
			f2.set_bp(r, f * 1.52, 20.0)
		var w := rng.randf_range(-1.0, 1.0)
		var env := minf(t / 0.006, 1.0) * exp(-t * 16.0)
		s[i] = (f1.step(w) + 0.5 * f2.step(w)) * env
	return AudioDsp.normalise(s)
