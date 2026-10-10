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
# - surface: kerb/sidewalk rumble on the "Kerb" surface.
# - cabin: PerspectiveAudio feeds `cabin` (0 chase .. 1 cockpit) and `window`
#   (0 closed .. 1 open). In the cockpit with the window up the wind is a
#   sealed hush plus a seal whistle at speed; cracked open, the low "throb" a
#   real car makes; fully open, the full buffet. The chase view is always
#   outside sound.
# - buffeting (2026-10-09, Roy: "wind buffeting that grows as the window opens
#   at speed"): a low pressure flutter in the cabin, louder the further the
#   window is down and the faster you go, pulsing quicker with speed. Gone with
#   the window up and in the chase view. The cracked-window throb now keeps
#   growing up to motorway speed too.
# - no audible repeat (Roy, 2026-10-08: "multiple sounds for things that are
#   repetitive"): every continuous layer (wind buffet, rush, whistle, both
#   road loops) plays as two takes of different lengths and seeds, a hair
#   apart in pitch, so their sum never repeats; the chirp is five variants
#   picked at random with pitch and volume jitter.
# - road features (2026-10-08, Roy's small ideas): highway joints -- a da-dum
#   (front axle, then rear) every JOINT_SPACING metres that speeds up with the
#   car; a metal hum on bridge decks; a clank over manhole covers. Joints and
#   covers also nudge the chase camera (road_bump). Bridges, decks and covers
#   come from SoundZone markers the road will place; joints play on the whole
#   road for now (JOINTS_EVERYWHERE), since all of it is highway.
# Volume and pitch move every frame through AudioStreamPlayer, so the mixing
# itself is engine code, not GDScript. Every curve is a starting value for Roy
# to judge by ear (the listen pack: tests/audio/sound_listen_pack.gd).

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
## Continuous layers played as two takes (A, and "_b" of TAKE_B_SECS).
const PAIRED := ["buffet", "rush", "whistle", "road_dark", "road_bright", "flutter"]
const CHIRP_VARIANTS := 5

# Road features.
const JOINT_SPACING := 15.0       # m between expansion joints (a concrete slab)
const JOINTS_EVERYWHERE := true   # the whole road is highway for now; false = only in CONCRETE zones
const JOINT_GAIN := 0.35
const MANHOLE_GAIN := 0.55
const DECK_GAIN := 0.45
const ROAD_VARIANTS := 5

## A joint or a manhole under a wheel, 0..1: the chase camera kicks a little.
signal road_bump(strength: float)
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
const FLUTTER_GAIN := 0.55
const ROAD_GAIN := 0.45
const SURFACE_GAIN := 0.6

