extends Node3D

# The raised ring (ring sites R2, 2026-10-11).
#
# At every ring site on the map (RoadMap.rings) a roundabout stands over the
# highway: 70 m across, RAMP_H up, one lane 7 m wide, driven anticlockwise.
# Two bridges carry it over the carriageways. Each side's two ramps
# (RoadRamps, built with the chunks) run along the ring's outside edge and
# open into it, so from the ring a car can go down onto either carriageway
# either way: round and back down your own side is a U-turn.
#
# One node, moved to the site nearest the player, like Junction: sites are
# 800 m apart and the road is drawn 300 m ahead, so two are never in view.
# It is laid out flat with RoadRamps' tools; the chunks under it are pinned
# straight (RoadMap.PIN_STRAIGHT) and it takes the road's own slight tilt
# there, so it meets the ramps exactly.
#
# What differs from site to site is built once per look and kept:
# - the bridge and wall colour follows the district (concrete; steel in the
#   docks; rust in industrial areas), and so does the bridge itself (ramps
#   doc 2.6): a plain slab, a steel truss over each span in the Docks with
#   the light line on its top chord and white "harbour" lamps, a deep rusty
#   girder with drip stains in industrial areas;
# - a "stop" or "lot" site has a spur: a stub of an arm off the ring on the
#   stop's side, ending at a barrier until the stops are built;
# - what stands on the island (RoadMap.rings `island`): a dead tree and a
#   shopping trolley, a water tower, a toppled crane wreck, or nothing.
#
# The lane leans in 4 % (RoadRamps.BANK). Each bridge's outside face carries
# the exit's number, lit, over the carriageway that drives at it, and beside
# it a plate naming the next exit along and how far it is ("EXIT 3 / 600 m"):
# the bridge is what you count, and it replaces the old 1 km gantry (#645).
#
# Cost: 3 draw calls (one mesh, vertex colours, RoadRamps' material; one
# MultiMesh of fake light pools; one MultiMesh of bridge lettering on the
# area signs' material and atlas), a trimesh for the deck and boxes for the
# barriers, walls and piers. No real lights, no new material.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const R := preload("res://scripts/world/road_ramps.gd")   # short, for the layout code
const PlaceNames := preload("res://scripts/world/place_names.gd")
const RoadSigns := preload("res://scripts/world/road_signs.gd")
const Graffiti := preload("res://scripts/world/graffiti.gd")

const L := 50.0
const SEGS := 64                 # rim pieces, RoadRamps.RING_SEG_DEG each
const HALF_SEGS := 32
const SLAB := 0.8                # the bridge deck's depth
## Nearer the centre line than this the ring is a bridge: nothing under it
## but piers.
const BRIDGE_HALF := 20.5
const PIER_X := 19.8
const SPUR_HALF := 3.43          # half its width: one rim piece each side
const SPUR_END := 50.0           # metres out, where its barrier stands
const LAMP_DEG: Array[float] = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]
const LAMP_H := 6.0
const POOL := 11.0
const BOARD_DEG := 38.0          # the chevron board, past each entry
const BOARD_LEN := 6.0
const BOARD_H := 1.1
## The bridge lettering: the number's centre this far out from the centre
## line, over the carriageway that drives at that face; the next-exit plate
## further out, to the reader's right.
const NUMBER_X := 5.5
const NUMBER_H := 1.2
const NEXT_X := 11.0
const NEXT_LINE_H := 0.5
const SIGN_PROUD := 0.06         # out from the parapet's outside face
const SIGN_CAP := 12
## The bridge as the landmark (ramps doc section 3). The light line: a small
## lamp on top of each parapet at every rim piece over the road, both rims of
## both bridges; sodium amber, steel-white at a Docks (steel) ring.
const LINE_LAMP := Vector3(0.22, 0.12, 0.22)
const C_LINE_STEEL := Color(0.9, 0.92, 0.95, 1.0)
## The wash of light on the road under each slab: a pool this big.
const WASH := Vector2(2.0 * BRIDGE_HALF + 4.0, 20.0)
## Sound zones under and on each bridge (SoundZone): the radio breaks up
## and the car's own noise echoes under the slab (TunnelAudio), and the
## tyres hum on the deck (CarAudio).
const UNDER_ZONE := Vector3(2.0 * BRIDGE_HALF, 5.5, 14.0)
const DECK_ZONE := Vector3(2.0 * BRIDGE_HALF, 3.0, 9.0)
## Graffiti on the piers' faces, downtown and in the Docks (doc section 3).
const PIER_TAGS := 4
## The steel truss over each span (Docks): posts every other rim piece up to
## TRUSS_H above the parapet, a top chord, a diagonal in every bay.
const TRUSS_H := 3.6
const TRUSS_T := 0.16
## The rusty girder under each span (industrial): this deep below the slab's
## edge, with dark drip stains down its face.
const GIRDER_D := 1.3
const GIRDER_T := 0.25
const C_STAIN := Color(0.16, 0.1, 0.06, 0.0)
## The water tower on x4's island and the crane wreck on x8's.
const C_TANK := Color(0.33, 0.3, 0.27, 0.0)
const C_WRECK := Color(0.3, 0.2, 0.12, 0.0)
const C_WRECK_CAB := Color(0.5, 0.44, 0.12, 0.0)

