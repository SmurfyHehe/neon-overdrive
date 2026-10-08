extends Node
class_name CrashAudio

# Crash and scrape sound (2026-10-08, sound research section 1b: "silence on
# impact feels like a bug"). Next to CarAudio on a Vehicle; reads GEVP state,
# never touches physics. Generated in code like the other car sounds
# (AudioDsp), so nothing to license.
#
# Impacts use the same measure as the camera shake (ChaseCamera.register_impact):
# how much the car's velocity changes in one tick. Here only the horizontal
# part counts (landings are DrivelineAudio's), and only while the body is
# actually touching something, so a respawn or a reset that zeroes the
# velocity stays silent. A hit is summed over the ticks it lasts, then played
# once at its size:
# - tap    (under 3 m/s):  a light knock and a panel ring;
# - thud   (3-7 m/s):      the body thump;
# - crunch (7 m/s and up): the thud plus crumpling metal;
# - glass  (10 m/s and up, most of the time): breaking glass on top.
# Each has five variants played at random pitch and volume, so no two hits
# match. While the body touches a wall or a car and is moving, a metal scrape
# loops, louder and higher with speed.
# impact_count / last_tier / last_dv / scrape_level are for tests (silent driver).

const MIX_RATE := 32000
const VARIANTS := 5
const IMPACT_ACCEL := 35.0       # m/s^2 horizontal: a hit (hard braking is about 12)
const MIN_DV := 0.8              # m/s: smaller changes are ignored
const THUD_DV := 3.0
const CRUNCH_DV := 7.0
const GLASS_DV := 10.0
const GLASS_CHANCE := 0.65
const CONTACT_GRACE := 4         # ticks a contact counts after it ends (reports lag a tick)
const COOLDOWN := 0.12           # s between two hits
const GAIN := {"tap": 0.45, "thud": 0.75, "crunch": 0.8, "glass": 0.45}
const SCRAPE_GAIN := 0.5
const SCRAPE_FROM := 1.5         # m/s
const SCRAPE_FULL := 15.0
const ATTACK := 25.0
const RELEASE := 10.0

var impact_count := 0
var last_tier := ""
var last_dv := 0.0
var scrape_level := 0.0

static var _streams := {}

var _vehicle: Vehicle
var _players := {}
var _scrape: AudioStreamPlayer
var _prev_vel := Vector3.ZERO
var _hit_dv := 0.0
var _contact := 0
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
## Tests and the listen pack: when >= 0, used instead of the real contact.
var forced_scrape_speed := -1.0

func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	if _vehicle == null:
		push_error("CrashAudio must be a child of a Vehicle")
		set_process(false)
		set_physics_process(false)
		return
	# Contact reports only; it changes nothing in the simulation.
	_vehicle.contact_monitor = true
	_vehicle.max_contacts_reported = maxi(_vehicle.max_contacts_reported, 4)
	_prev_vel = _vehicle.linear_velocity
	_rng.seed = 5150
	for tier in GAIN:
		var p := AudioStreamPlayer.new()
		p.name = String(tier).capitalize() + "Audio"
		p.stream = variants(tier)
		p.bus = &"Tires"
		p.max_polyphony = 3
		add_child(p)
		_players[tier] = p
	_scrape = AudioStreamPlayer.new()
	_scrape.name = "ScrapeAudio"
	_scrape.stream = stream("scrape")
	_scrape.bus = &"Tires"
	_scrape.volume_db = -80.0
	add_child(_scrape)
	_scrape.play()

func _physics_process(delta: float) -> void:
	_wait = maxf(_wait - delta, 0.0)
	var v := _vehicle.linear_velocity
	var dv := v - _prev_vel
	_prev_vel = v
	var touching := _vehicle.get_contact_count() > 0
	_contact = CONTACT_GRACE if touching else maxi(_contact - 1, 0)
	var dvh := Vector2(dv.x, dv.z).length()
	if dvh / delta > IMPACT_ACCEL and _contact > 0:
		_hit_dv += dvh
	elif _hit_dv > 0.0:
		impact(_hit_dv)
		_hit_dv = 0.0

