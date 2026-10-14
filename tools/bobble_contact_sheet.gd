extends SceneTree

# Draws the dash bobble figures' contact sheet (interiors B1, 2026-10-11):
# every figure in BobbleFigures.IDS, front view, side view and the black
# silhouette test, each tile at the figure's real size on a 96 dpi screen
# (7 cm tall is 7 cm on the sheet), five figures a row. Needs the real
# renderer (no --headless). Writes res://docs/bobbleheads/contact_sheet.png,
# or BOBBLE_SHEET=<path>.
#
#   <godot> --path . -s res://tools/bobble_contact_sheet.gd
#
# BOBBLE_BOB=1 adds a fourth tile: the front view at the full lean toward the
# windscreen (the worst case for the glass), to judge the swing by eye.

const PX_PER_M := 3780.0           # 96 dpi
const TILE_M := Vector2(0.060, 0.092)
const COLS := 5
const LABEL_H := 22
const BG := Color("#2A2E36")
const SHEET := "res://docs/bobbleheads/contact_sheet.png"

var vp: SubViewport
var cam: Camera3D
var env: WorldEnvironment
var bobble: BobbleHead
var black: StandardMaterial3D
var tile := Vector2i(int(TILE_M.x * PX_PER_M), int(TILE_M.y * PX_PER_M))

func _initialize() -> void:
	vp = SubViewport.new()
	vp.size = tile
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	sun.shadow_enabled = false
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(1.0, 0.85, 0.6)
	fill.rotation_degrees = Vector3(-20.0, -120.0, 0.0)
	vp.add_child(fill)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = TILE_M.y
	cam.near = 0.01
	cam.far = 2.0
	cam.cull_mask = 0xFFFFF
	vp.add_child(cam)
	bobble = BobbleHead.new(null, "p1_coupe")
	bobble.position = Vector3.ZERO
	bobble.scale = Vector3.ONE
	vp.add_child(bobble)
	bobble.set_physics_process(false)
	black = StandardMaterial3D.new()
	black.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	_run.call_deferred()

func _aim(from_dir: Vector3) -> void:
	var at := Vector3(0.0, TILE_M.y * 0.5 - 0.004, 0.0)
	cam.position = at + from_dir.normalized() * 0.5
	cam.look_at(at, Vector3.UP)

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()

func _label(text: String, w: int) -> Image:
	var lv := SubViewport.new()
	lv.size = Vector2i(w, LABEL_H)
	lv.transparent_bg = false
	lv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color("#15171C")
	bg.size = Vector2(w, LABEL_H)
	lv.add_child(bg)
	var l := Label.new()
	l.text = text
	UiTheme.apply(l, "menu", 15)
	l.add_theme_color_override("font_color", Color("#E9E6DF"))
	l.position = Vector2(6.0, 2.0)
	lv.add_child(l)
	root.add_child(lv)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := lv.get_texture().get_image()
	lv.queue_free()
	return img

func _run() -> void:
	var ids: Array[String] = []
	for id in BobbleFigures.IDS:
		if id != BobbleFigures.NONE:
			ids.append(id)
	var with_bob := OS.get_environment("BOBBLE_BOB") == "1"
	var views := 4 if with_bob else 3
	var cell := Vector2i(tile.x * views, tile.y + LABEL_H)
	var rows := int(ceil(float(ids.size()) / COLS))
	var sheet := Image.create(cell.x * COLS + 4 * (COLS + 1), cell.y * rows + 4 * (rows + 1), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#0E1424"))
	var e: Environment = env.environment
	var i := 0
	for id in ids:
		bobble.set_figure(id)
		var mi := bobble.mesh_instance()
		if mi == null:
			print("no mesh for ", id)
			quit(1)
			return
		var mat := mi.material_override
		var col := i % COLS
		var row := i / COLS
		var origin := Vector2i(4 + col * (cell.x + 4), 4 + row * (cell.y + 4))
		# front, side
		e.background_color = BG
		mi.material_override = mat
		(mat as ShaderMaterial).set_shader_parameter("bob", Vector2.ZERO)
		_aim(Vector3(0.0, 0.0, 1.0))
		var front := await _grab()
		_aim(Vector3(1.0, 0.0, 0.0))
		var side := await _grab()
		# the silhouette test: black on white, from the front
		e.background_color = Color.WHITE
		mi.material_override = black
		_aim(Vector3(0.0, 0.0, 1.0))
		var sil := await _grab()
		var imgs := [front, side, sil]
		if with_bob:
			e.background_color = BG
			mi.material_override = mat
			(mat as ShaderMaterial).set_shader_parameter("bob", Vector2(0.0, -BobbleHead.TILT_MAX))
			_aim(Vector3(1.0, 0.0, 0.0))
			imgs.append(await _grab())
			(mat as ShaderMaterial).set_shader_parameter("bob", Vector2.ZERO)
		mi.material_override = mat
		for v in imgs.size():
			var img: Image = imgs[v]
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, tile), origin + Vector2i(tile.x * v, LABEL_H))
		var lab := await _label("%d  %s   (%d tris)" % [i + 1, BobbleFigures.name_of(id), bobble.triangle_count()], cell.x)
		lab.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(lab, Rect2i(Vector2i.ZERO, Vector2i(cell.x, LABEL_H)), origin)
		print("%2d %-18s %4d tris" % [i + 1, id, bobble.triangle_count()])
		i += 1
	var out := OS.get_environment("BOBBLE_SHEET")
	if out == "":
		out = SHEET
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var err := sheet.save_png(ProjectSettings.globalize_path(out))
	print("sheet %s: %s (%dx%d)" % [out, error_string(err), sheet.get_width(), sheet.get_height()])
	quit(0 if err == OK else 1)
