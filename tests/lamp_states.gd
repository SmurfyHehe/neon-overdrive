extends SceneTree

# Flickering and dead street lamps (2026-10-09), headless. Checks
# RoadChunkBuilder.lamp_state():
# - over 20 000 lamps, about LAMP_DEAD_CHANCE are dead and LAMP_FLICKER_CHANCE
#   failing (each within 1.5 points), the rest working
# - the same chunk and slot always give the same state (a rebuilt or revisited
#   chunk shows the same street)
# - failing lamps get spread-out seeds, so they do not flicker in step
# The look itself (dead lamps lose pool and halo, failing ones stutter) was
# checked by eye on the real renderer; headless drops MultiMesh data.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/lamp_states.gd

func _initialize() -> void:
	var failures: Array[String] = []
	var n := 20000
	var dead := 0
	var failing := 0
	var seeds := {}
	for i in n:
		var s := RoadChunkBuilder.lamp_state(i / 8 - 300, i % 8)
		if s.r > 0.75:
			dead += 1
		elif s.r > 0.25:
			failing += 1
			seeds[snappedf(s.g, 0.05)] = true
		if s != RoadChunkBuilder.lamp_state(i / 8 - 300, i % 8):
			failures.append("lamp %d is not deterministic" % i)
			break
	var d := float(dead) / n
	var f := float(failing) / n
	print("dead %.3f, failing %.3f" % [d, f])
	if absf(d - RoadChunkBuilder.LAMP_DEAD_CHANCE) > 0.015:
		failures.append("dead share %.3f, want ~%.2f" % [d, RoadChunkBuilder.LAMP_DEAD_CHANCE])
	if absf(f - RoadChunkBuilder.LAMP_FLICKER_CHANCE) > 0.015:
		failures.append("failing share %.3f, want ~%.2f" % [f, RoadChunkBuilder.LAMP_FLICKER_CHANCE])
	if seeds.size() < 15:
		failures.append("failing lamps share too few seeds (%d)" % seeds.size())
	if failures.is_empty():
		print("lamp_states: PASS")
		quit(0)
	else:
		for x in failures:
			print("FAIL ", x)
		quit(1)
