extends Node3D

# A pocket: a place at the end of a ring's arm (ramps doc step 7,
# notes/better-ramps-and-destinations-2026-10-13.md section 5; Roy 1505:
# the Docks pier first, 1539: build). The first exit that leads somewhere.
#
# A pocket hangs off the spur of a ring site (RoadMap.POCKETS names the ring
# and the side). The spur's stub (RingSite._spur, RAMP_H up, to SPUR_END)
# goes on as the ARM: two lanes that bend a quarter turn to run along the
# road and drop to the pocket's floor over ARM_LEN, kerbs, barriers and
# studs like a ramp; then the LOT: one flat slab you drive round and leave
# the way you came (every pocket is a loop, never a stub). What stands on
# the lot is the pocket's kind:
#
#   pier   the Docks pier (x5a, the act-1 meet spot): a concrete apron
#          PIER_Y above the water, bollards along the edge, a moored ship's
#          hull as the far wall with its lit bridge, two gantry cranes with
#          white harbour lamps, parked racers with their hazards blinking,
#          the lamps' light lying on the water.
#
# Built once per pocket in the ring's flat space (RoadRamps' tools: x out
# from the road's centre line on the pocket's side, y up, v along the road,
# turned by `turn` so the arm bends with the road's direction) and kept; one
# node per pocket, standing at its ring like RingSite stands at the nearest
# one, shown within SHOW_WITHIN of it. The chunk builder clears the lots and
# moves the out-of-bounds wall past the pocket (RoadRamps.pocket_bound).
#
# To the car: the arm and the lot are concrete (SurfaceMap.DECK_META), a
# car on them is "off the main road" (RoadRamps.place_of, part "pocket"), a
# save made there loads at the ring's arm and so does a put-back (Roy 1506).
#
# Cost: 2 draw calls (one mesh on RoadRamps' material, one MultiMesh of
# light pools), a trimesh for the deck, boxes for the walls. No new
# material, no real lights, nothing moves.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const R := preload("res://scripts/world/road_ramps.gd")
const RingSite := preload("res://scripts/world/ring_site.gd")

const L := 50.0
## The arm: starts where the spur's stub ends, bends ARC_R round a quarter
## turn, then runs ARM_STRAIGHT along the road; two lanes ARM_HALF each
## side of its centre line (the stub is SPUR_HALF, it widens over the bend).
const ARM_START := RingSite.SPUR_END
const ARC_R := 30.0
const ARM_STRAIGHT := 75.0
const ARM_HALF := 4.0
const ARM_ROW := 4.0
## The drop from RAMP_H to the pocket's floor, eased at both ends like a
## ramp's climb (RoadRamps.EASE_IN / EASE_OUT).
const EASE_IN := 20.0
const EASE_OUT := 15.0
## The floor of the pier above the road's level (the water lies at WATER_Y).
const PIER_Y := 1.2
const WATER_Y := 0.03
## The lot: x from LOT_X0 to LOT_X1 out from the centre line, LOT_LEN along
## the road from where the arm ends. Everything a car drives on stays within
## 100 m of the centre line: RoadFrame.unroll reads no further out than that
## (RoadFrame.BESIDE), and the car's place, the save and the rescue all read
## through it.
const LOT_X0 := 58.0
const LOT_X1 := 96.0
const LOT_LEN := 100.0
## The out-of-bounds wall stands this far out along the pocket, and the
## pocket's footprint along the road (for place_of and the builder).
const BOUND := 130.0
const REACH_V := 240.0
## Shown while the player is within this of the ring, metres along the road.
const SHOW_WITHIN := 600.0
const POOL_CAPACITY := 14
const BOLLARD_EVERY := 8.0
const EDGE_H := 0.45     # the pier's edge wall
const LAMP_H := 12.0

