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
#   truck  the truck stop (x3a, step 8): a tall lit sign on a pole, two
#          diesel canopies glowing sodium, pump islands, parked trucks with
#          amber marker lights (one with its hazards going), the diner's
#          warm window along the back.
#   diner  the drive-in diner (x3b, step 8): a round lit sign, the diner
#          with its long window, a canopy with a row of cars parked under it
#          with their lights on, a loop lot.
#
# A pocket on side -1 is laid out as if on side +1 and mirrored (_mirror).
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
const ARM_STRAIGHT := 80.0
const ARM_HALF := 4.0
const ARM_ROW := 4.0
## The drop from RAMP_H to the pocket's floor, eased at both ends like a
## ramp's climb (RoadRamps.EASE_IN / EASE_OUT).
const EASE_IN := 20.0
const EASE_OUT := 15.0
## The floor of the pier above the road's level (the water lies at WATER_Y);
## the other pockets stand on the ground, a slab's thickness up.
const PIER_Y := 1.2
const WATER_Y := 0.03
const GROUND_Y := 0.12
## The lot: x from LOT_X0 to LOT_X1 out from the centre line, lot_len()
## along the road from where the arm ends. Everything a car drives on stays within
## 100 m of the centre line: RoadFrame.unroll reads no further out than that
## (RoadFrame.BESIDE), and the car's place, the save and the rescue all read
## through it.
const LOT_X0 := 58.0
const LOT_X1 := 96.0
const LOT_LEN := 100.0          # the pier's; see lot_len()
const LOT_LENS := {"pier": 100.0, "truck": 130.0, "diner": 80.0}
## The out-of-bounds wall stands this far out along the pocket, and the
## pocket's footprint along the road (for place_of and the builder).
const BOUND := 130.0
const REACH_V := 240.0          # the pier's; see reach_v()
## Shown while the player is within this of the ring, metres along the road.
const SHOW_WITHIN := 600.0
const POOL_CAPACITY := 20
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
const C_CANOPY := Color(0.3, 0.3, 0.32, 0.0)
const C_CANOPY_LIT := Color(1.0, 0.85, 0.6, 0.32)   # the underside, lit
const C_SIGN_AMBER := Color(1.0, 0.62, 0.12, 0.5)
const C_SIGN_RED := Color(0.9, 0.1, 0.08, 0.5)
const C_SIGN_WHITE := Color(1.0, 0.95, 0.85, 0.45)
const C_MARKER := Color(1.0, 0.55, 0.1, 0.45)      # a truck's marker lights, steady
const C_TAIL := Color(0.9, 0.08, 0.05, 0.4)
const C_HEADLIGHT := Color(1.0, 0.95, 0.85, 0.5)
const C_TRUCK_CAB: Array[Color] = [Color(0.6, 0.1, 0.08, 0.0), Color(0.1, 0.2, 0.45, 0.0), Color(0.75, 0.75, 0.72, 0.0), Color(0.12, 0.35, 0.18, 0.0), Color(0.5, 0.45, 0.1, 0.0)]
const C_TRAILER := Color(0.7, 0.7, 0.68, 0.0)
const C_PUMP := Color(0.8, 0.8, 0.78, 0.0)
const C_ISLAND := Color(0.5, 0.5, 0.48, 0.0)
const C_DINER := Color(0.7, 0.68, 0.6, 0.0)
const C_DINER_ROOF := Color(0.3, 0.1, 0.1, 0.0)
const C_DINER_TRIM := Color(0.9, 0.3, 0.5, 0.4)     # the neon-ish trim band
const C_CARS: Array[Color] = [Color(0.55, 0.12, 0.1, 0.0), Color(0.15, 0.18, 0.4, 0.0), Color(0.7, 0.7, 0.68, 0.0), Color(0.1, 0.1, 0.1, 0.0), Color(0.55, 0.5, 0.2, 0.0), Color(0.2, 0.4, 0.3, 0.0)]

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

## The floor height of a pocket's lot.
static func floor_y(pk: Dictionary) -> float:
	return PIER_Y if String(pk.kind) == "pier" else GROUND_Y

