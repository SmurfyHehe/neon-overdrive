extends SceneTree

# Night lighting shots (2026-10-11): drives the real Game.tscn down the same
# seeded road and saves a screenshot at set spots and times of night, so a
# lighting change can be judged before/after from the same frames. Chase
# camera, light traffic, the road from seed 777 (the benchmark's), the
# player on a lane driver at a steady 22 m/s.
#
# Run (real renderer; a window opens for ~25 s per time of night):
#   godot --path . --audio-driver Dummy -s res://tools/night_shots.gd -- --out=before
# saves user://night_shots/before/<hhmm>_<spot>.png for 20:30, 00:00 and
# 04:30 at spots 1-3 (6, 14 and 22 s into the drive, about 130/300/480 m).
# One time of night per run (--time=2030|0000|0430); run them one after the
# other, never in parallel (one Godot at a time on the laptop).
#
# Contact sheet (headless, no window):
#   godot --headless --path . -s res://tools/night_shots.gd -- --sheet=before,after
# writes user://night_shots/sheet_before_after.png: one row per time of
# night and set, left to right spots 1-3; the sets alternate row by row
# (before 20:30, after 20:30, before 00:00, ...).

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TIMES := {"2030": 30.0, "0000": 240.0, "0430": 510.0}
const SPOT_SECS := [6.0, 14.0, 22.0]
const SPEED := 22.0
const WARMUP := 1.5
const SHEET_W := 480

var game: Node
var out_dir := ""
var time_key := ""
var t := 0.0
var spot := 0
var done := false

static func opt(key: String, fallback: String = "") -> String:
	var prefix := "--%s=" % key
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback

func _initialize() -> void:
	var sheet := opt("sheet")
	if sheet != "":
		_sheet(sheet.split(",", false))
		quit(0)
		return
	out_dir = opt("out", "shots")
	time_key = opt("time", "2030")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://night_shots/" + out_dir))
	game = Harness.boot(self, 6, 150.0, 777)

func _process(delta: float) -> bool:
	if done or game == null:
		return false
	t += delta
	if t < WARMUP:
		return false
	var p: PlayerCar = game.get("player")
	if p.driver.is_null():
		game.night_clock.set_time(TIMES[time_key], 1)
		p.driver = Harness.lane_driver(Harness.lane_x(1), 0.7, SPEED)
		Harness.launch_player(p, SPEED)
		t = WARMUP
		return false
	if spot < SPOT_SECS.size() and t - WARMUP >= SPOT_SECS[spot]:
		spot += 1
		var path := "user://night_shots/%s/%s_spot%d.png" % [out_dir, time_key, spot]
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(path)
		print("SHOT %s  z=%.0f m" % [ProjectSettings.globalize_path(path), -RoadFrame.unroll(p.global_position).z])
	if spot >= SPOT_SECS.size():
		done = true
		quit(0)
	return false

func _sheet(sets: PackedStringArray) -> void:
	var cols := SPOT_SECS.size()
	var rows: Array[Array] = []
	for tk in TIMES.keys():
		for s in sets:
			var row := []
			for k in range(1, cols + 1):
				var path := "user://night_shots/%s/%s_spot%d.png" % [s, tk, k]
				var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
				if img == null:
					push_warning("missing " + path)
					continue
				img.resize(SHEET_W, int(float(img.get_height()) * SHEET_W / img.get_width()), Image.INTERPOLATE_LANCZOS)
				row.append(img)
			if not row.is_empty():
				rows.append(row)
	if rows.is_empty():
		push_error("no shots found")
		return
	var cell_h: int = (rows[0][0] as Image).get_height()
	var gap := 4
	var sheet := Image.create((SHEET_W + gap) * cols, (cell_h + gap) * rows.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.06, 0.06, 0.08))
	for r in rows.size():
		for c in (rows[r] as Array).size():
			var img: Image = rows[r][c]
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(c * (SHEET_W + gap), r * (cell_h + gap)))
	var out := "user://night_shots/sheet_%s.png" % "_".join(sets)
	sheet.save_png(out)
	print("SHEET ", ProjectSettings.globalize_path(out))
