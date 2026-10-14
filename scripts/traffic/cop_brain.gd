class_name CopBrain
extends RefCounted

# The cop brain (police step P5, spec section 2): one per driving cop, run
# PoliceRules.BRAIN_HZ times a second by its owner (police_patrol.gd).
#
#   Patrol      drives the traffic lanes like traffic, lights off.
#   Checking    a soft offence at heat 0 (the P2 warning): it follows 30-50 m
#               back with its lights off for the 5 s window, if it is close
#               behind and going your way; else it just drives on.
#   Pursuit     heat 1 or more: lights on, the free driver (P4) tails you.
#   Lost        unseen for 2 s: it drives to the last place it saw you.
#   Search      it got there: it sweeps on down the road at the search speed;
#               the stretch it searches grows 50 m a second.
#   Called off  honest cops only: the danger number over the line for 3 s.
#               Lights off, back to Patrol at once, and it stays out of this
#               chase until the heat is gone: it does not watch you for the
#               heat either (PoliceHeat.stood_down), so the heat can cool.
#
# Heat is PoliceHeat's (events, and cooling while nobody sees you); the brain
# only reads it. Sight is PoliceHeat.cop_can_see_player, the one hook.
#
# Turning round: a cop cannot U-turn on the road yet. One that has to (you
# went past it the other way, or it is on the other carriageway) switches its
# lights on, slows, and once no camera sees it comes back from behind, out of
# view, PoliceRules.TURN_SECS later. Nothing is teleported in view, and it
# never drives faster than its car can.
#
# Cost: one sight test (heat's own budget), a few compares and at most one
# index walk (the danger number) per step.

enum State { PATROL, CHECKING, PURSUIT, LOST, SEARCH, CALLED_OFF }
## What it does in Pursuit (P6, spec section 3.1; the dispatcher deals them):
##   chaser   tails 12 m behind, pulls right up when you are slow, and nudges
##            your tail if you are slower than it inside 3 m.
##   blocker  gets in front of you in your lane (it passes in a free lane, or
##            it was put on the road ahead of you), a second of your speed
##            ahead at least, and then drives slower, slowing gently.
##   flanker  holds its nose by your rear wheel, one side or the other.
##   heavy    heat 4: the patrol SUV with a push bar. Sits close behind and
##            rams a rear corner when you are slower than it.
## None of them crosses in front of you closer than you could stop, or brakes
## hard in front of you (FreeDriver, issue #625).
enum Role { CHASER, BLOCKER, FLANKER, HEAVY }
const ROLE_NAMES := ["chaser", "blocker", "flanker", "heavy"]
const NAMES := ["patrol", "checking", "pursuit", "lost", "search", "called off"]
const WAIT_MARGIN := 40.0       # m past where a blocker is sent ahead that it still counts as waiting for you

signal state_changed(from: int, to: int)
## A line for the police radio (heard only with a scanner fitted: P10).
signal radio(text: String)

var car: PatrolCar
var heat: PoliceHeat
var traffic: TrafficManager
var player: Node3D
## A marker the free driver chases in Lost and Search (the owner's child).
var ghost: Node3D
## Bad cops skip the danger number and never call off (P14 sets this).
var honest := true
var role := Role.CHASER
## The fastest this cop's car is driven, m/s (the dispatcher sets it by car).
var v_cap := INF
var flank_side := 0.0         # +1 / -1 once the flanker has picked a side
## Whether the road has no barrier between the carriageways at road z (wired
## by the game; unknown = divided).
var undivided_at := Callable()

var state := State.PATROL
var driver: FreeDriver
var danger := 0.0
var sees := false
var unseen_t := 0.0
var search_t := 0.0
var turning := false          # waiting to come back from behind, unseen
var stood_down_at := -1       # heat level it called the chase off at (-1 = not stood down)
var called_off := 0
var turns := 0
## Where it last saw the player, in road terms (the world origin moves).
var last_s := 0.0
var last_x := 0.0
var last_dir := -1.0

var _danger_t := 0.0
var _turn_t := 0.0

func _init(patrol_car: PatrolCar, police_heat: PoliceHeat, manager: TrafficManager, target: Node3D, marker: Node3D) -> void:
	car = patrol_car
	heat = police_heat
	traffic = manager
	player = target
	ghost = marker

func state_name() -> String:
	return NAMES[state]

func in_chase() -> bool:
	return state == State.PURSUIT or state == State.LOST or state == State.SEARCH

