extends SceneTree

# The road's shape (#37 step R3): RoadAlignment rolls bends from a seed and
# RoadFrame / the chunk builder follow it. Headless, no game scene:
# - limits: no bend tighter than MIN_RADIUS, heading never past MAX_HEADING,
#   and with curviness 1 the road really bends (some chunk turns)
# - the same seed gives the same road whichever order chunks are asked for in;
#   curviness 0 gives a straight road
# - chunks join: the end of chunk i's arc is the start of chunk i+1, to 1 mm,
#   and the headings match, across 20 km and a floating-origin change
# - the Path3D centreline the builder fits to each arc follows it to 5 mm, and
#   built chunks' road strips meet their neighbours' to 1 mm in the world
# - RoadFrame.unroll(roll(u)) == u to 1 mm across the road, 20 km of it,
#   including far behind (where parked traffic waits) and after an origin shift
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/road_alignment.gd

const B := preload("res://scripts/road_chunk_builder.gd")
const EPS := 0.001
const CHUNKS := 400  # 20 km

var fails := 0

func _initialize() -> void:
	_limits_and_determinism()
	_joins_and_roundtrip(0)
	_joins_and_roundtrip(37)  # after the floating origin moved 37 chunks on
	_built_chunks()
	RoadFrame.align = null
	print("road_alignment: %d failures" % fails)
	quit(1 if fails > 0 else 0)

func _limits_and_determinism() -> void:
	var turned := 0
	for seed_value in range(1, 21):
		var a := RoadAlignment.new(seed_value, 1.0)
		var max_k := 0.0
		var max_psi := 0.0
		for i in CHUNKS:
			max_k = maxf(max_k, absf(a.curvature(i)))
			max_psi = maxf(max_psi, absf(a.start_heading(i)))
			if absf(a.curvature(i)) > 0.0:
				turned += 1
		_check(max_k <= 1.0 / RoadAlignment.MIN_RADIUS + 1e-9, "seed %d: a bend of radius %.0f m" % [seed_value, 1.0 / max_k])
		_check(max_psi <= RoadAlignment.MAX_HEADING + 1e-9, "seed %d: heading reached %.1f deg" % [seed_value, rad_to_deg(max_psi)])
		# Same seed, chunks asked for backwards: same road.
		var b := RoadAlignment.new(seed_value, 1.0)
		for i in range(CHUNKS - 1, -1, -1):
			if b.curvature(i) != a.curvature(i) or b.start_x(i) != a.start_x(i) or b.start_z(i) != a.start_z(i):
				_check(false, "seed %d: chunk %d differs on a second build" % [seed_value, i])
				break
	_check(turned > CHUNKS * 20 / 4, "curviness 1 barely bends: %d of %d chunks turn" % [turned, CHUNKS * 20])
	var flat := RoadAlignment.new(5, 0.0)
	for i in CHUNKS:
		if flat.curvature(i) != 0.0:
			_check(false, "curviness 0 bends at chunk %d" % i)
			break
	print("limits: %d of %d chunks turn at curviness 1" % [turned, CHUNKS * 20])

func _joins_and_roundtrip(origin: int) -> void:
	RoadFrame.align = RoadAlignment.new(1234, 1.0)
	RoadFrame.origin_index = origin
	var worst_join := 0.0
	var worst_rt := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(origin - 5, origin + CHUNKS):
		# The game recentres every 1 km (20 chunks), so nothing it asks about
		# is ever further than that from the origin; float32 positions are
		# good to ~0.1 mm there, but 2 mm at 20 km. Move the origin along too.
		RoadFrame.origin_index = origin + maxi(0, (i - origin) / 20 * 20)
		var k := RoadFrame.curvature(i)
		var end := RoadFrame.chunk_xf(i) * RoadAlignment.arc_point(k, B.CHUNK_LEN)
		var next := RoadFrame.chunk_xf(i + 1)
		worst_join = maxf(worst_join, end.distance_to(next.origin))
		var h_end := RoadFrame.align.start_heading(i) + RoadAlignment.arc_heading(k, B.CHUNK_LEN)
		_check(absf(h_end - RoadFrame.align.start_heading(i + 1)) < 1e-6, "chunk %d: heading jumps at its end" % i)
		for n in 3:
			var u := Vector3(rng.randf_range(-16.0, 16.0), rng.randf_range(-0.2, 2.0), -(float(i - RoadFrame.origin_index) + rng.randf()) * B.CHUNK_LEN)
			worst_rt = maxf(worst_rt, RoadFrame.unroll(RoadFrame.roll(u)).distance_to(u))
	# Far behind, where TrafficManager parks cars it has no slot for: found
	# (float32 at 10 km is good to a centimetre, plenty for a hidden car).
	RoadFrame.origin_index = origin + CHUNKS
	for z in [5000.0, 10000.0]:
		var u := Vector3(RoadChunkBuilder.lane_offset(1), -0.124, z)
		var far := RoadFrame.unroll(RoadFrame.roll(u)).distance_to(u)
		_check(far < 0.02, "origin %d: a car parked %.0f m behind comes back %.3f m off" % [origin, z, far])
	_check(worst_join < EPS, "origin %d: chunks open a %.4f m gap at a join" % [origin, worst_join])
	_check(worst_rt < EPS, "origin %d: roll/unroll round trip off by %.4f m" % [origin, worst_rt])
	print("origin %d: worst join %.5f m, worst round trip %.5f m" % [origin, worst_join, worst_rt])

func _built_chunks() -> void:
	RoadFrame.align = RoadAlignment.new(4321, 1.0)
	RoadFrame.origin_index = 0
	var cfg := {"own_lanes": 4, "onc_lanes": 4, "barrier": false}
	var worst_fit := 0.0
	var worst_seam := 0.0
	var prev_end: Array = []
	var curved := 0
	for i in 60:
		var chunk: Node3D = B.build_chunk(i, cfg, cfg)
		var k := RoadFrame.curvature(i)
		if k != 0.0:
			curved += 1
		var curve := (chunk.get_node(^"Centerline") as Path3D).curve
		for s in range(0, int(B.CHUNK_LEN) + 1, 5):
			worst_fit = maxf(worst_fit, B.station(curve, float(s)).origin.distance_to(RoadAlignment.arc_point(k, float(s))))
		# World positions of the road strip's corners at the chunk's start and end.
		var verts: PackedVector3Array = ((chunk.get_node(^"RoadOwn") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var xf := chunk.transform
		var end_frame := B.station(curve, B.CHUNK_LEN).affine_inverse()
		var start: Array = []
		var end: Array = []
		for v in verts:
			if absf(v.z) < 0.001:  # on the start line (the start frame is the chunk's own)
				start.append(xf * v)
			if absf((end_frame * v).z) < 0.001:  # on the end line
				end.append(xf * v)
		for p in start:
			var best := INF
			for q in prev_end:
				best = minf(best, (p as Vector3).distance_to(q))
			if not prev_end.is_empty():
				worst_seam = maxf(worst_seam, best)
		prev_end = end
		chunk.free()
	_check(curved > 10, "only %d of 60 built chunks are curved" % curved)
	_check(worst_fit < 0.005, "the Path3D centreline strays %.4f m from its arc" % worst_fit)
	_check(worst_seam < EPS, "road strips open a %.4f m gap between chunks" % worst_seam)
	print("built: %d of 60 curved, centreline fit %.5f m, strip seam %.5f m" % [curved, worst_fit, worst_seam])

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		if fails <= 30:
			printerr("FAIL: " + msg)