const C_APRON := Color(0.14, 0.14, 0.145, 0.0)
const C_WATER := Color(0.025, 0.04, 0.065, 0.0)
const C_HULL := Color(0.2, 0.09, 0.06, 0.0)
const C_HULL_LINE := Color(0.42, 0.12, 0.08, 0.0)
const C_HOUSE := Color(0.5, 0.5, 0.48, 0.0)
const C_WINDOW := Color(1.0, 0.72, 0.35, 0.3)
const C_CRANE := Color(0.22, 0.26, 0.3, 0.0)
const C_LAMP_WHITE := Color(0.85, 0.9, 1.0, 1.0)
const C_BOLLARD := Color(0.12, 0.12, 0.12, 0.0)
const C_HAZARD := Color(1.0, 0.6, 0.15, 0.6)   # in the shader's blink band
const C_RACERS: Array[Color] = [Color(0.12, 0.14, 0.22, 0.0), Color(0.3, 0.08, 0.06, 0.0), Color(0.2, 0.2, 0.21, 0.0), Color(0.08, 0.1, 0.09, 0.0)]
const C_GLASS := Color(0.06, 0.07, 0.09, 0.0)
const C_TYRE := Color(0.05, 0.05, 0.05, 0.0)

static var enabled := true
static var _builds := {}   # pocket id -> {mesh, faces, boxes, pools}

var pocket := {}
var ring := -1
var _site_s := -1.0
var _origin := -999999
var _mesh: MeshInstance3D
var _pools: MultiMeshInstance3D
var _deck: CollisionShape3D
var _walls: StaticBody3D

# ---------- the arm's line ----------

## Length of the arm from the stub's end to the lot, m.
static func arm_len() -> float:
	return ARC_R * PI * 0.5 + ARM_STRAIGHT

## A point of the arm's centre line `s` metres from the stub's end, for a
## pocket on side +1 bending toward +v: {p (x, v), t (unit tangent), n (unit
## normal to the left of travel)}. `turn` mirrors v.
static func arm_at(s: float, turn: float) -> Dictionary:
	var arc := ARC_R * PI * 0.5
	var p: Vector2
	var t: Vector2
	if s <= arc:
		var a := s / ARC_R
		p = Vector2(ARM_START + ARC_R * sin(a), ARC_R - ARC_R * cos(a))
		t = Vector2(cos(a), sin(a))
	else:
		p = Vector2(ARM_START + ARC_R, ARC_R + (s - arc))
		t = Vector2(0.0, 1.0)
	p.y *= turn
	t.y *= turn
	return {"p": p, "t": t, "n": Vector2(-t.y, t.x) * turn}

## Height of the arm's deck above the road `s` metres from the stub's end:
## RAMP_H down to PIER_Y with eased ends.
static func arm_y(s: float) -> float:
	var run := arm_len()
	var drop := R.RAMP_H - PIER_Y
	if s <= 0.0:
		return R.RAMP_H
	if s >= run:
		return PIER_Y
	var g := drop / (run - (EASE_IN + EASE_OUT) * 0.5)
	var d := 0.0
	if s < EASE_IN:
		d = g * s * s / (2.0 * EASE_IN)
	elif s > run - EASE_OUT:
		d = drop - g * (run - s) * (run - s) / (2.0 * EASE_OUT)
	else:
		d = g * (s - EASE_IN * 0.5)
	return R.RAMP_H - d

## The arm's half width `s` from the stub's end: the stub's, widening to
## ARM_HALF over the first 30 m.
static func arm_half(s: float) -> float:
	return lerpf(RingSite.SPUR_HALF, ARM_HALF, clampf(s / 30.0, 0.0, 1.0))

## The steepest the arm gets.
static func max_grade() -> float:
	return (R.RAMP_H - PIER_Y) / (arm_len() - (EASE_IN + EASE_OUT) * 0.5)

## Whether (x out on the pocket's side, v signed along the road) is on the
## pocket's footprint: the arm's deck (within `slack` of its edge) or the lot.
static func covers(pk: Dictionary, x: float, v: float, slack: float = 0.6) -> bool:
	var turn := float(pk.turn)
	var vv := v * turn
	if x >= LOT_X0 - slack and x <= LOT_X1 + slack and vv >= ARC_R + ARM_STRAIGHT - slack and vv <= ARC_R + ARM_STRAIGHT + LOT_LEN + slack:
		return true
	# the arm: nearest point of its line
	var best := INF
	var s := 0.0
	var run := arm_len()
	while s <= run + 0.01:
		var a := arm_at(s, 1.0)
		var d := (a.p as Vector2).distance_to(Vector2(x, vv)) - arm_half(s) - slack
		best = minf(best, d)
		s += 2.0
	return best <= 0.0

