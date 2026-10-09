class_name PoliceHeat
extends Node

# Police heat, F0 + F1 (police build plan 2026-10-09). Heat is one number,
# 0..5, that rises while a cop can see the player doing more than the limit
# and cools once nobody has seen them for a while. Its whole part is the
# level, and every level has its own icon on the HUD (scripts/ui/heat_icons.gd),
# not a row of stars:
#
#   1 one patrol car   2 two cars   3 sawhorse (roadblock)   4 spike strip
#   5 helicopter
#
# Bad cops (the ones who take tonight's cash, scripts/core/wallet.gd) get no
# icon on purpose: a cop registered as bad never raises heat. What they do is
# a later stage; they are only told apart here.
#
# The hook every police system asks is cop_can_see_player(cop). Headlights
# off (H) hides the car beyond SEE_RANGE_DARK: a dark car is a shape, a lit
# one is seen from far down the road.
#
# Night one also talks: a warning the first time a patrol car comes near,
# and a jab if the player gets spotted anyway. The lines are placeholders
# (the story is Roy's to write); `line_said` carries them, and game.gd hands
# them to Dave when his station is on, else to the HUD caption.
#
# F0/F1 does not chase or bust yet: nothing here starts SaveStore chases.
# Heat numbers are placeholders for the balance stage (G).

signal level_changed(level: int)
signal spotted(cop: Node3D)
signal line_said(text: String)

enum { NONE, ONE_CAR, TWO_CARS, ROADBLOCK, SPIKES, HELICOPTER }
const MAX_LEVEL := HELICOPTER
## Icon per level (HeatIcons draws them). Level 0 has none; neither do bad cops.
const ICONS := ["", "car", "two_cars", "sawhorse", "spikes", "helicopter"]

## Seeing. A lit car is seen down most of the reveal distance; a dark one
## only close up. Inside SEE_NEAR a cop notices you whichever way it faces;
## further out it looks through its windscreen (SEE_HALF_ANGLE) or, closer,
## its mirrors (MIRROR_RANGE behind).
const SEE_RANGE_LIT := 140.0
const SEE_RANGE_DARK := 18.0
const SEE_NEAR := 12.0
const SEE_HALF_ANGLE := 60.0   # degrees either side of straight ahead
const MIRROR_RANGE := 45.0
const EYE_HEIGHT := 1.2        # m above the cop's origin, for the line of sight
const TARGET_HEIGHT := 0.8

## Heat. Seen over the limit: straight to level 1, then up by RISE_PER_SEC x
## (speed / limit). Unseen for COOL_DELAY: down by COOL_PER_SEC.
const SPEED_LIMIT_KMH := 70.0
const RISE_PER_SEC := 0.1
const COOL_DELAY := 10.0
const COOL_PER_SEC := 0.05
const CHECK_EVERY := 0.1       # s between looks (rays are cheap, but not free)

## Night one.
const WARN_RANGE := 220.0
const WARNING_LINE := "Patrol car up ahead. First night out, so listen: they spot headlights long before they spot a car. Go dark and you were never here."
const MOCK_LINE := "And there it is. Lit up and flying past a patrol car on night one. Smile for the dashcam."

var player: Node3D
var night_clock: NightClock
var heat := 0.0
var level := NONE
var seen := false              # a (good) cop sees the player right now
var seen_by: Node3D
var cops: Array[Node3D] = []
var bad_cops: Array[Node3D] = []
var warned := false
var mocked := false
var _unseen_t := 0.0
var _check_t := 0.0
var _ray := PhysicsRayQueryParameters3D.new()

func register_cop(cop: Node3D, bad := false) -> void:
	var list := bad_cops if bad else cops
	if not cop in list:
		list.append(cop)

func unregister_cop(cop: Node3D) -> void:
	cops.erase(cop)
	bad_cops.erase(cop)
	if seen_by == cop:
		seen_by = null

## Run restarted: no heat, and night one may warn again.
func reset() -> void:
	heat = 0.0
	seen = false
	seen_by = null
	_unseen_t = 0.0
	warned = false
	mocked = false
	_set_level(NONE)

static func icon_for(lvl: int) -> String:
	return ICONS[clampi(lvl, 0, MAX_LEVEL)]

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
	var to := target - cop_xf.origin
	var d := to.length()
	var reach := SEE_RANGE_LIT if lights_on else SEE_RANGE_DARK
	if d > reach:
		return false
	if d <= SEE_NEAR:
		return true
	var fwd := -cop_xf.basis.z
	var cos_a := fwd.dot(to / d)
	if cos_a >= cos(deg_to_rad(SEE_HALF_ANGLE)):
		return true
	return cos_a < 0.0 and d <= MIRROR_RANGE

## THE hook: can this cop see the player right now? Range, view cone and
## headlights (can_see), then a ray for walls, buildings and cars in between.
func cop_can_see_player(cop: Node3D) -> bool:
	if player == null or cop == null or not is_instance_valid(cop) or not cop.is_inside_tree():
		return false
	if not can_see(cop.global_transform, player.global_position, headlights_on(player)):
		return false
	return _line_of_sight(cop)

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
	_ray.exclude = ex
	return space.intersect_ray(_ray).is_empty()

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		_look()
	_update_heat(delta)

func _look() -> void:
	cops = cops.filter(func(c: Node3D) -> bool: return is_instance_valid(c))
	bad_cops = bad_cops.filter(func(c: Node3D) -> bool: return is_instance_valid(c))
	var was := seen
	seen = false
	seen_by = null
	var nearest := INF
	for c in cops:
		nearest = minf(nearest, c.global_position.distance_to(player.global_position))
		if not seen and cop_can_see_player(c):
			seen = true
			seen_by = c
	if _night_one() and not warned and nearest <= WARN_RANGE:
		warned = true
		line_said.emit(WARNING_LINE)
	if seen and not was:
		spotted.emit(seen_by)

func _update_heat(delta: float) -> void:
	var kmh := 0.0
	if player is RigidBody3D:
		kmh = (player as RigidBody3D).linear_velocity.length() * 3.6
	if seen and kmh > SPEED_LIMIT_KMH:
		_unseen_t = 0.0
		var before := heat
		heat = maxf(heat, 1.0)
		heat = minf(heat + RISE_PER_SEC * (kmh / SPEED_LIMIT_KMH) * delta, float(MAX_LEVEL) + 0.999)
		if before < 1.0 and _night_one() and not mocked:
			mocked = true
			line_said.emit(MOCK_LINE)
	elif seen and heat > 0.0:
		_unseen_t = 0.0   # in sight at the limit: holds, no worse
	else:
		_unseen_t += delta
		if _unseen_t >= COOL_DELAY:
			heat = maxf(heat - COOL_PER_SEC * delta, 0.0)
	_set_level(clampi(int(floor(heat)), NONE, MAX_LEVEL))

func _set_level(l: int) -> void:
	if l != level:
		level = l
		level_changed.emit(l)

func _night_one() -> bool:
	return night_clock == null or night_clock.night == 1