## One brain step.
func step(dt: float) -> void:
	if car == null or not is_instance_valid(car) or heat == null or player == null:
		return
	# The cops in a chase talk: what one sees they all know (PoliceHeat.seen is
	# any cop that has not stood down). A blocker in front of you rarely sees
	# you itself; it must not go looking for you while the chaser is on your tail.
	# The helicopter (heat 5) calls you in wherever it can see you. A blocker
	# sent out in front of you is told where you are while it waits for you to
	# come up (it faces away from you): without that it went Lost and swept
	# the road at the search speed right in front of you (issue #625).
	sees = heat.seen or heat.helicopter_sees or _waiting_ahead() or heat.cop_can_see_player(car)
	if sees:
		_note_seen()
	if stood_down_at >= 0 and heat.level == PoliceHeat.NONE:
		stood_down_at = -1   # that chase is over: it is free for the next one
		heat.stood_down.erase(car)
	match state:
		State.PATROL:
			if heat.level >= PoliceHeat.ONE_CAR and stood_down_at < 0:
				_enter(State.PURSUIT)
			elif heat.warning_active and heat.warning_cop == car:
				_enter(State.CHECKING)
		State.CHECKING:
			if heat.level >= PoliceHeat.ONE_CAR:
				_enter(State.PURSUIT)
			elif not heat.warning_active:
				_enter(State.PATROL)
		State.PURSUIT:
			if heat.level == PoliceHeat.NONE:
				_enter(State.PATROL)
			elif sees:
				unseen_t = 0.0
				_role_step()
				_danger_step(dt)
			else:
				_danger_t = 0.0
				unseen_t += dt
				if unseen_t >= PoliceRules.LOST_SECS and not turning:
					_enter(State.LOST)
		State.LOST:
			if heat.level == PoliceHeat.NONE:
				_enter(State.PATROL)
			elif sees:
				_enter(State.PURSUIT)
			elif _to_last_seen() < PoliceRules.ARRIVE_M:
				_enter(State.SEARCH)   # there, or already past it
		State.SEARCH:
			if heat.level == PoliceHeat.NONE:
				_enter(State.PATROL)
			elif sees:
				_enter(State.PURSUIT)
			else:
				search_t += dt
		State.CALLED_OFF:
			_enter(State.PATROL)
	_turn_step(dt)
	_place_ghost()
	# On the rails (far off, out of the sim) the free driver is not run and the
	# car is traffic at its cruise speed: keep that at what the state wants.
	# In front of its spot (a blocker put on the road ahead) it dawdles so the
	# player catches it up; behind it, it comes on as fast as its car goes.
	if driver != null and not car.detailed:
		var fast := minf(driver.v_top, driver.v_max)
		if state == State.PURSUIT and driver.target == player:
			var pu := RoadFrame.unroll(player.global_position)
			var to_spot := (pu.z - last_dir * driver.offset_back - car.road_z()) * car.direction
			if to_spot < 0.0:
				fast = minf(fast, maxf(absf(heat._kmh_of(player)) / 3.6 * 0.6, 12.0))
		car.target_speed = fast

## A blocker in Pursuit on your road, going your way, out in front of you no
## farther than it is sent (the reveal distance and a margin).
func _waiting_ahead() -> bool:
	if role != Role.BLOCKER or state != State.PURSUIT or traffic == null:
		return false
	var u := RoadFrame.unroll(car.global_position)
	var pu := RoadFrame.unroll(player.global_position)
	if (u.x < 0.0) != (pu.x < 0.0):
		return false
	var ahead := (u.z - pu.z) * car.direction
	return ahead > 0.0 and ahead < traffic.reveal_distance() + PolicePatrol.SPAWN_PAST_REVEAL + WAIT_MARGIN

## Metres from the cop to the last place it saw the player, along its own
## direction (negative = it has driven past).
func _to_last_seen() -> float:
	var cs := RoadFrame.s_at(car.road_z())
	return (last_s - cs) * -car.direction

func _note_seen() -> void:
	var u := RoadFrame.unroll(player.global_position)
	last_s = RoadFrame.s_at(u.z)
	last_x = u.x
	var vel: Vector3 = player.get("linear_velocity") if player.get("linear_velocity") is Vector3 else Vector3.ZERO
	var vz := RoadFrame.dir_to_road(u.z, vel).z
	if absf(vz) > 2.0:
		last_dir = signf(vz)