## How long a pocket's lot is along the road.
static func lot_len(pk: Dictionary) -> float:
	return float(LOT_LENS.get(String(pk.kind), LOT_LEN))

## How far a pocket reaches along the road from its ring's centre (the way
## its arm turns): the arm, the lot and a little past it.
static func reach_v(pk: Dictionary) -> float:
	return ARC_R + ARM_STRAIGHT + lot_len(pk) + 18.0

## Which light the pocket's lamps throw on the ground (RoadChunkBuilder's
## pool materials).
static func pool_light(pk: Dictionary) -> String:
	return "sodium" if String(pk.kind) == "truck" else "white"

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
## RAMP_H down to the lot's floor with eased ends.
static func arm_y(pk: Dictionary, s: float) -> float:
	var run := arm_len()
	var fy := floor_y(pk)
	var drop := R.RAMP_H - fy
	if s <= 0.0:
		return R.RAMP_H
	if s >= run:
		return fy
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
static func max_grade(pk: Dictionary) -> float:
	return (R.RAMP_H - floor_y(pk)) / (arm_len() - (EASE_IN + EASE_OUT) * 0.5)

## Whether (x out on the pocket's side, v signed along the road) is on the
## pocket's footprint: the arm's deck (within `slack` of its edge) or the lot.
static func covers(pk: Dictionary, x: float, v: float, slack: float = 0.6) -> bool:
	var turn := float(pk.turn)
	var vv := v * turn
	if x >= LOT_X0 - slack and x <= LOT_X1 + slack and vv >= ARC_R + ARM_STRAIGHT - slack and vv <= ARC_R + ARM_STRAIGHT + lot_len(pk) + slack:
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
	if x >= LOT_X0 and x <= LOT_X1 and vv >= ARC_R + ARM_STRAIGHT - 0.5 and vv <= ARC_R + ARM_STRAIGHT + lot_len(pk):
		return floor_y(pk) + R.LIFT
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
	return arm_y(pk, at_s) + R.LIFT if best <= arm_half(at_s) + 0.6 else -INF

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
	_pools.material_override = RoadChunkBuilder._get_pool_mat(pool_light(pocket))
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

## Lays a pocket out: {mesh, faces, boxes, pools}. Laid out on side +1 and
## mirrored across the road for side -1.
static func build(pk: Dictionary) -> Dictionary:
	R.begin_flat()
	R.wall_colour = RingSite.WALLS["steel"] if String(pk.kind) == "pier" else R.C_WALL
	var turn := float(pk.turn)
	_arm(pk, turn)
	_lot(pk, turn)
	match String(pk.kind):
		"pier":
			_pier(turn)
		"truck":
			_truck(turn)
		"diner":
			_diner(turn)
	var made := R.end_flat()
	R.wall_colour = R.C_WALL
	if int(pk.side) < 0:
		made = _mirror(made)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made.arrays)
	return {"mesh": mesh, "faces": made.faces, "boxes": made.boxes, "pools": made.pools}

## The layout mirrored across the road (x -> -x): vertices and normals
## flipped with the triangles' winding, the collision faces the same, the
## boxes' and pools' transforms reflected (M B M keeps a box right-handed).
static func _mirror(made: Dictionary) -> Dictionary:
	var m := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))
	var arrays: Array = made.arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nc := PackedColorArray()
	nv.resize(verts.size())
	nn.resize(norms.size())
	nc.resize(cols.size())
	@warning_ignore("integer_division")
	for t in verts.size() / 3:
		for j in 3:
			var from := t * 3 + (j if j == 0 else 3 - j)   # a b c -> a c b
			var to := t * 3 + j
			nv[to] = m * verts[from]
			nn[to] = m * norms[from]
			nc[to] = cols[from]
	arrays[Mesh.ARRAY_VERTEX] = nv
	arrays[Mesh.ARRAY_NORMAL] = nn
	arrays[Mesh.ARRAY_COLOR] = nc
	var faces: PackedVector3Array = made.faces
	var nf := PackedVector3Array()
	nf.resize(faces.size())
	@warning_ignore("integer_division")
	for t in faces.size() / 3:
		for j in 3:
			nf[t * 3 + j] = m * faces[t * 3 + (j if j == 0 else 3 - j)]
	var boxes: Array = []
	for b in made.boxes:
		var xf: Transform3D = b[0]
		boxes.append([Transform3D(m * xf.basis * m, m * xf.origin), b[1]])
	var pools: Array = []
	for pxf in made.pools:
		var xf: Transform3D = pxf
		pools.append(Transform3D(m * xf.basis * m, m * xf.origin))
	return {"arrays": arrays, "faces": nf, "boxes": boxes, "pools": pools}

