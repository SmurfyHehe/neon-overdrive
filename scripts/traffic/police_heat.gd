class_name PoliceHeat
extends Node

# Police sight, offences and heat (F0/F1, rewritten for P1 + P2 by the
# rulebook in scripts/traffic/police_rules.gd). Heat is one number, 0..5; its
# whole part is the level, and every level has its own icon on the HUD
# (scripts/ui/heat_icons.gd):
#
#   1 one patrol car   2 two cars   3 sawhorse (roadblock)   4 spike strip
#   5 helicopter
#
# (The strip's icon stays until the art stage; no spikes exist anywhere.)
#
# Bad cops (the ones who take tonight's cash, scripts/core/wallet.gd) get no
# icon on purpose: a cop registered as bad never raises heat.
#
# What a cop does with what it sees:
#
# 1. Sight, 10 times a second (PoliceRules.LOOK_HZ), at most
#    MAX_RAYS_PER_TICK line-of-sight rays across all cops. Per cop: the cone
#    (reach by the lamps, mirrors for a driving cop when you are 25 km/h
#    faster, radar car 150 m), and the all-round 12 m.
# 2. Offences are only ever counted when seen: a judged one (speeding) needs
#    the cone for 1.0 s in a row (radar: at once); the others are noticed by
#    the cone or the all-round 12 m.
# 3. A soft offence at heat 0 is a warning first (P2): the dim icon, one
#    flash and whoop from the cop, a loudspeaker line the first time tonight,
#    5 s to comply; no second warning inside 2 minutes. Otherwise it is heat.
# 4. Heat rises by events and +1 per 45 s seen and still offending; it
#    drops one level after a time unseen (PoliceRules.UNSEEN_DROP_SECS),
#    halved in a hiding pocket with lights off, and dawn clears it.
#
# The hook every police system asks is cop_can_see_player(cop).
#
# F0/F1 does not chase or bust yet: nothing here starts SaveStore chases.
# Heat numbers are placeholders for the balance stage (G).

const RoadMap := preload("res://scripts/world/road_map.gd")

signal level_changed(level: int)
signal spotted(cop: Node3D)
signal line_said(text: String)
## P2: a warning begins (the dim icon, cop flash) and ends. `complied` = the
## player got back under the line / into the lane in time (no heat).
signal warning_started(cop: Node3D, kind: int)
signal warning_ended(complied: bool)
## An offence was seen and counted (or turned into a warning), for tests and
## the later stages.
signal offence_seen(kind: int, cop: Node3D)

enum { NONE, ONE_CAR, TWO_CARS, ROADBLOCK, SPIKES, HELICOPTER }
const MAX_LEVEL := HELICOPTER
## Icon per level (HeatIcons draws them). Level 0 has none; neither do bad cops.
const ICONS := ["", "car", "two_cars", "sawhorse", "spikes", "helicopter"]

## The old names, now the table's numbers (scripts/traffic/police_rules.gd).
const SEE_RANGE_LIT := PoliceRules.REACH_LOW
const SEE_RANGE_HIGH := PoliceRules.REACH_HIGH
const SEE_RANGE_DARK := PoliceRules.REACH_DARK
const SEE_NEAR := PoliceRules.ALL_ROUND
const SEE_HALF_ANGLE := PoliceRules.CONE_HALF_ANGLE
const MIRROR_RANGE := PoliceRules.MIRROR_RANGE
const EYE_HEIGHT := PoliceRules.EYE_HEIGHT
const TARGET_HEIGHT := PoliceRules.TARGET_HEIGHT
const CHECK_EVERY := 1.0 / PoliceRules.LOOK_HZ
const BARRIER_SKIPS := 3

## Night one.
const WARN_RANGE := 220.0
const WARNING_LINE := "Patrol car up ahead. First night out, so listen: they spot headlights long before they spot a car. Go dark and you were never here."
const MOCK_LINE := "And there it is. Lit up and flying past a patrol car on night one. Smile for the dashcam."

var player: Node3D
var night_clock: NightClock:
	set(v):
		if night_clock != null and night_clock.night_ended.is_connected(_on_dawn):
			night_clock.night_ended.disconnect(_on_dawn)
		night_clock = v
		if night_clock != null:
			night_clock.night_ended.connect(_on_dawn)
