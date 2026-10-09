extends SceneTree

# Chunk rebuild cost and the staged rebuild (2026-10-09, frame-spike pass).
#
# 1. Staged == atomic: a chunk rebuilt a stage per call (rebuild_begin /
#    rebuild_step, what game.gd spreads over frames) must come out the same
#    as one rebuilt in one go (rebuild_chunk): every child's transform and
#    every building's collision box, shader params and meta, and the global
#    RNG must be left in the same state.
# 2. Cost: how long one pooled chunk takes to rebuild, on a straight road and
#    on a bent, hilly one, with the per-stage split (SpikeLog). Headless, so
#    this is the CPU side only. The cap is loose (machine-dependent, and the
#    laptop is often busy); it only catches a gross regression.
#
#   godot --headless --path . -s tests/chunk_rebuild_perf.gd

const B := preload("res://scripts/road_chunk_builder.gd")
const N := 200
const CHUNK_MAX_MS := 10.0
const PARAMS := ["tile", "tint", "size", "floor_h", "lit_density", "seed"]

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _cfg(o: int, n: int, barrier: bool) -> Dictionary:
	return {"own_lanes": o, "onc_lanes": n, "barrier": barrier}

func _initialize() -> void:
	_go.call_deferred()

## After a frame, so the chunks under test sit inside the tree as they do in
## the game (in _initialize the root is not inside it yet).
func _go() -> void:
	await process_frame
	_check_staged_equals_atomic()
	var worst := 0.0
	worst = maxf(worst, _run("straight", 0.0, 0.0))
	worst = maxf(worst, _run("curves", 1.0, 0.0))
	worst = maxf(worst, _run("curves+hills", 1.0, 1.0))
	if worst > CHUNK_MAX_MS:
		_fail("rebuild avg %.2f ms > %.1f ms" % [worst, CHUNK_MAX_MS])
	print("chunk_rebuild_perf: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(0 if fails == 0 else 1)

func _check_staged_equals_atomic() -> void:
	var cases := 0
	for shape in [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0]]:
		RoadFrame.origin_index = 0
		RoadFrame.align = RoadAlignment.new(4242, shape[0], shape[1], 0.0) if shape[0] > 0.0 or shape[1] > 0.0 else null
		for idx in [3, 77, 1000]:
			for pair in [[_cfg(4, 4, false), _cfg(4, 4, true)], [_cfg(4, 4, true), _cfg(4, 4, false)]]:
				var a := B.build_chunk(idx + 10, pair[1], pair[0])
				var b := B.build_chunk(idx + 10, pair[1], pair[0])
				get_root().add_child(a)
				get_root().add_child(b)
				seed(500 + idx)
				B.rebuild_chunk(a, idx, pair[0], pair[1])
				B.build_chunk(idx + 20, pair[0], pair[0]).free()  # the same interleaved work as below
				var rng_a := randi()
				seed(500 + idx)
				var job := B.rebuild_begin(b, idx, pair[0], pair[1])
				# the job must survive other builder work between its stages
				var steps := 0
				while not B.rebuild_step(job):
					steps += 1
					if steps == 2:
						B.build_chunk(idx + 20, pair[0], pair[0]).free()
				var rng_b := randi()
				if rng_a != rng_b:
					_fail("chunk %d: staged rebuild leaves the global RNG elsewhere" % idx)
				if steps + 1 != B.STAGES.size():
					_fail("chunk %d: %d steps, expected %d" % [idx, steps + 1, B.STAGES.size()])
				if B.is_rebuilding(b):
					_fail("chunk %d: still flagged as rebuilding" % idx)
				_compare(a, b, "chunk %d shape %s" % [idx, shape])
				a.free()
				b.free()
				cases += 1
	print("staged == atomic: %d cases" % cases)

func _compare(a: Node3D, b: Node3D, label: String) -> void:
	if not a.transform.is_equal_approx(b.transform):
		_fail("%s: root transform %s vs %s" % [label, a.transform, b.transform])
	for ca in a.get_children():
		var cb: Node = b.get_node(NodePath(ca.name))
		if ca is Node3D and not (ca as Node3D).transform.is_equal_approx((cb as Node3D).transform):
			_fail("%s %s: transform differs" % [label, ca.name])
		if ca is MeshInstance3D:
			var ma := ca as MeshInstance3D
			var mb := cb as MeshInstance3D
			if ma.visible != mb.visible:
				_fail("%s %s: visibility differs" % [label, ca.name])
			for p in PARAMS:
				if ma.get_instance_shader_parameter(p) != mb.get_instance_shader_parameter(p):
					_fail("%s %s: shader param %s differs" % [label, ca.name, p])
			for k in ma.get_meta_list():
				if ma.get_meta(k) != mb.get_meta(k, null):
					_fail("%s %s: meta %s differs" % [label, ca.name, k])
		if ca is CollisionObject3D:
			var la := (ca as CollisionObject3D).collision_layer
			var lb := (cb as CollisionObject3D).collision_layer
			if la != lb or la == 0:
				_fail("%s %s: collision layer %d vs %d" % [label, ca.name, la, lb])
			for sa in ca.get_children():
				if sa is CollisionShape3D:
					var sb: CollisionShape3D = cb.get_node(NodePath(sa.name))
					if sa.disabled != sb.disabled or not sa.transform.is_equal_approx(sb.transform):
						_fail("%s %s/%s: shape differs" % [label, ca.name, sa.name])
					if sa.shape is BoxShape3D and not (sa.shape as BoxShape3D).size.is_equal_approx((sb.shape as BoxShape3D).size):
						_fail("%s %s/%s: box size differs" % [label, ca.name, sa.name])
					if sa.shape is ConcavePolygonShape3D and (sa.shape as ConcavePolygonShape3D).get_faces() != (sb.shape as ConcavePolygonShape3D).get_faces():
						_fail("%s %s/%s: faces differ" % [label, ca.name, sa.name])

func _run(label: String, curviness: float, hilliness: float) -> float:
	RoadFrame.origin_index = 0
	RoadFrame.align = RoadAlignment.new(4242, curviness, hilliness, 0.0) if curviness > 0.0 or hilliness > 0.0 else null
	var root := Node3D.new()
	get_root().add_child(root)
	seed(777)
	var chunk := B.build_chunk(0, _cfg(4, 4, false), _cfg(4, 4, true))
	root.add_child(chunk)
	var times := PackedFloat32Array()
	var stage_total := {}
	var stage_max := {}
	SpikeLog.enabled = true
	for i in range(1, N + 1):
		var barrier := randf() < 0.3
		var t0 := Time.get_ticks_usec()
		B.rebuild_chunk(chunk, i, _cfg(4, 4, false), _cfg(4, 4, barrier))
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		for e in SpikeLog.take():
			stage_total[e[0]] = float(stage_total.get(e[0], 0.0)) + float(e[1])
			stage_max[e[0]] = maxf(float(stage_max.get(e[0], 0.0)), float(e[1]))
	SpikeLog.enabled = false
	root.queue_free()
	var s := Array(times)
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	var avg := sum / s.size()
	print("%-16s rebuild x%d: avg=%.3fms p95=%.3fms max=%.3fms" % [label, N, avg, s[int(s.size() * 0.95)], s[s.size() - 1]])
	var tags := stage_total.keys()
	tags.sort()
	for tag in tags:
		print("    %-18s avg=%.3fms max=%.3fms" % [tag, stage_total[tag] / N, stage_max[tag]])
	return avg
