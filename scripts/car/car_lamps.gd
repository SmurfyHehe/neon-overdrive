class_name CarLamps
extends Node

# The lamp driver for a car you drive (car-parts-every-vehicle plan, Roy
# 1173): brake lamps (and the third brake light) on the brake pedal, reverse
# lamps in reverse, left and right indicators, and the hazard lights on their
# own key. It only writes the lamp channels (instance uniforms on the body,
# NpcCarBuilder.set_lamps); the glow shader does the blinking, so a lit lamp
# costs no node and no draw call.
#
# Keys (project.godot): turn_left is ",", turn_right is ".", hazard is "/":
# three keys side by side under the right hand. An indicator stays on until
# you press it again, press the other side, or steer round the corner and
# straighten out (the stalk self-cancels). The hazards stay on until pressed
# again and override the indicators while on.

## Steering that counts as "turning" for the self-cancel, and the amount it
## must come back under (stalk returns once the wheel straightens).
const TURN_STEER := 0.35
const STRAIGHT_STEER := 0.10
const BRAKE_ON := 0.05

var vehicle: Vehicle
var turn_left := false
var turn_right := false
var hazard := false
var _turned := false      # steered past TURN_STEER since the indicator went on
var _key := -1

static func attach(v: Vehicle) -> CarLamps:
	var l := CarLamps.new()
	l.name = "CarLamps"
	l.vehicle = v
	v.add_child(l)
	return l

func toggle_left() -> void:
	turn_left = not turn_left
	turn_right = false
	_turned = false

func toggle_right() -> void:
	turn_right = not turn_right
	turn_left = false
	_turned = false

func toggle_hazard() -> void:
	hazard = not hazard

func _physics_process(_delta: float) -> void:
	if InputMap.has_action("turn_left") and Input.is_action_just_pressed("turn_left"):
		toggle_left()
	if InputMap.has_action("turn_right") and Input.is_action_just_pressed("turn_right"):
		toggle_right()
	if InputMap.has_action("hazard") and Input.is_action_just_pressed("hazard"):
		toggle_hazard()
	_self_cancel()
	apply()

## The stalk returns after the turn: steered past TURN_STEER, then straight.
func _self_cancel() -> void:
	if not (turn_left or turn_right):
		return
	var s := absf(vehicle.steering_input)
	if s > TURN_STEER:
		_turned = true
	elif _turned and s < STRAIGHT_STEER:
		turn_left = false
		turn_right = false
		_turned = false

## Writes this tick's lamp state to the body (only when it changed).
func apply() -> void:
	var parent := vehicle
	var visual: Node3D = parent.get("chassis_visual")
	if visual == null:
		return
	var brake := vehicle.brake_input > BRAKE_ON
	var reverse := vehicle.current_gear == -1
	var key := (1 if brake else 0) + (2 if reverse else 0) + (4 if hazard else 0) \
		+ (8 if turn_left else 0) + (16 if turn_right else 0)
	if key == _key:
		return
	_key = key
	NpcCarBuilder.set_lamps(visual, 1.0 if brake else 0.0, hazard, reverse, turn_left, turn_right)
