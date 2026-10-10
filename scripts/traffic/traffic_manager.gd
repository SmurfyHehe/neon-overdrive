extends Node3D
class_name TrafficManager

# Traffic spawner and occupancy index (stage B step 3; milestone 3 2026-10-05,
# milestone 4 2026-10-06). Owns a fixed pool of TrafficCar nodes, places them
# in lanes, and recycles a car to a fresh slot once it is far behind the
# player, far ahead, or wrecked out of the player's sight. The car count never
# changes except through set_car_count(); recycling moves cars, it never frees
# or creates them, the same pattern as game.gd's chunk pool.
#
# Lanes: the road is 4 lanes each way (game.gd), own lanes at positive x and
# oncoming at negative x, lane i centred at RoadChunkBuilder.lane_offset(i).
# Every x and z here is road space (RoadFrame, #37): across and along the
# road, not world axes. On today's straight road the two are the same.
#
# Occupancy index (milestone 4): rebuilt at the top of every tick (this node
# runs before its cars). Every car and the player is an x-range across the
# road (its footprint, plus the target lane while it changes lane), a z and a
# z-velocity, bucketed by the lane slots the range touches. TrafficCar asks
# scan() for the nearest thing ahead or behind in a corridor: that is what it
# brakes for and what a lane change has to clear. A bucket holds a handful of
# cars, so a query is a few comparisons rather than one per car.
#
# Spawns (milestone 4): a slot must keep `lane_gap` to everything in its lane
# and a time to contact of SPAWN_TTC (SPAWN_TTC_PLAYER for the player, who may
# not brake) both ways, counting oncoming closing speed. Ahead of the player a
# car is placed beyond the draw distance, hidden, and drives into view instead
# of popping in close. Behind the player (own-direction lanes faster than the
# player only) it is placed where the camera cannot see it.
#
# Draw distance: `detail_distance` (at least REVEAL_MIN) is how far out cars are
# drawn, and the physics band never reaches past it; the pause menu's Traffic
# sliders set this and the car count live (TrafficSettings).
#
# Never visibly pop (Roy, 2026-10-09): a car is placed, recycled or removed only
# where no live camera can see it (ViewGuard: the current camera whichever view
# it is in, the mirrors while they draw, anything in the view_cameras group,
# with sight lines blocked by crests, buildings and walls counted), and it is
# drawn only inside reveal_distance(), where the world itself ends in fog. The
# one transition left is a car crossing that distance: it is ~93 % fogged there
# (exp fog, density 0.009, at 300 m) and the road chunks end at the same place.
#
# Physics band (near-band traffic, 2026-10-09): only cars within
# `physics_distance` of the player run the raycast sim and can crash; the rest
# drive on rails (TrafficCar.set_detailed(false)), drawn if inside the reveal
# distance. A car joins the sim at physics_distance and leaves it only past
# PHYSICS_HYSTERESIS more, and only once it is driving normally
# (TrafficCar.can_rail), so a car on the edge does not flip every tick and a
# crashed one stays crashed.

const LANE_W := RoadChunkBuilder.LANE_W
const Weather := preload("res://scripts/world/weather.gd")

