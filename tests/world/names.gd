extends SceneTree

# Names you can read (world step 4, 2026-10-10): the name table, the lettering
# atlas, the area gantry and advance sign, the painted road words, the street
# blades and the head unit's area banner. Everything here is data and node
# counts, so it runs headless; what the signs look like is
# tools/world_names_shots.gd.
#
# Checks:
# - every district in districts.gd has a name in PlaceNames, in capitals, and
#   every word the world prints has an atlas layer that actually has letters in
#   it, inside the visible band, narrower than the layer
# - the gantry panel clears 4.5 m, fits MAX_PANEL_LEN, its post stands outside
#   the sidewalk and goes below the road on a hilly one; the advance sign's
#   panel clears a car and stays over the sidewalk side
# - one gantry and one advance sign per district run, in the right chunks,
#   none before chunk 0, and a built chunk draws exactly those instances
# - painted marks stay inside their lanes, never where the lane count tapers,
#   fit the chunk's capacity at 4 lanes, and the paint is the lane dashes' paint
# - the head unit shows the area name for AREA_SECS and then goes back
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/names.gd

const PlaceNames := preload("res://scripts/world/place_names.gd")
const WordAtlas := preload("res://scripts/world/word_atlas.gd")
const RoadSigns := preload("res://scripts/world/road_signs.gd")
const RoadPaint := preload("res://scripts/world/road_paint.gd")
const Districts := preload("res://scripts/world/districts.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")

