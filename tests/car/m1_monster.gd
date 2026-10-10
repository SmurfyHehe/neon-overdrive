extends SceneTree
# Monster truck (special vehicles S1, Roy 2026-10-10), a real headless run:
#   - boots as the player's car (NEON_CAR=m1_monster) with its own body, wheels
#     at M1MonsterBuilder.CFG, the truck's CarSpec (3.5 t, 750 Nm), no errors;
#   - settles upright with the chassis where the body is drawn, and the wheels
#     are 0.85 m;
#   - a 15 s throttle drive down the lane: moves, finite, upright, on the road;
#   - crab steer (Ctrl, SpecialMoves): at the same speed and steering input the
#     truck yaws far less and slides sideways more (a bigger angle between where
#     it points and where it goes) than with crab steer off.
# Prints the numbers it measured, so the report can quote them.
#
# Run: <godot> --headless --fixed-fps 120 --path . -s res://tests/car/m1_monster.gd
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RATE := 120
const DRIVE_SECS := 15.0
const KIND := "m1_monster"

var logger := Harness.ErrorCounter.new()
var fails := 0
var game: Node
var p: PlayerCar
var lane_x := 0.0
var probe_steer := 0.0     # used while probing is true: the steering input, lane keeping off
var probing := false
var throttle_cmd := 1.0
var hold_kmh := -1.0       # >0: throttle follows to hold this speed

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_run.call_deferred()

func _driver(c: Vehicle) -> void:
	if probing:
		c.steering_input = probe_steer
	else:
		# Lane keeping: +steering_input turns left (+yaw), so too far right steers left.
		var u := RoadFrame.unroll(c.global_position)
		var side_v := RoadFrame.dir_to_road(u.z, c.linear_velocity).x
		c.steering_input = clampf((u.x - lane_x) * 0.10 + side_v * 0.3, -0.4, 0.4)
	c.handbrake_input = 0.0
	var throttle := throttle_cmd
	var brake := 0.0
	if hold_kmh > 0.0:
		var kmh: float = c.current_speed() * 3.6
		throttle = 1.0 if kmh < hold_kmh else 0.0
		brake = 0.5 if kmh > hold_kmh + 3.0 else 0.0   # the truck coasts a long way: brake down to speed
	c.brake_input = brake
	c.throttle_input = throttle

