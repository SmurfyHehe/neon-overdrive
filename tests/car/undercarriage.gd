extends SceneTree

# The underside (car-parts plan 2026-10-09, section 5b, build list item 3):
#   - the player's P1 carries one Undercarriage mesh: one draw call, under
#     1,000 triangles, always drawn (no visibility range)
#   - it hangs under the body floor, never below the road at rest, and stays
#     inside the body's footprint; the tail pipes end at the exhaust tips
#   - a crew (ally / rival) or cop car gets the real set to 40 m and a dark
#     plate from 40 to 80 m, nothing beyond; the cop variant adds the push-bar
#     brackets and the interceptor loses its muffler
#   - traffic gets nothing extra: its tray is in the body mesh already
#   - FWD, RWD and AWD each build, and differ
#
# Run (headless is fine):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/undercarriage.gd

const TRI_MAX := 1000
const PLATE_TRI_MAX := 60

var fails := 0

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails += 1

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _aabb(mi: MeshInstance3D) -> AABB:
	return (mi.mesh as ArrayMesh).get_aabb()

func _tris(mi: MeshInstance3D) -> int:
	return (mi.mesh as ArrayMesh).surface_get_array_len(0) / 3

func _initialize() -> void:
	# ---- the player's P1
	var car := P1CoupeBuilder.build_chassis_visual()
	var under := car.get_node_or_null(Undercarriage.NODE_NAME) as MeshInstance3D
	_check(under != null and under.mesh is ArrayMesh, "the P1 should carry an Undercarriage mesh")
	if under != null:
		var p := P1CoupeBuilder.undercarriage_params()
		var box := _aabb(under)
		var tris := _tris(under)
		print("P1 underside: %d triangles, box %s, floor %.3f ground %.3f" % [tris, box, p.floor_y, p.ground_y])
		_check(tris > 200 and tris <= TRI_MAX, "P1 underside %d triangles, want 200..%d" % [tris, TRI_MAX])
		_check((under.mesh as ArrayMesh).get_surface_count() == 1, "one surface, one draw call")
		_check(under.material_override is StandardMaterial3D, "one dark vertex-colour material")
		_check(box.position.y >= p.ground_y + 0.04, "the underside should stay above the road at rest (%.3f vs %.3f)" % [box.position.y, p.ground_y])
		_check(box.end.y <= p.ground_y + 2.0 * p.wheel_r, "the underside should stay below the wheel tops (%.3f vs %.3f)" % [box.end.y, p.ground_y + 2.0 * p.wheel_r])
		_check(box.position.x >= -p.half_w and box.end.x <= p.half_w, "inside the body's width (%s)" % box)
		_check(box.position.z >= -p.half_l and box.end.z <= p.half_l, "inside the body's length (%s)" % box)
		_check(under.visibility_range_end == 0.0, "the player's underside is always drawn")
		_check(car.get_node_or_null(Undercarriage.PLATE_NAME) == null, "the player gets no distance plate")
		_check(P1CoupeBuilder.draw_call_count() == (P1CoupeBuilder._get_body_mesh().get_surface_count() + 6), "draw_call_count counts the underside")
		# The tail pipes reach the tips.
		var tip: Vector3 = p.tips[0].pos
		_check(box.end.z >= tip.z - 0.12, "the tail pipe should reach the exhaust tip (%.3f vs %.3f)" % [box.end.z, tip.z])
	car.free()

	# ---- the sheet traffic cars: no underside, and the builder's count agrees
	# (KINDS also holds the player cars P0-P6 since #274; those keep their underside.)
	for kind in NpcCarBuilder.KINDS:
		if Undercarriage.role_for_kind(kind) != Undercarriage.ROLE_TRAFFIC:
			continue
		var vis := NpcCarBuilder.chassis_visual(kind, "stock", Color.GRAY)
		_check(vis.get_node_or_null(Undercarriage.NODE_NAME) == null, "%s traffic should get no underside" % kind)
		_check(NpcCarBuilder.draw_call_count(kind, "stock") == NpcCarBuilder.body_mesh(kind, "stock").get_surface_count() + 4, "%s traffic draw calls unchanged" % kind)
		vis.free()

	# ---- the same body as a crew car (ally / rival): LOD0 to 40 m, plate to 80 m
	var crew := NpcCarBuilder.chassis_visual("n1_commuter", "stock", Color.GRAY, Undercarriage.ROLE_CREW)
	var cu := crew.get_node_or_null(Undercarriage.NODE_NAME) as MeshInstance3D
	var cp := crew.get_node_or_null(Undercarriage.PLATE_NAME) as MeshInstance3D
	_check(cu != null and cp != null, "a crew car should carry the real set and the plate")
	if cu != null and cp != null:
		var p := NpcCarBuilder.undercarriage_params("n1_commuter", "stock")
		var box := _aabb(cu)
		print("crew n1 underside: %d triangles, plate %d, box %s, floor %.3f ground %.3f" % [_tris(cu), _tris(cp), box, p.floor_y, p.ground_y])
		_check(_tris(cu) > 200 and _tris(cu) <= TRI_MAX, "crew underside %d triangles" % _tris(cu))
		_check(_tris(cp) > 0 and _tris(cp) <= PLATE_TRI_MAX, "plate %d triangles, want under %d" % [_tris(cp), PLATE_TRI_MAX])
		_check(is_equal_approx(cu.visibility_range_end, Undercarriage.LOD0_END), "LOD0 ends at %.0f m" % Undercarriage.LOD0_END)
		_check(is_equal_approx(cp.visibility_range_begin, Undercarriage.LOD0_END) and is_equal_approx(cp.visibility_range_end, Undercarriage.LOD1_END), "the plate shows from %.0f to %.0f m" % [Undercarriage.LOD0_END, Undercarriage.LOD1_END])
		_check(box.position.y >= p.ground_y + 0.04, "crew underside above the road (%.3f vs %.3f)" % [box.position.y, p.ground_y])
		_check(cu.material_override == cp.material_override, "LOD0 and the plate share the one material")
		_check(NpcCarBuilder.draw_call_count("n1_commuter", "stock", Undercarriage.ROLE_CREW) == NpcCarBuilder.body_mesh("n1_commuter", "stock").get_surface_count() + 5, "a crew car is body + 4 wheels + 1")
	crew.free()

	# ---- the cop variant: brackets up front; the interceptor keeps a straight pipe
	var base := NpcCarBuilder.undercarriage_params("n1_commuter", "stock")
	var crew_tris := Undercarriage.triangle_count(base, Undercarriage.ROLE_CREW)
	var cop_tris := Undercarriage.triangle_count(base, Undercarriage.ROLE_COP)
	_check(cop_tris > crew_tris, "the cop set adds the push-bar brackets (%d vs %d)" % [cop_tris, crew_tris])
	var icpt := base.duplicate()
	icpt.variant = "interceptor"
	var icpt_tris := Undercarriage.triangle_count(icpt, Undercarriage.ROLE_COP)
	_check(icpt_tris != cop_tris and icpt_tris <= TRI_MAX, "the interceptor's straight pipe differs from the muffler (%d vs %d)" % [icpt_tris, cop_tris])
	var cop_box := Undercarriage.build_mesh(base, Undercarriage.ROLE_COP).get_aabb()
	_check(cop_box.position.z < -base.axle_z - 0.5, "the brackets reach toward the nose (%s)" % cop_box)
	print("cop n1 underside: %d triangles, interceptor %d" % [cop_tris, icpt_tris])

	# ---- the three drive layouts build and differ
	var counts := {}
	for drive in ["fwd", "rwd", "awd"]:
		var q := base.duplicate()
		q.drive = drive
		counts[drive] = Undercarriage.triangle_count(q, Undercarriage.ROLE_CREW)
		_check(counts[drive] > 0 and counts[drive] <= TRI_MAX, "%s builds under budget (%d)" % [drive, counts[drive]])
	_check(counts.awd > counts.rwd and counts.awd > counts.fwd, "AWD carries both ends (%s)" % [counts])

	# ---- roles from kinds
	_check(Undercarriage.role_for_kind("n2_cityhatch") == Undercarriage.ROLE_TRAFFIC, "n* is traffic")
	_check(Undercarriage.role_for_kind("c3_interceptor") == Undercarriage.ROLE_COP, "c* is a cop")
	_check(Undercarriage.role_for_kind("p1_coupe") == Undercarriage.ROLE_PLAYER, "p* is player class")
	_check(Undercarriage.draw_calls(Undercarriage.ROLE_TRAFFIC) == 0 and Undercarriage.draw_calls(Undercarriage.ROLE_COP, 100.0) == 0 and Undercarriage.draw_calls(Undercarriage.ROLE_COP, 30.0) == 1, "draw_calls per role and distance")

	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
