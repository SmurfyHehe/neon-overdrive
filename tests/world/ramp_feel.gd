extends SceneTree

# The exit's feel and paint (ramps doc step 2, notes/better-ramps-and-
# destinations-2026-10-13.md sections 2.2, 2.4 and 2.5; Roy 1539).
#
# 1. Surface: a ramp's and the ring's deck read as concrete to the tyres
#    (SurfaceMap.Kind.CONCRETE), the expansion joint at V_TOP as JOINT, the
#    first 20 m of the deck's inside edge after the gore as RUMBLE; the feel
#    tables have a row for each band, wet never gripping better than dry.
#    The joint is a 15 mm ridge in the deck, gone 20 cm either side.
# 2. Paint: on every up-ramp a row of give-way triangles before the rim and
#    none on the down-ramp; a left-turn arrow on the deck at ARROW_V, lying on
#    the deck (every corner within 4 cm of it); the exit's word on the slip
#    lane about 50 m before its gore, reading for that carriageway; nothing
#    painted on the ring chunks themselves. The ring's lane has a dashed edge
#    line along both kerbs.
# 3. Light: kerb studs on every ramp row and every ring rim piece, amber and
#    lit (alpha drives the glow); the nose markers are the only thing in the
#    blink band of the shader, which pulses them at 1 Hz (under the 2.5 Hz
#    photosensitive band); the ring's two chevron boards each have a light
#    pool below them.
# 4. The bridge as the landmark (doc section 3): a lit lamp on each parapet
#    at every rim piece over the road (both rims, both bridges; steel-white at
#    a Docks ring), a wash of light on the road under each slab, sound zones
#    under each bridge (the radio breaks up, the car's own noise echoes:
#    TunnelAudio.bridge_amount) and on each deck, and graffiti on the piers'
#    faces downtown and in the Docks only.
# 5. Variety (doc 2.6): a steel truss over each span at a Docks ring, with
#    the light line on its top chord and white harbour lamps; a deep rusty
#    girder under each span at an industrial ring; a water tower on x4's
#    island and a toppled crane on x8's, the dead tree on x2's.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/world/ramp_feel.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const RingSite := preload("res://scripts/world/ring_site.gd")
const RoadPaint := preload("res://scripts/world/road_paint.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")
const WordAtlas := preload("res://scripts/world/word_atlas.gd")
const TunnelAudio := preload("res://scripts/audio/tunnel_audio.gd")

const L := 50.0
const K := SurfaceMap.Kind

var fails: Array[String] = []
var checks := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		_fail(msg)

func _initialize() -> void:
	RoadFrame.align = null
	RoadFrame.layout = null
	RoadFrame.origin_index = 0
	RoadMap.use(0, 1)
	_check(not RoadMap.rings().is_empty(), "act 1 has no ring sites")
	_surface()
	_paint()
	_light()
	# the ring node needs a tree that is up and running
	_pools.call_deferred()

func _finish() -> void:
	RoadMap.use(RoadMap.ENDLESS)
	print("ramp_feel: %d checks, %d failed" % [checks, fails.size()])
	quit(1 if not fails.is_empty() else 0)

## Road-space z of `s` metres along the road.
func _z_of(s: float) -> float:
	return float(RoadFrame.origin_index) * L - s

# ---------- 1. surface ----------

