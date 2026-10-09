extends SceneTree

# The traffic cars (stage B step 5, NpcCarBuilder): every car, every build.
#
# Model checks, per build:
#   - the body's bounding box is the sheet's length and height (fleet.json dims,
#     3 cm, stock build) and at least its body width (the mirrors stick out past it);
#   - triangles within the 4,000 traffic budget, and 8 draw calls;
#   - two tail flares (one per side), behind the rear axle;
#   - no magenta or cyan in any vertex colour or paint (tests/core/palette.gd rule);
#   - exhaust tips behind the rear axle, 4 sticker slot placements on the body.
# Drive checks, per car (stock build), on the game's road with nothing else
# about, the car's own controller holding lane 1 at 120 km/h:
#   - settled chassis height within 1 cm of KINDS rest_y, and each wheel hub
#     within 3 cm of where the sheet draws it (wheels fill the arches);
#   - 0-100 km/h and the speed after 30 s (it must reach 110 km/h: the fastest
#     traffic lane cruises at 115 +- 2.5);
#   - lane error after the launch under 0.3 m;
#   - stopping from 100 km/h on its own brakes (target speed 0);
#   - brake lamps: off while cruising, on while it brakes to that stop.
# Prints every number so the CarSpec choices are visible in the run log.
#
# Run: <godot> --headless --fixed-fps 120 --path . -s res://tests/traffic/npc_cars.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Palette := preload("res://tests/core/palette.gd")

const RATE := 120
const CRUISE := 120.0 / 3.6

var fails: Array[String] = []
var logger := Harness.ErrorCounter.new()
var game: Node

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _initialize() -> void:
	OS.add_logger(logger)
	var fleet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/design/fleet/fleet.json"))
	var dims := {}
	for c in fleet.cars:
		dims[c.id] = c.dims
	for kind in NpcCarBuilder.KINDS:
		for build in NpcCarBuilder.builds(kind):
			_model_checks(kind, build, dims[kind])
	game = Harness.boot(self, 0, 300.0, 7, 1.0e6)
	_run.call_deferred()

func _model_checks(kind: String, build: String, d: Dictionary) -> void:
	var tag := "%s/%s" % [kind, build]
	var mesh := NpcCarBuilder.body_mesh(kind, build)
	var aabb := mesh.get_aabb()
	for w in [false, true]:
		var wm := NpcCarBuilder.wheel_mesh(kind, build, w)
		var hub: Vector3 = NpcCarBuilder.KINDS[kind].data.BUILDS[build].wheels[1 if w else 0].hub
		aabb = aabb.merge(AABB(wm.get_aabb().position + hub, wm.get_aabb().size))
	var tris := NpcCarBuilder.triangle_count(kind, build)
	var calls := NpcCarBuilder.draw_call_count(kind, build)
	print("npc_cars: %-22s %.2f x %.2f x %.2f m (sheet %.2f x %.2f x %.2f), %d tris, %d draw calls" % [
		tag, aabb.size.z, aabb.size.x, aabb.size.y, d.length, d.width_body, d.height, tris, calls])
	# The sheet's sizes are the stock build's; variant kits (a sport bumper, the
	# taxi sign, a sports bar) may add a little.
	if build == "stock":
		_check(absf(aabb.size.z - float(d.length)) < 0.03, "%s is %.3f m long, the sheet says %.2f" % [tag, aabb.size.z, d.length])
		_check(absf(aabb.size.y - float(d.height)) < 0.03, "%s is %.3f m tall, the sheet says %.2f" % [tag, aabb.size.y, d.height])
	else:
		_check(absf(aabb.size.z - float(d.length)) < 0.10, "%s is %.3f m long, the sheet says %.2f" % [tag, aabb.size.z, d.length])
	_check(aabb.size.x >= float(d.width_body) - 0.01, "%s is %.3f m wide, narrower than the sheet's %.2f body" % [tag, aabb.size.x, d.width_body])
	_check(tris <= 4000, "%s has %d triangles, over the 4,000 traffic budget" % [tag, tris])
	_check(calls == 8, "%s takes %d draw calls, not 8" % [tag, calls])
	for i in mesh.get_surface_count():
		var cols: PackedColorArray = mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
		for c in cols:
			var bad := Palette.is_bad(c.linear_to_srgb())
			if bad != "":
				fails.append("%s has a %s vertex colour %s" % [tag, bad, c.linear_to_srgb().to_html(false)])
				break
	var paints: Array = NpcCarBuilder.PAINTS.map(func(p): return p[0])
	paints.append_array(NpcCarBuilder.KINDS[kind].build_paint.values())
	for c in paints:
		_check(Palette.is_bad(c) == "", "%s paint %s is %s" % [tag, c.to_html(false), Palette.is_bad(c)])
	var flare := -1
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == "flare":
			flare = i
	_check(flare >= 0, "%s has no tail flare surface" % tag)
	if flare >= 0:
		var fv: PackedVector3Array = mesh.surface_get_arrays(flare)[Mesh.ARRAY_VERTEX]
		var rear_axle: float = NpcCarBuilder.KINDS[kind].axle_z
		_check(fv.size() == 12, "%s has %d flare vertices, not 12 (two quads)" % [tag, fv.size()])
		if fv.size() == 12:
			_check(fv[0].x * fv[6].x < 0.0, "%s tail flares are not one per side" % tag)
			_check(fv[0].z > rear_axle and fv[6].z > rear_axle, "%s tail flare ahead of the rear axle" % tag)
	var vis := NpcCarBuilder.chassis_visual(kind, build, Color.WHITE)
	var axle: float = NpcCarBuilder.KINDS[kind].axle_z
	for t in vis.get_meta("exhaust_tips"):
		_check(t.pos.z > axle, "%s has an exhaust tip ahead of the rear axle" % tag)
	_check((vis.get_meta("sticker_slots") as Array).size() == 5, "%s has %d sticker placements, not 5 (door mirrored)" % [tag, (vis.get_meta("sticker_slots") as Array).size()])
	vis.free()

