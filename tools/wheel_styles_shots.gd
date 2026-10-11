extends SceneTree

# Renders every steering wheel shape from the driver's eye (W1, 2026-10-11)
# for judging by eye: the coupe with each of the 9 shapes, then the Bug (the
# beater) with its default wheel, as one contact sheet, 3 columns, left to
# right and top to bottom in WheelStyles.SHAPE_IDS order, the Bug last.
# Needs the real renderer (no --headless). Writes PNGs to user://wheel_shots/
# (the sheet is sheet.png, one crop per wheel beside it).
#
#   <godot> --path . -s res://tools/wheel_styles_shots.gd
# WHEEL_GRIP=<id> and WHEEL_STITCH=<id> apply a grip and stitching to every shape.

const WheelStyles := preload("res://scripts/view/wheel_styles.gd")
const CELL := Vector2i(560, 330)
const COLS := 3

var game: Node
var crops: Array[Image] = []

func _initialize() -> void:
	AudioSettings.path = "user://wheel_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CABIN_MODS", "trinket=none")
	OS.set_environment("NEON_CAR", "p1_coupe")
	_run.call_deferred()

func _boot() -> void:
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	for i in 60:
		await physics_frame

## The lower middle of the screen, where the wheel is, scaled to a cell.
func _snap(label: String) -> void:
	for i in 8:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var rect := Rect2i(int(w * 0.18), int(h * 0.38), int(w * 0.64), int(h * 0.62))
	var crop := img.get_region(rect)
	crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	crops.append(crop)
	var dir := ProjectSettings.globalize_path("user://wheel_shots")
	crop.save_png("%s/%02d_%s.png" % [dir, crops.size(), label])

func _run() -> void:
	var dir := ProjectSettings.globalize_path("user://wheel_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	await _boot()
	var frame: CockpitFrame = (game.get("camera") as ChaseCamera).frame
	var kind := PlayerCar.chassis_kind()
	var grip := OS.get_environment("WHEEL_GRIP")
	var stitch := OS.get_environment("WHEEL_STITCH")
	for id in WheelStyles.SHAPE_IDS:
		CabinMods.set_wheel_shape(kind, id)
		CabinMods.set_wheel_grip(kind, grip)
		CabinMods.set_wheel_stitch(kind, stitch)
		for i in 4:
			await process_frame   # the cockpit rebuilds the wheel on its next frame
		print("%s: %d triangles, rim r %.1f cm, dish %.1f cm" % [id, frame.wheel.triangle_count(), frame.wheel.radius() * 100.0, frame.wheel.dish() * 100.0])
		await _snap(id)
	# the Bug, its own wheel
	game.queue_free()
	await process_frame
	OS.set_environment("NEON_CAR", "p0_beater")
	CabinMods.set_wheel_shape("p1_coupe", "")
	CabinMods.set_wheel_grip("p1_coupe", "")
	CabinMods.set_wheel_stitch("p1_coupe", "")
	await _boot()
	await _snap("bug_default")
	# the sheet
	var rows := ceili(float(crops.size()) / float(COLS))
	var sheet := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.07, 0.12))
	for i in crops.size():
		sheet.blit_rect(crops[i], Rect2i(Vector2i.ZERO, CELL), Vector2i((i % COLS) * CELL.x, (i / COLS) * CELL.y))
	sheet.save_png("%s/sheet.png" % dir)
	print("wrote %s/sheet.png (%d wheels)" % [dir, crops.size()])
	quit(0)
