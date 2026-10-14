class_name CarLids
extends Node

# The hood and the trunk open in the game (engine bays B1, roadside hood pop
# R0; notes/engine-bays-better-2026-10-13.md, notes/roadside-hood-pop-2026-10-11.md;
# Roy 1270-1278, 1510). One node on the player car.
#
#   Y tap   the engine lid: the hood, or the rear lid on a rear-engined car
#           (the Bug, the kei).
#   Y hold  the other lid: trunk, hatch, tailgate.
#
# Rules:
#   - A lid opens only with the car stopped: under STOP_KMH for STOP_HOLD_S.
#     Open, the car is held on the handbrake (PlayerCar.lid_open).
#   - It shuts on gas, a gear change, Y again, a push over DRIVE_OFF_SPEED or
#     a hit (a velocity change over IMPACT_DV in one tick). Nothing but Y ever
#     opens one, so a crash never pops the hood (Roy 132).
#   - The swing is the hinge the car's glb carries (CarAssembler.hinges):
#     the latch pops the lid onto its safety catch (CATCH_DEG at once), then it
#     lifts to the hinge's open_deg in OPEN_TIME; it drops shut faster
#     (SHUT_TIME). While a lid is anything but shut, its panel is split out of
#     the body (CarAssembler.set_split: +1 draw call per open lid); shut, the
#     body goes back to the one closed mesh and the drive pays nothing.
#   - CarDetail.panel_open follows, so the bay parts exist only while a lid is
#     up and the car stands (CarDetail builds and hides them).
#   - The hazards come on with the lid and go back to how they were after
#     (CarLamps.hazard; Roy 1273).
#   - The chase camera cuts to the bay view while a lid is up (ChaseCamera
#     _place_bay); hinge_point() and lid_end() tell it where to stand.
#
# Cost: a few comparisons a tick; the swing is one transform a frame per open
# lid. No sound yet (the latch, hinge and slam are B2's sound step).

const NODE_NAME := "CarLids"
const ACTION := "hood_trunk"
const HOLD_S := 0.35           # Y held this long is the other lid
const STOP_KMH := 2.0
const STOP_HOLD_S := 0.5
const DRIVE_OFF_SPEED := 1.0   # m/s: a push over this drops an open lid shut
const IMPACT_DV := 0.8         # m/s change in one tick: a hit shuts it (ChaseCamera.IMPACT_DV)
const OPEN_TIME := 0.9         # s, catch to fully open
const SHUT_TIME := 0.45        # s, open to shut (it drops)
const CATCH_DEG := 4.0         # the latch pops it this far onto the safety catch at once
## Cars whose engine sits under the rear lid: Y tap opens that one (Roy 1274).
const REAR_ENGINE := ["p0_beater", "p4_kei"]
const OTHER_LIDS := ["hinge_trunk", "hinge_hatch", "hinge_tailgate", "hinge_hood"]

var vehicle: Vehicle
var body: MeshInstance3D
## The hinge Y taps and the one it holds for ("" when the car has none).
var engine_lid := ""
var other_lid := ""
## hinge name -> {open: bool, angle: float (degrees), node: Node3D}
var lids := {}

signal lid_changed(hinge: String, open: bool)

var _still_t := 0.0
var _press_t := 0.0
var _press_spent := false
var _last_vel := Vector3.ZERO
var _hazard_before := false
var _held_hazards := false

static func attach(v: Vehicle) -> CarLids:
	var l := CarLids.new()
	l.name = NODE_NAME
	l.vehicle = v
	v.add_child(l)
	return l

static func of(v: Node) -> CarLids:
	return v.get_node_or_null(NODE_NAME) as CarLids if v != null else null

func _ready() -> void:
	body = CarAssembler.body_of(vehicle)
	if body == null:
		return
	var hinges := CarAssembler.hinges(String(body.get_meta("car_id")))
	var car_id := String(body.get_meta("car_id"))
	if REAR_ENGINE.has(car_id) and hinges.has("hinge_trunk"):
		engine_lid = "hinge_trunk"
	elif hinges.has("hinge_hood"):
		engine_lid = "hinge_hood"
	for h in OTHER_LIDS:
		if h != engine_lid and hinges.has(h):
			other_lid = h
			break
	_last_vel = vehicle.linear_velocity

## True while the car has stood still long enough for a lid to open.
func can_open() -> bool:
	return body != null and _still_t >= STOP_HOLD_S

func is_open(hinge: String) -> bool:
	return lids.has(hinge) and lids[hinge].open

func any_open() -> bool:
	for h in lids:
		if lids[h].open:
			return true
	return false

## The open lid the camera should stand at: the engine lid first.
func view_lid() -> String:
	if is_open(engine_lid):
		return engine_lid
	for h in lids:
		if lids[h].open:
			return h
	return ""

## The lid's hinge line in the car's own frame (vehicle space).
func hinge_point(hinge: String) -> Vector3:
	var h: Dictionary = CarAssembler.hinges(String(body.get_meta("car_id"))).get(hinge, {})
	if h.is_empty():
		return Vector3.ZERO
	var xf := vehicle.global_transform.affine_inverse() * body.global_transform
	return xf * (h.origin as Vector3)

