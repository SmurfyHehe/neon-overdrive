extends SceneTree

# Renders the dash bobble head (interiors step 10, 2026-10-11) for judging by
# eye: the dash from the driver's seat (the game's own cockpit camera) with the
# pick on the passenger side, then the same view with the head thrown outward
# by a hard corner, and a close-up of every figure from the driver's eye side.
# Needs the real renderer (no --headless). Writes PNGs to user://bobble_shots/.
#
#   <godot> --path . -s res://tools/bobble_shots.gd
# BOBBLE=<id> picks the figure for the two dash views (default ledger);
# BOBBLE_ALL=1 also writes one close-up per figure.

var game: Node

func _initialize() -> void:
	AudioSettings.path = "user://bobble_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	var pick := OS.get_environment("BOBBLE")
	OS.set_environment("NEON_CABIN_MODS", "trinket=none;bobble=%s" % (pick if pick != "" else "ledger"))
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run.call_deferred()

func _snap(path: String) -> void:
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	for i in 60:
		await physics_frame
	var dir := ProjectSettings.globalize_path("user://bobble_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	print("bobble: %s, %d tris, at %s" % [frame.bobble.figure, frame.bobble.triangle_count(), frame.bobble.position])
	await _snap("%s/dash_at_rest.png" % dir)
	# a hard right-hand corner: the spring is driven directly so the lean is
	# there for the frame (the real car does this from its own acceleration)
	frame.bobble.set_physics_process(false)
	for i in 40:
		frame.bobble.step(1.0 / 60.0, Vector3(7.0, 0.0, 0.0))
	await _snap("%s/dash_corner.png" % dir)
	print("bob in the corner: %s" % frame.bobble.bob)
	if OS.get_environment("BOBBLE_ALL") == "1":
		for id in BobbleFigures.IDS:
			if id == BobbleFigures.NONE:
				continue
			CabinMods.set_bobble(PlayerCar.chassis_kind(), id)
			frame.bobble.set_figure(id)
			frame.bobble.bob = Vector2.ZERO
			frame.bobble.step(0.0, Vector3.ZERO)
			var shot := Camera3D.new()
			shot.fov = 30.0
			shot.near = 0.03
			root.add_child(shot)
			var at: Vector3 = p.global_transform * (frame.bobble.position + Vector3(0.0, 0.035, 0.0))
			shot.global_position = at + p.global_transform.basis * Vector3(0.0, 0.03, 0.3)
			shot.look_at(at)
			shot.make_current()
			await _snap("%s/figure_%s.png" % [dir, id])
			shot.queue_free()
	print("wrote ", dir)
	quit(0)
