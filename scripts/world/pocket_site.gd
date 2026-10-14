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
#   deck   the parking deck (x1b, step 12): two levels. The ground floor
#          under a slab on columns, strip lights by the mouth and dark at
#          the back (the hiding spot); a straight ramp up the far side to
#          the open roof with its lamps, parapet and lit stair tower.
#   laundry the laundromat block (x2b): a block of low houses in the middle
#          of the lot you drive round, the laundromat's white window on the
#          road side, the back lane behind it dark (the hiding spot).
#   salvage the salvage yard (x4a): a chain gate, crushed cars stacked
#          three high, a mobile crane, one floodlight on a mast, puddles,
#          sparks from a welder behind a wall.
#   layby  the lay-by (x8a): a short lit bay with a bus shelter and a cop
#          car parked with its lights off; the dark pocket behind the
#          shelter's wall.
#   street a service street (steps 9 and 11): two arms, one off each of two
#          neighbouring rings, and a two-lane LANE between them that runs
#          behind the highway's buildings (STREET_X out, pavements both
#          sides), so an exit takes you somewhere and brings you back to the
#          highway at the next one. Its look is the entry's `street`:
#            shop   Shop Street (x1a to x2a): downtown backs, a brick wall
#                   with roller doors, fire escapes, bins, a corner bar's
#                   amber window, one lamp flickering, parked cars, and The
#                   Shop's door half open with the light on, halfway along.
#            diesel Diesel Row (x4b to x5b): dead straight between
#                   warehouses, loading doors, sodium wall lights, bollards;
#                   a painted start line with a light tree and a finish line:
#                   the drag strip.
#            lanes  the container lanes (x7b to x8b): the lane winds left
#                   and right between walls of stacked containers, under
#                   three gantry cranes whose legs stand at the kerb and
#                   whose floodlights light the lane.
#          The far ring's entry is kind "street_end": no node, it only holds
#          that ring's spur, bound and gantry word (RoadMap.street_main).
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
const LOT_LENS := {"pier": 100.0, "truck": 130.0, "diner": 80.0, "deck": 70.0, "laundry": 90.0, "salvage": 100.0, "layby": 40.0}
## The parking deck: the roof's height over the ground floor, the ramp's
## lane (x out from the centre line) and its run along the lot.
const DECK_H := 3.4
const DECK_RAMP_X := Vector2(LOT_X1 - 9.0, LOT_X1 - 1.0)
const DECK_RAMP_V := Vector2(4.0, 64.0)
## The out-of-bounds wall stands this far out along the pocket, and the
## pocket's footprint along the road (for place_of and the builder).
const BOUND := 130.0
## A service street: the lane's centre line out from the road (where the
## arms end), its half width, the pavements', where the lane starts from
## each ring's centre, the chunks cleared for the arm (STREET_CLEAR_V from
## the centre), the chunk bounds along the lane (RoadFrame.BESIDE: the
## lane keeps inside what unroll() can read), and the walls' heights.
const STREET_X := ARM_START + ARC_R
const STREET_HALF := ARM_HALF
const WALK_W := 2.0
const STREET_V0 := ARC_R + ARM_STRAIGHT
const STREET_CLEAR_V := 150.0
const STREET_BOUND := 100.0
const KERB_UP := 0.12
const LANE_ROW := 5.0
## The container lanes' line: (fraction of the lane's length, x out).
const LANES_LINE := [Vector2(0.0, 80.0), Vector2(0.12, 80.0), Vector2(0.22, 91.0), Vector2(0.34, 69.0), Vector2(0.46, 91.0),
	Vector2(0.58, 69.0), Vector2(0.70, 91.0), Vector2(0.82, 80.0), Vector2(1.0, 80.0)]
const REACH_V := 240.0          # the pier's; see reach_v()
## Shown while the player is within this of the ring, metres along the road.
const SHOW_WITHIN := 600.0
const POOL_CAPACITY := 20
const STREET_POOL_CAPACITY := 72
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
const C_CONCRETE := Color(0.36, 0.36, 0.35, 0.0)
const C_STRIP := Color(0.85, 0.9, 1.0, 0.3)       # a ceiling strip light
const C_STAIR_WINDOW := Color(0.6, 0.8, 1.0, 0.35)
const C_HOUSE_WALL := Color(0.45, 0.4, 0.36, 0.0)
const C_HOUSE_ROOF := Color(0.22, 0.2, 0.19, 0.0)
const C_LAUNDRY := Color(1.0, 1.0, 0.95, 0.42)
const C_MACHINE := Color(0.75, 0.78, 0.8, 0.2)
const C_WRECK_PAINTS: Array[Color] = [Color(0.4, 0.1, 0.08, 0.0), Color(0.3, 0.3, 0.32, 0.0), Color(0.1, 0.15, 0.3, 0.0), Color(0.5, 0.45, 0.25, 0.0), Color(0.2, 0.3, 0.2, 0.0)]
const C_RUST := Color(0.35, 0.18, 0.1, 0.0)
const C_PUDDLE := Color(0.03, 0.04, 0.06, 0.0)
const C_SPARK := Color(0.7, 0.85, 1.0, 0.6)        # in the shader's blink band
const C_GATE := Color(0.5, 0.5, 0.5, 0.0)
const C_SHELTER := Color(0.25, 0.3, 0.35, 0.0)
const C_SHELTER_GLASS := Color(0.5, 0.6, 0.7, 0.12)
const C_COP := Color(0.92, 0.92, 0.9, 0.0)
const C_COP_DOOR := Color(0.08, 0.1, 0.25, 0.0)
const C_LIGHTBAR := Color(0.2, 0.2, 0.25, 0.0)
const C_PAVE := Color(0.3, 0.3, 0.3, 0.0)
const C_LANE := Color(0.12, 0.12, 0.125, 0.0)
const C_BRICK := Color(0.36, 0.22, 0.17, 0.0)
const C_DOOR := Color(0.3, 0.34, 0.38, 0.0)
const C_DOOR_LIT := Color(1.0, 0.75, 0.4, 0.4)
const C_STRIPE := Color(0.9, 0.75, 0.1, 0.25)
const C_FACADES: Array[Color] = [Color(0.32, 0.26, 0.22, 0.0), Color(0.26, 0.26, 0.27, 0.0), Color(0.3, 0.2, 0.16, 0.0), Color(0.22, 0.24, 0.26, 0.0), Color(0.34, 0.3, 0.24, 0.0)]
const C_WINDOW_DARK := Color(0.08, 0.09, 0.11, 0.0)
const C_BAR := Color(1.0, 0.55, 0.15, 0.45)
const C_FLICKER := Color(1.0, 0.8, 0.55, 0.6)   # in the shader's blink band
const C_WAREHOUSE := Color(0.4, 0.42, 0.42, 0.0)
const C_WALL_LAMP := Color(1.0, 0.65, 0.25, 0.45)
const C_TREE_AMBER := Color(1.0, 0.65, 0.1, 0.5)
const C_TREE_GREEN := Color(0.2, 1.0, 0.3, 0.5)
const C_TREE_RED := Color(1.0, 0.1, 0.08, 0.5)
const C_CONTAINERS: Array[Color] = [Color(0.5, 0.14, 0.1, 0.0), Color(0.1, 0.2, 0.45, 0.0), Color(0.15, 0.35, 0.2, 0.0), Color(0.45, 0.45, 0.42, 0.0), Color(0.6, 0.5, 0.12, 0.0), Color(0.35, 0.2, 0.12, 0.0)]
const C_FLOOD := Color(0.9, 0.95, 1.0, 0.5)
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
	if RoadMap.is_street(pk):
		# to the middle of the street, where the next ring's reach takes over
		return RoadMap.pocket_span(pk) * 0.5 + 5.0
	return ARC_R + ARM_STRAIGHT + lot_len(pk) + 18.0

## How far from the ring's centre the chunks are cleared for the pocket and
## the out-of-bounds wall stands out at BOUND: the whole pocket, or a
## street's arm (its lane runs behind the buildings from there).
static func clear_v(pk: Dictionary) -> float:
	return STREET_CLEAR_V if RoadMap.is_street(pk) else reach_v(pk)