## Tonight's events (a crackdown tightens the offence line).
var world_mood: WorldMood
## The signalised crossing (red-light offence); null = none.
var junction: Junction
## "" = ask the road map; tests set "city" / "highway".
var area_override := ""
## () -> float: km/h of the traffic flow in the player's lane, so matching
## the flow is never speeding. Unset = no exemption.
var flow_kmh := Callable()
## (Vector3) -> bool: a street lamp or a lit district at that world position
## (lights off is seen from 40 m instead of 18 m there).
var lit_here := Callable()
## Race hooks: `racing` is the race core's flag; `racers` are the other cars
## in a race, any of them over the line side by side with the player counts.
var racing := false
var racers: Array[Node3D] = []
## Set by the hiding-pocket stage; halves the unseen time with lights off.
var in_hiding_pocket := false
## Set by the helicopter stage: level 5 does not drop while it has you.
var helicopter_sees := false

var heat := 0.0
var level := NONE
var seen := false              # a (good) cop notices the player right now
var seen_by: Node3D
var cops: Array[Node3D] = []
var bad_cops: Array[Node3D] = []
## Cops that called the chase off (CopBrain): they see nothing for the heat
## until it is gone, so a terminated pursuit can cool.
var stood_down: Array[Node3D] = []
var warned := false
var mocked := false
## P2.
var warning_active := false
var warning_kind := -1
var warning_cop: Node3D
var warnings_given := 0
var _warn_t := 0.0
var _warn_cooldown := 0.0
var _speaker_said := false
## Offence clocks.
var _over_t := 0.0
var _flag_t := 0.0
var _flag_fired := false
var _flag_extra := false
var _wrong_t := 0.0
var _wrong_fired := false
var _race_latched := false
var _esc_t := 0.0
var _unseen_t := 0.0
var _crash_t := 0.0
var _flee_t := 0.0
var _prev_side := 0
var _prev_z := 0.0
var _have_prev := false
var _x_hist: Array[Vector2] = []   # (time, road x) for the fault test
var _clock := 0.0
var _acc := 0.0
var _start := 0
var _cs := {}                  # cop -> {cone, near, run, see, los}
var _ray := PhysicsRayQueryParameters3D.new()
var _rays_left := 0

func register_cop(cop: Node3D, bad := false) -> void:
	var list := bad_cops if bad else cops
	if not cop in list:
		list.append(cop)

func unregister_cop(cop: Node3D) -> void:
	cops.erase(cop)
	bad_cops.erase(cop)
	stood_down.erase(cop)
	_cs.erase(cop)
	if seen_by == cop:
		seen_by = null
	if warning_cop == cop:
		warning_cop = null

## Busted (police_patrol.gd): the chase is over, heat starts from nothing.
func bust() -> void:
	_clear_heat()
	_cancel_warning()

## Run restarted: no heat, and night one may warn again.
func reset() -> void:
	_clear_heat()
	warned = false
	mocked = false
	_speaker_said = false
	_warn_cooldown = 0.0
	_cancel_warning()
	_cs.clear()

func _clear_heat() -> void:
	heat = 0.0
	stood_down.clear()
	seen = false
	seen_by = null
	_unseen_t = 0.0
	_esc_t = 0.0
	_over_t = 0.0
	_flag_t = 0.0
	_flag_fired = false
	_flag_extra = false
	_wrong_t = 0.0
	_wrong_fired = false
	_crash_t = 0.0
	_flee_t = 0.0
	_set_level(NONE)

## Dawn: heat to 0, and the first warning of the next night speaks again.
func _on_dawn(_night: int) -> void:
	_clear_heat()
	_cancel_warning()
	_speaker_said = false
	_warn_cooldown = 0.0

static func icon_for(lvl: int) -> String:
	return ICONS[clampi(lvl, 0, MAX_LEVEL)]

## How far a cop sees this car by its lamps: dark, low beam or high beam.
## (`lit` = a street lamp or a lit district: lights off is seen from 40 m.)
static func see_reach_for(car: Node, lit := false) -> float:
	if car != null and car.has_method("beam_mode"):
		return PoliceRules.reach(int(car.call("beam_mode")), lit)
	return PoliceRules.reach(1 if headlights_on(car) else 0, lit)

static func headlights_on(car: Node) -> bool:
	if car == null:
		return false
	if "headlights_on" in car:
		return bool(car.headlights_on)
	var l := car.get_node_or_null("Headlights") as Node3D
	return l != null and l.visible