var player: Node3D
var own_lanes := 4
var onc_lanes := 4
var car_count := 16
## Beyond this many metres from the player a car runs the frozen lane cruise.
var detail_distance := 300.0
## Within this many metres of the player (along the road) a car runs the full
## sim. NEON_TRAFFIC_PHYSICS_M overrides it (perf comparisons; a value at or
## past the draw distance is the old behaviour, every drawn car in the sim).
var physics_distance := PHYSICS_DISTANCE_DEFAULT
static var PHYSICS_DISTANCE_DEFAULT := float(OS.get_environment("NEON_TRAFFIC_PHYSICS_M")) if OS.get_environment("NEON_TRAFFIC_PHYSICS_M").is_valid_float() else 60.0
## A race rival runs the full sim out to this far (never less than the traffic
## band): further away it rides the rails like traffic, which is the same
## controller on the same lane path without the tyres. PerfLadder lowers it.
const PINNED_DISTANCE_DEFAULT := 150.0
var pinned_distance := PINNED_DISTANCE_DEFAULT
## A car leaves the sim only this much further out than it joined it.
const PHYSICS_HYSTERESIS := 10.0
## Cars are drawn out to at least this far whatever the slider says: the road
## chunks end here (Game.CHUNKS_AHEAD * CHUNK_LEN), so a car hidden any nearer
## would blink out in plain view. Spawns happen beyond it.
const REVEAL_MIN := 300.0
## A shown car is hidden again only this much further out (no flicker for a car
## pacing the player at the edge).
const HIDE_HYSTERESIS := 15.0
## A car found in sight is not looked at again for this many physics ticks.
const SEEN_RECHECK_TICKS := 6
## Show/hide, the physics band, recycling and the full occupancy index run
## this many times a second (see _physics_process).
const BOOKKEEP_HZ := 60.0
var _tick := 0
var _index_cars := -1
## Spawn band ahead of the player, metres along the road: never nearer than
## spawn_min and never inside the draw distance, so the band actually used is
## [max(spawn_min, detail + SPAWN_HIDE_MARGIN), max(spawn_max, that + SPAWN_BAND)].
var spawn_min := 60.0
var spawn_max := 240.0
const SPAWN_HIDE_MARGIN := 10.0
const SPAWN_BAND := 150.0
## Behind the player, own-direction lanes only, only for cars at least
## BEHIND_DV faster than the player, and only out of the camera's view.
var spawn_behind_min := 60.0
var spawn_behind_max := 90.0
const BEHIND_DV := 3.0
const BEHIND_SHARE := 0.5
## Recycled once this far behind; cars that are falling back (slower than the
## player, or oncoming) already at RECYCLE_RECEDING.
var recycle_behind := 100.0
const RECYCLE_RECEDING := 60.0
## Minimum bumper gap to anything in the lane at spawn time.
var lane_gap := 10.0
## Minimum time to contact at spawn, s: with other traffic (which brakes) and
## with the player (who may not).
const SPAWN_TTC := 5.0
const SPAWN_TTC_PLAYER := 10.0
## Random slot tries per placement before deferring; a deferred car waits
## DEFER_TICKS before it tries again (80 cars with the player's lane kept
## clear filled every slot, and retrying each tick cost 24 scans a car).
const SLOT_TRIES := 12
const DEFER_TICKS := 30
## Share of the cars on the road that drive the oncoming way (_find_slot
## spawns toward it).
var oncoming_share := 0.4
## Which way along the road the player is travelling, as a sign on road-space
## z: -1 = down the road (the +x lanes are the player's side), +1 = back up it
## (the map, 2026-10-10: the road is driven both ways, and then the -x lanes
## are the player's side). "Ahead", "behind", "oncoming" and the lane speeds
## all follow it. It flips only once the player is doing FLOW_FLIP m/s the
## other way, so backing up or a spin does not turn the traffic round.
var flow := -1.0
const FLOW_FLIP := 6.0
## Times the flow has turned round (tests).
var flow_flips := 0
## Own-direction / oncoming lanes traffic may use, for spawns and lane
## changes; empty = all. Tests keep the player's lane clear with this.
var own_lanes_used: Array[int] = []
var onc_lanes_used: Array[int] = []
## Cruise speed per lane, m/s, lane 0 (next to the centre line, the passing
## lane in right-hand traffic) first: 115/100/85/70 km/h with the flow,
## 95/85/75/65 km/h oncoming, plus or minus SPEED_JITTER per car. Milestone 4
## cars brake and pass, so the jitter is wide enough that they catch up with
## each other and do (milestone 3 kept it at 1 km/h because nothing braked).
var lane_speeds_own: Array[float] = [31.9, 27.8, 23.6, 19.4]
var lane_speeds_onc: Array[float] = [26.4, 23.6, 20.8, 18.0]
const SPEED_JITTER := 2.5
## Spawns, merges and moving over take the player into account as a car that
## may not brake. Tests turn it off to force rear-end crashes.
var react_to_player := true
## Spec every car is cloned from; empty = each car's own CarSpec.npc_spec().
var spec_template := {}
## One car for every slot (tests); empty = the traffic mix below.
var kind := ""
## Share of each traffic car in the pool (stage B step 5), NpcCarBuilder kinds.
const MIX := {"n1_commuter": 45, "n2_cityhatch": 35, "n3_pickup": 20}
var sim_only := false
## City lights (junction.gd): the signalised crossing whose red lights cars
## stop for. Null = none.
var junction: Junction

## Share of the cars that are on the road (living world step 2): the night
## clock's hour band sets it through game.gd (NightBands.traffic_share). Cars
## over the share are benched, parked hidden and frozen like a deferred spawn,
## and only when they recycle out of sight; when the share rises a benched car
## comes back through a normal spawn, one per tick. 1 = every car.
var active_share := 1.0
## Cars benched / brought back so far; tests watch them.
var bench_count := 0
var unbench_count := 0
## Cars benched while the player could see them (should stay 0).
var bench_seen := 0
## Share of spawns that are rule breakers (WorldMood sets it from tonight's
## events through game.gd), never above RULE_BREAKER_CAP; of those,
## weave_share drift weave_m metres around their lane (bar close).
var rule_breaker_share := 0.0
const RULE_BREAKER_CAP := 0.2
var weave_share := 0.0
var weave_m := 0.5
var rule_breaker_spawns := 0

