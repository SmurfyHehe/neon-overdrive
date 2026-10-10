extends SceneTree

# Fake wet-road reflections (RESEARCH-cheap-pretty item 7, 2026-10-09).
#
# Asserts (exit code 1 on failure):
# - every chunk gets one lamp smear per lamp, centred under that lamp's head
#   (the pool's x and z), on the tarmac, SMEAR_W x SMEAR_LEN
# - the rebuild (recycle) path keeps the smears in step with the lamps
# - set_wetness writes both materials' `wet` uniform and clamps to 0..1
# - a sheet car's tail smears: two quads behind its two tail lamps, at the
#   lamps' x, trailing behind the rear (+Z), on the ground; braking brightens
#   the instance colour, releasing restores it
# - the P1 coupe gets the same from its "tail_lights" meta
# - the smear shader compiles (no parse error from the shader compiler)
#
# Headless: MultiMesh instance transforms read back as identity there, so
# the placement checks need a window. Run:
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/world/wet_reflections.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const W := preload("res://scripts/world/wet_reflections.gd")
const EPS := 0.01

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	seed(4242)
	var headless := DisplayServer.get_name() == "headless"
	var cases := 0
	for o in [2, 4]:
		for n in [1, 2]:
			var prev := {"own_lanes": 3, "onc_lanes": 2, "barrier": false}
			var cfg := {"own_lanes": o, "onc_lanes": n, "barrier": n == 2}
			var chunk: Node3D = B.build_chunk(cases, prev, cfg)
			root.add_child(chunk)
			_check_chunk(chunk, "%s -> %s" % [prev, cfg], headless)
			B.rebuild_chunk(chunk, cases + 100, cfg, prev)
			_check_chunk(chunk, "rebuilt %s -> %s" % [cfg, prev], headless)
			chunk.free()
			cases += 1
	_check_wetness()
	_check_tails(headless)
	_check_shader()
	print("wet_reflections: %d chunk cases%s, %s" % [cases, " (headless: placement skipped)" if headless else "", "PASS" if fails == 0 else "%d failure(s)" % fails])
	quit(0 if fails == 0 else 1)

func _check_chunk(chunk: Node3D, label: String, headless: bool) -> void:
	var pools_mmi := chunk.get_node_or_null(^"LampPools") as MultiMeshInstance3D
	var smears_mmi := chunk.get_node_or_null(^"LampSmears") as MultiMeshInstance3D
	if smears_mmi == null:
		_fail("%s: no LampSmears node" % label)
		return
	if smears_mmi.material_override != W.lamp_mat():
		_fail("%s: LampSmears do not use the shared lamp smear material" % label)
	var pools := pools_mmi.multimesh
	var smears := smears_mmi.multimesh
	if smears.visible_instance_count != pools.visible_instance_count:
		_fail("%s: %d smears for %d pools" % [label, smears.visible_instance_count, pools.visible_instance_count])
		return
	if headless:
		return
	for i in smears.visible_instance_count:
		var p := pools.get_instance_transform(i)
		var s := smears.get_instance_transform(i)
		# Same spot as the pool, in the chunk's bent frame: compare the
		# pool's origin with the smear's, lifted from POOL_Y to SMEAR_Y.
		var want := p.origin + p.basis.y.normalized() * (W.SMEAR_Y - B.POOL_Y)
		if s.origin.distance_to(want) > EPS:
			_fail("%s smear %d: at %s, pool at %s" % [label, i, s.origin, p.origin])
		var sc := s.basis.get_scale()
		if absf(sc.x - W.SMEAR_W) > EPS or absf(sc.z - W.SMEAR_LEN) > EPS:
			_fail("%s smear %d: scale %s, want %.1f x %.1f" % [label, i, sc, W.SMEAR_W, W.SMEAR_LEN])

