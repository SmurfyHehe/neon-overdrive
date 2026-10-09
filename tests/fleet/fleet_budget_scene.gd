extends SceneTree

# Fleet budget check (stage B1 audit): what the planned car meshes cost in
# the real stage A scene, counted by Godot's renderer.
#
# Loads Game.tscn, parks the player, and counts draw calls, triangles and
# objects per frame from the chase cam:
#   baseline   the scene as it is (no traffic)
#   nodes      + TRAFFIC traffic cars (the 3 traffic designs' proxies) built
#              the way B1 plans a car: 1 body mesh (3 surfaces) + 4 wheels,
#              at most 7 draw calls per car (Godot measured 5 on 2026-10-05:
#              the Mobile renderer drew each body in one call)
#   multimesh  the same cars drawn as one MultiMesh per design for the body
#              and one for its wheels (RESEARCH-cheap-pretty.md proposal 3,
#              not approved yet)
# then scales the triangle numbers up to the class budgets (traffic 4k,
# police 6k, player 10k) to show the worst case.
#
# Pass (counts come from Godot's renderer, not the GPU, so they hold on the
# laptop too):
#   - each node-built car adds no more than the planned 7 draw calls
#   - the MultiMesh version adds at most 4 draw calls per design
#   - triangles at full budget stay under TRI_LIMIT per frame
# Frame time is NOT measured here: this sandbox renders on the CPU. The
# laptop number comes from benchmark mode in stage B step 3.
#
# Writes budget_scene.json to user://fleet_audit/;
# -- --out=res://docs/design/fleet/audit refreshes the committed snapshot.
#
# Needs a real renderer:
#   godot --path . -s res://tests/fleet/fleet_budget_scene.gd

const Proxies := preload("res://tests/fleet/fleet_proxies.gd")
const TRAFFIC := 30
const BUDGET := {"player": 10000, "cop": 6000, "npc": 4000}
const TRI_LIMIT := 1000000     # Iris Xe handles this many per frame at 60 fps with room to spare
const SAMPLE_FRAMES := 20
const OUT_DIR := "user://fleet_audit"

