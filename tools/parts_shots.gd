extends SceneTree

# Renders the wheels and brakes (CarParts) in the game's night scene for
# judging by eye: the player's front wheel cold and hot, a low rear view of
# the springs, and the four rim designs on parked cars. Needs the real
# renderer (no --headless). Writes PNGs to user://parts_shots/.
#
#   <godot> --path . -s res://tools/parts_shots.gd

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
	root.get_viewport().get_texture().get_image().save_png("user://parts_shots/%s.png" % name)
	print("parts_shots: wrote %s" % name)

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://parts_shots"))
	# Three parked cars wearing the other rim designs, with the parts set.
	var z0 := p.global_position.z - 14.0
	var x := Harness.lane_x(0) - 1.0
	var cars: Array[TrafficCar] = []
	for style in ["mesh", "dish", "steel"]:
		var car := TrafficCar.new()
		car.kind = "n1_commuter"
		car.build = "stock"
		car.color = NpcCarBuilder.pick_paint("n1_commuter", "stock")
		car.spec = CarSpec.clone_spec(CarSpec.npc_spec("n1_commuter"))
		car.spec["parts"] = "full"
		car.spec["rim"] = style
		game.add_child(car)
		car.place(x, -1.0, z0, car.rest_y, 0.0)
		car.target_speed = 0.0
		cars.append(car)
		x += 3.4
	for i in 120:
		await physics_frame
	var cam := Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	var fl: Wheel = p.front_left_wheel
	var hub: Vector3 = fl.wheel_node.global_position
	await _shot(cam, hub + Vector3(-1.6, 0.25, -0.9), hub, "p1_five_cold")
	p.health.brake_temp = 420.0
	await _shot(cam, hub + Vector3(-1.6, 0.25, -0.9), hub, "p1_five_hot")
	# Wheels turned hard left: the arch opens and the strut shows from behind.
	p.driver = func(c: PlayerCar) -> void:
		c.steering_input = -1.0
		c.throttle_input = 0.0
		c.brake_input = 1.0
	for i in 180:
		await physics_frame
	await _shot(cam, hub + Vector3(-1.1, -0.05, 1.4), hub + Vector3(0.25, 0.15, 0.0), "p1_spring_steered_rear")
	await _shot(cam, hub + Vector3(-1.3, 0.1, 0.9), hub + Vector3(0.3, 0.15, 0.0), "p1_spring_steered_side")
	p.driver = Callable()
	p.health.brake_temp = PowertrainHealth.AMBIENT_C
	var names := ["mesh", "dish", "steel"]
	for i in cars.size():
		var w: Wheel = cars[i].front_left_wheel
		var h: Vector3 = w.wheel_node.global_position
		await _shot(cam, h + Vector3(-1.6, 0.25, -0.9), h, "n1_" + names[i])
	# A hot cop-class disc, seen from behind like the mirrors would.
	(cars[0].get_node("CarParts") as CarParts).brake_temp = 420.0
	var rl: Wheel = cars[0].rear_left_wheel
	var rh: Vector3 = rl.wheel_node.global_position
	await _shot(cam, rh + Vector3(-1.4, 0.3, 1.6), rh, "n1_mesh_hot_rear")
	print("parts_shots: done, see %s" % ProjectSettings.globalize_path("user://parts_shots"))
	quit(0)
