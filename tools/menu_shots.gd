extends SceneTree

# Screenshots of the menus for PR reviews (not a test; nothing is asserted).
# Boots Game.tscn, then walks a few states and saves a PNG of each to
# user://menu_shots/. Run with NEON_TEST=1 so the real settings file is untouched:
#   set NEON_TEST=1 && Godot_v4.7.2-stable_win64_console.exe --path . -s res://tools/menu_shots.gd -- pause

var tick := 0
var shots: Array = []   # [tick, name, Callable]
var out_dir := "user://menu_shots"

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "6")
	DirAccess.make_dir_recursive_absolute(out_dir)
	change_scene_to_file("res://Game.tscn")
	var what := OS.get_cmdline_user_args()
	if "title" in what:
		OS.set_environment("NEON_TITLE", "1")
	var t := 120
	for w in what:
		shots.append([t, w])
		t += 150

func _process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("game_state") == null:
		return false
	for s in shots:
		if tick == s[0] - 60:
			_prepare(game, s[1])
		elif tick == s[0]:
			var img := root.get_texture().get_image()
			var p: String = out_dir.path_join("%s.png" % s[1])
			img.save_png(p)
			print("shot: ", ProjectSettings.globalize_path(p))
	if not shots.is_empty() and tick > shots[-1][0] + 5:
		quit()
	return false

## Puts the game in the state a shot wants. Unknown names just shoot the game.
func _prepare(game: Node, what: String) -> void:
	var gs: GameState = game.game_state
	match what:
		"pause":
			gs.pause()
		"play":
			if gs.state == GameState.State.PAUSED:
				gs.resume()
		"title", "title_quit":
			if what == "title_quit":
				_find(game, "TitleScreen").confirm.ask("Quit to desktop?", "Quit", func() -> void: pass)
		"drive":
			gs.start_drive()
		"title_settings":
			_find(game, "TitleScreen")._open_settings()
		"confirm":
			gs.pause()
			_find(game, "PauseMenu").restart_button.pressed.emit()
		"controls":
			gs.pause()
			_find(game, "PauseMenu").show_controls()
		"display":
			gs.pause()
			_find(game, "PauseMenu").show_display()
		_:
			if game.has_method("menu_shot"):
				game.menu_shot(what)

## First child of game whose script has this class_name.
func _find(game: Node, cls: String) -> Node:
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null