const C_UNDER := Color(0.07, 0.07, 0.075, 0.0)
const C_BOARD := Color(0.03, 0.03, 0.03, 0.0)
const C_CHEVRON := Color(0.88, 0.88, 0.84, 0.05)
const C_SPLIT_A := Color(1.0, 0.54, 0.12, 0.035)
const C_SPLIT_B := Color(0.85, 0.85, 0.8, 0.035)
const C_NOSE := Color(1.0, 0.54, 0.12, 0.6)
## The lane's painted edge (doc 2.4): a dash on every other rim piece, this
## far in from each kerb.
const DASH_IN := 0.45
const DASH_W := 0.12
## The light pool under each chevron board (doc 2.5), on the lane's inside.
const BOARD_POOL := Vector2(6.0, 4.0)
const C_TREE := Color(0.1, 0.085, 0.07, 0.0)
const C_TROLLEY := Color(0.5, 0.52, 0.54, 0.0)
const WALLS := {
	"concrete": Color(0.3, 0.295, 0.28, 0.0),
	"steel": Color(0.19, 0.22, 0.26, 0.0),
	"rust": Color(0.29, 0.18, 0.11, 0.0),
}

## Off for tests of the bare ramps. Read when the node is placed.
static var enabled := true
## Where the player is, metres along the road (RoadFrame.s_at; game.gd, every
## frame). Not road-space z: that jumps when the floating origin moves, and
## for the tick before the next frame the ring would stand at another site.
static var focus_s := 0.0
static var _looks := {}   # look key -> {mesh, faces, boxes, pools}

var site := -1            # index into RoadMap.rings() of the site it stands at
var _site_s := -1.0
var _origin := -999999
var _mesh: MeshInstance3D
var _pools: MultiMeshInstance3D
var _deck: CollisionShape3D
var _walls: StaticBody3D
var _signs: MultiMeshInstance3D
var _zones: Array[SoundZone] = []

# ---------- where ----------

## Which rim pieces of the outside edge are open, counted anticlockwise from
## the +x point: three pieces either side of each ramp point where a ramp's
## lane comes in or goes out, and two at the spur.
static func rim_open(i: int, spur_side: int) -> bool:
	for base in [0, HALF_SEGS]:
		var d := posmod(i - base, SEGS)
		if (d >= 3 and d <= 5) or (d >= SEGS - 6 and d <= SEGS - 4):
			return true
		if (d == 0 or d == SEGS - 1) and spur_side == (1 if base == 0 else -1):
			return true
	return false

## The look of a site: its wall colour by district and what it carries.
static func look_of(ring: int) -> Dictionary:
	var r: Dictionary = RoadMap.rings()[ring]
	var info := RoadMap.district_info(RoadMap.district_of(floori(float(r.s) / L)))
	var style := "concrete"
	if String(info.kind) == "industrial":
		style = "rust"
	elif String(info.zone) == "The Docks":
		style = "steel"
	var island := String(r.get("island", "tree" if String(r.kind) == "landmark" else ""))
	return {"style": style, "spur": RoadMap.ring_spur_side(ring), "landmark": island == "tree", "island": island,
		"bridge": {"steel": "truss", "rust": "girder"}.get(style, "slab"),
		"graffiti": style == "steel" or String(info.kind) == "downtown"}

func _ready() -> void:
	name = "RingSite"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mesh = MeshInstance3D.new()
	_mesh.name = "Ring"
	_mesh.material_override = RoadRamps.material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = RoadChunkBuilder._get_pool_mesh()
	mm.instance_count = LAMP_DEG.size() + 4   # + one under each chevron board, a wash under each bridge
	mm.visible_instance_count = 0
	_pools = MultiMeshInstance3D.new()
	_pools.name = "RingPools"
	_pools.multimesh = mm
	_pools.material_override = RoadChunkBuilder._get_pool_mat()
	_pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pools)
	var deck := StaticBody3D.new()
	deck.name = "RingDeck"
	deck.add_to_group("Road")
	deck.set_meta(SurfaceMap.DECK_META, true)
	_deck = CollisionShape3D.new()
	_deck.name = "Shape"
	var tri := ConcavePolygonShape3D.new()
	tri.backface_collision = true
	_deck.shape = tri
	deck.add_child(_deck)
	add_child(deck)
	_walls = StaticBody3D.new()
	_walls.name = "RingWalls"
	CarSpec.make_wall(_walls)
	add_child(_walls)
	_signs = RoadSigns.new_multimesh(SIGN_CAP)
	_signs.name = "BridgeSigns"
	add_child(_signs)
	Graffiti.create(self, PIER_TAGS)
	var mid := (R.RING_IN + R.RING_OUT) * 0.5
	for vz in [-1.0, 1.0]:
		var under := SoundZone.make(SoundZone.Kind.UNDER_BRIDGE, UNDER_ZONE)
		under.name = "UnderBridge%s" % ("A" if vz < 0.0 else "B")
		under.position = Vector3(0.0, UNDER_ZONE.y * 0.5, vz * mid)
		add_child(under)
		_zones.append(under)
		var deck_zone := SoundZone.make(SoundZone.Kind.BRIDGE_DECK, DECK_ZONE)
		deck_zone.name = "BridgeDeck%s" % ("A" if vz < 0.0 else "B")
		deck_zone.position = Vector3(0.0, R.RAMP_H + DECK_ZONE.y * 0.5 - 0.5, vz * mid)
		add_child(deck_zone)
		_zones.append(deck_zone)
	_place()

