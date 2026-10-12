extends Node3D

# Gas stations, first slice (Stage C stops, 2026-10-09). Roy: there was no way
# to fill up, so the car ran dry and limped for the rest of the night.
#
# The stops plan wants an exit that leads to a station. Exits are not built yet
# (RoadLayout.exits_live, road lane steps 4-5), so for now a station stands
# right on the road: a pump bay on the own-side shoulder and sidewalk under a
# canopy, every SPACING metres from FIRST_S. When exits land, the station moves
# behind one; the fuel rules below stay the same.
#
# Pull into the bay and stop: after HOLD_S the pump menu opens
# (scripts/ui/pump_panel.gd, GameState.State.STATION). No key hint on screen
# (Roy's UI rule): stopping at the pump is the action.
#
# On a loop (RoadMap.period > 0) the stations are fixed places: the STOPS of
# kind "station", four on Loop 1, two on each side of the road and never
# opposite one another, the same every lap (2026-10-11). The endless road and
# tests that move first_s keep the old first_s + k x SPACING, own side only.
#
# One station mesh per side (side +1 own carriageway, -1 oncoming, turned half
# a circle), moved to whichever station of its side is nearest the player:
# they are far past the draw distance, so two of a side are never in view.
# RoadChunkBuilder asks cleared()/in_bay() so the buildings, lamps and edge
# posts make room, like the crossing does (Junction).
#
# Cost: 3 draw calls (concrete, lit canopy underside, amber sign) plus the
# sign's text and one fake light pool. No real lights. One static body.
#
# Compound lots, grey boxes (2026-10-11). A loop station is no longer a bay on
# the shoulder: it is a 110 x 60 m lot behind the pavement (LOT_HALF either
# side of the station's s, LOT_DEPTH back from the road edge), entered and
# left by two 10 m driveways, with pump islands under a canopy, a store with
# parking in front, a wash box and air, phone and tow spots, all inside a
# wall. RoadMap pins its three chunks straight and level; RoadChunkBuilder
# clears them on that side, drops the kerb at the driveways and moves the
# out-of-bounds wall back behind the lot. The recipe per station is the
# stop's `lot` (RoadMap.STOPS); _layout() turns it into boxes and spots.
# Stopping in a pump spot opens the pump menu like the old bay did; the other
# spots only say what they are (spot_at). Off a loop (the endless road, tests
# that move first_s) the old shoulder bay is built, unchanged.
# Lot cost: 5 meshes (ground, concrete, lit, sign, paint) + text + pool = 7
# draw calls, one static body of about 20 boxes.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RoadMap := preload("res://scripts/world/road_map.gd")
const L := RoadChunkBuilder.CHUNK_LEN

## Where the first station is and how far apart they are, metres of road.
## A third of a tank (the start) lasts about 9 km of mixed driving and the
## FUEL light leaves about 3-4 km (FuelTank), so a station is always in reach
## of the light; a dry tank still limps there (LimpMode: the engine starves, it never stops).
const DEFAULT_FIRST_S := 1500.0
const SPACING := 3000.0
## The bay, relative to the station centre: car centre within BAY_HALF_S
## along the road and between BAY_X.x and BAY_X.y metres out from the own
## road edge (the island starts at 3.0, so a car centred at 2 still clears it).
const BAY_HALF_S := 5.0
const BAY_X := Vector2(0.2, 2.6)
## Stopped means under STOP_SPEED m/s for HOLD_S seconds.
const STOP_SPEED := 1.0
const HOLD_S := 0.6
## How much road the station clears of buildings, lamps and edge posts.
const CLEAR_HALF := 14.0

## Off in benchmark runs (same road every time). Read before the first chunk.
static var enabled := true
## Tests move the first station next to the spawn.
static var first_s := DEFAULT_FIRST_S

signal pulled_up(station_s: float)

var player: Node3D
## Which carriageway this node's station stands on: +1 own, -1 oncoming.
var side := 1
## The station the mesh stands at (metres of road), and the floating origin it
## was placed for.
var station_s := -1.0
var _origin := -999999
var _held := 0.0
## False after the menu closed until the car leaves the bay, so it does not
## open again the moment the player shuts it.
var armed := true
## The lot spot the car is in (index into the lot's spots, -1 = none) and,
## once it has stopped there, what kind it is ("" until then).
var spot := -1
var spot_kind := ""
var _lot := {}
var _built := ""

# ---------- where the stations are (static, no node needed) ----------

## Metres of road of station k (k = 0, 1, ...).
static func s_of(k: int) -> float:
	return first_s + float(k) * SPACING

static var _loop_key := ""
## Lap metres of the loop's stations, per side (side -> Array of float).
static var _loop_stations := {1: [], -1: []}

