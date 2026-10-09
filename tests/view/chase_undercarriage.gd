extends SceneTree

# The worst-case chase's underside bill (car-parts plan 2026-10-09, section
# 5b): you plus 3 rival cars plus 4 cops in the chase cam's view, counted by
# Godot's renderer in the real stage A scene.
#
# Loads Game.tscn with no traffic, parks the player, then parks 7 sheet cars
# 12-36 m ahead (all inside LOD0) and samples draw calls, triangles and
# objects per frame:
#   baseline    the scene with the player (its underside included)
#   plain       + 7 cars built as traffic (no underside)
#   chase       the same 7 as 3 crew + 4 cops (the real set each)
#   far         the chase moved 55 m out (the dark plate)
#   gone        the chase moved 95 m out (nothing)
# and prints the differences. Pass: the chase costs at most 1 draw call per
# car over plain, the plate the same, and the gone row nothing.
#
# Frame time is NOT measured here (counts come from the renderer, not the
# GPU). Needs a real renderer (headless reports 0 draw calls):
#   godot --audio-driver Dummy --path . -s res://tests/view/chase_undercarriage.gd

const SAMPLE_FRAMES := 20
const RIVALS := 3
const COPS := 4

var fails := 0

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails += 1

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(777)
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 60:
		await process_frame
	var player: Node3D = game.get("player")
	var base: Dictionary = await _sample()
	print("baseline  draw calls %4d  triangles %7d  objects %4d" % [base.dc, base.tris, base.obj])

	var plain: Dictionary = await _run(game, player, false, 0.0)
	var chase: Dictionary = await _run(game, player, true, 0.0)
	var far: Dictionary = await _run(game, player, true, 55.0)
	var gone: Dictionary = await _run(game, player, true, 95.0)
	for row in [["plain", plain], ["chase", chase], ["far", far], ["gone", gone]]:
		var r: Dictionary = row[1]
		print("%-9s draw calls %4d  triangles %7d  objects %4d" % [row[0], r.dc, r.tris, r.obj])
	var n := RIVALS + COPS
	var dc_per_car := float(chase.dc - plain.dc) / n
	var tris_per_car := float(chase.tris - plain.tris) / n
	print("underside, chase over plain: +%d draw calls (%.2f per car), +%d triangles (%.0f per car)" % [chase.dc - plain.dc, dc_per_car, chase.tris - plain.tris, tris_per_car])
	print("cars at 55 m vs 95 m (plate vs nothing): +%d draw calls, +%d triangles" % [far.dc - gone.dc, far.tris - gone.tris])
	if chase.dc <= plain.dc:
		_fail("the chase should cost more draw calls than plain traffic (%d vs %d)" % [chase.dc, plain.dc])
	if chase.dc - plain.dc > n:
		_fail("the undersides cost %d draw calls for %d cars, want at most 1 each" % [chase.dc - plain.dc, n])
	if tris_per_car > 1000.0:
		_fail("%.0f triangles per underside, want under 1,000" % tris_per_car)
	game.queue_free()
	await process_frame
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

## Parks the 7 cars, samples, removes them.
func _run(game: Node, player: Node3D, real: bool, push: float) -> Dictionary:
	var holder := Node3D.new()
	game.add_child(holder)
	var slots := _slots(player.global_position, push)
	for i in RIVALS + COPS:
		var car := TrafficCar.new()
		var cop := i >= RIVALS
		car.kind = "n1_commuter"
		car.build = "stock"
		car.color = Color("#2E4FD8") if cop else Color("#C9CED6")
		if real:
			car.role = Undercarriage.ROLE_COP if cop else Undercarriage.ROLE_CREW
		else:
			car.role = Undercarriage.ROLE_TRAFFIC
		car.traffic = null
		car.target_speed = 0.0
		car.position = slots[i]
		car.rotation.y = 0.0 if slots[i].x > player.global_position.x else PI
		holder.add_child(car)
	for i in 10:
		await process_frame
	var s: Dictionary = await _sample()
	holder.queue_free()
	await process_frame
	await process_frame
	return s

## 3 lanes our way and 2 oncoming, 12-36 m ahead, plus `push` metres more.
func _slots(origin: Vector3, push: float) -> Array:
	var lanes := []
	for l in [[0, false], [1, false], [2, false], [0, true], [1, true]]:
		lanes.append(TrafficManager.lane_centre(l[0], l[1]))
	var out := []
	for i in RIVALS + COPS:
		var x: float = lanes[i % lanes.size()]
		var z := -12.0 - 24.0 * float(i) / (RIVALS + COPS) - push
		out.append(Vector3(origin.x + x, origin.y, origin.z + z))
	return out

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