func _physics_process(_delta: float) -> void:
	_place()

## Stands at the site nearest the player; follows the floating origin.
func _place() -> void:
	var on := enabled and RoadRamps.enabled and RoadRamps.ring and RoadMap.is_loop() and not RoadMap.rings().is_empty()
	if not on:
		if visible:
			visible = false
			_deck.disabled = true
			for c in _walls.get_children():
				(c as CollisionShape3D).disabled = true
			for z in _zones:
				z.size = Vector3.ZERO
			site = -1
		return
	var near := RoadMap.ring_near(focus_s)
	if int(near.index) == site and float(near.s) == _site_s and RoadFrame.origin_index == _origin:
		return
	_origin = RoadFrame.origin_index
	_site_s = float(near.s)
	var cz := float(RoadFrame.origin_index) * L - _site_s
	global_transform = Transform3D(RoadFrame.basis_at(cz), RoadFrame.roll(Vector3(0.0, 0.0, cz)))
	reset_physics_interpolation()
	if int(near.index) != site or not visible:
		site = int(near.index)
		_dress(look_of(site))
		_letter(site)
		for z in _zones:
			z.size = UNDER_ZONE if z.kind == SoundZone.Kind.UNDER_BRIDGE else DECK_ZONE
	visible = true
	force_update_transform()
	for c in get_children():
		if c is CollisionObject3D:
			(c as Node3D).force_update_transform()

func _dress(look: Dictionary) -> void:
	var key := "%s|%d|%s" % [look.style, look.spur, look.get("island", "")]
	if not _looks.has(key):
		_looks[key] = build(look)
	var made: Dictionary = _looks[key]
	_mesh.mesh = made.mesh
	_pools.material_override = RoadChunkBuilder._get_pool_mat(lamp_light(look))
	(_deck.shape as ConcavePolygonShape3D).set_faces(made.faces)
	_deck.disabled = false
	var boxes: Array = made.boxes
	while _walls.get_child_count() < boxes.size():
		var c := CollisionShape3D.new()
		c.shape = BoxShape3D.new()
		_walls.add_child(c)
	for i in _walls.get_child_count():
		var c := _walls.get_child(i) as CollisionShape3D
		if i < boxes.size():
			(c.shape as BoxShape3D).size = boxes[i][1]
			c.transform = boxes[i][0]
			c.disabled = false
		else:
			c.disabled = true
	var pools: Array = made.pools
	var mm := _pools.multimesh
	var n := mini(pools.size(), mm.instance_count)
	for i in n:
		mm.set_instance_transform(i, pools[i])
	mm.visible_instance_count = n
	Graffiti.place(self, pier_graffiti(look))

## The bridge lettering for this site (it differs per site, so it is not
## part of the cached look).
func _letter(ring: int) -> void:
	var items := bridge_signs(ring)
	var mm := _signs.multimesh
	var n := mini(items.size(), mm.instance_count)
	for i in n:
		mm.set_instance_transform(i, items[i].xf)
		mm.set_instance_custom_data(i, items[i].cd)
	mm.visible_instance_count = n
	_signs.visible = n > 0

## The next exit along from ring `ring` for traffic on carriageway `side`
## (+1 the way the chunks count): {number, metres}, metres from this ring's
## bridge face to that exit's gore, to the nearest 100 m.
static func next_exit(ring: int, side: int) -> Dictionary:
	var rings := RoadMap.rings()
	var n := rings.size()
	var here := float(rings[ring].s)
	var there: Dictionary = rings[posmod(ring + side, n)]
	var gap := fposmod((float(there.s) - here) * float(side), RoadMap.length())
	if gap < 1.0:
		gap += RoadMap.length()   # one ring on the whole loop
	var face := R.RING_OUT + R.BARRIER_W
	return {"number": int(there.number), "metres": roundi((gap - RoadMap.RING_GORE + face) / 100.0) * 100}

## The lettering on ring `ring`'s two bridges, in the ring's flat space:
## [{xf, cd}] (RoadSigns instances). On each bridge's outside face, over the
## carriageway that drives at it: the exit's number, lit amber, and to the
## reader's right a dark plate with the next exit's number over how far.
static func bridge_signs(ring: int) -> Array:
	var r: Dictionary = RoadMap.rings()[ring]
	var face := R.RING_OUT + R.BARRIER_W
	var mid_y: float = R.RAMP_H + (R.BARRIER_H - SLAB) * 0.5
	var out: Array = []
	for side in [1, -1]:
		var sd := float(side)
		# side +1 drives toward -z (up v) and meets the bridge at -v first
		var number := _on_face(NUMBER_X * sd, sd, face, mid_y)
		out.append(RoadSigns.text_plate(PlaceNames.exit_word(int(r.number)), number.c, number.n, NUMBER_H, RoadSigns.AMBER, RoadSigns.OVERLAY))
		var nx := next_exit(ring, side)
		var a := PlaceNames.exit_word(int(nx.number))
		var b := PlaceNames.metres_word(int(nx.metres))
		var inner := maxf(RoadSigns.plate_len(a, NEXT_LINE_H), RoadSigns.plate_len(b, NEXT_LINE_H))
		var gap := 0.08
		var panel_h := 2.0 * NEXT_LINE_H + 3.0 * gap
		var panel_len := inner + 2.0 * 0.2
		var plate := _on_face(NEXT_X * sd, sd, face, mid_y)
		var nn: Vector3 = plate.n
		out.append(RoadSigns._item(plate.c, nn, RoadSigns.PANEL_DEPTH, panel_h, panel_len, 0, 0, 0, RoadSigns.PANEL))
		var front: Vector3 = nn * (RoadSigns.PANEL_DEPTH / 2.0 + RoadSigns.PLATE_DEPTH / 2.0 + 0.004)
		var c: Vector3 = plate.c
		out.append(RoadSigns.text_plate(a, c + front + Vector3.UP * (NEXT_LINE_H + gap) * 0.5, nn, NEXT_LINE_H, RoadSigns.AMBER))
		out.append(RoadSigns.text_plate(b, c + front - Vector3.UP * (NEXT_LINE_H + gap) * 0.5, nn, NEXT_LINE_H, RoadSigns.OFF_WHITE))
	return out

