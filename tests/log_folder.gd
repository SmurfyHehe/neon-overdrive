extends SceneTree

# Open log folder (release-readiness list, 2026-10-08): file logging is on for
# desktop, the log folder resolves to an absolute path inside the user data
# folder, Godot has actually written godot.log there during this run, and the
# pause menu has the button wired to it. Does not press the button (that opens
# Explorer). Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/log_folder.gd

const LogFolder := preload("res://scripts/log_folder.gd")

var failures: Array[String] = []
var state: GameState
var menu: PauseMenu

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	_check(LogFolder.logging_enabled(), "file logging should be on for desktop")
	var dir := LogFolder.log_dir()
	_check(dir.is_absolute_path(), "log folder should be an absolute path, got '%s'" % dir)
	_check(dir.begins_with(OS.get_user_data_dir()), "log folder should sit in the user data folder, got '%s'" % dir)
	_check(DirAccess.dir_exists_absolute(dir), "log folder should exist: '%s'" % dir)
	_check(FileAccess.file_exists(LogFolder.log_file()), "godot.log should exist: '%s'" % LogFolder.log_file())

	# The root only enters the tree after _initialize, so build the menu here
	# and inspect it on the first frame, once _ready has run.
	state = GameState.new()
	menu = PauseMenu.new(state)
	root.add_child(state)
	root.add_child(menu)

func _process(_delta: float) -> bool:
	var found := false
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text == "Open log folder":
			found = true
			var wired := false
			for c in (b as Button).pressed.get_connections():
				var cb: Callable = c["callable"]
				if cb.get_method() == "open":
					wired = true
			_check(wired, "Open log folder button should call LogFolder.open")
	_check(found, "pause menu should have an Open log folder button")

	print("log_folder: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return true
