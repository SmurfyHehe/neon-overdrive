class_name PhotoMode
extends Node

# Photo mode (ROADMAP item 12, Roy's idea). P pauses the game (GameState.PHOTO),
# hides every HUD layer and hands the view to a photo camera. The car is frozen
# where it was (Roy 1499): the camera is for framing a shot, nothing moves.
# Keyboard only, no on-screen hints; the keys are on the Controls page like
# every other action.
#
# Two camera modes, Tab switches (camera proposal 2026-10-13, section 3):
#   ORBIT (the start): the car stays centred. A/D circle it, W/S closer/further
#     (ORBIT_DIST_MIN..MAX), Q/E lower/higher, arrows nudge the aim so the car
#     can sit off centre (AIM_MAX_DEG).
#   FREE: as before. W/S forward/back, A/D left/right, Q/E down/up, arrows look.
#   Both: hold Shift for fast; Shift + Left/Right tilts the shot (ROLL_MAX_DEG);
#     Z/X narrower/wider field of view; Shift + Z/X background blur 0..BLUR_STEPS
#     (0 = sharp, GT7's "background blurring" row); Enter saves a PNG;
#     P or Esc leaves.
#
# The blur is Godot's camera depth of field on the photo camera only, so it
# costs nothing outside photo mode. Focus sits on the car in orbit and on
# whatever is under the screen centre in free. Film grain and the screen
# effects stay on (they are the look, not the HUD). No film sims, stickers or
# frames (decided). Shots go to user://photos/neon_overdrive_<date>_<time>.png.

const PHOTO_DIR := "user://photos"
const MOVE_SPEED := 8.0      # m/s, free camera
const FAST_MULT := 4.0
const LOOK_SPEED := 60.0     # degrees per second (free look, orbit aim nudge)
const FOV_RATE := 25.0       # degrees per second
const FOV_MIN := 20.0
const FOV_MAX := 100.0
const ORBIT_RATE := 1.2            # rad/s round the car (A/D)
const ORBIT_DIST_RATE := 6.0       # m/s in and out (W/S)
const ORBIT_HEIGHT_RATE := 3.0     # m/s up and down (Q/E)
const ORBIT_DIST_MIN := 1.5
const ORBIT_DIST_MAX := 30.0
const ORBIT_HEIGHT_MIN := -0.4     # metres relative to the aim point: never under the car's floor
const ORBIT_HEIGHT_MAX := 12.0
const AIM_HEIGHT := 0.6            # aim a little above the car's origin, like the pause look
const AIM_MAX_DEG := 30.0          # how far the arrows push the car off centre in orbit
const ROLL_RATE := 45.0            # degrees per second (Shift + Left/Right)
const ROLL_MAX_DEG := 45.0
const BLUR_STEPS := 10             # Shift + Z/X: 0 sharp .. 10 blurriest
const BLUR_STEP_RATE := 6.0        # steps per second while held
const BLUR_AMOUNT_MAX := 0.35      # CameraAttributesPractical.dof_blur_amount at step 10
const FOCUS_FALLBACK_M := 60.0     # free camera looking at the sky: focus here
const KEEP_LAYERS := ["film_grain.gd", "screen_fx.gd"]  # scripts of the CanvasLayers that stay visible

## action -> keycode; registered into the InputMap so the Controls page lists them.
const KEYS := {
	"photo_mode": KEY_P, "photo_shot": KEY_ENTER, "photo_orbit": KEY_TAB,
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
var orbit := true           # Tab: true = circle the frozen car, false = fly free
var last_saved := ""        # path of the latest PNG, for tests and the log
var roll := 0.0             # degrees, + = clockwise on screen
var blur := 0.0             # 0..BLUR_STEPS (a float so holding the key glides)
var orbit_yaw := 0.0        # radians round the car, 0 = behind it (+z side)
var orbit_dist := 6.0
var orbit_height := 2.0     # metres above the aim point
var aim_yaw := 0.0          # degrees, orbit only: the arrows' off-centre nudge
var aim_pitch := 0.0
var _yaw := 0.0             # free camera, radians
var _pitch := 0.0
var hidden_layers: Array = []
var _dof: CameraAttributesPractical

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
	_dof = CameraAttributesPractical.new()
	game_state.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: GameState.State, _old: GameState.State) -> void:
	if new_state == GameState.State.PHOTO and not active:
		_enter()
	elif new_state != GameState.State.PHOTO and active:
		_leave()

