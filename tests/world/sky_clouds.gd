extends SceneTree

# Sky clouds (sky PR 3, 2026-10-10): the night number picks the cloud type, so
# a night always has the same sky, and over a month all four types turn up.
# Pure logic, no window. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/sky_clouds.gd

func _initialize() -> void:
	var seen := {}
	var fails: Array[String] = []
	for n in range(1, 61):
		var t := NightSky.cloud_type(n)
		if t != NightSky.cloud_type(n):
			fails.append("night %d is not repeatable" % n)
		seen[t] = int(seen.get(t, 0)) + 1
	for t in NightSky.CLOUD_TYPES:
		if int(seen.get(t, 0)) < 5:
			fails.append("cloud type %s turned up %d times in 60 nights" % [t, int(seen.get(t, 0))])
	if NightSky.CLOUD_COVER.clear != 0.0:
		fails.append("a clear night must have no cloud")
	var last := -1.0
	for t in NightSky.CLOUD_TYPES:
		if float(NightSky.CLOUD_COVER[t]) <= last and t != "clear":
			fails.append("cover must grow clear < scattered < broken < overcast")
		last = float(NightSky.CLOUD_COVER[t])
	if NightSky.cloud_offset_for_minutes(600.0) <= NightSky.cloud_offset_for_minutes(0.0):
		fails.append("clouds must drift through the night")
	for f in fails:
		printerr("FAIL: ", f)
	print("sky_clouds: %s %s" % [seen, "PASS" if fails.is_empty() else "FAIL"])
	quit(0 if fails.is_empty() else 1)
