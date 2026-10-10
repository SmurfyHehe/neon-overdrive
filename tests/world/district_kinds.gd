extends SceneTree

# World step 3 (W6, 2026-10-10): more district kinds. Headless: it reads the
# tables, node meta and shader parameters, not MultiMesh data.
#
# Asserts (exit code 1 on failure):
# - the loop: Districts.ORDER is 16 runs, starts downtown, uses every kind in
#   SPECS, and no kind follows itself (the wrap from the last run to the
#   first included, and far up and down the road)
# - the tables: every district row names real building types, roof shapes,
#   tints and a real landmark; every per-tile array in BuildingKit has one
#   entry per atlas tile; the atlas is that wide; each new tile is drawn
# - blending: the far district's share steps 1/5, 2/5 | 3/5, 4/5 across a run
#   boundary, the first run starts pure, and the setback never jumps by more
#   than a fifth of the difference between two neighbours
# - the look: over one whole loop, away from the blend chunks, every building
#   is of a type in its district's mix, wears a tint from its district's
#   palette, and every type in a mix turns up
# - the skyline: any two kinds differ in landmark, in mean roof height (by
#   30%) or in how much of the frontage is built (by 0.2); the kinds that are
#   neighbours in the loop differ in at least two of the three
# - support: no building's block ends above the road, and every piece of
#   every landmark stands on the ground, on its building's roof (inside the
#   footprint) or on another piece
# It also prints the build cost (ms per fresh build and per rebuild) and one
# line per kind, for the PR; it does not assert on the cost.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/district_kinds.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _cfg(o: int, n: int, barrier: bool) -> Dictionary:
	return {"own_lanes": o, "onc_lanes": n, "barrier": barrier}