## Which light the pocket's lamps throw on the ground (RoadChunkBuilder's
## pool materials).
static func pool_light(pk: Dictionary) -> String:
	if String(pk.kind) in ["truck", "laundry"] or String(pk.get("street", "")) in ["shop", "diesel"]:
		return "sodium"
	return "white"

## How many light pools the pocket's node can show.
static func pool_capacity(pk: Dictionary) -> int:
	return STREET_POOL_CAPACITY if RoadMap.is_street(pk) else POOL_CAPACITY

## A street's lane centre, x out from the road, `va` metres from its first
## ring's centre: STREET_X, or the container lanes' winding line.
static func lane_x(pk: Dictionary, va: float) -> float:
	var main := RoadMap.street_main(pk)
	if String(main.get("street", "")) != "lanes":
		return STREET_X
	var span := RoadMap.pocket_span(main)
	var t := clampf((va - STREET_V0) / (span - 2.0 * STREET_V0), 0.0, 1.0)
	for i in LANES_LINE.size() - 1:
		var a: Vector2 = LANES_LINE[i]
		var b: Vector2 = LANES_LINE[i + 1]
		if t <= b.x:
			var u := clampf((t - a.x) / (b.x - a.x), 0.0, 1.0)
			return lerpf(a.y, b.y, u * u * (3.0 - 2.0 * u))
	return (LANES_LINE[LANES_LINE.size() - 1] as Vector2).y

## `v` from either entry's ring (signed the way the chunks count) as metres
## from the street's first ring.
static func street_va(pk: Dictionary, v: float) -> float:
	return RoadMap.pocket_span(pk) + v if String(pk.get("kind", "")) == "street_end" else v

## The x range (out on the street's side) a boundary step wall leaves open
## where the lane crosses it, `v` from this entry's ring: the lane and its
## pavements with a little to spare.
static func lane_gap(pk: Dictionary, v: float) -> Vector2:
	var lx := lane_x(pk, street_va(pk, v))
	return Vector2(lx - STREET_HALF - WALK_W - 0.5, lx + STREET_HALF + WALK_W + 0.5)

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
	if RoadMap.is_street(pk):
		var main := RoadMap.street_main(pk)
		var span := RoadMap.pocket_span(main)
		var va := street_va(pk, v)
		if va <= STREET_V0 + 5.0 and _arm_near(x, va, slack):
			return true
		if va >= span - STREET_V0 - 5.0 and _arm_near(x, span - va, slack):
			return true
		return va >= STREET_V0 - slack and va <= span - STREET_V0 + slack \
			and absf(x - lane_x(main, va)) <= STREET_HALF + WALK_W + slack
	var turn := float(pk.turn)
	var vv := v * turn
	if x >= LOT_X0 - slack and x <= LOT_X1 + slack and vv >= ARC_R + ARM_STRAIGHT - slack and vv <= ARC_R + ARM_STRAIGHT + lot_len(pk) + slack:
		return true
	return _arm_near(x, vv, slack)

## Whether (x, vv) is within `slack` of the arm's deck (the +1 layout, vv
## the arm's way).
static func _arm_near(x: float, vv: float, slack: float) -> bool:
	var best := INF
	var s := 0.0
	var run := arm_len()
	while s <= run + 0.01:
		var a := arm_at(s, 1.0)
		var d := (a.p as Vector2).distance_to(Vector2(x, vv)) - arm_half(s) - slack
		best = minf(best, d)
		s += 2.0
	return best <= 0.0

## Height of the deck nearest `y` under (x, v): the parking deck has two
## levels and a ramp between them; every other pocket is deck_y().
static func deck_y_near(pk: Dictionary, x: float, v: float, y: float) -> float:
	if String(pk.kind) != "deck":
		return deck_y(pk, x, v)
	var vv := v * float(pk.turn)
	var v0 := ARC_R + ARM_STRAIGHT
	var ground := GROUND_Y + R.LIFT
	if x >= LOT_X0 and x <= LOT_X1 and vv >= v0 - 0.5 and vv <= v0 + lot_len(pk):
		if x >= DECK_RAMP_X.x - 0.5 and x <= DECK_RAMP_X.y + 0.5:
			if vv >= v0 + DECK_RAMP_V.y:
				return ground + DECK_H   # the landing at the top
			if vv >= v0 + DECK_RAMP_V.x:
				return ground + DECK_H * (vv - v0 - DECK_RAMP_V.x) / (DECK_RAMP_V.y - DECK_RAMP_V.x)
			return ground
		# the floor or the roof, whichever the car is nearer
		return ground + DECK_H if y - ground > DECK_H * 0.5 else ground
	return deck_y(pk, x, v)

## Height of the pocket's deck under (x, v signed), or -INF off it.
static func deck_y(pk: Dictionary, x: float, v: float) -> float:
	if RoadMap.is_street(pk):
		var main := RoadMap.street_main(pk)
		var span := RoadMap.pocket_span(main)
		var va := street_va(pk, v)
		if va <= STREET_V0 + 5.0:
			var ya := _arm_deck_y(main, x, va)
			if not is_inf(ya):
				return ya
		if va >= span - STREET_V0 - 5.0:
			var yb := _arm_deck_y(main, x, span - va)
			if not is_inf(yb):
				return yb
		if va >= STREET_V0 - 0.5 and va <= span - STREET_V0 + 0.5 and absf(x - lane_x(main, va)) <= STREET_HALF + WALK_W + 0.6:
			return GROUND_Y + R.LIFT
		return -INF
	var turn := float(pk.turn)
	var vv := v * turn
	if x >= LOT_X0 and x <= LOT_X1 and vv >= ARC_R + ARM_STRAIGHT - 0.5 and vv <= ARC_R + ARM_STRAIGHT + lot_len(pk):
		return floor_y(pk) + R.LIFT
	return _arm_deck_y(pk, x, vv)

## Height of the arm's deck under (x, vv the arm's way), or -INF off it.
static func _arm_deck_y(pk: Dictionary, x: float, vv: float) -> float:
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
	mm.instance_count = pool_capacity(pocket)
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
		var d := fposmod(RingSite.focus_s - float(RoadMap.rings()[ring].s) + lap * 0.5, lap) - lap * 0.5
		# a street runs on to the next ring: its distance is to the whole stretch
		var span := RoadMap.pocket_span(pocket)
		on = (minf(absf(d), absf(d - span)) if d < 0.0 or d > span else 0.0) < SHOW_WITHIN
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
	if String(pk.kind) == "street_end":
		# the street's first entry builds the whole street, this arm included
		return _finish(pk, R.end_flat())
	if String(pk.kind) == "street":
		_arm(pk, 1.0)
		R.flat_v_off = RoadMap.pocket_span(pk)
		_arm(pk, -1.0)
		R.flat_v_off = 0.0
		_street(pk)
		return _finish(pk, R.end_flat())
	_arm(pk, turn)
	_lot(pk, turn)
	match String(pk.kind):
		"pier":
			_pier(turn)
		"truck":
			_truck(turn)
		"diner":
			_diner(turn)
		"deck":
			_parking_deck(turn)
		"laundry":
			_laundry(turn)
		"salvage":
			_salvage(turn)
		"layby":
			_layby(turn)
	return _finish(pk, R.end_flat())

