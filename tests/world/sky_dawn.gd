extends SceneTree

# Sky dawn (sky PR 2, 2026-10-10): the sky stays night until 5 a.m., then the
# clock drives the dawn factor 0 -> 1 by 6 a.m. Boots Game.tscn at 10 p.m. and
# at 5:59 a.m. and checks the director set the global the shader reads.
# Run (real renderer):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/world/sky_dawn.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

var game: Node
var frame := 0
var failures: Array[String] = []

func _initialize() -> void:
	if NightSky.dawn_for_minutes(539.0) != 0.0 or NightSky.dawn_for_minutes(600.0) != 1.0:
		failures.append("dawn must be 0 before 5 a.m. and 1 at 6 a.m.")
	var prev := -1.0
	for m in range(540, 601, 5):
		var d := NightSky.dawn_for_minutes(float(m))
		if d < prev:
			failures.append("dawn not monotonic at minute %d" % m)
		prev = d
	var at := OS.get_environment("SKY_DAWN_CLOCK")
	OS.set_environment("NEON_CLOCK", at if at != "" else "05:59")
	game = Harness.boot(self, 0, 300.0, 7)

func _process(_delta: float) -> bool:
	frame += 1
	if frame < 30:
		return false
	var want := OS.get_environment("SKY_DAWN_WANT")
	if want == "":
		want = "high"
	if want == "high" and NightSky.dawn < 0.9:
		failures.append("5:59 a.m. should be nearly full dawn, got %.2f" % NightSky.dawn)
	if want == "zero" and NightSky.dawn != 0.0:
		failures.append("10 p.m. should have no dawn, got %.2f" % NightSky.dawn)
	for f in failures:
		printerr("FAIL: ", f)
	print("sky_dawn (%s): dawn=%.2f %s" % [want, NightSky.dawn, "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
	return true
