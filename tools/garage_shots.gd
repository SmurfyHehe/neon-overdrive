extends SceneTree

# Screenshots of the garage for PR reviews (not a test; nothing is asserted).
# Boots Game.tscn onto the road, pulls into the garage (GameState.open_garage)
# and saves a PNG of it to user://garage_shots/. Needs the real renderer (a
# window opens). NEON_TEST=1 keeps the real settings and saves untouched:
#   set NEON_TEST=1 && godot --path . -s res://tools/garage_shots.gd -- 1280x720
# NEON_CAR=p3_tuner parks another car.

var tick := 0
var out_dir := "user://garage_shots"
var done := {}

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_GARAGE", "1")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for a in OS.get_cmdline_user_args():
		if "x" in a:
			var wh := a.split("x")
			root.size = Vector2i(int(wh[0]), int(wh[1]))
	change_scene_to_file("res://Game.tscn")

func _shot(name: String) -> void:
	var p := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot: ", ProjectSettings.globalize_path(p))

func _once(name: String, at: int) -> bool:
	if tick >= at and not done.has(name):
		done[name] = true
		return true
	return false

func _process(_delta: float) -> bool:
	var game := current_scene
	if game == null or game.get("game_state") == null:
		return false
	tick += 1
	var gs: GameState = game.game_state
	if _once("drive", 30) and gs.state == GameState.State.TITLE:
		gs.start_drive()
	# the first drive of a session goes through the dawn card into the garage
	if _once("dawn", 120) and gs.state == GameState.State.DAWN:
		_shot("0_dawn_card")
		gs.dawn_continue()
	if _once("garage", 150) and gs.state == GameState.State.PLAYING:
		if not gs.open_garage():
			print("garage refused (state %d)" % gs.state)
	if _once("shot", 220):
		print("state at shot: %d" % gs.state)
		_shot("1_garage")
	return tick >= 230
