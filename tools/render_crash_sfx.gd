extends SceneTree

# Renders every crash and scrape take (CrashSfx recipes) into assets/sfx/crash
# as 16-bit mono WAVs, plus recipe_hash.txt naming the recipe version they came
# from (tests/audio/crash_variety.gd fails when it is stale). Run after editing
# scripts/audio/crash_sfx.gd, then let the editor import the files (or run
# tools/refresh-godot-cache.ps1). Takes about a minute.
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/render_crash_sfx.gd

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var dir := ProjectSettings.globalize_path(CrashSfx.DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var layers: Array[String] = []
	for pname in CrashAudio.POOLS:
		for k in CrashAudio.VARIANTS:
			layers.append("%s%d" % [pname, k])
	for kind in CrashAudio.LOOPS:
		for k in CrashAudio.LOOP_TAKES:
			layers.append("loop_%s%d" % [kind, k])
	var bytes := 0
	for layer in layers:
		var wav := CrashSfx.make(layer)
		var err := wav.save_to_wav(dir.path_join(layer + ".wav"))
		if err != OK:
			push_error("could not write %s: %d" % [layer, err])
			quit(1)
			return
		bytes += wav.data.size()
	var f := FileAccess.open(dir.path_join("recipe_hash.txt"), FileAccess.WRITE)
	f.store_string(CrashSfx.recipe_hash() + "\n")
	f.close()
	print("rendered %d takes (%.1f MB) in %.1f s to %s" % [layers.size(), bytes / 1048576.0, (Time.get_ticks_msec() - t0) / 1000.0, dir])
	quit(0)
