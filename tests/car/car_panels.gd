extends SceneTree

# Opening panels (car-parts plan 2026-10-09, build list item 4):
#   - every sheet car cuts a hood, doors (one or two a side) and a trunk lid,
#     hatch or tailgate out of its body; nothing is lost in the cut (the
#     split copy has the body's triangles plus the panels' inner skins)
#   - closed, the car draws its one Body and the split copy is hidden, so
#     the draw-call counts the other tests assert do not move
#   - opening swaps to the split copy; the engine bay is drawn only while
#     the hood is open, the trunk tub only while the trunk is
#   - the keys work only while stopped; driving off closes everything
#
# Run (headless is fine):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/car_panels.gd

var fails := 0

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails += 1

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _tris(mi: MeshInstance3D) -> int:
	var n := 0
	var m := mi.mesh as ArrayMesh
	for i in m.get_surface_count():
		n += m.surface_get_array_len(i) / 3
	return n

func _panel(cp: CarPanels, pname: String) -> MeshInstance3D:
	if not cp.panels.has(pname):
		return null
	return (cp.panels[pname].hinge as Node3D).get_child(0) as MeshInstance3D

func _initialize() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	# ---- every sheet car cuts
	var kinds := ["p1_coupe"]
	for k in NpcCarBuilder.KINDS:
		kinds.append(k)
	var pickup_checked := false
	for kind in kinds:
		var car: Node3D
		if kind == "p1_coupe":
			car = P1CoupeBuilder.build_chassis_visual()
		else:
			car = NpcCarBuilder.chassis_visual(kind, "stock", NpcCarBuilder.sheet_paint(kind), Undercarriage.ROLE_PLAYER)
		var body := car.get_node("Body") as MeshInstance3D
		var body_tris := _tris(body)
		var cp := CarPanels.attach(car, null)
		holder.add_child(car)
		_check(cp != null, "%s: CarPanels.attach should cut the body" % kind)
		if cp == null:
			continue
		var names := cp.panels.keys()
		names.sort()
		var sizes := []
		for pname in names:
			sizes.append("%s %d" % [pname, _tris(_panel(cp, pname))])
		print("%s: trunk=%s panels: %s; shell %d, bay %d, split copy %d tris (body %d)" % [kind, cp.trunk_kind, ", ".join(sizes),
			_tris(cp.shell), _tris(cp.engine_bay) if cp.engine_bay else 0, cp.triangle_count(), body_tris])
		_check(cp.panels.has("hood"), "%s: should have a hood" % kind)
		_check(cp.panels.has("door_fl") and cp.panels.has("door_fr"), "%s: should have a front door each side" % kind)
		var doors: int = CarPanels.KINDS.get(kind, CarPanels.DEFAULT_KIND).get("doors", 4)
		_check(cp.panels.has("door_rl") == (doors >= 4), "%s: rear doors only on a four-door (%d)" % [kind, doors])
		_check(cp.panels.has("trunk"), "%s: should have a trunk / hatch / tailgate" % kind)
		if kind == "n3_pickup":
			_check(cp.trunk_kind == "tailgate", "the pickup's trunk is a tailgate, got %s" % cp.trunk_kind)
			pickup_checked = true
		# Nothing lost: shell + panels == body, plus the inner skins (one twin per body triangle in a panel).
		var panel_tris := 0
		var inner := 0
		for pname in cp.panels:
			var mi := _panel(cp, pname)
			var m := mi.mesh as ArrayMesh
			for i in m.get_surface_count():
				var n: int = m.surface_get_array_len(i) / 3
				if m.surface_get_name(i) == "body":
					inner += n / 2
					panel_tris += n / 2
				else:
					panel_tris += n
		var shell_tris := _tris(cp.shell)
		_check(shell_tris + panel_tris == body_tris, "%s: shell %d + panels %d should equal the body's %d triangles" % [kind, shell_tris, panel_tris, body_tris])
		_check(inner > 0, "%s: the panels carry inner skins" % kind)
		for pname in cp.panels:
			_check(_tris(_panel(cp, pname)) >= 6, "%s: panel %s is too small to be a panel (%d tris)" % [kind, pname, _tris(_panel(cp, pname))])
		# Hood lies ahead of the cabin and above the arches; doors sit between the arches.
		var p: Dictionary = car.get_meta("under_params")
		if not (cp.panels.has("hood") and cp.panels.has("door_fl") and cp.panels.has("trunk")):
			continue
		var hood_box: AABB = (_panel(cp, "hood").mesh as ArrayMesh).get_aabb()
		_check(hood_box.end.z < 0.0, "%s: the hood is in the front half (ends at z %.2f)" % [kind, hood_box.end.z])
		_check(hood_box.position.y > 1.5 * p.wheel_r, "%s: the hood is above the arches (y %.2f)" % [kind, hood_box.position.y])
		var door_box: AABB = (_panel(cp, "door_fl").mesh as ArrayMesh).get_aabb()
		_check(door_box.position.z > -p.axle_z and door_box.end.z < p.axle_z, "%s: the front door is between the axles (%s)" % [kind, door_box])
		_check(door_box.end.x < 0.0, "%s: door_fl is on the left" % kind)
		if cp.trunk_kind != "tailgate":
			var trunk_box: AABB = (_panel(cp, "trunk").mesh as ArrayMesh).get_aabb()
			_check(trunk_box.position.z > hood_box.end.z + 0.5, "%s: the %s is behind the hood (starts at z %.2f)" % [kind, cp.trunk_kind, trunk_box.position.z])
			print("  %s: hood %s, door_fl %s, %s %s" % [kind, hood_box, door_box, cp.trunk_kind, trunk_box])
		# Closed: hidden, body shown, bay hidden.
		_check(not cp.visible and body.visible, "%s: closed, the split copy is hidden and the Body shown" % kind)
		_check(cp.engine_bay != null and not cp.engine_bay.visible, "%s: the engine bay is not drawn with the hood shut" % kind)
		# Budget of the split copy.
		_check(cp.triangle_count() <= body_tris * 2 + 600, "%s: the split copy should stay near the body's size, got %d for %d" % [kind, cp.triangle_count(), body_tris])
	_check(pickup_checked, "the pickup was among the kinds")

	# ---- the swing, on a P1: open the hood, the bay appears; drive off, all shut
	var p1 := P1CoupeBuilder.build_chassis_visual()
	var p1_body := p1.get_node("Body") as MeshInstance3D
	var body := RigidBody3D.new()
	body.add_child(p1)
	holder.add_child(body)
	var cp1 := CarPanels.attach(p1, body)
	await process_frame
	CarPanels.ensure_actions()
	_check(InputMap.has_action("open_hood") and InputMap.has_action("open_doors") and InputMap.has_action("open_trunk"), "the three actions are registered")
	cp1.toggle_hood()
	_check(cp1.is_open("hood"), "the hood opens while stopped")
	cp1.step(0.1)
	_check(cp1.visible and not p1_body.visible, "opening swaps to the split copy")
	_check(cp1.engine_bay.visible, "the engine bay is drawn while the hood opens")
	_check(not cp1.trunk_tub.visible, "the trunk tub stays hidden with the lid shut")
	for i in 20:
		cp1.step(0.1)
	var hinge: Node3D = cp1.panels.hood.hinge
	var hood_deg := rad_to_deg(hinge.rotation.x)
	print("hood swung to %.1f degrees after 2 s; split copy draws %d calls" % [hood_deg, cp1.open_draw_calls()])
	_check(absf(hood_deg - CarPanels.HOOD_ANGLE) < 0.5, "the hood should reach %.0f degrees, got %.1f" % [CarPanels.HOOD_ANGLE, hood_deg])
	var bay_box: AABB = (cp1.engine_bay.mesh as ArrayMesh).get_aabb()
	var hood_box: AABB = (_panel(cp1, "hood").mesh as ArrayMesh).get_aabb()
	_check(bay_box.end.y <= hood_box.position.y + 0.001, "the bay sits under the hood (bay top %.2f, hood %.2f)" % [bay_box.end.y, hood_box.position.y])
	_check(bay_box.position.z >= hood_box.position.z and bay_box.end.z <= hood_box.end.z, "the bay stays inside the hood's footprint")
	cp1.toggle_doors()
	cp1.toggle_trunk()
	_check(cp1.doors_open() and cp1.is_open("trunk"), "doors and trunk open too")
	cp1.step(0.1)
	_check(cp1.trunk_tub.visible, "the trunk tub is drawn while the lid opens")
	var left: Node3D = cp1.panels.door_fl.hinge
	var right: Node3D = cp1.panels.door_fr.hinge
	_check(left.rotation.y < 0.0 and right.rotation.y > 0.0, "the doors swing outward on their own sides (%.2f, %.2f)" % [left.rotation.y, right.rotation.y])
	# Driving: no opening, and everything shuts.
	body.linear_velocity = Vector3(0.0, 0.0, -5.0)
	_check(not cp1.is_stopped(), "5 m/s is not stopped")
	cp1.close_all()
	cp1.toggle_hood()
	_check(not cp1.is_open("hood"), "the hood does not open on the move")
	for i in 30:
		cp1.step(0.1)
	_check(not cp1.visible and p1_body.visible, "all shut: back to the one Body")
	_check(not cp1.engine_bay.visible and not cp1.trunk_tub.visible, "bay and tub hidden again")
	_check(absf(hinge.rotation.x) < 1e-6, "the hood is back down")

	# ---- the player builds with panels (NEON_CAR unset: the selected car)
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 10:
		await process_frame
	var player: Node = game.get("player")
	var pp: CarPanels = player.get("panels")
	_check(pp != null, "the player's car carries CarPanels")
	if pp != null:
		_check(pp.vehicle == player, "the panels read the player's speed")
		var on_layer := true
		for mi in pp.find_children("*", "VisualInstance3D", true, false):
			if (mi as VisualInstance3D).layers != 1 << (CarFx.CAR_LAYER - 1):
				on_layer = false
		_check(on_layer, "the split copy is on the car render layer (cut before CarFx.attach)")
		_check(pp.process_mode == Node.PROCESS_MODE_ALWAYS, "panels keep swinging in photo mode (tree paused)")

	if fails == 0:
		print("car_panels: PASS")
	else:
		print("car_panels: %d FAILED" % fails)
	quit(1 if fails > 0 else 0)
