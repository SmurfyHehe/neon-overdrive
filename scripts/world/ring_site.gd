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
#   docks; rust in industrial areas);
# - a "stop" or "lot" site has a spur: a stub of an arm off the ring on the
#   stop's side, ending at a barrier until the stops are built;
# - a "landmark" site has something on the ground inside the ring (one
#   shared placeholder for now: a dead tree and a shopping trolley).
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

const C_UNDER := Color(0.07, 0.07, 0.075, 0.0)
const C_BOARD := Color(0.03, 0.03, 0.03, 0.0)
const C_CHEVRON := Color(0.88, 0.88, 0.84, 0.05)
const C_SPLIT_A := Color(1.0, 0.54, 0.12, 0.035)
const C_SPLIT_B := Color(0.85, 0.85, 0.8, 0.035)
const C_NOSE := Color(1.0, 0.54, 0.12, 0.6)
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
	return {"style": style, "spur": RoadMap.ring_spur_side(ring), "landmark": String(r.kind) == "landmark"}

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
	mm.instance_count = LAMP_DEG.size()
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
	visible = true
	force_update_transform()
	for c in get_children():
		if c is CollisionObject3D:
			(c as Node3D).force_update_transform()

func _dress(look: Dictionary) -> void:
	var key := "%s|%d|%s" % [look.style, look.spur, look.landmark]
	if not _looks.has(key):
		_looks[key] = build(look)
	var made: Dictionary = _looks[key]
	_mesh.mesh = made.mesh
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
	return {"verts": verts, "faces": faces, "boxes": boxes, "pools": _pools.multimesh.visible_instance_count,
		"signs": _signs.multimesh.visible_instance_count,
		"draws": (1 if verts > 0 else 0) + (1 if _pools.multimesh.visible_instance_count > 0 else 0) + (1 if _signs.multimesh.visible_instance_count > 0 else 0)}

# ---------- geometry ----------

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
	# tall sodium lamps on the outside barrier, a pool of light under each
	for deg in LAMP_DEG:
		if (deg == 0.0 and spur > 0) or (deg == 180.0 and spur < 0):
			continue
		var a := deg_to_rad(deg)
		var r: float = R.RING_OUT + R.BARRIER_W * 0.5
		R._box(Vector3(r * cos(a), y + LAMP_H * 0.5, r * sin(a)), Vector3(0.16, LAMP_H, 0.16), R.C_POLE)
		R._box(Vector3(r * cos(a), y + LAMP_H + 0.06, r * sin(a)), Vector3(0.8, 0.14, 0.8), R.C_HEAD)
		var mid := (R.RING_IN + R.RING_OUT) * 0.5
		# the pool lies on the leaning deck
		var tip := Basis(Quaternion(Vector3.UP, R.ring_normal(a)))
		R._pools.append(Transform3D(tip * Basis.from_scale(Vector3(POOL, 1.0, POOL)), R._p(mid * cos(a), y - R.ring_drop(mid) + 0.05, mid * sin(a))))
	# chevron boards on the inside, past each entry; a lit marker on each nose
	for base in [0.0, 180.0]:
		_board(deg_to_rad(base + BOARD_DEG), y_in)
		for d in [-6.0, 6.0]:
			var a := deg_to_rad(base + d * R.RING_SEG_DEG)
			var r: float = R.RING_OUT + R.BARRIER_W * 0.5
			R._box(Vector3(r * cos(a), y + R.BARRIER_H + 0.25, r * sin(a)), Vector3(0.36, 0.5, 0.36), C_NOSE)
	if spur != 0:
		_spur(float(spur), y)
	if bool(look.landmark):
		_landmark()
	var made := R.end_flat()
	R.wall_colour = R.C_WALL
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made.arrays)
	return {"mesh": mesh, "faces": made.faces, "boxes": made.boxes, "pools": made.pools}

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