## Height of the pocket's deck under (x, v signed), or -INF off it.
static func deck_y(pk: Dictionary, x: float, v: float) -> float:
	var turn := float(pk.turn)
	var vv := v * turn
	if x >= LOT_X0 and x <= LOT_X1 and vv >= ARC_R + ARM_STRAIGHT - 0.5 and vv <= ARC_R + ARM_STRAIGHT + LOT_LEN:
		return PIER_Y + R.LIFT
	var best := INF
	var at_s := 0.0
	var s := 0.0
	var run := arm_len()
	while s <= run + 0.01:
		var a := arm_at(s, 1.0)
		var d := (a.p as Vector2).distance_to(Vector2(x, vv))
		if d < best:
			best = d
			at_s = s
		s += 1.0
	return arm_y(at_s) + R.LIFT if best <= arm_half(at_s) + 0.6 else -INF

# ---------- nodes ----------

func _ready() -> void:
	name = "Pocket_%s" % String(pocket.get("id", "none"))
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mesh = MeshInstance3D.new()
	_mesh.name = "Pocket"
	_mesh.material_override = RoadRamps.material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = RoadChunkBuilder._get_pool_mesh()
	mm.instance_count = POOL_CAPACITY
	mm.visible_instance_count = 0
	_pools = MultiMeshInstance3D.new()
	_pools.name = "PocketPools"
	_pools.multimesh = mm
	_pools.material_override = RoadChunkBuilder._get_pool_mat("white")
	_pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pools)
	var deck := StaticBody3D.new()
	deck.name = "PocketDeck"
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
	_walls.name = "PocketWalls"
	CarSpec.make_wall(_walls)
	add_child(_walls)
	for i in RoadMap.rings().size():
		if String(RoadMap.rings()[i].id) == String(pocket.get("ring", "")):
			ring = i
	if ring >= 0:
		_dress()
	_place()

func _physics_process(_delta: float) -> void:
	_place()

## Stands at its ring, shown while the player is near; follows the floating
## origin.
func _place() -> void:
	var on := enabled and RoadRamps.enabled and RoadRamps.ring and RoadMap.is_loop() and ring >= 0
	if on:
		var lap := RoadMap.length()
		var d := absf(fposmod(RingSite.focus_s - float(RoadMap.rings()[ring].s) + lap * 0.5, lap) - lap * 0.5)
		on = d < SHOW_WITHIN
	if not on:
		if visible:
			visible = false
			_deck.disabled = true
			for c in _walls.get_children():
				(c as CollisionShape3D).disabled = true
		return
	# the ring's centre on the lap nearest the player
	var lap := RoadMap.length()
	var s := float(RoadMap.rings()[ring].s) + roundf((RingSite.focus_s - float(RoadMap.rings()[ring].s)) / lap) * lap
	if visible and s == _site_s and RoadFrame.origin_index == _origin:
		return
	_origin = RoadFrame.origin_index
	_site_s = s
	var cz := float(RoadFrame.origin_index) * L - _site_s
	global_transform = Transform3D(RoadFrame.basis_at(cz), RoadFrame.roll(Vector3(0.0, 0.0, cz)))
	reset_physics_interpolation()
	if not visible:
		_deck.disabled = false
		for c in _walls.get_children():
			(c as CollisionShape3D).disabled = false
	visible = true
	force_update_transform()
	for c in get_children():
		if c is CollisionObject3D:
			(c as Node3D).force_update_transform()

func _dress() -> void:
	var key := String(pocket.id)
	if not _builds.has(key):
		_builds[key] = build(pocket)
	var made: Dictionary = _builds[key]
	_mesh.mesh = made.mesh
	(_deck.shape as ConcavePolygonShape3D).set_faces(made.faces)
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
		"draws": (1 if verts > 0 else 0) + (1 if _pools.multimesh.visible_instance_count > 0 else 0)}

# ---------- geometry ----------