## A point on the outside face of the bridge that carriageway `sd` meets
## first, x across: {c centre (proud of the face), n the face's outward normal}.
static func _on_face(x: float, sd: float, face: float, y: float) -> Dictionary:
	var z := sd * sqrt(face * face - x * x)
	var n := Vector3(x, 0.0, z) / face
	return {"c": n * (face + SIGN_PROUD) + Vector3(0.0, y, 0.0), "n": n}

## Tags on the piers' faces toward the road, downtown and in the Docks: the
## same few at every such ring (one look, cached like the rest). Items for
## Graffiti.place, in the ring's flat space.
static func pier_graffiti(look: Dictionary) -> Array:
	if not bool(look.get("graffiti", false)):
		return []
	var seed := 71 if String(look.style) == "steel" else 37
	var planned := Graffiti.plan(seed, 1.6, 3.0, PIER_TAGS, ["tag", "piece"])
	var mid := (R.RING_IN + R.RING_OUT) * 0.5
	var out: Array = []
	for i in planned.size():
		var it: Dictionary = planned[i]
		# the four piers' faces that look along the road: the centre pier's two
		# faces, then the edge piers' faces toward the road, one tag each
		var vz := -1.0 if i % 2 == 0 else 1.0
		var at: Vector3
		var normal: Vector3
		if i < 2:
			at = Vector3(0.0, 0.0, vz * mid)
			normal = Vector3(1.0 if i == 0 else -1.0, 0.0, 0.0)
			at.x += normal.x * 0.36
		else:
			var sx := 1.0 if i == 2 else -1.0
			at = Vector3(sx * PIER_X, 0.0, vz * sqrt(mid * mid - PIER_X * PIER_X))
			normal = Vector3(-sx, 0.0, 0.0)
			at.x += normal.x * 0.51
		var xf: Transform3D = it.xf
		var y: float = xf.origin.y
		var basis := Basis.looking_at(-normal, Vector3.UP) * xf.basis
		out.append({"xf": Transform3D(basis, at + Vector3(0.0, y, 0.0)), "cell": it.cell, "fade": it.fade, "tint": it.tint})
	return out