## The arm: rows across its centre line every ARM_ROW, the deck between them,
## kerb and barrier down both edges, a dashed line between its two lanes,
## white lamps on the outside of the bend.
static func _arm(pk: Dictionary, turn: float) -> void:
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
		var y := arm_y(pk, s) + R.LIFT
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
	for s: float in [30.0, 75.0, 115.0]:
		var a := arm_at(s, turn)
		var p: Vector2 = a.p
		var nrm: Vector2 = a.n
		var h := arm_half(s) + R.BARRIER_W + 0.2
		_lamp(Vector2(p.x - nrm.x * h, p.y - nrm.y * h), arm_y(pk, s), nrm, 2.0, 7.0)

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

## The lot: one slab at the floor from where the arm ends, an edge wall and
## kerb all round but at the arm's mouth; bollards along the water at the
## pier.
static func _lot(pk: Dictionary, turn: float) -> void:
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var v1 := (ARC_R + ARM_STRAIGHT + lot_len(pk)) * turn
	var fy := floor_y(pk)
	var y := fy + R.LIFT
	# the slab, in strips (so the trimesh stays fine for the wheels)
	var strips := 10
	for i in strips:
		var va := lerpf(v0, v1, float(i) / float(strips))
		var vb := lerpf(v0, v1, float(i + 1) / float(strips))
		R._quad(R._p(LOT_X0, y, va), R._p(LOT_X1, y, va), R._p(LOT_X0, y, vb), R._p(LOT_X1, y, vb), C_APRON, Vector3.UP)
		R._deck_faces([R._p(LOT_X0, y, va), R._p(LOT_X1, y, va), R._p(LOT_X0, y, vb), R._p(LOT_X1, y, va), R._p(LOT_X1, y, vb), R._p(LOT_X0, y, vb)])
	# the face down to the ground on the land side and the water side
	for x: float in [LOT_X0, LOT_X1]:
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
	if String(pk.kind) != "pier":
		return
	# bollards along the water's edge
	var v := v0 + BOLLARD_EVERY * 0.5 * turn
	while absf(v - v0) < lot_len(pk):
		R._box(Vector3(LOT_X1 - 0.9, fy + 0.4, v), Vector3(0.42, 0.8, 0.42), C_BOLLARD)
		R._box(Vector3(LOT_X1 - 0.9, fy + 0.82, v), Vector3(0.5, 0.1, 0.5), C_BOLLARD)
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
	for wv: float in [vm - 36.0 * turn, aft]:
		R._pools.append(Transform3D(Basis.from_scale(Vector3(9.0, 1.0, 16.0)), R._p(LOT_X1 + 2.5, WATER_Y + 0.02, wv)))
	# two gantry cranes over the apron, their booms out over the ship
	for cv: float in [v0 + 25.0 * turn, v0 + 80.0 * turn]:
		_crane(cv, turn)
	# mast lamps on the land side
	for lv: float in [v0 + 12.0 * turn, v0 + 88.0 * turn]:
		_lamp(Vector2(LOT_X0 + 0.9, lv), PIER_Y, Vector2(1.0, 0.0), 2.5, LAMP_H)
	# the racers, parked nose to the water along the apron, hazards on
	for k in 4:
		_racer(Vector2(LOT_X1 - 7.0, v0 + (38.0 + 8.0 * float(k)) * turn), C_RACERS[k], float(k))