func _process(delta: float) -> void:
	var speed := _vehicle.speed
	var touching := _contact > 0
	if forced_scrape_speed >= 0.0:
		speed = forced_scrape_speed
		touching = true
	var target := smoothstep(SCRAPE_FROM, SCRAPE_FULL, speed) if touching else 0.0
	var rate := ATTACK if target > scrape_level else RELEASE
	scrape_level = lerpf(scrape_level, target, 1.0 - exp(-rate * delta))
	_scrape.volume_db = linear_to_db(scrape_level * SCRAPE_GAIN) if scrape_level > 0.001 else -80.0
	_scrape.pitch_scale = 0.8 + 0.4 * clampf(speed / 30.0, 0.0, 1.2)

## Plays one hit of this size (m/s of velocity change). Public so the listen
## pack and tests can fire hits directly.
func impact(dv: float) -> void:
	if dv < MIN_DV or _wait > 0.0:
		return
	_wait = COOLDOWN
	impact_count += 1
	last_dv = dv
	if dv < THUD_DV:
		last_tier = "tap"
		_play("tap", 0.4 + 0.6 * dv / THUD_DV)
		return
	_play("thud", clampf(dv / CRUNCH_DV, 0.5, 1.0))
	last_tier = "thud"
	if dv >= CRUNCH_DV:
		last_tier = "crunch"
		_play("crunch", clampf(dv / 15.0, 0.55, 1.0))
	if dv >= GLASS_DV and _rng.randf() < GLASS_CHANCE:
		last_tier = "glass"
		_play("glass", clampf(dv / 18.0, 0.6, 1.0))

func _play(tier: String, level: float) -> void:
	var p: AudioStreamPlayer = _players[tier]
	p.volume_db = linear_to_db(GAIN[tier] * level)
	p.play()

## Five variants of a tier, picked at random per hit.
static func variants(tier: String) -> AudioStreamRandomizer:
	var list: Array[AudioStream] = []
	for k in VARIANTS:
		list.append(stream("%s%d" % [tier, k]))
	return AudioDsp.randomizer(list, 1.1, 2.0)

## One stream ("tap0".."glass4", "scrape"), generated on first use.
static func stream(layer: String) -> AudioStreamWAV:
	if not _streams.has(layer):
		_streams[layer] = AudioDsp.cached("res://scripts/crash_audio.gd", layer, _make.bind(layer))
	return _streams[layer]

