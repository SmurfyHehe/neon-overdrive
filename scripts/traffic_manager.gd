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
# Draw distance: cars further than `detail_distance` from the player run the
# frozen lane cruise (TrafficCar.set_detailed(false)) and are hidden; the pause
# menu's Traffic sliders set this and the car count live (TrafficSettings).

const LANE_W := RoadChunkBuilder.LANE_W

var player: Node3D
var own_lanes := 4
var onc_lanes := 4
var car_count := 16
## Beyond this many metres from the player a car is hidden and frozen.
var detail_distance := 300.0
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
## Share of cars that drive the oncoming way.
var oncoming_share := 0.4
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

## Where a car with no free slot waits, frozen and hidden, behind the player.
const PARK_BEHIND := 10000.0

## Chassis origin height of a car settled on its springs on the flat road
## (origin is at y=0 with the springs fully extended, so it is negative).
## Measured by tests/traffic_spawn.gd, which prints the mean; cars are placed
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
	_build_index()
	var pz := _player_z()
	var pv := _player_speed()
	var band_hi := _spawn_band().y
	var frame := Engine.get_physics_frames()
	var target := active_target()
	var active := active_count()
	var brought_back := false
	for car in cars:
		if car.benched:
			if active < target and not brought_back:
				car.benched = false
				active += 1
				brought_back = true
				unbench_count += 1
				_respawn(car)
			continue
		var z := RoadFrame.unroll(car.global_position).z
		var behind := z - pz
		if behind > PARK_BEHIND * 0.5 and frame < car.retry_frame:
			continue  # parked after a deferred spawn, waiting to retry
		var receding := car.direction > 0.0 or car.lane_speed() < pv
		var recycle := behind > recycle_behind or (behind > RECYCLE_RECEDING and receding) or -behind > band_hi + RoadChunkBuilder.CHUNK_LEN
		var wreck := not recycle and car.wrecked and not in_view(car.global_position)
		if not (recycle or wreck):
			continue
		recycle_count += 1
		if wreck:
			wreck_recycle_count += 1
		if active > target:
			_bench(car, pz)  # the band wants fewer cars: this one leaves out of sight
			active -= 1
		else:
			_respawn(car)
	for car in cars:
		car.set_detailed(absf(RoadFrame.unroll(car.global_position).z - pz) <= detail_distance)

## The player's road-space z (RoadFrame): metres along the road.
func _player_z() -> float:
	return RoadFrame.unroll(player.global_position).z

func _player_speed() -> float:
	if not player is RigidBody3D:
		return 0.0
	return -RoadFrame.dir_to_road(_player_z(), player.linear_velocity).z

## [nearest, furthest] metres ahead of the player a car may be placed.
func _spawn_band() -> Vector2:
	var lo := maxf(spawn_min, detail_distance + SPAWN_HIDE_MARGIN)
	return Vector2(lo, maxf(spawn_max, lo + SPAWN_BAND))

## Whether the player can see this world point: inside the draw distance and
## inside the active camera's view (a few points along the car, so a car
## straddling the frustum edge counts as seen). Occlusion is not considered.
func in_view(pos: Vector3) -> bool:
	var u := RoadFrame.unroll(pos)
	if absf(u.z - _player_z()) > detail_distance:
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	for dz in [-2.0, 0.0, 2.0]:
		if cam.is_position_in_frustum(RoadFrame.roll(u + Vector3(0.0, 0.6, dz))):
			return true
	return false

## How many cars the hour band wants on the road (active_share of the pool).
func active_target() -> int:
	return clampi(roundi(float(cars.size()) * clampf(active_share, 0.0, 1.0)), 0, cars.size())

## Cars not benched (on the road, or waiting for a free slot).
func active_count() -> int:
	var n := 0
	for car in cars:
		if not car.benched:
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
	car.place(car.lane_x, car.direction, pz + PARK_BEHIND, REST_Y, 0.0)
	_put(car)