## Lays a pocket out: {mesh, faces, boxes, pools}. Side +1 only for now (the
## pier); a side -1 pocket would mirror x.
static func build(pk: Dictionary) -> Dictionary:
	assert(int(pk.side) == 1, "pockets on the -1 side are not laid out yet")
	R.begin_flat()
	R.wall_colour = RingSite.WALLS["steel"] if String(pk.kind) == "pier" else R.C_WALL
	var turn := float(pk.turn)
	_arm(turn)
	_lot(turn)
	match String(pk.kind):
		"pier":
			_pier(turn)
	var made := R.end_flat()
	R.wall_colour = R.C_WALL
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made.arrays)
	return {"mesh": mesh, "faces": made.faces, "boxes": made.boxes, "pools": made.pools}

## The arm: rows across its centre line every ARM_ROW, the deck between them,
## kerb and barrier down both edges, a dashed line between its two lanes,
## white lamps on the outside of the bend.
static func _arm(turn: float) -> void:
	var run := arm_len()
	var n := ceili(run / ARM_ROW)
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	var left_out: Array[Vector2] = []
	var right_out: Array[Vector2] = []
	var hs := PackedFloat32Array()
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in n + 1:
		var s := minf(float(i) * ARM_ROW, run)
		var a := arm_at(s, turn)
		var p: Vector2 = a.p
		var nrm: Vector2 = a.n
		var h := arm_half(s)
		var y := arm_y(s) + R.LIFT
		var pl := Vector3(p.x + nrm.x * h, p.y + nrm.y * h, y)
		var pr := Vector3(p.x - nrm.x * h, p.y - nrm.y * h, y)
		left.append(pl)
		right.append(pr)
		left_out.append(nrm)
		right_out.append(-nrm)
		# the barriers run the whole arm and stop short of the lot
		hs.append(R.BARRIER_H if s < run - 0.5 else 0.0)
		if i > 0:
			R._deck_quad(R._p(prev_l.x, prev_l.z, prev_l.y), R._p(prev_r.x, prev_r.z, prev_r.y), R._p(pl.x, pl.z, pl.y), R._p(pr.x, pr.z, pr.y))
			# the dashed line between the two lanes, every other row
			if i % 2 == 1:
				var c0 := (prev_l + prev_r) * 0.5
				var c1 := (pl + pr) * 0.5
				var along := Vector2(c1.x - c0.x, c1.y - c0.y).normalized() * 0.5
				var across := Vector2(-along.y, along.x) * 0.12
				R._quad(R._p(c0.x + along.x - across.x, c0.z + R.PAINT_LIFT, c0.y + along.y - across.y), R._p(c0.x + along.x + across.x, c0.z + R.PAINT_LIFT, c0.y + along.y + across.y),
					R._p(c1.x - along.x - across.x, c1.z + R.PAINT_LIFT, c1.y - along.y - across.y), R._p(c1.x - along.x + across.x, c1.z + R.PAINT_LIFT, c1.y - along.y + across.y), R.C_PAINT, Vector3.UP)
		prev_l = pl
		prev_r = pr
	R._edge(left, left_out, hs)
	R._edge(right, right_out, hs)
	# lamps on the outside of the bend (the right-hand edge, away from the ring)
	for s in [30.0, 75.0, 115.0]:
		var a := arm_at(s, turn)
		var p: Vector2 = a.p
		var nrm: Vector2 = a.n
		var h := arm_half(s) + R.BARRIER_W + 0.2
		_lamp(Vector2(p.x - nrm.x * h, p.y - nrm.y * h), arm_y(s), nrm, 2.0, 7.0)

## A white lamp: a pole from the ground to `y` + height, an arm `reach`
## toward `toward`, a head and a pool of light under it.
static func _lamp(at: Vector2, y: float, toward: Vector2, reach: float, height: float) -> void:
	var top := y + height
	R._box(Vector3(at.x, (top + R.SKIRT) * 0.5 - R.SKIRT * 0.5, at.y), Vector3(0.18, top + R.SKIRT, 0.18), R.C_POLE)
	var hx := at.x + toward.x * reach
	var hv := at.y + toward.y * reach
	R._box(Vector3((at.x + hx) * 0.5, top, (at.y + hv) * 0.5), Vector3(absf(hx - at.x) + 0.12, 0.1, absf(hv - at.y) + 0.12), R.C_POLE)
	R._box(Vector3(hx, top - 0.1, hv), Vector3(0.5, 0.14, 0.7), C_LAMP_WHITE)
	var px := at.x + toward.x * (reach + 1.0)
	var pv := at.y + toward.y * (reach + 1.0)
	R._pools.append(Transform3D(Basis.from_scale(Vector3(height * 1.3, 1.0, height * 1.6)), R._p(px, y + 0.06, pv)))

