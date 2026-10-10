extends SceneTree

# Wet asphalt and visible puddles (S1a, 2026-10-10, scripts/world/road_wet.gd).
#
# Asserts (exit code 1 on failure):
# - both shaders compile (their uniforms list), and every road strip,
#   shoulder, sidewalk and the junction crossing use the asphalt shader
# - every chunk has one puddle quad per grip puddle of scripts/world/puddles.gd,
#   at that puddle's road-space spot on the tarmac (PUDDLE_Y), sized to its
#   ellipse, deep ones marked by instance colour; the rebuild (recycle) path
#   keeps them in step
# - WetReflections.set_wetness drives the asphalt `wetness` and the puddle
#   `fill` (full at steady rain, the same ramp as Weather.puddle_fill)
# - set_reflections(false) zeroes both sheens, true restores them
# - GraphicsSettings.apply turns the mirrors off on Low and on otherwise
#
# Headless: MultiMesh instance transforms read back as identity there, so
# the placement checks need a window. Run:
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/world/road_wet.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const RW := preload("res://scripts/world/road_wet.gd")
const W := preload("res://scripts/world/wet_reflections.gd")
const P := preload("res://scripts/world/puddles.gd")
const Weather := preload("res://scripts/world/weather.gd")
const EPS := 0.01

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	seed(4242)
	var headless := DisplayServer.get_name() == "headless"
	_check_shaders()
	_check_materials()
	var cases := 0
	var with_puddles := 0
	for c in range(0, 24):
		var prev := {"own_lanes": 3, "onc_lanes": 2, "barrier": false}
		var cfg := {"own_lanes": 2 + c % 3, "onc_lanes": 1 + c % 2, "barrier": c % 2 == 0}
		var chunk: Node3D = B.build_chunk(c, prev, cfg)
		root.add_child(chunk)
		with_puddles += _check_chunk(chunk, c, "chunk %d" % c, headless)
		B.rebuild_chunk(chunk, c + 1000, cfg, prev)
		_check_chunk(chunk, c + 1000, "rebuilt chunk %d" % (c + 1000), headless)
		chunk.free()
		cases += 1
	if with_puddles == 0:
		_fail("no chunk in 0..23 had a puddle; puddles.gd places 0-3 per chunk")
	_check_wetness()
	_check_reflections()
	print("road_wet: %d chunks (%d with puddles)%s, %s" % [cases, with_puddles, " (headless: placement skipped)" if headless else "", "PASS" if fails == 0 else "%d failure(s)" % fails])
	quit(0 if fails == 0 else 1)

func _check_shaders() -> void:
	# A shader that failed to compile has no uniforms to list.
	var want := {
		"asphalt": [RW.asphalt_shader(), ["grain", "grain_scale", "wetness", "sheen_gain", "sheen"]],
		"puddle": [RW.puddle_mat().shader, ["fill", "mirror_gain", "water", "sky", "edge"]],
	}
	for k in want:
		var sh: Shader = want[k][0]
		var names := []
		for u in sh.get_shader_uniform_list():
			names.append(u.name)
		for n in want[k][1]:
			if not names.has(n):
				_fail("%s shader: uniform %s missing (compile error?); got %s" % [k, n, names])
				break

func _check_materials() -> void:
	var chunk: Node3D = B.build_chunk(0, {"own_lanes": 2, "onc_lanes": 2, "barrier": false}, {"own_lanes": 2, "onc_lanes": 2, "barrier": false})
	root.add_child(chunk)
	for n in ["RoadOwn", "RoadOnc", "ShoulderOwn", "ShoulderOnc", "SidewalkOwn", "SidewalkOnc"]:
		var mi := chunk.get_node_or_null(NodePath(n)) as MeshInstance3D
		var m := mi.material_override if mi != null else null
		if m == null:
			m = mi.mesh.surface_get_material(0) if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
		if m == null:
			m = mi.get_surface_override_material(0) if mi != null else null
		if not (m is ShaderMaterial) or (m as ShaderMaterial).shader != RW.asphalt_shader():
			_fail("%s is not drawn with the asphalt shader (%s)" % [n, m])
	var p := chunk.get_node_or_null(^"Puddles") as MultiMeshInstance3D
	if p == null:
		_fail("chunk has no Puddles node")
	else:
		if p.material_override != RW.puddle_mat():
			_fail("Puddles do not use the shared puddle material")
		if p.multimesh.instance_count != P.MAX_PER_CHUNK or not p.multimesh.use_colors:
			_fail("Puddles capacity %d (want %d), use_colors %s" % [p.multimesh.instance_count, P.MAX_PER_CHUNK, p.multimesh.use_colors])
	chunk.free()
	# the crossing is paved with the same shader
	if B._get_own_mat().shader != RW.asphalt_shader():
		_fail("the road's own material is not the asphalt shader")

