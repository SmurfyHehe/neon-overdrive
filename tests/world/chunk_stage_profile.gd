extends SceneTree

# Where a chunk rebuild goes, stage by stage (2026-10-13, cloud half of the
# "benchmark and profile" ask). Headless, so CPU only.
#
# game.gd recycles a chunk with rebuild_begin() and runs one stage per frame
# (rebuild_step); the stages are RoadChunkBuilder.STAGES. This rebuilds a
# pooled chunk N times a stage at a time, on a straight road and on one with
# curves and hills (the expensive case), and prints per-stage mean / p95 / max,
# the whole rebuild, and how many nodes the chunk holds. At 400 km/h the car
# crosses a 50 m chunk in 0.45 s.
#
#   godot --headless --audio-driver Dummy --path . -s res://tests/world/chunk_stage_profile.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const N := 300

func _cfg(o: int, n: int, barrier: bool) -> Dictionary:
	return {"own_lanes": o, "onc_lanes": n, "barrier": barrier}

func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	await process_frame
	for shape in [["straight", 0.0, 0.0], ["curves+hills", 1.0, 1.0]]:
		_run(shape[0], shape[1], shape[2])
	quit(0)

func _run(label: String, curviness: float, hilliness: float) -> void:
	RoadFrame.origin_index = 0
	RoadFrame.align = RoadAlignment.new(4242, curviness, hilliness, 0.0) if curviness > 0.0 or hilliness > 0.0 else null
	var holder := Node3D.new()
	get_root().add_child(holder)
	seed(777)
	var chunk := B.build_chunk(0, _cfg(4, 4, false), _cfg(4, 4, true))
	holder.add_child(chunk)
	var per := {}
	var whole := PackedFloat32Array()
	SpikeLog.enabled = true
	for i in range(1, N + 1):
		var barrier := randf() < 0.3
		var job := B.rebuild_begin(chunk, i, _cfg(4, 4, false), _cfg(4, 4, barrier))
		var total := 0.0
		while true:
			var t0 := Time.get_ticks_usec()
			var done := B.rebuild_step(job)
			total += float(Time.get_ticks_usec() - t0) / 1000.0
			if done:
				break
		for e in SpikeLog.take():
			if not per.has(e[0]):
				per[e[0]] = PackedFloat32Array()
			per[e[0]].append(e[1])
		whole.append(total)
	SpikeLog.enabled = false
	var s := _stats(whole)
	print("chunk_stage_profile [%s]: %d rebuilds, whole rebuild mean %.3f ms  p95 %.3f  max %.3f" % [label, N, s[0], s[1], s[2]])
	print("  chunk children: %d, nodes under it: %d" % [chunk.get_child_count(), _count(chunk)])
	for tag in B.STAGES:
		var a: PackedFloat32Array = per.get("chunk/" + tag, PackedFloat32Array())
		var st := _stats(a)
		print("  %-9s mean %6.3f  p95 %6.3f  max %7.3f ms   %4.1f%% of the rebuild" % [tag, st[0], st[1], st[2], 100.0 * st[0] / maxf(s[0], 0.0001)])
	holder.queue_free()

func _stats(a: PackedFloat32Array) -> Array:
	if a.is_empty():
		return [0.0, 0.0, 0.0]
	var s := Array(a)
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	return [sum / s.size(), s[int(s.size() * 0.95)], s[s.size() - 1]]

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
