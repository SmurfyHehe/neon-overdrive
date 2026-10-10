extends SceneTree

# Sign legibility (2026-10-10): what a shop sign draws must be the word, the
# right way round, from the road and from where a driver sees it.
#
# 1. Square-on: an orthographic camera looks straight at each sign face and
#    the test samples the screen at the centre of every glyph pixel and
#    compares it with the 5x7 font bitmap. A mirrored, shifted or garbled
#    word fails; a band facing the wrong way shows its back (mirrored) and
#    fails too. Checked: a band on a +x building, a band on a -x building,
#    a blade from the front and from behind, the diner sign.
# 2. At a glance: a perspective camera at driver eye height (and from the
#    high chase view) looks at a band from 15 to 45 m up the road, 7 m off
#    its front. Every letter must keep at least MIN_LETTER of the word's
#    mean brightness. The old atlas (1 texel per glyph pixel, nearest, no
#    mipmaps) skipped whole columns at that size: LAUNDRY read LAU DRY.
#
# Needs a real window (MultiMesh + viewport read-back).
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/world/sign_legibility.gd

const Signs := preload("res://scripts/world/building_signs.gd")
const SETTLE := 6
const LIT := 0.25
const MAX_MISMATCH := 0.04
const MIN_LETTER := 0.35
const GLANCES := [
	# [camera offset from the sign centre (x toward the road, y up, z back up the road), name]
	[Vector3(-7.0, 0.3, 15.0), "eye 15 m"],
	[Vector3(-7.0, 0.3, 25.0), "eye 25 m"],
	[Vector3(-7.0, 0.3, 35.0), "eye 35 m"],
	[Vector3(-7.0, 0.3, 45.0), "eye 45 m"],
	[Vector3(-7.0, 4.0, 20.0), "high 20 m"],
	[Vector3(-7.0, 4.0, 35.0), "high 35 m"],
]

var mmi: MultiMeshInstance3D
var cam: Camera3D
var signs: Array = []  # [name, word, instance, from_back]
var step := 0
var frame := 0
var wait_until := 0
var fails := 0
var checks := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	mmi = Signs.new_multimesh(8)
	root.add_child(mmi)
	var mm := mmi.multimesh
	# a band on a +x building, one on a -x building, a blade, the diner sign
	Signs.place(mm, 0, "LAUNDRY", 1, 0, Vector3(0.0, 0.0, 0.0), 1, 0.75, 10.0)
	Signs.place(mm, 1, "NOODLES", 0, 0, Vector3(0.0, 0.0, -30.0), -1, 0.75, 10.0)
	Signs.place(mm, 2, "PARTS", 2, 0, Vector3(0.0, 0.0, -60.0), 1, 0.8, 2.0, true)
	Signs.place(mm, 3, "DINER", 0, 0, Vector3(0.0, 0.0, -90.0), 1, 1.6, 4.5, false, PI / 2.0)
	mm.visible_instance_count = 4
	signs = [
		["band +x side", "LAUNDRY", 0, false],
		["band -x side", "NOODLES", 1, false],
		["blade front", "PARTS", 2, false],
		["blade back", "PARTS", 2, true],
		["diner", "DINER", 3, false],
	]
	cam = Camera3D.new()
	# the project interpolates physics; a camera moved in _process would be
	# drawn (and unproject) from a blend of two frames
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(cam)
	cam.current = true
	wait_until = SETTLE

func _xf(i: int) -> Transform3D:
	return mmi.global_transform * mmi.multimesh.get_instance_transform(i)

## World point of glyph pixel (px, py) on the front (-x) or back (+x) face.
func _glyph_point(xf: Transform3D, word_px: int, px: float, py: float, back: bool) -> Vector3:
	var u := (px + 2.0) / float(word_px + 4)
	var lz := (0.5 - u) if back else (u - 0.5)
	var ly := 0.5 - py / 9.0
	return xf * Vector3(0.5 if back else -0.5, ly, lz)

