extends SceneTree

# Real wheels and brakes (car parts plan 2026-10-09, session 1), headless.
# Checks that
# - the player gets a CarParts node: a new wheel mesh per corner (the design's
#   closed wheel kept as child 0, hidden), 4 calipers as one MultiMesh while
#   driving (+1 draw call) and the 4 shocks as a second one only once the
#   car's CarDetail turns detail on (forced here), so the car pays +1 driving
#   and +2 in detail and stays inside the P1 budgets
# - meshes face the right way: tyre tread normals point out, the damper rod's
#   point out, a bar's faces point away from its middle
# - at rest on a floor the shock is scaled to the live spring length and the
#   caliper rides at the hub's height, both under the steered Wheel
# - cold discs give no glow; brake_temp 400 degC glows with the fronts above
#   the rears; cooling back to ambient turns it off; heat_for() clamps
# - a traffic car gets no parts unless its spec says parts = "full"; one that
#   does gets them with the 40 m range and keeps its own heat estimate that
#   rises under braking and falls when coasting
# - nothing logs an error the whole time
# The look was checked by eye on the real renderer. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/car_parts.gd

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
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	_run()

func _run() -> void:
	_meshes()
	await _player()
	await _traffic()
	_check(logger.errors.is_empty(), "errors were logged: %s" % [logger.errors])
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

# ---------- meshes face outward ----------

func _meshes() -> void:
	var wm := CarParts.wheel_mesh(0.34, 0.245, 0.238, "five", false)
	var arrays := wm.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var tread := 0
	var tread_out := 0
	var disc := 0
	var rim := 0
	for t in verts.size() / 3:
		var c := (verts[t * 3] + verts[t * 3 + 1] + verts[t * 3 + 2]) / 3.0
		var r := Vector2(c.y, c.z).length()
		if r > 0.335 and absf(c.x) < 0.09:
			tread += 1
			if norms[t * 3].dot(Vector3(0.0, c.y, c.z).normalized()) > 0.9:
				tread_out += 1
		if absf(cols[t * 3].a - 0.5) < 0.01:
			disc += 1
		if cols[t * 3].a < 0.01:
			rim += 1
	_check(tread >= 24 and tread_out == tread, "tyre tread triangles should face outward: %d of %d do" % [tread_out, tread])
	_check(disc >= 48, "the wheel mesh should carry brake disc faces (alpha 0.5), got %d" % disc)
	_check(rim >= 60, "the wheel mesh should carry rim faces (alpha 0), got %d" % rim)
	for style in CarParts.RIM_STYLES:
		var m := CarParts.wheel_mesh(0.34, 0.245, 0.238, style, true)
		_check(m.get_surface_count() == 1 and m.surface_get_array_len(0) > 0, "rim style %s should build one surface" % style)
	var tris := wm.surface_get_array_len(0) / 3
	print("car_parts: one wheel is %d triangles" % tris)
	_check(tris < 1200, "a wheel should stay cheap, got %d triangles" % tris)

	# A bar's six faces point away from its middle.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	CarParts._bar(st, Vector3(0.0, 0.0, -0.1), Vector3(0.0, 0.0, 0.1), Vector3.RIGHT, 0.04, 0.04, Color.WHITE)
	st.generate_normals()
	var bar := st.commit()
	var ba := bar.surface_get_arrays(0)
	var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = ba[Mesh.ARRAY_NORMAL]
	var bad := 0
	for t in bv.size() / 3:
		var c := (bv[t * 3] + bv[t * 3 + 1] + bv[t * 3 + 2]) / 3.0
		if bn[t * 3].dot(c) <= 0.0:
			bad += 1
	_check(bad == 0, "%d bar faces point inward" % bad)

	# The damper rod (a lathe) faces outward too.
	var sm := CarParts.shock_mesh()
	var sa := sm.surface_get_arrays(0)
	var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = sa[Mesh.ARRAY_NORMAL]
	var rod := 0
	var rod_out := 0
	for t in sv.size() / 3:
		var c := (sv[t * 3] + sv[t * 3 + 1] + sv[t * 3 + 2]) / 3.0
		var r := Vector2(c.x, c.z).length()
		if absf(r - 0.012) < 0.002 and c.y < -0.05 and c.y > -0.5:
			rod += 1
			if sn[t * 3].dot(Vector3(c.x, 0.0, c.z).normalized()) > 0.9:
				rod_out += 1
	_check(rod >= 8 and rod_out == rod, "damper rod faces should point outward: %d of %d do" % [rod_out, rod])
	_check(sm.surface_get_material(0) != null, "the shock mesh carries its material (MultiMesh has no override slot)")
	var cm := CarParts.caliper_mesh(0.19, 0.026, Color("#B5261E"))
	_check(cm.surface_get_material(0) != null, "the caliper mesh carries its material")
	_check(CarParts.heat_for(100.0) == 0.0 and CarParts.heat_for(CarParts.GLOW_FULL + 100.0) == 1.0
		and absf(CarParts.heat_for((CarParts.GLOW_START + CarParts.GLOW_FULL) * 0.5) - 0.5) < 1e-6, "heat_for should map GLOW_START..GLOW_FULL onto 0..1, clamped")

