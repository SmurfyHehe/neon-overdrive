extends SceneTree

# Road space (2026-10-06): the lanes sit MEDIAN_GAP off the centre line, the
# shoulder is 1.4 m, lanes stay 3.2 m, and everything laid out from the road
# edge moved out with it. Headless, no game scene:
# - the numbers: LANE_W 3.2, SHOULDER_W 1.4, MEDIAN_GAP inside Roy's 0.2-0.6 m
# - lane centres and the lane-from-distance inverse agree (traffic places cars
#   with one and indexes them with the other), on both sides
# - TrafficManager's occupancy slots: each lane centre, and the median gap,
#   land in the right lane's slot
# - a built chunk: the drawn road edge is at the median gap plus the lanes, the
#   out-of-bounds wall's inner face is at
#   the sidewalk's outer edge plus BUILDING_GAP (so the wider verge stays drivable)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/road_space.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Districts := preload("res://scripts/world/districts.gd")
const EPS := 0.001

var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check(is_equal_approx(B.LANE_W, 3.2), "lane width changed: %.2f (should stay 3.2)" % B.LANE_W)
	_check(is_equal_approx(B.SHOULDER_W, 1.4), "shoulder %.2f, should be 1.4 (0.9 + 0.5)" % B.SHOULDER_W)
	_check(B.MEDIAN_GAP >= 0.2 and B.MEDIAN_GAP <= 0.6, "median gap %.2f outside 0.2-0.6" % B.MEDIAN_GAP)

	for i in 4:
		var d: float = B.lane_offset(i)
		_check(absf(d - (B.MEDIAN_GAP + (i + 0.5) * B.LANE_W)) < EPS, "lane %d centre at %.2f" % [i, d])
		_check(B.lane_at(d) == i, "lane_at(centre of lane %d) = %d" % [i, B.lane_at(d)])
		_check(B.lane_at(d - B.LANE_W * 0.45) == i and B.lane_at(d + B.LANE_W * 0.45) == i, "lane %d edges map to another lane" % i)
		_check(absf(TrafficManager.lane_centre(i, false) - d) < EPS and absf(TrafficManager.lane_centre(i, true) + d) < EPS, "TrafficManager.lane_centre(%d) disagrees" % i)
	_check(B.lane_at(B.MEDIAN_GAP * 0.5) == 0, "the median gap should count as lane 0")

	var tm := TrafficManager.new()
	tm.own_lanes = 3
	tm.onc_lanes = 2
	for i in 3:
		_check(tm._slot_of(TrafficManager.lane_centre(i, false)) == 2 + i, "own lane %d in slot %d" % [i, tm._slot_of(TrafficManager.lane_centre(i, false))])
	for i in 2:
		_check(tm._slot_of(TrafficManager.lane_centre(i, true)) == 1 - i, "oncoming lane %d in slot %d" % [i, tm._slot_of(TrafficManager.lane_centre(i, true))])
	_check(tm._slot_of(B.MEDIAN_GAP * 0.5) == 2 and tm._slot_of(-B.MEDIAN_GAP * 0.5) == 1, "median gap slots wrong")
	tm.free()

	var holder := Node3D.new()
	root.add_child(holder)
	var cfg := {"own_lanes": 3, "onc_lanes": 2, "barrier": false}
	var chunk: Node3D = B.build_chunk(0, cfg, cfg)
	holder.add_child(chunk)
	for side in [1, -1]:
		var lanes: int = 3 if side == 1 else 2
		var edge: float = B._lane_w(lanes)
		_check(absf(edge - (B.MEDIAN_GAP + lanes * B.LANE_W)) < EPS, "road edge %.2f" % edge)
		var road := (chunk.get_node(^"RoadOwn" if side == 1 else ^"RoadOnc") as MeshInstance3D).mesh.get_aabb()
		_check(absf(maxf(absf(road.position.x), absf(road.end.x)) - edge) < EPS, "drawn road ends at %.2f, not %.2f" % [maxf(absf(road.position.x), absf(road.end.x)), edge])
		var walk_out: float = edge + Districts.shoulder_at(0) + B.CURB_W + Districts.walk_at(0)
		var wall: StaticBody3D = chunk.get_node(^"BoundaryOwn" if side == 1 else ^"BoundaryOnc")
		# The wall is one box per centreline station (#37); they all sit at one x.
		var inner_face := absf(wall.position.x + (wall.get_node(^"Shape") as Node3D).position.x) - B.BOUNDARY_T / 2.0
		_check(absf(inner_face - (walk_out + B.BUILDING_GAP)) < EPS, "side %d: wall inner face at %.2f, sidewalk ends %.2f" % [side, inner_face, walk_out])
	print("road_space: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL ", msg)
