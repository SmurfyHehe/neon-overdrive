extends SceneTree

# Screenshots of a flipped and an airborne car for review (not a pass/fail
# test): the player's P1 on its roof, the same car mid-jump with its nose up,
# and a crew car on its side beside it, each on the Medium preset and on Low.
# Writes PNGs to -- --out=<dir> (default user://flipped_shots), named
# <tag>_<shot>_<preset>.png with -- --tag=<before|after>. Needs a real
# renderer:
#   godot --audio-driver Dummy --path . -s res://tests/view/flipped_shot.gd -- --out=C:/tmp/shots --tag=after

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	var out := "user://flipped_shots"
	var tag := "shot"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 60:
		await process_frame
	var player: RigidBody3D = game.get("player")
	var origin: Vector3 = player.global_position
	# A crew car one lane over, on its side.
	var holder := Node3D.new()
	game.add_child(holder)
	var dx := TrafficManager.lane_centre(1, false) - TrafficManager.lane_centre(0, false)
	var crew := TrafficCar.new()
	crew.kind = "n1_commuter"
	crew.role = Undercarriage.ROLE_CREW
	crew.color = Color("#C9CED6")
	crew.traffic = null
	crew.target_speed = 0.0
	crew.position = origin + Vector3(-dx * 1.6, 0.0, 0.0)
	holder.add_child(crew)
	for i in 30:
		await process_frame
	crew.freeze = true
	crew.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), origin + Vector3(-dx * 1.6, 0.9, 0.0))
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.current = true
	cam.fov = 75.0
	# A review light from low behind: the street is lit from above on purpose,
	# so without this the underside is a black silhouette.
	var light := DirectionalLight3D.new()
	light.light_energy = 3.0
	light.rotation_degrees = Vector3(-25.0, 200.0, 0.0)
	game.add_child(light)
	var was := GraphicsSettings.preset
	for preset in ["medium", "low"]:
		GraphicsSettings.preset = preset
		GraphicsSettings.apply(self)
		# On its roof: upside down, resting about where the roof would land.
		player.freeze = true
		player.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), origin + Vector3(0.0, 0.9, 0.0))
		await _settle()
		await _shot(cam, origin + Vector3(3.6, 1.6, 4.2), origin + Vector3(0.0, 0.8, 0.0), "%s/%s_roof_%s.png" % [out, tag, preset])
		await _shot(cam, origin + Vector3(-dx * 0.8, 1.4, 4.8), origin + Vector3(-dx * 0.8, 0.8, -0.5), "%s/%s_roof_and_crew_%s.png" % [out, tag, preset])
		# Close on the rear arch, where the spring and damper unit lives.
		await _shot(cam, origin + Vector3(2.3, 1.1, 2.4), origin + Vector3(0.6, 0.95, 1.3), "%s/%s_roof_arch_%s.png" % [out, tag, preset])
		# Mid-jump: 1.6 m up with the nose raised, seen from low behind.
		player.global_transform = Transform3D(Basis(Vector3.RIGHT, -0.35), origin + Vector3(0.0, 1.6, 0.0))
		await _settle()
		await _shot(cam, origin + Vector3(3.0, 0.45, 5.2), origin + Vector3(0.0, 1.5, 0.0), "%s/%s_jump_%s.png" % [out, tag, preset])
	GraphicsSettings.preset = was
	GraphicsSettings.apply(self)
	quit(0)

## Let the detail poll (CarDetail.POLL_SECS) and the physics see the new pose.
func _settle() -> void:
	for i in 30:
		await process_frame

func _shot(cam: Camera3D, from: Vector3, at: Vector3, path: String) -> void:
	# Say what the frame holds, so a review can tell a hidden part from a dark one.
	for car in root.find_children("*", "Vehicle", true, false):
		var d := (car as Node).get_node_or_null(CarDetail.NODE_NAME) as CarDetail
		var sh := (car as Node).get_node_or_null("Shocks") as Node3D
		var under := (car as Node).find_child(Undercarriage.NODE_NAME, true, false) as Node3D
		print("  %s: detail %s, shocks %s, underside %s" % [car.name, "on" if d != null and d.on else "off",
			"shown" if sh != null and sh.visible else "absent" if sh == null else "hidden",
			"shown" if under != null and under.visible else "hidden" if under != null else "none"])
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