## Geometry only (no walls): whether a cop at `cop_xf` (facing its -Z) can
## see a car at `target`, lit or not.
static func can_see(cop_xf: Transform3D, target: Vector3, lights_on: bool) -> bool:
	return can_see_within(cop_xf, target, SEE_RANGE_LIT if lights_on else SEE_RANGE_DARK)

## Same, with the reach given (see_reach_for): the all-round radius, the cone
## and (`mirrors`) the mirrors.
static func can_see_within(cop_xf: Transform3D, target: Vector3, reach: float, mirrors := true) -> bool:
	if cop_xf.origin.distance_to(target) <= SEE_NEAR:
		return true
	return PoliceRules.in_cone(cop_xf, target, reach, mirrors)

func _lit_at(pos: Vector3) -> bool:
	return lit_here.is_valid() and bool(lit_here.call(pos))

func _kmh_of(n: Object) -> float:
	if n is RigidBody3D:
		return (n as RigidBody3D).linear_velocity.length() * 3.6
	return 0.0

## A cop that drives (a patrol) has mirrors; a parked one (radar car) does not.
func _mirrors_for(cop: Node3D, player_kmh: float) -> bool:
	if cop.get_meta(&"parked", false):
		return false
	return player_kmh - _kmh_of(cop) >= PoliceRules.MIRROR_FASTER_KMH

## The geometry of what this cop sees of the player: {cone, near}.
func _geometry(cop: Node3D, player_kmh: float) -> Dictionary:
	var pos := player.global_position
	var xf := cop.global_transform
	var reach := see_reach_for(player, _lit_at(pos))
	var cone := PoliceRules.in_cone(xf, pos, reach, _mirrors_for(cop, player_kmh))
	if not cone and cop.get_meta(&"radar", false):
		cone = PoliceRules.in_cone(xf, pos, PoliceRules.RADAR_RANGE, false)
	return {"cone": cone, "near": PoliceRules.is_near(xf.origin, pos)}

## THE hook: can this cop see the player right now? Range, view cone and
## headlights, then a ray for walls, buildings and cars in between.
func cop_can_see_player(cop: Node3D) -> bool:
	if player == null or cop == null or not is_instance_valid(cop) or not cop.is_inside_tree():
		return false
	var g := _geometry(cop, _kmh_of(player))
	if not (g.cone or g.near):
		return false
	return _line_of_sight(cop)

## One ray from the cop's eye to the car. The centre barrier and the side
## rails have boxes taller than they look (0.65 m), made for cars, so they are
## looked over: the ray is cast again past them (up to BARRIER_SKIPS times).
func _line_of_sight(cop: Node3D) -> bool:
	var space := cop.get_world_3d().direct_space_state
	if space == null:
		return true
	_ray.from = cop.global_position + Vector3.UP * EYE_HEIGHT
	_ray.to = player.global_position + Vector3.UP * TARGET_HEIGHT
	var ex: Array[RID] = []
	for n in [cop, player]:
		if n is CollisionObject3D:
			ex.append((n as CollisionObject3D).get_rid())
	for i in BARRIER_SKIPS + 1:
		_ray.exclude = ex
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			return true
		var col := hit.collider as CollisionObject3D
		if col == null or col.name != &"BarrierCol" or i == BARRIER_SKIPS:
			return false
		ex.append(col.get_rid())
	return false

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_clock += delta
	_acc += delta
	if _acc < CHECK_EVERY - 0.0001:
		return
	var dt := _acc
	_acc = 0.0
	_look(dt)
	_apply(dt)

# ---------- sight ----------

func _look(dt: float) -> void:
	cops = cops.filter(func(c: Node3D) -> bool: return is_instance_valid(c))
	bad_cops = bad_cops.filter(func(c: Node3D) -> bool: return is_instance_valid(c))
	var was := seen
	seen = false
	seen_by = null
	var nearest := INF
	var pk := _kmh_of(player)
	_rays_left = PoliceRules.MAX_RAYS_PER_TICK
	var n := cops.size()
	for j in n:
		var c := cops[(_start + j) % n]
		nearest = minf(nearest, c.global_position.distance_to(player.global_position))
		var s: Dictionary = _cs.get(c, {"cone": false, "near": false, "run": 0.0, "see": 0.0, "los": true})
		if stood_down.has(c):
			# it called this chase off: it is not watching you until the heat is gone
			s.cone = false
			s.near = false
			s.run = 0.0
			s.see = 0.0
			_cs[c] = s
			continue
		var g := _geometry(c, pk)
		var los: bool = s.los
		if g.cone or g.near:
			if _rays_left > 0:
				_rays_left -= 1
				los = _line_of_sight(c)
		else:
			los = true
		s.los = los
		s.cone = g.cone and los
		s.near = g.near and los
		s.run = float(s.run) + dt if s.cone else 0.0
		s.see = float(s.see) + dt if (s.cone or s.near) else 0.0
		_cs[c] = s
		if not seen and (s.cone or s.near):
			seen = true
			seen_by = c
	if n > 0:
		_start = (_start + 1) % n
	if _night_one() and not warned and nearest <= WARN_RANGE:
		warned = true
		line_said.emit(WARNING_LINE)
	if seen and not was:
		spotted.emit(seen_by)