## A gantry crane: four legs on the apron, a crossbeam, a boom out over the
## water with two white lamps and their pools.
static func _crane(cv: float, turn: float) -> void:
	var h := 18.0
	for lx: float in [LOT_X0 + 2.0, LOT_X0 + 8.0]:
		for dv: float in [-4.0, 4.0]:
			R._box(Vector3(lx, (h + R.SKIRT) * 0.5 - R.SKIRT * 0.5, cv + dv), Vector3(0.6, h + R.SKIRT, 0.6), C_CRANE)
			R._wall_box(R._p(lx, 0.0, cv + dv - 0.3), R._p(lx, 0.0, cv + dv + 0.3), 0.0, 3.0, 0.6)
		R._box(Vector3(lx, h + 0.4, cv), Vector3(0.7, 0.8, 9.0), C_CRANE)
	R._box(Vector3(LOT_X0 + 5.0, h + 0.4, cv), Vector3(7.0, 0.8, 0.8), C_CRANE)   # the crossbeam
	var boom_x0 := LOT_X0
	var boom_x1 := LOT_X1 + 16.0
	R._box(Vector3((boom_x0 + boom_x1) * 0.5, h + 1.4, cv), Vector3(boom_x1 - boom_x0, 1.2, 1.4), C_CRANE)
	R._box(Vector3(LOT_X0 + 5.0, h + 4.5, cv), Vector3(0.4, 5.0, 0.4), C_CRANE)   # the A-frame post
	for lx: float in [LOT_X0 + 26.0, LOT_X1 + 4.0]:
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
	for dx: float in [-1.4, 1.4]:
		for dv: float in [-0.85, 0.85]:
			R._box(Vector3(cx + dx, y + 0.32, cv + dv), Vector3(0.64, 0.64, 0.24), C_TYRE)
	for dx: float in [-2.19, 2.19]:
		for dv: float in [-0.75, 0.75]:
			R._quad(R._p(cx + dx * 1.0, y + 0.72, cv + dv - 0.14), R._p(cx + dx * 1.0, y + 0.72, cv + dv + 0.14),
				R._p(cx + dx * 1.0, y + 0.86, cv + dv - 0.14), R._p(cx + dx * 1.0, y + 0.86, cv + dv + 0.14), C_HAZARD, Vector3(signf(dx), 0.0, 0.0))
	R._wall_box(R._p(cx - 2.2, 0.0, cv), R._p(cx + 2.2, 0.0, cv), PIER_Y, PIER_Y + 1.4, 1.85)

# ---------- the truck stop ----------

## A diesel canopy: six posts, a flat roof, its underside lit, three pump
## islands under it, a sodium pool under each bay. Centred on (cx, cv),
## its long side along the road.
static func _canopy(cx: float, cv: float, turn: float, y: float, bays: int, lit: Color) -> void:
	var h := 5.5
	var len := float(bays) * 9.0
	var w := 12.0
	for dx: float in [-w * 0.5 + 0.6, w * 0.5 - 0.6]:
		for k in bays + 1:
			var pv := cv + (float(k) - float(bays) * 0.5) * 9.0 * turn
			R._box(Vector3(cx + dx, y + h * 0.5, pv), Vector3(0.4, h, 0.4), C_CANOPY)
	R._box(Vector3(cx, y + h + 0.5, cv), Vector3(w, 1.0, len), C_CANOPY)
	R._quad(R._p(cx - w * 0.5 + 0.3, y + h - 0.01, cv - len * 0.5 * turn + 0.3), R._p(cx + w * 0.5 - 0.3, y + h - 0.01, cv - len * 0.5 * turn + 0.3),
		R._p(cx - w * 0.5 + 0.3, y + h - 0.01, cv + len * 0.5 * turn - 0.3), R._p(cx + w * 0.5 - 0.3, y + h - 0.01, cv + len * 0.5 * turn - 0.3), lit, Vector3.DOWN)
	for k in bays:
		var pv := cv + (float(k) - float(bays) * 0.5 + 0.5) * 9.0 * turn
		R._box(Vector3(cx, y + 0.1, pv), Vector3(1.2, 0.2, 5.0), C_ISLAND)
		R._box(Vector3(cx, y + 0.95, pv), Vector3(0.8, 1.5, 1.1), C_PUMP)
		R._quad(R._p(cx - 0.41, y + 1.2, pv - 0.3), R._p(cx - 0.41, y + 1.2, pv + 0.3), R._p(cx - 0.41, y + 1.6, pv - 0.3), R._p(cx - 0.41, y + 1.6, pv + 0.3), C_SIGN_WHITE, Vector3(-1.0, 0.0, 0.0))
		R._quad(R._p(cx + 0.41, y + 1.2, pv - 0.3), R._p(cx + 0.41, y + 1.2, pv + 0.3), R._p(cx + 0.41, y + 1.6, pv - 0.3), R._p(cx + 0.41, y + 1.6, pv + 0.3), C_SIGN_WHITE, Vector3(1.0, 0.0, 0.0))
		R._wall_box(R._p(cx, 0.0, pv - 2.5), R._p(cx, 0.0, pv + 2.5), y, y + 1.6, 1.2)
		for dx: float in [-3.5, 3.5]:
			R._pools.append(Transform3D(Basis.from_scale(Vector3(8.0, 1.0, 9.0)), R._p(cx + dx, y + 0.06, pv)))

