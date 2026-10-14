extends RefCounted

# The sat-nav's route finder (2026-10-11): pure logic, no screen, no sound, no
# car part. Given where the car is and a place on the map, it works out the
# way there, including when turning round is much shorter than going on.
#
# The road is two-way with a solid centre barrier, so each road is two one-way
# carriageways (dir +1 and dir -1). The only ways off a carriageway are the
# legal ones: a gap in the barrier or a crossing (turn round, onto the other
# carriageway of the same road), and an interchange (onto another road). The
# router never turns the car anywhere else: driving the wrong way is a police
# offence.
#
# How it works. build() makes a small graph whose points are those turn-round
# spots and interchange ends, one per carriageway, and works out the shortest
# way between every pair once. A route then needs no search: from any place
# there is exactly one first point ahead, and before any goal exactly one last
# point, so plan() is two look-ups in sorted lists and one in the table, or
# simply straight on when the goal is ahead on the same carriageway. Exits are
# not points in the graph: an exit is only ever where a route ends.
#
# Places. From: {road, s, dir} (RoadMap.where). To: {road, s, side}, side being
# the carriageway it is on: a stop's exit (RoadMap.stop_place) or any other
# spot (a race's start or finish).
#
# A route: {ok, steps, total_m, cost_m, to} plus what progress() keeps. Each
# step is {kind, s, road, dir, id, m}: `dir` is the way the car is going as it
# reaches the step and `m` the metres driven from the route's start to it.
# Kinds: turn_around (id = the gap or crossing), keep_left / keep_right (take
# the interchange `id`, also carries to_road), and last of all exit (id = the
# exit) or arrive (a place that is not an exit). total_m is metres on the
# road; cost_m adds TURN_PENALTY_M per turn-round, and is what routes are
# compared by.
#
# Nothing here runs per frame except progress(). No class_name on purpose:
# preload it.

const RoadMap := preload("res://scripts/world/road_map.gd")

## What a turn-round costs when routes are compared, in metres of driving.
const TURN_PENALTY_M := 1500.0
## Metres of ramp through an interchange that does not give its own `length`.
const INTERCHANGE_M := 300.0
## How near a turn-round spot the car must be, facing the other way, for the
## turn to count as made (a gap is one whole chunk long).
const TURN_SLACK_M := 75.0

var turn_penalty := TURN_PENALTY_M

var _roads := {}
var _stops: Array = []
var _exit_ids := {}                      # road -> {exit key -> exit id}
var _n := 0
var _n_road := PackedInt32Array()
var _n_s := PackedFloat64Array()
var _n_dir := PackedInt32Array()
var _n_id := PackedStringArray()
var _lane := {}                          # lane key -> points on it, by rising s
var _lane_s := {}                        # lane key -> their s
var _cost := PackedFloat64Array()        # _n * _n: cheapest cost from a to b
var _next := PackedInt32Array()          # _n * _n: the first point on that way
var _link := {}                          # a * _n + b -> the interchange it is

## The road in use as a table build() reads: {road id: {length, exits, gaps,
## junctions}}. Tests pass a made-up one of the same shape.
static func roads_from_map() -> Dictionary:
	if not RoadMap.is_loop():
		return {}
	return {RoadMap.road_id: {"length": RoadMap.length(), "exits": RoadMap.exits(),
		"gaps": RoadMap.gaps(), "junctions": RoadMap.junctions()}}