## Whether the stations come from the loop's STOPS.
static func _on_loop() -> bool:
	return enabled and RoadMap.period > 0 and is_equal_approx(first_s, DEFAULT_FIRST_S)

## Lap metres of this side's stations on the loop (this act's road, inside
## the lap).
static func _loop_s(side: int) -> Array:
	var key := "%d/%d/%d" % [RoadMap.road_id, RoadMap.act, RoadMap.period]
	if key != _loop_key:
		_loop_key = key
		_loop_stations = {1: [], -1: []}
		var lap := RoadMap.length()
		for st in RoadMap.STOPS:
			if String(st.kind) != "station" or int(st.road) != RoadMap.road_id:
				continue
			var at := RoadMap.stop_place(String(st.id))
			if at.is_empty() or float(at.s) < 0.0 or float(at.s) >= lap:
				continue
			(_loop_stations[1 if int(at.side) >= 0 else -1] as Array).append(float(at.s))
	return _loop_stations[side]

## The station of `side` nearest `s` (INF when that side has none).
static func nearest(s: float, side := 1) -> float:
	if _on_loop():
		var lap := RoadMap.length()
		var m := fposmod(s, lap)
		var best := INF
		for st in _loop_s(side):
			var d := fposmod(float(st) - m + lap * 0.5, lap) - lap * 0.5
			if absf(d) < absf(best):
				best = d
		return s + best
	if side != 1:
		return INF
	return s_of(maxi(0, roundi((s - first_s) / SPACING)))

## The next station of `side` ahead of `s` (more s, the same lap as the car);
## one the car is still in the bay of counts. INF when that side has none.
static func next_after(s: float, side := 1) -> float:
	if _on_loop():
		var lap := RoadMap.length()
		var from := s - BAY_HALF_S
		var m := fposmod(from, lap)
		var best := INF
		for st in _loop_s(side):
			best = minf(best, fposmod(float(st) - m, lap))
		return from + best
	if side != 1:
		return INF
	return s_of(maxi(0, ceili((s - BAY_HALF_S - first_s) / SPACING)))

## Distance from the centre line to the road edge of `side` (+1 own, -1
## oncoming) at `s`.
static func own_edge(s: float, side := 1) -> float:
	var lanes := RoadChunkBuilder.MAX_OWN_LANES if side == 1 else RoadChunkBuilder.MAX_ONC_LANES
	if RoadFrame.layout != null and RoadFrame.layout.lanes_live:
		lanes = RoadFrame.layout.lanes_at(side != 1, s)
	return RoadChunkBuilder.MEDIAN_GAP + float(lanes) * RoadChunkBuilder.LANE_W

## Chunk-local z (0 at the chunk start, -L at its end) of the station of `side`
## nearest chunk `chunk_index`; INF when that side has none.
static func _local(chunk_index: int, z: float, side := 1) -> float:
	var s := float(chunk_index) * L - z
	var n := nearest(s, side)
	if is_inf(n):
		return INF
	return float(chunk_index) * L - n

## Whether chunk-local z on `side` is within `half` of a station.
static func near(chunk_index: int, z: float, half: float, side := 1) -> bool:
	return enabled and absf(z - _local(chunk_index, z, side)) < half

## Half the road a station clears: the lot on a loop, the bay off it.
static func clear_half() -> float:
	return LOT_HALF if _on_loop() else CLEAR_HALF

## Whether a building of `side` spanning [z0, z1] (chunk-local) has to go.
static func cleared(chunk_index: int, z0: float, z1: float, side := 1) -> bool:
	if not enabled:
		return false
	var c := _local(chunk_index, (z0 + z1) / 2.0, side)
	var half := clear_half()
	return maxf(z0, z1) > c - half and minf(z0, z1) < c + half

## No lamp or edge post of `side` here.
static func in_bay(chunk_index: int, z: float, side := 1) -> bool:
	return near(chunk_index, z, clear_half(), side)

# ---------- the compound lot (loop stations; static, no node needed) ----------
#
# Lot space: lx = metres away from that side's road edge, la = metres along
# the road from the station centre in that side's direction of travel (so the
# oncoming station is the same lot turned half a circle). A Rect2 here is
# (lx, la, depth, length).

