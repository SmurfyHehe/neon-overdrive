extends Node
class_name CabinLifeAudio

# Small cabin sounds that make the car feel lived in (more-alive pass MA1,
# 2026-10-11; Roy's Q1 + Q2). Owned by CarAudio (a child of it), reads the car,
# never touches physics. Every sound is made in code with AudioDsp, the way
# CrashSfx does it: no files, nothing to license.
#
# - cooling: when the engine goes from running to off (X, or a stall) the
#   metal ticks as it cools. Irregular clicks whose rate falls off as
#   e^(-3 t / length), so they thin out and stop; the electric fan runs on for
#   a few seconds. How long and how loud scales with `heat` (0..1), a 2-minute
#   running average of throttle and rpm. The engine starting again ends it at
#   once. Plays from the engine bay (3D), quieter in the cockpit view.
# - can: a can in the passenger footwell. Braking harder than CAN_BRAKE_G or
#   cornering harder than CAN_CORNER_G clunks, rolls and stops, panned to the
#   passenger side. At most once per CAN_COOLDOWN, and only again after it has
#   rolled back (acceleration under CAN_REST_G for CAN_REST_S).
# - coins: in the tray, chatter quietly on rough road and kerbs. Capped
#   (COIN_GAP minimum between bursts), never a loop.
# - glovebox: a front hit above CrashAudio.CRUNCH_DV (the crash audio's "big
#   hit") latches it open: a clack, and `glovebox_open` stays true until
#   reset_cabin() (the put-back / a garage visit). No cabin has a glovebox lid
#   node yet (CabinSpec / CabinSpots have none), so it is sound and state only.
#   The lid rotation (GLOVEBOX_OPEN_DEG) is applied if a node "GloveboxLid"
#   ever appears under the car.
#
# Only one of can / coins / glovebox sounds at a time (one player); the glovebox
# latch pre-empts the others, the rest wait. Cooling ticks wait for a one-shot
# too. The fan is the engine bay's own bed and may run under one.

const RATE := 24000
const HEAT_WINDOW := 120.0       # s: the running average of throttle and rpm
const HEAT_FLOOR := 0.08         # a short run still ticks a little
const COOL_MIN_S := 20.0         # tick run length at heat 0 .. 1
const COOL_MAX_S := 40.0
const FAN_MIN_S := 3.0
const FAN_MAX_S := 8.0
const TICK_RATE_MIN := 0.7       # ticks per second at the start, at heat 0 .. 1
const TICK_RATE_MAX := 1.7
const TICK_GAIN := 0.5
const FAN_GAIN := 0.12
const TICK_VARIANTS := 6
const PATH := "res://scripts/audio/cabin_life_audio.gd"
const COCKPIT_QUIET := 0.55      # tick level in the cockpit view, of the chase level

const G := 9.81
const CAN_BRAKE_G := 0.6
const CAN_CORNER_G := 0.7
const CAN_REST_G := 0.3
const CAN_REST_S := 0.8          # acceleration under CAN_REST_G this long: it has rolled back
const CAN_COOLDOWN := 20.0
const CAN_GAIN := 0.5
const ACCEL_SMOOTH := 0.08       # s: low pass on the measured acceleration

const COIN_GAP := 1.2            # s between coin bursts
const COIN_GAIN := 0.14
const COIN_ROUGH_MIN := 0.25     # share of wheels off the road surface (CarAudio's on_rough)
const COIN_SPEED_MIN := 4.0      # m/s

const LATCH_GAIN := 0.5
const GLOVEBOX_OPEN_DEG := 35.0
const HIT_MEMORY := 0.4          # s of velocity change kept to tell which way a hit came from

# Read by tests.
var heat := 0.0                  # 0..1 running average
var cooling := false
var cool_length := 0.0           # s the current tick run lasts
var cool_age := 0.0
var fan_left := 0.0
var tick_log := PackedFloat32Array()   # age of each tick of the current/last run
var tick_count := 0
var can_clunks := 0
var coin_bursts := 0
var latch_count := 0
var glovebox_open := false
var can_forward := false         # the can sits at the front of the footwell: it must roll back
var cabin := 0.0                 # 0 chase .. 1 cockpit; CarAudio feeds it
var last_event := ""             # last one-shot that started: "can" / "coins" / "latch"