## What the node holds now: {verts, faces, boxes, pools, draws}. Tests.
func counts() -> Dictionary:
	var verts := 0
	var am := _mesh.mesh as ArrayMesh
	if am != null and am.get_surface_count() > 0:
		verts = (am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var boxes := 0
	for c in _walls.get_children():
		if not (c as CollisionShape3D).disabled:
			boxes += 1
	@warning_ignore("integer_division")
	var faces := (_deck.shape as ConcavePolygonShape3D).get_faces().size() / 3
	var tags := (get_node(^"Graffiti") as MultiMeshInstance3D).multimesh.visible_instance_count
	return {"verts": verts, "faces": faces, "boxes": boxes, "pools": _pools.multimesh.visible_instance_count,
		"signs": _signs.multimesh.visible_instance_count, "tags": tags,
		"draws": (1 if verts > 0 else 0) + (1 if _pools.multimesh.visible_instance_count > 0 else 0) + (1 if _signs.multimesh.visible_instance_count > 0 else 0) + (1 if tags > 0 else 0)}

# ---------- geometry ----------

## The lamps' light at a look: the Docks' steel rings get the cooler white
## "harbour" lamps the cranes use; everywhere else sodium.
static func lamp_light(look: Dictionary) -> String:
	return "white" if String(look.style) == "steel" else "sodium"

## Lays one look of the ring out: {mesh, faces, boxes, pools}.
static func build(look: Dictionary) -> Dictionary:
	R.begin_flat()
	R.wall_colour = WALLS[look.style]
	var y: float = R.RAMP_H
	# the lane leans in: its inside edge is lower (RoadRamps.BANK)
	var y_in: float = y - R.ring_drop(R.RING_IN)
	var spur: int = look.spur
	var step := TAU / float(SEGS)
	# the lane and the slab's underside
	for i in SEGS:
		var a0 := step * float(i)
		var a1 := step * float(i + 1)
		var i0 := R._p(R.RING_IN * cos(a0), y_in, R.RING_IN * sin(a0))
		var o0 := R._p(R.RING_OUT * cos(a0), y, R.RING_OUT * sin(a0))
		var i1 := R._p(R.RING_IN * cos(a1), y_in, R.RING_IN * sin(a1))
		var o1 := R._p(R.RING_OUT * cos(a1), y, R.RING_OUT * sin(a1))
		R._deck_quad(i0, o0, i1, o1)
		if i % 2 == 0:
			# the lane's dashed edge lines, on the leaning deck
			for r in [R.RING_IN + DASH_IN, R.RING_OUT - DASH_IN]:
				_dash(r, a0, a1, y)
		var down := Vector3(0.0, -SLAB, 0.0)
		R._quad(i0 + down, o0 + down, i1 + down, o1 + down, C_UNDER, Vector3.DOWN)
	# the outside edge, in runs between the mouths; then the inside edge, whole
	var first_open := 0
	while not rim_open(first_open, spur):
		first_open += 1
	var run_from := -1
	for j in range(first_open, first_open + SEGS + 1):
		var open := rim_open(j % SEGS, spur)
		if not open and run_from < 0:
			run_from = j
		elif open and run_from >= 0:
			_rim(R.RING_OUT, 1.0, run_from, j, y)
			run_from = -1
	_rim(R.RING_IN, -1.0, 0, SEGS, y_in)
	# piers: on the centre barrier's line and at each road edge, under each bridge
	for vz in [-1.0, 1.0]:
		var mid := (R.RING_IN + R.RING_OUT) * 0.5
		_pier(0.0, vz * mid, 0.7, 2.0, y)
		for sx in [-1.0, 1.0]:
			_pier(sx * PIER_X, vz * sqrt(mid * mid - PIER_X * PIER_X), 1.0, 1.6, y)
	# the light line: a small lamp on each parapet at every rim piece over the
	# road, both rims, both bridges; a wash of light on the road under each slab
	var line_col: Color = C_LINE_STEEL if String(look.style) == "steel" else R.C_HEAD
	var bridge := String(look.get("bridge", "slab"))
	var head_col: Color = C_LINE_STEEL if String(look.style) == "steel" else R.C_HEAD
	for i in SEGS:
		var a := step * (float(i) + 0.5)
		if absf(R.RING_OUT * cos(a)) >= BRIDGE_HALF:
			continue
		for r in [R.RING_OUT + R.BARRIER_W * 0.5, R.RING_IN - R.BARRIER_W * 0.5]:
			var top: float = y + R.BARRIER_H + LINE_LAMP.y * 0.5
			if r < R.RING_IN:
				top -= R.ring_drop(R.RING_IN)
			if bridge == "truss":
				top += TRUSS_H + TRUSS_T * 0.5   # on the truss's top chord
			R._box(Vector3(r * cos(a), top, r * sin(a)), LINE_LAMP, line_col)
	if bridge == "truss":
		_truss(y)
	elif bridge == "girder":
		_girder(y)
	for vz in [-1.0, 1.0]:
		var wmid := (R.RING_IN + R.RING_OUT) * 0.5
		R._pools.append(Transform3D(Basis.from_scale(Vector3(WASH.x, 1.0, WASH.y)), R._p(0.0, 0.05, vz * wmid)))
	# tall sodium lamps on the outside barrier, a pool of light under each
	for deg in LAMP_DEG:
		if (deg == 0.0 and spur > 0) or (deg == 180.0 and spur < 0):
			continue
		var a := deg_to_rad(deg)
		var r: float = R.RING_OUT + R.BARRIER_W * 0.5
		R._box(Vector3(r * cos(a), y + LAMP_H * 0.5, r * sin(a)), Vector3(0.16, LAMP_H, 0.16), R.C_POLE)
		R._box(Vector3(r * cos(a), y + LAMP_H + 0.06, r * sin(a)), Vector3(0.8, 0.14, 0.8), head_col)
		var mid := (R.RING_IN + R.RING_OUT) * 0.5
		# the pool lies on the leaning deck
		var tip := Basis(Quaternion(Vector3.UP, R.ring_normal(a)))
		R._pools.append(Transform3D(tip * Basis.from_scale(Vector3(POOL, 1.0, POOL)), R._p(mid * cos(a), y - R.ring_drop(mid) + 0.05, mid * sin(a))))
	# chevron boards on the inside, past each entry, each lit from a pool on
	# the lane below it; a lit marker on each nose
	for base in [0.0, 180.0]:
		var ba := deg_to_rad(base + BOARD_DEG)
		_board(ba, y_in)
		var br: float = R.RING_IN + BOARD_POOL.y * 0.5 + 0.3
		var btip := Basis(Quaternion(Vector3.UP, R.ring_normal(ba)))
		R._pools.append(Transform3D(btip * Basis(Vector3.UP, -ba) * Basis.from_scale(Vector3(BOARD_POOL.x, 1.0, BOARD_POOL.y)),
			R._p(br * cos(ba), y - R.ring_drop(br) + 0.05, br * sin(ba))))
		for d in [-6.0, 6.0]:
			var a := deg_to_rad(base + d * R.RING_SEG_DEG)
			var r: float = R.RING_OUT + R.BARRIER_W * 0.5
			R._box(Vector3(r * cos(a), y + R.BARRIER_H + 0.25, r * sin(a)), Vector3(0.36, 0.5, 0.36), C_NOSE)
	if spur != 0:
		_spur(float(spur), y)
	match String(look.get("island", "")):
		"tree":
			_landmark()
		"tower":
			_water_tower()
		"wreck":
			_crane_wreck()
	var made := R.end_flat()
	R.wall_colour = R.C_WALL
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made.arrays)
	return {"mesh": mesh, "faces": made.faces, "boxes": made.boxes, "pools": made.pools}