static func _make(layer: String) -> AudioStreamWAV:
	var r := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layer)
	if layer == "scrape":
		return AudioDsp.to_wav(_scrape_loop(rng), MIX_RATE, true)
	var tier := layer.rstrip("0123456789")
	var secs: float = {"tap": 0.18, "thud": 0.45, "crunch": 0.95, "glass": 0.9}[tier]
	var n := int(secs * r)
	var s := PackedFloat32Array()
	s.resize(n)
	match tier:
		"tap":
			# a knuckle on a panel: a short knock and a brief ring
			var knock_hz := rng.randf_range(120.0, 180.0)
			var click := AudioDsp.bp(r, rng.randf_range(1500.0, 2500.0), 2.0)
			var ring := AudioDsp.bp(r, rng.randf_range(600.0, 900.0), 12.0)
			for i in n:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				s[i] = sin(TAU * knock_hz * t) * exp(-t * 40.0) + click.step(w) * exp(-t * 60.0) * 1.5 + ring.step(w) * exp(-t * 25.0) * 3.0
		"thud":
			# the body taking a hit: a falling low boom, dull noise, panel ring
			var boom_hz := rng.randf_range(55.0, 75.0)
			var dull := AudioDsp.lp(r, 300.0)
			var rings := [AudioDsp.bp(r, rng.randf_range(280.0, 420.0), 14.0), AudioDsp.bp(r, rng.randf_range(600.0, 900.0), 16.0)]
			var ph := 0.0
			for i in n:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				ph += TAU * boom_hz * (1.0 - 0.3 * minf(t / 0.2, 1.0)) / r
				s[i] = sin(ph) * exp(-t * 12.0) * 1.2 + dull.step(w) * exp(-t * 15.0) * 3.0 \
					+ ((rings[0] as AudioDsp.Biquad).step(w) + (rings[1] as AudioDsp.Biquad).step(w)) * exp(-t * 10.0) * 2.5
		"crunch":
			# crumpling metal: a burst of short grains, thinning out, rung
			# through a few metallic resonances, over a low boom
			var res: Array[AudioDsp.Biquad] = []
			for k in 4:
				res.append(AudioDsp.bp(r, rng.randf_range(400.0, 3500.0), rng.randf_range(10.0, 25.0)))
			var grit := AudioDsp.hp(r, 1800.0)
			var grains: Array[float] = []   # start times
			var tt := 0.0
			while tt < secs * 0.7:
				grains.append(tt)
				tt += rng.randf_range(0.004, 0.02) * (1.0 + tt * 12.0)
			var g := 0
			var excite := 0.0
			var boom_hz := rng.randf_range(42.0, 55.0)
			for i in n:
				var t := float(i) / r
				while g < grains.size() and grains[g] <= t:
					excite = maxf(excite, rng.randf_range(0.5, 1.0) * exp(-grains[g] * 3.0))
					g += 1
				excite *= 0.996
				var w := rng.randf_range(-1.0, 1.0) * excite
				var v := 0.0
				for f in res:
					v += f.step(w)
				s[i] = v * 2.5 + grit.step(w) * 0.5 + sin(TAU * boom_hz * t) * exp(-t * 9.0) * 0.6
		"glass":
			# glass going: a bright shatter, then tinkling pieces
			var res: Array[AudioDsp.Biquad] = []
			for k in 4:
				res.append(AudioDsp.bp(r, rng.randf_range(3000.0, 7500.0), rng.randf_range(40.0, 80.0)))
			var shatter := AudioDsp.hp(r, 2000.0)
			for i in n:
				var t := float(i) / r
				var w := rng.randf_range(-1.0, 1.0)
				var hit := 0.0
				# tinkles: sparse impulses, thinning out
				if rng.randf() < 0.004 * exp(-t * 4.0):
					hit = rng.randf_range(-1.0, 1.0) * 8.0
				var v := 0.0
				for f in res:
					v += f.step(hit)
				s[i] = shatter.step(w) * exp(-t * 22.0) + v * 0.5
	# a 3 ms fade-in so no variant starts on a click, then normalise
	var fade_in := int(0.003 * r)
	for i in fade_in:
		s[i] *= float(i) / fade_in
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.9), MIX_RATE, false)

## Metal dragging along a wall: noise in stick-slip bursts through hard,
## slightly detuned resonances, with grit on top.
static func _scrape_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var r := float(MIX_RATE)
	var n := int(2.0 * r)
	var fade := int(0.15 * r)
	var total := n + fade
	var res := [AudioDsp.bp(r, 720.0, 18.0), AudioDsp.bp(r, 1650.0, 20.0), AudioDsp.bp(r, 2900.0, 22.0)]
	var gains := [1.0, 0.8, 0.5]
	var grit := AudioDsp.hp(r, 2500.0)
	var s := PackedFloat32Array()
	s.resize(total)
	var env := 0.0
	var wait := 0
	for i in total:
		var w := rng.randf_range(-1.0, 1.0)
		wait -= 1
		if wait <= 0:
			env = rng.randf_range(0.5, 1.0)
			wait = int(rng.randf_range(0.006, 0.02) * r)
		env *= 0.999
		var x := w * (0.35 + 0.65 * env)
		var v := 0.0
		for k in 3:
			v += gains[k] * (res[k] as AudioDsp.Biquad).step(x)
		s[i] = v + 0.12 * grit.step(w)
	return AudioDsp.normalise(AudioDsp.seamless(s, n, fade))
