extends Node
class_name CrashAudio

# Crash and scrape sound (2026-10-08, sound research section 1b: "silence on
# impact feels like a bug"; reworked 2026-10-09 because one scrape loop on
# repeat sounded thin). Next to CarAudio on a Vehicle; reads GEVP state, never
# touches physics. The takes are synthesised by CrashSfx (scripts/crash_sfx.gd)
# and rendered once into assets/sfx/crash, so nothing to license or credit and
# nothing to build at boot.
#
# Impacts use the same measure as the camera shake (ChaseCamera.register_impact):
# how much the car's velocity changes in one tick. Here only the horizontal
# part counts (landings are DrivelineAudio's), and only while the body is
# actually touching something, so a respawn or a reset that zeroes the
# velocity stays silent. A hit opens a short window (HIT_WINDOW) and every
# horizontal velocity change inside it is summed, so one crash that judders
# over a few ticks is one sound at its full size, not several taps.
#
# What the body touches picks the sound set (the physics contact's collider
# and normal, read each tick):
# - concrete: walls and buildings (the default for anything static);
# - metal:    anything whose collider has meta audio_surface = "metal"
#             (guardrails, when there are some);
# - car:      another Vehicle; scrapes use the speed relative to it;
# - underbody: the body itself on the road (bottoming out, or on its roof).
#
# A hit is built in layers by size:
# - tap    (under 3 m/s):  a light knock off that surface;
# - thud   (3 m/s and up): the body thump off that surface;
#   + sparks (5 m/s and up on concrete or metal, most of the time);
#   + debris (6 m/s and up): trim and plastic bits bouncing on the road;
# - crunch (7 m/s and up): crumpling metal on top;
# - glass  (10 m/s and up, most of the time): breaking glass on top.
# The body slamming down on the road (a big upward velocity change while the
# underbody touches) is a grounding hit of its own.
#
# Every pool holds VARIANTS takes. Each play picks one at random but never the
# take that pool played last, and nudges its pitch and volume, so no two hits
# match. Scrapes loop per surface (LOOP_TAKES takes of different lengths): two
# players crossfade to a fresh take every few seconds, from a random point, so
# a long slide never repeats; a scrape starting at speed bites with a short
# screech, and sparks crackle on top while the body grinds concrete, metal or
# road fast enough.
#
# impact_count / last_tier / last_dv / last_surface / scrape_level /
# scrape_kind / ground_hits / plays are for tests (silent driver).

const VARIANTS := 8              # takes per one-shot pool
const LOOP_TAKES := 6            # takes per scrape loop
const IMPACT_ACCEL := 35.0       # m/s^2 horizontal: a hit (hard braking is about 12)
const MIN_DV := 0.8              # m/s: smaller changes are ignored
const THUD_DV := 3.0
const SPARK_DV := 5.0
const SPARK_CHANCE := 0.7
const DEBRIS_DV := 6.0
const CRUNCH_DV := 7.0
const GLASS_DV := 10.0
const GLASS_CHANCE := 0.65
const GROUND_DV := 2.5           # m/s upward, summed over a hit window: the body slamming down
const HIT_WINDOW := 0.12         # s: one hit gathers everything this long after it starts
const CONTACT_GRACE := 4         # ticks a contact counts after it ends (reports lag a tick)
const COOLDOWN := 0.12           # s between two hits
const GROUND_COOLDOWN := 0.3
const PITCH_JITTER := 0.06       # +-6 % per play
const VOLUME_JITTER_DB := 1.5    # +-1.5 dB per play
const VOICES := 10               # one-shot players, reused oldest first
const SURFACES := ["concrete", "metal", "car"]
const SCRAPE_KINDS := ["concrete", "metal", "car", "underbody"]
const SPARK_KINDS := ["concrete", "metal", "underbody"]
const SCRAPE_FROM := 1.5         # m/s
const SCRAPE_FULL := 15.0
const SPARKS_FROM := 6.0         # m/s: sparks only when grinding this fast
const SPARKS_FULL := 22.0
const BITE_FROM := 5.0           # m/s: a scrape starting faster than this bites
const ATTACK := 25.0
const RELEASE := 10.0
const PLAY_LOG := 256

