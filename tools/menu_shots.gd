extends SceneTree

# Screenshots of the menus for PR reviews (not a test; nothing is asserted).
# Boots Game.tscn, then walks the named states and saves a PNG of each to
# user://menu_shots/. Needs the real renderer (a window opens). NEON_TEST=1
# keeps the real settings file untouched:
#   set NEON_TEST=1 && Godot_v4.7.2-stable_win64_console.exe --path . -s res://tools/menu_shots.gd -- title pause
#
# States: title, title_settings, drive, pause, pause_stall, pause_focus,
#         confirm, refusal, settings_sound, settings_game.
# "title" and "title_settings" set NEON_TITLE=1; the rest start on the road.

var tick := 0
var shots: Array = []   # [tick, name]
var out_dir := "user://menu_shots"

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "6")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var what := OS.get_cmdline_user_args()
	if "title" in what or "title_settings" in what:
		OS.set_environment("NEON_TITLE", "1")
	change_scene_to_file("res://Game.tscn")
	var t := 150
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

## Puts the game in the state a shot wants.
func _prepare(game: Node, what: String) -> void:
	var gs: GameState = game.game_state
	var menu := _find(game, "PauseMenu") as PauseMenu
	_reset(game)
	match what:
		"title":
			pass
		"title_settings":
			(_find(game, "TitleScreen") as TitleScreen)._open_settings()
		"drive":
			if gs.state == GameState.State.TITLE:
				gs.start_drive()
		"pause":
			_to_road(gs)
			gs.pause()
		"pause_stall":
			_to_road(gs)
			gs.pause(GameState.REASON_STALL)
		"pause_focus":
			_to_road(gs)
			gs.pause(GameState.REASON_FOCUS)
		"confirm":
			_to_road(gs)
			gs.pause()
			menu.restart_button.pressed.emit()
		"refusal":
			_to_road(gs)
			gs.pause_refused.emit()
		"settings_sound":
			_to_road(gs)
			gs.pause()
			menu.show_settings("Sound")
		"settings_game":
			_to_road(gs)
			gs.pause()
			menu.show_settings("Game")

func _to_road(gs: GameState) -> void:
	if gs.state == GameState.State.TITLE:
		gs.start_drive()

## Closes whatever the previous shot opened.
func _reset(game: Node) -> void:
	var menu := _find(game, "PauseMenu") as PauseMenu
	if menu != null and menu.settings.visible:
		menu.settings.close()
	if menu != null and menu.confirm.is_open():
		menu.confirm.no_button.pressed.emit()
	var gs: GameState = game.game_state
	if gs.state == GameState.State.PAUSED:
		gs.resume()

## First child of game whose script has this class_name.
func _find(game: Node, cls: String) -> Node:
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null
