extends SceneTree

# Screenshots of one car in the game, for a PR's before/after: the stage A
# chase cam, then a 3/4 front and a side camera. Real renderer (no
# --headless): a window opens for about ten seconds. Settings go to the test
# harness's file, so your own settings.cfg is untouched.
#
#   set NEON_CAR=p17_work_pickup
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tools/car_shot.gd
#
# Writes user://car_shots/<kind>_chase.png, _front.png and _side.png (the
# path is printed at the end). Any NpcCarBuilder kind works, traffic and
# police included, so a new car can be shot next to the one it replaces.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const SETTLE_FRAMES := 240
const DIR := "user://car_shots"

var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var kind := PlayerCar.chassis_kind()
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in SETTLE_FRAMES:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_save("%s/%s_chase.png" % [DIR, kind])
	var car := _player()
	if car != null:
		var prev := root.get_viewport().get_camera_3d()
		var cam := Camera3D.new()
		cam.fov = 50.0
		root.add_child(cam)
		# car space: X right, -Z forward
		# the car may be rolling (the harness boots it driving), so the camera
		# follows it every frame until the shot is taken
		for shot in [["front", Vector3(3.6, 1.4, -6.2)], ["side", Vector3(7.0, 1.2, 0.0)]]:
			cam.make_current()
			for i in 12:
				cam.global_position = car.global_transform * Vector3(shot[1])
				cam.look_at(car.global_position + Vector3(0.0, 0.7, 0.0))
				await process_frame
			_save("%s/%s_%s.png" % [DIR, kind, shot[0]])
		if prev != null:
			prev.make_current()
		cam.queue_free()
	else:
		printerr("car_shot: no PlayerCar in the scene")
	print("car_shot: wrote ", ProjectSettings.globalize_path(DIR))
	quit(0)

func _player() -> Node3D:
	for n in root.find_children("*", "PlayerCar", true, false):
		return n
	return null

func _save(path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("car_shot: ", path)