var cars: Array[TrafficCar] = []
var spawn_count := 0
var recycle_count := 0
## Wrecked cars recycled out of view (also counted in recycle_count).
var wreck_recycle_count := 0
var lane_change_count := 0
## Spawns that found no free slot this tick and will retry; tests watch it.
var deferred_count := 0
## Every placement, for the tests: {z, lane_x, direction, player_z, dist,
## gap, ttc, behind, in_view, speed}. dist is metres ahead of the player
## (negative behind).
var spawn_log: Array[Dictionary] = []
var log_spawns := false
## Tests: called as (kind, car, world_pos) at the moment a car is "spawn"ed (just
## placed), "despawn"ed (about to be moved or freed while drawn), "show"n or
## "hide"n at the reveal distance. Null in the game.
var event_hook: Callable = Callable()
## Slider target; set_car_count() trims down to it as cars leave the cameras' view.
var target_count := 16

## Where a car with no free slot waits, frozen and hidden, behind the player.
const PARK_BEHIND := 10000.0

## Chassis origin height of a car settled on its springs on the flat road
## (origin is at y=0 with the springs fully extended, so it is negative).
## Measured by tests/traffic/traffic_spawn.gd, which prints the mean; cars are placed
## here so a spawn has no settling hop. This is the old box car's; the NPC cars
## carry their own (TrafficCar.rest_y, NpcCarBuilder.KINDS).
const REST_Y := -0.124

const PALETTE := [
	Color(0.62, 0.64, 0.67), Color(0.15, 0.16, 0.2), Color(0.55, 0.1, 0.1),
	Color(0.12, 0.2, 0.45), Color(0.8, 0.78, 0.7), Color(0.2, 0.35, 0.2),
	Color(0.45, 0.3, 0.15), Color(0.3, 0.3, 0.32),
]

## The player's footprint in the index (the P1 coupe and the #63 test car
## are both about 1.8 x 4.4 m).
const PLAYER_HALF_W := 1.0
const PLAYER_HALF_L := 2.2

# Occupancy index: entry 0 is the player, entry i + 1 is cars[i].
var _lo := PackedFloat32Array()
var _hi := PackedFloat32Array()
var _z := PackedFloat32Array()
var _vz := PackedFloat32Array()
var _hl := PackedFloat32Array()
var _slots: Array = []  # per lane slot (oncoming lanes, then own), an Array of entry ids
## Result of the last scan(): speed along the asker's direction, whether it
## was the player, and the entry id (-1 = nothing found).
var q_speed := 0.0
var q_player := false
var q_idx := -1

func _ready() -> void:
	target_count = car_count
	for i in car_count:
		_make_car()
	_build_index()
	for car in cars:
		_respawn(car)

func _make_car() -> TrafficCar:
	var car := TrafficCar.new()
	car.kind = kind if kind != "" else _pick_kind()
	car.sim_only = sim_only
	car.traffic = self
	if NpcCarBuilder.is_npc(car.kind):
		car.build = NpcCarBuilder.pick_build(car.kind)
		car.color = NpcCarBuilder.pick_paint(car.kind, car.build)
	else:
		car.color = PALETTE[randi() % PALETTE.size()]
	if not spec_template.is_empty():
		car.spec = CarSpec.clone_spec(spec_template)
	# Off the road and far behind until _respawn places it, so a car never
	# starts on the player.
	car.position = Vector3(0.0, REST_Y, 10000.0)
	car.set_shown(false)
	add_child(car)
	cars.append(car)
	return car

func _pick_kind() -> String:
	var total := 0
	for k in MIX:
		total += int(MIX[k])
	var r := randi() % total
	for k in MIX:
		r -= int(MIX[k])
		if r < 0:
			return k
	return MIX.keys()[0]