func _check_wetness() -> void:
	W.set_wetness(0.4)
	for m in [W.lamp_mat(), W.tail_mat()]:
		if absf(float(m.get_shader_parameter("wet")) - 0.4) > EPS:
			_fail("set_wetness(0.4): material reads %s" % m.get_shader_parameter("wet"))
	W.set_wetness(3.0)
	if absf(W.wetness - 1.0) > EPS or absf(float(W.tail_mat().get_shader_parameter("wet")) - 1.0) > EPS:
		_fail("set_wetness(3.0) did not clamp to 1")
	W.set_wetness(-1.0)
	if W.is_on():
		_fail("set_wetness(-1.0) did not clamp to 0 / is_on")
	W.set_wetness(1.0)

func _check_tails(headless: bool) -> void:
	var vis: Node3D = NpcCarBuilder.chassis_visual("n1_commuter", "stock", Color.WHITE)
	root.add_child(vis)
	var info: Dictionary = W.tail_info(vis)
	if info.is_empty() or info.lamps.size() != 2:
		_fail("n1_commuter: tail_info gave %s, want 2 lamps" % info)
	else:
		var half_l: float = vis.get_meta("half_l")
		for p in info.lamps:
			if p.z < half_l * 0.6:
				_fail("n1_commuter: tail lamp %s is not at the rear (half_l %.2f)" % [p, half_l])
		if signf(info.lamps[0].x) == signf(info.lamps[1].x):
			_fail("n1_commuter: both tail lamps on one side: %s" % [info.lamps])
		var mmi := W.attach_tail(vis, info.lamps, info.ground_y)
		_check_tail_mmi(mmi, info, "n1_commuter", headless)
	vis.free()

	var p1: Node3D = P1CoupeBuilder.build_chassis_visual()
	root.add_child(p1)
	var pinfo: Dictionary = W.tail_info(p1)
	if pinfo.is_empty() or pinfo.lamps.size() != 2:
		_fail("P1: tail_info gave %s, want 2 lamps" % pinfo)
	else:
		_check_tail_mmi(W.attach_tail(p1, pinfo.lamps, pinfo.ground_y), pinfo, "P1", headless)
	p1.free()

func _check_tail_mmi(mmi: MultiMeshInstance3D, info: Dictionary, label: String, headless: bool) -> void:
	if mmi == null or mmi.multimesh.instance_count != 2:
		_fail("%s: tail smears missing or not 2 instances" % label)
		return
	if mmi.material_override != W.tail_mat():
		_fail("%s: tail smears do not use the shared tail material" % label)
	if headless:
		return
	for i in 2:
		var xf := mmi.multimesh.get_instance_transform(i)
		var lamp: Vector3 = info.lamps[i]
		if absf(xf.origin.x - lamp.x) > EPS:
			_fail("%s smear %d: x %.2f, lamp x %.2f" % [label, i, xf.origin.x, lamp.x])
		if xf.origin.z < lamp.z:
			_fail("%s smear %d: centre z %.2f is ahead of the lamp z %.2f" % [label, i, xf.origin.z, lamp.z])
		if absf(xf.origin.y - (float(info.ground_y) + W.TAIL_LIFT)) > EPS:
			_fail("%s smear %d: y %.2f, ground %.2f" % [label, i, xf.origin.y, info.ground_y])
		if mmi.multimesh.get_instance_color(i) != Color.WHITE:
			_fail("%s smear %d: running colour %s, want white" % [label, i, mmi.multimesh.get_instance_color(i)])
	W.set_tail_brake(mmi.get_parent(), 1.0)
	if mmi.multimesh.get_instance_color(0).r < 1.0 + W.BRAKE_GAIN - EPS:
		_fail("%s: braking did not brighten the smears (%s)" % [label, mmi.multimesh.get_instance_color(0)])
	W.set_tail_brake(mmi.get_parent(), 0.0)
	if mmi.multimesh.get_instance_color(0) != Color.WHITE:
		_fail("%s: releasing the brake did not restore the running colour" % label)

func _check_shader() -> void:
	# A shader that failed to compile has no uniforms to list.
	var sh: Shader = W.lamp_mat().shader
	var names := []
	for u in sh.get_shader_uniform_list():
		names.append(u.name)
	for want in ["tint", "energy", "wet", "one_sided", "fade"]:
		if not names.has(want):
			_fail("smear shader: uniform %s missing (compile error?); got %s" % [want, names])
			return
