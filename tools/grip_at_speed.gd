extends SceneTree

# Cornering grip and body clearance at speed, for comparing suspension or
# aero changes on one car (issue #538, the coupe's downforce and springs).
#
# The real Game.tscn on a flat straight road, no traffic. For each speed the
# car is built from its stock spec (plus GRIP_SET overrides), set going in the
# third lane with the speed held by a push at the centre of mass, left to
# settle, then steered left with a wheel input that ramps to STEER in 0.3 s
# and holds. It prints:
# - the body's clearance cruising straight (lowest point of the body shape
#   above the road) and the spring travel left front and rear,
# - the peak sideways acceleration in the turn (averaged over 0.1 s), which
#   is the grip the tyres found at that speed,
# - how far the body rolled at that peak, and the lowest clearance in the turn.
#
#   [GRIP_CAR=p1_coupe] [GRIP_SET=front_resting_ratio=0.4,rear_resting_ratio=0.4]
#   [GRIP_SPEEDS=100,200,250,300] [GRIP_STEER=0.2]
#     <godot> --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tools/grip_at_speed.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 120
const LANE := 2

var game: Node
var kind := "p1_coupe"
var overrides := {}
var speeds: Array = [100.0, 150.0, 200.0, 250.0, 300.0]
var steer_to := 0.2

func _initialize() -> void:
	Engine.physics_ticks_per_second = RATE
	if OS.get_environment("GRIP_CAR") != "":
		kind = OS.get_environment("GRIP_CAR")
	for part in OS.get_environment("GRIP_SET").split(",", false):
		var kv := part.split("=")
		overrides[kv[0]] = float(kv[1])
	if OS.get_environment("GRIP_SPEEDS") != "":
		speeds = []
		for part in OS.get_environment("GRIP_SPEEDS").split(","):
			speeds.append(float(part))
	if OS.get_environment("GRIP_STEER").is_valid_float():
		steer_to = float(OS.get_environment("GRIP_STEER"))
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_ROAD", "endless")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_LAYOUT", "0")
	game = Harness.boot(self, 0, 300.0, 777)
	_run.call_deferred()

func _run() -> void:
	for i in RATE:
		await physics_frame
	var first: PlayerCar = game.get("player")
	first.freeze = true
	first.process_mode = Node.PROCESS_MODE_DISABLED
	first.visible = false
	var rescue: Node = game.get("rescue")
	if rescue != null:
		rescue.set("enabled", false)
	var was_selected := PlayerCars.selected
	PlayerCars.selected = kind
	print("grip: %s %s, steer input %.2f" % [kind, str(overrides) if not overrides.is_empty() else "stock", steer_to])
	var at := first.global_position
	for kmh in speeds:
		at = await _pass(kmh, at)
	PlayerCars.selected = was_selected
	game.set("player", first)
	quit(0)

func _pass(kmh: float, from: Vector3) -> Vector3:
	var car := PlayerCar.new()
	car.sim_only = true
	var spec := CarSpec.player_spec(kind)
	for path in overrides:
		TuneParams.set_value(spec, path, overrides[path])
	car.spec = spec
	var lane := Harness.lane_x(LANE)
	car.position = Vector3(lane, 0.6, from.z - 30.0)
	game.add_child(car)
	Harness.launch_player(car, 0.0)
	game.set("player", car)
	var steer := [0.0, true]   # wheel input, hold the lane
	var v := kmh / 3.6
	car.driver = func(c: Vehicle) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 1.0
		c.steering_input = 0.0
	for i in RATE * 2:
		await physics_frame
	var rest := _clearance(car)
	Harness.launch_player(car, v)
	car.driver = func(c: Vehicle) -> void:
		if steer[1]:
			c.steering_input = TrafficCar.lane_steer(c, lane - c.linear_velocity.x * Harness.LAT_DAMP_T, -1.0, 2.5, Harness.PLAYER_UNDERSTEER_FF)
		else:
			c.steering_input = steer[0]
		c.throttle_input = 0.25
		c.brake_input = 0.0
		c.handbrake_input = 0.0
		var fwd := c.linear_velocity.normalized() if c.linear_velocity.length() > 1.0 else -c.global_transform.basis.z
		c.apply_central_force(fwd * clampf((v - c.linear_velocity.length()) * 4.0, -6.0, 12.0) * c.mass)
	# cruise: settle, then measure
	var cruise := INF
	var travel := [INF, INF]
	var contacts := 0
	for i in RATE * 5:
		await physics_frame
		if i > RATE * 3:
			cruise = minf(cruise, _clearance(car))
			for k in car.wheel_array.size():
				var w = car.wheel_array[k]
				var axle := 0 if k < 2 else 1
				travel[axle] = minf(travel[axle], w.spring_current_length)
		if _touches_road(car):
			contacts += 1
	# the turn: ramp the wheel left, hold, watch the sideways acceleration
	steer[1] = false
	var vx: Array[float] = []
	var peak := 0.0
	var roll_at_peak := 0.0
	var low := INF
	var t := 0
	while t < RATE * 2:
		await physics_frame
		t += 1
		steer[0] = steer_to * clampf(float(t) / (RATE * 0.3), 0.0, 1.0)
		# sideways = across the car's own path, from the change of velocity
		vx.append(car.linear_velocity.x)
		low = minf(low, _clearance(car))
		if _touches_road(car):
			contacts += 1
		if vx.size() > 12:
			var a := absf(vx[-1] - vx[-13]) / (12.0 / RATE)
			if a > peak:
				peak = a
				roll_at_peak = rad_to_deg(asin(clampf(car.global_transform.basis.x.y, -1.0, 1.0)))
		if car.global_position.x < 2.5:
			break  # the centre barrier is near
	print("grip: %3.0f km/h  cruise clearance %5.1f cm (rest %.1f), spring left front %4.1f cm rear %4.1f cm | peak sideways %5.2f m/s2 (%.2f g), roll %4.1f deg, lowest in turn %5.1f cm, road contact %d ticks" % [
		kmh, cruise * 100.0, rest * 100.0, float(travel[0]) * 100.0, float(travel[1]) * 100.0, peak, peak / 9.81, absf(roll_at_peak), low * 100.0, contacts])
	var end := car.global_position
	car.driver = Callable()
	car.queue_free()
	await physics_frame
	return end

func _touches_road(v: Vehicle) -> bool:
	for b in v.get_colliding_bodies():
		var n := String(b.name)
		if not (n.begins_with("Boundary") or n.begins_with("Building") or n == "BarrierCol" or n == "CushionCol"):
			return true
	return false

func _clearance(v: Vehicle) -> float:
	var col: CollisionShape3D
	for ch in v.get_children():
		if ch is CollisionShape3D:
			col = ch
	var pts: PackedVector3Array = (col.shape as ConvexPolygonShape3D).points
	var space := v.get_world_3d().direct_space_state
	var low := INF
	for pt in pts:
		var w := v.global_transform * (col.position + pt)
		var q := PhysicsRayQueryParameters3D.create(w + Vector3(0, 3, 0), w - Vector3(0, 3, 0), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			low = minf(low, w.y - hit.position.y)
	return low