## Half the lot's length along the road, and its depth from the road edge.
const LOT_HALF := 55.0
const LOT_DEPTH := 60.0
## Driveways: entry centred DRIVE_AT before the station, exit DRIVE_AT after.
const DRIVE_AT := 45.0
const DRIVE_HALF := 5.0
## Painted taper on the shoulder before the entry.
const TAPER := 40.0
## The knee wall along the road, just behind the pavement.
const KNEE_X := 4.0
const KNEE_T := 0.5
const KNEE_H := 0.5
const LOT_WALL_T := 0.4
const LOT_WALL_H := 2.4
## Pump islands, parallel to the road: the first one's centre, their spacing,
## width and half length; a dispenser DISPENSER_AT either side of the middle.
const ISLAND_X0 := 9.25
const ISLAND_STEP := 7.5
const ISLAND_W := 1.2
const ISLAND_HALF := 8.5
const DISPENSER_AT := 4.5
## A pump spot: the car's centre this far from the island's centre line, and
## within PUMP_HALF of the dispenser along the road.
const PUMP_X := Vector2(0.8, 3.2)
const PUMP_HALF := 3.0
const LOT_CANOPY_X0 := 6.0
const LOT_CANOPY_HALF := 15.0
## The row of nose-in bays behind the drive aisle, and the store behind it.
const ROW_X := Vector2(34.0, 39.5)
const STORE_D := 12.5
const STORE_HALF := 12.0
const PARK_W := 2.7
const WIDE_W := 3.2
const WASH_LA := Vector2(21.5, 27.1)
const TOW_LA := 33.0
## The spot check runs only this near a station, metres of road.
const SPOT_RANGE := 80.0
const KINDS := ["pump", "park", "wash", "air", "phone", "tow"]

static var _layouts := {}

## The lot of the `side` station at `s` metres of road: {} off a loop (the old
## bay) or where there is no station, else {id, pumps, store, wash, islands,
## canopy, boxes, solids, spots} (see _layout).
static func lot_of(s: float, side := 1) -> Dictionary:
	if not _on_loop() or is_inf(s):
		return {}
	var stop: Dictionary = RoadMap.station_at(fposmod(s, RoadMap.length()), side)
	if stop.is_empty():
		return {}
	var id := String(stop.id)
	if not _layouts.has(id):
		_layouts[id] = _layout(stop)
	return _layouts[id]