var _vehicle: Vehicle
var _car_audio: Node
var _rng := RandomNumberGenerator.new()
var _bay: AudioStreamPlayer3D    # ticks, at the engine
var _fan: AudioStreamPlayer3D    # the fan, same place
var _one: AudioStreamPlayer      # can / coins / latch
var _ticks: Array[AudioStream] = []
var _can: Array[AudioStream] = []
var _coins: Array[AudioStream] = []
var _latch: Array[AudioStream] = []
var _fan_stream: AudioStream
var _running := true
var _tick_wait := 0.0
var _tick_rate0 := 1.0
var _tick_level := 1.0
var _one_left := 0.0
var _prev_v := Vector3.ZERO
var _have_prev := false
var _accel := Vector3.ZERO       # smoothed, car space (x right, z back), m/s^2
var _can_wait := 0.0
var _rest_time := 0.0
var _coin_wait := 0.0
var _dv_log: Array = []          # [t, local dv] pairs, last HIT_MEMORY s
var _clock := 0.0
var _crash: CrashAudio
var _lid: Node3D

func _ready() -> void:
	_car_audio = get_parent()
	_vehicle = _car_audio.get_parent() as Vehicle if _car_audio != null else null
	_rng.seed = 7711
	_bay = _player3d("EngineBayTicks")
	_fan = _player3d("EngineBayFan")
	# Booting into the garage nothing here can sound yet: the takes (on a cold
	# cache still being made, #524) are taken once ready or once the car is out.
	if not CarAudio.garage_boot():
		_build_streams()
	_one = AudioStreamPlayer.new()
	_one.name = "CabinOneShot"
	_one.bus = &"World"
	add_child(_one)
	if _vehicle != null:
		_running = _vehicle.engine_running
		_prev_v = _vehicle.linear_velocity
		_have_prev = true
		var z := _vehicle.front_axle_position.z - 0.35
		if _vehicle.get("spec") is Dictionary and String((_vehicle.get("spec") as Dictionary).get("engine", "front")) == "rear":
			z = _vehicle.rear_axle_position.z + 0.35
		_bay.position = Vector3(0.0, 0.65, z)
		_fan.position = _bay.position
	else:
		set_physics_process(false)