## One-shot pools and their gain. Every take's peak is normalised, so gain
## sets the pool's level against the others (the old tiers' gains carried over).
## The sounds themselves are CrashSfx's recipes.
const POOLS := {
	"tap_concrete": 0.45,
	"tap_metal": 0.42,
	"tap_car": 0.45,
	"thud_concrete": 0.75,
	"thud_metal": 0.7,
	"thud_car": 0.75,
	"crunch": 0.8,
	"glass": 0.45,
	"debris": 0.32,
	"sparks": 0.3,
	"ground_hit": 0.7,
	"scrape_bite": 0.4,
}
## Scrape loops: gain at full speed.
const LOOPS := {"concrete": 0.5, "metal": 0.45, "car": 0.45, "underbody": 0.5, "sparks": 0.22}

var impact_count := 0
var ground_hits := 0
var last_tier := ""
var last_dv := 0.0
var last_surface := ""
var scrape_level := 0.0
var scrape_kind := ""
## Every one-shot played, newest last: {pool, take, db, pitch}. Capped.
var plays: Array[Dictionary] = []
## Tests and the listen pack: when >= 0, used instead of the real contact.
var forced_scrape_speed := -1.0
var forced_scrape_kind := "concrete"

static var _streams := {}

var _vehicle: Vehicle
var _pools := {}                 # name -> Pool
var _loops := {}                 # kind -> LoopLayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _prev_vel := Vector3.ZERO
var _hit_dv := 0.0
var _hit_left := -1.0            # s left in the open hit window, < 0 = none open
var _hit_surface := "concrete"
var _ground_dv := 0.0
var _ground_left := -1.0
var _grace := {}                 # kind -> ticks left
var _rel_speed := {}             # kind -> m/s sliding speed against it
var _wait := 0.0
var _ground_wait := 0.0
var _rng := RandomNumberGenerator.new()

## A set of takes played at random, never the same take twice in a row.
class Pool:
	var name := ""
	var streams: Array[AudioStream] = []
	var last := -1

	func pick(rng: RandomNumberGenerator) -> int:
		var n := streams.size()
		var i := rng.randi_range(0, n - 1)
		if n > 1 and i == last:
			i = (last + 1 + rng.randi_range(0, n - 2)) % n
		last = i
		return i

## One scrape surface: two players, the current take and the one fading out.
class LoopLayer:
	const _SWAP_MIN := 1.8
	const _SWAP_MAX := 3.6
	const _XFADE := 0.35
	var pool: Pool
	var gain := 0.5
	var players: Array[AudioStreamPlayer] = []
	var takes: Array[int] = [-1, -1]
	var jitter: Array[float] = [1.0, 1.0]
	var cur := 0
	var xfade := 1.0
	var level := 0.0
	var swap_in := 0.0
	var started: Array[int] = [] # takes started, oldest first (tests; last 64)

	## Returns true when the layer started from silence this frame.
	func update(target: float, delta: float, pitch: float, rng: RandomNumberGenerator, attack: float, release: float) -> bool:
		var rate := attack if target > level else release
		level = lerpf(level, target, 1.0 - exp(-rate * delta))
		if target <= 0.0 and level < 0.002:
			level = 0.0
			for p in players:
				if p.playing:
					p.stop()
			return false
		var started := false
		if not players[cur].playing:
			_start(cur, rng)
			xfade = 1.0
			started = true
		swap_in -= delta
		if swap_in <= 0.0:
			cur = 1 - cur
			_start(cur, rng)
			xfade = 0.0
		xfade = minf(xfade + delta / _XFADE, 1.0)
		var other := players[1 - cur]
		if xfade >= 1.0 and other.playing:
			other.stop()
		var g := level * gain
		players[cur].volume_db = linear_to_db(maxf(g * sin(xfade * PI * 0.5), 1e-5))
		other.volume_db = linear_to_db(maxf(g * cos(xfade * PI * 0.5), 1e-5))
		players[cur].pitch_scale = pitch * jitter[cur]
		other.pitch_scale = pitch * jitter[1 - cur]
		return started

	func _start(slot: int, rng: RandomNumberGenerator) -> void:
		var k := pool.pick(rng)
		takes[slot] = k
		jitter[slot] = rng.randf_range(0.95, 1.05)
		var p := players[slot]
		p.stream = pool.streams[k]
		p.volume_db = -80.0
		p.play(rng.randf_range(0.0, p.stream.get_length() * 0.9))
		swap_in = rng.randf_range(_SWAP_MIN, _SWAP_MAX)
		started.append(k)
		if started.size() > 64:
			started.pop_front()