# Cabin: how much of the outside wind gets in with the window up, and how much
# louder the buffet is with it fully down (the opening is next to your ear).
const SEALED_WIND := 0.18
const OPEN_BUFFET := 2.6
# Buffeting and throb grow with speed between these (m/s).
const BUFFETING_FROM := 8.0
const BUFFETING_FULL := 55.0

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
var buffeting_level := 0.0
var gust := 1.0
var tyre := {}           # kind -> [left, right] level, 0..1
var chirp_count := 0
var joint_count := 0       # every axle crossing, so a da-dum counts 2
var manhole_count := 0
var deck_level := 0.0
var odometer := 0.0        # m driven, for the joint spacing

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
var _wheelbase := 2.6
var _on_cover := {}        # wheel index -> on a manhole last frame

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
	for layer in PAIRED:
		var bus := &"Tires" if layer.begins_with("road") else &"World"
		_players[layer] = _add_player(layer, bus)
		_players[layer + "_b"] = _add_player(layer + "_b", bus)
	_players.throb = _add_player("throb", &"World")
	_players.surface = _add_player("surface", &"Tires")
	_players.chirp = _add_player("chirp", &"Tires", false)
	var chirps: Array[AudioStream] = []
	for k in CHIRP_VARIANTS:
		chirps.append(stream("chirp" if k == 0 else "chirp%d" % k))
	_players.chirp.stream = AudioDsp.randomizer(chirps, 1.08, 2.0)
	for layer in ["joint", "manhole"]:
		var list: Array[AudioStream] = []
		for k in ROAD_VARIANTS:
			list.append(stream("%s%d" % [layer, k]))
		var p := _add_player(layer, &"Tires", false)
		p.stream = AudioDsp.randomizer(list, 1.06, 1.5)
		p.max_polyphony = 4
		_players[layer] = p
	_players.deck = _add_player("deck", &"Tires")
	if _vehicle != null:
		_wheelbase = maxf(1.5, absf(_vehicle.front_axle_position.z - _vehicle.rear_axle_position.z))

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
	var st := {"speed": 0.0, "on_road": 0.0, "on_rough": 0.0, "deck": 0.0, "concrete": 0.0}
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
	var here := _vehicle.global_position
	st.deck = 1.0 if SoundZone.find(SoundZone.Kind.BRIDGE_DECK, here) != null else 0.0
	st.concrete = 1.0 if JOINTS_EVERYWHERE or SoundZone.find(SoundZone.Kind.CONCRETE, here) != null else 0.0
	for i in _vehicle.wheel_array.size():
		var w: Wheel = _vehicle.wheel_array[i]
		var on := w.is_colliding() and SoundZone.find(SoundZone.Kind.MANHOLE, w.get_collision_point()) != null
		if on and not _on_cover.get(i, false):
			hit_manhole(st.speed)
		_on_cover[i] = on
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
		c.play()
	_spin_prev = spin_now

	# --- road: louder and brighter, barely higher
	var bright := smoothstep(4.0, 45.0, speed)
	_drive_pair("road_dark", road_level * ROAD_GAIN * (1.0 - 0.55 * bright), 0.92 + 0.1 * clampf(speed / 45.0, 0.0, 1.2))
	_drive_pair("road_bright", road_level * ROAD_GAIN * bright, 0.94 + 0.1 * clampf(speed / 45.0, 0.0, 1.2))
	_drive_layer(_players.surface, surface_level * SURFACE_GAIN, 0.5 + clampf(speed / 30.0, 0.0, 1.5))
	_road_features(st, speed, delta)

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
	var at_speed := smoothstep(BUFFETING_FROM, BUFFETING_FULL, speed)
	throb_level = _approach(throb_level, cabin * crack * at_speed, delta)
	# Buffeting: grows with how far down the window is, times speed.
	buffeting_level = _approach(buffeting_level, cabin * pow(window, 0.8) * at_speed, delta)
	var wind_pitch := 0.96 + 0.08 * clampf(speed / WIND_FULL, 0.0, 1.2)
	_drive_pair("buffet", pow(wind_level, 0.8) * gust * inside * buffet_boost * BUFFET_GAIN * (1.0 - 0.35 * rush_mix), wind_pitch)
	_drive_pair("rush", wind_level * (0.6 + 0.4 * gust) * inside * lerpf(1.0, buffet_boost, 0.6) * RUSH_GAIN * (0.35 + 0.65 * rush_mix), wind_pitch)
	_drive_pair("whistle", whistle_level * gust * WHISTLE_GAIN, 0.97 + 0.12 * clampf((speed - WHISTLE_FROM) / 30.0, 0.0, 1.0))
	_drive_layer(_players.throb, throb_level * THROB_GAIN, 0.9 + 0.2 * clampf(speed / 50.0, 0.0, 1.0))
	# the flutter pulses faster as the air speeds up past the opening
	_drive_pair("flutter", buffeting_level * gust * FLUTTER_GAIN, 0.75 + 0.55 * clampf(speed / BUFFETING_FULL, 0.0, 1.0))

## Joints, bridge-deck hum.
func _road_features(st: Dictionary, speed: float, delta: float) -> void:
	var before := odometer
	odometer += speed * delta
	if st.on_road > 0.0 and st.concrete > 0.0 and speed > 1.0:
		var strength := smoothstep(2.0, 35.0, speed) * (0.55 + 0.45 * float(st.on_road))
		# front axle on the joint ("da"), then the rear one a wheelbase later ("dum")
		if floor(odometer / JOINT_SPACING) > floor(before / JOINT_SPACING):
			_joint(strength, 1.0)
		if floor((odometer - _wheelbase) / JOINT_SPACING) > floor((before - _wheelbase) / JOINT_SPACING):
			_joint(strength, 0.85)
	deck_level = _approach(deck_level, float(st.deck) * smoothstep(3.0, 30.0, speed), delta)
	_drive_layer(_players.deck, deck_level * DECK_GAIN, 0.6 + clampf(speed / 40.0, 0.0, 1.3))

func _joint(strength: float, pitch: float) -> void:
	joint_count += 1
	var p: AudioStreamPlayer = _players.joint
	p.volume_db = linear_to_db(maxf(JOINT_GAIN * strength, 0.001))
	p.pitch_scale = pitch
	p.play()
	road_bump.emit(strength * 0.5)

## One wheel over a manhole cover. Public for the listen pack and tests.
func hit_manhole(speed: float) -> void:
	if speed < 1.0:
		return
	manhole_count += 1
	var strength := smoothstep(1.0, 25.0, speed)
	var p: AudioStreamPlayer = _players.manhole
	p.volume_db = linear_to_db(maxf(MANHOLE_GAIN * (0.4 + 0.6 * strength), 0.001))
	p.play()
	road_bump.emit(strength * 0.8)

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

## A PAIRED layer: both takes at -3 dB each (uncorrelated noise, so the sum
## keeps the single loop's loudness), B a touch lower so they drift apart.
func _drive_pair(layer: String, amplitude: float, pitch: float) -> void:
	_drive_layer(_players[layer], amplitude * 0.71, pitch)
	_drive_layer(_players[layer + "_b"], amplitude * 0.71, pitch * 0.985)

func _drive_layer(p: AudioStreamPlayer, amplitude: float, pitch: float) -> void:
	p.volume_db = linear_to_db(amplitude) if amplitude > 0.0005 else -80.0
	p.pitch_scale = pitch