## Puts a car in a free slot. If every slot is taken it parks the car far
## behind (hidden, frozen) and tries again next tick.
func _respawn(car: TrafficCar) -> void:
	var pz := _player_z()
	# Rule breakers (living world step 3): the event share, picked per spawn.
	# No random draw at a 0 share: the benchmark and the traffic tests keep the
	# exact random sequence they had before rule breakers existed.
	var breaker := rule_breaker_share > 0.0 and randf() < minf(rule_breaker_share, RULE_BREAKER_CAP)
	var slot := _find_slot(car, pz, TrafficCar.RB_SPEED if breaker else 0.0)
	if slot.is_empty():
		deferred_count += 1
		car.set_detailed(false)
		car.place(car.lane_x, car.direction, pz + PARK_BEHIND, car.rest_y, 0.0)
		car.retry_frame = Engine.get_physics_frames() + DEFER_TICKS
		_put(car)
		return
	spawn_count += 1
	car.target_speed = slot.speed
	car.set_rule_breaker(breaker, weave_m if breaker and weave_share > 0.0 and randf() < weave_share else 0.0)
	if breaker:
		rule_breaker_spawns += 1
	car.set_detailed(absf(slot.dist) <= detail_distance)
	car.place(slot.lane_x, slot.direction, slot.z, car.rest_y, slot.speed)
	_put(car)
	if log_spawns:
		slot["player_z"] = pz
		slot["player_speed"] = _player_speed()
		slot["breaker"] = breaker
		spawn_log.append(slot)

func _find_slot(car: TrafficCar, pz: float, extra_speed := 0.0) -> Dictionary:
	var pv := _player_speed()
	var band := _spawn_band()
	for attempt in SLOT_TRIES:
		var oncoming := randf() < oncoming_share
		var lanes: Array[int] = onc_lanes_used if oncoming else own_lanes_used
		var n_lanes := onc_lanes if oncoming else own_lanes
		var lane_i: int = lanes[randi() % lanes.size()] if not lanes.is_empty() else randi() % n_lanes
		var lane_x := lane_centre(lane_i, oncoming)
		var dir := 1.0 if oncoming else -1.0
		var speed := lane_speed(lane_i, oncoming) + randf_range(-SPEED_JITTER, SPEED_JITTER) + extra_speed
		var behind := not oncoming and speed > pv + BEHIND_DV and randf() < BEHIND_SHARE
		var z := pz + randf_range(spawn_behind_min, spawn_behind_max) if behind else pz - randf_range(band.x, band.y)
		var seen := in_view(RoadFrame.roll(Vector3(lane_x, 0.0, z)))
		if seen:
			continue
		var check := _slot_check(car, lane_x, z, dir, speed)
		if check.is_empty():
			continue
		return {"lane_x": lane_x, "direction": dir, "z": z, "dist": pz - z, "gap": check.gap, "ttc": check.ttc,
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

func lane_speed(lane_i: int, oncoming: bool) -> float:
	var speeds := lane_speeds_onc if oncoming else lane_speeds_own
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

func _build_index() -> void:
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
	var p := RoadFrame.unroll(player.global_position)
	_lo[0] = p.x - PLAYER_HALF_W
	_hi[0] = p.x + PLAYER_HALF_W
	_z[0] = p.z
	_vz[0] = RoadFrame.dir_to_road(p.z, player.linear_velocity).z if player is RigidBody3D else 0.0
	_hl[0] = PLAYER_HALF_L
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
	var o := RoadFrame.unroll(car.global_position)
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
	_register(k)

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

## Floating origin (game.gd): move every car with the world.
func shift_world(offset: Vector3) -> void:
	for car in cars:
		car.shift_world(offset)

## Live count change from the Settings sliders. Removes the cars furthest from
## the player first; new cars spawn like any recycled one.
func set_car_count(n: int) -> void:
	n = maxi(n, 0)
	while cars.size() > n:
		var far: TrafficCar = cars[0]
		var pz := _player_z()
		for car in cars:
			if absf(RoadFrame.unroll(car.global_position).z - pz) > absf(RoadFrame.unroll(far.global_position).z - pz):
				far = car
		cars.erase(far)
		# queue_free() runs at the end of the frame, and a car added below could
		# be placed on top of this one in the meantime: park it out of the way
		# first (frozen, 50 km behind), out of the draft lookup too.
		far.set_detailed(false)
		far.remove_from_group("aero_vehicles")
		far.global_position.z += 50000.0
		far.queue_free()
	while cars.size() < n:
		_make_car()
	_build_index()
	for car in cars:
		if not car.benched and RoadFrame.unroll(car.global_position).z > _player_z() + PARK_BEHIND * 0.5:
			_respawn(car)
	car_count = n

func detailed_count() -> int:
	var n := 0
	for car in cars:
		if car.detailed:
			n += 1
	return n
