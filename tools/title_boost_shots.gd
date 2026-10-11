extends SceneTree

# Screenshots of the title's turbo build-up (not a test; nothing is asserted):
# boost 0, 0.5 and 1.0 while W is held, and 0.2 s after letting go at full
# boost (blow-off puff, release shake). Needs the real renderer:
#   set NEON_TEST=1 && godot --path . -s res://tools/title_boost_shots.gd
# "-- 1280x720" sets the window size. Writes to docs/title-kerbside/.

const OUT := "res://docs/title-kerbside/"
var t := 0.0
var done := {}
var title: TitleScreen
var _release_t := -1.0

func _initialize() -> void:
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_SPLASH", "0")
	OS.set_environment("NEON_WELCOME", "0")
	TitleScreen.splash_done = true
	for a in OS.get_cmdline_user_args():
		if "x" in a:
			var wh := a.split("x")
			root.size = Vector2i(int(wh[0]), int(wh[1]))
	change_scene_to_file("res://Game.tscn")

func _shot(name: String) -> void:
	var p := ProjectSettings.globalize_path(OUT + name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot: ", p, "  boost %.2f spin %.1f" % [title.menu_boost, title.menu_spin])

func _process(delta: float) -> bool:
	var game := current_scene
	if game == null or game.get("game_state") == null:
		return false
	if title == null:
		for c in game.get_children():
			if c is TitleScreen:
				title = c
		return false
	if not title.visible:
		return false
	t += delta
	if t < 2.0:
		return false
	var held := t - 2.0   # seconds W has been held, from t = 2
	if not done.has("hold"):
		done["hold"] = true
		_shot("8_boost_0_00")
		title._spin_held = true
	if held >= 3.0 and not done.has("half"):
		done["half"] = true
		_shot("9_boost_0_50")
	if held >= 6.0 and not done.has("full"):
		done["full"] = true
		_shot("10_boost_1_00")
		title._spin_held = false
		_release_t = 0.0
	if _release_t >= 0.0:
		_release_t += delta
		if _release_t >= 0.2 and not done.has("after"):
			done["after"] = true
			_shot("11_release_0_2s")
			quit()
	return false