func _player3d(node_name: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.bus = &"World"
	p.unit_size = 4.0
	p.max_distance = 30.0
	p.volume_db = -80.0
	add_child(p)
	return p

## Heat: throttle and rpm over the last two minutes, 0..1.
func _heat_step(delta: float, throttle: float, rpm_share: float) -> void:
	var input := clampf(0.6 * throttle + 0.4 * rpm_share, 0.0, 1.0)
	var a := 1.0 - exp(-delta / HEAT_WINDOW)
	heat += (input - heat) * a

func _physics_process(delta: float) -> void:
	var v := _vehicle.linear_velocity
	var dv := v - _prev_v
	_prev_v = v
	var running := _vehicle.engine_running
	var rpm_share := clampf(_vehicle.motor_rpm / maxf(_vehicle.max_rpm, 1.0), 0.0, 1.0)
	var rough := 0.0
	if _car_audio != null:
		rough = float(_car_audio.get("rough_share"))
		cabin = float(_car_audio.get("cabin"))
	# Acceleration in the car's frame from the velocity change; gravity is
	# vertical and left out by only using the horizontal part of the world.
	var local_dv := _vehicle.global_transform.basis.inverse() * Vector3(dv.x, 0.0, dv.z)
	step(delta, running, float(_vehicle.throttle_amount), rpm_share, local_dv / maxf(delta, 0.0001), rough, v.length())
	_find_crash()

func _find_crash() -> void:
	if _crash != null:
		return
	for c in _vehicle.get_children():
		if c is CrashAudio:
			_crash = c
			_crash.big_hit.connect(_on_crash_hit)
			return

## One tick of the cabin. `accel` is the car's acceleration in its own frame
## (x right, z back; so braking while going forward is +z), m/s^2. Public so a
## test can script it without a car.
func step(delta: float, running: bool, throttle: float, rpm_share: float, accel: Vector3, rough := 0.0, speed := 0.0) -> void:
	if _ticks.is_empty() and (GameState.garage_seen or speed > 2.0 or _all_built()):
		_build_streams()
	_clock += delta
	if running:
		_heat_step(delta, throttle, rpm_share)
	if running and not _running:
		_stop_cooling()      # the engine starting again ends it at once
	elif _running and not running:
		_start_cooling()
	_running = running
	_step_cooling(delta)
	_one_left = maxf(_one_left - delta, 0.0)
	# smoothed acceleration
	var k := 1.0 - exp(-delta / ACCEL_SMOOTH)
	_accel += (accel - _accel) * k
	_prune_hits()
	_dv_log.append([_clock, accel * delta])
	_step_can(delta)
	_step_coins(delta, rough, speed)

# ---------- cooling ----------

func _start_cooling() -> void:
	var h := clampf(heat, HEAT_FLOOR, 1.0)
	cooling = true
	cool_age = 0.0
	cool_length = lerpf(COOL_MIN_S, COOL_MAX_S, h)
	fan_left = lerpf(FAN_MIN_S, FAN_MAX_S, h)
	_tick_rate0 = lerpf(TICK_RATE_MIN, TICK_RATE_MAX, h)
	_tick_level = lerpf(0.35, 1.0, h)
	tick_log = PackedFloat32Array()
	_tick_wait = _next_wait(0.0)
	_fan.volume_db = linear_to_db(FAN_GAIN * _tick_level)
	_fan.play()

func _stop_cooling() -> void:
	cooling = false
	fan_left = 0.0
	_fan.stop()
	_bay.stop()

func _step_cooling(delta: float) -> void:
	if not cooling:
		return
	cool_age += delta
	if fan_left > 0.0:
		fan_left = maxf(fan_left - delta, 0.0)
		# winds down over its last second
		_fan.volume_db = linear_to_db(maxf(FAN_GAIN * _tick_level * minf(fan_left, 1.0), 0.0001))
		if fan_left <= 0.0:
			_fan.stop()
	if cool_age >= cool_length:
		cooling = false
		return
	_tick_wait -= delta
	if _tick_wait <= 0.0:
		_tick()
		_tick_wait = _next_wait(cool_age)

## Poisson gaps at a rate that decays to about 5 % of its start over the run.
func _next_wait(age: float) -> float:
	var rate := _tick_rate0 * exp(-3.0 * age / maxf(cool_length, 1.0))
	return maxf(-log(maxf(_rng.randf(), 0.001)) / maxf(rate, 0.01), 0.1)

func _tick() -> void:
	if _one_left > 0.0:
		return   # a loose-object sound is sounding: the tick waits its turn
	tick_count += 1
	tick_log.append(cool_age)
	if _ticks.is_empty():
		return   # takes not in yet (garage boot)
	_bay.stream = _ticks[_rng.randi() % _ticks.size()]
	var fade := exp(-1.5 * cool_age / maxf(cool_length, 1.0))
	var level := TICK_GAIN * _tick_level * fade * lerpf(1.0, COCKPIT_QUIET, cabin)
	_bay.volume_db = linear_to_db(maxf(level, 0.0001)) + _rng.randf_range(-1.5, 1.5)
	_bay.pitch_scale = _rng.randf_range(0.9, 1.15)
	_bay.play()

# ---------- the can ----------

func _step_can(delta: float) -> void:
	_can_wait = maxf(_can_wait - delta, 0.0)
	var long_g := _accel.z / G        # + braking while going forward
	var side_g := absf(_accel.x) / G
	var calm := absf(_accel.z) / G < CAN_REST_G and side_g < CAN_REST_G
	if calm:
		_rest_time += delta
		if _rest_time >= CAN_REST_S:
			can_forward = false       # it has rolled back
	else:
		_rest_time = 0.0
	if _can_wait > 0.0 or can_forward or _one_left > 0.0:
		return
	if long_g > CAN_BRAKE_G or side_g > CAN_CORNER_G:
		if not _can.is_empty():
			_play_one("can", _can[_rng.randi() % _can.size()], CAN_GAIN, 1.0)
		can_clunks += 1
		can_forward = true
		_can_wait = CAN_COOLDOWN
		_rest_time = 0.0

# ---------- coins ----------

func _step_coins(delta: float, rough: float, speed: float) -> void:
	_coin_wait = maxf(_coin_wait - delta, 0.0)
	if _coin_wait > 0.0 or _one_left > 0.0 or speed < COIN_SPEED_MIN or rough < COIN_ROUGH_MIN:
		return
	coin_bursts += 1
	_coin_wait = COIN_GAP + _rng.randf_range(0.0, 1.0)
	var level := COIN_GAIN * clampf(speed / 20.0, 0.4, 1.0) * clampf(rough * 1.5, 0.4, 1.0)
	if not _coins.is_empty():
		_play_one("coins", _coins[_rng.randi() % _coins.size()], level, _rng.randf_range(0.92, 1.1))

# ---------- the glovebox ----------

func _on_crash_hit(dv: float) -> void:
	_prune_hits()
	var sum := Vector3.ZERO
	for e in _dv_log:
		sum += e[1]
	var front := sum.z > 0.0 and sum.z > absf(sum.x)
	hit(dv, front)

## A hit of `dv` m/s; `front` when it came from ahead.
func hit(dv: float, front: bool) -> void:
	if not front or dv < CrashAudio.CRUNCH_DV or glovebox_open:
		return
	glovebox_open = true
	latch_count += 1
	_one_left = 0.0
	if not _latch.is_empty():
		_play_one("latch", _latch[_rng.randi() % _latch.size()], LATCH_GAIN, 1.0)
	if _vehicle != null:
		var lid := _vehicle.find_child("GloveboxLid", true, false) as Node3D
		if lid != null:
			_lid = lid
			lid.rotation_degrees.x = GLOVEBOX_OPEN_DEG

## The garage or a put-back: the glovebox shuts, the can is back in its place.
func reset_cabin() -> void:
	glovebox_open = false
	can_forward = false
	_can_wait = 0.0
	if _lid != null and is_instance_valid(_lid):
		_lid.rotation_degrees.x = 0.0
	_lid = null

## The cabin of a Vehicle, or null.
static func of(vehicle: Node) -> CabinLifeAudio:
	if vehicle == null:
		return null
	for c in vehicle.get_children():
		if c is CarAudio:
			for k in c.get_children():
				if k is CabinLifeAudio:
					return k
	return null

func _prune_hits() -> void:
	while not _dv_log.is_empty() and _clock - float(_dv_log[0][0]) > HIT_MEMORY:
		_dv_log.pop_front()

func _play_one(kind: String, stream: AudioStream, gain: float, pitch: float) -> void:
	last_event = kind
	_one.stream = stream
	_one.volume_db = linear_to_db(maxf(gain, 0.0001))
	_one.pitch_scale = pitch
	_one.play()
	_one_left = stream.get_length() / maxf(pitch, 0.1)

## True while a can / coins / latch is sounding (tests).
func busy() -> bool:
	return _one_left > 0.0

# ---------- the sounds ----------

## Every take: [set, cache layer, maker]. Through the disk cache since issue
## #524 (they were made on every boot, about 0.3 s).
static func takes() -> Array:
	var out := []
	for i in TICK_VARIANTS:
		out.append(["tick", "tick%d" % i, make_tick.bind(1000 + i * 37)])
	for i in 3:
		out.append(["can", "can%d" % i, make_can.bind(2000 + i * 53)])
	for i in 4:
		out.append(["coins", "coins%d" % i, make_coins.bind(3000 + i * 29)])
	for i in 2:
		out.append(["latch", "latch%d" % i, make_latch.bind(4000 + i * 11)])
	out.append(["fan", "fan", make_fan.bind(5000)])
	return out

## Starts making the takes off the main thread (issue #524); on a garage boot
## nothing waits for them (see _ready): AudioDsp's background lane.
static func prefetch() -> void:
	var urgent := not CarAudio.garage_boot()
	for t in takes():
		AudioDsp.prefetch(PATH, t[1], t[2], urgent)

static func _all_built() -> bool:
	for t in takes():
		if AudioDsp.building(PATH, t[1]):
			return false
	return true

func _build_streams() -> void:
	if not _ticks.is_empty():
		return
	for t in takes():
		var s := AudioDsp.cached(PATH, t[1], t[2])
		match String(t[0]):
			"tick": _ticks.append(s)
			"can": _can.append(s)
			"coins": _coins.append(s)
			"latch": _latch.append(s)
			_: _fan_stream = s
	_fan.stream = _fan_stream

static func _noise(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(-1.0, 1.0)

## One metal tick: a short ring at a few kHz with a dull knock under it.
static func make_tick(seed_value: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * 0.09)
	var ring := AudioDsp.reso(RATE, rng.randf_range(1700.0, 3300.0), rng.randf_range(90.0, 160.0))
	var body := AudioDsp.reso(RATE, rng.randf_range(420.0, 700.0), 140.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var imp := 1.0 if i == 0 else 0.0
		s[i] = ring.step(imp) * 0.8 + body.step(imp) * 0.5
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.7), RATE, false)

## The fan: a motor hum with air over it, a one-second loop.
static func make_fan(seed_value: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := RATE
	var air := AudioDsp.bp(RATE, 900.0, 0.7)
	var s := PackedFloat32Array()
	s.resize(n + 480)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = air.step(_noise(rng)) * 0.5 + sin(TAU * 120.0 * t) * 0.35 + sin(TAU * 240.0 * t) * 0.12
	s = AudioDsp.seamless(s, n, 480)
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.6), RATE, true)

