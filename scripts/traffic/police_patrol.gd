class_name PolicePatrol
extends Node3D

# The police dispatcher (the spec's "PoliceDispatch"; police steps F1, P5, P6).
# It owns the police slots: at most PoliceRules.MAX_COPS driving cops, never
# more. Every cop is a PatrolCar with a CopBrain, in the traffic index
# (TrafficManager.adopt) and registered with PoliceHeat, which decides what it
# sees.
#
# No chase (heat 0): one patrol car at a time, as before. It appears out past
# the reveal distance, in fog, never in view (the same rule as traffic:
# tests/traffic/no_visible_spawn.gd), alternating oncoming and same-direction
# lanes, at that lane's traffic speed. Once it is well behind or far off, it
# goes and the next one comes PATROL_GAP later.
#
# A chase (heat 1 or more): as many cops as the heat icon shows (1, 2, then 3),
# one new one every SPAWN_GAP at most, each with a role (CopBrain.Role):
#   chaser   first. From behind, out of sight (or the patrol that saw you).
#   blocker  from heat 2. From AHEAD, out of sight, in your lane, driving
#            slower than you so you catch it up.
#   flanker  from heat 3. From behind, out of sight.
# Nobody is ever placed in view, and nobody drives faster than its car can.
# A cop that has called the chase off, or is cruising on Patrol, is dropped
# once it is far off and out of view, which frees its slot.
#
# This node also runs the bust ring (under 10 km/h with a chasing cop within
# 6 m for 3 s). Box-in is what the three roles do together when you are slow;
# the ring is what busts.
#
# NEON_POLICE=0 turns it off (tests/run_tests.bat does, so older drive tests
# meet no cop); the benchmark never has one.

const PATROL_GAP := 25.0       # s between one patrol leaving and the next
const SPAWN_PAST_REVEAL := 40.0
const DROP_PAST_REVEAL := 60.0
const RETRY := 1.0

## The chase began (the first cop went into Pursuit) / ended: escaped = heat
## cooled to nothing, not escaped = busted.
signal pursuit_started
signal pursuit_ended(escaped: bool)
## The bust ring filled. What a bust costs (ticket, tow, night one's warning)
## is the bust stage's; this only ends the chase and clears the heat.
signal busted(cop: Node3D)
## A cop was put on the road (tests: it must not be in view).
signal unit_spawned(car: PatrolCar, role: int)

class Unit:
	var car: PatrolCar
	var brain: CopBrain
	var ghost: Node3D
	var acc := 0.0

var player: Node3D
var traffic: TrafficManager
var heat: PoliceHeat
var units: Array[Unit] = []
## The first cop on the road and its brain (the patrol, before a chase).
var car: PatrolCar:
	get:
		return units[0].car if not units.is_empty() else null
var brain: CopBrain:
	get:
		return units[0].brain if not units.is_empty() else null
var oncoming_next := true
var spawn_count := 0
## The most cops that were ever on the road at once (tests).
var most_units := 0
## The bust ring, 0..1 (HeatIcons draws it).
var bust_fill := 0.0
var chasing := false
var busts := 0
var escapes := 0
## Game hook: whether the road has no centre barrier at road z.
var undivided_at := Callable()
var _wait := 3.0               # first patrol a few seconds in
var _dispatch_acc := 0.0
var _spawn_t := 0.0

static func enabled(benchmark: bool) -> bool:
	return not benchmark and OS.get_environment("NEON_POLICE") != "0"

## Builds what the first cop needs while the game loads: the patrol's spec
## and its body (sheet mesh and underside, cached per kind once built). Left
## to the first spawn, that was a 100-130 ms physics tick about 3 s into
## every drive in the cloud (speed ladder stress run, 2026-10-13), and again
## on a failed placement for the spec. Later cops reuse the cache (2 ms).
func _ready() -> void:
	var c := PatrolCar.make()
	NpcCarBuilder.chassis_visual(PatrolCar.KIND, c.build, c.color, c.role, true).free()
	c.free()