var failures: Array[String] = []
var checks := 0

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	_table()
	_atlas()
	_signs()
	_schedule()
	_built()
	_paint()
	_head_unit()
	if failures.is_empty():
		print("names: %d checks PASS" % checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL ", f)
		print("names: %d failure(s) of %d checks" % [failures.size(), checks])
		quit(1)

func _table() -> void:
	for k in Districts.SPECS:
		_check(PlaceNames.AREAS.has(k), "district '%s' has no entry in PlaceNames.AREAS" % k)
	for k in PlaceNames.AREAS:
		_check(Districts.SPECS.has(k), "PlaceNames.AREAS has '%s', which is not a district" % k)
		var n := PlaceNames.area_name(k)
		_check(n != "" and n == n.to_upper(), "area '%s' name '%s' is empty or not in capitals" % [k, n])
	var words := PlaceNames.atlas_words()
	for i in words.size():
		_check(words.find(words[i]) == i, "atlas word '%s' is listed twice" % words[i])
	_check(PlaceNames.cross_street(0) != "" and PlaceNames.cross_street(-3) != "", "cross_street gave no name")

func _atlas() -> void:
	var words := PlaceNames.atlas_words()
	_check(WordAtlas.layer_count() == words.size(), "atlas has %d layers for %d words" % [WordAtlas.layer_count(), words.size()])
	_check(WordAtlas.layer_count() <= 32, "atlas has %d layers (32 max)" % WordAtlas.layer_count())
	for w in words:
		var l := WordAtlas.layer(w)
		_check(l >= 0, "word '%s' has no atlas layer" % w)
		if l < 0:
			continue
		var px := WordAtlas.width_px(w)
		_check(px > 8 and px + 2 * WordAtlas.PAD <= WordAtlas.W, "word '%s' is %d px wide in a %d px layer" % [w, px, WordAtlas.W])
		var img: Image = WordAtlas.images[l]
		var lit := 0
		var stray := 0
		var right := 0
		for y in WordAtlas.H:
			for x in WordAtlas.W:
				if img.get_pixel(x, y).r > 0.5:
					lit += 1
					if y < WordAtlas.Y0 or y >= WordAtlas.Y0 + WordAtlas.BAND:
						stray += 1
					right = maxi(right, x)
		_check(lit > 120, "word '%s' drew only %d lit pixels (font not loaded?)" % [w, lit])
		_check(stray == 0, "word '%s' has %d lit pixels outside the visible band" % [w, stray])
		_check(right <= WordAtlas.PAD + px + 1, "word '%s' is wider than its recorded %d px (ink to %d)" % [w, px, right])

func _signs() -> void:
	for k in PlaceNames.AREAS:
		var area := PlaceNames.area_name(k)
		var g := RoadSigns.gantry(area, Vector3(17.5, 0.0, -42.0), 4.0, 1)
		_check(g.size() == 8, "gantry for '%s' has %d parts (expected 8)" % [area, g.size()])
		var lowest := 1e9
		var post_bottom := 1e9
		var leftmost := 1e9
		var dead := 0
		for it in g:
			var xf: Transform3D = it.xf
			var half := xf.basis.get_scale() / 2.0
			var style := int(it.cd.a)
			if style == RoadSigns.METAL and half.y > 3.0:
				post_bottom = minf(post_bottom, xf.origin.y - half.y)
				continue
			if style == RoadSigns.LAMP_DEAD:
				dead += 1
			if style == RoadSigns.METAL:
				continue
			lowest = minf(lowest, xf.origin.y - half.y)
			leftmost = minf(leftmost, xf.origin.x - half.z)
		_check(lowest >= 4.5, "gantry '%s' lowest part is %.2f m over the road" % [area, lowest])
		_check(RoadSigns.gantry_clearance(area) >= 4.5, "gantry_clearance('%s') = %.2f" % [area, RoadSigns.gantry_clearance(area)])
		_check(post_bottom <= -3.9, "gantry '%s' post stops %.2f m below the road (hill foundation 4 m)" % [area, post_bottom])
		_check(dead == 1, "gantry '%s' with lamp 1 burnt out has %d dead lamps" % [area, dead])
		_check(17.5 - leftmost <= RoadSigns.MAX_PANEL_LEN + 1.5, "gantry '%s' reaches %.1f m from its post" % [area, 17.5 - leftmost])
		var a := RoadSigns.advance(area, Vector3(17.5, 0.0, -2.0), 0.0)
		_check(a.size() == 5, "advance sign for '%s' has %d parts (expected 5)" % [area, a.size()])
		for it in a:
			var xf2: Transform3D = it.xf
			if int(it.cd.a) == RoadSigns.PANEL:
				var low := xf2.origin.y - xf2.basis.get_scale().y / 2.0
				_check(low >= 2.5, "advance sign '%s' bottom is %.2f m up" % [area, low])
				_check(xf2.basis.get_scale().z <= 8.0, "advance sign '%s' panel is %.1f m long" % [area, xf2.basis.get_scale().z])
	# a lettering plate is as long as its word needs for its height: letters keep their shape
	var p := RoadSigns.text_plate("DOWNTOWN", Vector3.ZERO, Vector3.BACK, 1.0, RoadSigns.OFF_WHITE)
	var want := float(WordAtlas.width_px("DOWNTOWN") + 2 * WordAtlas.PAD) / float(WordAtlas.BAND)
	_check(absf(p.xf.basis.get_scale().z - want) < 0.001, "text plate length %.3f, expected %.3f" % [p.xf.basis.get_scale().z, want])
	# a blade reads from the front: its front (local -x) faces the traffic it is built for
	var bl := RoadSigns.blade("5TH ST", Vector3.ZERO, Vector3.BACK)
	_check((bl.xf.basis.x.normalized() + Vector3.BACK).length() < 0.001, "blade front does not face +z")

func _schedule() -> void:
	var gantries := 0
	var advances := 0
	for c in range(-3, Districts.RUN * 5):
		var kind := B.name_sign_kind(c)
		if c < 0:
			_check(kind == "", "chunk %d (before the road) has a '%s' sign" % [c, kind])
		if kind == "gantry":
			gantries += 1
			_check(posmod(c + 1, Districts.RUN) == 0, "gantry in chunk %d is not the last of its run" % c)
		elif kind == "advance":
			advances += 1
			_check(posmod(c + 1 + 8, Districts.RUN) == 0, "advance sign in chunk %d is not 8 chunks before a run" % c)
	_check(gantries == 5 and advances == 5, "5 runs gave %d gantries and %d advance signs" % [gantries, advances])
	_check(B.name_sign_kind(Districts.RUN - 1) == "gantry", "chunk 15 (before the first run change) has no gantry")
	_check(B.name_sign_kind(Districts.RUN - 8 - 1) == "advance", "chunk 7 has no advance sign")
	_check(B.name_sign_kind(0) == "", "chunk 0 has a name sign")

func _built() -> void:
	RoadFrame.align = null
	RoadFrame.origin_index = 0
	var cfg := {"own_lanes": 2, "onc_lanes": 1, "barrier": false}
	var counts := {}
	for c in [3, 7, 15, 16, 17, 23, 31]:
		var root := B.build_chunk(c, cfg, cfg)
		var signs: MultiMesh = (root.get_node(^"NameSigns") as MultiMeshInstance3D).multimesh
		counts[c] = signs.visible_instance_count
		root.free()
	_check(counts[7] == 5, "chunk 7 draws %d name-sign parts (advance: 5)" % counts[7])
	_check(counts[15] == 8, "chunk 15 draws %d name-sign parts (gantry: 8)" % counts[15])
	_check(counts[23] == 5 and counts[31] == 8, "chunks 23 / 31 draw %d / %d" % [counts[23], counts[31]])
	_check(counts[3] == 0 and counts[16] == 0 and counts[17] == 0, "an ordinary chunk draws name signs: %s" % [counts])

func _paint() -> void:
	_check(RoadPaint.PAINT_COLOR.is_equal_approx(B.LANE_DASH_COLOR), "road paint colour is not the lane dashes' colour")
	_check(is_equal_approx(RoadPaint.PAINT_ENERGY, B.PAINT_ENERGY), "road paint glow is not the lane dashes' glow")
	var mg := B.MEDIAN_GAP
	var lw := B.LANE_W
	var cl := B.CHUNK_LEN
	var biggest := 0
	for lanes in [1, 2, 3, 4]:
		for c in range(1, 64):
			var d := Districts.name_at(c)
			for crossing in [INF, float(c) * cl - 600.0]:
				var marks := RoadPaint.marks(c, d, Districts.RUN, lanes, false, crossing, mg, lw, cl)
				biggest = maxi(biggest, marks.size())
				for m in marks:
					var half_w: float = m.basis.get_scale().x / 2.0
					_check(m.x - half_w >= mg - 0.05 and m.x + half_w <= mg + float(lanes) * lw + 0.05, "chunk %d: a mark at x=%.2f (%.1f m wide) leaves the %d own lanes" % [c, m.x, half_w * 2.0, lanes])
					var half_l: float = m.basis.get_scale().z / 2.0
					_check(m.z + half_l <= 0.0 and m.z - half_l >= -cl, "chunk %d: a mark at z=%.1f (%.1f m long) leaves its chunk" % [c, m.z, half_l * 2.0])
	_check(biggest <= RoadPaint.CAPACITY, "a chunk wants %d marks (capacity %d)" % [biggest, RoadPaint.CAPACITY])
	_check(biggest >= 4, "no chunk got the crossing's approach marks (biggest %d)" % biggest)
	# nothing where the lane count tapers
	_check(RoadPaint.marks(17, "residential", Districts.RUN, 3, true, float(17) * cl - 600.0, mg, lw, cl).is_empty(), "paint on a chunk where the lane count changes")
	# an area's number: second chunk of a run, in that district's speed
	var first := RoadPaint.marks(Districts.RUN + 1, "residential", Districts.RUN, 2, false, INF, mg, lw, cl)
	_check(first.size() == 1 and int(first[0].cd.r) == WordAtlas.layer("30"), "the residential area's start has no painted 30")
	var plain := RoadPaint.marks(Districts.RUN + 5, "residential", Districts.RUN, 2, false, INF, mg, lw, cl)
	_check(plain.is_empty(), "an ordinary residential chunk has %d marks" % plain.size())
	# a built chunk draws its marks: with the crossing on, the chunk 32 m + 75 m before it
	Junction.enabled = true
	var cfg := {"own_lanes": 3, "onc_lanes": 1, "barrier": false}
	RoadFrame.align = null
	RoadFrame.origin_index = 0
	var drawn := 0
	for c in range(0, 14):
		var root := B.build_chunk(c, cfg, cfg)
		var mm: MultiMesh = (root.get_node(^"RoadPaint") as MultiMeshInstance3D).multimesh
		drawn += mm.visible_instance_count
		root.free()
	Junction.enabled = false
	_check(drawn >= 6, "the crossing's approach chunks drew %d marks (3 SLOW + 3 arrows expected)" % drawn)

func _head_unit() -> void:
	var u := HeadUnit.new("p1_coupe")
	root.add_child(u)
	_check(u.area_t == 0.0, "head unit starts with an area banner")
	u.show_area("THE STRIP")
	_check(u.area_name == "THE STRIP" and is_equal_approx(u.area_t, HeadUnit.AREA_SECS), "show_area did not set the banner")
	u.show_state(-1, "", 0.0, HeadUnit.AREA_SECS * 0.5)
	_check(u.area_t > 0.0, "banner ended after half its time")
	u.show_state(-1, "", 0.0, HeadUnit.AREA_SECS)
	_check(u.area_t == 0.0, "banner did not end")
	u.free()
