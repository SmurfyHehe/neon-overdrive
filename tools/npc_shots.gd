extends SceneTree

# Renders the traffic cars (NpcCarBuilder) in the game's night scene, for
# judging them by eye: every build of every car parked on the road in a row,
# seen from the 3/4 front, the 3/4 rear and the chase cam. Needs the real
# renderer (no --headless). Writes PNGs to user://npc_shots/.
#
#   <godot> --path . -s res://tools/npc_shots.gd [-- kind]

const Harness := preload("res://tests/traffic/traffic_harness.gd")

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var only := ""
	for a in OS.get_cmdline_user_args():
		only = a
	var p: PlayerCar = game.get("player")
	var z0 := p.global_position.z - 14.0
	var cars: Array[TrafficCar] = []
	var x := Harness.lane_x(0) - 1.0
	for kind in NpcCarBuilder.KINDS:
		if only != "" and kind != only:
			continue
		for build in NpcCarBuilder.builds(kind):
			var car := TrafficCar.new()
			car.kind = kind
			car.build = build
			car.color = NpcCarBuilder.pick_paint(kind, build)
			game.add_child(car)
			car.place(x, -1.0, z0, car.rest_y, 0.0)
			car.target_speed = 0.0
			cars.append(car)
			x += 3.2
	for i in 120:
		await physics_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://npc_shots"))
	var mid := (cars[0].global_position + cars[-1].global_position) / 2.0
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	var views := {
		"front34": mid + Vector3(-7.0, 2.2, -9.0),
		"rear34": mid + Vector3(-6.0, 2.0, 9.0),
		"side": mid + Vector3(-12.0, 1.4, 0.0),
	}
	for v in views:
		cam.global_position = views[v]
		cam.look_at(mid + Vector3(0.0, 0.7, 0.0))
		cam.make_current()
		for i in 10:
			await process_frame
		var path := "user://npc_shots/%s_%s.png" % [only if only != "" else "all", v]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("npc_shots: ", ProjectSettings.globalize_path(path))
	quit(0)
