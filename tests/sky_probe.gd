extends SceneTree

# Sky probe (2026-10-07): the sky gradient shows and the moon renders.
# Boots Game.tscn and measures the sky in three screen regions (top, mid, the
# horizon gap down the road), region-averaged because the film grain is
# per-pixel noise. Then steps the moon through its phases and measures the
# moon's lit area.
#
# Asserts (exit code 1 on failure):
# - the sky is a gradient, not flat fog: horizon at least 2x brighter than top
# - turning fog_sky_affect back to 1.0 (the old setup) flattens it (the probe
#   that found the bug, kept as a control)
# - the moon is on screen at the chase camera, brighter than the sky round it
# - its lit area grows new -> quarter -> full; a new moon is ~invisible
# Saves frames and moon close-ups to SKY_SHOT_DIR if set.
# Run (real renderer; a window opens briefly):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/sky_probe.gd

const Harness := preload("res://tests/traffic_harness.gd")
const PHASES := [0.0, 0.12, 0.25, 0.38, 0.5]
const SETTLE := 6  # frames per change

var game: Node
var env: Environment
var cam: Camera3D
var frame := 0
var failures: Array[String] = []
var lit_px := {}
var step := 0
var wait_until := 90

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 7)

func _process(_delta: float) -> bool:
	frame += 1
	if frame < wait_until:
		return false
	if env == null:
		for n in game.get_children():
			if n is WorldEnvironment:
				env = n.environment
		cam = root.get_viewport().get_camera_3d()
		NightSky.set_phase(env.sky, 0.5)
		wait_until = frame + SETTLE
		return false
	match step:
		0:
			var r := _regions("moon_sky")
			if r.horizon.length() < 2.0 * r.top.length():
				failures.append("sky looks flat: top %s horizon %s" % [r.top, r.horizon])
			env.fog_sky_affect = 1.0
			env.fog_aerial_perspective = 0.0
		1:
			var r := _regions("old_fog")
			if r.horizon.length() >= 1.5 * r.top.length():
				failures.append("control: old fog setup no longer flattens the sky (%s / %s)" % [r.top, r.horizon])
			env.fog_sky_affect = 0.0
			env.fog_aerial_perspective = 1.0
		_:
			var i := step - 2
			if i > 0:
				lit_px[PHASES[i - 1]] = _moon("phase_%02d" % int(PHASES[i - 1] * 100))
			if i >= PHASES.size():
				_check_phases()
				for f in failures:
					printerr("FAIL: ", f)
				print("sky_probe: %s" % ("PASS" if failures.is_empty() else "FAIL"))
				quit(0 if failures.is_empty() else 1)
				return true
			NightSky.set_phase(env.sky, PHASES[i])
	step += 1
	wait_until = frame + SETTLE
	return false

func _shot(tag: String) -> Image:
	var img := root.get_viewport().get_texture().get_image()
	var dir := OS.get_environment("SKY_SHOT_DIR")
	if dir != "":
		img.save_png(dir.path_join("sky_%s.png" % tag))
	return img

static func _avg(img: Image, r: Rect2i) -> Vector3:
	var sum := Vector3.ZERO
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r8, c.g8, c.b8)
	return sum / float(r.get_area())

func _regions(tag: String) -> Dictionary:
	var img := _shot(tag)
	var w := img.get_width()
	var h := img.get_height()
	var out := {
		"top": _avg(img, Rect2i(int(w * 0.29), int(h * 0.005), int(w * 0.06), int(h * 0.06))),
		"mid": _avg(img, Rect2i(int(w * 0.44), int(h * 0.20), int(w * 0.12), int(h * 0.06))),
		"horizon": _avg(img, Rect2i(int(w * 0.475), int(h * 0.40), int(w * 0.05), int(h * 0.04))),
	}
	print("%s: top=%s mid=%s horizon=%s" % [tag, out.top, out.mid, out.horizon])
	return out

## Counts moon pixels clearly brighter than the sky beside it; saves a close-up.
func _moon(tag: String) -> int:
	var img := root.get_viewport().get_texture().get_image()
	var target: Vector3 = cam.global_position + env.sky.sky_material.get_shader_parameter("moon_dir") * 1000.0
	var c := cam.unproject_position(target)
	var half := 24
	var box := Rect2i(int(c.x) - half, int(c.y) - half, half * 2, half * 2)
	if cam.is_position_behind(target) or not Rect2i(Vector2i(30, 0), img.get_size() - Vector2i(30, 0)).encloses(box):
		failures.append("moon off screen at %s" % c)
		return 0
	var bg := _avg(img, Rect2i(box.position.x - 30, box.position.y, 6, box.size.y))
	var n := 0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var p := img.get_pixel(x, y)
			if Vector3(p.r8, p.g8, p.b8).length() > bg.length() + 40.0:
				n += 1
	var dir := OS.get_environment("SKY_SHOT_DIR")
	if dir != "":
		var crop := img.get_region(box)
		crop.resize(box.size.x * 4, box.size.y * 4, Image.INTERPOLATE_NEAREST)
		crop.save_png(dir.path_join("moon_%s.png" % tag))
	print("%s: moon at %s, lit px %d (bg %s)" % [tag, c.round(), n, bg])
	return n

func _check_phases() -> void:
	var new_moon: int = lit_px.get(0.0, -1)
	var quarter: int = lit_px.get(0.25, -1)
	var full: int = lit_px.get(0.5, -1)
	if full < 150:
		failures.append("full moon too small or dim: %d lit px" % full)
	if not (new_moon < quarter and quarter < full):
		failures.append("lit area should grow new < quarter < full: %d %d %d" % [new_moon, quarter, full])
	if new_moon > full / 10:
		failures.append("new moon too visible: %d lit px" % new_moon)