## The lot: one slab at PIER_Y from where the arm ends, an edge wall and
## kerb all round but at the arm's mouth, bollards along the water.
static func _lot(turn: float) -> void:
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var v1 := (ARC_R + ARM_STRAIGHT + LOT_LEN) * turn
	var y := PIER_Y + R.LIFT
	# the slab, in strips (so the trimesh stays fine for the wheels)
	var strips := 10
	for i in strips:
		var va := lerpf(v0, v1, float(i) / float(strips))
		var vb := lerpf(v0, v1, float(i + 1) / float(strips))
		R._quad(R._p(LOT_X0, y, va), R._p(LOT_X1, y, va), R._p(LOT_X0, y, vb), R._p(LOT_X1, y, vb), C_APRON, Vector3.UP)
		R._deck_faces([R._p(LOT_X0, y, va), R._p(LOT_X1, y, va), R._p(LOT_X0, y, vb), R._p(LOT_X1, y, va), R._p(LOT_X1, y, vb), R._p(LOT_X0, y, vb)])
	# the face down to the ground on the land side and the water side
	for x in [LOT_X0, LOT_X1]:
		var out := -1.0 if x == LOT_X0 else 1.0
		R._quad(R._p(x, y, v0), R._p(x, y, v1), R._p(x, -R.SKIRT, v0), R._p(x, -R.SKIRT, v1), R.wall_colour, Vector3(out, 0.0, 0.0))
	R._quad(R._p(LOT_X0, y, v1), R._p(LOT_X1, y, v1), R._p(LOT_X0, -R.SKIRT, v1), R._p(LOT_X1, -R.SKIRT, v1), R.wall_colour, Vector3(0.0, 0.0, -turn))
	# the edge: a low wall with a kerb, all round except the arm's mouth
	var full := PackedFloat32Array([EDGE_H, EDGE_H])
	var mouth_x := ARM_START + ARC_R
	var edges := [
		[Vector3(LOT_X0, v0, y), Vector3(LOT_X0, v1, y), Vector2(-1.0, 0.0)],
		[Vector3(LOT_X0, v1, y), Vector3(LOT_X1, v1, y), Vector2(0.0, turn)],
		[Vector3(LOT_X1, v1, y), Vector3(LOT_X1, v0, y), Vector2(1.0, 0.0)],
		[Vector3(LOT_X1, v0, y), Vector3(mouth_x + ARM_HALF + 0.3, v0, y), Vector2(0.0, -turn)],
		[Vector3(mouth_x - ARM_HALF - 0.3, v0, y), Vector3(LOT_X0, v0, y), Vector2(0.0, -turn)],
	]
	for e in edges:
		var pts: Array[Vector3] = [e[0], e[1]]
		var outs: Array[Vector2] = [e[2], e[2]]
		R._edge(pts, outs, full)
	# bollards along the water's edge
	var v := v0 + BOLLARD_EVERY * 0.5 * turn
	while absf(v - v0) < LOT_LEN:
		R._box(Vector3(LOT_X1 - 0.9, PIER_Y + 0.4, v), Vector3(0.42, 0.8, 0.42), C_BOLLARD)
		R._box(Vector3(LOT_X1 - 0.9, PIER_Y + 0.82, v), Vector3(0.5, 0.1, 0.5), C_BOLLARD)
		v += BOLLARD_EVERY * turn

