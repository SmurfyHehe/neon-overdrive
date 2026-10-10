extends SceneTree

# Kerb and pavement shots (pavements step 1, 2026-10-10): builds a few road
# chunks beside the game's night scene and photographs the kerb line up
# close, so the raised kerb, gutter, slab lines, yellow paint and dropped
# kerbs can be judged by eye. Needs the real renderer (no --headless).
# Writes PNGs to user://kerb_shots/<tag>/ ; tag is the first user arg.
#
#   <godot> --path . -s res://tools/kerb_shots.gd -- before

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")
const Districts := preload("res://scripts/world/districts.gd")

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var tag := "shot"
	for a in OS.get_cmdline_user_args():
		tag = a
	var dir := "user://kerb_shots/%s" % tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var p: Node3D = game.get("player")
	var base := Vector3(400.0, 0.0, p.global_position.z)
	var cfg := {"own_lanes": 2, "onc_lanes": 2, "barrier": false}
	# downtown chunk (run 0), a strip-district chunk (first strip run), and the
	# two chunks either side of the crossing with the lights on
	var strip_run := 1
	while Districts.name_of_run(strip_run) != "strip" and strip_run < 40:
		strip_run += 1
	var chunks := {"downtown": [1], "strip": [strip_run * 16 + 1], "junction": [11, 12]}
	var x_off := 0.0
	var roots := {}
	for key in chunks:
		var was := Junction.enabled
		Junction.enabled = key == "junction"
		var list: Array = []
		for ci in chunks[key]:
			var c: Node3D = B.build_chunk(ci, cfg, cfg)
			game.add_child(c)
			c.transform = Transform3D(Basis(), base + Vector3(x_off, 0.0, -50.0 * float(ci - int(chunks[key][0]))))
			list.append(c)
		Junction.enabled = was
		roots[key] = list
		x_off += 60.0
	for i in 30:
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 55.0
	root.add_child(cam)
	var kerb_x := B._lane_w(2) + B.SHOULDER_W + B.CURB_W  # kerb's outer edge
	var views := []
	var o: Vector3 = (roots["downtown"][0] as Node3D).global_position
	views.append(["kerb_close", o + Vector3(kerb_x - 1.6, 0.9, -8.0), o + Vector3(kerb_x, 0.1, -16.0)])
	views.append(["pavement_along", o + Vector3(kerb_x + 1.1, 1.5, -2.0), o + Vector3(kerb_x + 0.6, 0.1, -30.0)])
	views.append(["road_wide", o + Vector3(2.0, 1.4, 2.0), o + Vector3(kerb_x, 0.2, -30.0)])
	var s: Vector3 = (roots["strip"][0] as Node3D).global_position
	# the strip chunk's dropped kerbs sit on the building centres; find the
	# lowest kerb row on the own side and look along the kerb at it
	var sv: PackedVector3Array = (((roots["strip"][0] as Node3D).get_node(^"CurbOwn") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# (row height = the row's top minus its foot, so a hilly road's slope
	# does not matter)
	var tops := {}
	var feet := {}
	for v in sv:
		var r := roundi(-v.z / 2.0)
		tops[r] = maxf(float(tops.get(r, -INF)), v.y)
		feet[r] = minf(float(feet.get(r, INF)), v.y)
	var drop_z := -12.5
	var low := INF
	for r in tops:
		var hgt: float = tops[r] - feet[r]
		if hgt < low:
			low = hgt
			drop_z = -float(r) * 2.0
	print("kerb_shots: strip drop at z=%.1f (kerb top %.3f)" % [drop_z, low])
	views.append(["strip_drop", s + Vector3(kerb_x - 2.5, 1.3, drop_z + 11.0), s + Vector3(kerb_x, 0.1, drop_z)])
	views.append(["strip_drop_low", s + Vector3(kerb_x - 0.8, 0.5, drop_z + 7.0), s + Vector3(kerb_x, 0.05, drop_z)])
	var j: Vector3 = (roots["junction"][1] as Node3D).global_position
	views.append(["junction_kerb", j + Vector3(kerb_x - 2.0, 1.4, 16.0), j + Vector3(kerb_x, 0.1, 0.0)])
	views.append(["junction_paint", j + Vector3(kerb_x - 3.0, 1.2, -4.0), j + Vector3(kerb_x, 0.1, -12.0)])
	views.append(["junction_far", j + Vector3(-kerb_x + 2.0, 2.0, 20.0), j + Vector3(kerb_x, 0.1, -4.0)])
	# a hydrant, if one of the built chunks has one (real renderer, so the
	# MultiMesh transforms are readable)
	for key in roots:
		for c in roots[key]:
			var mm: MultiMesh = ((c as Node3D).get_node(^"Hydrants") as MultiMeshInstance3D).multimesh
			if mm.visible_instance_count > 0:
				var hp: Vector3 = (c as Node3D).to_global(mm.get_instance_transform(0).origin)
				var toward := -1.0 if hp.x > (c as Node3D).global_position.x else 1.0
				views.append(["hydrant_" + key, hp + Vector3(toward * 2.2, 1.1, 2.5), hp + Vector3(0.0, 0.35, 0.0)])
				break
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2])
		cam.make_current()
		for i in 10:
			await process_frame
		var path := "%s/%s.png" % [dir, v[0]]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("kerb_shots: ", ProjectSettings.globalize_path(path))
	quit(0)
