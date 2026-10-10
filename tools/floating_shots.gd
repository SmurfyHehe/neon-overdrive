extends SceneTree

# Driver-view screenshots of the roadside (2026-10-09, floating structures):
# boots Game.tscn, teleports the player to the middle of a chunk in each
# district and saves what the driver sees, at eye height looking ahead-right
# and from 6 m up looking ahead, then one contact sheet of all of them.
#
# Env: FLOAT_SHOT_DIR (output folder, required), NEON_ROAD_SEED, NEON_HILLS,
# NEON_CURVES (the road, as in the game), FLOAT_SHOT_CHUNKS (comma list).
# Run (real window):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tools/floating_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Districts := preload("res://scripts/world/districts.gd")
const SETTLE := 24
const LOOKS := [[1.1, -0.55, "eye-right"], [1.1, 0.55, "eye-left"], [6.0, -0.2, "high"]]

var game: Node
var cam: Camera3D
var frame := 0
var wait_until := 60
var chunks: Array = []
var step := 0
var out_dir := ""
var sheets: Array = []

func _initialize() -> void:
	OS.set_environment("NEON_COCKPIT", "0")
	# test mode: never resume (or autosave over) Roy's real run
	OS.set_environment("NEON_TEST", "1")
	out_dir = OS.get_environment("FLOAT_SHOT_DIR")
	var list := OS.get_environment("FLOAT_SHOT_CHUNKS")
	if list == "":
		list = "3,19,35,51,67,83"
	for s in list.split(","):
		chunks.append(int(s))
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = Harness.boot(self, 0, 300.0, 7)
	cam = Camera3D.new()
	cam.fov = 80.0
	cam.far = 1500.0
	root.add_child(cam)

func _process(_delta: float) -> bool:
	frame += 1
	var player: PlayerCar = game.get("player")
	var n_looks: int = LOOKS.size()
	var total: int = chunks.size() * n_looks
	if step >= total:
		_sheet()
		quit(0)
		return true
	var ci: int = chunks[step / n_looks]
	var look: Array = LOOKS[step % n_looks]
	var z := -float(ci) * RoadChunkBuilder.CHUNK_LEN - 25.0
	var x := RoadChunkBuilder.MEDIAN_GAP + RoadChunkBuilder.LANE_W * 1.5
	if frame < wait_until:
		# the car is parked at the station (no physics, hidden) while the pool
		# catches up; the camera stands where the driver's eye would be
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.freeze = true
		player.visible = false
		player.global_transform = RoadFrame.pose(x, 0.6, z, 0.0)
		player.reset_physics_interpolation()
		cam.global_transform = RoadFrame.pose(x, float(look[0]), z, float(look[1]))
		cam.current = true
		return false
	var img := root.get_viewport().get_texture().get_image()
	var name := "%s_chunk%03d_%s" % [Districts.name_at(ci), ci, look[2]]
	img.save_png(out_dir.path_join(name + ".png"))
	sheets.append([name, img])
	print("shot ", name)
	step += 1
	wait_until = frame + SETTLE
	return false

func _sheet() -> void:
	if sheets.is_empty():
		return
	var w: int = sheets[0][1].get_width() / 2
	var h: int = sheets[0][1].get_height() / 2
	var cols := LOOKS.size()
	var rows := ceili(float(sheets.size()) / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in sheets.size():
		var im: Image = sheets[i][1]
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out_dir.path_join("sheet.png"))
	print("sheet: ", sheets.size(), " shots")