## -1 for a lid at the nose, +1 for one at the tail.
func lid_end(hinge: String) -> float:
	return -1.0 if hinge_point(hinge).z < 0.0 else 1.0

## Current swing of a lid, 0 shut .. open_deg, degrees.
func angle(hinge: String) -> float:
	return float(lids[hinge].angle) if lids.has(hinge) else 0.0

## Y tap. Opens the engine lid if the car stands, shuts it if it is open.
func tap() -> void:
	toggle(engine_lid)

## Y held. The other lid.
func hold() -> void:
	toggle(other_lid)

func toggle(hinge: String) -> void:
	if hinge == "" or body == null:
		return
	if is_open(hinge):
		shut(hinge)
	elif can_open():
		open(hinge)

func open(hinge: String) -> void:
	if hinge == "" or body == null or is_open(hinge):
		return
	var names := CarAssembler.split_hinges(body)
	if not names.has(hinge):
		names.append(hinge)
	var nodes := CarAssembler.set_split(body, names)
	if lids.has(hinge):
		lids[hinge].open = true
	else:
		lids[hinge] = {"open": true, "angle": CATCH_DEG, "node": null}
	_refresh_nodes(nodes)
	_set_panel_open(true)
	if not _held_hazards:
		var lamps := vehicle.get_node_or_null("CarLamps") as CarLamps
		if lamps != null:
			_hazard_before = lamps.hazard
			lamps.hazard = true
			_held_hazards = true
	lid_changed.emit(hinge, true)

func shut(hinge: String) -> void:
	if not is_open(hinge):
		return
	lids[hinge].open = false
	lid_changed.emit(hinge, false)
	if not any_open():
		_set_panel_open(false)
		if _held_hazards:
			var lamps := vehicle.get_node_or_null("CarLamps") as CarLamps
			if lamps != null:
				lamps.hazard = _hazard_before
			_held_hazards = false

func shut_all() -> void:
	for h in lids.keys():
		shut(h)

func _set_panel_open(on: bool) -> void:
	vehicle.set("lid_open", on)
	var d := vehicle.get_node_or_null(CarDetail.NODE_NAME) as CarDetail
	if d != null:
		d.panel_open = on
		d.refresh()

## A re-merge puts every hinge node back at 0: take the new nodes and set
## every lid's swing again.
func _refresh_nodes(nodes: Dictionary) -> void:
	for h in lids:
		if nodes.has(h):
			lids[h].node = nodes[h]
		_apply_angle(h)

func _physics_process(delta: float) -> void:
	if body == null:
		return
	var v := vehicle.linear_velocity
	var speed := v.length()
	_still_t = _still_t + delta if speed < STOP_KMH / 3.6 else 0.0
	if any_open():
		var dv := (v - _last_vel).length()
		var gas := float(vehicle.get("throttle_input")) > 0.0
		var shifted := InputMap.has_action("shift_up") and (Input.is_action_just_pressed("shift_up") \
			or Input.is_action_just_pressed("shift_down") or Input.is_action_just_pressed("reverse"))
		if speed > DRIVE_OFF_SPEED or gas or shifted or dv > IMPACT_DV * 60.0 / float(Engine.physics_ticks_per_second):
			shut_all()
	_last_vel = v
	if not InputMap.has_action(ACTION):
		return
	if Input.is_action_pressed(ACTION):
		_press_t += delta
		if _press_t >= HOLD_S and not _press_spent:
			_press_spent = true
			hold()
	elif _press_t > 0.0:
		if not _press_spent:
			tap()
		_press_t = 0.0
		_press_spent = false

func _process(delta: float) -> void:
	var done: Array[String] = []
	for h in lids:
		var lid: Dictionary = lids[h]
		var open_deg := float(CarAssembler.hinges(String(body.get_meta("car_id")))[h].open_deg)
		var target := open_deg if lid.open else 0.0
		var rate := open_deg / (OPEN_TIME if lid.open else SHUT_TIME)
		lid.angle = move_toward(float(lid.angle), target, rate * delta)
		_apply_angle(h)
		if not lid.open and float(lid.angle) <= 0.0:
			done.append(h)
	for h in done:
		lids.erase(h)
	if not done.is_empty():
		var names := CarAssembler.split_hinges(body)
		var keep := PackedStringArray()
		for n in names:
			if not done.has(n):
				keep.append(n)
		_refresh_nodes(CarAssembler.set_split(body, keep))

func _apply_angle(hinge: String) -> void:
	var lid: Dictionary = lids[hinge]
	var node := lid.node as Node3D
	if node == null or not is_instance_valid(node):
		return
	var h: Dictionary = CarAssembler.hinges(String(body.get_meta("car_id")))[hinge]
	node.transform = Transform3D(Basis(h.axis as Vector3, deg_to_rad(float(h.open_sign) * float(lid.angle))), h.origin as Vector3)