## One painted dash of the lane's edge line at radius r between angles a0
## and a1, on the leaning deck.
static func _dash(r: float, a0: float, a1: float, y: float) -> void:
	var hi: float = y - R.ring_drop(r - DASH_W * 0.5) + R.PAINT_LIFT
	var ho: float = y - R.ring_drop(r + DASH_W * 0.5) + R.PAINT_LIFT
	var ri := r - DASH_W * 0.5
	var ro := r + DASH_W * 0.5
	# a short gap at each end so the dashes read as dashes
	var g := (a1 - a0) * 0.12
	a0 += g
	a1 -= g
	R._quad(R._p(ri * cos(a0), hi, ri * sin(a0)), R._p(ro * cos(a0), ho, ro * sin(a0)),
		R._p(ri * cos(a1), hi, ri * sin(a1)), R._p(ro * cos(a1), ho, ro * sin(a1)), R.C_PAINT, Vector3.UP)

## Kerb, barrier and wall along the rim at radius r, pieces from..to (to may
## run past SEGS). side +1 = the outside edge, -1 the inside one.
static func _rim(r: float, side: float, from: int, to: int, y: float) -> void:
	var step := TAU / float(SEGS)
	var pts: Array[Vector3] = []
	var out: Array[Vector2] = []
	var hs := PackedFloat32Array()
	var bottoms := PackedFloat32Array()
	var faces: Array = []
	for i in range(from, to + 1):
		var a := step * float(i)
		pts.append(Vector3(r * cos(a), r * sin(a), y))
		out.append(Vector2(cos(a), sin(a)) * side)
		hs.append(R.BARRIER_H)
		bottoms.append(y - SLAB if absf(r * cos(a)) < BRIDGE_HALF else -R.SKIRT)
		# the splitter between a way in and a way out: amber and white, to catch the lamps
		var d := posmod(i, HALF_SEGS)
		var splitter := side > 0.0 and (d < 3 or d >= HALF_SEGS - 3)
		faces.append((C_SPLIT_A if i % 2 == 0 else C_SPLIT_B) if splitter else R.wall_colour)
	R._edge(pts, out, hs, bottoms, faces)

static func _pier(x: float, v: float, across: float, along: float, y: float) -> void:
	var h := y - SLAB
	R._box(Vector3(x, h * 0.5, v), Vector3(across, h, along), R.wall_colour)
	R._wall_box(R._p(x, 0.0, v - along * 0.5), R._p(x, 0.0, v + along * 0.5), 0.0, h, across)

## A black board with white chevrons pointing the way round (anticlockwise),
## on the inside of the lane at angle a, facing the lane.
static func _board(a: float, y: float) -> void:
	var r: float = R.RING_IN - R.BARRIER_W - 0.25
	var n := Vector2(cos(a), sin(a))          # toward the lane
	var t := Vector2(-sin(a), cos(a))         # the way round
	var cy: float = y + R.BARRIER_H + 0.2 + BOARD_H * 0.5
	var want := Vector3(n.x, 0.0, -n.y)
	for face in [1.0, -1.0]:
		var bc: Vector2 = n * (r + 0.05 * face)
		R._quad(R._p(bc.x - t.x * BOARD_LEN * 0.5, cy - BOARD_H * 0.5, bc.y - t.y * BOARD_LEN * 0.5),
			R._p(bc.x + t.x * BOARD_LEN * 0.5, cy - BOARD_H * 0.5, bc.y + t.y * BOARD_LEN * 0.5),
			R._p(bc.x - t.x * BOARD_LEN * 0.5, cy + BOARD_H * 0.5, bc.y - t.y * BOARD_LEN * 0.5),
			R._p(bc.x + t.x * BOARD_LEN * 0.5, cy + BOARD_H * 0.5, bc.y + t.y * BOARD_LEN * 0.5), C_BOARD, want * face)
	# two posts down to the barrier
	for e in [-1.0, 1.0]:
		var pc: Vector2 = n * r + t * (BOARD_LEN * 0.4 * e)
		R._box(Vector3(pc.x, y + (R.BARRIER_H + 0.2) * 0.5 + 0.3, pc.y), Vector3(0.12, R.BARRIER_H + 0.2, 0.12), R.C_POLE)
	var c := n * (r + 0.09)
	var w := 0.32
	for k in 5:
		var s0 := (float(k) - 2.0) * 1.1 - 0.25
		for half in [1.0, -1.0]:
			# one stroke of a ">": from the tip at mid height back to the top (or bottom) edge
			var tip0 := c + t * (s0 + 0.45)
			var tip1 := c + t * (s0 + 0.45 + w)
			var back0 := c + t * s0
			var back1 := c + t * (s0 + w)
			R._quad(R._p(tip0.x, cy, tip0.y), R._p(tip1.x, cy, tip1.y),
				R._p(back0.x, cy + half * (BOARD_H * 0.5 - 0.08), back0.y), R._p(back1.x, cy + half * (BOARD_H * 0.5 - 0.08), back1.y), C_CHEVRON, want)

