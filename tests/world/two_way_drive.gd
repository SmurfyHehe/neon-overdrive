extends SceneTree

# The road goes both ways (the map, loop 1, 2026-10-10). On the curved, hilly
# loop, no traffic: drive 2 km down the road, turn round, drive 3 km back (past
# where the road starts, so across the lap's seam), then turn round ten times
# in a row a few seconds apart.
#
# - there is road under the car on every tick
# - the chunk pool keeps 300 m of road both sides of the car
# - never more than one chunk rebuilt in a frame, every one at least 300 m from
#   the car, and none that a live camera can see
# - turning round where the car stands rebuilds nothing, and gives the same
#   place on the loop with the other heading (RoadMap.where)
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/world/two_way_drive.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

const L := 50.0
const OUT := 2000.0
const BACK := 3000.0
const TURNS := 10
const TURN_SECS := 4

var game: Node
var phase := 0
var ticks := 0
var fails: Array[String] = []
var way := -1.0  # sign of travel on road-space z: -1 = down the road
var z0 := 0.0
var z_turn := 0.0
var turns := 0
var rebuilds := 0
var rebuilds_at_turns := 0
var seen_rebuilds := 0
var nearest_rebuild := 1 << 30
var most_in_a_frame := 0
var _frame := -1
var _in_frame := 0
var no_road := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_ROAD_SEED", "4242")
	OS.set_environment("NEON_LAYOUT", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)

func _on_chunk(chunk_root: Node3D, gap: int) -> void:
	rebuilds += 1
	nearest_rebuild = mini(nearest_rebuild, gap)
	if ViewGuard.chunk_seen(self, chunk_root):
		seen_rebuilds += 1
	var f := Engine.get_process_frames()
	_in_frame = _in_frame + 1 if f == _frame else 1
	_frame = f
	most_in_a_frame = maxi(most_in_a_frame, _in_frame)

func _where(p: PlayerCar) -> Dictionary:
	return RoadMap.where(RoadFrame.unroll(p.global_position).z, -p.global_transform.basis.z)

## Turns the car round where it stands, onto the other carriageway.
func _turn(p: PlayerCar) -> void:
	var before := _where(p)
	var had := rebuilds
	way = -way
	var u := RoadFrame.unroll(p.global_position)
	var t := RoadFrame.pose(TrafficManager.lane_centre(1, way > 0.0), u.y, u.z, PI if way > 0.0 else 0.0)
	game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", u.z)
	var after := _where(p)
	if after.road != before.road or absf(after.s - before.s) > 0.5 or after.dir != -before.dir:
		_fail("turned round at %.1f m heading %d, now at %.1f m heading %d" % [before.s, before.dir, after.s, after.dir])
	rebuilds_at_turns += rebuilds - had

func _drive(p: PlayerCar) -> void:
	p.driver = func(c: Vehicle) -> void:
		# About 100 km/h, with the pure-pursuit steering the traffic uses (and
		# the damping of tests/traffic/traffic_harness.gd's lane driver).
		c.throttle_input = 1.0 if c.linear_velocity.length() < 28.0 else 0.0
		c.brake_input = 0.0
		var lane := TrafficManager.lane_centre(1, way > 0.0)
		var side_v := RoadFrame.dir_to_road(RoadFrame.unroll(c.global_position).z, c.linear_velocity).x
		c.steering_input = TrafficCar.lane_steer(c, lane - side_v * 3.0, way, 2.5, 0.0008)
		if c.current_gear < 3 and c.motor_rpm > 6000.0:
			c.current_gear += 1

func _check(p: PlayerCar) -> void:
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 2.0, p.global_position + Vector3.DOWN * 5.0)
	q.exclude = [p.get_rid()]
	var u := RoadFrame.unroll(p.global_position)
	if space.intersect_ray(q).is_empty() or absf(u.y) > 1.5 or absf(u.x) > 16.0 or p.global_basis.y.y < 0.5:
		no_road += 1
		if no_road <= 3:
			_fail("tick %d, phase %d: no road under the car (x %.1f, y %.1f, up %.2f, %.0f m round)" % [ticks, phase, u.x, u.y, p.global_basis.y.y, _where(p).s])
	if ticks % 30 == 0:
		var at := floori(RoadFrame.s_at(u.z) / L)
		var lo := 1 << 30
		var hi := -(1 << 30)
		for c in game.chunk_pool:
			lo = mini(lo, c.index)
			hi = maxi(hi, c.index)
		if lo > at - 5 or hi < at + 5:
			_fail("tick %d: pool spans %d..%d around chunk %d" % [ticks, lo, hi, at])

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	var hz := Engine.physics_ticks_per_second
	var p: PlayerCar = game.get("player")
	if ticks < 3:
		return false
	if ticks == 3:
		game.set("chunk_event_hook", _on_chunk)
		z0 = RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)
		_drive(p)
		return false
	_check(p)
	# Metres along the road, counted on from lap to lap (the floating origin
	# moves road-space z, not this).
	var z := RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)
	if ticks % (hz * 20) == 0:
		print("t=%d phase %d: %.0f m round, heading %d, %.0f km/h, %d rebuilds" % [ticks, phase, _where(p).s, _where(p).dir, p.linear_velocity.length() * 3.6, rebuilds])
	if ticks > hz * 400 and ticks < 1000000 or no_road > 200:
		_fail("timed out in phase %d" % phase)
		_finish()
		return true
	match phase:
		0:  # 2 km down the road
			if z - z0 >= OUT:
				print("out: %.0f m, at %.0f m round, %d rebuilds" % [z - z0, _where(p).s, rebuilds])
				z_turn = z
				_turn(p)
				phase = 1
		1:  # 3 km back, across the lap's seam
			if z_turn - z >= BACK:
				print("back: %.0f m, at %.0f m round, %d rebuilds" % [z_turn - z, _where(p).s, rebuilds])
				if _where(p).s < RoadMap.length() * 0.5:
					_fail("3 km back from 2 km out should be before the start, on the end of the lap")
				_turn(p)
				turns = 1
				ticks = 1000000  # zig-zag clock
				phase = 2
		2:  # ten turns, a few seconds apart
			if (ticks - 1000000) % (hz * TURN_SECS) == 0:
				if turns >= TURNS:
					_finish()
					return true
				_turn(p)
				turns += 1
	return false

func _finish() -> void:
	if rebuilds < 80:
		_fail("only %d chunk rebuilds over 5 km" % rebuilds)
	if most_in_a_frame > 1:
		_fail("%d chunks rebuilt in one frame" % most_in_a_frame)
	if nearest_rebuild < 6:
		_fail("a chunk %d chunks from the car was rebuilt" % nearest_rebuild)
	if seen_rebuilds > 0:
		_fail("%d chunks were rebuilt where a camera could see them" % seen_rebuilds)
	if rebuilds_at_turns > 0:
		_fail("turning round rebuilt %d chunks" % rebuilds_at_turns)
	if no_road > 0:
		_fail("no road under the car on %d ticks" % no_road)
	print("two_way: %d turns, %d rebuilds (nearest %d chunks away, at most %d a frame, %d in view), %d ticks without road" % [turns, rebuilds, nearest_rebuild, most_in_a_frame, seen_rebuilds, no_road])
	print("two_way_drive: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