## A parked truck: a cab with its lights on and a trailer, nose along +v,
## marker lights along the trailer's top edge, `hazards` blinking.
static func _truck_rig(cx: float, cv: float, turn: float, y: float, paint: Color, hazards: bool) -> void:
	var cab_v := cv + 7.0 * turn
	R._box(Vector3(cx, y + 1.75, cab_v), Vector3(2.5, 2.9, 2.6), paint)
	R._box(Vector3(cx, y + 2.9, cab_v - 1.4 * turn), Vector3(2.5, 0.6, 0.4), paint)   # the wind deflector
	R._box(Vector3(cx, y + 2.1, cv - 0.5 * turn), Vector3(2.55, 2.9, 13.0), C_TRAILER)
	for dv: float in [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0]:
		var wv := cv + (dv - 0.5) * turn
		for dx: float in [-1.0, 1.0]:
			R._box(Vector3(cx + dx, y + 0.5, wv), Vector3(0.5, 1.0, 1.0), C_TYRE)
	for dx: float in [-1.0, 1.0]:
		R._box(Vector3(cx + dx, y + 0.5, cab_v), Vector3(0.5, 1.0, 1.0), C_TYRE)
	# marker lights along both top edges of the trailer, and the cab's roof
	for k in 7:
		var mv := cv + (float(k) - 3.5) * 1.8 * turn
		for dx: float in [-1.29, 1.29]:
			R._quad(R._p(cx + dx, y + 3.3, mv - 0.08), R._p(cx + dx, y + 3.3, mv + 0.08), R._p(cx + dx, y + 3.45, mv - 0.08), R._p(cx + dx, y + 3.45, mv + 0.08), C_MARKER, Vector3(signf(dx), 0.0, 0.0))
	for dx: float in [-0.9, -0.45, 0.0, 0.45, 0.9]:
		R._quad(R._p(cx + dx - 0.08, y + 3.25, cab_v + 1.31 * turn), R._p(cx + dx + 0.08, y + 3.25, cab_v + 1.31 * turn), R._p(cx + dx - 0.08, y + 3.4, cab_v + 1.31 * turn), R._p(cx + dx + 0.08, y + 3.4, cab_v + 1.31 * turn), C_MARKER, Vector3(0.0, 0.0, -turn))
	# headlights, tail lights, hazards on the corners
	var side_col := C_HAZARD if hazards else C_MARKER
	for dx: float in [-0.9, 0.9]:
		R._quad(R._p(cx + dx - 0.2, y + 1.0, cab_v + 1.31 * turn), R._p(cx + dx + 0.2, y + 1.0, cab_v + 1.31 * turn), R._p(cx + dx - 0.2, y + 1.2, cab_v + 1.31 * turn), R._p(cx + dx + 0.2, y + 1.2, cab_v + 1.31 * turn), C_HEADLIGHT, Vector3(0.0, 0.0, -turn))
		R._quad(R._p(cx + dx - 0.15, y + 1.0, cv - 7.01 * turn), R._p(cx + dx + 0.15, y + 1.0, cv - 7.01 * turn), R._p(cx + dx - 0.15, y + 1.2, cv - 7.01 * turn), R._p(cx + dx + 0.15, y + 1.2, cv - 7.01 * turn), C_TAIL, Vector3(0.0, 0.0, turn))
		for ev: float in [cab_v + 1.0 * turn, cv - 6.5 * turn]:
			R._quad(R._p(cx + dx * 1.42, y + 1.3, ev - 0.12), R._p(cx + dx * 1.42, y + 1.3, ev + 0.12), R._p(cx + dx * 1.42, y + 1.45, ev - 0.12), R._p(cx + dx * 1.42, y + 1.45, ev + 0.12), side_col, Vector3(signf(dx), 0.0, 0.0))
	R._wall_box(R._p(cx, 0.0, cv - 7.0 * turn), R._p(cx, 0.0, cv + 8.4 * turn), y, y + 3.4, 2.6)

