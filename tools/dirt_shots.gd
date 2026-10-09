extends SceneTree

# Renders the player car clean, half dirty and fully dirty (CarDirt levels 0,
# 0.5 and 1) in the night scene, for judging the grime by eye. Needs the real
# renderer (no --headless). Writes PNGs to user://dirt_shots/.
#
#   <godot> --path . -s res://tools/dirt_shots.gd

const Harness := preload("res://tests/traffic_harness.gd")

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 60:
		await process_frame
	var p: PlayerCar = game.get("player")
	var dirt: CarDirt = game.get("fx").dirt
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://dirt_shots"))
	var cam := Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	for level in [0.0, 0.5, 1.0]:
		dirt.set_level(level)
		var mid: Vector3 = p.global_position
		var views := {
			"front34": mid + Vector3(-4.5, 1.3, -5.0),
			"side": mid + Vector3(-6.0, 0.9, 0.0),
			"rear34": mid + Vector3(4.0, 1.4, 5.0),
		}
		for v in views:
			cam.global_position = views[v]
			cam.look_at(mid + Vector3(0.0, 0.5, 0.0))
			cam.make_current()
			for i in 10:
				await process_frame
			var path := "user://dirt_shots/dirt_%d_%s.png" % [int(level * 100.0), v]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("dirt_shots: ", ProjectSettings.globalize_path(path))
	dirt.set_level(0.0)
	quit(0)