## The pier's things: the water, the moored ship, two gantry cranes, mast
## lamps, parked racers with their hazards on.
static func _pier(turn: float) -> void:
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var v1 := (ARC_R + ARM_STRAIGHT + LOT_LEN) * turn
	var vm := (v0 + v1) * 0.5
	# the water: beyond the pier's edge and past its end, dark and still
	R._quad(R._p(LOT_X1, WATER_Y, v0 - 30.0 * turn), R._p(BOUND + 20.0, WATER_Y, v0 - 30.0 * turn), R._p(LOT_X1, WATER_Y, v1 + 40.0 * turn), R._p(BOUND + 20.0, WATER_Y, v1 + 40.0 * turn), C_WATER, Vector3.UP)
	R._quad(R._p(LOT_X0 - 10.0, WATER_Y, v1), R._p(LOT_X1, WATER_Y, v1), R._p(LOT_X0 - 10.0, WATER_Y, v1 + 40.0 * turn), R._p(LOT_X1, WATER_Y, v1 + 40.0 * turn), C_WATER, Vector3.UP)
	# the ship: a hull along the pier, its bridge aft, a mast lamp; a wall to the car
	var hull_x := LOT_X1 + 7.5
	R._box(Vector3(hull_x, 4.0, vm), Vector3(13.0, 10.0, 88.0), C_HULL)
	R._box(Vector3(hull_x, 2.2, vm), Vector3(13.1, 0.5, 88.1), C_HULL_LINE)   # the waterline stripe
	R._box(Vector3(hull_x, 9.1, vm), Vector3(13.4, 0.3, 88.4), C_HOUSE)      # the deck's edge
	var aft := vm + 30.0 * turn
	R._box(Vector3(hull_x, 12.5, aft), Vector3(10.0, 7.0, 13.0), C_HOUSE)
	R._box(Vector3(hull_x, 17.0, aft), Vector3(9.0, 2.2, 7.0), C_HOUSE)      # the bridge deck
	for k in 6:
		var wv := aft + (float(k) - 2.5) * 1.3 * turn
		R._quad(R._p(hull_x - 4.52, 16.6, wv - 0.5), R._p(hull_x - 4.52, 16.6, wv + 0.5), R._p(hull_x - 4.52, 17.6, wv - 0.5), R._p(hull_x - 4.52, 17.6, wv + 0.5), C_WINDOW, Vector3(-1.0, 0.0, 0.0))
	for k in 8:
		var wv := vm + (float(k) - 3.5) * 9.0 * turn
		R._quad(R._p(hull_x - 6.52, 7.0, wv - 0.35), R._p(hull_x - 6.52, 7.0, wv + 0.35), R._p(hull_x - 6.52, 7.7, wv - 0.35), R._p(hull_x - 6.52, 7.7, wv + 0.35), C_WINDOW, Vector3(-1.0, 0.0, 0.0))
	R._box(Vector3(hull_x, 16.0, vm - 32.0 * turn), Vector3(1.2, 4.0, 1.2), C_HOUSE)   # the funnel's stump forward
	R._box(Vector3(hull_x, 22.0, aft), Vector3(0.2, 8.0, 0.2), R.C_POLE)              # the mast
	R._box(Vector3(hull_x, 26.2, aft), Vector3(0.5, 0.4, 0.5), C_LAMP_WHITE)
	R._wall_box(R._p(LOT_X1 + 1.0, 0.0, v0), R._p(LOT_X1 + 1.0, 0.0, v1), 0.0, 10.0, 0.6)   # the hull's wall
	# the lamps' light on the water
	for wv in [vm - 36.0 * turn, aft]:
		R._pools.append(Transform3D(Basis.from_scale(Vector3(9.0, 1.0, 16.0)), R._p(LOT_X1 + 2.5, WATER_Y + 0.02, wv)))
	# two gantry cranes over the apron, their booms out over the ship
	for cv in [v0 + 25.0 * turn, v0 + 80.0 * turn]:
		_crane(cv, turn)
	# mast lamps on the land side
	for lv in [v0 + 12.0 * turn, v0 + 88.0 * turn]:
		_lamp(Vector2(LOT_X0 + 0.9, lv), PIER_Y, Vector2(1.0, 0.0), 2.5, LAMP_H)
	# the racers, parked nose to the water along the apron, hazards on
	for k in 4:
		_racer(Vector2(LOT_X1 - 7.0, v0 + (38.0 + 8.0 * float(k)) * turn), C_RACERS[k], float(k))