func _enter() -> void:
	active = true
	# Start where the view is now: the chase camera while driving, the pause
	# look's orbit when opened from the pause menu. Orbit mode reads that pose
	# as a position round the car, so the first frame barely moves.
	var seen := get_viewport().get_camera_3d()
	if seen == null or seen == free_cam:
		seen = chase
	free_cam.global_transform = seen.global_transform
	free_cam.fov = seen.fov
	var e := free_cam.global_transform.basis.get_euler()
	_pitch = e.x
	_yaw = e.y
	roll = 0.0
	blur = 0.0
	aim_yaw = 0.0
	aim_pitch = 0.0
	orbit = true
	_orbit_from(free_cam.global_position)
	free_cam.attributes = _dof
	_apply_blur()
	free_cam.current = true
	hidden_layers.clear()
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if layer.visible and not _keeps(layer):
			hidden_layers.append(layer)
			layer.visible = false
	_place()

func _leave() -> void:
	active = false
	free_cam.attributes = null   # the blur costs nothing while driving
	for layer in hidden_layers:
		if is_instance_valid(layer):
			layer.visible = true
	hidden_layers.clear()
	chase.reset_orbit()   # back from photo mode: straight behind the car
	chase.current = true

func _process(delta: float) -> void:
	if not active:
		return
	if Input.is_action_just_pressed("photo_orbit"):
		toggle_orbit()
	step(delta)
	if Input.is_action_just_pressed("photo_shot"):
		save_shot()

## The point the orbit circles and the blur focuses on: the frozen car.
func aim_point() -> Vector3:
	if chase == null or chase.target == null:
		return free_cam.global_position + free_cam.global_basis * Vector3(0.0, 0.0, -orbit_dist)
	return chase.target.global_position + Vector3(0.0, AIM_HEIGHT, 0.0)

## Tab: orbit <-> free. Either way the camera stays where it is: orbit reads the
## free pose as yaw/distance/height, free picks up the orbit's look direction.
func toggle_orbit() -> void:
	set_orbit(not orbit)

func set_orbit(on: bool) -> void:
	if on == orbit:
		return
	orbit = on
	if orbit:
		_orbit_from(free_cam.global_position)
		aim_yaw = 0.0
		aim_pitch = 0.0
	else:
		var e := free_cam.global_transform.basis.get_euler()
		_pitch = e.x
		_yaw = e.y
	_place()

func _orbit_from(pos: Vector3) -> void:
	var d := pos - aim_point()
	var flat := Vector2(d.x, d.z)
	orbit_dist = clampf(flat.length(), ORBIT_DIST_MIN, ORBIT_DIST_MAX)
	orbit_yaw = atan2(d.x, d.z) if flat.length() > 0.01 else 0.0
	orbit_height = clampf(d.y, ORBIT_HEIGHT_MIN, ORBIT_HEIGHT_MAX)