## What was laid out, mirrored for side -1, as the node takes it.
static func _finish(pk: Dictionary, made: Dictionary) -> Dictionary:
	R.wall_colour = R.C_WALL
	if int(pk.side) < 0:
		made = _mirror(made)
	var mesh := ArrayMesh.new()
	if not (made.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
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
static func _lamp(at: Vector2, y: float, toward: Vector2, reach: float, height: float, head: Color = C_LAMP_WHITE) -> void:
	var top := y + height
	R._box(Vector3(at.x, (top + R.SKIRT) * 0.5 - R.SKIRT * 0.5, at.y), Vector3(0.18, top + R.SKIRT, 0.18), R.C_POLE)
	var hx := at.x + toward.x * reach
	var hv := at.y + toward.y * reach
	R._box(Vector3((at.x + hx) * 0.5, top, (at.y + hv) * 0.5), Vector3(absf(hx - at.x) + 0.12, 0.1, absf(hv - at.y) + 0.12), R.C_POLE)
	R._box(Vector3(hx, top - 0.1, hv), Vector3(0.5, 0.14, 0.7), head)
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

# ---------- the parking deck ----------

static func _parking_deck(turn: float) -> void:
	var y := GROUND_Y + R.LIFT
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var len := float(LOT_LENS.deck)
	var v1 := v0 + len * turn
	var top := y + DECK_H
	var rx0: float = DECK_RAMP_X.x
	var rx1: float = DECK_RAMP_X.y
	var rv0 := v0 + DECK_RAMP_V.x * turn
	var rv1 := v0 + DECK_RAMP_V.y * turn
	# the roof slab over everything but the ramp's slot, drivable, with a
	# soffit underneath
	var roof_x1 := rx0 - 0.5
	var strips := 7
	for i in strips:
		var va := lerpf(v0, v1, float(i) / float(strips))
		var vb := lerpf(v0, v1, float(i + 1) / float(strips))
		R._deck_quad(R._p(LOT_X0, top, va), R._p(roof_x1, top, va), R._p(LOT_X0, top, vb), R._p(roof_x1, top, vb))
		R._quad(R._p(LOT_X0, top - 0.5, va), R._p(roof_x1, top - 0.5, va), R._p(LOT_X0, top - 0.5, vb), R._p(roof_x1, top - 0.5, vb), C_CONCRETE, Vector3.DOWN)
	# the landing at the top of the ramp, over the slot's far end
	R._deck_quad(R._p(rx0 - 0.6, top, rv1), R._p(rx1, top, rv1), R._p(rx0 - 0.6, top, v1), R._p(rx1, top, v1))
	# the slab's edges
	for e: Array in [[LOT_X0, v0, LOT_X0, v1], [roof_x1, v0, roof_x1, rv1], [rx1, rv1, rx1, v1], [LOT_X0, v1, rx1, v1], [LOT_X0, v0, roof_x1, v0]]:
		R._quad(R._p(e[0], top, e[1]), R._p(e[2], top, e[3]), R._p(e[0], top - 0.5, e[1]), R._p(e[2], top - 0.5, e[3]), C_CONCRETE, Vector3(signf(e[0] + e[2] - LOT_X0 - LOT_X1), 0.0, 0.0))
	# the ramp up the far side, two lanes, kerbs along it
	var n := 15
	for i in n:
		var va := lerpf(rv0, rv1, float(i) / float(n))
		var vb := lerpf(rv0, rv1, float(i + 1) / float(n))
		var ya := y + DECK_H * float(i) / float(n)
		var yb := y + DECK_H * float(i + 1) / float(n)
		R._deck_quad(R._p(rx0, ya, va), R._p(rx1, ya, va), R._p(rx0, yb, vb), R._p(rx1, yb, vb))
		R._quad(R._p(rx0, ya - 0.4, va), R._p(rx1, ya - 0.4, va), R._p(rx0, yb - 0.4, vb), R._p(rx1, yb - 0.4, vb), C_CONCRETE, Vector3.DOWN)
	var full := PackedFloat32Array([EDGE_H, EDGE_H])
	# the inner kerb starts 10 m up the ramp, so the turn in off the mouth is
	# not a squeeze against it
	var ramp_in: Array[Vector3] = [Vector3(rx0, rv0 + 10.0 * turn, y + DECK_H * 10.0 / DECK_RAMP_V.y), Vector3(rx0, rv1, top)]
	var ramp_in_out: Array[Vector2] = [Vector2(-1.0, 0.0), Vector2(-1.0, 0.0)]
	R._edge(ramp_in, ramp_in_out, full, PackedFloat32Array([y - 0.4, top - 0.5]))
	var ramp_out: Array[Vector3] = [Vector3(rx1, rv0, y), Vector3(rx1, rv1, top)]
	var ramp_out_out: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(1.0, 0.0)]
	R._edge(ramp_out, ramp_out_out, full, PackedFloat32Array([y - 0.4, top - 0.5]))
	# the parapet round the roof, and along the slot
	for e: Array in [[LOT_X0, v0, LOT_X0, v1, Vector2(-1.0, 0.0)], [LOT_X0, v1, rx1, v1, Vector2(0.0, turn)], [rx1, v1, rx1, rv1, Vector2(1.0, 0.0)],
			[roof_x1, rv1 - 0.5 * turn, roof_x1, v0, Vector2(1.0, 0.0)], [roof_x1, v0, LOT_X0, v0, Vector2(0.0, -turn)]]:
		var pts: Array[Vector3] = [Vector3(e[0], e[1], top), Vector3(e[2], e[3], top)]
		var outs: Array[Vector2] = [e[4], e[4]]
		# bottoms are absolute heights: the wall stops just under the slab,
		# not at the ground, or it would close the lot's mouth
		R._edge(pts, outs, full, PackedFloat32Array([top - 0.5, top - 0.5]))
	# columns on a grid under the slab (none in the drive lanes by the mouth)
	for cx: float in [LOT_X0 + 1.0, LOT_X0 + 13.0, LOT_X0 + 23.0]:
		var k := 0
		while float(k) * 9.0 < len - 2.0:
			var cv := v0 + (3.0 + float(k) * 9.0) * turn
			if not (cx > LOT_X0 + 10.0 and cx < LOT_X0 + 26.0 and float(k) * 9.0 < 14.0):
				R._box(Vector3(cx, y + DECK_H * 0.5, cv), Vector3(0.6, DECK_H, 0.6), C_CONCRETE)
				R._wall_box(R._p(cx, 0.0, cv - 0.3), R._p(cx, 0.0, cv + 0.3), y, top, 0.6)
			k += 1
	# strip lights on the ceiling by the mouth; the back half stays dark
	for k in 4:
		var sv := v0 + (6.0 + 8.0 * float(k)) * turn
		for sx: float in [LOT_X0 + 7.0, LOT_X0 + 19.0]:
			R._quad(R._p(sx - 0.6, top - 0.52, sv - 0.08), R._p(sx + 0.6, top - 0.52, sv - 0.08), R._p(sx - 0.6, top - 0.52, sv + 0.08), R._p(sx + 0.6, top - 0.52, sv + 0.08), C_STRIP, Vector3.DOWN)
			R._pools.append(Transform3D(Basis.from_scale(Vector3(5.0, 1.0, 7.0)), R._p(sx, y + 0.06, sv)))
	# the stair tower at the road-side far corner, over the roof, lit
	var tx := LOT_X0 + 3.0
	var tv := v1 - 4.0 * turn
	R._box(Vector3(tx, y + 4.8, tv), Vector3(5.0, 9.6, 6.0), C_CONCRETE)
	R._quad(R._p(tx - 2.51, top + 0.8, tv - 1.2), R._p(tx - 2.51, top + 0.8, tv + 1.2), R._p(tx - 2.51, top + 5.2, tv - 1.2), R._p(tx - 2.51, top + 5.2, tv + 1.2), C_STAIR_WINDOW, Vector3(-1.0, 0.0, 0.0))
	R._quad(R._p(tx - 1.2, top + 0.8, tv - 3.01 * turn), R._p(tx + 1.2, top + 0.8, tv - 3.01 * turn), R._p(tx - 1.2, top + 5.2, tv - 3.01 * turn), R._p(tx + 1.2, top + 5.2, tv - 3.01 * turn), C_STAIR_WINDOW, Vector3(0.0, 0.0, turn))
	R._wall_box(R._p(tx, 0.0, tv - 3.0 * turn), R._p(tx, 0.0, tv + 3.0 * turn), y, top + 6.0, 5.0)
	# roof lamps
	for lv: float in [v0 + 18.0 * turn, v0 + 50.0 * turn]:
		_lamp(Vector2(LOT_X0 + 14.0, lv), top - R.LIFT, Vector2(0.0, turn), 0.0, 6.0)
	# a few cars parked on the ground floor and the roof
	_parked_car_x(LOT_X0 + 7.0, v0 + 40.0 * turn, y, C_CARS[1])
	_parked_car_x(LOT_X0 + 7.0, v0 + 60.0 * turn, y, C_CARS[3])
	_parked_car_x(LOT_X0 + 14.0, v0 + 30.0 * turn, top, C_CARS[0])