func _surface() -> void:
	_check(SurfaceMap.NAMES.size() == 8 and SurfaceFeel.DRY.size() == 8 and SurfaceFeel.WET.size() == 8, "the feel tables have %d / %d rows for %d bands" % [SurfaceFeel.DRY.size(), SurfaceFeel.WET.size(), SurfaceMap.NAMES.size()])
	for k in [K.CONCRETE, K.JOINT, K.RUMBLE]:
		var d: Array = SurfaceFeel.DRY[k]
		var w: Array = SurfaceFeel.WET[k]
		_check(w[SurfaceFeel.PEAK] <= d[SurfaceFeel.PEAK] and w[SurfaceFeel.ONSET] <= d[SurfaceFeel.ONSET], "%s grips better wet than dry" % SurfaceMap.NAMES[k])
	_check(SurfaceFeel.DRY[K.CONCRETE][SurfaceFeel.PEAK] > SurfaceFeel.DRY[K.ASPHALT][SurfaceFeel.PEAK], "concrete should grip a little better than asphalt dry")
	_check(SurfaceFeel.WET[K.CONCRETE][SurfaceFeel.PEAK] < SurfaceFeel.WET[K.ASPHALT][SurfaceFeel.PEAK], "wet concrete should grip less than wet asphalt")
	_check(SurfaceFeel.DRY[K.JOINT][SurfaceFeel.ROUGH] > SurfaceFeel.DRY[K.CONCRETE][SurfaceFeel.ROUGH] and SurfaceFeel.DRY[K.RUMBLE][SurfaceFeel.ROUGH] >= 0.9, "the joint and the rumble strip should be rougher than the deck")
	# the joint's ridge
	var x := RoadRamps.X_TOP
	var base := RoadRamps.y_at(RoadRamps.V_TOP) + RoadRamps.LIFT - RoadRamps.ring_drop(Vector2(x, RoadRamps.V_TOP).length())
	_check(absf(RoadRamps.deck_y(x, RoadRamps.V_TOP) - base - RoadRamps.JOINT_H) < 1e-6, "the joint's ridge is %.4f m (%.3f wanted)" % [RoadRamps.deck_y(x, RoadRamps.V_TOP) - base, RoadRamps.JOINT_H])
	for dv in [-RoadRamps.JOINT_W * 0.5 - 0.01, RoadRamps.JOINT_W * 0.5 + 0.01, -3.0, 3.0]:
		_check(RoadRamps.joint_lift(RoadRamps.V_TOP + dv) == 0.0, "the ridge is still %.4f m at %.2f m from the joint" % [RoadRamps.joint_lift(RoadRamps.V_TOP + dv), dv])
	# the bands, on every act-1 site, both sides and both legs
	for ri in RoadMap.rings().size():
		var r: Dictionary = RoadMap.rings()[ri]
		var site_s := float(r.s)
		for side in [1.0, -1.0]:
			for leg in [-1.0, 1.0]:
				var sd: float = side
				var lg: float = leg
				var probe := func(v: float, dx: float) -> int:
					var xx: float = sd * (RoadRamps.x_at(v) + dx)
					var u := Vector3(xx, RoadRamps.deck_y(RoadRamps.x_at(v) + dx, v), _z_of(site_s + lg * v))
					return SurfaceMap.deck_kind_at(u)
				_check(probe.call(100.0, 0.0) == K.CONCRETE, "ring %s side %d leg %d: mid-ramp reads %s" % [r.id, side, leg, SurfaceMap.NAMES[probe.call(100.0, 0.0)]])
				_check(probe.call(RoadRamps.V_TOP, 0.0) == K.JOINT and probe.call(RoadRamps.V_TOP, 1.5) == K.JOINT, "ring %s side %d leg %d: the joint reads %s" % [r.id, side, leg, SurfaceMap.NAMES[probe.call(RoadRamps.V_TOP, 0.0)]])
				_check(probe.call(RoadRamps.V_TOP + 1.0, 0.0) == K.CONCRETE, "ring %s side %d leg %d: 1 m past the joint reads %s" % [r.id, side, leg, SurfaceMap.NAMES[probe.call(RoadRamps.V_TOP + 1.0, 0.0)]])
				var gv := RoadRamps.V_GORE - 5.0
				_check(probe.call(gv, -RoadRamps.HALF + 0.2) == K.RUMBLE, "ring %s side %d leg %d: the deck's inside edge at the gore reads %s" % [r.id, side, leg, SurfaceMap.NAMES[probe.call(gv, -RoadRamps.HALF + 0.2)]])
				_check(probe.call(gv, 0.0) == K.CONCRETE, "ring %s side %d leg %d: the deck's middle at the gore reads %s" % [r.id, side, leg, SurfaceMap.NAMES[probe.call(gv, 0.0)]])
				_check(probe.call(RoadRamps.V_GORE - SurfaceMap.RUMBLE_LEN - 2.0, -RoadRamps.HALF + 0.2) == K.CONCRETE, "ring %s side %d leg %d: the inside edge past the strip reads rumble" % [r.id, side, leg])
		var a := deg_to_rad(100.0)
		var ru := Vector3(RoadRamps.X_TOP * cos(a), RoadRamps.RAMP_H - RoadRamps.ring_drop(RoadRamps.X_TOP), _z_of(site_s + RoadRamps.X_TOP * sin(a)))
		_check(SurfaceMap.deck_kind_at(ru) == K.CONCRETE, "ring %s: the ring's lane reads %s" % [r.id, SurfaceMap.NAMES[SurfaceMap.deck_kind_at(ru)]])

