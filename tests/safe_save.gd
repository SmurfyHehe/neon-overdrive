extends SceneTree

# Crash-safe saving (release readiness, 2026-10-08): SafeSave writes through a
# .tmp file and keeps the previous save as .bak, and the loaders fall back to
# the .bak when the main file is missing or damaged.
# - first save: no .bak, no .tmp left behind
# - second save: .bak holds the first save, main holds the second
# - damaged main (half-written JSON / config): read_json / load_config return the .bak
# - crash between the two renames (main gone, .bak there): still loads the .bak
# - settings.cfg end to end: AudioSettings saves, main is truncated, the volume survives
# - tune slots: a damaged tune_slots.json loads the slots from the .bak
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/safe_save.gd

const SafeSave := preload("res://scripts/safe_save.gd")
const DIR := "user://safe_save_test"

var fails := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_json_round_trip()
	_config_round_trip()
	_audio_settings_survive_truncation()
	_tune_slots_fall_back()
	print("safe_save: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)

func _json_round_trip() -> void:
	var p := DIR.path_join("data.json")
	_clean(p)
	_check(SafeSave.write_json(p, {"n": 1}), "first write_json failed")
	_check(not FileAccess.file_exists(p + ".tmp"), "a .tmp was left behind")
	_check(not FileAccess.file_exists(p + ".bak"), "first save made a .bak with nothing to back up")
	_check(SafeSave.write_json(p, {"n": 2}), "second write_json failed")
	_check(_n(SafeSave.read_json(p)) == 2, "main should hold the newest save")
	_check(_n(SafeSave.read_json(p + ".bak")) == 1, ".bak should hold the previous save")
	_write_raw(p, "{\"n\": 3, \"half-writ")  # a crash halfway through a plain write
	_check(_n(SafeSave.read_json(p)) == 1, "damaged main should load the .bak (got %s)" % str(SafeSave.read_json(p)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))  # crash between the renames
	_check(_n(SafeSave.read_json(p)) == 1, "missing main should load the .bak")
	_check(SafeSave.write_json(p, {"n": 4}) and _n(SafeSave.read_json(p)) == 4, "a save after the crash should land normally")
	_clean(p)
	_check(SafeSave.read_json(p) == null, "no file and no .bak should read as null")

func _config_round_trip() -> void:
	var p := DIR.path_join("settings.cfg")
	_clean(p)
	for v in [0.25, 0.75]:
		var cfg := ConfigFile.new()
		cfg.set_value("audio", "master", v)
		_check(SafeSave.save_config(cfg, p), "save_config failed")
	_write_raw(p, "[audio]\nmaster=\"unterminated")
	var back := ConfigFile.new()
	_check(SafeSave.load_config(back, p) == OK, "damaged config should load the .bak")
	_check(is_equal_approx(float(back.get_value("audio", "master", -1.0)), 0.25), "the .bak should hold the previous value (got %s)" % str(back.get_value("audio", "master")))
	_clean(p)
	_check(SafeSave.load_config(ConfigFile.new(), p) != OK, "no file and no .bak should fail to load")

func _audio_settings_survive_truncation() -> void:
	var old_path := AudioSettings.path
	AudioSettings.path = DIR.path_join("audio.cfg")
	_clean(AudioSettings.path)
	AudioSettings.set_volume("Music", 0.4)
	AudioSettings.save_settings()
	AudioSettings.set_volume("Music", 0.6)
	AudioSettings.save_settings()
	_write_raw(AudioSettings.path, "")  # the old failure: a crash left an empty file
	AudioSettings.volumes["Music"] = 1.0
	AudioSettings.load_settings()
	_check(is_equal_approx(AudioSettings.volumes["Music"], 0.4), "Music volume should come back from the .bak (got %.2f)" % AudioSettings.volumes["Music"])
	_clean(AudioSettings.path)
	AudioSettings.path = old_path
	AudioSettings.volumes["Music"] = 1.0

func _tune_slots_fall_back() -> void:
	var p := DIR.path_join("slots.json")
	_clean(p)
	_write_raw(p + ".bak", JSON.stringify({"version": 1, "slots": {"Street": {"engine.max_rpm": 7000.0}}}))
	_write_raw(p, "{\"version\": 1, \"slo")
	var slots := TuneSlots.new(p)
	_check(slots.names().has("Street"), "a damaged slot file should load the slots in the .bak (got %s)" % str(slots.names()))
	_clean(p)
	var bad := p.get_basename() + ".bad.json"
	if FileAccess.file_exists(bad):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))

func _n(v: Variant) -> int:
	return int(v.get("n", -1)) if v is Dictionary else -1

func _write_raw(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _clean(p: String) -> void:
	for x in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(x):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(x))

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: ", msg)
