extends SceneTree
# Prints the district of road runs 0..11 and the moon path per night 1..30 (headless, no scene).
const Districts := preload("res://scripts/world/districts.gd")
func _initialize() -> void:
	var s := "runs:"
	for r in range(12):
		s += " %d=%s" % [r, Districts.name_of_run(r)]
	print(s)
	for n in range(1, 31):
		var p := NightSky.moon_path(n)
		print("night %2d side=%+d el %.1f->%.1f az %.1f->%.1f phase=%.2f" % [n, int(p.side), p.el0, p.el1, p.az0, p.az1, NightSky.phase_for_night(n)])
	quit(0)
