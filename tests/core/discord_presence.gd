extends SceneTree

# Discord Rich Presence (2026-10-10): on by default, the off switch round-trips
# in the shared settings file, the activity carries only night / area / car /
# station / start time and the logo, every Districts kind has a name, the
# module stays dormant in tests and with no app id, and opening a Discord pipe
# that does not exist is a quiet null (Discord closed). Exit code 1 on failure.
# Run: Godot --headless --path . -s res://tests/core/discord_presence.gd

const DP := preload("res://scripts/core/discord_presence.gd")
const Districts := preload("res://scripts/world/districts.gd")
var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	AudioSettings.path = "user://discord_presence_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	DP.load_settings()
	_check(DP.enabled, "should be on by default")
	DP.set_enabled(false)
	AudioSettings.set_volume("Music", 0.5)
	AudioSettings.save_settings()
	_check(DP.save_settings(), "save failed")
	DP.set_enabled(true)
	DP.load_settings()
	_check(not DP.enabled, "off should round-trip")
	AudioSettings.volumes["Music"] = 1.0
	AudioSettings.load_settings()
	_check(is_equal_approx(AudioSettings.volumes["Music"], 0.5), "saving must keep the audio section")
	DP.set_enabled(true)
	DP.save_settings()
	DP.set_enabled(false)
	DP.load_settings()
	_check(DP.enabled, "on should round-trip")

	var a: Dictionary = DP.build_activity(3, "The Strip", "Kobo", "Synthwave", 1000)
	_check(a.details == "Night 3 · The Strip", "details: %s" % a.details)
	_check(a.state == "Kobo · Synthwave", "state: %s" % a.state)
	_check(a.timestamps.start == 1000 and a.assets.large_image == DP.LOGO_KEY, "start time and logo")
	_check(a.keys().size() == 4 and a.assets.keys().size() == 1, "only details, state, timestamps, assets")
	_check(DP.build_activity(1, "Downtown", "Tarp", "", 0).state == "Tarp", "radio off shows the car only")
	_check(DP.build_activity(0, "", "Tarp", "", 0).details == "Night 1", "night is at least 1, no empty area")
	for kind in ["downtown", "residential", "strip", "industrial"]:
		_check(DP.AREA_NAMES.has(kind), "no area name for " + kind)
	for e in Districts.PICK:
		_check(DP.AREA_NAMES.has(e[0]), "Districts kind without a name: " + String(e[0]))
	_check(DP.area_name("old_town") == "Old Town", "unknown kind falls back to a readable name")

	_check(not DP.wanted(), "must be dormant under tests / headless / empty app id")
	var pipe := FileAccess.open("\\\\?\\pipe\\neon-no-such-pipe-for-test", FileAccess.READ_WRITE)
	_check(pipe == null, "a missing pipe should open as null")

	DirAccess.remove_absolute(AudioSettings.path)
	print("discord_presence: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
