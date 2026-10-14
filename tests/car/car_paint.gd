extends SceneTree

# The shared car paint (CarPaint, look pass 2026-10-10). Checks that
# - every car body (the P1 coupe and every sheet kind and build: player,
#   traffic, cop) and every wheel is drawn with the CarPaint body shader, and
#   every window with its glass shader
# - every body mesh carries what the shader reads: unit normals that are
#   smooth somewhere (not one normal per triangle), the finish, shade and
#   edge arrays, and the paint flag in the vertex alpha
# - chrome, tyres and trim each get their own finish; the beater is rusty and
#   dull, every other car gloss
# - the tiers switch the shader code (Low plain, Medium + city, High + lamps)
#   and the contact shadow, and switching back restores them
# - with a real renderer (run without --headless) every shader variant
#   compiles at every tier; headless has no shader compiler, so that part
#   is skipped there and says so
# - nothing logs an error
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/car_paint.gd

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

var logger := ErrorCounter.new()
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _surface(mesh: ArrayMesh, surf: String) -> int:
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == surf:
			return i
	return -1

func _check_body_mesh(mesh: ArrayMesh, who: String) -> void:
	var i := _surface(mesh, "body")
	_check(i >= 0, "%s: a body surface" % who)
	if i < 0:
		return
	var arrays := mesh.surface_get_arrays(i)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check(arrays[Mesh.ARRAY_TEX_UV] != null and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == verts.size(), "%s: finish per vertex" % who)
	_check(arrays[Mesh.ARRAY_TEX_UV2] != null, "%s: shade per vertex" % who)
	_check(arrays[Mesh.ARRAY_CUSTOM0] != null and (arrays[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).size() == verts.size() * 3, "%s: crease distances" % who)
	_check(arrays[Mesh.ARRAY_CUSTOM1] != null, "%s: seam distances" % who)
	var smooth := 0
	var bad := 0
	var paint := 0
	for t in verts.size() / 3:
		var a := normals[t * 3]
		if not (a.is_equal_approx(normals[t * 3 + 1]) and a.is_equal_approx(normals[t * 3 + 2])):
			smooth += 1
		for k in 3:
			if absf(normals[t * 3 + k].length() - 1.0) > 0.01:
				bad += 1
		if colors[t * 3].a < 0.5:
			paint += 1
	_check(bad == 0, "%s: %d normals are not unit length" % [who, bad])
	_check(smooth > verts.size() / 3 / 10, "%s: only %d of %d triangles are smooth shaded" % [who, smooth, verts.size() / 3])
	_check(paint > 0, "%s: no paint faces" % who)
	var seams: Vector4 = mesh.get_meta("paint_seams", Vector4.ZERO)
	_check(seams.w > 0.2 and seams.x < seams.y, "%s: door cuts %s" % [who, seams])

func _run() -> void:
	var body := CarPaint.body_shader(true)
	var body_own := CarPaint.body_shader(false)
	var glass := CarPaint.glass_shader(false)
	var glass_see := CarPaint.glass_shader(true)
	var start := Time.get_ticks_msec()
	var worst_ms := 0
	var worst := ""

	# The coupe (also worn by the lowrider and the truck stand-in).
	var p1 := P1CoupeBuilder.build_chassis_visual()
	var p1_body := p1.get_node(^"Body") as MeshInstance3D
	var p1_mesh := p1_body.mesh as ArrayMesh
	var mat := p1.get_meta("body_mat") as ShaderMaterial
	var p1_glass := _surface(p1_mesh, "glass")
	if P1CoupeBuilder.uses_parts():
		# Assembled from parts: baked shade and shut lines in CUSTOM0, its own
		# CarPaint variant, the glass set on the instance.
		var pi := _surface(p1_mesh, "body")
		_check(pi >= 0 and p1_mesh.surface_get_arrays(pi)[Mesh.ARRAY_CUSTOM0] != null, "p1_coupe: baked shade per vertex")
		_check(mat != null and mat.shader == CarPaint.parts_body_shader(), "p1_coupe: the body is the CarPaint parts shader")
		_check((p1_body.get_surface_override_material(p1_glass) as ShaderMaterial).shader == glass_see, "p1_coupe: see-through CarPaint glass")
	else:
		_check_body_mesh(p1_mesh, "p1_coupe")
		_check(mat != null and mat.shader == body_own, "p1_coupe: the body is the CarPaint shader")
		_check((p1_mesh.surface_get_material(p1_glass) as ShaderMaterial).shader == glass_see, "p1_coupe: see-through CarPaint glass")
	var w1 := P1CoupeBuilder.build_wheel_visual(0.32, Vector3(0.765, 0.32, -1.26))
	_check(((w1.get_node(^"Mesh") as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial).shader == body_own, "p1_coupe: wheels use the CarPaint shader")
	_check(is_equal_approx(float((p1_body.get_instance_shader_parameter("finish") as Vector4).x), 1.0), "p1_coupe: gloss by default")
	p1.free()
	w1.free()

	# Every sheet car.
	for kind: String in NpcCarBuilder.KINDS:
		for build: String in NpcCarBuilder.builds(kind):
			var who := "%s/%s" % [kind, build]
			var t0 := Time.get_ticks_msec()
			var vis := NpcCarBuilder.chassis_visual(kind, build, NpcCarBuilder.pick_paint(kind, build))
			var took := Time.get_ticks_msec() - t0
			if took > worst_ms:
				worst_ms = took
				worst = who
			var mi := vis.get_node(^"Body") as MeshInstance3D
			var mesh := mi.mesh as ArrayMesh
			if NpcCarBuilder.uses_parts(kind):
				# Assembled from parts, as the coupe above: baked shade per
				# vertex, the parts paint on the body surface.
				var bi := _surface(mesh, "body")
				_check(bi >= 0 and mesh.surface_get_arrays(bi)[Mesh.ARRAY_CUSTOM0] != null, "%s: baked shade per vertex" % who)
				var pm := mi.get_surface_override_material(bi) as ShaderMaterial if bi >= 0 else null
				_check(pm != null and pm.shader == CarPaint.parts_body_shader(), "%s: the body is CarPaint's parts paint (city, moon, lamps)" % who)
			else:
				_check_body_mesh(mesh, who)
				_check((mesh.surface_get_material(_surface(mesh, "body")) as ShaderMaterial).shader == body, "%s: the body is the CarPaint shader" % who)
				var gi := _surface(mesh, "glass")
				_check(gi < 0 or (mesh.surface_get_material(gi) as ShaderMaterial).shader == glass, "%s: CarPaint glass" % who)
				var wm := NpcCarBuilder.wheel_mesh(kind, build, false)
				_check((wm.surface_get_material(0) as ShaderMaterial).shader == body_own, "%s: wheels use the CarPaint shader" % who)
			var fin: Vector4 = mi.get_instance_shader_parameter("finish")
			if kind == "p0_beater":
				_check(fin.y > 0.5 and fin.x < 0.6, "the beater is rusty and dull")
			else:
				_check(fin.y == 0.0 and fin.x >= 0.7, "%s: clean paint" % who)
			vis.free()
	print("car_paint: built every car in %d ms; slowest first build %s, %d ms" % [Time.get_ticks_msec() - start, worst, worst_ms])

	# Finishes: chrome is a mirror, tyres are not.
	_check(CarPaint.FINISH.chrome[0] > 0.8 and CarPaint.FINISH.chrome[1] > 0.8, "chrome is bright metal")
	_check(CarPaint.FINISH.tire[1] < 0.2 and CarPaint.FINISH.trim[0] == 0.0, "rubber and plastic are dull and not metal")

	# Tiers.
	var was := CarPaint.tier()
	for variant: String in CarPaint.VARIANTS:
		var low := CarPaint.code(variant, CarPaint.TIER_LOW)
		var med := CarPaint.code(variant, CarPaint.TIER_MEDIUM)
		var high := CarPaint.code(variant, CarPaint.TIER_HIGH)
		_check(not low.contains("#define PANO") and not low.contains("#define LAMPS"), "%s: Low is paint only" % variant)
		_check(med.contains("#define PANO") and med.contains("#define LAMPS") and not med.contains("#define FLAKE"),
			"%s: Medium adds the city and the lamps (Roy 1526)" % variant)
		_check(high.contains("#define PANO") and high.contains("#define LAMPS") and high.contains("#define FLAKE"), "%s: High adds the flake" % variant)
		_check(not low.contains("#define FLAKE"), "%s: Low has no flake" % variant)
	CarPaint.set_preset("low")
	_check(body.code == CarPaint.code("body_instance", CarPaint.TIER_LOW), "the Low preset rewrites the shared shader")
	_check(not CarFx._soft, "Low keeps the plain blob shadow")
	CarPaint.set_preset("high")
	_check(body.code.contains("#define LAMPS") and glass.code.contains("#define LAMPS"), "the High preset turns the lamps on")
	_check(body.code.contains("#define FLAKE"), "the High preset turns the flake on")
	_check(CarFx._soft, "Medium and High use the soft contact shadow")
	_check(CarPaint.tier_of("custom") == CarPaint.TIER_MEDIUM, "a custom preset is Medium")
	CarPaint.set_tier(CarPaint.TIER_MEDIUM)
	_check(body.code.contains("#define LAMPS") and not body.code.contains("#define FLAKE"), "set_tier picks the tier by number")
	_check(body.code.contains("dark * p * mix(0.06, 0.16, gloss)"), "dark paint takes a coat sheen under the lamps")
	_check(body.code.contains("#define OVERHEAD 0.12"), "with the lamps drawn, the overhead glow is only the far ones")
	CarPaint.set_tier(99)
	_check(CarPaint.tier() == CarPaint.TIER_HIGH, "an out-of-range tier clamps")

	# The coupe assembled from parts wears the same paint (look upgrade).
	var parts_body := CarPaint.code("body_parts", CarPaint.TIER_HIGH)
	_check(parts_body.contains("ao_shut = CUSTOM0.rg") and parts_body.contains("city(") and parts_body.contains("lamps("),
		"the parts body reads its baked shade from CUSTOM0 and mirrors the city and the lamps")
	var trim := CarPaint.code("trim_parts", CarPaint.TIER_HIGH)
	_check(trim.contains("city(") and trim.contains("lamps("), "the parts trim mirrors the city and the lamps")
	_check(CarPaint.code("body", CarPaint.TIER_MEDIUM).contains("moon_rim(n, v, f)"), "the paint takes the moon's rim light")
	if P1CoupeBuilder.uses_parts():
		var coupe := P1CoupeBuilder.build_chassis_visual()
		var cm := coupe.get_meta("body_mat") as ShaderMaterial
		_check(cm != null and cm.shader == CarPaint.parts_body_shader(), "the parts coupe is painted by CarPaint")
		_check(CarAssembler.trim_material().shader == CarPaint.parts_trim_shader(), "its trim is CarPaint's too")
		coupe.free()

	# Compile check (real renderer only).
	if DisplayServer.get_name() == "headless":
		print("car_paint: headless, so the shaders were not compiled here (run without --headless for that)")
	else:
		for t in [CarPaint.TIER_LOW, CarPaint.TIER_MEDIUM, CarPaint.TIER_HIGH]:
			for variant: String in CarPaint.VARIANTS:
				var sh := Shader.new()
				sh.code = CarPaint.code(variant, t)
				var names := []
				for u in sh.get_shader_uniform_list():
					names.append(u.name)
				var want := "glass" if variant.begins_with("glass") else ("trim_shine" if variant == "trim_parts" else "paint_roughness")
				_check(want in names, "%s does not compile at tier %d" % [variant, t])
		for i in 3:
			await process_frame
		print("car_paint: every shader variant compiled at every tier")
	CarPaint.set_preset(["low", "medium", "high"][was])

	_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
	if fails == 0:
		print("car_paint: PASS")
	quit(1 if fails > 0 else 0)