# ---------- the laundromat block ----------

static func _laundry(turn: float) -> void:
	var y := GROUND_Y + R.LIFT
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var len := float(LOT_LENS.laundry)
	var v1 := v0 + len * turn
	# the block in the middle: three low houses and the laundromat, between
	# the road-side street and the back lane
	var bx0 := LOT_X0 + 11.0
	var bx1 := LOT_X1 - 11.0
	var hv := v0 + 18.0 * turn
	var hlen := (len - 26.0) / 4.0
	for k in 4:
		var va := hv + hlen * float(k) * turn
		var vb := va + (hlen - 1.5) * turn
		var h := 5.5 if k != 1 else 4.2
		var body := C_HOUSE_WALL if k != 1 else C_DINER
		var cx := (bx0 + bx1) * 0.5
		var cv := (va + vb) * 0.5
		R._box(Vector3(cx, y + h * 0.5, cv), Vector3(bx1 - bx0, h, absf(vb - va)), body)
		R._box(Vector3(cx, y + h + 0.25, cv), Vector3(bx1 - bx0 + 0.8, 0.5, absf(vb - va) + 0.8), C_HOUSE_ROOF)
		R._wall_box(R._p(cx, 0.0, va), R._p(cx, 0.0, vb), y, y + h, bx1 - bx0)
		if k == 1:
			# the laundromat: a white window the whole front, machines in a row
			var lo := minf(va, vb) + 1.0
			var hi := maxf(va, vb) - 1.0
			R._quad(R._p(bx0 - 0.02, y + 0.6, lo), R._p(bx0 - 0.02, y + 0.6, hi), R._p(bx0 - 0.02, y + h - 0.6, lo), R._p(bx0 - 0.02, y + h - 0.6, hi), C_LAUNDRY, Vector3(-1.0, 0.0, 0.0))
			var mv := lo + 1.5
			while mv < hi - 1.5:
				R._quad(R._p(bx0 - 0.04, y + 1.0, mv - 0.5), R._p(bx0 - 0.04, y + 1.0, mv + 0.5), R._p(bx0 - 0.04, y + 2.0, mv - 0.5), R._p(bx0 - 0.04, y + 2.0, mv + 0.5), C_MACHINE, Vector3(-1.0, 0.0, 0.0))
				mv += 1.8
			R._pools.append(Transform3D(Basis.from_scale(Vector3(7.0, 1.0, hi - lo)), R._p(bx0 - 2.5, y + 0.06, (lo + hi) * 0.5)))
		else:
			# a lit window or two on the houses' fronts
			var wv := (va + vb) * 0.5
			R._quad(R._p(bx0 - 0.02, y + 1.4, wv - 0.7), R._p(bx0 - 0.02, y + 1.4, wv + 0.7), R._p(bx0 - 0.02, y + 2.6, wv - 0.7), R._p(bx0 - 0.02, y + 2.6, wv + 0.7), C_WINDOW, Vector3(-1.0, 0.0, 0.0))
	# a wall along the back lane's far side (the lot's edge is the kit's), bins
	for k in 3:
		var bv := v0 + (30.0 + 20.0 * float(k)) * turn
		R._box(Vector3(LOT_X1 - 1.4, y + 0.6, bv), Vector3(1.2, 1.2, 1.0), C_CRANE)
		R._wall_box(R._p(LOT_X1 - 1.4, 0.0, bv - 0.5), R._p(LOT_X1 - 1.4, 0.0, bv + 0.5), y, y + 1.2, 1.2)
	# one street lamp on the road side; the back lane has none
	_lamp(Vector2(LOT_X0 + 0.9, v0 + 40.0 * turn), GROUND_Y, Vector2(1.0, 0.0), 2.0, 7.0)
	_parked_car_x(LOT_X0 + 3.2, v0 + 70.0 * turn, y, C_CARS[2])

# ---------- the salvage yard ----------

static func _salvage(turn: float) -> void:
	var y := GROUND_Y + R.LIFT
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var len := float(LOT_LENS.salvage)
	var v1 := v0 + len * turn
	var mouth := ARM_START + ARC_R
	# the chain gate at the mouth: two posts and the gate panels swung open
	for gx: float in [mouth - ARM_HALF - 0.6, mouth + ARM_HALF + 0.6]:
		R._box(Vector3(gx, y + 1.5, v0 + 1.0 * turn), Vector3(0.3, 3.0, 0.3), C_GATE)
		R._wall_box(R._p(gx, 0.0, v0 + 0.85 * turn), R._p(gx, 0.0, v0 + 1.15 * turn), y, y + 3.0, 0.3)
		var dirx := -1.0 if gx < mouth else 1.0
		R._quad(R._p(gx + dirx * 0.2, y + 0.3, v0 + 1.0 * turn), R._p(gx + dirx * 4.0, y + 0.3, v0 + 4.0 * turn), R._p(gx + dirx * 0.2, y + 2.6, v0 + 1.0 * turn), R._p(gx + dirx * 4.0, y + 2.6, v0 + 4.0 * turn), C_GATE, Vector3(0.0, 0.0, -turn))
	# crushed cars stacked three high along the back and in a row down the middle
	var stack_x := [LOT_X1 - 4.0, LOT_X1 - 4.0, LOT_X1 - 4.0, LOT_X1 - 4.0, LOT_X1 - 4.0, LOT_X1 - 15.0, LOT_X1 - 15.0, LOT_X1 - 15.0]
	var stack_v := [10.0, 22.0, 34.0, 60.0, 72.0, 30.0, 45.0, 60.0]
	for i in stack_x.size():
		var sx: float = stack_x[i]
		var sv: float = v0 + float(stack_v[i]) * turn
		var high := 3 if i % 3 != 2 else 2
		for k in high:
			R._box(Vector3(sx + 0.2 * float(k % 2), y + 0.45 + 0.9 * float(k), sv + 0.3 * float(k % 2)), Vector3(4.3, 0.85, 1.9), C_WRECK_PAINTS[(i + k) % C_WRECK_PAINTS.size()])
		R._wall_box(R._p(sx - 2.2, 0.0, sv), R._p(sx + 2.2, 0.0, sv), y, y + 0.9 * float(high), 2.2)
	# the mobile crane: a base on tracks, a cab, a boom up over the stacks
	var kx := LOT_X1 - 24.0
	var kv := v0 + 85.0 * turn
	R._box(Vector3(kx, y + 0.6, kv), Vector3(4.0, 1.2, 5.0), C_TYRE)
	R._box(Vector3(kx, y + 2.2, kv), Vector3(3.0, 2.0, 3.6), C_RUST)
	R._wall_box(R._p(kx, 0.0, kv - 2.5), R._p(kx, 0.0, kv + 2.5), y, y + 3.2, 4.0)
	RingSite._bar(Vector3(kx + 0.5, y + 3.0, kv), Vector3(kx + 14.0, y + 15.0, kv - 2.0 * turn), 0.5, C_RUST)
	R._box(Vector3(kx + 14.0, y + 11.5, kv - 2.0 * turn), Vector3(0.08, 7.0, 0.08), R.C_POLE)   # the cable
	R._box(Vector3(kx + 14.0, y + 7.8, kv - 2.0 * turn), Vector3(1.6, 0.4, 1.6), C_RUST)         # the magnet
	# one floodlight on a mast by the gate, its light across the yard
	var mx := LOT_X0 + 6.0
	var mv := v0 + 8.0 * turn
	R._box(Vector3(mx, y + 8.0, mv), Vector3(0.4, 16.0, 0.4), R.C_POLE)
	R._wall_box(R._p(mx, 0.0, mv - 0.25), R._p(mx, 0.0, mv + 0.25), y, y + 3.0, 0.4)
	for k in 3:
		R._box(Vector3(mx + 0.5, y + 15.2 + 0.7 * float(k), mv + (float(k) - 1.0) * 0.9 * turn), Vector3(0.7, 0.5, 0.8), C_FLOOD)
	R._pools.append(Transform3D(Basis.from_scale(Vector3(30.0, 1.0, 44.0)), R._p(mx + 14.0, y + 0.06, mv + 22.0 * turn)))
	# puddles on the yard's floor
	for pd: Array in [[LOT_X0 + 12.0, 30.0, 5.0, 3.0], [LOT_X0 + 20.0, 58.0, 7.0, 4.0], [LOT_X1 - 20.0, 15.0, 4.0, 6.0]]:
		var px: float = pd[0]
		var pv: float = v0 + float(pd[1]) * turn
		R._quad(R._p(px - pd[2] * 0.5, y + 0.01, pv - pd[3] * 0.5), R._p(px + pd[2] * 0.5, y + 0.01, pv - pd[3] * 0.5), R._p(px - pd[2] * 0.5, y + 0.01, pv + pd[3] * 0.5), R._p(px + pd[2] * 0.5, y + 0.01, pv + pd[3] * 0.5), C_PUDDLE, Vector3.UP)
	# the welder's wall at the far end, sparks blinking behind it
	var wx := LOT_X0 + 10.0
	var wv := v1 - 6.0 * turn
	R._box(Vector3(wx, y + 1.3, wv), Vector3(10.0, 2.6, 0.4), C_CONCRETE)
	R._wall_box(R._p(wx - 5.0, 0.0, wv), R._p(wx + 5.0, 0.0, wv), y, y + 2.6, 0.4)
	for k in 5:
		var sx := wx - 2.0 + float(k) * 1.0
		R._quad(R._p(sx, y + 2.7 + 0.3 * float(k % 2), wv + 0.6 * turn), R._p(sx + 0.15, y + 2.7 + 0.3 * float(k % 2), wv + 0.6 * turn),
			R._p(sx, y + 2.85 + 0.3 * float(k % 2), wv + 0.6 * turn), R._p(sx + 0.15, y + 2.85 + 0.3 * float(k % 2), wv + 0.6 * turn), C_SPARK, Vector3(0.0, 0.0, -turn))
	R._pools.append(Transform3D(Basis.from_scale(Vector3(8.0, 1.0, 6.0)), R._p(wx, y + 0.06, wv + 2.5 * turn)))