## Lays a station's recipe out. boxes: [{r, y0, y1, mat}] to draw; solids:
## [{r, h}] to collide with; spots: [{kind, r}], r = where the car's centre
## counts as in the spot.
static func _layout(stop: Dictionary) -> Dictionary:
	var recipe: Dictionary = stop.get("lot", {})
	var pumps := int(recipe.get("pumps", 4))
	var store_at := String(recipe.get("store", "back_centre"))
	var wash := String(recipe.get("wash", "bay"))
	var islands := 3 if pumps >= 6 else 2
	# cc: the canopy's centre along the road, sc: the store's.
	var cc := 0.0
	var sc := 0.0
	var side_bays := [-17.55, -14.85, 14.85, 17.55]
	var air := -36.0
	var phone := -24.0
	var pen := -42.0
	match store_at:
		"back_left":
			sc = -22.0
			air = 2.0
			phone = 14.0
			pen = 44.0
		"corner":
			# the store in the back corner on the entry side, the canopy toward the exit
			sc = -38.0
			cc = 12.0
			side_bays = [14.85, 17.55, 20.25, 22.95]
			air = -9.0
			phone = 3.0
			pen = 6.0
	var boxes := []
	var solids := []
	var spots := []
	# the boundary: knee wall along the road (open at the two driveways), a
	# wall down each side and along the back
	for seg in [[-LOT_HALF, -DRIVE_AT - DRIVE_HALF], [-DRIVE_AT + DRIVE_HALF, DRIVE_AT - DRIVE_HALF], [DRIVE_AT + DRIVE_HALF, LOT_HALF]]:
		var r := Rect2(KNEE_X, float(seg[0]), KNEE_T, float(seg[1]) - float(seg[0]))
		boxes.append({"r": r, "y0": 0.0, "y1": KNEE_H, "mat": "concrete"})
		solids.append({"r": r, "h": 1.0})
	for r in [Rect2(KNEE_X, -LOT_HALF - LOT_WALL_T, LOT_DEPTH - KNEE_X, LOT_WALL_T),
			Rect2(KNEE_X, LOT_HALF, LOT_DEPTH - KNEE_X, LOT_WALL_T),
			Rect2(LOT_DEPTH - LOT_WALL_T, -LOT_HALF, LOT_WALL_T, LOT_HALF * 2.0)]:
		boxes.append({"r": r, "y0": 0.0, "y1": LOT_WALL_H, "mat": "concrete"})
		solids.append({"r": r, "h": 3.0})
	# pump islands under the canopy; pillars stand on the islands only
	var canopy := Rect2(LOT_CANOPY_X0, cc - LOT_CANOPY_HALF, 7.0 * float(islands), LOT_CANOPY_HALF * 2.0)
	for i in islands:
		var ix := ISLAND_X0 + ISLAND_STEP * float(i)
		boxes.append({"r": Rect2(ix - ISLAND_W / 2.0, cc - ISLAND_HALF + 0.5, ISLAND_W, ISLAND_HALF * 2.0 - 1.0), "y0": 0.0, "y1": 0.2, "mat": "concrete"})
		solids.append({"r": Rect2(ix - ISLAND_W / 2.0, cc - ISLAND_HALF, ISLAND_W, ISLAND_HALF * 2.0), "h": 1.8})
		for e in [-1.0, 1.0]:
			boxes.append({"r": Rect2(ix - 0.15, cc + e * (ISLAND_HALF - 0.2) - 0.15, 0.3, 0.3), "y0": 0.0, "y1": 1.0, "mat": "concrete"})  # bollard
			boxes.append({"r": Rect2(ix - 0.18, cc + e * 6.8 - 0.18, 0.36, 0.36), "y0": 0.0, "y1": CANOPY_Y, "mat": "concrete"})  # pillar
			var d: float = cc + e * DISPENSER_AT
			boxes.append({"r": Rect2(ix - 0.25, d - 0.22, 0.5, 0.44), "y0": 0.2, "y1": 1.7, "mat": "concrete"})
			boxes.append({"r": Rect2(ix - 0.27, d - 0.15, 0.54, 0.3), "y0": 1.25, "y1": 1.6, "mat": "sign"})  # lit display, both faces
			for face in [-1.0, 1.0]:
				var x0: float = ix + PUMP_X.x if face > 0.0 else ix - PUMP_X.y
				spots.append({"kind": "pump", "r": Rect2(x0, d - PUMP_HALF, PUMP_X.y - PUMP_X.x, PUMP_HALF * 2.0)})
	boxes.append({"r": canopy, "y0": CANOPY_Y + 0.06, "y1": CANOPY_Y + 0.65, "mat": "concrete"})
	boxes.append({"r": canopy.grow(-0.15), "y0": CANOPY_Y, "y1": CANOPY_Y + 0.06, "mat": "lit"})
	boxes.append({"r": Rect2(canopy.position.x - 0.04, canopy.position.y, 0.04, canopy.size.y), "y0": CANOPY_Y + 0.2, "y1": CANOPY_Y + 0.5, "mat": "sign"})
	# the store, its glass front facing the road, nose-in bays along the front
	var store := Rect2(ROW_X.y, sc - STORE_HALF, STORE_D, STORE_HALF * 2.0)
	boxes.append({"r": store, "y0": 0.0, "y1": 4.5, "mat": "concrete"})
	boxes.append({"r": Rect2(ROW_X.y - 0.06, sc - STORE_HALF + 1.0, 0.06, STORE_HALF * 2.0 - 2.0), "y0": 0.6, "y1": 2.8, "mat": "lit"})
	solids.append({"r": store, "h": 4.5})
	var row_d := ROW_X.y - ROW_X.x
	for i in 8:
		spots.append({"kind": "park", "r": Rect2(ROW_X.x, sc + (float(i) - 3.5) * PARK_W - PARK_W / 2.0, row_d, PARK_W)})
	for b in side_bays:
		spots.append({"kind": "park", "r": Rect2(ROW_X.x, sc + float(b) - PARK_W / 2.0, row_d, PARK_W)})
	# the wash box: nose in from the aisle; a tunnel is open at the back too
	var wash_d := STORE_D
	for r in [Rect2(ROW_X.y, WASH_LA.x - LOT_WALL_T, wash_d, LOT_WALL_T), Rect2(ROW_X.y, WASH_LA.y, wash_d, LOT_WALL_T)]:
		boxes.append({"r": r, "y0": 0.0, "y1": 3.2, "mat": "concrete"})
		solids.append({"r": r, "h": 3.2})
	if wash != "tunnel":
		var back := Rect2(ROW_X.y + wash_d - LOT_WALL_T, WASH_LA.x, LOT_WALL_T, WASH_LA.y - WASH_LA.x)
		boxes.append({"r": back, "y0": 0.0, "y1": 3.2, "mat": "concrete"})
		solids.append({"r": back, "h": 3.2})
	boxes.append({"r": Rect2(ROW_X.y, WASH_LA.x - LOT_WALL_T, wash_d, WASH_LA.y - WASH_LA.x + LOT_WALL_T * 2.0), "y0": 3.2, "y1": 3.5, "mat": "concrete"})
	spots.append({"kind": "wash", "r": Rect2(ROW_X.y + 1.5, (WASH_LA.x + WASH_LA.y) / 2.0 - 2.0, 8.0, 4.0)})
	spots.append({"kind": "air", "r": Rect2(ROW_X.x, air - WIDE_W / 2.0, row_d, WIDE_W)})
	spots.append({"kind": "phone", "r": Rect2(ROW_X.x, phone - WIDE_W / 2.0, row_d, WIDE_W)})
	spots.append({"kind": "tow", "r": Rect2(ROW_X.x, TOW_LA - WIDE_W / 2.0, row_d, WIDE_W)})
	# air and phone posts at the head of their spots, the dumpster pen at the back
	for a in [air, phone]:
		var post := Rect2(ROW_X.y + 0.3, float(a) - 0.3, 0.6, 0.6)
		boxes.append({"r": post, "y0": 0.0, "y1": 1.6 if a == air else 2.2, "mat": "concrete"})
		solids.append({"r": post, "h": 2.2})
	var pen_r := Rect2(LOT_DEPTH - LOT_WALL_T - 5.6, pen - 3.0, 5.6, 6.0)
	boxes.append({"r": pen_r, "y0": 0.0, "y1": 1.8, "mat": "concrete"})
	solids.append({"r": pen_r, "h": 1.8})
	# the price sign: a pole at the entry-side corner, the board facing the traffic
	boxes.append({"r": Rect2(KNEE_X + 0.1, -LOT_HALF - 0.35, 0.3, 0.3), "y0": 0.0, "y1": 5.7, "mat": "concrete"})
	boxes.append({"r": Rect2(KNEE_X - 0.95, -LOT_HALF - 0.35, 2.4, 0.3), "y0": 5.7, "y1": 7.1, "mat": "sign"})
	return {"id": String(stop.id), "pumps": pumps, "store": store_at, "wash": wash, "islands": islands,
		"canopy": canopy, "boxes": boxes, "solids": solids, "spots": spots}

