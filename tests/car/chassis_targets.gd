extends SceneTree

# Chassis targets (Phase A/B, 2026-10-05): the default coupe on the hidden test
# track (TuneTrack) must stay inside the feel targets from
# docs/research/build-phases.md, so a later tweak can't quietly break the car:
#   top speed 235-250 km/h, 0-100 4.8-6.4 s, 100-0 36-46 m, peak lateral g 1.0-1.5
# Headless, silent, about a minute. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/chassis_targets.gd

func _initialize() -> void:
	_run()

func _run() -> void:
	var track := TuneTrack.new()
	root.add_child(track)
	await process_frame
	var res: Array = await track.evaluate([CarSpec.coupe_default()])
	var m: Dictionary = res[0]
	print("default coupe: top %.1f km/h, 0-100 %.2f s, 100-0 %.1f m, peak %.2f g" % [m.top_speed_kmh, m.t_0_100, m.brake_dist_100, m.peak_lat_g])
	var fails: Array[String] = []
	if not (m.top_speed_kmh >= 235.0 and m.top_speed_kmh <= 250.0):
		fails.append("top speed %.1f outside 235-250" % m.top_speed_kmh)
	if not (m.t_0_100 >= 4.8 and m.t_0_100 <= 6.4):
		fails.append("0-100 %.2f outside 4.8-6.4" % m.t_0_100)
	if not (m.brake_dist_100 >= 36.0 and m.brake_dist_100 <= 46.0):
		fails.append("100-0 %.1f outside 36-46" % m.brake_dist_100)
	if not (m.peak_lat_g >= 1.0 and m.peak_lat_g <= 1.5):
		fails.append("peak lateral g %.2f outside 1.0-1.5" % m.peak_lat_g)
	for f in fails:
		printerr("FAIL: ", f)
	print("chassis_targets: ", "PASS" if fails.is_empty() else "FAIL")
	quit(0 if fails.is_empty() else 1)
