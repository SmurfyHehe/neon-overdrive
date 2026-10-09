class_name PhotoMode
extends Node

# Photo mode (ROADMAP item 12, Roy's idea). P pauses the game (GameState.PHOTO),
# hides every HUD layer and hands the view to a free camera that starts where the
# chase camera was. Keyboard only, no on-screen hints; the keys are on the
# Controls page like every other action.
#
#   W/S forward/back, A/D left/right, Q/E down/up (hold Shift for fast),
#   arrows look, Z/X narrower/wider field of view, Enter saves a PNG,
#   P or Esc leaves.
#
# Film grain and the screen effects stay on (they are the look, not the HUD).
# Shots go to user://photos/neon_overdrive_<date>_<time>.png.

const PHOTO_DIR := "user://photos"
const MOVE_SPEED := 8.0      # m/s
const FAST_MULT := 4.0
const LOOK_SPEED := 60.0     # degrees per second
const FOV_RATE := 25.0       # degrees per second
const FOV_MIN := 20.0
const FOV_MAX := 100.0
const KEEP_LAYERS := ["film_grain.gd", "screen_fx.gd"]  # scripts of the CanvasLayers that stay visible

## action -> keycode; registered into the InputMap so the Controls page lists them.
const KEYS := {
	"photo_mode": KEY_P, "photo_shot": KEY_ENTER,
	"photo_forward": KEY_W, "photo_back": KEY_S, "photo_left": KEY_A, "photo_right": KEY_D,
	"photo_down": KEY_Q, "photo_up": KEY_E, "photo_fast": KEY_SHIFT,
	"photo_look_left": KEY_LEFT, "photo_look_right": KEY_RIGHT,
	"photo_look_up": KEY_UP, "photo_look_down": KEY_DOWN,
	"photo_fov_narrow": KEY_Z, "photo_fov_wide": KEY_X,
}

var game_state: GameState
var chase: ChaseCamera
var free_cam: Camera3D
var active := false
var last_saved := ""        # path of the latest PNG, for tests and the log
var _yaw := 0.0
var _pitch := 0.0
var hidden_layers: Array = []

static func ensure_actions() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.keycode = KEYS[action]
		InputMap.action_add_event(action, ev)

func _init(state: GameState, chase_camera: ChaseCamera) -> void:
	game_state = state
	chase = chase_camera

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_actions()
	free_cam = Camera3D.new()
	free_cam.name = "PhotoCamera"
	add_child(free_cam)
	game_state.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: GameState.State, _old: GameState.State) -> void:
	if new_state == GameState.State.PHOTO and not active:
		_enter()
	elif new_state != GameState.State.PHOTO and active:
		_leave()

func _enter() -> void:
	active = true
	free_cam.global_transform = chase.global_transform
	free_cam.fov = chase.fov
	var e := free_cam.global_transform.basis.get_euler()
	_pitch = e.x
	_yaw = e.y
	free_cam.current = true
	hidden_layers.clear()
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if layer.visible and not _keeps(layer):
			hidden_layers.append(layer)
			layer.visible = false

func _leave() -> void:
	active = false
	for layer in hidden_layers:
		if is_instance_valid(layer):
			layer.visible = true
	hidden_layers.clear()
	chase.current = true

func _process(delta: float) -> void:
	if not active:
		return
	step(delta)
	if Input.is_action_just_pressed("photo_shot"):
		save_shot()

## One frame of free-camera control; split out so tests can drive it.
func step(delta: float) -> void:
	_yaw -= Input.get_axis("photo_look_left", "photo_look_right") * deg_to_rad(LOOK_SPEED) * delta
	_pitch = clampf(_pitch + Input.get_axis("photo_look_down", "photo_look_up") * deg_to_rad(LOOK_SPEED) * delta, -1.5, 1.5)
	free_cam.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var move := Vector3(
		Input.get_axis("photo_left", "photo_right"),
		Input.get_axis("photo_down", "photo_up"),
		-Input.get_axis("photo_back", "photo_forward"))
	var speed := MOVE_SPEED * (FAST_MULT if Input.is_action_pressed("photo_fast") else 1.0)
	free_cam.global_position += free_cam.global_basis * move * speed * delta
	free_cam.fov = clampf(free_cam.fov + Input.get_axis("photo_fov_narrow", "photo_fov_wide") * FOV_RATE * delta, FOV_MIN, FOV_MAX)

## Saves the current frame as a PNG; returns the path, or "" when there is no
## image to save (a headless run has no framebuffer) or the write failed.
func save_shot() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	var t := Time.get_datetime_dict_from_system()
	var path := "%s/neon_overdrive_%04d%02d%02d_%02d%02d%02d.png" % [PHOTO_DIR, t.year, t.month, t.day, t.hour, t.minute, t.second]
	if img.save_png(path) != OK:
		return ""
	last_saved = path
	return path

static func _keeps(layer: CanvasLayer) -> bool:
	var s: Script = layer.get_script()
	return s != null and KEEP_LAYERS.has(s.resource_path.get_file())
