extends SceneTree

# Renders THE player's car as the game builds it (PlayerCar, the pause menu's
# Car page path: NEON_CAR=<kind> picks the car), parked in the night scene,
# from the 3/4 front and the 3/4 rear, for judging its default look by eye
# (PlayerCars.LOOK, the temporary kit until the mod tree). Needs the real
# renderer (no --headless). Writes PNGs to user://player_shots/.
#
#   NEON_CAR=p2_hothatch <godot> --path . -s res://tools/player_shots.gd
#
# One car per run: the player is built once at boot. tools/npc_shots.gd is the
# traffic-car equivalent (every build in a row).

const Harness := preload("res://tests/traffic/traffic_harness.gd")

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _shot(cam: Camera3D, at: Vector3, look: Vector3, name: String) -> void:
	cam.global_position = at
	cam.look_at(look)
	cam.make_current()
	for i in 12:
		await process_frame
	var path := "user://player_shots/%s.png" % name
	root.get_viewport().get_texture().get_image().save_png(path)
	print("player_shots: wrote ", ProjectSettings.globalize_path(path))

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	# Hold the car still with the lights on, then let the springs settle.
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
	for i in 120:
		await physics_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://player_shots"))
	var kind: String = p.chassis_visual.get_meta("kind", PlayerCar.chassis_kind())
	var build: String = p.build
	var c := p.global_position
	var fwd: Vector3 = -p.global_transform.basis.z
	var right: Vector3 = p.global_transform.basis.x
	var look := c + Vector3(0.0, 0.55, 0.0)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	await _shot(cam, c + fwd * 5.2 - right * 4.2 + Vector3(0, 1.6, 0), look, "%s_%s_front34" % [kind, build])
	await _shot(cam, c - fwd * 5.2 + right * 4.2 + Vector3(0, 1.6, 0), look, "%s_%s_rear34" % [kind, build])
	await _shot(cam, c - right * 7.5 + Vector3(0, 0.9, 0), look, "%s_%s_side" % [kind, build])
	print("player_shots: %s wears build %s, rim %s" % [kind, build, String(PlayerCars.look_for(kind).rim)])
	quit(0)
