extends SceneTree

# Screenshots of the underside for review (not a pass/fail test): the player's
# P1 from a low three-quarter angle behind, from straight below, and a crew
# car and a cop beside it. Writes PNGs to -- --out=<dir> (default
# user://undercarriage_shots). Needs a real renderer:
#   godot --audio-driver Dummy --path . -s res://tests/undercarriage_shot.gd -- --out=C:/tmp/shots

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	var out := "user://undercarriage_shots"
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
	# A crew car and a cop one lane over, nose level with the player.
	var holder := Node3D.new()
	game.add_child(holder)
	var dx := TrafficManager.lane_centre(1, false) - TrafficManager.lane_centre(0, false)
	for spec in [[Undercarriage.ROLE_CREW, Color("#C9CED6"), 1.0], [Undercarriage.ROLE_COP, Color("#2E4FD8"), 2.0]]:
		var car := TrafficCar.new()
		car.kind = "n1_commuter"
		car.role = spec[0]
		car.color = spec[1]
		car.traffic = null
		car.target_speed = 0.0
		car.position = origin + Vector3(-dx * float(spec[2]), 0.0, 0.0)
		holder.add_child(car)
	for i in 30:
		await process_frame
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.current = true
	# A review light from below and behind: the street is lit from above on
	# purpose, so without this the underside is a black silhouette.
	var light := DirectionalLight3D.new()
	light.light_energy = 3.0
	light.rotation_degrees = Vector3(55.0, 20.0, 0.0)   # -z tilted upward: shines up at the floor
	game.add_child(light)
	cam.fov = 80.0
	var shots := [
		["p1_low_rear", origin + Vector3(2.2, -0.35, 3.4), origin + Vector3(0.0, 0.3, 0.3)],
		["p1_below", origin + Vector3(0.0, -1.8, 0.2), origin + Vector3(0.0, 0.4, 0.2)],
		["p1_side_low", origin + Vector3(3.4, 0.0, -0.5), origin + Vector3(0.0, 0.35, 0.0)],
		["crew_and_cop", origin + Vector3(-dx * 1.5, -1.4, 3.5), origin + Vector3(-dx * 1.5, 0.4, 0.0)],
	]
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP if absf((s[2] - s[1]).normalized().y) < 0.95 else Vector3.FORWARD)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [out, s[0]]
		img.save_png(path)
		print("wrote ", ProjectSettings.globalize_path(path))
	quit(0)