# ---------- the player ----------

func _floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (CarSpec.WORLD_LAYER - 1)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	col.shape = box
	body.add_child(col)
	body.position = Vector3(0.0, -0.5, 0.0)
	return body

func _player() -> void:
	root.add_child(_floor())
	var player: PlayerCar = load("res://scripts/car/player.gd").new()
	player.position = Vector3(0.0, 0.6, 0.0)
	root.add_child(player)
	await process_frame
	var parts := player.get_node_or_null("CarParts") as CarParts
	_check(parts != null, "the player should carry a CarParts node")
	if parts == null:
		return
	var fl: Wheel = player.front_left_wheel
	var design := fl.wheel_node.get_child(0) as MeshInstance3D
	_check(design != null and design.name == "Mesh" and not design.visible, "the design's closed wheel stays as child 0 of the wheel node, hidden")
	var ours := fl.wheel_node.get_node_or_null("Parts") as MeshInstance3D
	_check(ours != null and ours.visible, "our wheel mesh hangs under the wheel node")
	if ours != null:
		_check(ours.layers == 1 << (CarFx.CAR_LAYER - 1), "the wheel mesh should be on the car render layer (CarFx.attach ran after it)")
		_check(ours.position.x == design.position.x, "our wheel sits at the design track like the design's (x %.3f vs %.3f)" % [ours.position.x, design.position.x])
		_check((absf(ours.rotation.y - PI) < 1e-4) == (fl.position.x < 0.0), "the left wheel is the right one turned round (rotation.y %.3f)" % ours.rotation.y)
	var calipers := player.get_node_or_null("Calipers") as MultiMeshInstance3D
	_check(calipers != null and calipers.multimesh.instance_count == 4, "4 calipers in one MultiMesh")
	_check(player.get_node_or_null("Shocks") == null, "no shocks exist while driving (a detail part, CarDetail)")
	_check(calipers != null and calipers.visibility_range_end == 0.0, "the player's parts have no distance cut-off")
	_check(calipers != null and calipers.layers == 1 << (CarFx.CAR_LAYER - 1), "the calipers are on the car layer")
	var draws_driving := P1CoupeBuilder.draw_call_count() + CarParts.extra_draw_calls()
	_check(draws_driving == 10, "the player driving should be 10 draw calls (8 + underside + calipers), got %d" % draws_driving)

	# Detail on (photo mode, the garage, stopped with a panel open): the
	# shocks appear, on the car layer, and go when detail turns off.
	var detail := CarDetail.of(player)
	detail.force = true
	detail.refresh()
	var shocks := player.get_node_or_null("Shocks") as MultiMeshInstance3D
	_check(shocks != null and shocks.multimesh.instance_count == 4, "detail on builds the 4 shocks in one MultiMesh")
	_check(shocks != null and shocks.visible and shocks.layers == calipers.layers, "the shocks are shown on the car layer")
	detail.force = false
	detail.refresh()
	_check(shocks != null and not shocks.visible and shocks.get_parent() == player, "detail off hides the shocks and keeps the node")
	detail.force = true
	detail.refresh()
	_check(shocks != null and shocks.visible and player.get_node_or_null("Shocks") == shocks, "detail on again shows the same node, no rebuild")

	# Budgets: the P1 test's numbers plus what we add, in detail (the most).
	var tris := P1CoupeBuilder.triangle_count() + P1CoupeBuilder.mirror_triangle_count() + parts.triangle_count()
	var draws := P1CoupeBuilder.draw_call_count() + CarParts.extra_draw_calls(true)
	print("car_parts: player %d triangles as drawn (parts %d), %d draw calls in detail" % [tris, parts.triangle_count(), draws])
	_check(tris <= 10000, "the player with parts should stay inside the 10,000 triangle budget, got %d" % tris)
	_check(draws == 11, "the player in detail should be 11 draw calls (8 + underside + calipers + shocks), got %d" % draws)

	# Settle on the floor, then the shock follows the spring and the caliper the hub.
	for i in 180:
		await physics_frame
	await process_frame
	var wheels: Array[Wheel] = [player.front_left_wheel, player.front_right_wheel, player.rear_left_wheel, player.rear_right_wheel]
	var names := ["FL", "FR", "RL", "RR"]
	for i in 4:
		var w := wheels[i]
		_check(w.spring_current_length > 0.02 and w.spring_current_length < w.spring_length, "%s should be on its spring at rest (length %.3f of %.3f)" % [names[i], w.spring_current_length, w.spring_length])
		var st := parts.shock_xf[i]
		var sy := st.basis.y.length()
		var want_len: float = float(parts.cfg.shock_top) + w.spring_current_length
		_check(absf(sy - want_len) < 1e-3, "%s shock scaled to the spring length plus its top mount: %.3f vs %.3f" % [names[i], sy, want_len])
		var top := w.transform.origin
		_check(absf(st.origin.y - top.y - float(parts.cfg.shock_top)) < 1e-4 and st.origin.z - top.z > 0.3 and absf(st.origin.x) < absf(top.x), "%s shock hangs from the top mount height, behind the tyre (at %s, mount %s)" % [names[i], st.origin, top])
		var ct := parts.caliper_xf[i]
		var hub_y := top.y + w.wheel_node.position.y
		_check(absf(ct.origin.y - hub_y) < 0.01, "%s caliper rides at the hub height %.3f, got %.3f" % [names[i], hub_y, ct.origin.y])
		_check(absf(ct.basis.determinant() - 1.0) < 1e-4, "%s caliper has no mirror scale" % names[i])
		# The caliper body sits behind the hub on both sides: its mesh's hub-side
		# point (the disc edge at CALIPER_ANGLE) lands at +z in car space.
		var edge := ct * (Basis(Vector3.RIGHT, -CarParts.CALIPER_ANGLE) * Vector3(0.0, 0.0, 0.19))
		_check(edge.z - ct.origin.z > 0.1 and edge.y - ct.origin.y > 0.05, "%s caliper sits behind and above the hub (edge %s from %s)" % [names[i], edge, ct.origin])

	# Glow from the sim's brake heat.
	var fl_mesh := player.front_left_wheel.wheel_node.get_node("Parts") as MeshInstance3D
	var rl_mesh := player.rear_left_wheel.wheel_node.get_node("Parts") as MeshInstance3D
	_check(float(fl_mesh.get_instance_shader_parameter("brake_heat")) == 0.0, "cold discs give no glow")
	player.health.brake_temp = 400.0
	await process_frame
	var front := float(fl_mesh.get_instance_shader_parameter("brake_heat"))
	var rear := float(rl_mesh.get_instance_shader_parameter("brake_heat"))
	_check(front > 0.7 and front <= 1.0, "400 degC should glow strongly on the front: %.2f" % front)
	_check(rear > 0.0 and rear < front, "the rear should glow less than the front: %.2f vs %.2f" % [rear, front])
	player.health.brake_temp = PowertrainHealth.AMBIENT_C
	await process_frame
	_check(float(fl_mesh.get_instance_shader_parameter("brake_heat")) == 0.0, "back at ambient the glow is off")
	player.free()