func _physics_process(_delta: float) -> void:
	# The bookkeeping below (who is drawn, who is in the sim, who is recycled)
	# and the full index rebuild run BOOKKEEP_HZ times a second (every other
	# tick at the game's 120 Hz); the ticks between only refresh the index
	# entries that matter tick to tick: the player and the cars in the sim
	# (80-car pass 2026-10-10: at 80 cars this function was 8 ms of a 60 fps
	# frame, most of it re-deriving things that had not moved a lane's width
	# since the tick before).
	TrafficCar.update_think_ticks()
	_tick += 1
	if _tick % maxi(1, roundi(Engine.physics_ticks_per_second / BOOKKEEP_HZ)) != 0 and _index_cars == cars.size():
		_refresh_index()
		return
	_build_index()
	var pz := _player_z()
	if _vz[0] * flow < -FLOW_FLIP:
		flow = -flow
		flow_flips += 1
	var pv := _player_speed()
	var band_hi := _spawn_band().y
	var frame := Engine.get_physics_frames()
	var target := active_target()
	var active := active_count()
	var brought_back := false
	var reveal := reveal_distance()
	# Physics band: a hidden car is never hit, so it ends at the draw distance too.
	var band := minf(physics_distance, detail_distance)
	var band_out := band + PHYSICS_HYSTERESIS
	for car in cars:
		# Road-space z straight from the index just built (no second lookup).
		var d := absf(_z[car._idx] - pz)
		var want := d <= reveal or (car.visible and d <= reveal + HIDE_HYSTERESIS)
		if want != car.visible and not car.sim_only:
			if event_hook.is_valid():
				event_hook.call("show" if want else "hide", car, car.global_position)
			car.set_shown(want)
		# Shown first (set_detailed reads it): a car leaving the sim in view eases onto its rails.
		# A race rival keeps the full sim further out (pinned_distance).
		var far := maxf(pinned_distance, band) - band if car.race_pinned else 0.0
		if d <= band + far:
			car.set_detailed(true)
		elif car.detailed and d > band_out + far and (not car.shown or car.can_rail()):
			car.set_detailed(false)
	var gone: Array[TrafficCar] = []
	for car in cars:
		if car.race_pinned:
			continue  # a live race rival is never recycled (race_controller.gd)
		if car.benched:
			if active < target and not brought_back:
				car.benched = false
				active += 1
				brought_back = true
				unbench_count += 1
				_respawn(car)
			continue
		var behind := (pz - _z[car._idx]) * flow
		if behind > PARK_BEHIND * 0.5 and frame < car.retry_frame:
			continue  # parked after a deferred spawn, waiting to retry
		var receding := car.direction != flow or car.lane_speed() < pv
		var due := behind > recycle_behind or (behind > RECYCLE_RECEDING and receding) or -behind > band_hi + RoadChunkBuilder.CHUNK_LEN
		# Due is not enough: the move waits until no camera can see the car.
		# It keeps driving meanwhile and leaves view (or the reveal distance) soon.
		var recycle := due and not _car_seen(car)
		var wreck := not recycle and car.wrecked and not _car_seen(car)
		if not (recycle or wreck):
			continue
		if car.race_released:
			gone.append(car)  # an ex-rival leaves for good instead of joining the pool
			continue
		recycle_count += 1
		if wreck:
			wreck_recycle_count += 1
		if active > target:
			_bench(car, pz)  # the band wants fewer cars: this one leaves out of sight
			active -= 1
		else:
			_respawn(car)
	for car in gone:
		cars.erase(car)
		car.queue_free()
	if not gone.is_empty():
		_build_index()
	if _pool_size() > target_count:
		_trim_cars()

## Races (RC1): one extra full-sim car, in the index like any other car so
## traffic sees it and it sees traffic. Pinned: never recycled, never frozen,
## until release_rival() hands it back.
func add_rival(kind_name: String, lane_x: float, z: float, speed: float, paint: Color) -> TrafficCar:
	var car := TrafficCar.new()
	car.kind = kind_name
	car.traffic = self
	car.race_pinned = true
	car.color = paint
	if NpcCarBuilder.is_npc(car.kind):
		car.build = NpcCarBuilder.pick_build(car.kind)
	car.position = Vector3(0.0, REST_Y, 10000.0)
	add_child(car)
	cars.append(car)
	_build_index()
	car.target_speed = speed
	car.place(lane_x, -1.0, z, car.rest_y, speed)
	_put(car)
	return car

## The race is over: the rival drives on as traffic and is removed once it is
## out of range, so it never vanishes in front of the player.
func release_rival(car: TrafficCar) -> void:
	if car != null and is_instance_valid(car):
		car.race_pinned = false
		car.race_released = true

## The same show/hide and physics band for a car that is not in the pool (the
## patrol car): d is its distance from the player along the road.
func tier(car: TrafficCar, d: float) -> void:
	var reveal := reveal_distance()
	var want := d <= reveal or (car.visible and d <= reveal + HIDE_HYSTERESIS)
	if want != car.shown:
		car.set_shown(want)
	var band := minf(physics_distance, detail_distance)
	if d <= band:
		car.set_detailed(true)
	elif car.detailed and d > band + PHYSICS_HYSTERESIS and (not car.shown or car.can_rail()):
		car.set_detailed(false)

## Metres from the player out to which cars are drawn.
func reveal_distance() -> float:
	return maxf(detail_distance, REVEAL_MIN)

## Whether a drawn car is in sight of any camera right now. A car that is not
## drawn cannot be seen.
func _car_seen(car: TrafficCar) -> bool:
	if not (car.visible or car.sim_only):
		return false
	var frame := Engine.get_physics_frames()
	if frame < car.seen_recheck_frame:
		return true  # looked a moment ago: still counts as seen
	var seen := in_view(car.global_position)
	# Only "seen" is cached; "unseen" is always judged fresh, at the moment of the move.
	car.seen_recheck_frame = frame + SEEN_RECHECK_TICKS if seen else 0
	return seen

## The player's road-space z (RoadFrame): metres along the road.
func _player_z() -> float:
	return RoadFrame.unroll(player.global_position).z