## Builds the graph. With no table it reads the road RoadMap is on now, so
## build again after RoadMap.use() (a new act makes the loop longer).
## roads: {id: {length, exits: [{id, s, side}], gaps: [{id, s}], junctions: [s]}}
## interchanges: [{id, a: {road, s}, b: {road, s}, kind}], optional `length`
## (metres of ramp) and `keep` ("left" or "right").
func build(roads: Dictionary = {}, stops: Array = RoadMap.STOPS,
		interchanges: Array = RoadMap.INTERCHANGES, penalty: float = TURN_PENALTY_M) -> RefCounted:
	_roads = roads if not roads.is_empty() else roads_from_map()
	_stops = stops
	turn_penalty = penalty
	_exit_ids = {}
	_n_road = PackedInt32Array()
	_n_s = PackedFloat64Array()
	_n_dir = PackedInt32Array()
	_n_id = PackedStringArray()
	_lane = {}
	_lane_s = {}
	_link = {}
	var turns: Array = []   # [a, b]: the same spot on the two carriageways
	var joins: Array = []   # [a, b, metres, interchange]
	for id: int in _roads:
		var road: Dictionary = _roads[id]
		var ids := {}
		for e: Dictionary in road.get("exits", []):
			ids[_exit_key(float(e.s), int(e.side))] = String(e.id)
		_exit_ids[id] = ids
		for g: Dictionary in road.get("gaps", []):
			turns.append([_add(id, float(g.s), 1, String(g.id)), _add(id, float(g.s), -1, String(g.id))])
		var j := 0
		for c: float in road.get("junctions", []):
			j += 1
			turns.append([_add(id, c, 1, "j%d" % j), _add(id, c, -1, "j%d" % j)])
	for ic: Dictionary in interchanges:
		if not (_roads.has(int(ic.a.road)) and _roads.has(int(ic.b.road))):
			continue
		var ends: Array = []
		for end: Dictionary in [ic.a, ic.b]:
			ends.append([_add(int(end.road), float(end.s), 1, String(ic.id)),
				_add(int(end.road), float(end.s), -1, String(ic.id))])
		var ramp := float(ic.get("length", INTERCHANGE_M))
		for from_end in 2:
			for a: int in ends[from_end]:
				for b: int in ends[1 - from_end]:
					joins.append([a, b, ramp, ic])
	_n = _n_road.size()
	_cost.resize(_n * _n)
	_cost.fill(INF)
	_next.resize(_n * _n)
	_next.fill(-1)
	for i in _n:
		_cost[i * _n + i] = 0.0
		_next[i * _n + i] = i
	# Along each carriageway, each point to the next one the way it runs.
	for key: int in _lane:
		var pts: Array = _lane[key]
		pts.sort_custom(func(a: int, b: int) -> bool: return _n_s[a] < _n_s[b])
		var packed := PackedInt32Array(pts)
		var ss := PackedFloat64Array()
		for p in packed:
			ss.append(_n_s[p])
		_lane[key] = packed
		_lane_s[key] = ss
		var count := packed.size()
		if count < 2:
			continue
		var dir := _n_dir[packed[0]]
		var lap := _len(_n_road[packed[0]])
		for i in count:
			var a := packed[i]
			var b := packed[posmod(i + dir, count)]
			_edge(a, b, fposmod((_n_s[b] - _n_s[a]) * dir, lap))
	for t: Array in turns:
		_edge(t[0], t[1], turn_penalty)
		_edge(t[1], t[0], turn_penalty)
	for jn: Array in joins:
		_edge(jn[0], jn[1], jn[2])
		_link[int(jn[0]) * _n + int(jn[1])] = jn[3]
	# Cheapest way between every pair (Floyd-Warshall; a few dozen points).
	for k in _n:
		for i in _n:
			var ik := _cost[i * _n + k]
			if ik == INF:
				continue
			var row := i * _n
			var first := _next[row + k]
			for j in _n:
				var c := ik + _cost[k * _n + j]
				if c < _cost[row + j]:
					_cost[row + j] = c
					_next[row + j] = first
	return self

## How many points the graph has (for tests and cost reports).
func point_count() -> int:
	return _n

## Where a stop is in this router's table: {road, s, side} ({} if unknown).
## A stop off an exit is at its exit; one with its own `s` and `side` (the gas
## stations) opens straight off the road there.
func stop_place(stop_id: String) -> Dictionary:
	for st: Dictionary in _stops:
		if st.id == stop_id and _roads.has(int(st.road)):
			if st.has("s") and st.has("side"):
				return {"road": int(st.road), "s": float(st.s), "side": int(st.side)}
			for e: Dictionary in _roads[int(st.road)].get("exits", []):
				if e.id == st.exit:
					return {"road": int(st.road), "s": float(e.s), "side": int(e.side)}
	return {}

## The route from `from` {road, s, dir} to `to` {road, s, side}. ok = false
## (no steps) when there is no legal way.
func plan(from: Dictionary, to: Dictionary) -> Dictionary:
	var road_f := int(from.road)
	var road_t := int(to.road)
	if not (_roads.has(road_f) and _roads.has(road_t)):
		return _no_route(to)
	var dir_f := 1 if int(from.dir) >= 0 else -1
	var side := 1 if int(to.side) >= 0 else -1
	var s_f := float(from.s)
	var s_t := float(to.s)
	var best := INF
	if road_f == road_t and dir_f == side:
		best = fposmod((s_t - s_f) * dir_f, _len(road_f))
	# Or by way of the graph: the first point ahead, and the last one before
	# the goal on the goal's carriageway.
	var first := _point(road_f, dir_f, s_f, dir_f > 0)
	var last := _point(road_t, side, s_t, side < 0)
	var via := false
	var d1 := 0.0
	var d2 := 0.0
	if first >= 0 and last >= 0 and _cost[first * _n + last] < INF:
		d1 = fposmod((_n_s[first] - s_f) * dir_f, _len(road_f))
		d2 = fposmod((s_t - _n_s[last]) * side, _len(road_t))
		var c := d1 + _cost[first * _n + last] + d2
		if c < best:
			best = c
			via = true
	if best == INF:
		return _no_route(to)
	var steps: Array = []
	var m := best
	if via:
		m = d1
		var a := first
		while a != last:
			var b := _next[a * _n + last]
			if _link.has(a * _n + b):
				var ic: Dictionary = _link[a * _n + b]
				steps.append({"kind": "keep_" + String(ic.get("keep", "right")), "s": _n_s[a],
					"road": _n_road[a], "dir": _n_dir[a], "id": String(ic.id), "m": m,
					"to_road": _n_road[b]})
				m += float(ic.get("length", INTERCHANGE_M))
			elif _n_dir[a] == _n_dir[b]:
				m += fposmod((_n_s[b] - _n_s[a]) * _n_dir[a], _len(_n_road[a]))
			else:
				steps.append({"kind": "turn_around", "s": _n_s[a], "road": _n_road[a],
					"dir": _n_dir[a], "id": _n_id[a], "m": m})
			a = b
		m += d2
	var exit_id := String((_exit_ids[road_t] as Dictionary).get(_exit_key(s_t, side), ""))
	steps.append({"kind": "arrive" if exit_id == "" else "exit", "s": s_t, "road": road_t,
		"dir": side, "id": exit_id, "m": m})
	return {"ok": true, "steps": steps, "total_m": m, "cost_m": best, "to": to,
		"i": 0, "prev": float(steps[0].m), "off": false}