func _physics_process(delta: float) -> void:
	if player == null or traffic == null:
		return
	for i in range(units.size() - 1, -1, -1):
		if not is_instance_valid(units[i].car):
			units.remove_at(i)
	_dispatch_acc += delta
	if _dispatch_acc >= 1.0 / PoliceRules.DISPATCH_HZ:
		_dispatch(_dispatch_acc)
		_dispatch_acc = 0.0
	var pz := _player_z()
	for i in range(units.size() - 1, -1, -1):
		var u := units[i]
		# Shown, hidden and put on the rails by the traffic manager (adopted):
		# full crash physics within its pinned distance of the player.
		u.acc += delta
		if u.acc >= 1.0 / PoliceRules.BRAIN_HZ:
			u.brain.step(u.acc)
			u.acc = 0.0
		if u.brain.driver != null and u.brain.driver.recycle_due:
			u.brain.driver.recycle(u.car)   # stuck or flipped 5 s: back behind the player, out of view
		# A cop that is not chasing (cruising, or it called the chase off) goes
		# once it is far off and nobody can see it.
		if u.brain.state == CopBrain.State.PATROL and not (heat != null and heat.warning_active and heat.warning_cop == u.car):
			var d := absf(u.car.road_z() - pz)
			if d > traffic.reveal_distance() + DROP_PAST_REVEAL and not traffic.in_view(u.car.global_position):
				_drop(u)
	_chase_step(delta)

## Slots and roles, PoliceRules.DISPATCH_HZ times a second.
func _dispatch(dt: float) -> void:
	var level := heat.level if heat != null else PoliceHeat.NONE
	if level < PoliceHeat.ONE_CAR:
		_spawn_t = 0.0
		if units.is_empty():
			_wait -= dt
			if _wait <= 0.0:
				_wait = RETRY
				spawn()
		return
	_spawn_t -= dt
	var active := 0
	var roles := {}
	var terminated := false
	for u in units:
		if u.brain.stood_down_at < 0:
			active += 1
			roles[u.brain.role] = true
		else:
			terminated = true
	if terminated:
		# One honest cop called the chase off as too dangerous: that goes for
		# all of them, and nobody new is sent until the heat is gone.
		for u in units:
			u.brain.call_off()
		return
	if active >= PoliceRules.cops_wanted(level) or _spawn_t > 0.0:
		return
	if units.size() >= PoliceRules.MAX_COPS:
		# every slot is taken: one that is out of the chase and out of view makes room
		for u in units:
			if u.brain.stood_down_at >= 0 and not traffic.in_view(u.car.global_position):
				_drop(u)
				break
		return
	var role := CopBrain.Role.CHASER
	for r in [CopBrain.Role.CHASER, CopBrain.Role.BLOCKER, CopBrain.Role.FLANKER]:
		if not roles.has(r):
			role = r
			break
	_spawn_t = PoliceRules.SPAWN_GAP if spawn_unit(role) else RETRY

## The chase as a whole: started, the bust ring, escaped.
func _chase_step(delta: float) -> void:
	var on := heat != null and heat.level >= PoliceHeat.ONE_CAR
	var cop: PatrolCar = null
	var cop_dist := INF
	var any := false
	for u in units:
		if not u.brain.in_chase():
			continue
		any = true
		if u.car.detailed:
			var d := maxf(u.car.global_position.distance_to(player.global_position) - PoliceRules.BUST_BODY, 0.0)
			if d < cop_dist:
				cop_dist = d
				cop = u.car
	if on and not chasing and any:
		chasing = true
		bust_fill = 0.0
		pursuit_started.emit()
	if not chasing:
		bust_fill = 0.0
		return
	if not on:
		chasing = false
		bust_fill = 0.0
		escapes += 1
		pursuit_ended.emit(true)
		return
	bust_fill = PoliceRules.bust_step(bust_fill, delta, absf(heat._kmh_of(player)), cop_dist)
	if bust_fill >= 1.0:
		chasing = false
		bust_fill = 0.0
		busts += 1
		heat.bust()
		for u in units:
			u.brain.step(0.0)   # heat is gone: back to Patrol, lights off
		busted.emit(cop)
		pursuit_ended.emit(false)

## Puts a patrol car on the road now (no chase), if a slot is free. True if placed.
func spawn() -> bool:
	if not units.is_empty():
		return false
	var oncoming := oncoming_next
	var lane := 0
	if not traffic.lane_allowed(lane, oncoming):
		var used := traffic.onc_lanes_used if oncoming else traffic.own_lanes_used
		if used.is_empty():
			return false
		lane = used[0]
	var lane_x := TrafficManager.lane_centre(lane, oncoming)
	var dir := 1.0 if oncoming else -1.0
	var z := _player_z() - (traffic.reveal_distance() + SPAWN_PAST_REVEAL)
	var city := traffic.city_at(z, dir)
	var speed := traffic.lane_speed(lane, oncoming, city)
	if _place(lane_x, dir, z, speed, CopBrain.Role.CHASER, lane, oncoming, city) == null:
		return false
	oncoming_next = not oncoming_next
	return true