## The player's speed the way it is travelling (flow), m/s.
func _player_speed() -> float:
	if not player is RigidBody3D:
		return 0.0
	return flow * RoadFrame.dir_to_road(_player_z(), player.linear_velocity).z

## [nearest, furthest] metres ahead of the player a car may be placed.
func _spawn_band() -> Vector2:
	var lo := maxf(spawn_min, reveal_distance() + SPAWN_HIDE_MARGIN)
	return Vector2(lo, maxf(spawn_max, lo + SPAWN_BAND))

## Whether anyone can see a car standing at this world point: inside the reveal
## distance, and seen by a live camera (ViewGuard: current camera, mirrors,
## view_cameras group; sight lines blocked by hills, buildings and walls do not
## count as seen).
func in_view(pos: Vector3) -> bool:
	var u := RoadFrame.unroll(pos)
	if absf(u.z - _player_z()) > reveal_distance() + HIDE_HYSTERESIS:
		return false
	u.y = maxf(u.y, 0.0)
	return ViewGuard.car_seen(get_tree(), get_world_3d().direct_space_state, u)

## How many cars the hour band wants on the road (active_share of the pool).
func active_target() -> int:
	var pool := _pool_size()
	return clampi(roundi(float(pool) * clampf(active_share, 0.0, 1.0)), 0, pool)

## Traffic cars, not counting a race rival (live or released): the rival is
## an extra car on top of the traffic count (race_controller.gd).
func _pool_size() -> int:
	var n := 0
	for car in cars:
		if not (car.race_pinned or car.race_released):
			n += 1
	return n

## Cars not benched (on the road, or waiting for a free slot).
func active_count() -> int:
	var n := 0
	for car in cars:
		if not (car.benched or car.race_pinned or car.race_released):
			n += 1
	return n

## Rule breakers on the road now (benched cars do not count).
func rule_breakers_on_road() -> int:
	var n := 0
	for car in cars:
		if car.rule_breaker and not car.benched:
			n += 1
	return n

## A police crackdown: everyone on the road starts behaving at once, not only
## the cars that spawn from now on.
func reform_all() -> void:
	for car in cars:
		if car.rule_breaker:
			car.set_rule_breaker(false, 0.0)
			car.target_speed -= TrafficCar.RB_SPEED

## Takes a car off the road for now: parked hidden and frozen far behind,
## where a deferred spawn waits, until the share rises again.
func _bench(car: TrafficCar, pz: float) -> void:
	if in_view(car.global_position):
		bench_seen += 1
	car.benched = true
	bench_count += 1
	car.set_detailed(false)
	car.place(car.lane_x, car.direction, pz - flow * PARK_BEHIND, REST_Y, 0.0)
	_put(car)

## Puts a car in a free slot. If every slot is taken it parks the car far
## behind (hidden, frozen) and tries again next tick.
func _respawn(car: TrafficCar) -> void:
	var t0 := Time.get_ticks_usec()
	var pz := _player_z()
	if car.visible and event_hook.is_valid():
		event_hook.call("despawn", car, car.global_position)
	# Rule breakers (living world step 3): the event share, picked per spawn.
	# No random draw at a 0 share: the benchmark and the traffic tests keep the
	# exact random sequence they had before rule breakers existed.
	var breaker := rule_breaker_share > 0.0 and randf() < minf(rule_breaker_share, RULE_BREAKER_CAP)
	var slot := _find_slot(car, pz, TrafficCar.RB_SPEED if breaker else 0.0)
	if slot.is_empty():
		deferred_count += 1
		car.set_shown(false)
		car.set_detailed(false)
		car.set_shown(false)
		car.place(car.lane_x, car.direction, pz - flow * PARK_BEHIND, car.rest_y, 0.0)
		car.retry_frame = Engine.get_physics_frames() + DEFER_TICKS
		_put(car)
		SpikeLog.mark("traffic_defer", SpikeLog.since(t0))
		return
	spawn_count += 1
	car.target_speed = slot.speed
	car.set_rule_breaker(breaker, weave_m if breaker and weave_share > 0.0 and randf() < weave_share else 0.0)
	if breaker:
		rule_breaker_spawns += 1
	car.set_detailed(absf(slot.dist) <= minf(physics_distance, detail_distance))
	# In the wet a car arrives already at its wet speed, on wet tyres
	# (weather.gd, wet_grip.gd): spawning is not a change anyone feels.
	car.place(slot.lane_x, slot.direction, slot.z, car.rest_y, slot.speed * Weather.ai_speed_factor())
	car.wet.settle()
	car.set_shown(absf(slot.dist) <= reveal_distance())
	_put(car)
	if car.visible and event_hook.is_valid():
		event_hook.call("spawn", car, car.global_position)
	SpikeLog.mark("traffic_respawn", SpikeLog.since(t0))
	if log_spawns:
		slot["player_z"] = pz
		slot["player_speed"] = _player_speed()
		slot["breaker"] = breaker
		spawn_log.append(slot)