## The first good cop that judges speed now: the cone for JUDGE_SECS in a row,
## or at once for the radar car. A distracted parked cop (CopAlertness) takes
## its factor longer.
func _judge_cop() -> Node3D:
	for c in cops:
		var s: Dictionary = _cs.get(c, {})
		if s.is_empty() or not s.cone:
			continue
		if float(s.run) >= PoliceRules.judge_secs(CopAlertness.delay_of(c), c.get_meta(&"radar", false)):
			return c
	return null

## A cop that notices the player for an offence needing no speed judgement:
## the cone or the all-round 12 m (a distracted parked cop: after the extra
## of its factor in sight).
func _notice_cop() -> Node3D:
	for c in cops:
		var s: Dictionary = _cs.get(c, {})
		if not s.is_empty() and (s.cone or s.near) and float(s.get("see", 0.0)) >= PoliceRules.notice_secs(CopAlertness.delay_of(c)):
			return c
	return null

# ---------- offences and heat ----------

func _crackdown() -> bool:
	return world_mood != null and world_mood.crackdown_until >= 0.0

func _area(z: float) -> String:
	if area_override != "":
		return area_override
	return PoliceRules.area_at(RoadFrame.s_at(z))

func _apply(dt: float) -> void:
	var p := RoadFrame.unroll(player.global_position)
	var kmh := _kmh_of(player)
	var area := _area(p.z)
	var flow := -1.0
	if flow_kmh.is_valid():
		flow = float(flow_kmh.call())
	var speeding := PoliceRules.is_speeding(kmh, area, _crackdown(), flow)
	var flagrant := PoliceRules.is_flagrant(kmh, area)
	var wrong := p.x < -RoadChunkBuilder.MEDIAN_GAP and kmh > 5.0
	_x_hist.append(Vector2(_clock, p.x))
	while _x_hist.size() > 1 and _x_hist[0].x < _clock - PoliceRules.FAULT_LOOKBACK - 0.3:
		_x_hist.pop_front()
	var judge := _judge_cop()
	var notice := _notice_cop()
	if _warn_cooldown > 0.0:
		_warn_cooldown = maxf(_warn_cooldown - dt, 0.0)

	# Speeding: over the line for a second, and a cop that has judged it.
	_over_t = _over_t + dt if speeding else 0.0
	if speeding and judge != null and _over_t >= PoliceRules.SPEED_HOLD_SECS and not (flagrant and _flag_fired):
		_offence(PoliceRules.Offence.SPEEDING, judge, area)
	# Flagrant: 60+ over the posted limit; held 5 s seen is one more.
	if flagrant and judge != null:
		_flag_t += dt
		if not _flag_fired:
			_flag_fired = true
			_offence(PoliceRules.Offence.FLAGRANT, judge, area)
		if _flag_t >= PoliceRules.FLAGRANT_HOLD and not _flag_extra and heat >= 1.0:
			_flag_extra = true
			_add_heat(1.0)
	elif not flagrant:
		_flag_t = 0.0
		_flag_fired = false
		_flag_extra = false
	# The wrong way: in the oncoming lanes for 2 s, noticed.
	_wrong_t = _wrong_t + dt if wrong else 0.0
	if wrong and notice != null and _wrong_t >= PoliceRules.WRONG_SIDE_SECS and not _wrong_fired:
		_wrong_fired = true
		_offence(PoliceRules.Offence.WRONG_SIDE, notice, area)
	elif not wrong:
		_wrong_fired = false
	# The median gap: crossing the centre line where the barrier is open.
	var side := 1 if p.x >= 0.0 else -1
	if _prev_side != 0 and side != _prev_side and notice != null:
		if RoadMap.gap_in(floori(RoadFrame.s_at(p.z) / RoadChunkBuilder.CHUNK_LEN)):
			_offence(PoliceRules.Offence.MEDIAN_GAP, notice, area)
	_prev_side = side
	# A red light with a cop at the junction.
	_red_light(p, notice, area)
	# Racing.
	var racing_now := racing or _side_by_side(kmh, area, flow)
	if racing_now and notice != null and not _race_latched:
		_race_latched = true
		_offence(PoliceRules.Offence.RACING, notice, area)
	elif not racing_now:
		_race_latched = false
	# Driving off after a crash while seen.
	if _crash_t > 0.0:
		_crash_t -= dt
		if kmh > PoliceRules.FLEE_KMH and notice != null:
			_flee_t += dt
			if _flee_t >= 2.0:
				_flee_t = 0.0
				_crash_t = 0.0
				_offence(PoliceRules.Offence.HIT_AND_RUN, notice, area)
		else:
			_flee_t = 0.0

	var offending := (speeding and judge != null) or (wrong and notice != null) or racing_now
	_update_heat(dt, offending)
	_update_warning(dt, speeding, flagrant, wrong)