## Puts a cop with `role` on the road for the chase: the blocker ahead of the
## player, the others behind, out past the reveal distance and never in view.
## True if placed.
func spawn_unit(role: int) -> bool:
	if units.size() >= PoliceRules.MAX_COPS:
		return false
	var pu := RoadFrame.unroll(player.global_position)
	var vel: Vector3 = player.get("linear_velocity") if player.get("linear_velocity") is Vector3 else Vector3.ZERO
	var pvz := RoadFrame.dir_to_road(pu.z, vel).z
	var far := pu.x < 0.0
	# the way the player is going; standing still, the way its side of the road runs
	var pd := signf(pvz) if absf(pvz) > 2.0 else (1.0 if far else -1.0)
	var ahead := role == CopBrain.Role.BLOCKER
	var z := pu.z + pd * (traffic.reveal_distance() + SPAWN_PAST_REVEAL) * (1.0 if ahead else -1.0)
	var pv := absf(pvz)
	# ahead: slower than the player, so it is caught up; behind: the player's pace or better
	var speed := maxf(pv * 0.6, 12.0) if ahead else minf(maxf(pv, 20.0), PoliceRules.PATROL_TOP_KMH / 3.6)
	var lanes := traffic.onc_lanes if far else traffic.own_lanes
	var first := clampi(RoadChunkBuilder.lane_at(absf(pu.x)), 0, maxi(lanes, 1) - 1)
	var city := traffic.city_at(z, pd)
	for k in lanes:
		var lane := (first + k) % lanes
		if not traffic.lane_allowed(lane, far):
			continue
		if _place(TrafficManager.lane_centre(lane, far), pd, z, speed, role, lane, far, city) != null:
			return true
	return false

## One cop at (lane_x, z) going `dir`, if nobody can see the place and the
## slot is free. Null if not.
func _place(lane_x: float, dir: float, z: float, speed: float, role: int, lane: int, far: bool, city: bool) -> Unit:
	if units.size() >= PoliceRules.MAX_COPS:
		return null
	var c := PatrolCar.make()
	c.name = "Patrol%d" % spawn_count
	c.traffic = traffic
	c.target_speed = speed
	c.pace_lane = lane
	c.pace_far = far
	c.pace_city = city
	if traffic.in_view(RoadFrame.roll(Vector3(lane_x, c.rest_y, z))) or traffic._slot_check(c, lane_x, z, dir, speed).is_empty():
		c.free()
		return null
	add_child(c)
	c.place(lane_x, dir, z, c.rest_y, speed)
	traffic.adopt(c)
	var u := Unit.new()
	u.car = c
	u.ghost = Node3D.new()
	u.ghost.name = "LastSeen%d" % spawn_count
	add_child(u.ghost)
	u.brain = CopBrain.new(c, heat, traffic, player, u.ghost)
	u.brain.undivided_at = undivided_at
	u.brain.role = role
	u.brain.v_cap = PoliceRules.PATROL_TOP_KMH / 3.6
	u.acc = float(units.size()) * 0.03   # brains think on different ticks
	units.append(u)
	most_units = maxi(most_units, units.size())
	spawn_count += 1
	if heat != null:
		heat.register_cop(c)
	unit_spawned.emit(c, role)
	return u

## Takes the first cop off the road (the patrol, before a chase).
func drop() -> void:
	if not units.is_empty():
		_drop(units[0])

func _drop(u: Unit) -> void:
	units.erase(u)
	if is_instance_valid(u.car):
		if heat != null:
			heat.unregister_cop(u.car)
		traffic.disown(u.car)
		u.car.free_driver = null
		u.car.queue_free()
	if is_instance_valid(u.ghost):
		u.ghost.queue_free()
	if units.is_empty():
		_wait = PATROL_GAP

## Floating origin (game.gd): the cars are in the traffic manager's list
## (adopted), which moves them with the world; nothing to do here.
func shift_world(_offset: Vector3) -> void:
	pass

func _player_z() -> float:
	return RoadFrame.unroll(player.global_position).z