func _initialize() -> void:
	_check_loop()
	_check_tables()
	_check_blend()
	var stats := _check_look()
	_check_skyline(stats)
	_check_landmark_support()
	print("district_kinds: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

func _check_loop() -> void:
	var D := B.Districts
	if D.ORDER.size() != 16:
		_fail("the loop is %d runs, not 16" % D.ORDER.size())
	if D.name_at(0) != "downtown":
		_fail("the drive does not start downtown")
	for k in D.SPECS:
		if not D.ORDER.has(k):
			_fail("district %s is in SPECS but never in the loop" % k)
	for k in D.ORDER:
		if not D.SPECS.has(k):
			_fail("the loop names %s, which has no SPECS row" % k)
	for run in range(-64, 128):
		if D.name_of_run(run) == D.name_of_run(run + 1):
			_fail("runs %d and %d are both %s" % [run, run + 1, D.name_of_run(run)])
	print("loop: %d runs, %d kinds: %s" % [D.ORDER.size(), D.SPECS.size(), D.ORDER])

func _check_tables() -> void:
	var D := B.Districts
	var K := B.BuildingKit
	var R := B.RoofProps
	for arr in [["FLOOR_H", K.FLOOR_H], ["BAY_W", K.BAY_W], ["COOL_BIAS", K.COOL_BIAS], ["GLOW", K.GLOW], ["CELL_VARY", K.CELL_VARY]]:
		if (arr[1] as Array).size() != K.TILES:
			_fail("BuildingKit.%s has %d entries for %d tiles" % [arr[0], (arr[1] as Array).size(), K.TILES])
	var img := K.atlas().get_image()
	if img.get_width() != K.TILE_PX * K.TILES or img.get_height() != K.TILE_PX * 2:
		_fail("the atlas is %dx%d, not %dx%d" % [img.get_width(), img.get_height(), K.TILE_PX * K.TILES, K.TILE_PX * 2])
	# each new tile is drawn (more than grit: a spread of brightness), and the
	# three with windows have glass on the upper floors
	for t in [K.T_LOFT, K.T_CLAPBOARD, K.T_HANGAR, K.T_CONTAINER]:
		for row in 2:
			var lo := 1.0
			var hi := 0.0
			var glass := 0
			for y in K.TILE_PX:
				for x in K.TILE_PX:
					var c := img.get_pixel(t * K.TILE_PX + x, row * K.TILE_PX + y)
					lo = minf(lo, c.r)
					hi = maxf(hi, c.r)
					if c.a > 0.5:
						glass += 1
			if hi - lo < 0.3:
				_fail("tile %d row %d is nearly flat (%.2f..%.2f)" % [t, row, lo, hi])
			if t == K.T_CONTAINER and glass > 0:
				_fail("the container tile has %d glass pixels" % glass)
			if t != K.T_CONTAINER and glass == 0:
				_fail("tile %d row %d has no glass" % [t, row])
	for type in K.TYPES:
		for e in K.TYPES[type].tiles:
			if int(e[0]) < 0 or int(e[0]) >= K.TILES:
				_fail("type %s uses tile %d of %d" % [type, e[0], K.TILES])
		if not K.TOPS_FOR.has(type):
			_fail("type %s has no TOPS_FOR row" % type)
	for name in D.SPECS:
		var s: Dictionary = D.SPECS[name]
		for key in ["mix", "h", "d", "w", "setback", "gap", "lit", "low", "billboard"]:
			if not s.has(key):
				_fail("district %s has no '%s'" % [name, key])
		for e in s.mix:
			if not K.TYPES.has(e[0]):
				_fail("district %s mixes in unknown type %s" % [name, e[0]])
		if not K.TYPES.has(s.low):
			_fail("district %s: low is unknown type %s" % [name, s.low])
		for t in s.h:
			if not K.TYPES.has(t):
				_fail("district %s sets a height for unknown type %s" % [name, t])
		for e in s.get("tops", D.DEFAULTS.tops):
			if not K.TOPS.has(e[0]):
				_fail("district %s: unknown roof top %s" % [name, e[0]])
		for e in s.get("tints", D.DEFAULTS.tints):
			if int(e[0]) < 0 or int(e[0]) >= K.TINTS.size():
				_fail("district %s: tint %d of %d" % [name, e[0], K.TINTS.size()])
		if float(s.d[1]) > B.BUILDING_SPACING - 1.0:
			_fail("district %s: a %.0f m frontage does not fit a %.0f m slot" % [name, s.d[1], B.BUILDING_SPACING])
		var lm: String = s.get("landmark", "")
		if lm != "":
			if not R.LANDMARKS.has(lm):
				_fail("district %s: unknown landmark %s" % [name, lm])
			elif not D.LANDMARK_BUILDING.has(lm) or not K.LANDMARK_TOP.has(lm):
				_fail("landmark %s has no building or no top" % lm)
			elif not (K.TOPS_FOR[D.LANDMARK_BUILDING[lm].type] as Array).has(K.LANDMARK_TOP[lm]):
				_fail("landmark %s: its %s cannot wear a %s roof" % [lm, D.LANDMARK_BUILDING[lm].type, K.LANDMARK_TOP[lm]])

func _check_blend() -> void:
	var D := B.Districts
	if float(D.blend_at(0)[1]) != 0.0 or float(D.blend_at(1)[1]) != 0.0:
		_fail("the first run does not start pure")
	# the next district's share across the boundary between runs 1 and 2
	var want := [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
	for i in 6:
		var idx := 2 * D.RUN - 3 + i
		var b := D.blend_at(idx)
		var share := 0.0
		if int(b[0]) == 2 and D.run_of(idx) == 1:
			share = float(b[1])
		elif D.run_of(idx) == 2:
			share = 1.0 - (float(b[1]) if int(b[0]) == 1 else 0.0)
		if absf(share - float(want[i])) > 1e-5:
			_fail("chunk %d: the next district's share is %.2f, expected %.2f" % [idx, share, want[i]])
	var gap_max := 0.0
	for r in D.ORDER.size():
		gap_max = maxf(gap_max, absf(float(D.SPECS[D.ORDER[r]].setback) - float(D.SPECS[D.ORDER[(r + 1) % D.ORDER.size()]].setback)))
	var worst := 0.0
	for idx in range(1, D.RUN * D.ORDER.size() * 2 + 1):
		var step := absf(D.setback_at(idx) - D.setback_at(idx - 1))
		worst = maxf(worst, step)
	if worst > gap_max / 5.0 + 0.01:
		_fail("the worst setback step is %.2f m; a fifth of the biggest difference is %.2f m" % [worst, gap_max / 5.0])
	print("blend: worst setback step %.2f m over two loops" % worst)

# Builds one whole loop and returns per-kind numbers from its pure chunks.
func _check_look() -> Dictionary:
	var D := B.Districts
	var K := B.BuildingKit
	seed(4242)
	var stats := {}
	for name in D.SPECS:
		stats[name] = {"slots": 0, "built": 0, "h_sum": 0.0, "h_max": 0.0, "lit_sum": 0.0, "types": {}, "tints": {}}
	var chunks := D.RUN * D.ORDER.size()
	var t_build := 0.0
	var t_rebuild := 0.0
	var pooled := B.build_chunk(0, _cfg(2, 2, false), _cfg(2, 2, false))
	for idx in chunks:
		var cfg := _cfg(1 + idx % 4, 1 + (idx / 4) % 2, idx % 3 == 0)
		var t0 := Time.get_ticks_usec()
		var fresh := B.build_chunk(idx, _cfg(2, 2, false), cfg)
		var t1 := Time.get_ticks_usec()
		B.rebuild_chunk(pooled, idx, _cfg(2, 2, false), cfg)
		var t2 := Time.get_ticks_usec()
		t_build += float(t1 - t0) / 1000.0
		t_rebuild += float(t2 - t1) / 1000.0
		var pure := float(D.blend_at(idx)[1]) == 0.0
		var name: String = D.name_at(idx)
		var spec: Dictionary = D.SPECS[name]
		var st: Dictionary = stats[name]
		for i in B._building_slots() * 2:
			var mi: MeshInstance3D = fresh.get_node(NodePath("BuildingMesh%d" % i))
			var type: String = mi.get_meta("building_type", "")
			var built := mi.visible and type != "lot"
			if built:
				# support: the block reaches the road (or below it)
				var bottom := mi.transform.origin.y - mi.transform.basis.get_scale().y / 2.0
				if bottom > 0.01:
					_fail("chunk %d building %d: the block ends %.2f m above the road" % [idx, i, bottom])
			if not pure or D.landmark_at(idx, i) != "" or Junction.touches(idx):
				continue
			st.slots += 1
			if not built:
				continue
			var h := mi.transform.basis.get_scale().y
			st.built += 1
			st.h_sum += h
			st.h_max = maxf(st.h_max, h)
			st.lit_sum += float(mi.get_instance_shader_parameter("lit_density"))
			st.types[type] = st.types.get(type, 0) + 1
			var ok_type: bool = type == spec.low
			for e in spec.mix:
				ok_type = ok_type or type == e[0]
			if not ok_type:
				_fail("chunk %d building %d: a %s in %s" % [idx, i, type, name])
			var tint: Vector3 = mi.get_instance_shader_parameter("tint")
			var ti := _tint_index(tint, K)
			st.tints[ti] = st.tints.get(ti, 0) + 1
			var palette: Array = spec.get("tints", D.DEFAULTS.tints)
			var ok_tint := palette.is_empty() and ti >= 0 and ti < K.DEFAULT_TINTS
			for e in palette:
				ok_tint = ok_tint or ti == int(e[0])
			if not ok_tint:
				_fail("chunk %d building %d: tint %d is not in %s's palette" % [idx, i, ti, name])
		fresh.free()
	pooled.free()
	for name in D.SPECS:
		var st: Dictionary = stats[name]
		for e in D.SPECS[name].mix:
			if int(e[1]) >= 10 and not st.types.has(e[0]):
				_fail("district %s: no %s in a whole loop" % [name, e[0]])
		st["h_mean"] = st.h_sum / maxf(1.0, float(st.built))
		st["fill"] = float(st.built) / maxf(1.0, float(st.slots))
		st["lit"] = st.lit_sum / maxf(1.0, float(st.built))
		print("%-12s built %3d of %3d (%.2f)  roof mean %5.1f m, max %5.1f m  lit %.2f  landmark %-13s types %s" % [name, st.built, st.slots, st.fill, st.h_mean, st.h_max, st.lit, D.SPECS[name].get("landmark", ""), st.types])
	print("build cost: fresh %.2f ms/chunk, rebuild %.2f ms/chunk, over %d chunks" % [t_build / chunks, t_rebuild / chunks, chunks])
	return stats

# Which TINTS entry a building's tint is a 0.65..0.85 shade of, or -1.
func _tint_index(tint: Vector3, K) -> int:
	for i in K.TINTS.size():
		var c: Color = K.TINTS[i]
		var k := tint.x / c.r
		if k > 0.64 and k < 0.86 and absf(tint.y - c.g * k) < 1e-3 and absf(tint.z - c.b * k) < 1e-3:
			return i
	return -1

func _check_skyline(stats: Dictionary) -> void:
	var D := B.Districts
	var names: Array = D.SPECS.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var n := _differences(D, stats, names[i], names[j])
			if n < 1:
				_fail("%s and %s share a skyline: same landmark, roof height and fill" % [names[i], names[j]])
	for r in D.ORDER.size():
		var a: String = D.ORDER[r]
		var b: String = D.ORDER[(r + 1) % D.ORDER.size()]
		if _differences(D, stats, a, b) < 2:
			_fail("neighbours %s and %s differ in fewer than two of landmark, roof height, fill" % [a, b])

func _differences(D, stats: Dictionary, a: String, b: String) -> int:
	var n := 0
	if String(D.SPECS[a].get("landmark", "")) != String(D.SPECS[b].get("landmark", "")):
		n += 1
	var ha: float = stats[a].h_mean
	var hb: float = stats[b].h_mean
	if maxf(ha, hb) / maxf(0.1, minf(ha, hb)) >= 1.3:
		n += 1
	if absf(float(stats[a].fill) - float(stats[b].fill)) >= 0.2:
		n += 1
	return n

# How tall a rooftop shape is at scale 1, m (RoofProps.mesh()).
func _shape_h(R, shape: int) -> float:
	if shape == R.SHAPE_TANK:
		return 3.6
	if shape == R.SHAPE_ANTENNA:
		return 6.14
	if shape == R.SHAPE_FLOOD:
		return 5.15
	return 1.0

func _check_landmark_support() -> void:
	var D := B.Districts
	var R := B.RoofProps
	for kind in R.LANDMARKS:
		var bld: Dictionary = D.LANDMARK_BUILDING[kind]
		for side in [1, -1]:
			var w := 14.0
			var d := 20.0
			var h: float = bld.h
			var front := 12.0
			var cx := (front + w / 2.0) * float(side)
			var cz := -37.5
			var info := {"side": side, "w": w, "d": d, "h": h, "type": bld.type, "front_x_abs": front, "lot_front_x_abs": front, "z": cz, "landmark": kind}
			var pieces: Array = R._landmark(kind, info, cx, cz)
			# the building's own roof shape can carry a piece (the tower's
			# mast stands on its crown)
			var rng := RandomNumberGenerator.new()
			var held_by: Array = pieces + R._apply_top(B.BuildingKit.LANDMARK_TOP[kind], [], info, rng, cx, cz)
			if pieces.is_empty():
				_fail("landmark %s builds nothing" % kind)
			for p in pieces:
				var pos: Vector3 = p[2]
				var held := false
				if absf(pos.y) < 0.01:
					held = true  # on the ground
				elif absf(pos.y - h) < 0.01:
					# on the roof: its centre is over the building
					held = absf(pos.x - cx) <= w / 2.0 + 0.01 and absf(pos.z - cz) <= d / 2.0 + 0.01
				else:
					var ps: Vector3 = p[1]
					for q in held_by:
						if is_same(q, p):
							continue
						var qpos: Vector3 = q[2]
						var qs: Vector3 = q[1]
						var top := qpos.y + qs.y * _shape_h(R, int(q[0]))
						# resting on q: its base is at q's top and the two overlap in plan
						if absf(top - pos.y) < 0.15 and absf(pos.x - qpos.x) < (qs.x + ps.x) / 2.0 and absf(pos.z - qpos.z) < (qs.z + ps.z) / 2.0:
							held = true
				if not held:
					_fail("landmark %s (side %d): a piece at %s floats" % [kind, side, pos])
	print("support: %d landmarks, every piece stands on the ground, the roof or another piece" % R.LANDMARKS.size())
