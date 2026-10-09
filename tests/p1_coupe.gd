extends SceneTree

# P1 sports coupe, the player's car (stage D step 1, Roy 2026-10-06):
#   - the model builds from the design data and is the sheet's size
#     (4.42 x 1.80 x 1.24 m, mirrors excluded)
#   - budget: at most 10,000 triangles and 8 draw calls (body surfaces + door
#     mirrors + 4 wheels); the mirror cups are a few dozen triangles on top
#   - exactly the 4 sticker slots (door, hood, sun strip, rear), each lying on
#     the body, the door one mirrored
#   - head lamps at the nose, tail lamps at the tail, both on the glow surface;
#     2 exhaust tips behind the rear axle
#   - the physics are unchanged: the player's CFG, wheel positions, tyre radius,
#     collision box and CarSpec are the Phase B numbers whichever body is on,
#     and the body carries no collision
#   - NEON_TEST_CAR=1 still gives the #63 test car
#
# Run (headless is fine):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/p1_coupe.gd

const TOL := 0.05
const TRI_BUDGET := 10000
const DRAW_CALL_BUDGET := 8
## Phase B hardpoints (player.gd CFG) and the collision box from player._ready.
const CFG := {"wheel_r": 0.34, "axle_z": 1.25, "wheel_x": 0.88}
const COLLISION := Vector3(1.6, 1.0, 3.4)