func _find_slot(car: TrafficCar, pz: float, extra_speed := 0.0) -> Dictionary:
	var pv := _player_speed()
	var band := _spawn_band()
	# oncoming_share is a share of the cars on the road, not of the spawns: an
	# oncoming car is past the player and recycled in a few seconds while one
	# going the player's way stays for a minute, so drawing each spawn at 40%
	# left the other carriageway nearly empty (1 car in 14 at 110 km/h). The
	# first half of the tries fill whichever side is short; the rest draw as
	# before, so a full side never blocks a spawn.
	var others := 0
	var others_onc := 0
	for c in cars:
		if c != car and not c.benched and not c.race_pinned:
			others += 1
			if c.direction != flow:
				others_onc += 1
	var short_onc := float(others_onc) < oncoming_share * float(others + 1)
	for attempt in SLOT_TRIES:
		# Oncoming for the player; `far_side` is the road's own -x carriageway.
		# (The draw is taken either way: the same number of draws per try as before.)
		var oncoming := randf() < oncoming_share
		if attempt * 2 < SLOT_TRIES:
			oncoming = short_onc
		var dir := -flow if oncoming else flow
		var far_side := dir > 0.0
		var lanes: Array[int] = onc_lanes_used if far_side else own_lanes_used
		var n_lanes := onc_lanes if far_side else own_lanes
		var lane_i: int = lanes[randi() % lanes.size()] if not lanes.is_empty() else randi() % n_lanes
		var lane_x := lane_centre(lane_i, far_side)
		var speed := lane_speed(lane_i, far_side) + randf_range(-SPEED_JITTER, SPEED_JITTER) + extra_speed
		var behind := not oncoming and speed > pv + BEHIND_DV and randf() < BEHIND_SHARE
		var z := pz - flow * randf_range(spawn_behind_min, spawn_behind_max) if behind else pz + flow * randf_range(band.x, band.y)
		var seen := in_view(RoadFrame.roll(Vector3(lane_x, car.rest_y, z)))
		if seen:
			continue
		var check := _slot_check(car, lane_x, z, dir, speed)
		if check.is_empty():
			continue
		return {"lane_x": lane_x, "direction": dir, "z": z, "dist": (z - pz) * flow, "gap": check.gap, "ttc": check.ttc,
			"behind": behind, "in_view": seen, "speed": speed}
	return {}

## Gap and time-to-contact check for a car placed at (lane_x, z) moving at
## `speed` along `dir`. Empty if unsafe, else {gap, ttc}.
func _slot_check(car: TrafficCar, lane_x: float, z: float, dir: float, speed: float) -> Dictionary:
	var lo := lane_x - car.half_w - TrafficCar.CORRIDOR_MARGIN
	var hi := lane_x + car.half_w + TrafficCar.CORRIDOR_MARGIN
	var skip_player := not react_to_player
	var ttc := INF
	var gap_a := scan(z, dir, lo, hi, true, car._idx, car.half_l, INF, skip_player)
	if gap_a < lane_gap:
		return {}
	if gap_a < INF and speed > q_speed:
		var t := gap_a / (speed - q_speed)
		if t < (SPAWN_TTC_PLAYER if q_player else SPAWN_TTC):
			return {}
		ttc = minf(ttc, t)
	if player_behind_blocks(z, dir, lo, hi, speed, car.half_l, SPAWN_TTC_PLAYER, lane_gap):
		return {}
	var gap_b := scan(z, dir, lo, hi, false, car._idx, car.half_l, INF, skip_player)
	if gap_b < lane_gap:
		return {}
	if gap_b < INF and q_speed > speed:
		var t := gap_b / (q_speed - speed)
		if t < (SPAWN_TTC_PLAYER if q_player else SPAWN_TTC):
			return {}
		ttc = minf(ttc, t)
	return {"gap": minf(gap_a, gap_b), "ttc": ttc}

## `oncoming` is the road's -x carriageway; the slower set goes to whichever
## side is oncoming for the player (flow).
func lane_speed(lane_i: int, oncoming: bool) -> float:
	var speeds := lane_speeds_onc if oncoming != (flow > 0.0) else lane_speeds_own
	return speeds[mini(lane_i, speeds.size() - 1)]

## Whether traffic on that side may drive in lane `lane_i` (spawns and lane
## changes). Never the other side of the centre line.
func lane_allowed(lane_i: int, oncoming: bool) -> bool:
	if lane_i < 0 or lane_i >= (onc_lanes if oncoming else own_lanes):
		return false
	var used := onc_lanes_used if oncoming else own_lanes_used
	return used.is_empty() or lane_i in used