# ---------- the lay-by ----------

static func _layby(turn: float) -> void:
	var y := GROUND_Y + R.LIFT
	var v0 := (ARC_R + ARM_STRAIGHT) * turn
	var len := float(LOT_LENS.layby)
	var v1 := v0 + len * turn
	# the bus shelter against the back, glass on three sides, lit inside
	var sx := LOT_X1 - 3.0
	var sv := v0 + 20.0 * turn
	R._box(Vector3(sx, y + 2.6, sv), Vector3(2.6, 0.2, 6.0), C_SHELTER)
	R._box(Vector3(sx + 1.1, y + 1.3, sv), Vector3(0.1, 2.6, 6.0), C_SHELTER)
	for ev: float in [sv - 2.95 * turn, sv + 2.95 * turn]:
		R._quad(R._p(sx - 1.2, y + 0.3, ev), R._p(sx + 1.0, y + 0.3, ev), R._p(sx - 1.2, y + 2.5, ev), R._p(sx + 1.0, y + 2.5, ev), C_SHELTER_GLASS, Vector3(0.0, 0.0, signf(ev - sv) * -turn))
	R._quad(R._p(sx - 1.0, y + 2.49, sv - 2.5), R._p(sx + 1.0, y + 2.49, sv - 2.5), R._p(sx - 1.0, y + 2.49, sv + 2.5), R._p(sx + 1.0, y + 2.49, sv + 2.5), C_STRIP, Vector3.DOWN)
	R._box(Vector3(sx + 0.2, y + 0.5, sv), Vector3(0.5, 0.1, 4.0), C_SHELTER)   # the bench
	R._wall_box(R._p(sx, 0.0, sv - 3.0 * turn), R._p(sx, 0.0, sv + 3.0 * turn), y, y + 2.7, 2.6)
	R._pools.append(Transform3D(Basis.from_scale(Vector3(6.0, 1.0, 8.0)), R._p(sx - 2.0, y + 0.06, sv)))
	# the wall behind the shelter, and the dark pocket past it
	R._box(Vector3(LOT_X1 - 1.0, y + 1.4, sv + 5.5 * turn), Vector3(1.0, 2.8, 5.0), C_CONCRETE)
	R._wall_box(R._p(LOT_X1 - 1.0, 0.0, sv + 3.0 * turn), R._p(LOT_X1 - 1.0, 0.0, sv + 8.0 * turn), y, y + 2.8, 1.0)
	# the cop car parked facing the arm, lights off
	var cx := LOT_X1 - 8.0
	var cv := v0 + 9.0 * turn
	R._box(Vector3(cx, y + 0.55, cv), Vector3(1.9, 0.65, 4.8), C_COP)
	R._box(Vector3(cx, y + 0.6, cv), Vector3(1.92, 0.3, 2.2), C_COP_DOOR)
	R._box(Vector3(cx, y + 1.1, cv + 0.2 * turn), Vector3(1.65, 0.55, 2.4), C_GLASS)
	R._box(Vector3(cx, y + 1.42, cv), Vector3(1.2, 0.12, 0.35), C_LIGHTBAR)
	for dx: float in [-0.85, 0.85]:
		for dv: float in [-1.5, 1.5]:
			R._box(Vector3(cx + dx, y + 0.32, cv + dv), Vector3(0.24, 0.64, 0.64), C_TYRE)
	R._wall_box(R._p(cx, 0.0, cv - 2.4), R._p(cx, 0.0, cv + 2.4), y, y + 1.5, 1.9)
	# two lamps light the bay; the pocket behind the wall has none
	_lamp(Vector2(LOT_X0 + 0.9, v0 + 12.0 * turn), GROUND_Y, Vector2(1.0, 0.0), 2.5, 8.0)
	_lamp(Vector2(LOT_X0 + 0.9, v0 + 30.0 * turn), GROUND_Y, Vector2(1.0, 0.0), 2.5, 8.0)

# ---------- service streets (steps 9 and 11) ----------

## The street between the two arms: the lane with its pavements and centre
## line, then what lines it, by the entry's `street`.
static func _street(pk: Dictionary) -> void:
	var span := RoadMap.pocket_span(pk)
	var y := GROUND_Y + R.LIFT
	var v0 := STREET_V0
	var v1 := span - STREET_V0
	var st := String(pk.get("street", "shop"))
	_lane(pk, v0, v1, y, st != "diesel")
	match st:
		"shop":
			_shop_street(pk, v0, v1, y)
		"diesel":
			_diesel_row(pk, v0, v1, y)
		"lanes":
			_container_lanes(pk, v0, v1, y)

## The lane's centre, tangent and left normal (toward the road) `va` along.
static func _lane_at(pk: Dictionary, va: float) -> Dictionary:
	var c := Vector2(lane_x(pk, va), va)
	var t := Vector2(lane_x(pk, va + 0.5) - lane_x(pk, va - 0.5), 1.0).normalized()
	return {"c": c, "t": t, "n": Vector2(-t.y, t.x)}

## A point `off` to the left of the lane's centre (toward the road; negative
## = away from it) `va` along, as (x, v).
static func _lane_off(pk: Dictionary, va: float, off: float) -> Vector2:
	var a := _lane_at(pk, va)
	return (a.c as Vector2) + (a.n as Vector2) * off

