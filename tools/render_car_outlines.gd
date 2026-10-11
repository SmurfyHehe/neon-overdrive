extends SceneTree

# Flat side-on outlines of every car, for the work board's cards and the
# scrap-yard donor panel (work board W3, 2026-10-11): an amber line on
# transparent, 256x128, car front on the right, written to
# assets/ui/outlines/<car_id>.png. The PNGs are committed; run this again only
# when a car's body changes.
#
# It draws the cars' own body and wheel meshes (NpcCarBuilder, P1CoupeBuilder),
# unshaded white, from the side with an orthographic camera, then keeps the
# silhouette's edge. It needs a real renderer: run it WITHOUT --headless, a
# window opens for a few seconds.
#
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tools/render_car_outlines.gd
#
# NEON_OUTLINES=n1_commuter,p4_kei limits it to those ids.

const P1CoupeBuilder := preload("res://scripts/car/p1_coupe_builder.gd")
const NpcCarBuilder := preload("res://scripts/traffic/npc_car_builder.gd")

const OUT_DIR := "res://assets/ui/outlines"
const SIZE := Vector2i(256, 128)
const SUPER := 2
const AMBER := Color("#FFC066")
const MARGIN := 1.12
const EDGE_PX := 2   # line thickness at the supersampled size

func _initialize() -> void:
	_run.call_deferred()

func _ids() -> Array[String]:
	var env := OS.get_environment("NEON_OUTLINES")
	var out: Array[String] = []
	if env != "":
		for s in env.split(",", false):
			out.append(s.strip_edges())
		return out
	out.append("p1_coupe")
	for k in NpcCarBuilder.KINDS:
		out.append(str(k))
	return out

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var vp := SubViewport.new()
	vp.size = SIZE * SUPER
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 100.0
	vp.add_child(cam)
	cam.make_current()
	var failed := 0
	for id in _ids():
		var car := _build(id)
		if car == null:
			printerr("render_car_outlines: no body for ", id)
			failed += 1
			continue
		vp.add_child(car)
		var box := _bounds(car)
		var centre := box.get_center()
		# From +X looking toward -X: the car's front (-Z) is on the right.
		var aspect := float(SIZE.x) / float(SIZE.y)
		cam.size = maxf(box.size.y * MARGIN, box.size.z * MARGIN / aspect)
		cam.global_position = centre + Vector3(30.0, 0.0, 0.0)
		cam.look_at(centre, Vector3.UP)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			printerr("render_car_outlines: nothing rendered for ", id, " (is this a headless run?)")
			failed += 1
		else:
			var line := _outline(img)
			line.save_png("%s/%s.png" % [OUT_DIR, id])
			print("render_car_outlines: ", id, "  ", box.size)
		vp.remove_child(car)
		car.free()
	quit(1 if failed > 0 else 0)

## Body and wheels as unshaded white meshes in design space (ground at y = 0).
func _build(id: String) -> Node3D:
	var root3 := Node3D.new()
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	if id == "p1_coupe":
		var body := MeshInstance3D.new()
		body.mesh = P1CoupeBuilder._get_body_mesh()
		root3.add_child(body)
		for w in P1CoupeBuilder.Data.WHEELS:
			var hub: Vector3 = w.hub
			var m := MeshInstance3D.new()
			m.mesh = P1CoupeBuilder._get_wheel_mesh(hub.z > 0.0)
			m.position = Vector3(0.0, 0.0, 0.0)
			if hub.x < 0.0:
				m.rotation.y = PI
				m.position.x = 0.0
			root3.add_child(m)
		return _flat(root3, white)
	if not NpcCarBuilder.KINDS.has(id):
		root3.free()
		return null
	var k: Dictionary = NpcCarBuilder.KINDS[id]
	var builds := NpcCarBuilder.builds(id)
	var build: String = "stock" if "stock" in builds else str(builds[0])
	var body2 := MeshInstance3D.new()
	body2.mesh = NpcCarBuilder.body_mesh(id, build)
	root3.add_child(body2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var m2 := MeshInstance3D.new()
			m2.mesh = NpcCarBuilder.wheel_mesh(id, build, sz > 0.0)
			m2.position = Vector3(sx * float(k.wheel_x), float(k.wheel_r), sz * float(k.axle_z))
			if sx < 0.0:
				m2.rotation.y = PI
			root3.add_child(m2)
	return _flat(root3, white)

func _flat(n: Node3D, mat: Material) -> Node3D:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = mat
	return n

func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var b := mi.transform * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box

## The silhouette's edge as an amber line on transparent, at SIZE.
func _outline(img: Image) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if img.get_pixel(x, y).a > 0.5 else 0
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(AMBER, 0.0))   # transparent, but amber underneath: no dark fringe on resize
	for y in h:
		for x in w:
			if solid[y * w + x] == 0:
				continue
			var edge := false
			for d in [Vector2i(EDGE_PX, 0), Vector2i(-EDGE_PX, 0), Vector2i(0, EDGE_PX), Vector2i(0, -EDGE_PX)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or solid[ny * w + nx] == 0:
					edge = true
					break
			if edge:
				out.set_pixel(x, y, AMBER)
	out.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	return out
