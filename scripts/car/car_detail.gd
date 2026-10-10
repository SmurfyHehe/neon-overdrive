class_name CarDetail
extends Node

# Parts nobody can see while driving (hide-unseen-parts plan 2026-10-09,
# Part 1): one node per car that decides when its "detail" parts exist and
# show. Detail parts are the ones only visible with a panel open or from a
# camera that walks round the car: the spring and damper units in the arches
# (CarParts), and later the engine bay, door and trunk contents (PRs #299 and
# #323 register theirs here). They are built the first time they are needed
# and hidden again after, so a drive pays nothing for them: no node, no draw
# call, no per-frame transform work.
#
# Detail is on when any of these holds:
#   - photo mode (GameState.PHOTO)
#   - the garage view (`CarDetail.garage`, set by the garage screen later)
#   - the car is stopped (under STOP_SPEED) with a panel open (`panel_open`,
#     set by the hood/door/trunk code)
#   - the underside is exposed (Part 2, flipped-car undersides): the car is
#     on its side or roof (basis.y.y under EXPOSED_UP, the wreck test's
#     threshold) or every wheel has been off the ground for AIRBORNE_MIN
#     seconds (a kerb hop builds nothing). It stays on EXPOSED_HOLD seconds
#     after the car lands or rights itself, so a bumpy landing does not
#     flicker the shocks. The undercarriage follows: on Low, where it is
#     hidden while driving, it shows while the car is exposed.
# It polls every POLL_SECS and also answers the state change signal at once,
# so photo mode never shows a frame without the parts. It runs while the tree
# is paused (photo mode pauses it).
#
# The undercarriage is the other half: it keeps its distance LOD (the real
# set within Undercarriage.LOD0_END, the plate to LOD1_END, nothing beyond)
# on every class now, player included, and the Low preset hides it unless
# detail is on. This node sits in the graphics_settings group for that.

const NODE_NAME := "CarDetail"
const STOP_SPEED := 0.5  # m/s, under this the car counts as stopped
const POLL_SECS := 0.2
const EXPOSED_UP := 0.5     # basis.y.y below this: on its side or roof (TrafficCar.WRECK_UP)
const AIRBORNE_MIN := 0.25  # seconds in the air before a jump counts as exposed
const EXPOSED_HOLD := 0.6   # seconds detail stays on after the car lands or rights itself

## The run's state machine, bound once by game.gd (null in tests and tools:
## then photo mode never counts).
static var game_state: GameState
## True while the garage view shows the car (the garage sets this later).
static var garage := false

## True while a hood, door or trunk on this car is open.
var panel_open := false
## Force detail on for this car (tests, the fleet orbit shots).
var force := false

signal changed(on: bool)

var vehicle: Vehicle
var on := false
var _parts: Array = []  # [{name, build: Callable, node: Node}]
var _underside: Array[VisualInstance3D] = []
var _t := 0.0
var _exposed_until_ms := 0
var _airborne_since_ms := -1

## The car's CarDetail node, made on first use.
static func of(v: Vehicle) -> CarDetail:
	var d := v.get_node_or_null(NODE_NAME) as CarDetail
	if d == null:
		d = CarDetail.new()
		d.name = NODE_NAME
		d.vehicle = v
		v.add_child(d)
	return d

const GROUP := "car_detail"

## Bind the run's state machine once (game.gd); every car's node, present or
## future, then answers photo mode entering and leaving at once.
static func bind_state(gs: GameState) -> void:
	game_state = gs
	gs.state_changed.connect(func(_n: GameState.State, _o: GameState.State) -> void:
		gs.get_tree().call_group(GROUP, "refresh"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GraphicsSettings.GROUP)
	add_to_group(GROUP)
	_find_underside()
	refresh()
	_apply_underside()

## Register a detail part. `build` returns the part's node (already added to
## the car); it runs once, the first time detail turns on. Until then the
## part does not exist.
func register(part_name: String, build: Callable) -> void:
	_parts.append({"name": part_name, "build": build, "node": null})
	if on:
		_show_part(_parts.back())

## The built node of a registered part, or null while it has not been needed.
func node_of(part_name: String) -> Node:
	for p in _parts:
		if p.name == part_name:
			return p.node
	return null

static func wants_detail(v: Vehicle, panel: bool, forced := false, exposed := false) -> bool:
	if forced or garage or exposed:
		return true
	if game_state != null and game_state.state == GameState.State.PHOTO:
		return true
	return panel and v != null and absf(v.speed) < STOP_SPEED

## On its side or roof.
static func is_flipped(v: Vehicle) -> bool:
	return v != null and v.is_inside_tree() and v.global_transform.basis.y.y < EXPOSED_UP

## No wheel touching anything. A car with no wheels wired up is never airborne.
static func is_airborne(v: Vehicle) -> bool:
	if v == null or not v.is_inside_tree():
		return false
	var any := false
	for w in [v.front_left_wheel, v.front_right_wheel, v.rear_left_wheel, v.rear_right_wheel]:
		if w == null:
			continue
		if (w as RayCast3D).is_colliding():
			return false
		any = true
	return any

## True while the underside can be seen from outside (flipped, or airborne
## for AIRBORNE_MIN) or within EXPOSED_HOLD seconds of that.
func exposed() -> bool:
	var now := Time.get_ticks_msec()
	var now_exposed := is_flipped(vehicle)
	if is_airborne(vehicle):
		if _airborne_since_ms < 0:
			_airborne_since_ms = now
		now_exposed = now_exposed or now - _airborne_since_ms >= int(AIRBORNE_MIN * 1000.0)
	else:
		_airborne_since_ms = -1
	if now_exposed:
		_exposed_until_ms = now + int(EXPOSED_HOLD * 1000.0)
		return true
	return now < _exposed_until_ms

func _process(delta: float) -> void:
	_t += delta
	if _t < POLL_SECS:
		return
	_t = 0.0
	refresh()

func apply_graphics() -> void:
	_apply_underside()

## Recompute and apply. Cheap when nothing changed.
func refresh() -> void:
	var want := wants_detail(vehicle, panel_open, force, exposed())
	if want == on:
		return
	on = want
	for p in _parts:
		if on:
			_show_part(p)
		elif p.node != null:
			(p.node as Node).set("visible", false)
	_apply_underside()
	changed.emit(on)

func _show_part(p: Dictionary) -> void:
	if p.node == null:
		p.node = (p.build as Callable).call()
	if p.node != null:
		(p.node as Node).set("visible", true)

# ---------- the undercarriage on Low ----------

func _find_underside() -> void:
	_underside.clear()
	for n in vehicle.find_children(Undercarriage.NODE_NAME + "*", "VisualInstance3D", true, false):
		_underside.append(n as VisualInstance3D)

func _apply_underside() -> void:
	var shown := on or GraphicsSettings.preset != "low"
	for u in _underside:
		u.visible = shown