## The lane: rows every LANE_ROW m, the dark lane between them and a raised
## pavement WALK_W wide each side with a kerb face, all in the deck's
## collision; a dashed centre line (none on the drag strip).
static func _lane(pk: Dictionary, v0: float, v1: float, y: float, dashes: bool) -> void:
	var n := ceili((v1 - v0) / LANE_ROW)
	var prev: Array = []
	var hw := STREET_HALF + WALK_W
	for i in n + 1:
		var va := minf(v0 + float(i) * LANE_ROW, v1)
		var a := _lane_at(pk, va)
		var c: Vector2 = a.c
		var nn: Vector2 = a.n
		# left pavement edge, left kerb, right kerb, right pavement edge
		var row: Array = [c + nn * hw, c + nn * STREET_HALF, c - nn * STREET_HALF, c - nn * hw]
		if i > 0:
			var p0: Vector2 = prev[1]
			var p1: Vector2 = prev[2]
			var q0: Vector2 = row[1]
			var q1: Vector2 = row[2]
			# the lane
			R._quad(R._p(p0.x, y, p0.y), R._p(p1.x, y, p1.y), R._p(q0.x, y, q0.y), R._p(q1.x, y, q1.y), C_LANE, Vector3.UP)
			R._deck_faces([R._p(p0.x, y, p0.y), R._p(p1.x, y, p1.y), R._p(q0.x, y, q0.y), R._p(p1.x, y, p1.y), R._p(q1.x, y, q1.y), R._p(q0.x, y, q0.y)])
			# the pavements, KERB_UP above it, and the kerb faces
			for side_k: Array in [[0, 1], [3, 2]]:
				var e0: Vector2 = prev[side_k[0]]
				var k0: Vector2 = prev[side_k[1]]
				var e1: Vector2 = row[side_k[0]]
				var k1: Vector2 = row[side_k[1]]
				R._quad(R._p(e0.x, y + KERB_UP, e0.y), R._p(k0.x, y + KERB_UP, k0.y), R._p(e1.x, y + KERB_UP, e1.y), R._p(k1.x, y + KERB_UP, k1.y), C_PAVE, Vector3.UP)
				R._deck_faces([R._p(e0.x, y + KERB_UP, e0.y), R._p(k0.x, y + KERB_UP, k0.y), R._p(e1.x, y + KERB_UP, e1.y),
					R._p(k0.x, y + KERB_UP, k0.y), R._p(k1.x, y + KERB_UP, k1.y), R._p(e1.x, y + KERB_UP, e1.y)])
				var toward := Vector3(signf(c.x - k0.x), 0.0, 0.0)
				R._quad(R._p(k0.x, y, k0.y), R._p(k1.x, y, k1.y), R._p(k0.x, y + KERB_UP, k0.y), R._p(k1.x, y + KERB_UP, k1.y), R.C_KERB, toward)
				R._deck_faces([R._p(k0.x, y, k0.y), R._p(k1.x, y, k1.y), R._p(k0.x, y + KERB_UP, k0.y), R._p(k1.x, y, k1.y), R._p(k1.x, y + KERB_UP, k1.y), R._p(k0.x, y + KERB_UP, k0.y)])
			if dashes and i % 2 == 1:
				var c0: Vector2 = (p0 + p1) * 0.5
				var c1: Vector2 = (q0 + q1) * 0.5
				var along := (c1 - c0).normalized() * 0.6
				var across := Vector2(-along.y, along.x).normalized() * 0.07
				R._quad(R._p(c0.x + along.x - across.x, y + R.PAINT_LIFT, c0.y + along.y - across.y), R._p(c0.x + along.x + across.x, y + R.PAINT_LIFT, c0.y + along.y + across.y),
					R._p(c1.x - along.x - across.x, y + R.PAINT_LIFT, c1.y - along.y - across.y), R._p(c1.x - along.x + across.x, y + R.PAINT_LIFT, c1.y - along.y + across.y), R.C_PAINT, Vector3.UP)
		prev = row

## A wall along the lane's edge, `off` from its centre (positive toward the
## road), from va0 to va1, `h` high, in `col`: drawn as a thin slab and in
## the collision.
static func _street_wall(pk: Dictionary, va0: float, va1: float, off: float, h: float, col: Color, thick: float = 0.4) -> void:
	var step := 10.0
	var va := va0
	while va < va1 - 0.01:
		var vb := minf(va + step, va1)
		var a := _lane_off(pk, va, off)
		var b := _lane_off(pk, vb, off)
		_slab(a, b, GROUND_Y, GROUND_Y + h, thick, col)
		R._wall_box(R._p(a.x, 0.0, a.y), R._p(b.x, 0.0, b.y), GROUND_Y, GROUND_Y + h, thick)
		va = vb

## An upright slab from (x, v) `a` to `b`, `bottom` to `top`, `thick` across
## its length: four faces and a top (the wall's look).
static func _slab(a: Vector2, b: Vector2, bottom: float, top: float, thick: float, col: Color) -> void:
	var along := (b - a).normalized()
	var across := Vector2(-along.y, along.x) * thick * 0.5
	var a0 := a + across
	var a1 := a - across
	var b0 := b + across
	var b1 := b - across
	R._quad(R._p(a0.x, bottom, a0.y), R._p(b0.x, bottom, b0.y), R._p(a0.x, top, a0.y), R._p(b0.x, top, b0.y), col, Vector3(across.x, 0.0, -across.y))
	R._quad(R._p(a1.x, bottom, a1.y), R._p(b1.x, bottom, b1.y), R._p(a1.x, top, a1.y), R._p(b1.x, top, b1.y), col, Vector3(-across.x, 0.0, across.y))
	R._quad(R._p(a0.x, top, a0.y), R._p(b0.x, top, b0.y), R._p(a1.x, top, a1.y), R._p(b1.x, top, b1.y), col, Vector3.UP)
	R._quad(R._p(a0.x, bottom, a0.y), R._p(a1.x, bottom, a1.y), R._p(a0.x, top, a0.y), R._p(a1.x, top, a1.y), col, Vector3(-along.x, 0.0, along.y))
	R._quad(R._p(b0.x, bottom, b0.y), R._p(b1.x, bottom, b1.y), R._p(b0.x, top, b0.y), R._p(b1.x, top, b1.y), col, Vector3(along.x, 0.0, -along.y))

## A flat mark on a wall's face at x (facing `face` = +1 toward +x), from
## v0 to v1, bottom to top.
static func _wall_mark(x: float, face: float, v0: float, v1: float, bottom: float, top: float, col: Color) -> void:
	R._quad(R._p(x, bottom, v0), R._p(x, bottom, v1), R._p(x, top, v0), R._p(x, top, v1), col, Vector3(face, 0.0, 0.0))

## A building box from x0 to x1 (x0 the face on the lane), v0 to v1, `h`
## high, in `body`, with its collision; windows in a grid on the lane face,
## lit at random in `rng`.
static func _facade(rng: RandomNumberGenerator, x0: float, x1: float, v0: float, v1: float, y: float, h: float, body: Color, face: float, lit_share: float) -> void:
	var cx := (x0 + x1) * 0.5
	var cv := (v0 + v1) * 0.5
	R._box(Vector3(cx, y + h * 0.5, cv), Vector3(absf(x1 - x0), h, absf(v1 - v0)), body)
	R._wall_box(R._p(cx, 0.0, v0), R._p(cx, 0.0, v1), y, y + h, absf(x1 - x0))
	var floors := maxi(int(h / 3.0), 1)
	var fx := x0 + face * 0.02
	var wv := minf(v0, v1) + 1.2
	while wv + 1.4 < maxf(v0, v1) - 0.8:
		for f in floors:
			var wb := y + 1.0 + float(f) * 3.0
			if wb + 1.5 > y + h - 0.4:
				break
			var col := C_WINDOW if rng.randf() < lit_share else C_WINDOW_DARK
			_wall_mark(fx, face, wv, wv + 1.4, wb, wb + 1.5, col)
		wv += 2.8

