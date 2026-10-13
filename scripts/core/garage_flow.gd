class_name GarageFlow
extends Node

# The garage's plumbing (G0, 2026-10-11): everything around the garage screen
# that is not the screen. GameState owns the states (DAWN, GARAGE) and the
# entry points (request_dawn, open_garage, leave_garage); this node reacts:
#
#   - on entry (GameState.garage_entering, the world still on screen): the run
#     is saved by SaveDirector as it leaves PLAYING, and a Polaroid of the car
#     goes next to it (user://saves/slot_N/polaroids/<car>.png, 320x180, one
#     file per car, replaced each visit; the shop-wall board reads them later);
#   - frame cap in the garage and on the dawn card: the lower of the player's
#     own cap and 60, dropping to 30 after IDLE_SECS with no key or mouse input;
#   - discord hook: Presence says "Garage" in there, "Driving" out here;
#   - "Go out": the car is parked where it stands (stopped, handbrake held) with
#     the engine off. It stays off until the starter key (X) is held for
#     START_HOLD seconds, and while it is off the throttle does nothing.
#
# Auto-pause is GameState's: neither state ever auto-pauses (feed_frame).
# The menu lock while a cop sees the player is GameState.open_garage /
# request_dawn (both refuse, the dawn card waits).

const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const Presence := preload("res://scripts/core/presence.gd")

## Frame caps in the garage, in fps. 0 for the player's own cap means uncapped.
const GARAGE_CAP := 60
const IDLE_CAP := 30
const IDLE_SECS := 5.0
## How long the starter key is held to start a parked car.
const START_HOLD := 0.4
const POLAROID_SIZE := Vector2i(320, 180)

var game_state: GameState
var player: PlayerCar

## What this node last asked Engine.max_fps to be (0 = not in the garage).
## Tests read it: a headless run never touches Engine.max_fps itself.
var applied_cap := 0
var idle_secs := 0.0
## True from "Go out" until the engine is started.
var parked_off := false
## Polaroids written this session (tests read it).
var polaroids := 0

var _held := 0.0
var _own_driver := false
var _inside := false

func _init(state: GameState, car: PlayerCar) -> void:
	game_state = state
	player = car
	name = "GarageFlow"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_state.garage_entering.connect(_on_entering)
	game_state.garage_left.connect(_on_left)
	game_state.state_changed.connect(_on_state_changed)

# ---------- pure bits (tests call these) ----------

## The frame cap for the garage, given the player's own cap (0 = none).
static func cap_for(player_cap: int, idle: bool) -> int:
	var cap := GARAGE_CAP if player_cap <= 0 else mini(player_cap, GARAGE_CAP)
	return mini(cap, IDLE_CAP) if idle else cap

static func polaroid_path(car_id: String, slot_n: int = 0) -> String:
	return SaveStore.slot_dir(slot_n).path_join("polaroids").path_join(car_id + ".png")

## Writes a Polaroid of the car from an image: scaled to POLAROID_SIZE, saved
## under the active slot. False on an empty image or a write error.
static func write_polaroid(img: Image, car_id: String) -> bool:
	if img == null or img.is_empty():
		return false
	var small := img.duplicate() as Image
	small.resize(POLAROID_SIZE.x, POLAROID_SIZE.y, Image.INTERPOLATE_BILINEAR)
	var path := polaroid_path(car_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return small.save_png(path) == OK

# ---------- entry ----------

func _on_entering(entry: String) -> void:
	capture_polaroid()
	# 6 a.m.: the car stands in the garage all day and comes out cold. Before
	# GameState leaves PLAYING, so the save made on the way in has it cool.
	if entry == GameState.ENTRY_DAWN and player != null and is_instance_valid(player):
		player.rest_overnight()

## Takes the Polaroid from what is on screen now. Needs a real renderer: a
## headless run has no frame to read, so it returns false there. Not in test
## mode or during a chase either (nothing is written then).
func capture_polaroid() -> bool:
	if not SaveDirector.enabled or SaveStore.chase_active:
		return false
	if DisplayServer.get_name() == "headless" or get_viewport() == null:
		return false
	var tex := get_viewport().get_texture()
	if tex == null:
		return false
	if write_polaroid(tex.get_image(), PlayerCar.chassis_kind()):
		polaroids += 1
		return true
	return false

func _on_state_changed(_new_state: GameState.State, _old_state: GameState.State) -> void:
	var now := game_state.in_garage()   # the dawn card, the garage, or its wash
	if now:
		idle_secs = 0.0
	if now and not _inside:
		Presence.set_activity(Presence.GARAGE)
	elif _inside and not now:
		Presence.set_activity(Presence.DRIVING)
		applied_cap = 0
		if _caps_fps():
			Engine.max_fps = GraphicsSettings.fps_cap   # the player's own cap again
	_inside = now

func _caps_fps() -> bool:
	return DisplayServer.get_name() != "headless"

# ---------- the frame cap ----------

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion \
			or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		idle_secs = 0.0

func _process(delta: float) -> void:
	if not game_state.in_garage():
		return
	idle_secs += delta
	applied_cap = cap_for(GraphicsSettings.fps_cap, idle_secs >= IDLE_SECS)
	# Settings re-applies the player's cap when it closes; this takes it back.
	if _caps_fps() and Engine.max_fps != applied_cap:
		Engine.max_fps = applied_cap

# ---------- "Go out": the parked car ----------

func _on_left() -> void:
	park_car()

## The car stays where it is, stopped, with the engine off.
func park_car() -> void:
	if player == null or not is_instance_valid(player):
		return
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player.engine_running = false
	player.throttle_input = 0.0
	parked_off = true
	_held = 0.0
	if not player.driver.is_valid():
		player.driver = _parked_driver
		_own_driver = true

## Keys as the player holds them, minus the throttle, plus the handbrake: a car
## with its engine off goes nowhere (also in AUTO/SEMI, where GEVP itself would
## still drive without a running engine).
func _parked_driver(c: Vehicle) -> void:
	var car := c as PlayerCar
	if car == null:
		return
	var k := PlayerCar.read_keys()
	k &= ~PlayerCar.KEY_ACCEL
	k |= PlayerCar.KEY_HANDBRAKE
	car.apply_keys(k)

func _physics_process(delta: float) -> void:
	if not parked_off or player == null or not is_instance_valid(player):
		return
	if Input.is_action_pressed("starter"):
		_held += delta
		if _held >= START_HOLD:
			start_engine()
	else:
		_held = 0.0

## Engine on: the parked car drives again.
func start_engine() -> void:
	if player != null and is_instance_valid(player):
		player.engine_running = true
		if _own_driver:
			player.driver = Callable()
	_own_driver = false
	parked_off = false
	_held = 0.0
