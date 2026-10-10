extends SceneTree

# Screenshots for the font pass: the chase HUD, the pause menu, its Controls
# page, the Tuner, and the cockpit (wheel LCD, dial numbers, head unit). Needs
# the real renderer (no --headless). Writes PNGs to user://font_shots/.
#
#   <godot> --path . -s res://tools/font_shots.gd

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://font_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _shot(dir: String, name: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])

func _run() -> void:
	for i in 60:
		await process_frame
	var dir := ProjectSettings.globalize_path("user://font_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	var gs: GameState = game.get("game_state")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.5
	for i in 240:
		await physics_frame
	await _shot(dir, "hud_chase")
	gs.pause()
	await _shot(dir, "pause_menu")
	var menu := _find(game, "PauseMenu")
	if menu != null and menu.has_method("show_controls"):
		menu.call("show_controls")
		await _shot(dir, "pause_controls")
	gs.toggle_pause()
	gs.toggle_tuning()
	await _shot(dir, "tuner")
	gs.toggle_tuning()
	cam.set_view(ChaseCamera.View.COCKPIT)
	for i in 120:
		await physics_frame
	await _shot(dir, "cockpit")
	print("wrote ", dir)
	quit(0)

func _find(n: Node, cls_name: String) -> Node:
	var s: Script = n.get_script()
	if s != null and s.resource_path.get_file().begins_with(cls_name.to_snake_case()):
		return n
	for c in n.get_children():
		var r := _find(c, cls_name)
		if r != null:
			return r
	return null