var fails := 0

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails += 1

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(777)
	var data := Proxies.load_data()
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 60:
		await process_frame
	var player: Node3D = game.get("player")
	var base: Dictionary = await _sample()
	print("baseline   draw calls %d  triangles %d  objects %d" % [base.dc, base.tris, base.obj])

	var npcs := []
	for car in data.cars:
		if car.role == "npc":
			npcs.append(car)
	var slots := _slots(player.global_position)

	# ---- node-built cars (B1 plan)
	var holder := Node3D.new()
	game.add_child(holder)
	var proxy_tris := 0
	for i in TRAFFIC:
		var car: Dictionary = npcs[i % npcs.size()]
		var node := Proxies.build_car(data, car, "stock", "full")
		node.position = slots[i]
		node.rotation.y = 0.0 if slots[i].x > 0.0 else PI
		holder.add_child(node)
		proxy_tris += int(Proxies.find_build(car, "stock").tris_total)
	var nodes: Dictionary = await _sample()
	holder.queue_free()
	await process_frame
	var nodes_dc_per_car: float = float(nodes.dc - base.dc) / TRAFFIC
	print("nodes      draw calls %d (+%.1f per car)  triangles %d (+%d)  objects %d" % [nodes.dc, nodes_dc_per_car, nodes.tris, nodes.tris - base.tris, nodes.obj])

	# ---- MultiMesh per design
	var mm_holder := Node3D.new()
	game.add_child(mm_holder)
	var per_design := {}
	for i in TRAFFIC:
		var car: Dictionary = npcs[i % npcs.size()]
		if not per_design.has(car.id):
			per_design[car.id] = {"car": car, "xf": []}
		var xf := Transform3D(Basis(Vector3.UP, 0.0 if slots[i].x > 0.0 else PI), slots[i])
		per_design[car.id].xf.append(xf)
	for id in per_design:
		var car: Dictionary = per_design[id].car
		var xfs: Array = per_design[id].xf
		var proto := Proxies.build_car(data, car, "stock", "full")
		var body_mesh: Mesh = (proto.get_node("Body") as MeshInstance3D).mesh
		var wheel_nodes := []
		for k in 4:
			wheel_nodes.append(proto.get_node("Wheel%d" % k))
		mm_holder.add_child(_multimesh(body_mesh, xfs, []))
		# one wheel mesh (front right) for all four corners; the left ones turn 180
		var wheel_xfs := []
		for xf in xfs:
			for k in 4:
				var w: MeshInstance3D = wheel_nodes[k]
				var local := Transform3D(Basis(Vector3.UP, PI) if w.position.x < 0.0 else Basis(), w.position)
				wheel_xfs.append(xf * local)
		mm_holder.add_child(_multimesh((wheel_nodes[0] as MeshInstance3D).mesh, wheel_xfs, []))
		proto.free()
	var mm: Dictionary = await _sample()
	mm_holder.queue_free()
	await process_frame
	print("multimesh  draw calls %d (+%d for %d designs)  triangles %d (+%d)  objects %d" % [mm.dc, mm.dc - base.dc, per_design.size(), mm.tris, mm.tris - base.tris, mm.obj])

	# ---- worst case at full budget: traffic at 4k, 3 police at 6k, player at 10k
	var proxy_avg := float(proxy_tris) / TRAFFIC
	var full: int = base.tris + TRAFFIC * BUDGET.npc + 3 * BUDGET.cop + BUDGET.player
	print("at full budget: %d traffic x %dk + 3 police x %dk + player %dk = %d triangles per frame (proxies average %.0f)" % [
		TRAFFIC, BUDGET.npc / 1000, BUDGET.cop / 1000, BUDGET.player / 1000, full, proxy_avg])

	if nodes_dc_per_car > 7.0:
		_fail("a node-built car adds %.1f draw calls, the plan allows 7" % nodes_dc_per_car)
	if mm.dc - base.dc > 4 * per_design.size():
		_fail("MultiMesh traffic adds %d draw calls, want <= %d" % [mm.dc - base.dc, 4 * per_design.size()])
	if full > TRI_LIMIT:
		_fail("%d triangles per frame at full budget, limit %d" % [full, TRI_LIMIT])

	var out_dir := OUT_DIR
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var f := FileAccess.open(out_dir.path_join("budget_scene.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"traffic_cars": TRAFFIC, "baseline": base, "nodes": nodes, "multimesh": mm,
		"nodes_draw_calls_per_car": snappedf(nodes_dc_per_car, 0.01),
		"multimesh_extra_draw_calls": mm.dc - base.dc, "designs": per_design.size(),
		"proxy_tris_avg": snappedf(proxy_avg, 1.0), "full_budget_tris_per_frame": full,
		"note": "Counts from Godot's renderer, independent of the GPU. Frame time is not measured here (CPU renderer)."}, " ", false))
	f.close()
	game.queue_free()
	await process_frame
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

# Cars spread over 3 lanes our way and 2 oncoming, 12-160 m ahead of the
# player, all inside the chase cam's view.
func _slots(origin: Vector3) -> Array:
	var lanes := []
	for l in [[0, false], [1, false], [2, false], [0, true], [1, true]]:
		lanes.append(TrafficManager.lane_centre(l[0], l[1]))
	var out := []
	for i in TRAFFIC:
		var x: float = lanes[i % lanes.size()]
		var z: float = -12.0 - 148.0 * float(i) / TRAFFIC
		out.append(Vector3(origin.x + x, origin.y, origin.z + z))
	return out

func _multimesh(mesh: Mesh, xfs: Array, _colors: Array) -> MultiMeshInstance3D:
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.mesh = mesh
	mmesh.instance_count = xfs.size()
	for i in xfs.size():
		mmesh.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mmesh
	return mmi

func _sample() -> Dictionary:
	for i in 5:
		await process_frame
	var dc := 0
	var tris := 0
	var obj := 0
	for i in SAMPLE_FRAMES:
		await RenderingServer.frame_post_draw
		dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		tris += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		obj += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	return {"dc": dc / SAMPLE_FRAMES, "tris": tris / SAMPLE_FRAMES, "obj": obj / SAMPLE_FRAMES}
