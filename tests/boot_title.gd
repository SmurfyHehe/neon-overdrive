extends SceneTree

# Title screen and loading card test (2026-10-09), headless and silent:
# - the project opens Boot.tscn, which shows the game name and waits
# - nothing loads until Enter; then the loading card replaces the title and
#   Game.tscn loads in the background
# - first launch: remembered once in the settings file, the other sections stay
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/boot_title.gd

const TIMEOUT_TICKS := 1200

var boot: Boot
var tick := 0
var failures: Array[String] = []
var started := false
var loaded := false

func _initialize() -> void:
	_check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://Boot.tscn", "the project opens the title screen")
	AudioSettings.path = "user://test_boot_title.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.path))
	_check(Boot.first_launch_pending(), "a fresh settings file means first launch")
	var cfg := ConfigFile.new()
	cfg.set_value("view", "cockpit_fov", 70.0)
	cfg.save(AudioSettings.path)
	_check(Boot.mark_launched(), "first launch can be marked")
	_check(not Boot.first_launch_pending(), "and is not pending again")
	cfg.load(AudioSettings.path)
	_check(is_equal_approx(float(cfg.get_value("view", "cockpit_fov", 0.0)), 70.0), "marking keeps the other sections")
	_check(not Boot.apply_first_launch_window(), "headless never touches the window")
	_check(not Boot.skip_title(), "the title is not skipped by default")
	boot = load("res://Boot.tscn").instantiate()
	boot.change_scene_on_load = false
	boot.start_requested.connect(func() -> void: started = true)
	boot.game_loaded.connect(func() -> void: loaded = true)
	root.add_child(boot)

func _process(_delta: float) -> bool:
	tick += 1
	if tick == 5:
		_check(boot.title_page.visible and not boot.loading_page.visible, "the title shows first")
		_check(_has_text(boot.title_page, "BOOST SIMCADE"), "with the game's name")
		_check(not started and not boot.loading, "nothing loads before a key")
	if tick == 10:
		_press(KEY_ENTER)
	if tick == 12:
		_check(started and boot.loading_page.visible and not boot.title_page.visible, "Enter swaps the title for the loading card")
	if loaded:
		_check(is_equal_approx(boot.bar.value, 1.0), "the bar is full when the game is loaded")
		return _end()
	if tick > TIMEOUT_TICKS:
		failures.append("Game.tscn never finished loading")
		return _end()
	return false

func _press(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	boot._unhandled_input(e)

func _has_text(n: Node, s: String) -> bool:
	if n is Label and (n as Label).text == s:
		return true
	for c in n.get_children():
		if _has_text(c, s):
			return true
	return false

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _end() -> bool:
	for f in failures:
		print("FAIL: ", f)
	print("boot_title: ", "PASS" if failures.is_empty() else "FAIL")
	quit(1 if failures.size() > 0 else 0)
	return true