# ---------- 2. paint ----------

## One leg of a ramp laid out flat: {verts, cols, faces}.
func _leg(side: float, lam: float, d: int) -> Dictionary:
	RoadRamps.begin_flat()
	RoadRamps._k = -d - 1 if lam < 0.0 else d
	RoadRamps._lam = lam
	RoadRamps._side = side
	RoadRamps._leg(float(d) * L, float(d + 1) * L)
	var made := RoadRamps.end_flat()
	var arrays: Array = made.arrays
	return {"verts": arrays[Mesh.ARRAY_VERTEX], "cols": arrays[Mesh.ARRAY_COLOR], "faces": made.faces}

## Whether a mesh colour is `want` (a mesh keeps 8 bits per channel).
static func _is(c: Color, want: Color) -> bool:
	return absf(c.r - want.r) < 0.006 and absf(c.g - want.g) < 0.006 and absf(c.b - want.b) < 0.006 and absf(c.a - want.a) < 0.006

## Painted give-way triangles: C_PAINT, centred within `v0..v1` along, and
## GIVE_WAY_LEN long (the edge lines' triangles are a row long).
func _give_way_tris(leg: Dictionary, v0: float, v1: float) -> int:
	var verts: PackedVector3Array = leg.verts
	var cols: PackedColorArray = leg.cols
	var n := 0
	for t in range(0, verts.size(), 3):
		if _is(cols[t], RoadRamps.C_PAINT):
			var mid := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
			var v := -mid.z
			var span := maxf(maxf(verts[t].z, verts[t + 1].z), verts[t + 2].z) - minf(minf(verts[t].z, verts[t + 1].z), verts[t + 2].z)
			if v >= v0 and v <= v1 and absf(span - RoadRamps.GIVE_WAY_LEN) < 0.05:
				n += 1
	return n

func _paint() -> void:
	# give-way triangles on the up-ramp only, just before the rim
	var gv := RoadRamps.V_RING_IN + RoadRamps.GIVE_WAY_V
	for side in [1.0, -1.0]:
		var up := _leg(side, -side, 0)
		var down := _leg(side, side, 0)
		_check(_give_way_tris(up, gv - RoadRamps.GIVE_WAY_LEN - 0.05, gv + 0.05) == RoadRamps.GIVE_WAY_N, "side %d: %d give-way triangles on the up-ramp (%d wanted)" % [side, _give_way_tris(up, gv - RoadRamps.GIVE_WAY_LEN - 0.05, gv + 0.05), RoadRamps.GIVE_WAY_N])
		_check(_give_way_tris(down, gv - RoadRamps.GIVE_WAY_LEN - 0.05, gv + 0.05) == 0, "side %d: give-way triangles on the down-ramp" % side)
	# the ring's dashed edge lines: a dash on every other piece, both edges
	var made := RingSite.build(RingSite.look_of(0))
	var mesh: ArrayMesh = made.mesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var dashes_in := 0
	var dashes_out := 0
	var studs := 0
	for t in range(0, verts.size(), 3):
		var mid := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
		var r := Vector2(mid.x, mid.z).length()
		if _is(cols[t], RoadRamps.C_PAINT):
			if absf(r - RoadRamps.RING_IN - RingSite.DASH_IN) < 0.2:
				dashes_in += 1
			elif absf(r - RoadRamps.RING_OUT + RingSite.DASH_IN) < 0.2:
				dashes_out += 1
		elif _is(cols[t], RoadRamps.C_STUD):
			studs += 1
	_check(dashes_in >= RingSite.SEGS and dashes_out >= RingSite.SEGS, "the ring's edge lines: %d inner, %d outer dash triangles (%d each wanted)" % [dashes_in, dashes_out, RingSite.SEGS])
	_check(studs >= RingSite.SEGS * 2, "%d stud triangles on the ring's rims (%d wanted)" % [studs, RingSite.SEGS * 2])
	# the marks: arrow on the deck, exit word on the slip lane, per chunk
	for ri in RoadMap.rings().size():
		var r: Dictionary = RoadMap.rings()[ri]
		var rc := floori(float(r.s) / L)
		var word := PlaceNames.exit_word(int(r.number))
		var arrows := 0
		var words := 0
		for k in range(-RoadMap.RAMP_CHUNKS - RoadMap.AUX_CHUNKS, RoadMap.RAMP_CHUNKS + RoadMap.AUX_CHUNKS):
			var c := rc + k
			var marks := RoadRamps.paint_marks(c)
			for m in marks:
				var layer := int((m.cd as Color).r)
				if layer == WordAtlas.layer("#LEFT"):
					arrows += 1
					_arrow_on_deck(r, k, m)
				elif layer == WordAtlas.layer(word):
					words += 1
					var side := 1.0 if float(m.x) > 0.0 else -1.0
					_check((side > 0.0 and k == -5) or (side < 0.0 and k == 4), "ring %s: the exit word for side %d is on chunk k %d" % [r.id, side, k])
					_check(absf(absf(float(m.x)) - (RoadRamps.X_LANE + RoadRamps.HALF)) < 0.01, "ring %s: the exit word is %.1f m out (slip lane at %.1f)" % [r.id, m.x, RoadRamps.X_LANE + RoadRamps.HALF])
					var fwd: Vector3 = -(m.basis as Basis).z.normalized()
					_check(fwd.z * side < -0.99, "ring %s: the exit word on side %d reads toward z %.2f" % [r.id, side, fwd.z])
					# about 50 m before the gore: v = V_GORE + EXIT_WORD_BEFORE_GORE
					var lam := -1.0 if k < 0 else 1.0
					var v := lam * (float(k) * L - float(m.z))
					_check(absf(v - RoadRamps.V_GORE - RoadRamps.EXIT_WORD_BEFORE_GORE) < 0.01, "ring %s: the exit word is %.0f m from the ring's centre" % [r.id, v])
				else:
					_fail("ring %s chunk k %d: a mark with atlas layer %d" % [r.id, k, layer])
		_check(arrows == 2, "ring %s: %d left arrows on its up-ramps (2 wanted)" % [r.id, arrows])
		_check(words == 2, "ring %s: the exit word is painted %d times (2 wanted)" % [r.id, words])