## Returns 1 when the chunk has at least one puddle, so the run proves the
## placement code ran on real data.
func _check_chunk(chunk: Node3D, c: int, label: String, headless: bool) -> int:
	var mmi := chunk.get_node_or_null(^"Puddles") as MultiMeshInstance3D
	if mmi == null:
		_fail("%s: no Puddles node" % label)
		return 0
	var list: PackedFloat32Array = P.of_chunk(c)
	var n := list.size() / P.STRIDE
	var mm := mmi.multimesh
	if mm.visible_instance_count != n:
		_fail("%s: %d puddle quads for %d grip puddles" % [label, mm.visible_instance_count, n])
		return 0
	if headless:
		return 1 if n > 0 else 0
	for i in n:
		var s := list[i * P.STRIDE]
		var x := list[i * P.STRIDE + 1]
		var hl := list[i * P.STRIDE + 2]
		var hw := list[i * P.STRIDE + 3]
		var depth := int(list[i * P.STRIDE + 4])
		var xf := mm.get_instance_transform(i)
		var lz := -(s - float(c) * B.CHUNK_LEN)
		if lz > 0.0 or lz < -B.CHUNK_LEN:
			_fail("%s puddle %d: s %.1f is outside the chunk" % [label, i, s])
		var want: Vector3 = B._at(x, RW.PUDDLE_Y, lz)
		if xf.origin.distance_to(want) > EPS:
			_fail("%s puddle %d: at %s, want %s" % [label, i, xf.origin, want])
		var sc := xf.basis.get_scale()
		if absf(sc.x - 2.0 * hw) > EPS or absf(sc.z - 2.0 * hl) > EPS:
			_fail("%s puddle %d: scale %s, want %.2f x %.2f" % [label, i, sc, 2.0 * hw, 2.0 * hl])
		if mm.get_instance_color(i) != RW.puddle_colour(depth):
			_fail("%s puddle %d: colour %s for depth %d" % [label, i, mm.get_instance_color(i), depth])
	return 1 if n > 0 else 0

func _check_wetness() -> void:
	if absf(RW.PUDDLE_FULL_AT - Weather.LEVEL_WETNESS[Weather.Level.RAIN]) > EPS:
		_fail("PUDDLE_FULL_AT %.2f != Weather's steady-rain wetness %.2f" % [RW.PUDDLE_FULL_AT, Weather.LEVEL_WETNESS[Weather.Level.RAIN]])
	W.set_wetness(0.375)
	if absf(float(B._get_own_mat().get_shader_parameter("wetness")) - 0.375) > EPS:
		_fail("set_wetness(0.375): road reads %s" % B._get_own_mat().get_shader_parameter("wetness"))
	if absf(float(B._get_sidewalk_mat().get_shader_parameter("wetness")) - 0.375) > EPS:
		_fail("set_wetness(0.375): sidewalk reads %s" % B._get_sidewalk_mat().get_shader_parameter("wetness"))
	if absf(float(RW.puddle_mat().get_shader_parameter("fill")) - 0.5) > EPS:
		_fail("set_wetness(0.375): puddle fill %s, want 0.5 (full at %.2f)" % [RW.puddle_mat().get_shader_parameter("fill"), RW.PUDDLE_FULL_AT])
	W.set_wetness(1.0)
	if absf(float(RW.puddle_mat().get_shader_parameter("fill")) - 1.0) > EPS:
		_fail("set_wetness(1.0): puddle fill %s" % RW.puddle_mat().get_shader_parameter("fill"))
	W.set_wetness(0.0)
	if float(RW.puddle_mat().get_shader_parameter("fill")) > 0.0 or float(B._get_onc_mat().get_shader_parameter("wetness")) > 0.0:
		_fail("set_wetness(0.0) left the road or puddles wet")

func _check_reflections() -> void:
	RW.set_reflections(false)
	if float(B._get_own_mat().get_shader_parameter("sheen_gain")) > 0.0 or float(RW.puddle_mat().get_shader_parameter("mirror_gain")) > 0.0:
		_fail("set_reflections(false) left a sheen on")
	RW.set_reflections(true)
	if float(B._get_own_mat().get_shader_parameter("sheen_gain")) < 1.0 - EPS or float(RW.puddle_mat().get_shader_parameter("mirror_gain")) < 1.0 - EPS:
		_fail("set_reflections(true) did not restore the sheens")
	# the graphics presets drive it: Low off, Medium on
	var was := GraphicsSettings.preset
	GraphicsSettings.set_preset("low")
	GraphicsSettings.apply(self)
	if RW.reflections:
		_fail("Low preset left the wet-road mirrors on")
	GraphicsSettings.set_preset("medium")
	GraphicsSettings.apply(self)
	if not RW.reflections:
		_fail("Medium preset did not turn the wet-road mirrors back on")
	if GraphicsSettings.PRESET_VALUES.has(was):
		GraphicsSettings.set_preset(was)