## A can: a knock on the plastic, a rolling rumble that slows, a last tap.
## Stereo, leaning to the passenger side (right; -x is the driver's).
static func make_can(seed_value: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * 1.5)
	var knock := AudioDsp.reso(RATE, rng.randf_range(260.0, 340.0), 38.0)
	var ping := AudioDsp.reso(RATE, rng.randf_range(1500.0, 2100.0), 70.0)
	var roll_lp := AudioDsp.lp(RATE, 700.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var roll_end := 1.15
	for i in n:
		var t := float(i) / RATE
		var imp := 1.0 if i == 0 else 0.0
		var y := knock.step(imp) * 0.9 + ping.step(imp) * 0.35
		if t > 0.06 and t < roll_end:
			# a rolling can: low rumble whose beat slows as it dies away
			var speed := 1.0 - t / roll_end
			var beat := 0.5 + 0.5 * sin(TAU * (6.0 + 22.0 * speed * speed) * t)
			y += roll_lp.step(_noise(rng)) * 0.9 * speed * (0.4 + 0.6 * beat)
		if i == int(RATE * 1.22):
			y += 0.6          # the stop: one last tap
		s[i] = y
	var tap := AudioDsp.reso(RATE, 380.0, 60.0)
	for i in range(int(RATE * 1.22), n):
		s[i] += tap.step(1.0 if i == int(RATE * 1.22) else 0.0) * 0.5
	s = AudioDsp.normalise(s, 0.75)
	var left := s.duplicate()
	for i in left.size():
		left[i] *= 0.3
	return AudioDsp.to_wav(left, RATE, false, s)

## Coins in a tray: a handful of small bright rings at uneven spacing.
static func make_coins(seed_value: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var hits := rng.randi_range(4, 7)
	var t0 := 0.0
	for h in hits:
		t0 += rng.randf_range(0.02, 0.09)
		var start := int(t0 * RATE)
		var r := AudioDsp.reso(RATE, rng.randf_range(2600.0, 5200.0), rng.randf_range(60.0, 120.0))
		var amp := rng.randf_range(0.4, 1.0) * (1.0 - 0.1 * h)
		for i in range(start, mini(n, start + int(RATE * 0.12))):
			s[i] += r.step(1.0 if i == start else 0.0) * amp
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.6), RATE, false)

## The glovebox latch: a spring clack, then the lid dropping onto its stop.
static func make_latch(seed_value: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * 0.4)
	var clack := AudioDsp.reso(RATE, rng.randf_range(2200.0, 2800.0), 160.0)
	var thump := AudioDsp.reso(RATE, rng.randf_range(150.0, 210.0), 36.0)
	var drop_at := int(RATE * 0.14)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var y := clack.step(1.0 if i == 0 else 0.0) * 0.8
		y += thump.step(1.0 if i == drop_at else 0.0) * 0.9
		s[i] = y
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.75), RATE, false)
