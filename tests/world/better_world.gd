extends SceneTree

# Better world, first cheap batch (2026-10-13; notes/better-world-2026-10-13.md
# B1, B2, B3, B4, B8; issues #652, #653, #654). Headless: tables, plans,
# materials and Environment values, no pixels.
#
# Asserts (exit code 1 on failure):
# - B4 loop: act 1 of Loop 1 is Roy's 8-look order exactly (downtown, old
#   town, strip, industrial, docks, lofts, residential, freeway); by act 3
#   every district kind is on the loop; at every act no kind follows itself,
#   the wrap back to District 1 included; areas stay per slot (city, city,
#   highway, highway), so the crossings did not move
# - B1 tables: every kind in Districts.SPECS has its own row in the sky glow,
#   the air, the roadside kit, the banner slots (all different), the kerb
#   table (or is an open, kerbless kind), the paint wear and the area names;
#   the canyon's glow dome is under half as bright as downtown's
# - B2 lamp fit: on each lamp shape the moth swarm's centre is within
#   FIT_HEAD_M of the lamp's head (its emissive surface), the banner hangs
#   between BANNER_MIN_Y and just under the head, clear of the pole; no bat
#   under a post lantern; a built chunk passes its street's lamp shape
# - B3 paint: every kind keeps 40-70 % of its paint (Roy 1516: worn), what is
#   left is dimmer than fresh paint and below the glow threshold; the share
#   the shader's wear function keeps (measured over many dashes and line
#   metres) is the table's cover to within COVER_TOL; a built chunk's dashes
#   and lines wear its district's paint, and a chunk recycled into another
#   district changes with it
# - B8 air: every kind's fog is at least the base (chunks appear 250-350 m
#   out; thinner fog would show them pop) and at most AIR_MAX_FOG times it;
#   fog colours are muted and never lean green or cyan; the mist is off at
#   1 a.m. and 6 a.m. and peaks at 4:30; SkyDirector writes the blend to the
#   Environment
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/better_world.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Districts := preload("res://scripts/world/districts.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const Kit := preload("res://scripts/world/roadside_kit.gd")
const L := preload("res://scripts/world/lamp_life.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")

const ACT1 := ["downtown", "old_town", "strip", "industrial", "docks", "lofts", "residential", "freeway"]
const AREAS := ["city", "city", "highway", "highway"]
const FIT_HEAD_M := 0.6        # moth orbit centre to the lamp head's box
const BANNER_MIN_Y := 2.2      # banner hem above the pavement, m
const COVER_TOL := 0.08        # measured kept share vs the table's cover
const COVER_MIN := 0.40
const COVER_MAX := 0.70
const FADE_MAX := 0.80         # dimmer than fresh paint
const AIR_MAX_FOG := 1.5
const AIR_MAX_CHANNEL := 0.12  # muted fog colour
const CFG := {"own_lanes": 3, "onc_lanes": 3, "barrier": false}

var fails := 0
var checks := 0

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_loop()
	_check_tables()
	_check_lamp_fit()
	_check_paint_table()
	_check_air()
	_check_chunks()
	RoadMap.use(RoadMap.ENDLESS)
	print("better_world: %d checks, %s" % [checks, "PASS" if fails == 0 else "%d failure(s)" % fails])
	quit(0 if fails == 0 else 1)

# ---------- B4 ----------

func _check_loop() -> void:
	var seen := {}
	for act in [1, 2, 3]:
		RoadMap.use(RoadMap.DEFAULT, act)
		var n := RoadMap.district_count()
		_check(n == [8, 12, 16][act - 1], "act %d has %d districts" % [act, n])
		var kinds := []
		for i in n:
			kinds.append(RoadMap.district_kind(i))
			seen[RoadMap.district_kind(i)] = true
			_check(String(RoadMap.district_info(i).area) == AREAS[i % 4], "act %d district %d area %s, slot wants %s" % [act, i + 1, RoadMap.district_info(i).area, AREAS[i % 4]])
		for i in n:
			_check(kinds[i] != kinds[(i + 1) % n], "act %d: district %d and %d are both %s" % [act, i + 1, (i + 1) % n + 1, kinds[i]])
		if act == 1:
			_check(kinds == ACT1, "act 1 order is %s, Roy's is %s" % [kinds, ACT1])
		print("loop act %d: %s" % [act, kinds])
	for k in Districts.SPECS:
		_check(seen.has(k), "kind %s never on the loop by act 3" % k)
	RoadMap.use(RoadMap.DEFAULT, 1)
	# the chunk lookups follow the map
	for i in 8:
		var c := int(RoadMap.district_start(i) / B.CHUNK_LEN) + 5
		_check(Districts.name_at(c) == ACT1[i], "chunk %d is %s, district %d is %s" % [c, Districts.name_at(c), i + 1, ACT1[i]])

# ---------- B1 ----------

func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

func _check_tables() -> void:
	var slots := {}
	for k in Districts.SPECS:
		_check(NightSky.GLOW.has(k), "%s has no sky glow row" % k)
		_check(NightSky.AIR.has(k), "%s has no air row" % k)
		_check(Kit.BY_DISTRICT.has(k), "%s has no roadside kit row" % k)
		_check(L.SLOTS.has(k), "%s has no banner slot" % k)
		_check(Districts.CROSS.has(k) or k in Districts.CROSS_OPEN, "%s has no kerb row and is not open" % k)
		_check(Districts.PAINT.has(k), "%s has no paint wear row" % k)
		_check(PlaceNames.AREAS.has(k), "%s has no area name" % k)
		if L.SLOTS.has(k):
			slots[L.district_slot(k)] = k
	_check(slots.size() == Districts.SPECS.size(), "banner slots shared: %s" % str(slots))
	var dt := _lum(NightSky.GLOW["downtown"].color) * float(NightSky.GLOW["downtown"].height_deg)
	var cy := _lum(NightSky.GLOW["canyon"].color) * float(NightSky.GLOW["canyon"].height_deg)
	_check(cy < 0.5 * dt, "canyon glow %.4f is not under half downtown's %.4f" % [cy, dt])
	# the kerb rows differ from each other
	var sections := {}
	for k in Districts.CROSS:
		var r: Dictionary = Districts.CROSS[k]
		sections["%s/%s/%s" % [r.walk, r.shoulder, r.kerb_h]] = k
	_check(sections.size() == Districts.CROSS.size(), "kerb rows repeat: %d sections for %d kinds" % [sections.size(), Districts.CROSS.size()])

# ---------- B2 ----------

func _head_box(kind: String) -> AABB:
	var mesh := B._get_lamp_mesh(kind, "sodium")
	var v: PackedVector3Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	return box

func _dist_to_box(p: Vector3, box: AABB) -> float:
	var q := Vector3(clampf(p.x, box.position.x, box.end.x), clampf(p.y, box.position.y, box.end.y), clampf(p.z, box.position.z, box.end.z))
	return p.distance_to(q)

func _check_lamp_fit() -> void:
	for kind in B.LAMP_KINDS:
		_check(L.FIT.has(kind), "lamp shape %s has no fit row" % kind)
		var off: Array = L.fit_offsets(kind)
		var head := _head_box(kind)
		# the swarm orbits HEAD + (0, -0.25, 0) in mesh space
		var centre: Vector3 = (off[0] as Transform3D) * (L.HEAD + Vector3(0.0, -0.25, 0.0))
		var d := _dist_to_box(centre, head)
		_check(d <= FIT_HEAD_M, "%s: moths %.2f m from the lamp head (box %s), allowed %.2f" % [kind, d, str(head), FIT_HEAD_M])
		var bxf: Transform3D = off[1]
		var top := bxf * Vector3(L.BANNER_X, L.BANNER_TOP + 0.06, 0.0)
		var hem := bxf * Vector3(L.BANNER_X, L.BANNER_TOP - L.BANNER_H, 0.0)
		var pole_h := float(B.LAMP_KINDS[kind].h)
		_check(hem.y >= BANNER_MIN_Y, "%s: banner hem at %.2f m, under %.2f" % [kind, hem.y, BANNER_MIN_Y])
		_check(top.y <= minf(head.position.y, pole_h) - 0.15, "%s: banner bracket at %.2f m, head starts %.2f, pole %.2f" % [kind, top.y, head.position.y, pole_h])
		# the cloth hangs outside the pole's own box (the widest pole piece)
		_check(absf(top.x) > 0.19, "%s: banner %.2f m from the pole axis, inside the pole" % [kind, absf(top.x)])
		print("lamp %-5s moths %.2f m from head, banner %.2f-%.2f m (pole %.1f)" % [kind, d, hem.y, top.y, pole_h])
	# no bat under a post lantern
	var xfs := []
	for k in 4:
		xfs.append(Transform3D(Basis(), Vector3(9.0, 0.0, -6.25 - 12.5 * float(k))))
	for c in 200:
		for m in L.plan(c, "old_town", xfs, "post").moths:
			_check((m.custom as Color).a == 0.0, "chunk %d: a bat under a post lantern" % c)
	# the plan carries the offset
	var p: Dictionary = L.plan(3, "airport", xfs, "mast")
	if not p.banners.is_empty():
		var want: Transform3D = (xfs[0] as Transform3D) * (L.fit_offsets("mast")[1] as Transform3D)
		var got: Transform3D = p.banners[0].xf
		_check(got.origin.y > 1.0 or want.origin.y == got.origin.y, "mast banner not moved up: %s" % str(got.origin))

# ---------- B3 ----------

## Measured on dashes and line metres the PAINT_CUT tables were not fitted
## on (ids from 100, line metres past 100 m), through the material's own cut.
func _kept_share(cut: float, seed_v: float, line: bool) -> float:
	var kept := 0
	var n := 0
	if line:
		for zi in 6000:
			for xi in 3:
				var lp := Vector3(-0.1 + 0.1 * float(xi), 0.0, -100.0 - float(zi) * 0.05)
				n += 1
				if B.paint_keep(lp, seed_v, 0, true) <= cut:
					kept += 1
	else:
		for id in range(100, 400):
			for zi in 12:
				for xi in 3:
					var lp := Vector3(-0.08 + 0.08 * float(xi), 0.0, -1.1 + 0.2 * float(zi))
					n += 1
					if B.paint_keep(lp, seed_v, id, false) <= cut:
						kept += 1
	return float(kept) / float(n)

func _check_paint_table() -> void:
	for k in Districts.PAINT:
		var w: Array = Districts.PAINT[k]
		var cover := float(w[0])
		var fade := float(w[1])
		_check(cover >= COVER_MIN and cover <= COVER_MAX, "%s keeps %.2f of its paint, want %.2f-%.2f" % [k, cover, COVER_MIN, COVER_MAX])
		_check(fade <= FADE_MAX, "%s paint fade %.2f, not dimmer than %.2f" % [k, fade, FADE_MAX])
		_check(B.PAINT_ENERGY * fade < 1.0, "%s paint glows" % k)
		for mark in ["lane", "edge", "centre"]:
			var m: ShaderMaterial = B._paint_mat(mark, k, 1)
			var line: bool = mark == "edge"
			var share := _kept_share(float(m.get_shader_parameter("cut")), float(m.get_shader_parameter("seed")), line)
			_check(absf(share - cover) <= COVER_TOL, "%s %s: %.2f of the paint kept, table says %.2f" % [k, mark, share, cover])
			print("paint %-11s %-6s cover %.2f fade %.2f: keeps %.2f" % [k, mark, cover, fade, share])

# ---------- B8 ----------

func _check_air() -> void:
	for k in NightSky.AIR:
		var a: Dictionary = NightSky.AIR[k]
		_check(float(a.fog) >= 1.0, "%s fog %.2f thinner than the base: chunks would pop in" % [k, float(a.fog)])
		_check(float(a.fog) <= AIR_MAX_FOG, "%s fog %.2f over %.2f" % [k, float(a.fog), AIR_MAX_FOG])
		var c: Color = a.color
		_check(maxf(c.r, maxf(c.g, c.b)) <= AIR_MAX_CHANNEL, "%s fog colour %s not muted" % [k, str(c)])
		_check(c.g <= maxf(c.r, c.b) + 0.005, "%s fog colour %s leans green/cyan" % [k, str(c)])
		_check(float(a.sat) >= 0.85 and float(a.sat) <= 1.05, "%s grade saturation %.2f" % [k, float(a.sat)])
	_check(NightSky.AIR["docks"].fog == NightSky.AIR.values().map(func(x): return x.fog).max(), "the docks are not the densest air")
	_check(is_equal_approx(NightSky.mist_for_minutes(300.0), 1.0), "mist at 1 a.m.")
	_check(is_equal_approx(NightSky.mist_for_minutes(600.0), 1.0), "mist at 6 a.m.")
	_check(is_equal_approx(NightSky.mist_for_minutes(510.0), 1.0 + NightSky.MIST_PEAK), "mist at 4:30 is not the peak")
	_check(NightSky.mist_for_minutes(480.0) > 1.1 and NightSky.mist_for_minutes(560.0) > 1.05, "no mist around 4 a.m.")
	# SkyDirector writes the blend
	var sd := SkyDirector.new()
	sd.env = Environment.new()
	sd.env.adjustment_saturation = 1.0
	sd._from_air = NightSky.air("downtown")
	sd._to_air = NightSky.air("docks")
	sd._mist = 1.0
	sd._base_sat = 1.0
	sd._apply_air(0.5)
	var want := NightSky.FOG_DENSITY * lerpf(1.0, float(NightSky.AIR["docks"].fog), 0.5)
	_check(absf(sd.env.fog_density - want) < 1e-6, "half-way fog %.5f, want %.5f" % [sd.env.fog_density, want])
	sd._mist = NightSky.mist_for_minutes(510.0)
	sd._apply_air(1.0)
	want = NightSky.FOG_DENSITY * float(NightSky.AIR["docks"].fog) * (1.0 + NightSky.MIST_PEAK)
	_check(absf(sd.env.fog_density - want) < 1e-6, "docks at 4:30 fog %.5f, want %.5f" % [sd.env.fog_density, want])
	_check(is_equal_approx(sd.env.adjustment_saturation, float(NightSky.AIR["docks"].sat)), "grade saturation not written")
	sd.free()

# ---------- built chunks ----------

func _check_chunks() -> void:
	RoadMap.use(RoadMap.DEFAULT, 1)
	Junction.enabled = false
	RoadFrame.layout = null
	var holder := Node3D.new()
	root.add_child(holder)
	var first: Node3D = null
	for i in 8:
		var c := int(RoadMap.district_start(i) / B.CHUNK_LEN) + 5
		var kind: String = ACT1[i]
		var chunk: Node3D = B.build_chunk(c, CFG, CFG)
		holder.add_child(chunk)
		var lane := (chunk.get_node(^"LaneDashes") as MultiMeshInstance3D).material_override as ShaderMaterial
		var edge := (chunk.get_node(^"EdgeLineOwn") as MeshInstance3D).material_override as ShaderMaterial
		_check(lane != null and is_equal_approx(float(lane.get_shader_parameter("cover")), float(Districts.PAINT[kind][0])), "%s chunk %d: dashes not worn as %s" % [kind, c, kind])
		_check(edge != null and is_equal_approx(float(edge.get_shader_parameter("fade")), float(Districts.PAINT[kind][1])), "%s chunk %d: edge line not faded as %s" % [kind, c, kind])
		if first == null:
			first = chunk
		else:
			holder.remove_child(chunk)
			chunk.free()
	# recycle the downtown chunk into the docks
	var docks_c := int(RoadMap.district_start(4) / B.CHUNK_LEN) + 6
	B.rebuild_chunk(first, docks_c, CFG, CFG)
	var lane2 := (first.get_node(^"LaneDashes") as MultiMeshInstance3D).material_override as ShaderMaterial
	_check(String(first.get_meta("paint_kit", "")).begins_with("docks/"), "recycled chunk's paint kit is %s" % first.get_meta("paint_kit", ""))
	_check(is_equal_approx(float(lane2.get_shader_parameter("cover")), float(Districts.PAINT["docks"][0])), "recycled chunk kept downtown's paint")
	var edge2 := (first.get_node(^"EdgeLineOnc") as MeshInstance3D).material_override as ShaderMaterial
	_check(is_equal_approx(float(edge2.get_shader_parameter("cover")), float(Districts.PAINT["docks"][0])), "recycled chunk's edge line kept downtown's paint")
	holder.queue_free()
	Junction.enabled = true