## Whether chunk-local z on `side` is inside a lot (between its side walls).
static func in_lot(chunk_index: int, z: float, side := 1) -> bool:
	return _on_loop() and absf(z - _local(chunk_index, z, side)) < LOT_HALF

## Chunk-local z of the centre of the lot that reaches into this chunk on
## `side`; INF when none does.
static func lot_centre(chunk_index: int, side := 1) -> float:
	if not _on_loop():
		return INF
	var c := _local(chunk_index, -L / 2.0, side)
	return c if c - LOT_HALF < 0.0 and c + LOT_HALF > -L else INF

## The lot's two driveways as kerb drops for this chunk side: [[z, half]].
static func lot_drops(chunk_index: int, side := 1) -> Array:
	var c := lot_centre(chunk_index, side)
	return [] if is_inf(c) else [[c + DRIVE_AT, DRIVE_HALF], [c - DRIVE_AT, DRIVE_HALF]]

## Whether chunk-local z on `side` is along a lot's frontage or the taper
## before its entry: nothing stands on the shoulder or the pavement there.
static func in_frontage(chunk_index: int, z: float, side := 1) -> bool:
	if not _on_loop():
		return false
	var c := _local(chunk_index, z, side)
	if is_inf(c):
		return false
	var la := (c - z) * float(side)
	return la > -(LOT_HALF + TAPER + 5.0) and la < LOT_HALF + 5.0

## Road position `p` (x, s) in the lot space of the `side` station at `ss`.
static func lot_pos(p: Vector2, ss: float, side := 1) -> Vector2:
	return Vector2(p.x * float(side) - own_edge(ss, side), (p.y - ss) * float(side))

## Lot position (lx, la) of the `side` station at `ss` as a road position.
static func lot_to_road(q: Vector2, ss: float, side := 1) -> Vector2:
	return Vector2((own_edge(ss, side) + q.x) * float(side), ss + q.y * float(side))

## Which of the lot's spots road position `p` is in (-1 = none).
static func spot_index(p: Vector2, ss: float, side := 1) -> int:
	var lot := lot_of(ss, side)
	if lot.is_empty() or absf(p.y - ss) > SPOT_RANGE:
		return -1
	var q := lot_pos(p, ss, side)
	var spots: Array = lot.spots
	for i in spots.size():
		if (spots[i].r as Rect2).has_point(q):
			return i
	return -1

## The spot at road position `p` (x, s), on either side of the road:
## {station_s, side, index, kind}, or {} when it is in none.
static func spot_at(p: Vector2) -> Dictionary:
	for side in [1, -1]:
		var ss := nearest(p.y, side)
		var i := spot_index(p, ss, side)
		if i >= 0:
			return {"station_s": ss, "side": side, "index": i, "kind": String(lot_of(ss, side).spots[i].kind)}
	return {}

## Road position of the middle of the first spot of `kind` (skipping `skip`
## of them) at the `side` station at `ss`; Vector2.INF when there is none.
static func spot_centre(ss: float, side: int, kind: String, skip := 0) -> Vector2:
	var lot := lot_of(ss, side)
	for sp in lot.get("spots", []):
		if String(sp.kind) == kind:
			if skip == 0:
				return lot_to_road((sp.r as Rect2).get_center(), ss, side)
			skip -= 1
	return Vector2.INF

