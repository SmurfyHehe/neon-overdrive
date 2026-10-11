extends SceneTree

# Breakable world: what the roadside prop work costs (I0, 2026-10-11).
# Same recipe as tools/lamp_life_cost.gd: on and off rounds interleaved so a
# busy laptop hits both the same, median of 6.
#
#   record  a chunk rebuild with the props record written and not written
#           (once per 50 m of driving)
#   touch   one physics tick's touch check: a car box against the props of
#           its own chunk and the next one (RoadsideProps.near), against the
#           same loop doing nothing
#
# Later steps add their own rows here (the breaker's tick, a hit, a spree).
#
#   <godot> --headless --path . --audio-driver Dummy -s res://tools/prop_cost.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Props := preload("res://scripts/world/roadside_props.gd")

const ROUNDS := 6
const REBUILDS := 150
const TICKS := 20000

func _median(a: PackedFloat64Array) -> float:
	a.sort()
	return a[ROUNDS / 2]

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
			Props.enabled = mode
			var t0 := Time.get_ticks_usec()
			for i in REBUILDS:
				B.rebuild_chunk(chunk, 1000 + r * REBUILDS + i, cfg, cfg)
			(on if mode else off).append(float(Time.get_ticks_usec() - t0) / float(REBUILDS))
	Props.enabled = true
	var m_off := _median(off)
	var m_on := _median(on)
	print("record: rebuild_chunk median over %d rounds x %d: off %.0f us, on %.0f us, the record adds %.0f us (%.2f%%)" % [
		ROUNDS, REBUILDS, m_off, m_on, m_on - m_off, (m_on - m_off) / m_off * 100.0])

	# two chunks with the most props found in a short search, as the worst case
	var a: Node3D = B.build_chunk(300, cfg, cfg)
	var b: Node3D = B.build_chunk(301, cfg, cfg)
	root.add_child(a)
	root.add_child(b)
	b.position = Vector3(0.0, 0.0, -Props.CHUNK_LEN)
	var n_props: int = Props.of(a).kind.size() + Props.of(b).kind.size()
	var out := PackedInt32Array()
	var none := PackedByteArray()
	off.clear()
	on.clear()
	var found := 0
	for r in ROUNDS:
		for mode in [false, true]:
			var t0 := Time.get_ticks_usec()
			for i in TICKS:
				# the car runs down the kerb line, where the props are
				var z := -fmod(float(i) * 0.37, Props.CHUNK_LEN)
				var car_inv := Transform3D(Basis(), Vector3(-15.0, 0.0, -z))
				out.clear()
				if mode:
					Props.near(Props.of(a), car_inv * a.transform, z, 0.9, 3.2, 2.2, none, out)
					Props.near(Props.of(b), car_inv * b.transform, z + Props.CHUNK_LEN, 0.9, 3.2, 2.2, none, out)
					found += out.size()
			(on if mode else off).append(float(Time.get_ticks_usec() - t0) / float(TICKS))
	m_off = _median(off)
	m_on = _median(on)
	print("touch: one tick against %d props in two chunks, median over %d rounds x %d: %.2f us (%.4f ms), loop alone %.2f us; %d props touched in all" % [
		n_props, ROUNDS, TICKS, m_on - m_off, (m_on - m_off) / 1000.0, m_off, found])
	print("budget: normal driving 0.01-0.02 ms a tick, hard ceiling 0.3 ms")
	quit(0)