func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	if _vehicle == null:
		push_error("CrashAudio must be a child of a Vehicle")
		set_process(false)
		set_physics_process(false)
		return
	# Contact reports only; it changes nothing in the simulation.
	_vehicle.contact_monitor = true
	_vehicle.max_contacts_reported = maxi(_vehicle.max_contacts_reported, 6)
	_prev_vel = _vehicle.linear_velocity
	_rng.seed = 5150
	for pool_name in POOLS:
		_pools[pool_name] = pool(pool_name)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "HitVoice%d" % i
		p.bus = &"Tires"
		add_child(p)
		_voices.append(p)
	for kind in LOOPS:
		var layer := LoopLayer.new()
		layer.pool = pool("loop_" + kind)
		layer.gain = LOOPS[kind]
		for side in ["A", "B"]:
			var p := AudioStreamPlayer.new()
			p.name = "Scrape%s%sAudio" % [String(kind).capitalize(), side]
			p.bus = &"Tires"
			p.volume_db = -80.0
			add_child(p)
			layer.players.append(p)
		_loops[kind] = layer
	for kind in SCRAPE_KINDS:
		_grace[kind] = 0
		_rel_speed[kind] = 0.0

func _physics_process(delta: float) -> void:
	_wait = maxf(_wait - delta, 0.0)
	_ground_wait = maxf(_ground_wait - delta, 0.0)
	var v := _vehicle.linear_velocity
	var dv := v - _prev_vel
	_prev_vel = v
	_read_contacts(v)
	var touching := false
	for kind in _grace:
		touching = touching or _grace[kind] > 0
	var dvh := Vector2(dv.x, dv.z).length()
	if _hit_left >= 0.0:
		_hit_dv += dvh
		_hit_left -= delta
		if _hit_left < 0.0:
			impact(_hit_dv, _hit_surface)
			_hit_dv = 0.0
	elif dvh / delta > IMPACT_ACCEL and touching:
		_hit_dv = dvh
		_hit_left = HIT_WINDOW
		_hit_surface = _dominant_surface()
	# the body slamming down on the road
	var up := maxf(dv.y, 0.0)
	if _ground_left >= 0.0:
		_ground_dv += up
		_ground_left -= delta
		if _ground_left < 0.0:
			if _ground_dv >= GROUND_DV:
				ground_hit(_ground_dv)
			_ground_dv = 0.0
	elif up / delta > IMPACT_ACCEL and _grace["underbody"] > 0:
		_ground_dv = up
		_ground_left = HIT_WINDOW

## Sorts this tick's contacts into surfaces, and how fast the body slides
## against each.
func _read_contacts(v: Vector3) -> void:
	var seen := {}
	var st := PhysicsServer3D.body_get_direct_state(_vehicle.get_rid())
	if st != null:
		for i in st.get_contact_count():
			var obj := st.get_contact_collider_object(i)
			var kind := classify(obj, st.get_contact_local_normal(i))
			var rel := v
			if obj is RigidBody3D:
				rel = v - (obj as RigidBody3D).linear_velocity
			seen[kind] = maxf(seen.get(kind, 0.0), rel.length())
	for kind in _grace:
		if seen.has(kind):
			_grace[kind] = CONTACT_GRACE
			_rel_speed[kind] = seen[kind]
		else:
			_grace[kind] = maxi(_grace[kind] - 1, 0)

## Which surface a contact is: another car, a tagged surface, the road under
## the body (a mostly vertical normal), or a wall.
static func classify(obj: Object, normal: Vector3) -> String:
	if obj is Vehicle:
		return "car"
	if obj != null and obj.has_meta(&"audio_surface"):
		var s := String(obj.get_meta(&"audio_surface"))
		if s in SURFACES:
			return s
	if absf(normal.y) > 0.6:
		return "underbody"
	return "concrete"

func _dominant_surface() -> String:
	for s in ["car", "metal", "concrete"]:
		if _grace[s] > 0:
			return s
	return "concrete"   # only the underbody touching: asphalt hits sound like concrete

func _process(delta: float) -> void:
	var targets := {}
	var speeds := {}
	for kind in SCRAPE_KINDS:
		var touching: bool = _grace[kind] > 0
		var sp: float = _rel_speed[kind]
		if forced_scrape_speed >= 0.0:
			touching = kind == forced_scrape_kind
			sp = forced_scrape_speed
		speeds[kind] = sp
		targets[kind] = smoothstep(SCRAPE_FROM, SCRAPE_FULL, sp) if touching else 0.0
	var spark := 0.0
	var spark_speed := 0.0
	for kind in SPARK_KINDS:
		if targets[kind] > 0.0:
			spark = maxf(spark, smoothstep(SPARKS_FROM, SPARKS_FULL, speeds[kind]))
			spark_speed = maxf(spark_speed, speeds[kind])
	scrape_level = 0.0
	scrape_kind = ""
	for kind in SCRAPE_KINDS:
		var layer: LoopLayer = _loops[kind]
		var sp: float = speeds[kind]
		var pitch := 0.8 + 0.4 * clampf(sp / 30.0, 0.0, 1.2)
		if layer.update(targets[kind], delta, pitch, _rng, ATTACK, RELEASE) and sp > BITE_FROM and kind != "underbody":
			_fire("scrape_bite", clampf(sp / 20.0, 0.4, 1.0), pitch)
		if layer.level > scrape_level:
			scrape_level = layer.level
			scrape_kind = kind
	(_loops["sparks"] as LoopLayer).update(spark, delta, 0.9 + 0.2 * clampf(spark_speed / 30.0, 0.0, 1.0), _rng, ATTACK, RELEASE)