## Road-space position of a node: x across (own side +), s along.
static func road_pos(n: Node3D) -> Vector2:
	var u := RoadFrame.unroll(n.global_position)
	return Vector2(u.x, RoadFrame.s_at(u.z))

## Whether road position `p` (x, s) is in the bay of the `side` station at
## `ss` (a pump spot of its lot on a loop).
static func in_spot(p: Vector2, ss: float, side := 1) -> bool:
	if is_inf(ss):
		return false
	var lot := lot_of(ss, side)
	if not lot.is_empty():
		var i := spot_index(p, ss, side)
		return i >= 0 and String(lot.spots[i].kind) == "pump"
	var x := p.x * float(side) - own_edge(ss, side)
	return absf(p.y - ss) <= BAY_HALF_S and x >= BAY_X.x and x <= BAY_X.y

# ---------- the node ----------

func _ready() -> void:
	name = "GasStation" if side == 1 else "GasStationOnc"
	visible = enabled
	if not enabled:
		set_physics_process(false)
		return
	_place()

func _physics_process(delta: float) -> void:
	_place()
	if player == null or is_inf(station_s):
		return
	var p := road_pos(player)
	var kind := "pump"
	var in_bay_now := false
	if _lot.is_empty():
		in_bay_now = in_spot(p, station_s, side)
	else:
		var now := spot_index(p, station_s, side)
		if now != spot:
			# another spot is another stop
			armed = true
			_held = 0.0
			spot_kind = ""
		spot = now
		in_bay_now = now >= 0
		if in_bay_now:
			kind = String(_lot.spots[now].kind)
	if not in_bay_now:
		armed = true
		_held = 0.0
		spot_kind = ""
		return
	var v: Vector3 = player.get("linear_velocity") if player.get("linear_velocity") != null else Vector3.ZERO
	if v.length() < STOP_SPEED:
		_held += delta
	else:
		_held = 0.0
	if armed and _held >= HOLD_S:
		armed = false
		spot_kind = kind
		if kind == "pump":
			pulled_up.emit(station_s)

## Follows the player from station to station and the floating origin.
func _place() -> void:
	var s := nearest(road_pos(player).y if player != null else 0.0, side)
	if s == station_s and RoadFrame.origin_index == _origin:
		return
	station_s = s
	_origin = RoadFrame.origin_index
	visible = enabled and not is_inf(s)
	if is_inf(s):
		return
	var z := float(RoadFrame.origin_index) * L - s
	# the oncoming station is the same mesh turned half a circle about the
	# road's up axis, so its pumps face the road and its sign faces its traffic
	global_transform = RoadFrame.pose(own_edge(s, side) * float(side), 0.0, z, 0.0 if side == 1 else PI)
	reset_physics_interpolation()
	# what stands there: this station's lot, or the old bay off a loop
	_lot = lot_of(s, side)
	var key := String(_lot.get("id", "bay"))
	if key != _built:
		_built = key
		spot = -1
		for c in get_children():
			remove_child(c)
			c.queue_free()
		if _lot.is_empty():
			_build()
		else:
			_build_lot()

# Local frame: x = 0 is the own road edge, +x away from the road, -z ahead.
# Shoulder 0..1.4, curb 1.4..1.7, sidewalk 1.7..3.9 (RoadChunkBuilder).
const ISLAND := Rect2(3.0, -3.2, 0.8, 6.4)    # x, z, width, length
const CANOPY_X := Vector2(0.2, 4.6)
const CANOPY_Z := 7.5
const CANOPY_Y := 4.6
const SIDEWALK_Y := 0.15

const CONCRETE := Color(0.42, 0.42, 0.44)
const CANOPY_LIT := Color(1.0, 0.86, 0.62)   # warm sodium-white under the roof
const SIGN_AMBER := Color("#FFC066")
const NAVY := Color("#0E1424")