func _side_by_side(kmh: float, area: String, flow: float) -> bool:
	if racers.is_empty() or not PoliceRules.is_speeding(kmh, area, _crackdown(), flow):
		return false
	for r in racers:
		if not is_instance_valid(r):
			continue
		var d := r.global_position - player.global_position
		if absf(d.dot(player.global_transform.basis.x)) <= 8.0 and absf(d.dot(player.global_transform.basis.z)) <= 15.0:
			if PoliceRules.is_speeding(_kmh_of(r), area, _crackdown(), flow):
				return true
	return false

func _red_light(p: Vector3, notice: Node3D, area: String) -> void:
	var z := p.z
	var had := _have_prev
	var pz := _prev_z
	_prev_z = z
	_have_prev = true
	if not had or junction == null or not Junction.enabled or notice == null:
		return
	if junction.main_state() != Junction.RED:
		return
	var dz := z - pz
	if absf(dz) < 0.01:
		return
	var dir := signf(dz)
	var c := Junction.centre_z_near(z)
	var line := c - dir * Junction.STOP_OFF
	if (line - pz) * dir >= 0.0 and (line - z) * dir < 0.0 and absf(z - c) < 40.0:
		if notice.global_position.distance_to(player.global_position) <= PoliceRules.JUNCTION_COP_RANGE:
			_offence(PoliceRules.Offence.RED_LIGHT, notice, area)

## A contact reported by the player's WreckSensor (`touched`): `other` is
## whatever was hit, `closing_kmh` how fast the two came together.
func on_contact(other: Object, closing_kmh: float) -> void:
	if player == null or other == null:
		return
	if other in bad_cops:
		return
	var area := _area(RoadFrame.unroll(player.global_position).z)
	if other in cops:
		# A cop that drives into you (the chaser's nudge, a box-in) is not your
		# offence: the same fault test as for a crash with traffic (P6).
		if level >= ONE_CAR and not player_at_fault(other as Node3D):
			return
		var kind := PoliceRules.Offence.RAM_COP if closing_kmh >= PoliceRules.BUMP_KMH else PoliceRules.Offence.TOUCH_COP
		_offence(kind, other as Node3D, area)
		return
	if not other is TrafficCar or closing_kmh < PoliceRules.BUMP_KMH:
		return
	var notice := _notice_cop()
	if notice == null or not player_at_fault(other as Node3D):
		return
	_crash_t = PoliceRules.FLEE_SECS
	_flee_t = 0.0
	_offence(PoliceRules.Offence.CRASH, notice, area)

## The fault test (PoliceRules.player_at_fault) from the cars' road-space state.
func player_at_fault(other: Node3D) -> bool:
	var p := RoadFrame.unroll(player.global_position)
	var o := RoadFrame.unroll(other.global_position)
	var pv := RoadFrame.dir_to_road(p.z, (player as RigidBody3D).linear_velocity) if player is RigidBody3D else Vector3.ZERO
	var ov := Vector3.ZERO
	if other is RigidBody3D:
		ov = RoadFrame.dir_to_road(o.z, (other as RigidBody3D).linear_velocity)
	var dirn := -1.0 if pv.z < 0.0 else 1.0
	var x_before := p.x
	for s in _x_hist:
		if s.x >= _clock - PoliceRules.FAULT_LOOKBACK:
			x_before = s.y
			break
	return PoliceRules.player_at_fault((o.z - p.z) * dirn, pv.z * dirn, ov.z * dirn, p.x, x_before, o.x, RoadChunkBuilder.LANE_W * 0.5)