## Plays one hit of this size (m/s of velocity change) off `surface`
## (concrete, metal or car). Public so the listen pack and tests can fire hits
## directly.
func impact(dv: float, surface := "concrete") -> void:
	if dv < MIN_DV or _wait > 0.0:
		return
	if not (surface in SURFACES):
		surface = "concrete"
	_wait = COOLDOWN
	impact_count += 1
	last_dv = dv
	last_surface = surface
	if dv < THUD_DV:
		last_tier = "tap"
		_fire("tap_" + surface, 0.4 + 0.6 * dv / THUD_DV)
		return
	# bigger hits sit a little lower
	var weight := 1.0 - 0.08 * clampf((dv - CRUNCH_DV) / 10.0, 0.0, 1.0)
	_fire("thud_" + surface, clampf(dv / CRUNCH_DV, 0.5, 1.0), weight)
	last_tier = "thud"
	if dv >= SPARK_DV and surface != "car" and _rng.randf() < SPARK_CHANCE:
		_fire("sparks", clampf(dv / 12.0, 0.5, 1.0))
	if dv >= DEBRIS_DV:
		_fire("debris", clampf(dv / 14.0, 0.45, 1.0))
	if dv >= CRUNCH_DV:
		last_tier = "crunch"
		_fire("crunch", clampf(dv / 15.0, 0.55, 1.0), weight)
	if dv >= GLASS_DV and _rng.randf() < GLASS_CHANCE:
		last_tier = "glass"
		_fire("glass", clampf(dv / 18.0, 0.6, 1.0))

## The body slamming onto the road, `dv` m/s upward change.
func ground_hit(dv: float) -> void:
	if _ground_wait > 0.0:
		return
	_ground_wait = GROUND_COOLDOWN
	ground_hits += 1
	_fire("ground_hit", clampf(dv / 7.0, 0.4, 1.0))
	if _vehicle != null and _vehicle.linear_velocity.length() > SPARKS_FROM and _rng.randf() < 0.5:
		_fire("sparks", clampf(dv / 10.0, 0.4, 0.8))

func _fire(pool_name: String, level: float, pitch := 1.0) -> void:
	var pl: Pool = _pools[pool_name]
	var k := pl.pick(_rng)
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	p.stream = pl.streams[k]
	p.volume_db = linear_to_db(POOLS[pool_name] * level) + _rng.randf_range(-VOLUME_JITTER_DB, VOLUME_JITTER_DB)
	p.pitch_scale = pitch * (1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER))
	p.play()
	plays.append({"pool": pool_name, "take": k, "db": p.volume_db, "pitch": p.pitch_scale})
	if plays.size() > PLAY_LOG:
		plays.pop_front()

## A pool by name ("thud_metal", "loop_car", ...): its takes, generated on
## first use.
static func pool(pname: String) -> Pool:
	var pl := Pool.new()
	pl.name = pname
	for k in (LOOP_TAKES if pname.begins_with("loop_") else VARIANTS):
		pl.streams.append(stream("%s%d" % [pname, k]))
	return pl

## One take ("tap_concrete0", "loop_metal5", ...): the rendered file in
## assets/sfx/crash (tools/render_crash_sfx.gd), or generated from the recipe
## if the file is missing.
static func stream(layer: String) -> AudioStreamWAV:
	if not _streams.has(layer):
		var path := CrashSfx.path(layer)
		var s: AudioStreamWAV
		if ResourceLoader.exists(path):
			s = load(path)
			if layer.begins_with("loop_"):
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = roundi(s.get_length() * s.mix_rate)
		else:
			s = AudioDsp.cached("res://scripts/crash_sfx.gd", layer, CrashSfx.make.bind(layer))
		_streams[layer] = s
	return _streams[layer]