## A fire escape on a facade's lane face at x (face toward `face`), between
## v0 and v1: a platform at each floor with a rail, a stair bar between.
static func _fire_escape(x: float, face: float, v0: float, v1: float, y: float, h: float) -> void:
	var floors := int(h / 3.0)
	var px := x + face * 0.55
	for f in range(1, floors):
		var fy := y + float(f) * 3.0
		R._box(Vector3(px, fy, (v0 + v1) * 0.5), Vector3(1.0, 0.08, absf(v1 - v0)), C_CRANE)
		R._box(Vector3(x + face * 1.02, fy + 0.5, (v0 + v1) * 0.5), Vector3(0.05, 1.0, absf(v1 - v0)), C_CRANE)
		RingSite._bar(Vector3(px, fy, v0), Vector3(px, fy + 3.0 if f < floors - 1 else fy, v1), 0.12, C_CRANE)

## A wheelie bin pair on a pavement at (x, v).
static func _bins(x: float, v: float, y: float) -> void:
	for dv: float in [-0.7, 0.7]:
		R._box(Vector3(x, y + 0.6, v + dv), Vector3(0.9, 1.2, 1.1), C_CRANE)
		R._box(Vector3(x, y + 1.24, v + dv), Vector3(0.95, 0.08, 1.15), C_HOUSE_ROOF)

## A car parked along the lane (nose the way the chunks count) at (cx, cv),
## with its collision.
static func _parked_car_v(cx: float, cv: float, y: float, paint: Color) -> void:
	R._box(Vector3(cx, y + 0.55, cv), Vector3(1.85, 0.65, 4.4), paint)
	R._box(Vector3(cx, y + 1.1, cv - 0.3), Vector3(1.6, 0.55, 2.2), C_GLASS)
	R._box(Vector3(cx, y + 1.38, cv - 0.3), Vector3(1.5, 0.08, 1.9), paint)
	for dx: float in [-0.85, 0.85]:
		for dv: float in [-1.4, 1.4]:
			R._box(Vector3(cx + dx, y + 0.32, cv + dv), Vector3(0.24, 0.64, 0.64), C_TYRE)
	R._wall_box(R._p(cx, 0.0, cv - 2.2), R._p(cx, 0.0, cv + 2.2), y, y + 1.4, 1.85)

## A sodium lamp on a wall at (x, v), `face` toward the lane: a hooded
## lantern and its pool on the pavement and lane.
static func _wall_lamp(x: float, face: float, v: float, y: float, height: float) -> void:
	R._box(Vector3(x + face * 0.3, y + height, v), Vector3(0.6, 0.25, 0.5), R.C_POLE)
	R._box(Vector3(x + face * 0.35, y + height - 0.2, v), Vector3(0.4, 0.14, 0.4), C_WALL_LAMP)
	R._pools.append(Transform3D(Basis.from_scale(Vector3(height * 1.4, 1.0, height * 1.5)), R._p(x + face * (height * 0.5), y + 0.06, v)))

# ---------- Shop Street (x1a to x2a) ----------

## Downtown backs: a brick wall along the road side with roller doors, The
## Shop's door halfway along with its light on, bins, a lamp every so often
## (one flickering), tenement backs with fire escapes across the lane, a
## corner bar's amber window by the first arm, cars parked along the kerb.
static func _shop_street(pk: Dictionary, v0: float, v1: float, y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(pk.id), "shop street"])
	var span := RoadMap.pocket_span(pk)
	var near_x := STREET_X - STREET_HALF - WALK_W   # the wall's lane face
	var far_x := STREET_X + STREET_HALF + WALK_W
	var shop_v := span * 0.5
	# the near wall, in two runs either side of The Shop
	for run: Array in [[v0, shop_v - 6.0], [shop_v + 6.0, v1]]:
		_street_wall(pk, run[0], run[1], STREET_HALF + WALK_W + 0.2, 2.8, C_BRICK)
	# roller doors in the wall every 24 m, bins by every other
	var dv := v0 + 12.0
	var k := 0
	while dv < v1 - 8.0:
		if absf(dv - shop_v) > 12.0:
			_wall_mark(near_x - 0.01, 1.0, dv - 1.75, dv + 1.75, y, y + 2.4, C_DOOR)
			if k % 2 == 0:
				_bins(near_x + 0.7, dv + 3.5, y)
		dv += 24.0
		k += 1
	# The Shop: its back stands out to the pavement, the roller door half
	# open with the light on inside, an amber lamp over it, a pool out front
	var sx0 := near_x - 10.0
	var sx1 := near_x + 0.6
	R._box(Vector3((sx0 + sx1) * 0.5, y + 2.75, shop_v), Vector3(sx1 - sx0, 5.5, 12.0), Color(0.3, 0.12, 0.1, 0.0))
	R._box(Vector3((sx0 + sx1) * 0.5, y + 5.6, shop_v), Vector3(sx1 - sx0 + 0.6, 0.3, 12.6), C_HOUSE_ROOF)
	R._wall_box(R._p((sx0 + sx1) * 0.5, 0.0, shop_v - 6.0), R._p((sx0 + sx1) * 0.5, 0.0, shop_v + 6.0), y, y + 5.5, sx1 - sx0)
	_wall_mark(sx1 + 0.02, 1.0, shop_v - 2.2, shop_v + 2.2, y + 1.7, y + 3.6, C_DOOR)
	_wall_mark(sx1 + 0.03, 1.0, shop_v - 2.2, shop_v + 2.2, y, y + 1.7, C_DOOR_LIT)
	R._box(Vector3(sx1 + 0.3, y + 4.2, shop_v), Vector3(0.6, 0.25, 1.2), C_SIGN_AMBER)
	R._pools.append(Transform3D(Basis.from_scale(Vector3(9.0, 1.0, 9.0)), R._p(sx1 + 3.0, y + 0.06, shop_v)))
	_parked_car_v(far_x - 1.1, shop_v + 9.0, y, C_CARS[1])
	# tenement backs across the lane: a building per 24 m, fire escapes on
	# every other, the corner bar first with its window lit amber
	var bv := v0
	var i := 0
	while bv < v1 - 4.0:
		var len := minf(24.0, v1 - bv)
		var h := 9.0 + 3.0 * float(rng.randi_range(0, 2))
		var body: Color = C_FACADES[rng.randi_range(0, C_FACADES.size() - 1)]
		if len < 10.0:
			_street_wall(pk, bv, v1, -(STREET_HALF + WALK_W + 0.2), 2.4, C_BRICK)
			break
		_facade(rng, far_x, far_x + 12.0, bv + 0.5, bv + len - 0.5, y, h, body, -1.0, 0.3)
		if i == 0:
			# the corner bar: the ground floor's window band and a sign
			_wall_mark(far_x - 0.04, -1.0, bv + 2.0, bv + len - 2.0, y + 0.9, y + 2.4, C_BAR)
			R._box(Vector3(far_x - 0.5, y + 3.4, bv + 4.0), Vector3(0.9, 0.7, 2.4), C_SIGN_RED)
		elif i % 2 == 1:
			_fire_escape(far_x, -1.0, bv + 4.0, bv + 8.0, y, h)
		bv += len
		i += 1
	# lamps on the far pavement, one of them flickering; cars along its kerb
	var lv := v0 + 18.0
	var j := 0
	while lv < v1 - 10.0:
		_lamp(Vector2(far_x - 0.5, lv), GROUND_Y, Vector2(-1.0, 0.0), 2.5, 7.0, C_FLICKER if j == 3 else C_LAMP_WHITE)
		lv += 36.0
		j += 1
	var cv := v0 + 30.0
	var m := 0
	while cv < v1 - 20.0:
		if absf(cv - shop_v) > 14.0:
			_parked_car_v(far_x - 1.1, cv, y, C_CARS[m % C_CARS.size()])
		cv += 44.0 + 13.0 * float(m % 3)
		m += 1

# ---------- Diesel Row (x4b to x5b) ----------

