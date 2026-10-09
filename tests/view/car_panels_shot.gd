extends SceneTree

# Screenshots of the opening panels for review (not a pass/fail test): the
# player's P1 with the hood, doors and trunk open, from the front and the
# rear, then a line-up of other sheet cars with everything open. Writes PNGs
# to -- --out=<dir> (default user://car_panels_shots). Needs a real renderer:
#   godot --audio-driver Dummy --path . -s res://tests/view/car_panels_shot.gd -- --out=C:/tmp/shots

const LINEUP := ["p2_hothatch", "p4_kei", "p6_crossover", "n3_pickup", "c1_patrol", "p0_beater"]

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	var out := "user://car_panels_shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 60:
		await process_frame
	var player: Node3D = game.get("player")
	var origin: Vector3 = player.global_position
	var cp: CarPanels = player.get("panels")
	# Other sheet cars in a row beside the player, everything open.
	var holder := Node3D.new()
	game.add_child(holder)
	var dx := TrafficManager.lane_centre(1, false) - TrafficManager.lane_centre(0, false)
	var others: Array[CarPanels] = []
	for i in LINEUP.size():
		var kind: String = LINEUP[i]
		var car := NpcCarBuilder.chassis_visual(kind, "stock", NpcCarBuilder.sheet_paint(kind), Undercarriage.ROLE_PLAYER)
		var k: Dictionary = NpcCarBuilder.KINDS[kind]
		car.position = origin + Vector3(-dx * float(i + 1), float(k.rest_y), 0.0)
		holder.add_child(car)
		var p := CarPanels.attach(car, null)
		others.append(p)
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.current = true
	var light := DirectionalLight3D.new()
	light.light_energy = 2.5
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	game.add_child(light)
	cam.fov = 70.0
	var shots := [
		["p1_closed_front", origin + Vector3(3.2, 1.6, -4.0), origin + Vector3(0.0, 0.6, 0.0), []],
		["p1_hood_front", origin + Vector3(3.2, 1.6, -4.0), origin + Vector3(0.0, 0.6, 0.0), ["hood"]],
		["p1_bay_above", origin + Vector3(2.4, 2.6, -2.2), origin + Vector3(0.0, 0.7, -0.9), ["hood"]],
		["p1_all_front", origin + Vector3(3.6, 1.8, -4.2), origin + Vector3(0.0, 0.6, 0.0), ["hood", "doors", "trunk"]],
		["p1_all_rear", origin + Vector3(-3.4, 1.8, 4.4), origin + Vector3(0.0, 0.6, 0.0), ["hood", "doors", "trunk"]],
		["p1_doors_side", origin + Vector3(4.5, 1.2, 0.5), origin + Vector3(0.0, 0.6, 0.0), ["doors"]],
		["lineup_front", origin + Vector3(-dx * 3.5 + 1.0, 3.0, -8.5), origin + Vector3(-dx * 3.5, 0.8, 0.0), ["hood", "doors", "trunk"]],
		["lineup_rear", origin + Vector3(-dx * 3.5 - 1.0, 3.0, 8.5), origin + Vector3(-dx * 3.5, 0.8, 0.0), ["hood", "doors", "trunk"]],
	]
	for s in shots:
		var want: Array = s[3]
		for p in [cp] + others:
			if p == null:
				continue
			p.set_open("hood", "hood" in want, true)
			p.set_doors("doors" in want, true)
			p.set_open("trunk", "trunk" in want, true)
			for i in 30:
				p.step(0.1)
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [out, s[0]]
		img.save_png(path)
		print("wrote ", ProjectSettings.globalize_path(path))
	quit(0)