## A gantry crane: four legs on the apron, a crossbeam, a boom out over the
## water with two white lamps and their pools.
static func _crane(cv: float, turn: float) -> void:
	var h := 18.0
	for lx in [LOT_X0 + 2.0, LOT_X0 + 8.0]:
		for dv in [-4.0, 4.0]:
			R._box(Vector3(lx, (h + R.SKIRT) * 0.5 - R.SKIRT * 0.5, cv + dv), Vector3(0.6, h + R.SKIRT, 0.6), C_CRANE)
			R._wall_box(R._p(lx, 0.0, cv + dv - 0.3), R._p(lx, 0.0, cv + dv + 0.3), 0.0, 3.0, 0.6)
		R._box(Vector3(lx, h + 0.4, cv), Vector3(0.7, 0.8, 9.0), C_CRANE)
	R._box(Vector3(LOT_X0 + 5.0, h + 0.4, cv), Vector3(7.0, 0.8, 0.8), C_CRANE)   # the crossbeam
	var boom_x0 := LOT_X0
	var boom_x1 := LOT_X1 + 16.0
	R._box(Vector3((boom_x0 + boom_x1) * 0.5, h + 1.4, cv), Vector3(boom_x1 - boom_x0, 1.2, 1.4), C_CRANE)
	R._box(Vector3(LOT_X0 + 5.0, h + 4.5, cv), Vector3(0.4, 5.0, 0.4), C_CRANE)   # the A-frame post
	for lx in [LOT_X0 + 26.0, LOT_X1 + 4.0]:
		R._box(Vector3(lx, h + 0.6, cv), Vector3(0.9, 0.3, 0.9), C_LAMP_WHITE)
		var ground := PIER_Y if lx < LOT_X1 else WATER_Y
		R._pools.append(Transform3D(Basis.from_scale(Vector3(22.0, 1.0, 26.0)), R._p(lx, ground + 0.06, cv)))
	var tipv := cv
	if turn > 0.0:
		tipv = cv
	R._box(Vector3(LOT_X1 + 2.0, h - 1.5, tipv), Vector3(0.1, 4.0, 0.1), R.C_POLE)   # a cable
	R._box(Vector3(LOT_X1 + 2.0, h - 3.8, tipv), Vector3(0.8, 0.6, 0.8), C_CRANE)   # the spreader

## A parked racer at `at` (its centre), facing +x (the water): body, cabin,
## four wheels, four hazard lights that blink with the shader, one box.
static func _racer(at: Vector2, paint: Color, k: float) -> void:
	var y := PIER_Y + R.LIFT
	var yaw_skew := (k - 1.5) * 0.4   # parked a little crooked, as racers are
	var cx := at.x
	var cv := at.y + yaw_skew
	R._box(Vector3(cx, y + 0.55, cv), Vector3(4.4, 0.65, 1.85), paint)
	R._box(Vector3(cx - 0.3, y + 1.1, cv), Vector3(2.2, 0.55, 1.6), C_GLASS)
	R._box(Vector3(cx - 0.3, y + 1.38, cv), Vector3(1.9, 0.08, 1.5), paint)   # the roof
	for dx in [-1.4, 1.4]:
		for dv in [-0.85, 0.85]:
			R._box(Vector3(cx + dx, y + 0.32, cv + dv), Vector3(0.64, 0.64, 0.24), C_TYRE)
	for dx in [-2.19, 2.19]:
		for dv in [-0.75, 0.75]:
			R._quad(R._p(cx + dx * 1.0, y + 0.72, cv + dv - 0.14), R._p(cx + dx * 1.0, y + 0.72, cv + dv + 0.14),
				R._p(cx + dx * 1.0, y + 0.86, cv + dv - 0.14), R._p(cx + dx * 1.0, y + 0.86, cv + dv + 0.14), C_HAZARD, Vector3(signf(dx), 0.0, 0.0))
	R._wall_box(R._p(cx - 2.2, 0.0, cv), R._p(cx + 2.2, 0.0, cv), PIER_Y, PIER_Y + 1.4, 1.85)