static func lane_centre(lane_i: int, oncoming: bool) -> float:
	var x := RoadChunkBuilder.lane_offset(lane_i)
	return -x if oncoming else x

# ---------- occupancy index ----------

## Between full rebuilds: the player's entry and the sim cars' entries, in
## place. Lane slots keep what the last rebuild gave them (a car that crosses a
## lane line registers there one tick late; a lane change start already
## registers at once, see note_lane_change), and a rail car's entry is at most
## one tick old at 120 Hz (0.25 m at 110 km/h).
func _refresh_index() -> void:
	_write_player()
	for car in cars:
		if car.detailed and car._idx > 0:
			_write(car)

func _write_player() -> void:
	var p := RoadFrame.unroll(player.global_position)
	_lo[0] = p.x - PLAYER_HALF_W
	_hi[0] = p.x + PLAYER_HALF_W
	_z[0] = p.z
	_vz[0] = RoadFrame.dir_to_road(p.z, player.linear_velocity).z if player is RigidBody3D else 0.0
	_hl[0] = PLAYER_HALF_L

func _build_index() -> void:
	_index_cars = cars.size()
	var n := cars.size() + 1
	if _lo.size() != n:
		_lo.resize(n)
		_hi.resize(n)
		_z.resize(n)
		_vz.resize(n)
		_hl.resize(n)
	var n_slots := own_lanes + onc_lanes
	if _slots.size() != n_slots:
		_slots.clear()
		for i in n_slots:
			_slots.append([])
	for s in _slots:
		s.clear()
	_write_player()
	_register(0)
	for i in cars.size():
		cars[i]._idx = i + 1
		_put(cars[i])

## Writes a car's entry (footprint across the road, z, z-velocity, all in
## road space: RoadFrame) and adds
## it to the lane slots it touches. Called again after a respawn or a lane
## change starts; the stale slot it may still sit in is harmless, the range
## test uses the fresh entry.
func _put(car: TrafficCar) -> void:
	var k := car._idx
	if k < 0 or k >= _lo.size():
		return
	_write(car)
	_register(k)

## The entry alone, without the lane slots.
func _write(car: TrafficCar) -> void:
	var k := car._idx
	# A car on rails is driven in road space and knows where it is; only a sim
	# car has to be looked up from its world position.
	var o := RoadFrame.unroll(car.global_position) if car.detailed or is_nan(car._rail_z) else Vector3(car.path_x() + car._rail_dx, 0.0, car.rail_z_now())
	var ex := car.half_w
	var ez := car.half_l
	var vz := car.direction * car._cruise_speed
	if car.detailed:
		# Footprint of the turned body: a car spun across the road blocks more.
		# RoadFrame.dir_to_road twice, with the road basis built once.
		var to_road := RoadFrame.basis_at(o.z).transposed()
		var axis := to_road * car.global_transform.basis.z
		var fx := absf(axis.x)
		var fz := absf(axis.z)
		ex = car.half_w * fz + car.half_l * fx
		ez = car.half_l * fz + car.half_w * fx
		vz = (to_road * car.linear_velocity).z
	var lo := o.x - ex
	var hi := o.x + ex
	if car.changing:
		lo = minf(lo, car.lane_x - car.half_w)
		hi = maxf(hi, car.lane_x + car.half_w)
	_lo[k] = lo
	_hi[k] = hi
	_z[k] = o.z
	_vz[k] = vz
	_hl[k] = ez

func _register(k: int) -> void:
	for s in range(_slot_of(_lo[k]), _slot_of(_hi[k]) + 1):
		_slots[s].append(k)

func _slot_of(x: float) -> int:
	# Own lanes are slots onc_lanes.., oncoming ones count down from onc_lanes - 1;
	# the median gap belongs to the nearest lane on its side.
	var i := RoadChunkBuilder.lane_at(absf(x))
	return clampi(onc_lanes + i if x >= 0.0 else onc_lanes - 1 - i, 0, own_lanes + onc_lanes - 1)

## A lane change has started: the car now also occupies its new lane.
func note_lane_change(car: TrafficCar) -> void:
	lane_change_count += 1
	_put(car)

## Whether the player, if it is BEHIND the point z (looking along dir) in the
## corridor [lo, hi], is too close or closing too fast for something moving
## at `speed` to be put or moved there: under min_gap, or under ttc_min
## seconds from contact. The nearest-follower scan alone is not enough: a car
## in between (or one straddling the lane line) hides the player behind it.
## Always false with react_to_player off.
func player_behind_blocks(z: float, dir: float, lo: float, hi: float, speed: float, self_hl: float, ttc_min: float, min_gap: float) -> bool:
	if not react_to_player or _hi[0] <= lo or _lo[0] >= hi:
		return false
	var d: float = (_z[0] - z) * dir
	if d >= 0.0:
		return false
	var gap: float = -d - self_hl - _hl[0]
	var closing: float = _vz[0] * dir - speed
	return gap < min_gap or (closing > 0.0 and gap / closing < ttc_min)