var fails := 0

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails += 1

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _initialize() -> void:
	# Never read (or write) the player's saved exhaust tune: a test must see the preset.
	ExhaustTune.save_path = "user://autotune/test_p1_coupe_exhaust.json"
	OS.set_environment("NEON_TEST_CAR", "")
	_check(PlayerCar.chassis_kind() == P1CoupeBuilder.KIND, "the player should drive the P1 coupe by default, got %s" % PlayerCar.chassis_kind())

	# ---- the model
	var car := P1CoupeBuilder.build_chassis_visual()
	var body := car.get_node_or_null("Body") as MeshInstance3D
	_check(body != null and body.mesh is ArrayMesh, "the chassis visual should have a Body ArrayMesh")
	var mesh := body.mesh as ArrayMesh
	var names := []
	for i in mesh.get_surface_count():
		names.append(mesh.surface_get_name(i))
	_check("body" in names and "glass" in names and "glow" in names, "want body, glass and glow surfaces, got %s" % [names])
	var box := mesh.get_aabb()
	print("body size %s (mirrors included), %d surfaces %s" % [box.size, mesh.get_surface_count(), names])
	_check(absf(box.size.z - P1CoupeBuilder.LENGTH) <= TOL, "length %.3f, want %.2f" % [box.size.z, P1CoupeBuilder.LENGTH])
	_check(absf(box.end.y - P1CoupeBuilder.HEIGHT) <= TOL, "height %.3f, want %.2f" % [box.end.y, P1CoupeBuilder.HEIGHT])
	_check(box.size.x >= P1CoupeBuilder.WIDTH - TOL and box.size.x <= P1CoupeBuilder.WIDTH + 0.15, "width %.3f, want %.2f plus mirrors" % [box.size.x, P1CoupeBuilder.WIDTH])
	_check(absf(body.position.y - P1CoupeBuilder.BODY_LIFT) < 1e-6, "the body should sit BODY_LIFT above the chassis origin")

	# ---- budget
	var tris := P1CoupeBuilder.triangle_count()
	var dc := P1CoupeBuilder.draw_call_count()
	print("triangles %d (budget %d), draw calls %d (budget %d)" % [tris, TRI_BUDGET, dc, DRAW_CALL_BUDGET])
	_check(tris <= TRI_BUDGET, "%d triangles, budget %d" % [tris, TRI_BUDGET])
	_check(dc <= DRAW_CALL_BUDGET, "%d draw calls, budget %d" % [dc, DRAW_CALL_BUDGET])
	_check(tris == P1CoupeBuilder.Data.TRIS_TOTAL, "built %d triangles, the design data says %d" % [tris, P1CoupeBuilder.Data.TRIS_TOTAL])
	var mirrors := car.get_node_or_null("Mirrors") as MeshInstance3D
	_check(mirrors != null and mirrors.mesh is ArrayMesh, "the body should carry a Mirrors mesh (door mirror cups)")
	var mtris := P1CoupeBuilder.mirror_triangle_count()
	_check(mtris > 0 and mtris <= 200 and tris + mtris <= TRI_BUDGET, "door mirrors are %d triangles" % mtris)
	if mirrors != null:
		var mb := (mirrors.mesh as ArrayMesh).get_aabb()
		_check(mb.position.x < -P1CoupeBuilder.WIDTH / 2.0 and mb.end.x > P1CoupeBuilder.WIDTH / 2.0, "the door mirrors should stand out past the body sides (%s)" % mb)
		_check(mirrors.get_surface_override_material(0) == car.get_meta("body_mat"), "the door mirrors should share the body paint")

	# ---- sticker slots
	var slots: Array = car.get_meta("sticker_slots", [])
	var ids := {}
	for s in slots:
		ids[s.id] = ids.get(s.id, 0) + 1
		_check(s.node is Node3D and s.node.get_parent() == car, "slot %s should have a marker node under the chassis visual" % s.id)
		_check((s.node.transform.basis.z - s.normal).length() < 1e-3, "slot %s marker +Z should be its outward normal" % s.id)
		_check(_on_body(mesh, s.center, s.normal), "slot %s centre %s does not lie on the body" % [s.id, s.center])
	_check(ids.keys().size() == 4 and ids.has("door") and ids.has("hood") and ids.has("sun") and ids.has("rear"), "want the 4 slots door/hood/sun/rear, got %s" % [ids.keys()])
	_check(ids.get("door", 0) == 2, "the door slot should be mirrored (2 placements), got %d" % ids.get("door", 0))
	print("sticker slots: %s" % [ids])

	# ---- lamps and exhaust
	var heads: Array = car.get_meta("headlights", [])
	var tails: Array = car.get_meta("tail_lights", [])
	_check(heads.size() == 2 and tails.size() == 2, "want 2 headlights and 2 tail lights")
	for h in heads:
		_check(h.z < box.position.z + 0.35, "headlight %s is not at the nose" % h)
	for t in tails:
		_check(t.z > box.end.z - 0.1, "tail light %s is not at the tail" % t)
	var tips: Array = car.get_meta("exhaust_tips", [])
	_check(tips.size() == 2, "the stock coupe has 2 exhaust tips, got %d" % tips.size())
	for t in tips:
		_check(t.pos.z > CFG.axle_z and t.dir.z > 0.9, "exhaust tip %s should point back from behind the rear axle" % t.pos)
	_check(absf(float(car.get_meta("half_l", 0.0)) - P1CoupeBuilder.LENGTH / 2.0) < 1e-6, "half_l meta should be half the length (CarFx reads it)")

	# ---- paint is a uniform, not baked in the mesh
	P1CoupeBuilder.recolor(car, Color.WHITE)
	_check((car.get_meta("body_mat") as ShaderMaterial).get_shader_parameter("paint") == Color.WHITE, "recolor should set the paint uniform")
	car.free()

	# ---- the physics are untouched
	var player: PlayerCar = load("res://scripts/player.gd").new()
	root.add_child(player)
	await process_frame
	_check(player.chassis_visual != null and player.chassis_visual.name == "P1Coupe", "the player should carry the P1 body")
	_check(PlayerCar.CFG == CFG, "player CFG changed: %s" % [PlayerCar.CFG])
	_check(player.spec == CarSpec.coupe_default(), "the player's spec should still be CarSpec.coupe_default()")
	var wheels := {
		"FL": [player.front_left_wheel, Vector3(-CFG.wheel_x, 0, -CFG.axle_z)],
		"FR": [player.front_right_wheel, Vector3(CFG.wheel_x, 0, -CFG.axle_z)],
		"RL": [player.rear_left_wheel, Vector3(-CFG.wheel_x, 0, CFG.axle_z)],
		"RR": [player.rear_right_wheel, Vector3(CFG.wheel_x, 0, CFG.axle_z)],
	}
	for wname in wheels:
		var w: Wheel = wheels[wname][0]
		var want: Vector3 = wheels[wname][1]
		_check(Vector2(w.position.x, w.position.z).distance_to(Vector2(want.x, want.z)) < 1e-4, "%s physics wheel at %s, want x/z of %s" % [wname, w.position, want])
		_check(absf(w.tire_radius - CFG.wheel_r) < 1e-4, "%s tyre radius %.3f, want %.2f" % [wname, w.tire_radius, CFG.wheel_r])
		var visual := w.wheel_node
		_check(visual != null and visual.name == "P1Wheel" and visual.position == Vector3.ZERO, "%s should carry the P1 wheel visual at the wheel node" % wname)
		var m := visual.get_child(0) as MeshInstance3D
		var k: float = CFG.wheel_r / P1CoupeBuilder.DESIGN_WHEEL_R
		_check(absf(m.scale.x - k) < 1e-4, "%s wheel mesh scale %.4f, want %.4f" % [wname, m.scale.x, k])
		var hub_x: float = w.position.x + m.position.x
		_check(absf(absf(hub_x) - P1CoupeBuilder.DESIGN_WHEEL_X) < 1e-4, "%s wheel drawn at x %.3f, want the design track %.3f" % [wname, hub_x, P1CoupeBuilder.DESIGN_WHEEL_X])
	var cols := player.find_children("*", "CollisionShape3D", true, false)
	# The chassis is CarSpec.chassis_hull now (a box with its underside lifted
	# at the ends, #281): its bounding box is still exactly COLLISION.
	var hull_ok := false
	if cols.size() == 1 and (cols[0] as CollisionShape3D).shape is ConvexPolygonShape3D:
		var pts := ((cols[0] as CollisionShape3D).shape as ConvexPolygonShape3D).points
		var span := AABB(pts[0], Vector3.ZERO)
		for pt in pts:
			span = span.expand(pt)
		hull_ok = span.size.is_equal_approx(COLLISION)
	_check(hull_ok, "the player's collision hull should still span %s" % COLLISION)
	_check(player.chassis_visual.find_children("*", "CollisionObject3D", true, false).is_empty() and player.chassis_visual.find_children("*", "CollisionShape3D", true, false).is_empty(), "the body is visual only, no collision")
	print("wheelbase %.2f m, track %.2f m, tyre %.2f m, mass %.0f kg" % [CFG.axle_z * 2.0, CFG.wheel_x * 2.0, CFG.wheel_r, player.mass])
	player.free()

	# ---- the test car is still a flag away
	OS.set_environment("NEON_TEST_CAR", "1")
	_check(PlayerCar.chassis_kind() == TestCarBuilder.KIND, "NEON_TEST_CAR=1 should pick the test car")
	var tc: PlayerCar = load("res://scripts/player.gd").new()
	root.add_child(tc)
	await process_frame
	_check(tc.chassis_visual.get_meta("kind", "") == TestCarBuilder.KIND, "NEON_TEST_CAR=1 should build the test car body")
	_check(tc.front_left_wheel.position == Vector3(-CFG.wheel_x, tc.front_left_wheel.position.y, -CFG.axle_z), "the test car's wheels sit at the same CFG hardpoints")
	tc.free()
	OS.set_environment("NEON_TEST_CAR", "")

	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

## True if some body or glass triangle is coplanar with the point (within 3 cm),
## faces the same way as the slot and is near it (centroid within 0.6 m), i.e.
## the slot lies on a panel instead of hovering or sitting inside the body.
func _on_body(mesh: ArrayMesh, center: Vector3, normal: Vector3) -> bool:
	var lifted := center - Vector3(0.0, P1CoupeBuilder.BODY_LIFT, 0.0)
	for si in mesh.get_surface_count():
		if mesh.surface_get_name(si) == "glow":   # the sun strip sits on the windshield glass
			continue
		var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_NORMAL]
		for t in verts.size() / 3:
			var n := norms[t * 3]
			if n.dot(normal) < 0.8:
				continue
			var a := verts[t * 3]
			var centroid := (a + verts[t * 3 + 1] + verts[t * 3 + 2]) / 3.0
			if centroid.distance_to(lifted) > 0.6:
				continue
			if absf(n.dot(lifted - a)) <= 0.03:
				return true
	return false
