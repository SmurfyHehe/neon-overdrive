extends SceneTree

# Photo mode: drives the real Game.tscn. P enters (tree paused, HUD layers
# hidden, free camera current at the chase camera's pose), held keys move the
# free camera, Esc leaves and restores everything. A headless run has no
# framebuffer, so save_shot() must return "" there instead of crashing; with a
# real renderer it writes a PNG under user://photos. The car is driven first
# and its position, velocity, gear and rpm are snapshotted on entering and on
# leaving photo mode: they must match, and a pausable counter must not tick
# while the photo is being taken. Exit code 1 on failure.
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/photo_mode.gd

const TIMEOUT_TICKS := 1200
var failures: Array[String] = []
var tick := 0
var phase := 0
var start_tick := 0
var chase_pos := Vector3.ZERO
var layers_before := 0
var game: Node
var photo: PhotoMode
var car_in := {}
var car_out := {}
var gameplay_ticks := 0     # counted by a pausable node: gameplay time
var ticks_at_enter := -1

## Counts physics frames only while the tree runs (default pausable mode).
class TickCounter extends Node:
	var owner_test
	func _physics_process(_d: float) -> void:
		owner_test.gameplay_ticks += 1

func _car_state(car: PlayerCar) -> Dictionary:
	return {"pos": car.global_position, "vel": car.linear_velocity,
		"ang": car.angular_velocity, "gear": car.gear, "rpm": car.motor_rpm}

func _same(a: Dictionary, b: Dictionary, label: String) -> void:
	_check(a.pos.distance_to(b.pos) < 0.001, "%s: car moved %.4f m" % [label, a.pos.distance_to(b.pos)])
	_check(a.vel.distance_to(b.vel) < 0.001, "%s: velocity changed %s -> %s" % [label, a.vel, b.vel])
	_check(a.ang.distance_to(b.ang) < 0.001, "%s: angular velocity changed" % label)
	_check(a.gear == b.gear, "%s: gear changed %d -> %d" % [label, a.gear, b.gear])
	_check(absf(a.rpm - b.rpm) < 0.5, "%s: rpm changed %.1f -> %.1f" % [label, a.rpm, b.rpm])

func _on_state(new_state: GameState.State, old_state: GameState.State) -> void:
	if new_state == GameState.State.PHOTO:
		car_in = _car_state(game.player)
		ticks_at_enter = gameplay_ticks
	elif old_state == GameState.State.PHOTO:
		car_out = _car_state(game.player)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _press(action: String, down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)

func _visible_layers() -> int:
	var n := 0
	for l in root.find_children("*", "CanvasLayer", true, false):
		if l.visible:
			n += 1
	return n

func _physics_process(_delta: float) -> bool:
	tick += 1
	game = current_scene
	if game == null or game.get("camera") == null or game.get("game_state") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var gs: GameState = game.game_state
	var cam: ChaseCamera = game.camera
	match phase:
		0:
			if tick < 30:
				return false
			if tick == 30:
				var counter := TickCounter.new()
				counter.owner_test = self
				game.add_child(counter)
				gs.state_changed.connect(_on_state)
				_press("accelerate", true)   # get the car rolling so velocity/rpm mean something
				return false
			if tick < 150:
				return false
			_press("accelerate", false)
			for c in game.get_children():
				if c is PhotoMode:
					photo = c
			_check(photo != null, "Game should own a PhotoMode node")
			if photo == null:
				return _end("")
			layers_before = _visible_layers()
			_check(layers_before >= 3, "HUD layers should be visible while playing (%d)" % layers_before)
			chase_pos = cam.global_position
			_press("photo_mode", true)
			start_tick = tick
			phase = 1
		1:
			if tick - start_tick < 3:
				return false
			_press("photo_mode", false)
			_check(gs.state == GameState.State.PHOTO, "P should enter photo mode, state %d" % gs.state)
			_check(paused, "the tree should be paused")
			_check(photo.free_cam.current, "the free camera should be current")
			_check(photo.free_cam.global_position.distance_to(chase_pos) < 0.5, "free cam should start at the chase camera")
			var shown := 0
			for l in root.find_children("*", "CanvasLayer", true, false):
				if l.visible and not PhotoMode._keeps(l):
					shown += 1
			_check(shown == 0, "all HUD layers should be hidden, %d still visible" % shown)
			_check(_visible_layers() < layers_before, "fewer layers should be visible than before")
			_press("photo_forward", true)
			_press("photo_up", true)
			start_tick = tick
			phase = 2
		2:
			photo.step(1.0 / 60.0)
			if tick - start_tick < 30:
				return false
			_press("photo_forward", false)
			_press("photo_up", false)
			_check(photo.free_cam.global_position.distance_to(chase_pos) > 1.5, "held keys should move the free camera (%.2f m)" % photo.free_cam.global_position.distance_to(chase_pos))
			_check(photo.free_cam.global_position.y > chase_pos.y, "the up key should raise the camera")
			var fov0 := photo.free_cam.fov
			_press("photo_fov_narrow", true)
			photo.step(0.5)
			_press("photo_fov_narrow", false)
			_check(photo.free_cam.fov < fov0, "Z should narrow the field of view")
			var path := photo.save_shot()
			if DisplayServer.get_name() == "headless":
				_check(path == "", "headless has no framebuffer: save_shot must return empty")
			else:
				_check(path != "" and FileAccess.file_exists(path), "a PNG should be written (%s)" % path)
				if path != "":
					var img := Image.load_from_file(path)
					_check(img != null and not img.is_empty() and img.get_width() > 0, "the saved PNG should load as an image")
					print("photo_mode: saved ", ProjectSettings.globalize_path(path))
			_check(gameplay_ticks == ticks_at_enter, "gameplay time advanced while in photo mode (%d ticks)" % (gameplay_ticks - ticks_at_enter))
			_same(car_in, _car_state(game.player), "while paused")
			_press("pause", true)
			start_tick = tick
			phase = 3
		3:
			if tick - start_tick < 3:
				return false
			_press("pause", false)
			_check(gs.state == GameState.State.PLAYING, "Esc should leave photo mode, state %d" % gs.state)
			_check(not paused, "the tree should run again")
			_check(cam.current and not photo.free_cam.current, "the chase camera should be current again")
			_check(_visible_layers() == layers_before, "HUD layers should be restored (%d vs %d)" % [_visible_layers(), layers_before])
			_check(not car_in.is_empty() and not car_out.is_empty(), "car state should be captured on enter and leave")
			if not car_in.is_empty() and not car_out.is_empty():
				_check(car_in.vel.length() > 1.0, "the car should be moving when photo mode starts (%.2f m/s)" % car_in.vel.length())
				_same(car_in, car_out, "enter vs leave")
				print("photo_mode: car at enter %.1f m/s, gear %d, %.0f rpm" % [car_in.vel.length(), car_in.gear, car_in.rpm])
			_check(gameplay_ticks > ticks_at_enter, "gameplay should tick again after leaving")
			return _end("")
	return tick > TIMEOUT_TICKS and _end("timed out in phase %d" % phase)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	print("photo_mode: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return true
