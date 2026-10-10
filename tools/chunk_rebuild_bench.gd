extends SceneTree

# Chunk rebuild micro-benchmark: how long RoadChunkBuilder.rebuild_chunk
# takes, headless, with nothing else running. The frame-rate probe
# (tests/core/perf_probe.gd) measures the whole game and swings by 2x on a
# shared laptop; this isolates the one cost a road-geometry change adds.
# Prints the mean and median ms over ROUNDS rebuilds of a rolling chunk
# index (buildings, kerbs, drops and hydrants all vary with the index).
#
#   <godot> --headless --path . -s res://tools/chunk_rebuild_bench.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const ROUNDS := 400
const CFGS := [
	[{"own_lanes": 2, "onc_lanes": 2, "barrier": false}, {"own_lanes": 2, "onc_lanes": 2, "barrier": false}],
	[{"own_lanes": 2, "onc_lanes": 1, "barrier": false}, {"own_lanes": 4, "onc_lanes": 2, "barrier": true}],
]

func _initialize() -> void:
	seed(1)
	var holder := Node3D.new()
	root.add_child(holder)
	var chunk: Node3D = B.build_chunk(0, CFGS[0][0], CFGS[0][1])
	holder.add_child(chunk)
	for i in 20:  # warm up
		B.rebuild_chunk(chunk, i, CFGS[i % 2][0], CFGS[i % 2][1])
	var times := PackedFloat64Array()
	for i in ROUNDS:
		var t0 := Time.get_ticks_usec()
		B.rebuild_chunk(chunk, 100 + i, CFGS[i % 2][0], CFGS[i % 2][1])
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	print("chunk_rebuild_bench: %d rebuilds, mean %.3f ms, p50 %.3f ms, p90 %.3f ms" % [ROUNDS, sum / ROUNDS, times[ROUNDS / 2], times[int(ROUNDS * 0.9)]])
	quit(0)