## A tall sign on a pole: a lit amber panel with a red band, seen from the
## highway.
static func _pole_sign(cx: float, cv: float, y: float, height: float) -> void:
	R._box(Vector3(cx, (y + height) * 0.5, cv), Vector3(0.5, height, 0.5), R.C_POLE)
	R._box(Vector3(cx, y + height + 2.2, cv), Vector3(0.5, 4.4, 7.0), C_CANOPY)
	for sx: float in [-0.26, 0.26]:
		R._quad(R._p(cx + sx, y + height + 0.3, cv - 3.4), R._p(cx + sx, y + height + 0.3, cv + 3.4), R._p(cx + sx, y + height + 3.2, cv - 3.4), R._p(cx + sx, y + height + 3.2, cv + 3.4), C_SIGN_AMBER, Vector3(signf(sx), 0.0, 0.0))
		R._quad(R._p(cx + sx, y + height + 3.3, cv - 3.4), R._p(cx + sx, y + height + 3.3, cv + 3.4), R._p(cx + sx, y + height + 4.1, cv - 3.4), R._p(cx + sx, y + height + 4.1, cv + 3.4), C_SIGN_RED, Vector3(signf(sx), 0.0, 0.0))
	R._wall_box(R._p(cx, 0.0, cv - 0.3), R._p(cx, 0.0, cv + 0.3), y, y + 3.0, 0.5)

## A low building along the back of a lot with a long lit window.
static func _shop(x0: float, x1: float, v0: float, v1: float, y: float, h: float, body: Color, roof: Color, window: Color, trim: Color) -> void:
	var cx := (x0 + x1) * 0.5
	var cv := (v0 + v1) * 0.5
	R._box(Vector3(cx, y + h * 0.5, cv), Vector3(x1 - x0, h, absf(v1 - v0)), body)
	R._box(Vector3(cx, y + h + 0.3, cv), Vector3(x1 - x0 + 0.6, 0.6, absf(v1 - v0) + 0.6), roof)
	# the window faces the lot (toward the road, -x)
	var lo := minf(v0, v1) + 1.5
	var hi := maxf(v0, v1) - 1.5
	R._quad(R._p(x0 - 0.02, y + 1.0, lo), R._p(x0 - 0.02, y + 1.0, hi), R._p(x0 - 0.02, y + h - 0.8, lo), R._p(x0 - 0.02, y + h - 0.8, hi), window, Vector3(-1.0, 0.0, 0.0))
	R._quad(R._p(x0 - 0.33, y + h + 0.05, lo), R._p(x0 - 0.33, y + h + 0.05, hi), R._p(x0 - 0.33, y + h + 0.35, lo), R._p(x0 - 0.33, y + h + 0.35, hi), trim, Vector3(-1.0, 0.0, 0.0))
	R._wall_box(R._p(cx, 0.0, v0), R._p(cx, 0.0, v1), y, y + h, x1 - x0)

