extends SceneTree

# Lamp-post life: what a chunk rebuild costs with the step on and off
# (living world step 2, 2026-10-10). The effects themselves have no per-frame
# script work (shader-driven), so the only CPU they add is in the chunk
# builder's recycle path, once per 50 m of driving. Rebuilds a pooled chunk
# many times with LampLife.enabled on and off, interleaved so a busy laptop
# hits both the same, and prints microseconds per rebuild.
#
#   <godot> --path . --audio-driver Dummy -s res://tools/lamp_life_cost.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const L := preload("res://scripts/world/lamp_life.gd")
const ROUNDS := 6
const REBUILDS := 150

func _initialize() -> void:
	var cfg := {"own_lanes": 3, "onc_lanes": 2, "barrier": true}
	var chunk: Node3D = B.build_chunk(100, cfg, cfg)
	root.add_child(chunk)
	for i in 30:
		B.rebuild_chunk(chunk, 200 + i, cfg, cfg)  # warm the caches
	var off := PackedFloat64Array()
	var on := PackedFloat64Array()
	for r in ROUNDS:
		for mode in [false, true]:
			L.enabled = mode
			var t0 := Time.get_ticks_usec()
			for i in REBUILDS:
				B.rebuild_chunk(chunk, 1000 + r * REBUILDS + i, cfg, cfg)
			var us := float(Time.get_ticks_usec() - t0) / float(REBUILDS)
			(on if mode else off).append(us)
	off.sort()
	on.sort()
	var m_off := off[ROUNDS / 2]
	var m_on := on[ROUNDS / 2]
	print("rebuild_chunk median over %d rounds x %d: off %.0f us, on %.0f us, lamp life adds %.0f us (%.2f%%)" % [
		ROUNDS, REBUILDS, m_off, m_on, m_on - m_off, (m_on - m_off) / m_off * 100.0])
	print("a chunk is rebuilt every 50 m: at 66 m/s that is %.1f rebuilds/s, +%.3f ms/s" % [66.0 / 50.0, (m_on - m_off) * 66.0 / 50.0 / 1000.0])
	quit(0)