func _run() -> void:
	OS.set_environment("NEON_CAR", KIND)
	OS.set_environment("NEON_CURVES", "0")  # straight road, so yaw is the truck's own
	OS.set_environment("NEON_HILLS", "0")
	_check(PlayerCar.chassis_kind() == KIND, "NEON_CAR did not pick %s" % KIND)
	var errors_before := logger.errors.size()
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE * 3:
		await physics_frame
	p = game.get("player")
	_check(p != null, "no player")
	if p == null:
		_finish()
		return
	for n in game.get_children():
		if n is SpecialRunEnd:
			n.queue_free()  # a flip restarts the scene; a -s test has no scene to reload
	# body and spec
	var spec := CarSpec.player_spec(KIND)
	_check(absf(float(p.spec.max_torque) - 750.0) < 0.5 and absf(float(p.spec.vehicle_mass) - 3500.0) < 0.5,
		"spec is %s Nm / %s kg" % [p.spec.max_torque, p.spec.vehicle_mass])
	_check(p.chassis_visual != null and String(p.chassis_visual.get_meta("kind", "")) == KIND, "the body is not the truck's")
	var cfg := PlayerCar.wheel_config(KIND)
	_check(absf(p.front_tire_radius - 0.85) < 0.001, "wheel radius %.3f" % p.front_tire_radius)
	print("m1_monster: settled y = %.3f, up %.3f" % [p.global_position.y, p.global_transform.basis.y.y])
	_check(p.global_transform.basis.y.y > 0.99, "does not stand upright")
	for w in p.wheel_array:
		var hub := p.to_local(w.wheel_node.global_position)
		_check(absf(absf(hub.x) - float(cfg.wheel_x)) < 0.02 and absf(absf(hub.z) - float(cfg.axle_z)) < 0.02,
			"wheel hub at %s, want x +-%.2f z +-%.2f" % [hub, cfg.wheel_x, cfg.axle_z])
		_check(absf(hub.y - 0.0) < 1.2, "wheel hub y %.2f" % hub.y)
	var tip_ok := (p.chassis_visual.get_meta("exhaust_tips") as Array).size() == 2
	_check(tip_ok, "exhaust tips")

	# straight drive: PD on the lane offset
	var lane := RoadFrame.unroll(p.global_position).x
	lane_x = lane
	var z0 := RoadFrame.unroll(p.global_position).z
	p.driver = _driver
	var t := 0.0
	var vmax := 0.0
	var max_err := 0.0
	var t60 := -1.0
	while t < DRIVE_SECS:
		await physics_frame
		t += 1.0 / RATE
		vmax = maxf(vmax, p.current_speed())
		if t60 < 0.0 and p.current_speed() >= 60.0 / 3.6:
			t60 = t
		if t > 3.0:
			max_err = maxf(max_err, absf(RoadFrame.unroll(p.global_position).x - lane))
	var travel := z0 - RoadFrame.unroll(p.global_position).z
	print("m1_monster: 0-60 km/h %.1f s, top %.0f km/h in %.0f s, %.0f m, gear %d, lane error %.2f m" % [
		t60, vmax * 3.6, DRIVE_SECS, travel, p.current_gear, max_err])
	_check(travel > 60.0, "moved only %.0f m" % travel)
	_check(vmax * 3.6 > 50.0, "only reached %.0f km/h" % (vmax * 3.6))
	_check(Harness.finite(p), "non-finite state after the drive")
	_check(p.global_transform.basis.y.y > 0.9, "not upright after the drive (%.2f)" % p.global_transform.basis.y.y)
	_check(max_err < 2.5, "wandered %.2f m off its lane" % max_err)

	# crab steer: same speed, same steering, rear follows the front or not
	var normal := await _turn_probe(false)
	var crab := await _turn_probe(true)
	print("m1_monster: steer 0.35 at 40 km/h, 1.5 s -> normal: yaw %.2f rad/s, slip %.1f deg, %.1f m sideways | crab: yaw %.2f rad/s, slip %.1f deg, %.1f m sideways" % [
		normal.yaw, normal.slip, normal.side, crab.yaw, crab.slip, crab.side])
	_check(absf(crab.yaw) < 0.75 * absf(normal.yaw), "crab yaw %.2f is not well below normal %.2f" % [crab.yaw, normal.yaw])
	_check(absf(crab.slip) > absf(normal.slip) + 3.0, "crab slip %.1f deg is not above normal %.1f" % [crab.slip, normal.slip])
	_check(Harness.finite(p) and p.global_transform.basis.y.y > 0.8, "unstable after the crab probes")

	_check(logger.errors.size() == errors_before, "%d error(s): %s" % [logger.errors.size() - errors_before, logger.errors.slice(errors_before)])
	p.driver = Callable()
	game.queue_free()
	await physics_frame
	OS.set_environment("NEON_CAR", "")
	_finish()

## Holds ~40 km/h in its lane, then steers 0.35 for 1.5 s with lane keeping off
## (crab on or off) and returns the yaw rate and the slip angle (car heading
## vs velocity) over the last 0.7 s, and how far it moved sideways.
func _turn_probe(crab_on: bool) -> Dictionary:
	var moves: SpecialMoves = p.get_node("SpecialMoves")
	moves.forced = false
	probing = false
	hold_kmh = 40.0
	for i in RATE * 12:
		await physics_frame
	var u0 := RoadFrame.unroll(p.global_position)
	probing = true
	probe_steer = 0.35
	moves.forced = crab_on
	var yaws := []
	var slips := []
	var steps := int(RATE * 1.5)
	for i in steps:
		await physics_frame
		if i > steps - int(RATE * 0.7):
			var v := p.linear_velocity
			if v.length() > 3.0:
				yaws.append(p.angular_velocity.y)
				slips.append(rad_to_deg(atan2(v.dot(p.global_transform.basis.x), v.dot(-p.global_transform.basis.z))))
	var side := absf(RoadFrame.unroll(p.global_position).x - u0.x)
	probing = false
	moves.forced = false
	for i in RATE * 3:
		await physics_frame
	return {"yaw": _mean(yaws), "slip": _mean(slips), "side": side}

func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / a.size()

func _finish() -> void:
	print("m1_monster: %d warning(s)" % logger.warnings)
	if fails == 0:
		print("PASS m1_monster")
	else:
		print("FAIL m1_monster: %d check(s)" % fails)
	quit(0 if fails == 0 else 1)
