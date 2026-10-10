extends SceneTree

# Judges the HUD gear readout against the speed readout in the chase view with
# the real renderer (no --headless): drives until the gear reads D5 (or 25 s),
# saves one screenshot of the game as it looks, one with a black backdrop under
# the HUD, and measures the vertical extent of the glyph ink of the gear and
# speed labels on the black one. Prints the ink centres and their difference.
# Needs NEON_TEST=1 so it does not touch Roy's save.
#
#   NEON_TEST=1 <godot> --path . --resolution 1280x720 -s res://tools/hud_gear_shots.gd
#   HUD_SHOT_DIR=<dir> sets where the PNGs go (default user://hud_gear_shots).

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://hud_gear_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _ink(img: Image, rect: Rect2) -> Vector2:
	# first and last image row inside rect with a pixel brighter than 0.35
	var top := -1
	var bot := -1
	var x0 := int(rect.position.x)
	var x1 := mini(int(rect.end.x), img.get_width())
	for y in range(maxi(int(rect.position.y), 0), mini(int(rect.end.y), img.get_height())):
		for x in range(x0, x1):
			if img.get_pixel(x, y).v > 0.35:
				if top < 0:
					top = y
				bot = y
				break
	return Vector2(top, bot)

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	cam.shake_enabled = false
	var hud: Hud
	for c in game.get_children():
		if c is Hud:
			hud = c
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	# Measured at a standstill and then at speed, with the unit and the A/M tag
	# made invisible (not hidden: hidden labels leave the layout) so only the
	# gear and speed digits are ink.
	var dir := OS.get_environment("HUD_SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://hud_gear_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var layer := CanvasLayer.new()
	layer.layer = -10
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	await _measure(hud, dir, "standstill", layer)
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 1.0
		c.brake_input = 0.0
		c.steering_input = 0.0
	var t := 0
	while hud.lbl_gear.text != "5" and t < 25 * 60:
		await physics_frame
		t += 1
	await _measure(hud, dir, "gear" + hud.lbl_gear.text, layer)
	quit(0)

func _measure(hud: Hud, dir: String, tag: String, layer: CanvasLayer) -> void:
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_scene.png" % [dir, tag])
	root.add_child(layer)
	hud.lbl_mode.modulate.a = 0.0
	hud.lbl_unit.modulate.a = 0.0
	for i in 6:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s_black.png" % [dir, tag])
	hud.lbl_mode.modulate.a = 1.0
	hud.lbl_unit.modulate.a = 1.0
	root.remove_child(layer)
	var gr := hud.lbl_gear.get_global_rect()
	var sr := hud.lbl_speed.get_global_rect()
	var gi := _ink(img, gr)
	var si := _ink(img, sr)
	print("[%s] gear '%s' speed '%s': label rects y %.1f..%.1f / %.1f..%.1f" % [tag, hud.lbl_gear.text, hud.lbl_speed.text, gr.position.y, gr.end.y, sr.position.y, sr.end.y])
	print("[%s]   ink rows gear %d..%d (centre %.1f), speed %d..%d (centre %.1f): gear - speed = %.1f px" % [tag, gi.x, gi.y, (gi.x + gi.y) * 0.5, si.x, si.y, (si.x + si.y) * 0.5, (gi.x + gi.y) * 0.5 - (si.x + si.y) * 0.5])