## The spur: a stub of an arm off the ring on `side`, to a barrier.
static func _spur(side: float, y: float) -> void:
	var x0: float = R.RING_OUT - 0.6
	var x1 := SPUR_END
	R._deck_quad(R._p(side * x0, y, -SPUR_HALF), R._p(side * x0, y, SPUR_HALF), R._p(side * x1, y, -SPUR_HALF), R._p(side * x1, y, SPUR_HALF))
	var full := PackedFloat32Array([R.BARRIER_H, R.BARRIER_H])
	for e in [-1.0, 1.0]:
		var pts: Array[Vector3] = [Vector3(side * (R.RING_OUT + 0.1), e * SPUR_HALF, y), Vector3(side * x1, e * SPUR_HALF, y)]
		var out: Array[Vector2] = [Vector2(0.0, e), Vector2(0.0, e)]
		R._edge(pts, out, full)
	var end_pts: Array[Vector3] = [Vector3(side * x1, -SPUR_HALF, y), Vector3(side * x1, SPUR_HALF, y)]
	var end_out: Array[Vector2] = [Vector2(side, 0.0), Vector2(side, 0.0)]
	R._edge(end_pts, end_out, full, PackedFloat32Array(), [C_SPLIT_A])
	R._box(Vector3(side * (x1 - 0.2), y + R.BARRIER_H + 0.2, 0.0), Vector3(0.3, 0.4, 0.3), C_NOSE)

## A thin bar between two points of the flat description (x, y, v), `t`
## thick: four long faces (for trusses, legs and wrecks, where a box square
## to the axes will not do).
static func _bar(p0: Vector3, p1: Vector3, t: float, col: Color) -> void:
	var a := R._p(p0.x, p0.y, p0.z)
	var b := R._p(p1.x, p1.y, p1.z)
	var along := (b - a)
	if along.length() < 0.01:
		return
	var dir := along.normalized()
	var ref := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	var u := dir.cross(ref).normalized() * t * 0.5
	var w := dir.cross(u).normalized() * t * 0.5
	for pair in [[u, w], [w, -u], [-u, -w], [-w, u]]:
		var e0: Vector3 = pair[0]
		var e1: Vector3 = pair[1]
		R._quad(a + e0, b + e0, a + e1, b + e1, col, (e0 + e1).normalized())

## The rim pieces over one span of the bridge: those whose outer-rim point
## is within BRIDGE_HALF of the centre line, for vz = -1 and +1.
static func _span_pieces(vz: float) -> Array:
	var step := TAU / float(SEGS)
	var out: Array = []
	for i in SEGS:
		var a := step * float(i)
		if absf(R.RING_OUT * cos(a)) < BRIDGE_HALF and signf(sin(a)) == vz:
			out.append(i)
	return out

## A steel truss over each span, on both rims: posts every other piece, a top
## chord, and a diagonal in every bay, the light line on the chord.
static func _truss(y: float) -> void:
	var step := TAU / float(SEGS)
	for vz in [-1.0, 1.0]:
		var pieces := _span_pieces(vz)
		for r in [R.RING_OUT + R.BARRIER_W * 0.5, R.RING_IN - R.BARRIER_W * 0.5]:
			var base: float = y + R.BARRIER_H - (R.ring_drop(R.RING_IN) if r < R.RING_IN else 0.0)
			var top := base + TRUSS_H
			for j in pieces.size():
				var i: int = pieces[j]
				var a0 := step * float(i)
				var a1 := step * float(i + 1)
				var p0 := Vector2(r * cos(a0), r * sin(a0))
				var p1 := Vector2(r * cos(a1), r * sin(a1))
				# the top chord over this piece, and a post at every other joint
				_bar(Vector3(p0.x, top, p0.y), Vector3(p1.x, top, p1.y), TRUSS_T, R.wall_colour)
				if j % 2 == 0:
					_bar(Vector3(p0.x, base, p0.y), Vector3(p0.x, top, p0.y), TRUSS_T, R.wall_colour)
					# a diagonal across the two-piece bay
					if j + 2 <= pieces.size():
						var a2 := step * float(i + 2)
						var p2 := Vector2(r * cos(a2), r * sin(a2))
						_bar(Vector3(p0.x, base, p0.y), Vector3(p2.x, top, p2.y), TRUSS_T * 0.8, R.wall_colour)
				if j == pieces.size() - 1:
					_bar(Vector3(p1.x, base, p1.y), Vector3(p1.x, top, p1.y), TRUSS_T, R.wall_colour)

## A deep rusty girder under each span's edges, with drip stains down its face.
static func _girder(y: float) -> void:
	var step := TAU / float(SEGS)
	for vz in [-1.0, 1.0]:
		var pieces := _span_pieces(vz)
		for r in [R.RING_OUT + R.BARRIER_W + GIRDER_T * 0.5, R.RING_IN - R.BARRIER_W - GIRDER_T * 0.5]:
			var top: float = y - SLAB * 0.5 - (R.ring_drop(R.RING_IN) if r < R.RING_IN else 0.0)
			for j in pieces.size():
				var i: int = pieces[j]
				var a0 := step * float(i)
				var a1 := step * float(i + 1)
				var am := step * (float(i) + 0.5)
				var p0 := Vector2(r * cos(a0), r * sin(a0))
				var p1 := Vector2(r * cos(a1), r * sin(a1))
				var c0 := R._p(p0.x, top, p0.y)
				var c1 := R._p(p1.x, top, p1.y)
				var d0 := R._p(p0.x, top - GIRDER_D, p0.y)
				var d1 := R._p(p1.x, top - GIRDER_D, p1.y)
				var outward := Vector3(cos(am), 0.0, -sin(am)) * signf(r - (R.RING_IN + R.RING_OUT) * 0.5)
				R._quad(c0, c1, d0, d1, R.wall_colour, outward)
				R._quad(c0, c1, d0, d1, R.wall_colour, -outward)
				R._quad(d0, d1, d0 - outward * GIRDER_T, d1 - outward * GIRDER_T, R.wall_colour, Vector3.DOWN)
				# a drip stain on the outer face of every third piece
				if j % 3 == 1:
					var sm := R._p(r * cos(am), top - 0.1, r * sin(am)) + outward * 0.01
					var sb := R._p(r * cos(am), top - GIRDER_D + 0.1, r * sin(am)) + outward * 0.01
					var sw := Vector3(-sin(am), 0.0, -cos(am)) * 0.18
					R._quad(sm - sw, sm + sw, sb - sw * 0.5, sb + sw * 0.5, C_STAIN, outward)

