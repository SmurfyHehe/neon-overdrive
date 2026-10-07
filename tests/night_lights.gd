extends SceneTree

# Night lights (2026-10-07): traffic tail lamps, brake lamps, distance flares
# and the median barrier reflectors, seen through the real renderer (no
# --headless: the dummy renderer compiles no shaders and draws nothing).
#
# Three stopped N1s up the road from a camera at eye height just ahead of the
# player, 25, 90 and 200 m away in lanes 0-2 (so none hides another), plus
# the barrier on every chunk. Checks:
#   - the lamp and reflector shaders compile (no logged errors);
#   - each car's tail lamps make at least twice the red light of the same
#     spot with the night-lights setting at 0 at 90 and 200 m (at 0 a car
#     out there is a pixel or nothing), 1.3x at 25 m;
#   - brake lamps on make 20% more red light than running lamps, at 90 m;
#   - the reflectors add amber to the barrier's line at 60 m.
# Writes the frames to user://night_lights/ for judging by eye.
#
# Run: <godot> --path . -s res://tests/night_lights.gd

const Harness := preload("res://tests/traffic_harness.gd")

const DISTS := [25.0, 90.0, 200.0]

var fails: Array[String] = []
var logger := Harness.ErrorCounter.new()
var game: Node
var cam: Camera3D

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _initialize() -> void:
	OS.add_logger(logger)
	game = Harness.boot(self, 0, 300.0, 11)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	# Every chunk gets the barrier, so the reflectors are in view.
	for c in game.get("chunk_pool"):
		(c.root.get_node(^"Barrier") as MeshInstance3D).visible = true
	var p: PlayerCar = game.get("player")
	Harness.move_player_to_lane(p, Harness.lane_x(3))
	var cars: Array[TrafficCar] = []
	for k in DISTS.size():
		var d: float = DISTS[k]
		var car := TrafficCar.new()
		car.kind = "n1_commuter"
		car.build = "stock"
		car.color = NpcCarBuilder.PAINTS[2][0]   # near-black: only the lamps show
		car.target_speed = 0.0
		game.add_child(car)
		car.place(Harness.lane_x(2 - k), -1.0, p.global_position.z - float(d), car.rest_y, 0.0)
		cars.append(car)
	for i in 120:
		await physics_frame

	cam = Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.global_position = Vector3(Harness.lane_x(3), 1.2, p.global_position.z - 3.0)
	cam.look_at(cam.global_position + Vector3(0.0, -0.01, -1.0))
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://night_lights"))

	# Stopped cars hold the brake: lamps on. Running level first.
	for car in cars:
		NpcCarBuilder.set_lamps(car.chassis_visual, 0.0, false)
	TrafficSettings.set_light_glow(0.0)
	var off := await _shot("glow0")
	TrafficSettings.set_light_glow(1.0)
	var on := await _shot("glow1")
	for k in cars.size():
		var spot := _tail_spot(cars[k])
		var a := _red(off, spot)
		var b := _red(on, spot)
		print("night_lights: car at %3.0f m, tail red %.3f with the setting at 0, %.3f at 1" % [DISTS[k], a, b])
		_check(b > a + 0.05, "car at %.0f m: tail lamps no brighter with night lights on (%.3f vs %.3f)" % [DISTS[k], b, a])
		# Up close the lamp itself shows at 0 too; past 50 m it is a pixel or nothing.
		var want := 1.3 if DISTS[k] < 50.0 else 2.0
		_check(b > a * want, "car at %.0f m: tail lamps under %.1fx the red light they make without night lights (%.3f vs %.3f)" % [DISTS[k], want, b, a])

	NpcCarBuilder.set_lamps(cars[1].chassis_visual, 1.0, false)
	var brake := await _shot("brake")
	var spot1 := _tail_spot(cars[1])
	var r0 := _red(on, spot1)
	var r1 := _red(brake, spot1)
	print("night_lights: car at 90 m, tail red %.3f running, %.3f braking" % [r0, r1])
	_check(r1 > r0 * 1.2, "brake lamps at 90 m not 20%% brighter than running lamps (%.3f vs %.3f)" % [r1, r0])

	NpcCarBuilder.set_lamps(cars[1].chassis_visual, 1.0, true)
	await _shot("hazard")

	# A reflector 60 m out: the dot nearest that distance on the barrier.
	var z := p.global_position.z - 60.0
	var zr := floorf(z / RoadChunkBuilder.REFLECTOR_SPACING) * RoadChunkBuilder.REFLECTOR_SPACING + RoadChunkBuilder.REFLECTOR_SPACING / 2.0
	var rp := Vector3(0.0, RoadChunkBuilder.BARRIER_Y + RoadChunkBuilder.BARRIER_H / 2.0 + 0.03, zr)
	var best := Vector2(-1, -1)
	var amber_on := 0.0
	var amber_off := 0.0
	for dz in [0.0, 5.0, -5.0, 2.5, -2.5]:
		var s := cam.unproject_position(rp + Vector3(0, 0, dz))
		var v1 := _amber(on, s)
		if v1 > amber_on:
			amber_on = v1
			amber_off = _amber(off, s)
			best = s
	print("night_lights: barrier reflector ~60 m, amber %.3f with the setting at 0, %.3f at 1 (pixel %s)" % [amber_off, amber_on, best])
	_check(amber_on > amber_off + 0.05, "barrier reflectors add nothing at 60 m (%.3f vs %.3f)" % [amber_on, amber_off])
	_finish()

## Screen position of the centre between the car's two tail flares.
func _tail_spot(car: TrafficCar) -> Vector2:
	var m := NpcCarBuilder.body_mesh(car.kind, car.build)
	for i in m.get_surface_count():
		if m.surface_get_name(i) == "flare":
			var v: PackedVector3Array = m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			var body := car.chassis_visual.get_node(^"Body") as Node3D
			# Left lamp: the nearer one to the lane's left edge, either is fine.
			return cam.unproject_position(body.to_global(v[0]))
	return Vector2(-1, -1)

func _shot(name: String) -> Image:
	for i in 6:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := "user://night_lights/%s.png" % name
	img.save_png(path)
	print("night_lights: ", ProjectSettings.globalize_path(path))
	return img

## Red light in a 9x9 box round `at`: the sum over its pixels of how far red
## stands above the other two (a bigger or brighter lamp both raise it).
func _red(img: Image, at: Vector2) -> float:
	var sum := 0.0
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var x := int(at.x) + dx
			var y := int(at.y) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			sum += maxf(c.r - maxf(c.g, c.b), 0.0)
	return sum

## Brightest amber-ish value (red and green up, blue down) in a 7x7 box.
func _amber(img: Image, at: Vector2) -> float:
	var best := 0.0
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var x := int(at.x) + dx
			var y := int(at.y) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			best = maxf(best, minf(c.r, c.g * 1.4) - c.b)
	return best

func _finish() -> void:
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("night_lights: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
