extends SceneTree

# Renders the look-back camera (B) in both views, with a traffic car and the
# road behind, for judging what the player sees: chase_fwd, chase_back,
# cockpit_fwd, cockpit_back. Real renderer only (no --headless). Writes PNGs
# to user://look_back_shots/.
#
#   <godot> --path . -s res://tools/look_back_shots.gd

var game: Node
var dir: String

func _initialize() -> void:
	AudioSettings.path = "user://look_back_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	dir = ProjectSettings.globalize_path("user://look_back_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 0.0
		c.handbrake_input = 0.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for i in 60:
		await physics_frame
	for view in [["chase", ChaseCamera.View.CHASE], ["cockpit", ChaseCamera.View.COCKPIT]]:
		cam.set_view(view[1])
		for back in [false, true]:
			Input.action_release("look_back")
			if back:
				Input.action_press("look_back")
			for i in 90:
				await physics_frame
			for i in 6:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, view[0], "back" if back else "fwd"])
		Input.action_release("look_back")
	print("wrote ", dir)
	quit(0)