## A water tower on the island (x4): four splayed legs, a squat tank, a
## short cap, a ladder stripe, on the +x side.
static func _water_tower() -> void:
	var cx := 24.5
	var leg_h := 11.0
	for sx in [-1.0, 1.0]:
		for sv in [-1.0, 1.0]:
			_bar(Vector3(cx + sx * 2.6, 0.0, sv * 2.6), Vector3(cx + sx * 1.5, leg_h, sv * 1.5), 0.22, C_TANK)
			# a brace half way up
			_bar(Vector3(cx + sx * 2.05, leg_h * 0.5, sv * 2.05), Vector3(cx - sx * 2.05, leg_h * 0.5, sv * 2.05), 0.1, C_TANK)
	R._box(Vector3(cx, leg_h + 0.1, 0.0), Vector3(4.2, 0.2, 4.2), C_TANK)   # the platform
	R._box(Vector3(cx, leg_h + 2.6, 0.0), Vector3(4.6, 4.8, 4.6), C_TANK)   # the tank
	R._box(Vector3(cx, leg_h + 5.3, 0.0), Vector3(3.2, 0.6, 3.2), C_TANK)   # the cap
	R._box(Vector3(cx, leg_h + 5.9, 0.0), Vector3(0.14, 0.6, 0.14), R.C_POLE)  # the vent
	R._box(Vector3(cx + 2.4, leg_h * 0.5 + 1.5, 0.0), Vector3(0.08, leg_h + 3.0, 0.5), R.C_POLE)  # the ladder

## A toppled lattice crane on the island (x8): the cab on its side, the jib
## lying across the island, the hook block on the ground.
static func _crane_wreck() -> void:
	R._box(Vector3(23.5, 1.0, -8.0), Vector3(2.4, 2.0, 2.8), C_WRECK_CAB)        # the cab, on its side
	R._box(Vector3(23.5, 0.35, -8.0), Vector3(3.2, 0.7, 3.6), C_WRECK)           # its base
	var foot := Vector3(23.8, 1.6, -6.4)
	var tip := Vector3(25.6, 0.8, 10.5)
	_bar(foot + Vector3(-0.5, 0.0, 0.0), tip + Vector3(-0.4, 0.0, 0.0), 0.2, C_WRECK)
	_bar(foot + Vector3(0.5, 0.0, 0.0), tip + Vector3(0.4, 0.0, 0.0), 0.2, C_WRECK)
	_bar(foot + Vector3(0.0, 0.8, 0.0), tip + Vector3(0.0, 0.5, 0.0), 0.2, C_WRECK)
	for k in 6:
		var t := float(k) / 5.0
		var at := foot.lerp(tip, t)
		_bar(at + Vector3(-0.5, 0.0, 0.0), at + Vector3(0.0, 0.8 - 0.3 * t, 0.0), 0.1, C_WRECK)
		_bar(at + Vector3(0.5, 0.0, 0.0), at + Vector3(0.0, 0.8 - 0.3 * t, 0.0), 0.1, C_WRECK)
	R._box(Vector3(25.9, 0.3, 11.5), Vector3(0.5, 0.6, 0.7), R.C_POLE)          # the hook block
	_bar(Vector3(25.6, 0.9, 10.5), Vector3(25.9, 0.6, 11.5), 0.04, R.C_POLE)     # the cable

## The shared placeholder landmark: a dead tree and a shopping trolley on the
## ground inside the ring, on the +x side.
static func _landmark() -> void:
	R._box(Vector3(24.0, 2.3, 0.0), Vector3(0.45, 4.6, 0.45), C_TREE)
	R._box(Vector3(24.9, 3.9, 0.15), Vector3(1.9, 0.2, 0.2), C_TREE)
	R._box(Vector3(25.8, 4.5, 0.15), Vector3(0.16, 1.2, 0.16), C_TREE)
	R._box(Vector3(23.4, 4.4, -0.6), Vector3(0.2, 0.2, 1.5), C_TREE)
	R._box(Vector3(23.4, 5.0, -1.3), Vector3(0.14, 1.3, 0.14), C_TREE)
	R._box(Vector3(24.0, 5.4, 0.0), Vector3(0.25, 1.7, 0.25), C_TREE)
	R._box(Vector3(24.3, 6.0, 0.5), Vector3(0.12, 0.12, 1.1), C_TREE)
	# the trolley, on its side
	R._box(Vector3(25.6, 0.3, 1.6), Vector3(0.9, 0.5, 0.55), C_TROLLEY)
	R._box(Vector3(26.15, 0.62, 1.6), Vector3(0.06, 0.2, 0.6), C_TROLLEY)