## Where this cop's role wants it, from how fast the player is going.
func _role_step() -> void:
	if driver == null or driver.target != player:
		return
	var kmh := absf(heat._kmh_of(player))
	driver.ram = false
	driver.offset_x = 0.0
	driver.v_max = v_cap
	match role:
		Role.CHASER:
			# a target that has all but stopped is pulled right up to (the bust ring)
			driver.offset_back = PoliceRules.CLOSE_BACK if kmh < PoliceRules.CLOSE_KMH else PoliceRules.CHASE_BACK
			driver.ram = true
			driver.ram_gap = PoliceRules.RAM_GAP
			driver.ram_dv = PoliceRules.RAM_DV
		Role.BLOCKER:
			var boxing := kmh < PoliceRules.BOX_KMH
			var ahead := maxf(PoliceRules.BLOCK_AHEAD, PoliceRules.BLOCK_HEADWAY * kmh / 3.6 + FreeDriver.TARGET_HALF_L + car.half_l)
			driver.offset_back = -(PoliceRules.BOX_AHEAD if boxing else ahead)
			# in front of you and in your lane: now it slows, and you have to go round
			var u := RoadFrame.unroll(car.global_position)
			var pu := RoadFrame.unroll(player.global_position)
			if car.detailed and absf(driver.gap_along) < PoliceRules.BLOCK_IN_PLACE and absf(u.x - pu.x) < 1.2:
				var slow := maxf(kmh - PoliceRules.BLOCK_SLOW_KMH, PoliceRules.BLOCK_MIN_KMH)
				driver.v_max = minf(v_cap, (kmh if boxing else slow) / 3.6)
		Role.FLANKER:
			var fu := RoadFrame.unroll(car.global_position)
			var fp := RoadFrame.unroll(player.global_position)
			if flank_side == 0.0 or absf(fu.x - fp.x) > 1.0:
				var side := signf(fu.x - fp.x) if absf(fu.x - fp.x) > 1.0 else 1.0
				# the side it is on, unless there is no road there
				var lanes := traffic.onc_lanes if fp.x < 0.0 else traffic.own_lanes
				var span := FreeDriver.side_span(lanes, fp.x < 0.0)
				var x := fp.x + side * PoliceRules.FLANK_SIDE
				if x < span.x or x > span.y:
					side = -side
				flank_side = side
			driver.offset_back = PoliceRules.FLANK_BACK
			driver.offset_x = flank_side * PoliceRules.FLANK_SIDE
		Role.HEAVY:
			if flank_side == 0.0:
				flank_side = 1.0 if car.get_instance_id() % 2 == 0 else -1.0
			driver.offset_back = PoliceRules.CLOSE_BACK if kmh < PoliceRules.CLOSE_KMH else PoliceRules.HEAVY_BACK
			driver.offset_x = flank_side * PoliceRules.HEAVY_CORNER
			driver.ram = true
			driver.ram_gap = PoliceRules.HEAVY_RAM_GAP
			driver.ram_dv = PoliceRules.HEAVY_RAM_KMH / 3.6

## The dispatcher's word that the chase is terminated (another cop called it).
func call_off() -> void:
	if honest and in_chase():
		_enter(State.CALLED_OFF)

## Honest cops give up a chase that has become too dangerous.
func _danger_step(dt: float) -> void:
	if not honest:
		return
	var u := RoadFrame.unroll(player.global_position)
	var kmh := heat._kmh_of(player)
	var cars_near := traffic.count_ahead(u.z, last_dir, PoliceRules.DANGER_CARS_M, u.x < 0.0, car) if traffic != null else 0
	var undivided: bool = undivided_at.is_valid() and bool(undivided_at.call(u.z))
	var junction := Junction.enabled and absf(Junction.centre_z_near(u.z) - u.z) < PoliceRules.DANGER_JUNCTION_M
	danger = PoliceRules.danger(kmh, cars_near, undivided, junction)
	if danger > PoliceRules.DANGER_LINE:
		_danger_t += dt
		if _danger_t >= PoliceRules.CALL_OFF_SECS:
			_enter(State.CALLED_OFF)
	else:
		_danger_t = 0.0

