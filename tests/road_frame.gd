extends SceneTree

# Road space (#37 step R1): RoadFrame's conversions agree with each other, so
# traffic, the chunk pool and the benchmark bot can reason in road space
# (across / along the road) instead of world axes. Headless, no game scene:
# - unroll(roll(u)) == u and roll(unroll(p)) == p, to 1 mm, over the whole
#   floating-origin range and both sides of the road
# - pose(x, y, z, yaw) lands at roll(x, y, z), and its basis read back in road
#   space points down the road (yaw 0) or against it (yaw PI, oncoming)
# - dir_to_road keeps a direction's length
# - while the road is straight (step R1) every conversion is the identity, so
#   nothing that moved onto RoadFrame can have changed behaviour
# Step R3 (curves) keeps the first three checks and drops the last.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/road_frame.gd

const EPS := 0.001
const STRAIGHT := true  # step R1; R3 turns this off

var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var xs := [-16.0, -RoadChunkBuilder.lane_offset(2), 0.0, RoadChunkBuilder.lane_offset(1), 16.0]
	var n := 0
	for z in range(-1200, 1201, 37):
		for x in xs:
			for y in [-0.124, 0.0, 2.0]:
				var u := Vector3(x, y, float(z))
				var w := RoadFrame.roll(u)
				_check(RoadFrame.unroll(w).distance_to(u) < EPS, "unroll(roll(%s)) = %s" % [u, RoadFrame.unroll(w)])
				_check(RoadFrame.roll(RoadFrame.unroll(w)).distance_to(w) < EPS, "roll(unroll(%s)) drifts" % w)
				if STRAIGHT:
					_check(w == u, "straight road: roll(%s) = %s, should be the identity" % [u, w])
				n += 1

	for z in [-900.0, -25.0, 0.0, 480.0]:
		for yaw in [0.0, PI]:
			var t := RoadFrame.pose(RoadChunkBuilder.lane_offset(0), -0.124, z, yaw)
			_check(t.origin.distance_to(RoadFrame.roll(Vector3(RoadChunkBuilder.lane_offset(0), -0.124, z))) < EPS, "pose origin off at z %.0f" % z)
			var b := RoadFrame.basis_to_road(z, t.basis)
			var heading := b.z.z  # forward is -basis.z and the road runs to -z: 1 = down the road
			var want := 1.0 if yaw == 0.0 else -1.0
			_check(absf(heading - want) < EPS, "pose yaw %.2f at z %.0f reads back heading %.3f, want %.0f" % [yaw, z, heading, want])
			_check(absf(b.y.y - 1.0) < EPS, "pose not upright in road space at z %.0f" % z)
			if STRAIGHT:
				_check(t.basis.is_equal_approx(Basis(Vector3.UP, yaw)), "straight road: pose basis should be a plain yaw")
		var v := Vector3(3.0, -1.0, -30.0)
		_check(absf(RoadFrame.dir_to_road(z, v).length() - v.length()) < EPS, "dir_to_road changed a length at z %.0f" % z)
		if STRAIGHT:
			_check(RoadFrame.dir_to_road(z, v) == v and RoadFrame.heading_at(z) == 0.0, "straight road: directions should pass through")

	print("road_frame: %d points, %d failures" % [n, fails])
	quit(1 if fails > 0 else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		if fails <= 20:
			printerr("FAIL: " + msg)