func _build() -> void:
	var concrete := SurfaceTool.new()
	concrete.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sign := SurfaceTool.new()
	sign.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ix := ISLAND.position.x + ISLAND.size.x / 2.0
	# pump island, two pumps, two canopy pillars on the island
	_box(concrete, Vector3(ix, SIDEWALK_Y + 0.1, 0.0), Vector3(ISLAND.size.x, 0.2, ISLAND.size.y))
	for z in [-1.4, 1.4]:
		_box(concrete, Vector3(ix, SIDEWALK_Y + 0.95, z), Vector3(0.5, 1.5, 0.45))
		_box(sign, Vector3(ix - 0.26, SIDEWALK_Y + 1.35, z), Vector3(0.02, 0.35, 0.3))  # lit pump display
	for z in [-2.9, 2.9]:
		_box(concrete, Vector3(ix, CANOPY_Y / 2.0, z), Vector3(0.35, CANOPY_Y, 0.35))
	# canopy: a concrete slab with a lit underside
	var cx := (CANOPY_X.x + CANOPY_X.y) / 2.0
	var cw := CANOPY_X.y - CANOPY_X.x
	_box(concrete, Vector3(cx, CANOPY_Y + 0.35, 0.0), Vector3(cw, 0.6, CANOPY_Z * 2.0))
	_box(lit, Vector3(cx, CANOPY_Y + 0.03, 0.0), Vector3(cw - 0.3, 0.06, CANOPY_Z * 2.0 - 0.3))
	# amber edge band round the canopy, the station's read from far off
	_box(sign, Vector3(CANOPY_X.x - 0.02, CANOPY_Y + 0.35, 0.0), Vector3(0.04, 0.25, CANOPY_Z * 2.0))
	# price sign before the bay, facing the traffic that comes from +z
	var sz := CANOPY_Z + 8.0
	_box(concrete, Vector3(ix, 3.0, sz), Vector3(0.3, 6.0, 0.3))
	_box(sign, Vector3(ix, 6.4, sz), Vector3(0.3, 1.4, 2.4))
	_add(concrete, _mat(CONCRETE, false), "Concrete")
	_add(lit, _mat(CANOPY_LIT, true, 2.2), "CanopyLight")
	_add(sign, _mat(SIGN_AMBER, true, 1.6), "Sign")
	var label := Label3D.new()
	label.name = "SignText"
	label.text = "FUEL"
	label.font = UiTheme.font("menu")
	label.font_size = 96
	label.pixel_size = 0.006
	label.modulate = NAVY
	label.outline_size = 0
	label.position = Vector3(ix, 6.4, sz + 0.17)
	add_child(label)
	# the light the canopy throws on the bay (a fake pool, like the street lamps)
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	pool.mesh = RoadChunkBuilder._get_pool_mesh()
	pool.material_override = RoadChunkBuilder._get_pool_mat()
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.transform = Transform3D(Basis.from_scale(Vector3(7.0, 1.0, 14.0)), Vector3(cx, RoadChunkBuilder.POOL_Y + SIDEWALK_Y, 0.0))
	add_child(pool)
	# one body: the island with its pumps and pillars (the canopy is out of reach)
	var body := StaticBody3D.new()
	body.name = "Island"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ISLAND.size.x, 1.8, ISLAND.size.y)
	shape.shape = box
	shape.position = Vector3(ix, SIDEWALK_Y + 0.9, 0.0)
	body.add_child(shape)
	add_child(body)

const LOT_GROUND := Color(0.2, 0.2, 0.21)
const LOT_PAINT := Color(0.62, 0.62, 0.6)
const PAINT_Y := 0.03

