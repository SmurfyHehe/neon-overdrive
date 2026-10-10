extends SceneTree

# People A1 lineup shots (needs the real renderer, not --headless):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tools/people_pipeline/people_shots.gd
# Writes docs/design/people/a1/*.jpg: the 21 bodies (7 heights x 3 builds) from
# the front and three-quarter, the 8 painted faces, and the seated / smoking /
# hands-on-hips poses, and the cast listed in assets/people/people.json. Baked meshes only (the CPU path everyone uses).

const OUT := "res://docs/design/people/a1"

var _vp: SubViewport

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0E1424")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#1B2A4A")
	e.ambient_light_energy = 1.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()   # sodium key light from the front-left
	sun.light_color = Color("#FFC066")
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-30, -35, 0)
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#C9CED6")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-10, 150, 0)
	root.add_child(fill)
	_vp = SubViewport.new()
	_vp.size = Vector2i(2400, 800)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(cam)
	cam.current = true

	var P := PersonBody
	var people := Node3D.new()
	root.add_child(people)
	# lineup: builds in rows front to back would hide; put them side by side in groups of three
	var x := 0.0
	for hi in P.HEIGHTS.size():
		for bi in P.BUILDS.size():
			var mi := MeshInstance3D.new()
			mi.mesh = P.bake(P.variant(hi, bi), P.pose("stand"), P.outfit(hi * 3 + bi + 11), (hi * 3 + bi) % P.FACE_COUNT)
			mi.position = Vector3(x, 0, 0)
			people.add_child(mi)
			x += 0.5
		x += 0.25
	var mid := (x - 0.75) * 0.5
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = x
	for view in [["lineup_front", 0.0], ["lineup_three_quarter", 35.0]]:
		var yaw := deg_to_rad(view[1])
		cam.transform = Transform3D(Basis(), Vector3(mid + sin(yaw) * 10.0, 1.0, -cos(yaw) * 10.0)).looking_at(Vector3(mid, 1.0, 0))
		await _shot(view[0])
	people.queue_free()

	# faces close up
	var faces := Node3D.new()
	root.add_child(faces)
	var v := P.variant(3, 1)
	for f in P.FACE_COUNT:
		var mi := MeshInstance3D.new()
		mi.mesh = P.bake(v, P.pose("stand"), P.outfit(f * 5 + 2), f)
		mi.position = Vector3(f * 0.32, 0, 0)
		faces.add_child(mi)
	_vp.size = Vector2i(2400, 500)
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 8 * 0.32
	cam.transform = Transform3D(Basis(), Vector3(3.5 * 0.32, 1.66, -4.0)).looking_at(Vector3(3.5 * 0.32, 1.66, 0))
	await _shot("faces")
	faces.queue_free()

	# poses: seated driver with arms on a wheel, smoker, hands on hips (short, average, tall)
	var poses := Node3D.new()
	root.add_child(poses)
	var px := 0.0
	for hi in [0, 3, 6]:
		var vv := P.variant(hi, 1)
		var legs := P.fk_globals(vv, P.sit_legs())
		var h: float = vv["h"]
		var gl: Vector3 = legs[0][P.UPPER_L] + Vector3(0.06, -0.14, -0.40) * h
		var gr: Vector3 = legs[0][P.UPPER_R] + Vector3(-0.06, -0.14, -0.40) * h
		for item in [["sit", P.sit_pose(vv, gl, gr)], ["smoke", P.smoke(vv)], ["hands_on_hips", P.hands_on_hips(vv)]]:
			var mi := MeshInstance3D.new()
			mi.mesh = P.bake(vv, item[1], P.outfit(hi + 40), hi % P.FACE_COUNT)
			mi.position = Vector3(px, 0, 0)
			mi.rotation_degrees.y = -50.0
			poses.add_child(mi)
			px += 0.8
		px += 0.4
	_vp.size = Vector2i(2400, 700)
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = px
	var pm := (px - 1.2) * 0.5
	cam.size = px
	cam.transform = Transform3D(Basis(), Vector3(pm, 1.0, -10.0)).looking_at(Vector3(pm, 1.0, 0))
	await _shot("poses")
	poses.queue_free()

	# the cast from people.json, each in their own pose
	var cast := Node3D.new()
	root.add_child(cast)
	var ids := P.cast_ids()
	for i in ids.size():
		var mi := MeshInstance3D.new()
		mi.mesh = P.bake_person(ids[i])
		mi.position = Vector3(i * 0.9, 0, 0)
		mi.rotation_degrees.y = -20.0
		cast.add_child(mi)
	_vp.size = Vector2i(2400, 1000)
	cam.size = ids.size() * 0.9 + 0.4
	var cm := (ids.size() - 1) * 0.45
	cam.transform = Transform3D(Basis(), Vector3(cm, 1.0, -10.0)).looking_at(Vector3(cm, 1.0, 0))
	await _shot("cast")
	quit(0)

func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	var img := _vp.get_texture().get_image()
	img.save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [OUT, name]), 0.88)
	print("wrote ", name)