## Bumper gap from a point at z (half length self_hl) to entry k, looking
## along dir; INF once k is behind. For a car refreshing the car it follows.
func entry_gap(k: int, z: float, dir: float, self_hl: float) -> float:
	if k >= _z.size():
		return INF
	var d: float = (_z[k] - z) * dir
	return INF if d < 0.0 else d - self_hl - _hl[k]

func entry_speed(k: int, dir: float) -> float:
	return _vz[k] * dir if k < _vz.size() else 0.0

## Nearest entry ahead of (or behind) the point z, looking along `dir`, whose
## footprint overlaps the corridor [lo, hi] across the road, within `reach`
## metres centre to centre. Returns the bumper gap (self_hl + the other's half
## length taken off; negative = touching) or INF, and leaves the other's speed
## along `dir`, whether it is the player, and its id in q_speed / q_player /
## q_idx. `skip` is the asker's own id.
func scan(z: float, dir: float, lo: float, hi: float, ahead: bool, skip: int, self_hl: float, reach: float, skip_player: bool) -> float:
	var best := INF
	var best_d := INF
	q_idx = -1
	for s in range(_slot_of(lo), _slot_of(hi) + 1):
		for k in _slots[s]:
			if k == skip or (k == 0 and skip_player):
				continue
			if _hi[k] <= lo or _lo[k] >= hi:
				continue
			var d: float = (_z[k] - z) * dir
			if (d < 0.0) == ahead:
				continue
			d = absf(d)
			if d < best_d and d <= reach:
				best_d = d
				best = d - self_hl - _hl[k]
				q_idx = k
	if q_idx >= 0:
		q_speed = _vz[q_idx] * dir
		q_player = q_idx == 0
	else:
		q_speed = 0.0
		q_player = false
	return best

## Whether a car is in the player's high beam's way (auto-dip, HeadlightBeams):
## one coming at you inside `oncoming` m, or one you are following inside
## `ahead` m. Reads the position list built this tick; no rays, no nodes.
func beam_blocked(oncoming := 150.0, ahead := 80.0) -> bool:
	if _z.size() < 2:
		return false
	var fwd := 1.0
	if player != null:
		fwd = signf(RoadFrame.dir_to_road(_z[0], -player.global_transform.basis.z).z)
		if fwd == 0.0:
			fwd = 1.0
	for k in range(1, _z.size()):
		var d: float = (_z[k] - _z[0]) * fwd
		if d <= 0.0 or d > oncoming:
			continue
		if _vz[k] * fwd < 0.0 or d <= ahead:
			return true
	return false

## Floating origin (game.gd): move every car with the world.
func shift_world(offset: Vector3) -> void:
	for car in cars:
		car.shift_world(offset)

## A graphics tier was picked (GraphicsSettings.apply): its car count and
## sim/draw distance, live. Only the game's own manager is in the group.
func apply_graphics() -> void:
	if cars.size() != TrafficSettings.car_count:
		set_car_count(TrafficSettings.car_count)
	detail_distance = TrafficSettings.detail_distance

## Live count change from the Settings sliders. Removes the cars furthest from
## the player first, but only ones no camera can see; the rest go as they leave
## view (_trim_cars, every tick). New cars spawn like any recycled one.
func set_car_count(n: int) -> void:
	n = maxi(n, 0)
	target_count = n
	_trim_cars()
	while _pool_size() < n:
		_make_car()
	_build_index()
	for car in cars:
		if not car.benched and absf(RoadFrame.unroll(car.global_position).z - _player_z()) > PARK_BEHIND * 0.5:
			_respawn(car)
	car_count = n

## Frees surplus cars (furthest first) that are out of every camera's sight.
func _trim_cars() -> void:
	var pz := _player_z()
	while _pool_size() > target_count:
		var far: TrafficCar = null
		var far_d := -1.0
		for car in cars:
			if car.race_pinned or car.race_released:
				continue  # the race rival is not part of the pool
			var d := absf(RoadFrame.unroll(car.global_position).z - pz)
			if d > far_d and not _car_seen(car):
				far = car
				far_d = d
		if far == null:
			return  # every surplus candidate is in view; try again next tick
		if far.visible and event_hook.is_valid():
			event_hook.call("despawn", far, far.global_position)
		cars.erase(far)
		# queue_free() runs at the end of the frame, and a car added meanwhile
		# could be placed on top of this one: park it out of the way first
		# (frozen, 50 km behind), out of the draft lookup too.
		far.set_detailed(false)
		far.set_shown(false)
		far.remove_from_group("aero_vehicles")
		far.global_position.z += 50000.0
		far.queue_free()

func detailed_count() -> int:
	var n := 0
	for car in cars:
		if car.detailed:
			n += 1
	return n