## Warehouses both sides of a dead straight lane: 6 m backs on the road
## side with loading doors and sodium wall lights, bigger sheds across the
## lane with a yard gap or two, bollards along both kerbs; a start line
## with a light tree and a finish line 500 m on: the drag strip.
static func _diesel_row(pk: Dictionary, v0: float, v1: float, y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(pk.id), "diesel row"])
	var near_x := STREET_X - STREET_HALF - WALK_W
	var far_x := STREET_X + STREET_HALF + WALK_W
	_street_wall(pk, v0, v1, STREET_HALF + WALK_W + 0.3, 6.0, C_WAREHOUSE, 0.6)
	# loading doors every 20 m with a yellow stripe at the foot, a wall light
	# over every other
	var dv := v0 + 10.0
	var k := 0
	while dv < v1 - 6.0:
		_wall_mark(near_x - 0.01, 1.0, dv - 2.0, dv + 2.0, y + 0.3, y + 4.2, C_DOOR)
		_wall_mark(near_x - 0.02, 1.0, dv - 2.0, dv + 2.0, y, y + 0.3, C_STRIPE)
		if k % 2 == 0:
			_wall_lamp(near_x, 1.0, dv, y, 4.8)
		dv += 20.0
		k += 1
	# sheds across the lane: 30 m each, 7 to 9 m high, every fourth bay a
	# fenced yard instead
	var bv := v0
	var i := 0
	while bv < v1 - 4.0:
		var len := minf(30.0, v1 - bv)
		if i % 4 == 3 or len < 12.0:
			_street_wall(pk, bv, bv + len, -(STREET_HALF + WALK_W + 0.2), 1.6, C_GATE, 0.1)
		else:
			var h := 7.0 + float(rng.randi_range(0, 2))
			R._box(Vector3(far_x + 7.0, y + h * 0.5, bv + len * 0.5), Vector3(14.0, h, len - 1.0), C_WAREHOUSE)
			R._box(Vector3(far_x + 7.0, y + h + 0.2, bv + len * 0.5), Vector3(14.4, 0.4, len - 0.6), C_HOUSE_ROOF)
			R._wall_box(R._p(far_x + 7.0, 0.0, bv + 0.5), R._p(far_x + 7.0, 0.0, bv + len - 0.5), y, y + h, 14.0)
			_wall_mark(far_x - 0.01, -1.0, bv + len * 0.5 - 2.5, bv + len * 0.5 + 2.5, y + 0.3, y + 4.5, C_DOOR)
			_wall_mark(far_x - 0.02, -1.0, bv + len * 0.5 - 2.5, bv + len * 0.5 + 2.5, y, y + 0.3, C_STRIPE)
			_wall_lamp(far_x, -1.0, bv + len * 0.5, y, 5.2)
		bv += len
		i += 1
	# bollards along both kerbs
	var pv := v0 + 4.0
	while pv < v1 - 2.0:
		for bx: float in [near_x + 0.6, far_x - 0.6]:
			R._box(Vector3(bx, y + KERB_UP + 0.45, pv), Vector3(0.26, 0.9, 0.26), C_BOLLARD)
		pv += 8.0
	# the strip: solid edge lines, a start line 40 m in with the light tree
	# beside it, a finish line 40 m before the far arm
	for ex: float in [STREET_X - STREET_HALF + 0.3, STREET_X + STREET_HALF - 0.3]:
		R._quad(R._p(ex - 0.07, y + R.PAINT_LIFT, v0 + 2.0), R._p(ex + 0.07, y + R.PAINT_LIFT, v0 + 2.0), R._p(ex - 0.07, y + R.PAINT_LIFT, v1 - 2.0), R._p(ex + 0.07, y + R.PAINT_LIFT, v1 - 2.0), R.C_PAINT, Vector3.UP)
	for lv: float in [v0 + 40.0, v1 - 40.0]:
		R._quad(R._p(STREET_X - STREET_HALF + 0.3, y + R.PAINT_LIFT, lv - 0.25), R._p(STREET_X + STREET_HALF - 0.3, y + R.PAINT_LIFT, lv - 0.25),
			R._p(STREET_X - STREET_HALF + 0.3, y + R.PAINT_LIFT, lv + 0.25), R._p(STREET_X + STREET_HALF - 0.3, y + R.PAINT_LIFT, lv + 0.25), R.C_PAINT, Vector3.UP)
	var tx := far_x - 0.7
	var tv := v0 + 40.0
	R._box(Vector3(tx, y + 1.8, tv), Vector3(0.14, 3.6, 0.14), R.C_POLE)
	for n in 3:
		R._box(Vector3(tx, y + 3.2 - float(n) * 0.5, tv), Vector3(0.3, 0.3, 0.3), C_TREE_AMBER)
	R._box(Vector3(tx, y + 1.5, tv), Vector3(0.3, 0.3, 0.3), C_TREE_GREEN)
	R._box(Vector3(tx, y + 1.0, tv), Vector3(0.3, 0.3, 0.3), C_TREE_RED)

# ---------- the container lanes (x7b to x8b) ----------

## Walls of stacked containers along both sides of the winding lane (one to
## three high, a second row behind), an unbroken wall in the collision so
## the stacks' corners at the bends do not open a way out, and three gantry
## cranes over the lane with their legs at the kerbs and floodlights on the
## lane.
static func _container_lanes(pk: Dictionary, v0: float, v1: float, y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(pk.id), "container lanes"])
	var hw := STREET_HALF + WALK_W
	for side: float in [1.0, -1.0]:
		# the wall in the collision, along the lane's line
		var off := side * (hw + 0.2)
		var va := v0
		while va < v1 - 0.01:
			var vb := minf(va + 10.0, v1)
			var a := _lane_off(pk, va, off)
			var b := _lane_off(pk, vb, off)
			R._wall_box(R._p(a.x, 0.0, a.y), R._p(b.x, 0.0, b.y), y, y + 2.6, 0.3)
			va = vb
		# the stacks: a container every 12.2 m, standing square to the road,
		# its near face on the wall's line; a second row behind, taller
		var cv := v0 + 6.1
		while cv < v1 - 6.0:
			for row in 2:
				var at := _lane_off(pk, cv, off + side * (1.22 + float(row) * 2.5))
				var high := rng.randi_range(1, 3) if row == 0 else rng.randi_range(2, 3)
				for level in high:
					var col: Color = C_CONTAINERS[rng.randi_range(0, C_CONTAINERS.size() - 1)]
					R._box(Vector3(at.x, y + 1.3 + 2.6 * float(level), cv), Vector3(2.44, 2.6, 12.2), col)
			cv += 12.2
	# the gantry cranes: legs at both kerbs, a beam across, a floodlight on
	# the beam lighting the lane
	for f: float in [0.18, 0.5, 0.82]:
		var gv := lerpf(v0, v1, f)
		var a := _lane_at(pk, gv)
		var c: Vector2 = a.c
		var nn: Vector2 = a.n
		var hgt := 13.0
		for side: float in [1.0, -1.0]:
			var leg := c + nn * side * (hw - 0.5)
			for dv: float in [-1.5, 1.5]:
				R._box(Vector3(leg.x, y + hgt * 0.5, gv + dv), Vector3(0.9, hgt, 0.9), C_CRANE)
			R._wall_box(R._p(leg.x, 0.0, gv - 1.5), R._p(leg.x, 0.0, gv + 1.5), y, y + hgt, 0.9)
			R._box(Vector3(leg.x, y + hgt * 0.5, gv), Vector3(0.5, hgt, 3.6), C_CRANE)
		R._box(Vector3(c.x, y + hgt + 0.6, gv), Vector3(2.0 * hw + 2.0, 1.2, 1.6), C_CRANE)
		R._box(Vector3(c.x, y + hgt + 2.0, gv), Vector3(2.0 * hw + 6.0, 1.6, 2.0), C_RUST)
		for dx: float in [-3.0, 3.0]:
			R._box(Vector3(c.x + dx, y + hgt - 0.2, gv), Vector3(0.6, 0.3, 0.6), C_FLOOD)
		R._pools.append(Transform3D(Basis.from_scale(Vector3(hgt * 1.3, 1.0, hgt * 1.8)), R._p(c.x, y + 0.06, gv)))