## One offence, seen by `cop`. Soft ones at heat 0 become a warning first.
func _offence(kind: int, cop: Node3D, area: String) -> void:
	if cop in bad_cops:
		return
	var o: Dictionary = PoliceRules.OFFENCES[kind]
	if o.warn:
		if level >= ONE_CAR or warning_active:
			return   # already wanted: it shows as the +1 per 45 s, not a new event
		offence_seen.emit(kind, cop)
		if _warn_cooldown <= 0.0:
			_start_warning(kind, cop, area)
			return
	else:
		offence_seen.emit(kind, cop)
	if o.get("add", false):
		_add_heat(float(o.heat))
	else:
		_raise_to(float(o.heat))

func _raise_to(h: float) -> void:
	heat = minf(maxf(heat, h), float(MAX_LEVEL) + 0.999)
	_set_level(clampi(int(floor(heat)), NONE, MAX_LEVEL))

func _add_heat(h: float) -> void:
	heat = minf(heat + h, float(MAX_LEVEL) + 0.999)
	_set_level(clampi(int(floor(heat)), NONE, MAX_LEVEL))

func _update_heat(dt: float, offending: bool) -> void:
	if seen:
		_unseen_t = 0.0
		if offending and heat >= 1.0:
			_esc_t += dt
			if _esc_t >= PoliceRules.ESCALATE_SECS:
				_esc_t = 0.0
				_add_heat(1.0)
		else:
			_esc_t = 0.0
	else:
		_esc_t = 0.0
		_unseen_t += dt
		var l := clampi(int(floor(heat)), NONE, MAX_LEVEL)
		var blocked := l == HELICOPTER and helicopter_sees
		var dark := see_reach_for(player) <= SEE_RANGE_DARK
		if l >= ONE_CAR and not blocked and _unseen_t >= PoliceRules.drop_after(l, in_hiding_pocket and dark):
			_unseen_t = 0.0
			heat = maxf(floorf(heat) - 1.0, 0.0)
	_set_level(clampi(int(floor(heat)), NONE, MAX_LEVEL))

# ---------- the warning step (P2) ----------

func _start_warning(kind: int, cop: Node3D, area: String) -> void:
	warning_active = true
	warning_kind = kind
	warning_cop = cop
	_warn_t = PoliceRules.WARN_SECS
	_warn_cooldown = PoliceRules.WARN_COOLDOWN
	warnings_given += 1
	if cop != null and cop.has_method("warn_flash"):
		cop.call("warn_flash")
	if not _speaker_said:
		_speaker_said = true
		line_said.emit(PoliceRules.WARN_LINES[PoliceRules.area_name(area)])
	warning_started.emit(cop, kind)

func _cancel_warning() -> void:
	if warning_active:
		warning_active = false
		warning_kind = -1
		warning_cop = null
		warning_ended.emit(true)

## Whether the thing the cop warned about is still going on.
func _still_offending(kind: int, speeding: bool, flagrant: bool, wrong: bool) -> bool:
	match kind:
		PoliceRules.Offence.SPEEDING:
			return speeding
		PoliceRules.Offence.FLAGRANT:
			return flagrant or speeding
		PoliceRules.Offence.WRONG_SIDE:
			return wrong
	return false   # a red light or a touch cannot be undone or kept up: it was only the warning

func _update_warning(dt: float, speeding: bool, flagrant: bool, wrong: bool) -> void:
	if not warning_active:
		return
	_warn_t -= dt
	if not _still_offending(warning_kind, speeding, flagrant, wrong):
		warning_active = false
		warning_kind = -1
		warning_cop = null
		warning_ended.emit(true)   # back under the line / in the lane: no heat
		return
	if _warn_t <= 0.0:
		warning_active = false
		warning_kind = -1
		warning_cop = null
		_raise_to(1.0)   # ignored: heat 1 and the chase starts (a later stage)
		warning_ended.emit(false)

func _set_level(l: int) -> void:
	if l != level:
		var was := level
		level = l
		if was == NONE and l >= ONE_CAR and _night_one() and not mocked:
			mocked = true
			line_said.emit(MOCK_LINE)
		level_changed.emit(l)

func _night_one() -> bool:
	return night_clock == null or night_clock.night == 1