## One frame of camera control; split out so tests can drive it.
func step(delta: float) -> void:
	var fast := Input.is_action_pressed("photo_fast")
	var side := Input.get_axis("photo_look_left", "photo_look_right")
	var updown := Input.get_axis("photo_look_down", "photo_look_up")
	if fast:
		# Shift + Left/Right: tilt the shot. Shift + Z/X: background blur.
		roll = clampf(roll + side * ROLL_RATE * delta, -ROLL_MAX_DEG, ROLL_MAX_DEG)
		blur = clampf(blur + Input.get_axis("photo_fov_narrow", "photo_fov_wide") * BLUR_STEP_RATE * delta, 0.0, float(BLUR_STEPS))
		side = 0.0
	else:
		free_cam.fov = clampf(free_cam.fov + Input.get_axis("photo_fov_narrow", "photo_fov_wide") * FOV_RATE * delta, FOV_MIN, FOV_MAX)
	var mult := FAST_MULT if fast else 1.0
	if orbit:
		orbit_yaw -= Input.get_axis("photo_left", "photo_right") * ORBIT_RATE * mult * delta
		orbit_dist = clampf(orbit_dist - Input.get_axis("photo_back", "photo_forward") * ORBIT_DIST_RATE * mult * delta, ORBIT_DIST_MIN, ORBIT_DIST_MAX)
		orbit_height = clampf(orbit_height + Input.get_axis("photo_down", "photo_up") * ORBIT_HEIGHT_RATE * mult * delta, ORBIT_HEIGHT_MIN, ORBIT_HEIGHT_MAX)
		aim_yaw = clampf(aim_yaw - side * LOOK_SPEED * delta, -AIM_MAX_DEG, AIM_MAX_DEG)
		aim_pitch = clampf(aim_pitch + updown * LOOK_SPEED * delta, -AIM_MAX_DEG, AIM_MAX_DEG)
	else:
		_yaw -= side * deg_to_rad(LOOK_SPEED) * delta
		_pitch = clampf(_pitch + updown * deg_to_rad(LOOK_SPEED) * delta, -1.5, 1.5)
		var move := Vector3(
			Input.get_axis("photo_left", "photo_right"),
			Input.get_axis("photo_down", "photo_up"),
			-Input.get_axis("photo_back", "photo_forward"))
		var flat := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))   # roll never steers the fly
		free_cam.global_position += flat * move * MOVE_SPEED * mult * delta
	_place()
	_apply_blur()

## Puts the camera where the mode says, with the aim nudge and the roll on top.
func _place() -> void:
	if orbit:
		var c := aim_point()
		var pos := c + Vector3(sin(orbit_yaw) * orbit_dist, orbit_height, cos(orbit_yaw) * orbit_dist)
		var look := Transform3D.IDENTITY.looking_at(c - pos, Vector3.UP).basis
		free_cam.global_position = pos
		free_cam.global_basis = look * Basis.from_euler(Vector3(deg_to_rad(aim_pitch), deg_to_rad(aim_yaw), deg_to_rad(-roll)))
	else:
		free_cam.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, deg_to_rad(-roll)))

## Where the blur is sharp: the car in orbit, what the screen centre sees in free.
func focus_distance() -> float:
	if orbit:
		return free_cam.global_position.distance_to(aim_point())
	var space := free_cam.get_world_3d().direct_space_state if free_cam.is_inside_tree() else null
	if space == null:
		return FOCUS_FALLBACK_M
	var from := free_cam.global_position
	var to := from + free_cam.global_basis * Vector3(0.0, 0.0, -200.0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return FOCUS_FALLBACK_M
	return maxf(from.distance_to(hit.position), 0.5)

## Depth of field on the photo camera from the blur row: 0 turns it off.
func _apply_blur() -> void:
	if _dof == null:
		return
	var on := blur > 0.01
	_dof.dof_blur_far_enabled = on
	_dof.dof_blur_near_enabled = on
	if not on:
		return
	var f := focus_distance()
	var t := blur / float(BLUR_STEPS)
	_dof.dof_blur_amount = lerpf(0.04, BLUR_AMOUNT_MAX, t)
	# The sharp band shrinks as the row goes up: wide at 1, tight at 10.
	var band := f * lerpf(0.9, 0.25, t)
	_dof.dof_blur_far_distance = f + band
	_dof.dof_blur_far_transition = maxf(band * 1.5, 1.0)
	_dof.dof_blur_near_distance = maxf(f - band, 0.3)
	_dof.dof_blur_near_transition = maxf(band, 0.5)

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
