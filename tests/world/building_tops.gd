extends SceneTree

# World step 1 (2026-10-10): roof shapes, facade wear and one skyline landmark
# per district run. Headless: it reads node meta and shader parameters, not
# MultiMesh data.
#
# Asserts (exit code 1 on failure):
# - every building wears a roof shape from BuildingKit.TOPS that suits its
#   type (TOPS_FOR), and every shape turns up somewhere along 320 chunks
# - every building's wear is inside its district's range (or the next
#   district's, in a run's blend chunks)
# - every run of 16 chunks has exactly one landmark: on the chunk and slot
#   Districts.landmark_at() names, of the district's kind, on a building of
#   the pinned type that is never an empty lot; a pooled chunk rebuilt there
#   shows the same landmark as a fresh build
# - the rooftop buffer never overflows RoofProps.CAPACITY
# It also prints the build cost (ms per fresh build and per rebuild), for the
# before/after note in the PR; it does not assert on it.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/building_tops.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const CHUNKS := 320  # 20 runs

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _cfg(o: int, n: int, barrier: bool) -> Dictionary:
	return {"own_lanes": o, "onc_lanes": n, "barrier": barrier}

func _initialize() -> void:
	var D := B.Districts
	var K := B.BuildingKit
	var R := B.RoofProps
	seed(4242)
	var tops := {}
	var landmarks := {}  # run -> kind
	var n_bld := 0
	var worst_props := 0
	var t_build := 0.0
	var t_rebuild := 0.0
	var pooled := B.build_chunk(0, _cfg(2, 2, false), _cfg(2, 2, false))
	for idx in CHUNKS:
		var cfg := _cfg(1 + idx % 4, 1 + (idx / 4) % 2, idx % 3 == 0)
		var t0 := Time.get_ticks_usec()
		var fresh := B.build_chunk(idx, _cfg(2, 2, false), cfg)
		var t1 := Time.get_ticks_usec()
		B.rebuild_chunk(pooled, idx, _cfg(2, 2, false), cfg)
		var t2 := Time.get_ticks_usec()
		t_build += float(t1 - t0) / 1000.0
		t_rebuild += float(t2 - t1) / 1000.0
		var run := D.run_of(idx)
		# a building near a run boundary may follow the neighbouring district
		var wa: Array = D.spec(D.name_of_run(run)).get("wear", D.DEFAULTS.wear)
		var wb: Array = D.spec(D.name_of_run(int(D.blend_at(idx)[0]))).get("wear", D.DEFAULTS.wear)
		var lo := minf(float(wa[0]), float(wb[0]))
		var hi := maxf(float(wa[1]), float(wb[1]))
		for i in B._building_slots() * 2:
			var mi: MeshInstance3D = fresh.get_node(NodePath("BuildingMesh%d" % i))
			var expect: String = D.landmark_at(idx, i)
			var got: String = mi.get_meta("landmark", "")
			var type: String = mi.get_meta("building_type", "")
			if type == "lot" or not mi.visible:
				if expect != "" or got != "":
					_fail("chunk %d building %d: the landmark slot is an empty lot" % [idx, i])
				continue
			n_bld += 1
			var top: String = mi.get_meta("roof_top", "")
			if not K.TOPS.has(top):
				_fail("chunk %d building %d: roof top '%s' is not in BuildingKit.TOPS" % [idx, i, top])
			elif not (K.TOPS_FOR[type] as Array).has(top):
				_fail("chunk %d building %d: a %s with a %s roof" % [idx, i, type, top])
			tops[top] = tops.get(top, 0) + 1
			var wear = mi.get_instance_shader_parameter("wear")
			if wear == null or float(wear) < lo - 1e-4 or float(wear) > hi + 1e-4:
				_fail("chunk %d building %d: wear %s outside [%.2f, %.2f]" % [idx, i, str(wear), lo, hi])
			if got != expect:
				_fail("chunk %d building %d: landmark '%s', expected '%s'" % [idx, i, got, expect])
			if got != "":
				landmarks[run] = got
				if type != D.LANDMARK_BUILDING[got].type:
					_fail("chunk %d: the %s stands on a %s, not a %s" % [idx, got, type, D.LANDMARK_BUILDING[got].type])
				var lm_pool: String = pooled.get_node(NodePath("BuildingMesh%d" % i)).get_meta("landmark", "")
				if lm_pool != got:
					_fail("chunk %d: rebuilt from the pool the landmark is '%s', fresh it is '%s'" % [idx, lm_pool, got])
		worst_props = maxi(worst_props, int(fresh.get_meta("roof_props", 0)))
		fresh.free()
	pooled.free()
	for run in CHUNKS / D.RUN:
		var want: String = D.spec(D.name_of_run(run)).get("landmark", "")
		if landmarks.get(run, "") != want:
			_fail("run %d (%s): landmark '%s', expected '%s'" % [run, D.name_of_run(run), landmarks.get(run, ""), want])
	for t in K.TOPS:
		if not tops.has(t):
			_fail("roof top '%s' never appears in %d chunks" % [t, CHUNKS])
	if worst_props > R.CAPACITY:
		_fail("roof props %d over CAPACITY %d" % [worst_props, R.CAPACITY])
	print("tops over %d buildings: %s" % [n_bld, tops])
	print("landmarks by run: %s" % [landmarks])
	print("roof props: worst %d of %d per chunk" % [worst_props, R.CAPACITY])
	print("build cost: fresh %.2f ms/chunk, rebuild %.2f ms/chunk, over %d chunks" % [t_build / CHUNKS, t_rebuild / CHUNKS, CHUNKS])
	print("building_tops: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