# ---------- traffic ----------

func _traffic() -> void:
	var plain := TrafficCar.new()
	plain.kind = "n1_commuter"
	plain.build = "stock"
	plain.position = Vector3(3.0, 0.6, 0.0)
	root.add_child(plain)
	await process_frame
	_check(plain.get_node_or_null("CarParts") == null, "a traffic car gets no parts")
	_check(plain.front_left_wheel.wheel_node.get_child_count() == 1, "a traffic car keeps its one wheel mesh")
	plain.free()

	var cop := TrafficCar.new()
	cop.kind = "n1_commuter"
	cop.build = "stock"
	cop.spec = CarSpec.clone_spec(CarSpec.npc_spec("n1_commuter"))
	cop.spec["parts"] = "full"
	cop.spec["rim"] = "10spoke"
	cop.position = Vector3(-3.0, 0.6, 0.0)
	root.add_child(cop)
	await process_frame
	var parts := cop.get_node_or_null("CarParts") as CarParts
	_check(parts != null, "parts = \"full\" in the spec gives a traffic-class car the parts set")
	if parts == null:
		return
	_check(parts.cfg.rim == "mesh", "a 10spoke fleet rim maps onto the mesh rim, got %s" % parts.cfg.rim)
	var cal := cop.get_node("Calipers") as MultiMeshInstance3D
	_check(absf(cal.visibility_range_end - CarParts.LOD_RANGE) < 1e-6, "a non-player car's parts stop drawing beyond %.0f m" % CarParts.LOD_RANGE)
	# Own heat: no health object, so the estimate here heats under braking and cools coasting.
	_check(cop.get("health") == null, "traffic-class cars have no PowertrainHealth")
	var t0 := parts.brake_temp
	cop.brake_force = 20000.0
	cop.speed = 40.0
	parts._physics_process(0.5)
	var t1 := parts.brake_temp
	_check(t1 > t0 + 50.0, "braking hard at 40 m/s should heat the discs: %.0f -> %.0f" % [t0, t1])
	cop.brake_force = 0.0
	parts._physics_process(0.5)
	_check(parts.brake_temp < t1, "coasting should cool them: %.0f -> %.0f" % [t1, parts.brake_temp])
	_check(absf(parts.disc_temp() - parts.brake_temp) < 1e-6, "disc_temp() reads the own estimate when there is no health")
	parts.brake_temp = 400.0
	await process_frame
	var fl_mesh := cop.front_left_wheel.wheel_node.get_node("Parts") as MeshInstance3D
	_check(float(fl_mesh.get_instance_shader_parameter("brake_heat")) > 0.7, "a hot cop disc glows")
	cop.free()