func _run() -> void:
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	for kind in NpcCarBuilder.KINDS:
		await _drive(kind, p)
	_finish()

func _drive(kind: String, p: PlayerCar) -> void:
	var cfg := NpcCarBuilder.config(kind)
	var car := TrafficCar.new()
	car.kind = kind
	car.build = "stock"
	car.color = NpcCarBuilder.PAINTS[0][0]
	car.target_speed = 0.0
	game.add_child(car)
	var lane := Harness.lane_x(1)
	# The player rides along two lanes over so the road keeps being built round it.
	Harness.move_player_to_lane(p, Harness.lane_x(3))
	car.place(lane, -1.0, p.global_position.z - 15.0, car.rest_y, 0.0)
	for i in RATE * 3:
		await physics_frame
	var y := car.global_position.y
	print("npc_cars: %s settles at y = %.3f (KINDS rest_y %.3f)" % [kind, y, cfg.rest_y])
	_check(absf(y - float(cfg.rest_y)) < 0.01, "%s settles at y %.3f, KINDS rest_y is %.3f: update it" % [kind, y, cfg.rest_y])
	var lift := -float(cfg.rest_y)
	for w in car.wheel_array:
		var hub := car.to_local(w.wheel_node.global_position)
		var want_y := lift + float(cfg.wheel_r)
		_check(absf(hub.y - want_y) < 0.03 and absf(absf(hub.x) - float(cfg.wheel_x)) < 0.01,
			"%s wheel hub at %s, the sheet draws it at y %.3f, x +-%.2f" % [kind, hub, want_y, cfg.wheel_x])

	car.target_speed = CRUISE
	var t := 0.0
	var t100 := -1.0
	var max_err := 0.0
	var lamp_on_cruise := false
	p.driver = func(c: Vehicle) -> void:
		var ahead := c.global_position.z - car.global_position.z
		c.steering_input = TrafficCar.lane_steer(c, Harness.lane_x(3) - c.linear_velocity.x * Harness.LAT_DAMP_T, -1.0, 2.5)
		c.throttle_input = 1.0 if ahead > 20.0 else 0.0
		c.brake_input = 0.0 if ahead > 5.0 else 0.5
		c.handbrake_input = 0.0
	while t < 30.0:
		await physics_frame
		t += 1.0 / RATE
		var v := car.current_speed()
		if t100 < 0.0 and v >= 100.0 / 3.6:
			t100 = t
		if t > 10.0:
			max_err = maxf(max_err, absf(car.global_position.x - lane))
		if t > 29.0:
			lamp_on_cruise = lamp_on_cruise or _brake_lamp(car) > 0.5
	var v30 := car.current_speed()
	print("npc_cars: %s 0-100 km/h %.1f s, %.0f km/h after 30 s, lane error %.2f m, gear %d" % [
		kind, t100, Harness.kmh(v30), max_err, car.current_gear])
	_check(t100 > 0.0 and t100 < 16.0, "%s took %.1f s to 100 km/h (limit 16 s)" % [kind, t100])
	_check(Harness.kmh(v30) >= 110.0, "%s only reached %.0f km/h in 30 s" % [kind, Harness.kmh(v30)])
	_check(max_err < 0.3, "%s wandered %.2f m off its lane at speed" % [kind, max_err])
	_check(not lamp_on_cruise, "%s shows brake lamps while cruising" % kind)

	# Brake from 100 km/h: launch at 100, then ask for 0.
	car.target_speed = 100.0 / 3.6
	TrafficCar.set_moving(car, 100.0 / 3.6)
	for i in RATE:
		await physics_frame
	car.target_speed = 0.0
	var z0 := car.global_position.z
	t = 0.0
	var lamp_on_stop := false
	while car.current_speed() > 0.3 and t < 20.0:
		await physics_frame
		t += 1.0 / RATE
		lamp_on_stop = lamp_on_stop or _brake_lamp(car) > 0.5
	var dist := absf(car.global_position.z - z0)
	print("npc_cars: %s stops from 100 km/h in %.1f s, %.0f m (target-speed stop, not an emergency stop)" % [kind, t, dist])
	_check(t < 20.0, "%s did not stop within 20 s" % kind)
	_check(lamp_on_stop, "%s braked to a stop without brake lamps" % kind)
	_check(Harness.finite(car), "%s has non-finite state" % kind)
	_check(car.global_transform.basis.y.y > 0.95, "%s is not upright" % kind)
	p.driver = Callable()
	car.queue_free()
	await physics_frame

func _brake_lamp(car: TrafficCar) -> float:
	var mi := car.chassis_visual.get_node(^"Body") as MeshInstance3D
	return float(mi.get_instance_shader_parameter("brake"))

func _finish() -> void:
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("npc_cars: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
