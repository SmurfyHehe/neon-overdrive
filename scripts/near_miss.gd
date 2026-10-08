extends Node
class_name NearMiss

# Near miss (driving-feel pass, 2026-10-08; Roy's pick: "near-miss sound
# only", so no score, popup or slow-motion): threading past a traffic car
# close at speed gives an air whoosh on that side and a small shove of the
# camera away from it, so a close pass feels close.
#
# A pass counts at the moment the other car's middle goes behind the player's
# middle (along the player's heading), if the side gap between the two bodies
# is under NEAR_GAP, the closing speed is at least MIN_CLOSING and the player
# is doing MIN_SPEED. Touching (a gap under -TOUCH_GAP, or a hit in the last
# moment) is a crash, not a near miss. Each car counts once per pass.
# Cheap: a loop over the detailed traffic cars, which the TrafficManager has
# already narrowed to the ones near the player. FxSettings "near_miss" is the
# off switch. count / last_side / last_strength are for tests.

const MIN_SPEED := 15.0        # m/s (54 km/h) the player must be doing
const MIN_CLOSING := 8.0       # m/s difference along the player's heading
const NEAR_GAP := 1.1          # m between the bodies' sides: near enough to count
const TOUCH_GAP := 0.15        # m of overlap: that is a hit, not a near miss
const MAX_LONG := 12.0         # m: cars further ahead or behind are not tracked
const MIX_RATE := 32000
const VARIANTS := 3
const GAIN := 0.7

var enabled := true
var count := 0
var last_side := 0             # -1 the car went by on the left, +1 on the right
var last_strength := 0.0

static var _streams := {}

var _player: PlayerCar
var _camera: ChaseCamera
var _traffic: Node
var _ahead := {}               # car instance id -> true while it is ahead of the player
var _crash: CrashAudio
var _since_hit := 10.0
var _players := {}

func _init(player: PlayerCar, camera: ChaseCamera) -> void:
	_player = player
	_camera = camera
	name = "NearMiss"

func _ready() -> void:
	for c in _player.get_children():
		if c is CrashAudio:
			_crash = c
			_crash.hit_building.connect(func(_dv: float, _first: bool) -> void: _since_hit = 0.0)
	for side in [-1, 1]:
		var p := AudioStreamPlayer.new()
		p.name = "Whoosh" + ("L" if side < 0 else "R")
		p.stream = variants(side)
		p.bus = &"World"
		p.max_polyphony = 2
		add_child(p)
		_players[side] = p

func _physics_process(delta: float) -> void:
	_since_hit += delta
	if _traffic == null:
		_traffic = get_tree().current_scene.get("traffic") if get_tree().current_scene != null else null
		if _traffic == null:
			_traffic = _find_traffic()
		if _traffic == null:
			return
	var cars: Array = _traffic.get("cars")
	if cars == null:
		return
	var b := _player.global_transform.basis
	var fwd := -b.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		return
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var pv := _player.linear_velocity
	var speed := Vector2(pv.x, pv.z).length()
	var my_half_w := float(_player.chassis_visual.get_meta("half_w", 0.9)) if _player.chassis_visual != null else 0.9
	var seen := {}
	for car in cars:
		if car == null or not is_instance_valid(car) or not car.detailed or car.wrecked:
			continue
		var id: int = car.get_instance_id()
		var d: Vector3 = car.global_position - _player.global_position
		var along := d.dot(fwd)
		if absf(along) > MAX_LONG:
			continue
		seen[id] = true
		var ahead := along > 0.0
		var was_ahead: bool = _ahead.get(id, ahead)
		_ahead[id] = ahead
		if not was_ahead or ahead:
			continue
		# It just went from ahead to behind: how close and how fast?
		var lat := d.dot(right)
		var gap := absf(lat) - my_half_w - float(car.half_w)
		var closing := (pv - (car.linear_velocity as Vector3)).dot(fwd)
		if speed < MIN_SPEED or closing < MIN_CLOSING or gap > NEAR_GAP or gap < -TOUCH_GAP or _since_hit < 0.5:
			continue
		var strength := clampf(closing / 30.0, 0.3, 1.0) * clampf(1.0 - maxf(gap, 0.0) / NEAR_GAP, 0.2, 1.0)
		trigger(1 if lat > 0.0 else -1, strength)
	for id in _ahead.keys():
		if not seen.has(id):
			_ahead.erase(id)

## A near miss on this side (-1 left, +1 right), 0..1 strong. Public for tests.
func trigger(side: int, strength: float) -> void:
	if not enabled or not FxSettings.is_on("near_miss"):
		return
	count += 1
	last_side = side
	last_strength = strength
	var p: AudioStreamPlayer = _players[side]
	p.volume_db = linear_to_db(GAIN * lerpf(0.5, 1.0, strength))
	p.play()
	if _camera != null:
		_camera.nudge(side, strength)

func _find_traffic() -> Node:
	var n := _player.get_parent()
	while n != null:
		var t: Variant = n.get("traffic")
		if t is Node:
			return t
		n = n.get_parent()
	return null

## The whoosh for one side: VARIANTS takes, random pick, pitch and volume.
static func variants(side: int) -> AudioStreamRandomizer:
	var list: Array[AudioStream] = []
	for k in VARIANTS:
		list.append(stream("whoosh%d_%s" % [k, "l" if side < 0 else "r"]))
	return AudioDsp.randomizer(list, 1.1, 2.0)

static func stream(layer: String) -> AudioStreamWAV:
	if not _streams.has(layer):
		_streams[layer] = AudioDsp.cached("res://scripts/near_miss.gd", layer, _make.bind(layer))
	return _streams[layer]

## Air pushed past the window: band-passed noise whose centre rises as the car
## comes up and falls as it goes by (a Doppler-ish sweep), over a soft low
## buffet. Louder on the side the car passed.
static func _make(layer: String) -> AudioStreamWAV:
	var r := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layer.left(7))   # both sides of one take share the noise
	var secs := rng.randf_range(0.5, 0.65)
	var peak := rng.randf_range(0.18, 0.26)   # s: the moment it passes
	var hi := rng.randf_range(1500.0, 2200.0)
	var n := int(secs * r)
	var s := PackedFloat32Array()
	s.resize(n)
	var band := AudioDsp.bp(r, 500.0, 1.2)
	var low := AudioDsp.lp(r, 140.0)
	for i in n:
		var t := float(i) / r
		if i % 64 == 0:
			var hz := lerpf(500.0, hi, t / peak) if t < peak else lerpf(hi, 350.0, minf((t - peak) / (secs - peak), 1.0))
			band.set_bp(r, hz, 1.2)
		var env := pow(t / peak, 2.0) if t < peak else exp(-(t - peak) * 9.0)
		var w := rng.randf_range(-1.0, 1.0)
		s[i] = (band.step(w) * 2.0 + low.step(w) * 1.5) * env
	var fade := int(0.004 * r)
	for i in fade:
		s[i] *= float(i) / fade
		s[n - 1 - i] *= float(i) / fade
	s = AudioDsp.normalise(s, 0.85)
	var far := s.duplicate()
	for i in far.size():
		far[i] *= 0.35
	return AudioDsp.to_wav(s if layer.ends_with("l") else far, MIX_RATE, false, far if layer.ends_with("l") else s)
