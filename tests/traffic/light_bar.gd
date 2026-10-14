extends SceneTree

# The police light bar (#665, Roy 2026-10-14 "it's not just cars, it's
# everything"): on every car kind the game builds (every sheet and parts
# body, as traffic and as the player's car), the bar's two halves carry the
# light-bar tag in the lamp surface, and only the three cop kinds have one;
# the lamp shader has the flasher switch; a patrol car's lights_on drives it.
#
#   godot --headless --audio-driver Dummy --path . -s res://tests/traffic/light_bar.gd

var fails := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var cops := ["c1_patrol", "c2_patrolsuv", "c3_interceptor"]
	for kind in NpcCarBuilder.KINDS:
		for ai in [true, false]:
			var role := Undercarriage.ROLE_COP if kind in cops else ""
			var vis := NpcCarBuilder.chassis_visual(kind, "stock", NpcCarBuilder.sheet_paint(kind), role, ai)
			root.add_child(vis)
			var body := vis.get_node_or_null(^"Body") as MeshInstance3D
			_check(body != null and body.mesh != null, "%s (%s): no Body" % [kind, "traffic" if ai else "player"])
			if body == null or body.mesh == null:
				continue
			var gi := CarAssembler.surface_index(body.mesh, "glow")
			var tagged := 0
			if gi >= 0:
				var cols: PackedColorArray = body.mesh.surface_get_arrays(gi)[Mesh.ARRAY_COLOR]
				for c in cols:
					if absf(c.a - CarPaint.LIGHT_BAR_TAG) < 0.02:
						tagged += 1
				var mat := body.get_active_material(gi) as ShaderMaterial
				_check(mat != null and mat.shader.code.contains("instance uniform float bar"), "%s: the lamp shader has no light bar switch" % kind)
			if kind in cops:
				_check(tagged >= 6, "%s (%s): the light bar is not tagged (%d vertices)" % [kind, "traffic" if ai else "player", tagged])
			else:
				_check(tagged == 0, "%s (%s): %d lamp vertices carry the light bar tag" % [kind, "traffic" if ai else "player", tagged])
			vis.queue_free()
	# The coupe has its own builder.
	var coupe := P1CoupeBuilder.build_chassis_visual()
	var cbody := coupe.get_node_or_null(^"Body") as MeshInstance3D
	var cgi := CarAssembler.surface_index(cbody.mesh, "glow") if cbody != null and cbody.mesh != null else -1
	var ctagged := 0
	if cgi >= 0:
		for c in (cbody.mesh.surface_get_arrays(cgi)[Mesh.ARRAY_COLOR] as PackedColorArray):
			if absf(c.a - CarPaint.LIGHT_BAR_TAG) < 0.02:
				ctagged += 1
	_check(cgi >= 0 and ctagged == 0, "p1_coupe: %d lamp vertices carry the light bar tag" % ctagged)
	coupe.free()
	# The patrol car's lights drive the bar, and the warning flash leaves it as it was.
	var cop := PatrolCar.make()
	cop.chassis_visual = NpcCarBuilder.chassis_visual(PatrolCar.KIND, "stock", NpcCarBuilder.sheet_paint(PatrolCar.KIND), Undercarriage.ROLE_COP, true)
	var cop_body := cop.chassis_visual.get_node(^"Body") as MeshInstance3D
	cop.lights_on = true
	_check(float(cop_body.get_instance_shader_parameter("bar")) == 1.0, "lights on: the bar should flash")
	cop.lights_on = false
	_check(float(cop_body.get_instance_shader_parameter("bar")) == 0.0, "lights off: the bar should be dark")
	cop.chassis_visual.free()
	cop.free()
	await process_frame
	print("light_bar: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