## The arrow lies on the deck: every corner of its quad within 4 cm of it.
func _arrow_on_deck(r: Dictionary, k: int, m: Dictionary) -> void:
	var lam := -1.0 if k < 0 else 1.0
	var side := 1.0 if float(m.x) > 0.0 else -1.0
	_check(lam == -side, "ring %s: the arrow on side %d is on chunk k %d, the down-ramp's" % [r.id, side, k])
	var b: Basis = m.basis
	var worst := 0.0
	for cx in [-0.5, 0.5]:
		for cz in [-0.5, 0.5]:
			var corner := b * Vector3(cx, 0.0, cz) + Vector3(float(m.x), float(m.y), float(m.z))
			var v := lam * (float(k) * L - corner.z)
			var deck := RoadRamps.deck_y(absf(corner.x), v) + RoadPaint.PAINT_Y
			worst = maxf(worst, absf(corner.y - deck))
	_check(worst < 0.04, "ring %s side %d: the arrow floats %.3f m off the deck" % [r.id, side, worst])
	var fwd: Vector3 = -b.z.normalized()
	_check(fwd.z * side < -0.9, "ring %s side %d: the arrow reads toward z %.2f" % [r.id, side, fwd.z])

# ---------- 3. light ----------

func _light() -> void:
	# studs on every row of a ramp
	var leg := _leg(1.0, -1.0, 1)
	var cols: PackedColorArray = leg.cols
	var studs := 0
	for t in range(0, cols.size(), 3):
		if _is(cols[t], RoadRamps.C_STUD):
			studs += 1
	# 11 rows x 2 edges x 2 triangles at least on a full ramp chunk
	_check(studs >= 40, "%d stud triangles on one ramp chunk (40 wanted)" % studs)
	_check(RoadRamps.C_STUD.a > 0.3, "the studs do not glow (alpha %.2f)" % RoadRamps.C_STUD.a)
	# only the nose markers blink
	var na := RingSite.C_NOSE.a
	_check(na >= 0.55 and na <= 0.65, "the nose marker's alpha %.2f is outside the shader's blink band" % na)
	for c in [RoadRamps.C_DECK, RoadRamps.C_WALL, RoadRamps.C_KERB, RoadRamps.C_PAINT, RoadRamps.C_POLE, RoadRamps.C_HEAD, RoadRamps.C_CUSHION, RoadRamps.C_CUSHION_BAND, RoadRamps.C_STUD,
			RingSite.C_UNDER, RingSite.C_BOARD, RingSite.C_CHEVRON, RingSite.C_SPLIT_A, RingSite.C_SPLIT_B, RingSite.C_TREE, RingSite.C_TROLLEY]:
		_check((c as Color).a < 0.55 or (c as Color).a > 0.65, "a colour with alpha %.2f would blink with the noses" % (c as Color).a)
	_check(RoadRamps.SHADER.contains("sin(TIME * 6.2831853 * 1.0)"), "the shader does not pulse at 1 Hz")
	_check(RoadRamps.BLINK_HZ < 2.5, "the blink is in the photosensitive band")

