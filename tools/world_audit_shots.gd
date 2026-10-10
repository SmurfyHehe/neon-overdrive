extends SceneTree

# World audit shots (2026-10-10, signs and floating structures): boots
# Game.tscn, parks the player at the middle of every Nth chunk along a long
# drive and saves what a driver would see: eye height looking ahead-right and
# ahead-left (the shop signs), a raised look ahead (roof props, billboards) and
# a sky look from 3 m up pitched 20 deg upward (anything hanging in the air).
# One contact sheet per run.
#
# Env: AUDIT_SHOT_DIR (output folder, required), NEON_SEED (building rolls),
# NEON_ROAD_SEED, NEON_HILLS, NEON_CURVES (the road, as in the game),
# AUDIT_CHUNKS (comma list) or AUDIT_FIRST/AUDIT_STEP/AUDIT_COUNT.
# Run (real window):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tools/world_audit_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Districts := preload("res://scripts/world/districts.gd")
const SETTLE := 30
# [cam height, yaw, pitch (rad, + looks up), name]
const LOOKS := [
	[1.1, -0.5, 0.0, "eye-right"],
	[1.1, 0.5, 0.0, "eye-left"],
	[5.0, -0.15, -0.1, "high"],
	[3.0, 0.0, 0.35, "sky"],
]

var game: Node
var cam: Camera3D
var frame := 0
var wait_until := 80
var chunks: Array = []
var step := 0
var out_dir := ""
var sheets: Array = []

func _initialize() -> void:
	OS.set_environment("NEON_COCKPIT", "0")
	# test mode: never resume (or write) Roy's real saved run
	OS.set_environment("NEON_TEST", "1")
	out_dir = OS.get_environment("AUDIT_SHOT_DIR")
	var list := OS.get_environment("AUDIT_CHUNKS")
	if list != "":
		for s in list.split(","):
			chunks.append(int(s))
	else:
		var first := 3
		var stepn := 9
		var count := 20
		if OS.get_environment("AUDIT_FIRST").is_valid_int():
			first = int(OS.get_environment("AUDIT_FIRST"))
		if OS.get_environment("AUDIT_STEP").is_valid_int():
			stepn = int(OS.get_environment("AUDIT_STEP"))
		if OS.get_environment("AUDIT_COUNT").is_valid_int():
			count = int(OS.get_environment("AUDIT_COUNT"))
		for k in count:
			chunks.append(first + k * stepn)
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = Harness.boot(self, 0, 300.0, 7)
	for c in game.get_children():
		if c is CanvasLayer:
			c.visible = false  # no HUD over the shots
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
	# road-space z is relative to the floating origin (shifts by whole chunks past 1 km)
	var z := -float(ci - RoadFrame.origin_index) * RoadChunkBuilder.CHUNK_LEN - 25.0
	var x := RoadChunkBuilder.MEDIAN_GAP + RoadChunkBuilder.LANE_W * 1.5
	if frame < wait_until:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.freeze = true
		player.visible = false
		player.global_transform = RoadFrame.pose(x, 0.6, z, 0.0)
		player.reset_physics_interpolation()
		var t := RoadFrame.pose(x, float(look[0]), z, float(look[1]))
		t.basis = t.basis * Basis(Vector3.RIGHT, float(look[2]))
		cam.global_transform = t
		cam.current = true
		return false
	var img := root.get_viewport().get_texture().get_image()
	var name := "%s_chunk%03d_%s" % [Districts.name_at(ci), ci, look[3]]
	img.save_png(out_dir.path_join(name + ".png"))
	sheets.append([name, img])
	print("shot ", name)
	step += 1
	wait_until = frame + SETTLE
	return false

func _sheet() -> void:
	if sheets.is_empty():
		return
	var w: int = sheets[0][1].get_width() / 3
	var h: int = sheets[0][1].get_height() / 3
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