## The lot in grey boxes, from _lot (lot space: x = lx, z = -la).
func _build_lot() -> void:
	var tools := {}
	for n in ["ground", "concrete", "lit", "sign", "paint"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[n] = st
	# the ground: one dark slab from the back of the pavement to the back wall
	_lbox(tools.ground, Rect2(KNEE_X - 0.3, -LOT_HALF, LOT_DEPTH - KNEE_X + 0.3, LOT_HALF * 2.0), -0.2, 0.012)
	for b in _lot.boxes:
		_lbox(tools[b.mat], b.r, float(b.y0), float(b.y1))
	# paint: every spot's outline, arrows through the driveways and along the
	# pump lanes and the aisle, the taper on the shoulder before the entry
	var paint: SurfaceTool = tools.paint
	for sp in _lot.spots:
		var r: Rect2 = sp.r
		if String(sp.kind) == "wash":
			continue
		_lbox(paint, Rect2(r.position.x, r.position.y - 0.05, r.size.x, 0.1), 0.012, PAINT_Y)
		_lbox(paint, Rect2(r.position.x, r.end.y - 0.05, r.size.x, 0.1), 0.012, PAINT_Y)
	var canopy: Rect2 = _lot.canopy
	var cc := canopy.get_center().y
	_arrow(paint, Vector2(1.6, -DRIVE_AT), Vector2(1.0, 0.0))
	_arrow(paint, Vector2(7.5, -DRIVE_AT), Vector2(1.0, 0.0))
	_arrow(paint, Vector2(7.5, DRIVE_AT), Vector2(-1.0, 0.0))
	_arrow(paint, Vector2(1.6, DRIVE_AT), Vector2(-1.0, 0.0))
	for i in int(_lot.islands) + 1:
		var lane_x := ISLAND_X0 + ISLAND_STEP * (float(i) - 0.5)
		_arrow(paint, Vector2(lane_x, cc - LOT_CANOPY_HALF - 4.0), Vector2(0.0, 1.0))
	for a in [-30.0, 0.0, 30.0]:
		_arrow(paint, Vector2(ROW_X.x - 3.5, a), Vector2(0.0, 1.0))
	var n_stripes := int(TAPER / 4.0)
	for i in n_stripes:
		var la0 := -DRIVE_AT - DRIVE_HALF - TAPER + float(i) * 4.0
		# a stripe leaning into the entry, wider the nearer it is
		var reach := lerpf(0.4, 1.3, float(i) / float(n_stripes - 1))
		var a0 := _road_local(0.1, la0, PAINT_Y)
		var a1 := _road_local(0.1 + reach, la0 + 1.6, PAINT_Y)
		var b0 := _road_local(0.1, la0 + 0.5, PAINT_Y)
		var b1 := _road_local(0.1 + reach, la0 + 2.1, PAINT_Y)
		for v in [a0, a1, b1, a0, b1, b0]:
			paint.add_vertex(v)
	_add(tools.ground, _mat(LOT_GROUND, false), "Ground")
	_add(tools.concrete, _mat(CONCRETE, false), "Concrete")
	_add(tools.lit, _mat(CANOPY_LIT, true, 2.2), "CanopyLight")
	_add(tools.sign, _mat(SIGN_AMBER, true, 1.6), "Sign")
	_add(tools.paint, _mat(LOT_PAINT, false), "Paint")
	var label := Label3D.new()
	label.name = "SignText"
	label.text = "FUEL"
	label.font = UiTheme.font("menu")
	label.font_size = 96
	label.pixel_size = 0.006
	label.modulate = NAVY
	label.outline_size = 0
	label.position = Vector3(KNEE_X + 0.25, 6.4, LOT_HALF + 0.37)
	add_child(label)
	# the light the canopy throws on the pumps (a fake pool, like the street lamps)
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	pool.mesh = RoadChunkBuilder._get_pool_mesh()
	pool.material_override = RoadChunkBuilder._get_pool_mat()
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.transform = Transform3D(Basis.from_scale(Vector3(canopy.size.x * 1.5, 1.0, canopy.size.y * 1.2)),
		Vector3(canopy.get_center().x, RoadChunkBuilder.POOL_Y, -cc))
	add_child(pool)
	# one body: every wall, island and building of the lot
	var body := StaticBody3D.new()
	body.name = "Lot"
	CarSpec.make_wall(body)
	for sd in _lot.solids:
		var r: Rect2 = sd.r
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, float(sd.h), r.size.y)
		shape.shape = box
		shape.position = Vector3(r.get_center().x, float(sd.h) / 2.0, -r.get_center().y)
		body.add_child(shape)
	add_child(body)

## A box over lot rectangle `r` from height y0 to y1.
static func _lbox(st: SurfaceTool, r: Rect2, y0: float, y1: float) -> void:
	_box(st, Vector3(r.get_center().x, (y0 + y1) / 2.0, -r.get_center().y), Vector3(r.size.x, y1 - y0, r.size.y))

## A flat arrow on the ground at lot position `at`, pointing along `dir`.
static func _arrow(st: SurfaceTool, at: Vector2, dir: Vector2) -> void:
	var f := Vector3(dir.x, 0.0, -dir.y)
	var r := Vector3(-f.z, 0.0, f.x)
	var o := Vector3(at.x, PAINT_Y, -at.y)
	var pts := [o - f * 1.5 - r * 0.12, o - f * 1.5 + r * 0.12, o + f * 0.3 + r * 0.12, o + f * 0.3 - r * 0.12]
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(pts[i])
	for v in [o + f * 0.3 - r * 0.5, o + f * 0.3 + r * 0.5, o + f * 1.5]:
		st.add_vertex(v)

## A point on the road beside the lot, in this node's space: lx from the road
## edge there, la along the road from the station (follows a bend or a hill
## outside the lot's own flat chunks).
func _road_local(lx: float, la: float, y: float) -> Vector3:
	var s := station_s + la * float(side)
	var z := float(RoadFrame.origin_index) * L - s
	return to_local(RoadFrame.pose((own_edge(s, side) + lx) * float(side), y, z, 0.0).origin)

func _add(st: SurfaceTool, mat: Material, n: String) -> void:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = st.commit()
	mi.material_override = mat
	if n != "Concrete":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

static func _mat(c: Color, emissive: bool, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c if not emissive else c * 0.3
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m

static func _box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size / 2.0
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		st.add_vertex(p[f[0]])
		st.add_vertex(p[f[1]])
		st.add_vertex(p[f[2]])
		st.add_vertex(p[f[0]])
		st.add_vertex(p[f[2]])
		st.add_vertex(p[f[3]])