# ---------- 4. the bridge as the landmark (doc section 3) ----------

## A pool under each chevron board and a wash under each bridge; the light
## line on the parapets; the sound zones; the piers' graffiti downtown and in
## the Docks only; the echo under a bridge.
func _pools() -> void:
	var node: Node3D = RingSite.new()
	root.add_child(node)
	RingSite.focus_s = float(RoadMap.rings()[1].s)
	node.call("_place")
	var c: Dictionary = node.counts()
	_check(int(c.pools) == RingSite.LAMP_DEG.size() + 4, "ring x2: %d light pools (%d lamps + 2 boards + 2 washes wanted)" % [c.pools, RingSite.LAMP_DEG.size()])
	_check(int(c.draws) == 3 and int(c.tags) == 0, "ring x2 (residential): %d draw calls, %d tags (3 and 0 wanted)" % [c.draws, c.tags])
	var islands := {}
	for ri in RoadMap.rings().size():
		islands[String(RingSite.look_of(ri).island)] = true
	_check(islands.has("tree") and islands.has("tower") and islands.has("wreck"), "act 1's islands carry %s" % [islands.keys()])
	# the light line: lamps on both parapets of both bridges, lit
	for ri in RoadMap.rings().size():
		var look := RingSite.look_of(ri)
		var made := RingSite.build(look)
		var mesh: ArrayMesh = made.mesh
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var want: Color = RingSite.C_LINE_STEEL if String(look.style) == "steel" else RoadRamps.C_HEAD
		var bridge := String(look.bridge)
		var lift := RingSite.TRUSS_H if bridge == "truss" else 0.0   # on the truss's top chord
		var line := 0
		var line_in := 0
		var truss := 0
		var girder := 0
		var tower := 0
		var wreck := 0
		for t in range(0, verts.size(), 3):
			var mid := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
			var over_span := absf(mid.x) < RingSite.BRIDGE_HALF and Vector2(mid.x, mid.z).length() > RoadRamps.RING_IN - 1.0
			if _is(cols[t], want) and absf(mid.x) < RingSite.BRIDGE_HALF and mid.y > RoadRamps.RAMP_H + RoadRamps.BARRIER_H + lift - 0.4 and mid.y < RoadRamps.RAMP_H + RoadRamps.BARRIER_H + lift + 0.3:
				line += 1
				if Vector2(mid.x, mid.z).length() < RoadRamps.RING_IN:
					line_in += 1
			elif _is(cols[t], RingSite.WALLS[look.style]) and over_span and mid.y > RoadRamps.RAMP_H + RoadRamps.BARRIER_H + 1.0:
				truss += 1
			elif _is(cols[t], RingSite.WALLS[look.style]) and over_span and mid.y < RoadRamps.RAMP_H - RingSite.SLAB - 0.3 and mid.y > RoadRamps.RAMP_H - RingSite.SLAB - RingSite.GIRDER_D - 0.5:
				girder += 1
			elif _is(cols[t], RingSite.C_TANK) and mid.y > 10.0:
				tower += 1
			elif _is(cols[t], RingSite.C_WRECK) and mid.y < 3.0:
				wreck += 1
		_check((truss > 100) == (bridge == "truss"), "ring %s (%s bridge): %d truss triangles" % [RoadMap.rings()[ri].id, bridge, truss])
		_check((girder > 50) == (bridge == "girder"), "ring %s (%s bridge): %d girder triangles" % [RoadMap.rings()[ri].id, bridge, girder])
		var island := String(look.island)
		_check((tower > 20) == (island == "tower") and (wreck > 20) == (island == "wreck"), "ring %s (island %s): %d tower and %d wreck triangles" % [RoadMap.rings()[ri].id, island, tower, wreck])
		_check(RingSite.lamp_light(look) == ("white" if String(look.style) == "steel" else "sodium"), "ring %s: the lamps are %s" % [RoadMap.rings()[ri].id, RingSite.lamp_light(look)])
		# 13 pieces x 2 rims x 2 bridges, 12 triangles a lamp, less the 2 hidden faces
		_check(line >= 40 * 8 and line_in >= 20 * 8, "ring %s: %d light-line triangles (%d on the inner rims)" % [RoadMap.rings()[ri].id, line, line_in])
		_check(want.a >= 1.0, "the light line's lamps do not glow")
		var tags := RingSite.pier_graffiti(look)
		var downtown := RoadMap.district_kind(RoadMap.district_of(floori(float(RoadMap.rings()[ri].s) / L))) == "downtown"
		var docks := String(look.style) == "steel"
		_check(tags.size() == (RingSite.PIER_TAGS if downtown or docks else 0), "ring %s: %d pier tags (%s)" % [RoadMap.rings()[ri].id, tags.size(), look])
		for it in tags:
			var o: Vector3 = (it.xf as Transform3D).origin
			var on_pier := absf(absf(o.x) - 0.36) < 0.01 or absf(absf(o.x) - (RingSite.PIER_X - 0.51)) < 0.01
			_check(on_pier and o.y > 0.5 and o.y < RoadRamps.RAMP_H - RingSite.SLAB, "ring %s: a tag at %s is not on a pier's face" % [RoadMap.rings()[ri].id, o])
	# the sound zones ride with the node: under each bridge, on each deck
	var under := 0
	var deck := 0
	var mid_r := (RoadRamps.RING_IN + RoadRamps.RING_OUT) * 0.5
	for ch in node.get_children():
		if ch is SoundZone:
			var z := ch as SoundZone
			if z.kind == SoundZone.Kind.UNDER_BRIDGE:
				under += 1
				_check(SoundZone.find(SoundZone.Kind.UNDER_BRIDGE, node.to_global(Vector3(10.0, 1.0, signf(z.position.z) * mid_r))) != null, "under the bridge at z %.0f is not in an under-bridge zone" % z.position.z)
			elif z.kind == SoundZone.Kind.BRIDGE_DECK:
				deck += 1
				_check(SoundZone.find(SoundZone.Kind.BRIDGE_DECK, node.to_global(Vector3(-10.0, RoadRamps.RAMP_H + 0.5, signf(z.position.z) * mid_r))) != null, "on the bridge at z %.0f is not in a deck zone" % z.position.z)
	_check(under == 2 and deck == 2, "%d under-bridge and %d deck sound zones (2 and 2 wanted)" % [under, deck])
	_check(SoundZone.find(SoundZone.Kind.UNDER_BRIDGE, node.to_global(Vector3(0.0, 1.0, 0.0))) == null and SoundZone.find(SoundZone.Kind.UNDER_BRIDGE, node.to_global(Vector3(0.0, 1.0, -60.0))) == null, "the road between and beyond the bridges is in an under-bridge zone")
	_check(SoundZone.reception_at(node.to_global(Vector3(0.0, 1.0, mid_r))) < 0.5, "the radio does not break up under the bridge")
	# the echo: the car's own noise gets a short room under the slab
	var listener := Node3D.new()
	root.add_child(listener)
	var ta: Node = TunnelAudio.new()
	ta.listener = listener
	root.add_child(ta)
	listener.global_position = node.to_global(Vector3(5.0, 1.0, -mid_r))
	_check(absf(float(ta.bridge_amount()) - TunnelAudio.BRIDGE_WET) < 1e-6, "under the bridge the echo is %.2f (%.2f wanted)" % [ta.bridge_amount(), TunnelAudio.BRIDGE_WET])
	listener.global_position = node.to_global(Vector3(5.0, 1.0, 0.0))
	_check(float(ta.bridge_amount()) == 0.0, "between the bridges the echo is %.2f" % ta.bridge_amount())
	_check(TunnelAudio.BRIDGE_WET > 0.0 and TunnelAudio.BRIDGE_WET < 1.0, "the bridge echo should be a share of the tunnel's")
	ta.free()
	listener.free()
	node.free()
	_finish()