func _enter(to: int) -> void:
	var from := state
	if from == to:
		return
	state = to
	unseen_t = 0.0
	_danger_t = 0.0
	match to:
		State.PATROL:
			_release()
			car.lights_on = false
			turning = false
		State.CHECKING:
			car.lights_on = false
			var u := RoadFrame.unroll(car.global_position)
			var pu := RoadFrame.unroll(player.global_position)
			var behind := (pu.z - u.z) * car.direction
			# only a cop close behind and on your side can follow; an oncoming one drives on
			if behind > 0.0 and behind < PoliceRules.CHECK_RANGE and (u.x < 0.0) == (pu.x < 0.0):
				_drive(player, PoliceRules.CHECK_BACK)
		State.PURSUIT:
			car.lights_on = true
			_drive(player, PoliceRules.CHASE_BACK)
			_role_step()
		State.LOST:
			car.lights_on = true
			_drive(ghost, 0.0)
		State.SEARCH:
			car.lights_on = true
			search_t = 0.0
			_drive(ghost, 0.0)
			driver.v_max = minf(v_cap, float(PoliceRules.SEARCH_KMH[PoliceRules.area_at(last_s)]) / 3.6)
		State.CALLED_OFF:
			called_off += 1
			stood_down_at = heat.level
			if not heat.stood_down.has(car):
				heat.stood_down.append(car)
			car.lights_on = false
			radio.emit("Pursuit terminated. Copy.")
	state_changed.emit(from, to)

func _drive(target: Node3D, back: float) -> void:
	if driver == null:
		driver = FreeDriver.new()
		driver.setup(car)
		car.free_driver = driver
	driver.target = target
	driver.offset_back = back
	driver.offset_x = 0.0
	driver.ram = false
	driver.v_max = v_cap

func _release() -> void:
	if driver == null:
		return
	var u := RoadFrame.unroll(car.global_position)
	var far := u.x < 0.0
	var city := traffic.city_at(u.z, car.direction) if traffic != null else false
	var lanes := 1
	if traffic != null:
		lanes = traffic.onc_lanes if far else traffic.own_lanes
	var lane := clampi(RoadChunkBuilder.lane_at(absf(u.x)), 0, maxi(lanes, 1) - 1)
	FreeDriver.release(car, traffic.lane_speed(lane, far, city) if traffic != null else 25.0)
	car.pace_lane = lane
	car.pace_far = far
	car.pace_city = city
	driver = null

## A cop that has to turn round (the chase runs the other way, or the target
## is on the other carriageway) does it out of sight: see the header.
func _turn_step(dt: float) -> void:
	if driver == null or not (state == State.PURSUIT or state == State.LOST):
		turning = false
		return
	var u := RoadFrame.unroll(car.global_position)
	var tu := RoadFrame.unroll(driver.target.global_position)
	var other_side := (u.x < 0.0) != (tu.x < 0.0)
	# A blocker is meant to be in front of you (it was put on the road ahead and
	# dawdles until you catch it up): you being behind it is not a pass.
	var passed := (tu.z - u.z) * car.direction < -30.0 and state == State.PURSUIT and role != Role.BLOCKER
	if not (driver.wrong_way or other_side or passed):
		turning = false
		_turn_t = 0.0
		return
	if not turning:
		turning = true
		_turn_t = 0.0
	if traffic == null or traffic.in_view(car.global_position):
		_turn_t = 0.0
		return
	_turn_t += dt
	if _turn_t >= PoliceRules.TURN_SECS and state == State.PURSUIT:
		# back onto the target's side, behind it, out of view
		driver.recycle_due = true
		if driver.recycle(car):
			turns += 1
			turning = false
			_turn_t = 0.0

## The marker for Lost (the last place seen) and Search (a point that runs on
## down the road ahead of the cop inside the growing stretch).
func _place_ghost() -> void:
	if ghost == null or not (state == State.LOST or state == State.SEARCH):
		return
	var s := last_s
	if state == State.SEARCH:
		var cs := RoadFrame.s_at(RoadFrame.unroll(car.global_position).z)
		# s grows against z: a car with direction -1 drives toward larger s
		var reach := PoliceRules.SEARCH_GROW * search_t
		var ahead := (cs - last_s) * -car.direction
		s = last_s - car.direction * minf(reach, maxf(ahead, 0.0) + 80.0)
	var z := float(RoadFrame.origin_index) * RoadChunkBuilder.CHUNK_LEN - s
	var side := RoadFrame.unroll(car.global_position).x < 0.0
	var x := last_x if (last_x < 0.0) == side else TrafficManager.lane_centre(0, side)
	ghost.global_position = RoadFrame.roll(Vector3(x, car.rest_y, z))