static func _truck(turn: float) -> void:
	var y := GROUND_Y + R.LIFT
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var len := float(LOT_LENS.truck)
	var v1 := v0 + len * turn
	# the sign, at the lot's road-side corner, over everything
	_pole_sign(LOT_X0 + 4.0, v0 + 8.0 * turn, y, 16.0)
	# two canopies down the middle, the lot's drive lanes either side
	_canopy(LOT_X0 + 19.0, v0 + 32.0 * turn, turn, y, 3, C_CANOPY_LIT)
	_canopy(LOT_X0 + 19.0, v0 + 78.0 * turn, turn, y, 3, C_CANOPY_LIT)
	# the diner and shop along the back, its window on the lot
	_shop(LOT_X1 - 9.0, LOT_X1 - 0.5, v0 + 14.0 * turn, v0 + 44.0 * turn, y, 4.0, C_DINER, C_DINER_ROOF, C_WINDOW, C_SIGN_AMBER)
	# trucks parked along the back past the shop, noses alternating, one
	# with its hazards going; the drive lane between them and the canopies
	for k in 5:
		var tv := v0 + (58.0 + 14.0 * float(k)) * turn
		_truck_rig(LOT_X1 - 4.0 - 1.2 * float(k % 2), tv, -turn if k % 2 == 0 else turn, y, C_TRUCK_CAB[k], k == 1)
	# mast lamps along the road side
	for lv: float in [v0 + 55.0 * turn, v0 + 105.0 * turn]:
		_lamp(Vector2(LOT_X0 + 0.9, lv), GROUND_Y, Vector2(1.0, 0.0), 2.5, LAMP_H)
	_lamp(Vector2(LOT_X1 - 0.9, v1 - 8.0 * turn), GROUND_Y, Vector2(-1.0, 0.0), 2.5, LAMP_H)

# ---------- the drive-in diner ----------

## A disc in the x-v plane's upright: a fan of quads facing +-x.
static func _disc(cx: float, cy: float, cv: float, radius: float, thick: float, col: Color, segs: int = 12) -> void:
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		for sx: float in [-thick * 0.5, thick * 0.5]:
			R._tri(R._p(cx + sx, cy, cv), R._p(cx + sx, cy + radius * sin(a0), cv + radius * cos(a0)), R._p(cx + sx, cy + radius * sin(a1), cv + radius * cos(a1)), col, Vector3(signf(sx), 0.0, 0.0))

static func _diner(turn: float) -> void:
	var y := GROUND_Y + R.LIFT
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var len := float(LOT_LENS.diner)
	var v1 := v0 + len * turn
	# the round sign on its pole at the mouth, lit both sides
	var sv := v0 + 6.0 * turn
	R._box(Vector3(LOT_X0 + 3.0, y + 5.5, sv), Vector3(0.4, 11.0, 0.4), R.C_POLE)
	_disc(LOT_X0 + 3.0, y + 11.0, sv, 3.2, 0.6, C_SIGN_RED)
	_disc(LOT_X0 + 3.0, y + 11.0, sv, 2.4, 0.7, C_SIGN_WHITE)
	R._wall_box(R._p(LOT_X0 + 3.0, 0.0, sv - 0.3), R._p(LOT_X0 + 3.0, 0.0, sv + 0.3), y, y + 3.0, 0.5)
	# the diner along the back with its long window and a trim band
	_shop(LOT_X1 - 10.0, LOT_X1 - 0.5, v0 + 10.0 * turn, v0 + 42.0 * turn, y, 4.2, C_DINER, C_DINER_ROOF, C_WINDOW, C_DINER_TRIM)
	# the canopy row: cars parked nose-in under a long roof, lit white
	_canopy_row(LOT_X1 - 18.0, v0 + 62.0 * turn, turn, y, 6)
	# lamps
	for lv: float in [v0 + 25.0 * turn, v0 + 65.0 * turn]:
		_lamp(Vector2(LOT_X0 + 0.9, lv), GROUND_Y, Vector2(1.0, 0.0), 2.5, LAMP_H * 0.8)
	# a dumpster behind the diner
	R._box(Vector3(LOT_X1 - 2.0, y + 0.7, v0 + 47.0 * turn), Vector3(1.6, 1.4, 2.4), C_CRANE)
	R._wall_box(R._p(LOT_X1 - 2.0, 0.0, v0 + 45.8 * turn), R._p(LOT_X1 - 2.0, 0.0, v0 + 48.2 * turn), y, y + 1.4, 1.6)