func plan_to_stop(from: Dictionary, stop_id: String) -> Dictionary:
	var to := stop_place(stop_id)
	return plan(from, to) if not to.is_empty() else _no_route(to)

## Where the car is on its route: {next_kind, next_m, left_m, missed, done}.
## Cheap enough for 10 calls a second. It ticks turn-rounds and interchanges
## off by itself; an exit it cannot see being taken, so the caller says so
## with advance(). `missed` is true once, on the call that sees the car has
## passed the next step without doing it or is no longer heading along the
## leg; after that the route is dead (`off`) until replan().
func progress(route: Dictionary, place: Dictionary) -> Dictionary:
	var out := {"next_kind": "", "next_m": 0.0, "left_m": 0.0, "missed": false, "done": false}
	if not route.ok or route.off:
		return out
	var steps: Array = route.steps
	var road := int(place.road)
	var dir := 1 if int(place.dir) >= 0 else -1
	var s := float(place.s)
	while true:
		if int(route.i) >= steps.size():
			out.done = true
			return out
		var st: Dictionary = steps[route.i]
		var lap := _len(int(st.road))
		var made := false
		if st.kind == "turn_around":
			var gap := fposmod(s - float(st.s) + lap * 0.5, lap) - lap * 0.5
			made = road == int(st.road) and dir == -int(st.dir) and absf(gap) <= TURN_SLACK_M
		elif st.has("to_road"):
			made = road == int(st.to_road)
		if made:
			advance(route)
			continue
		if road != int(st.road) or dir != int(st.dir):
			break
		var ahead := fposmod((float(st.s) - s) * dir, lap)
		if float(route.prev) >= 0.0 and ahead > float(route.prev) + lap * 0.5:
			# It was just ahead and is now a lap away: the car has gone past.
			if st.kind == "arrive":
				route.i = steps.size()
				out.done = true
				return out
			break
		route.prev = ahead
		out.next_kind = st.kind
		out.next_m = ahead
		out.left_m = ahead + float(route.total_m) - float(st.m)
		return out
	route.off = true
	out.missed = true
	return out

## Ticks the next step off (the caller's word that the exit was taken).
func advance(route: Dictionary) -> void:
	route.i = int(route.i) + 1
	route.prev = -1.0

## A new route to the same place from where the car is now (after a missed
## step, a put-back after a crash, or the heading flipping).
func replan(route: Dictionary, place: Dictionary) -> Dictionary:
	return plan(place, route.to) if not (route.to as Dictionary).is_empty() else _no_route({})

func _no_route(to: Dictionary) -> Dictionary:
	return {"ok": false, "steps": [], "total_m": INF, "cost_m": INF, "to": to,
		"i": 0, "prev": -1.0, "off": true}

func _len(road: int) -> float:
	return float(_roads[road].length)

func _add(road: int, s: float, dir: int, id: String) -> int:
	_n_road.append(road)
	_n_s.append(s)
	_n_dir.append(dir)
	_n_id.append(id)
	var key := _lane_key(road, dir)
	if not _lane.has(key):
		_lane[key] = []
	_lane[key].append(_n_road.size() - 1)
	return _n_road.size() - 1

func _edge(a: int, b: int, cost: float) -> void:
	if cost < _cost[a * _n + b]:
		_cost[a * _n + b] = cost
		_next[a * _n + b] = b

## The point on carriageway (road, dir) nearest to s: the first at or above s
## (`up`), or the last at or below it; round the lap seam if there is none.
## -1 for a carriageway with no points.
func _point(road: int, dir: int, s: float, up: bool) -> int:
	var key := _lane_key(road, dir)
	if not _lane_s.has(key):
		return -1
	var ss: PackedFloat64Array = _lane_s[key]
	var i := ss.bsearch(s) if up else ss.bsearch(s, false) - 1
	return (_lane[key] as PackedInt32Array)[posmod(i, ss.size())]

static func _lane_key(road: int, dir: int) -> int:
	return road * 2 + (1 if dir > 0 else 0)

static func _exit_key(s: float, side: int) -> int:
	return roundi(s * 10.0) * 2 + (1 if side > 0 else 0)