## The shared stream for one layer, generated on first use.
static func stream(layer: String) -> AudioStreamWAV:
	if not _streams.has(layer):
		_streams[layer] = AudioDsp.cached("res://scripts/audio/car_audio.gd", layer, _make.bind(layer))
	return _streams[layer]

static func _make(layer: String) -> AudioStreamWAV:
	if layer.begins_with("joint") or layer.begins_with("manhole"):
		return AudioDsp.to_wav(_road_hit(layer), MIX_RATE, false)
	if layer.begins_with("chirp"):
		return AudioDsp.to_wav(_chirp(hash(layer)), MIX_RATE, false)
	if layer.ends_with("_b") and layer.trim_suffix("_b") in PAIRED:
		return AudioDsp.to_wav(_loop(layer.trim_suffix("_b"), hash(layer), TAKE_B_SECS, 1.0), MIX_RATE, true)
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
		"deck":
			# tyres on a steel bridge deck: a buzzing hum from the grating,
			# with a rough metallic edge
			var f0 := 95.0
			var res := AudioDsp.bp(r, 520.0, 6.0)
			var ph := 0.0
			for i in total:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				ph = fmod(ph + TAU * f0 / r, TAU)
				var tone := sin(ph) + 0.6 * sin(2.0 * ph) + 0.4 * sin(3.0 * ph) + 0.25 * sin(5.0 * ph)
				s[i] = tone * (0.7 + 0.3 * absf(w)) * 0.5 + res.step(w) * 1.5 * (0.8 + 0.2 * sin(TAU * 3.0 * t))
		"flutter":
			# air pumping in and out of an open window: dark noise in uneven
			# pressure pulses, about 4 a second at pitch 1
			var f1 := AudioDsp.lp(r, 110.0, 1.1)
			var f2 := AudioDsp.bp(r, 240.0, 1.5)
			var ph := rng.randf() * TAU
			for i in total:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				var pulse := pow(0.5 + 0.5 * sin(TAU * 4.0 * t + ph + 0.8 * sin(TAU * 1.5 * t)), 1.6)
				s[i] = (2.2 * f1.step(w) + 0.5 * f2.step(w)) * (0.25 + 0.75 * pulse)
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
## A joint ("joint0".."joint4"): the tyre dropping into the gap -- a soft
## click -- and the slab thump under it. A manhole ("manhole0".."manhole4"):
## a heavier clank, the iron cover ringing and rattling once in its seat.
static func _road_hit(layer: String) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layer)
	var cover := layer.begins_with("manhole")
	var n := int((0.45 if cover else 0.22) * r)
	var s := PackedFloat32Array()
	s.resize(n)
	var thump_hz := rng.randf_range(65.0, 90.0) * (0.85 if cover else 1.0)
	var click := AudioDsp.bp(r, rng.randf_range(700.0, 1100.0), 2.0)
	var body := AudioDsp.lp(r, 250.0)
	var rings: Array[AudioDsp.Biquad] = []
	if cover:
		for k in 3:
			rings.append(AudioDsp.bp(r, rng.randf_range(300.0, 750.0) * (1.0 + k * 0.7), 22.0))
	var rattle := rng.randf_range(0.035, 0.06)
	for i in n:
		var t := float(i) / r
		var w := rng.randf_range(-1.0, 1.0)
		var v := sin(TAU * thump_hz * t) * exp(-t * (14.0 if cover else 24.0)) + body.step(w) * exp(-t * 30.0) * 2.0
		v += click.step(w) * exp(-t * 90.0) * (0.8 if cover else 0.5)
		if cover:
			var hit := w * (exp(-t * 200.0) + 0.6 * exp(-maxf(t - rattle, 0.0) * 200.0) * float(t >= rattle))
			var ring := 0.0
			for f in rings:
				ring += f.step(hit)
			v += ring * 6.0 * exp(-t * 9.0)
		s[i] = v
	var fade := int(0.003 * r)
	for i in fade:
		s[i] *= float(i) / fade
	return AudioDsp.normalise(s, 0.9)

## Each variant (by seed) starts and ends on its own note and lasts its own length.
static func _chirp(seed: int) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var secs := rng.randf_range(0.13, 0.24)
	var n := int(secs * r)
	var f_from := rng.randf_range(1180.0, 1420.0)
	var f_to := f_from * rng.randf_range(0.78, 0.9)
	var f1 := AudioDsp.bp(r, f_from, 20.0)
	var f2 := AudioDsp.bp(r, f_from * 1.52, 20.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / r
		if i % 64 == 0:
			var f := lerpf(f_from, f_to, t / secs)
			f1.set_bp(r, f, 20.0)
			f2.set_bp(r, f * 1.52, 20.0)
		var w := rng.randf_range(-1.0, 1.0)
		var env := minf(t / 0.006, 1.0) * exp(-t * 16.0)
		s[i] = (f1.step(w) + 0.5 * f2.step(w)) * env
	return AudioDsp.normalise(s)