## A long low canopy with `n` cars parked under it side by side, noses in.
static func _canopy_row(cx: float, cv: float, turn: float, y: float, n: int) -> void:
	var h := 3.2
	var len := float(n) * 3.2
	var w := 7.0
	for dx: float in [-w * 0.5 + 0.3, w * 0.5 - 0.3]:
		for k in range(0, n + 1, 2):
			var pv := cv + (float(k) - float(n) * 0.5) * 3.2 * turn
			R._box(Vector3(cx + dx, y + h * 0.5, pv), Vector3(0.3, h, 0.3), C_CANOPY)
	R._box(Vector3(cx, y + h + 0.3, cv), Vector3(w, 0.6, len + 0.6), C_DINER_ROOF)
	R._quad(R._p(cx - w * 0.5 + 0.2, y + h - 0.01, cv - len * 0.5 * turn), R._p(cx + w * 0.5 - 0.2, y + h - 0.01, cv - len * 0.5 * turn),
		R._p(cx - w * 0.5 + 0.2, y + h - 0.01, cv + len * 0.5 * turn), R._p(cx + w * 0.5 - 0.2, y + h - 0.01, cv + len * 0.5 * turn), C_SIGN_WHITE, Vector3.DOWN)
	for k in n:
		var pv := cv + (float(k) - float(n) * 0.5 + 0.5) * 3.2 * turn
		_parked_car_x(cx, pv, y, C_CARS[k % C_CARS.size()])
	R._pools.append(Transform3D(Basis.from_scale(Vector3(w * 1.6, 1.0, len * 1.1)), R._p(cx, y + 0.06, cv)))

## A parked car facing +x (nose away from the road), lights on.
static func _parked_car_x(cx: float, cv: float, y: float, paint: Color) -> void:
	R._box(Vector3(cx, y + 0.55, cv), Vector3(4.4, 0.65, 1.85), paint)
	R._box(Vector3(cx - 0.3, y + 1.1, cv), Vector3(2.2, 0.55, 1.6), C_GLASS)
	R._box(Vector3(cx - 0.3, y + 1.38, cv), Vector3(1.9, 0.08, 1.5), paint)
	for dx: float in [-1.4, 1.4]:
		for dv: float in [-0.85, 0.85]:
			R._box(Vector3(cx + dx, y + 0.32, cv + dv), Vector3(0.64, 0.64, 0.24), C_TYRE)
	for dv: float in [-0.6, 0.6]:
		R._quad(R._p(cx + 2.21, y + 0.7, cv + dv - 0.2), R._p(cx + 2.21, y + 0.7, cv + dv + 0.2), R._p(cx + 2.21, y + 0.85, cv + dv - 0.2), R._p(cx + 2.21, y + 0.85, cv + dv + 0.2), C_HEADLIGHT, Vector3(1.0, 0.0, 0.0))
		R._quad(R._p(cx - 2.21, y + 0.7, cv + dv - 0.2), R._p(cx - 2.21, y + 0.7, cv + dv + 0.2), R._p(cx - 2.21, y + 0.85, cv + dv - 0.2), R._p(cx - 2.21, y + 0.85, cv + dv + 0.2), C_TAIL, Vector3(-1.0, 0.0, 0.0))
	R._wall_box(R._p(cx - 2.2, 0.0, cv), R._p(cx + 2.2, 0.0, cv), y, y + 1.4, 1.85)