func _lum(img: Image, p: Vector2) -> float:
	var x := int(p.x)
	var y := int(p.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return -1.0
	var c := img.get_pixel(x, y)
	return maxf(c.r, maxf(c.g, c.b))

func _process(_delta: float) -> bool:
	frame += 1
	var total: int = signs.size() + GLANCES.size()
	if step >= total:
		print("sign_legibility: %d checks, %s" % [checks, "PASS" if fails == 0 else "%d failure(s)" % fails])
		quit(0 if fails == 0 else 1)
		return true
	if frame < wait_until:
		_aim(step)
		return false
	var img := root.get_viewport().get_texture().get_image()
	var dump := OS.get_environment("SIGN_TEST_DUMP")
	if dump != "":
		DirAccess.make_dir_recursive_absolute(dump)
		img.save_png(dump.path_join("step%02d.png" % step))
	if step < signs.size():
		_check_square(step, img)
	else:
		_check_glance(step - signs.size(), img)
	step += 1
	wait_until = frame + SETTLE
	return false

func _aim(s: int) -> void:
	if s < signs.size():
		var spec: Array = signs[s]
		var xf := _xf(int(spec[2]))
		var n := -xf.basis.x.normalized()
		if spec[3]:
			n = -n
		var sc := xf.basis.get_scale()
		var vp := root.get_viewport().get_visible_rect().size
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		# the whole face in view: height, or the length scaled to the window's aspect
		cam.size = maxf(sc.y * 1.6, sc.z * 1.15 * vp.y / vp.x)
		cam.look_at_from_position(xf.origin + n * 5.0, xf.origin, Vector3.UP)
	else:
		var g: Array = GLANCES[s - signs.size()]
		var xf := _xf(0)
		var off: Vector3 = g[0]
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 80.0
		# a driver looks up the road, not at the sign
		cam.look_at_from_position(xf.origin + off, xf.origin + Vector3(off.x, off.y, -40.0), Vector3.UP)

func _check_square(s: int, img: Image) -> void:
	var spec: Array = signs[s]
	var word: String = spec[1]
	var xf := _xf(int(spec[2]))
	var back: bool = spec[3]
	var word_px := Signs.word_px(word)
	var cells := 0
	var bad := 0
	var bad_list := ""
	for py in 9:
		for px in word_px:
			var want := false
			var k := px / Signs.GLYPH_W
			var gx := px % Signs.GLYPH_W
			var gy := py - 1
			if gx < 5 and gy >= 0 and gy < 7:
				var g: Array = Signs.FONT.get(word[k], [])
				want = g.size() == 7 and g[gy][gx] == "#"
			var p := cam.unproject_position(_glyph_point(xf, word_px, px + 0.5, py + 0.5, back))
			var l := _lum(img, p)
			if l < 0.0:
				_fail("%s: glyph pixel (%d, %d) is off screen" % [spec[0], px, py])
				return
			cells += 1
			if (l > LIT) != want:
				bad += 1
				if bad <= 6:
					bad_list += " (%d,%d)" % [px, py]
	checks += 1
	var ratio := float(bad) / float(cells)
	print("%s %s: %d of %d glyph pixels wrong (%.1f%%)" % [spec[0], word, bad, cells, ratio * 100.0])
	if ratio > MAX_MISMATCH:
		_fail("%s %s: %.1f%% of glyph pixels wrong (mirrored, shifted or garbled):%s" % [spec[0], word, ratio * 100.0, bad_list])

func _check_glance(gi: int, img: Image) -> void:
	var g: Array = GLANCES[gi]
	var word := "LAUNDRY"
	var xf := _xf(0)
	var word_px := Signs.word_px(word)
	var energy := []
	var widths := ""
	for k in word.length():
		# the letter's 5x7 cell on screen
		var corners := PackedVector2Array()
		for c in [[0.0, 1.0], [5.0, 1.0], [5.0, 8.0], [0.0, 8.0]]:
			corners.append(cam.unproject_position(_glyph_point(xf, word_px, float(k * Signs.GLYPH_W) + c[0], c[1], false)))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in corners:
			lo = lo.min(c)
			hi = hi.max(c)
		widths += " %.1f" % (hi.x - lo.x)
		var sum := 0.0
		var n := 0
		for y in range(floori(lo.y), ceili(hi.y) + 1):
			for x in range(floori(lo.x), ceili(hi.x) + 1):
				var p := Vector2(x + 0.5, y + 0.5)
				var thin := hi.x - lo.x < 1.5 and absf(p.x - (lo.x + hi.x) / 2.0) < 1.0 and p.y >= lo.y and p.y <= hi.y
				if thin or Geometry2D.is_point_in_polygon(p, corners):
					var l := _lum(img, p)
					if l >= 0.0:
						sum += l
						n += 1
		energy.append(sum / maxf(1.0, float(n)))
	var mean := 0.0
	for e in energy:
		mean += e
	mean /= float(energy.size())
	checks += 1
	var line := ""
	for k in energy.size():
		line += " %s=%.2f" % [word[k], energy[k] / maxf(mean, 1e-6)]
	print("glance %s (letters%s px wide):%s" % [g[1], widths, line])
	if mean < 0.02:
		_fail("glance %s: the sign is dark (mean %.3f)" % [g[1], mean])
		return
	for k in energy.size():
		if energy[k] < MIN_LETTER * mean:
			_fail("glance %s: letter %s of %s is %.0f%% of the word's brightness (dropped columns)" % [g[1], word[k], word, 100.0 * energy[k] / mean])
