extends RefCounted

# Traffic on the ramps and the ring (#630, 2026-10-13; Roy 17:27Z: "the NPCs
# dont even use the roundabout").
#
# Traffic has no lane graph: every car lives on one of the 4 + 4 main lanes.
# A ring visitor is a traffic car that leaves them for one fixed route at a
# ring site, built from the ramp and ring shapes that already exist
# (RoadRamps.x_at / y_at, the ring's lane at radius X_TOP):
#
#   outside lane -> slip lane -> up-ramp -> (round the ring) -> a down-ramp
#   -> slip lane -> back into the outside lane
#
# Three routes, described for the +1 carriageway (x > 0, driven the way the
# chunks count, w = metres past the ring's centre growing as it drives) and
# turned half a circle for the -1 one (the site is the same either way round):
#   STRAIGHT  up and straight down your own side (the ramp's top runs along the
#             ring's lane, so this crosses the ring where it meets it)
#   HALF      half way round the ring and down the far side: a U-turn
#   LAP       once round and down your own side
#
# A route is a list of points one metre apart in the site's own flat space (x
# across, w along, y up off the road), with the heading, pitch and the speed
# the route allows at each (ramp RAMP_V, ring RING_V, planned back at
# PLAN_DECEL). TrafficCar drives it on rails (posed from its distance along
# the route, as cheap as a lane) or in the full sim (pure pursuit at a route
# point). Rules, decided in TrafficCar._visit_accel:
#   - a car follows whatever is on its route ahead: other visitors, the player
#     (on a ramp or the ring), and on the slip lane the main-road traffic;
#   - at the ring the ramp's top is a give-way line: a car there waits while
#     anything on the ring would reach the point where the ramp meets it
#     inside GIVE_WAY_T seconds (the junction trick: the line is a stopped car);
#     cars already on the ring have priority, as on any roundabout;
#   - back on the slip lane it joins the outside lane only through a gap the
#     ordinary lane change would accept (TrafficCar._merge_safe), else waits.
# Which cars go (TrafficManager): about 1 in VISIT_SHARE of the cars in the
# outside lane as they pass PICK_W before a site; and some respawns are placed
# on a ring or a far ramp ahead of the player, out of sight, so cars also come
# down from the ring and join the main road. At most SITE_CAP per site.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")

const L := 50.0
const STEP := 1.0
## The outside lane's centre (RoadChunkBuilder.lane_offset(3)) and the slip lane's.
const LANE3 := 11.6
const SLIP_X := RoadRamps.X_LANE + RoadRamps.HALF
const R := RoadRamps.X_TOP
const DECK_Y := RoadRamps.RAMP_H + RoadRamps.LIFT
## Where (metres before the ring's centre) a car in the outside lane is picked
## and starts its route; where it moves out onto the slip lane, and back.
const START_W := -300.0
const LEAD_IN := Vector2(-290.0, -240.0)
const LEAD_OUT := Vector2(250.0, 300.0)
const END_W := 312.0
## Speeds the route allows, m/s: on the ramps, and on the ring and the last
## SLOW_W metres of ramp either side of where it meets the ring.
const RAMP_V := 15.0
const RING_V := 10.5
const SLOW_W := 30.0
const PLAN_DECEL := 2.0
## The give-way line: on the up-ramp, this far before the ramp's centre line
## touches the ring (just outside the ring's rim, RoadRamps.V_RING_IN).
const GIVE_WAY_W := 22.0
## The ramp's top runs along the ring's lane (x = X_TOP) and meets it
## tangentially, so they overlap over a stretch, not at a point: the ramp is
## within a car's width (plus margin) of the ring's lane for |w| < ZONE_W.
## A car at the line goes only when everything on the ring will reach that
## stretch at least GIVE_WAY_T seconds after the car itself has got into it
## (a gap acceptance, like any roundabout), and nothing is in the stretch or
## within GIVE_WAY_M metres of it.
const ZONE_W := 12.3
const GIVE_WAY_T := 2.0
const GIVE_WAY_M := 10.0
## Further round than this it is not counted at all (just over half the ring).
const GIVE_WAY_LOOK := 105.0
## The acceleration a car at the line is assumed to pull away with (follow_accel
## gives about this from a standstill), m/s^2.
const GIVE_WAY_A := 1.5
## Within this far across of a route point, something is on the route.
const ON_ROUTE := 2.3
## Height difference above which two things are on different decks.
const ON_DECK_Y := 2.5

const STRAIGHT := 0
const HALF := 1
const LAP := 2
## How often a visitor takes each route.
const KIND_SHARE := [0.2, 0.5, 0.3]

## Share of the outside-lane cars passing a site that take its exit.
const VISIT_SHARE := 1.0 / 8.0
## Most visitors at one site at once (ramps and ring together).
const SITE_CAP := 4
## Share of respawns, while a site ahead is in the spawn band and has fewer
## than SEED_CAP visitors, that are placed on its ring or a ramp coming down.
const RING_SPAWN_SHARE := 0.35
const SEED_CAP := 2
## Most visitors over all sites, as a share of the traffic cars: at the
## default 16 cars that is 2, so the main road keeps its traffic (the
## highway's flash check, tests/traffic/traffic_behaviour.gd E, needs cars in
## the player's lane).
const ALL_SHARE := 1.0 / 8.0

## NEON_RING_TRAFFIC=0 turns ring visitors off (before/after comparisons).
static var enabled := OS.get_environment("NEON_RING_TRAFFIC") != "0"

## Microseconds spent in the visitors' own code (routes, following, the
## give-way, picking, ring spawns) since start, for the cost test.
static var cost_usec := 0

static var _routes: Array = []   # [kind * 2 + (0 for side +1, 1 for side -1)]

## The route `kind` for a car starting on carriageway `side` (+1 / -1).
static func route(kind: int, side: int) -> Dictionary:
	if _routes.is_empty():
		for k in 3:
			var r := _build(k)
			_routes.append(r)
			_routes.append(_turned(r))
	return _routes[kind * 2 + (0 if side > 0 else 1)]

## Whether the site's ramps and ring are there to drive on.
static func live() -> bool:
	return enabled and RoadRamps.enabled and RoadRamps.ring and RoadMap.is_loop() and not RoadMap.rings().is_empty()

## The ring site whose ramps or slip lanes run beside the point `s` metres
## along the road: {index, s (its centre on this lap)}; index -1 for none.
## Two array lookups, no search (RoadMap.ring_at / ring_k).
static func site_at(s: float) -> Dictionary:
	var c := floori(s / L)
	var ri := RoadMap.ring_at(c)
	if ri < 0:
		return {"index": -1, "s": 0.0}
	return {"index": ri, "s": float(c - RoadMap.ring_k(c)) * L}

static func road_z(site_s: float, w: float) -> float:
	return float(RoadFrame.origin_index) * L - (site_s + w)

# ---------- building the routes ----------

static func _build(kind: int) -> Dictionary:
	var raw := PackedVector3Array()
	var w := START_W
	while w < -RoadRamps.V_GORE:
		raw.append(Vector3(lerpf(LANE3, SLIP_X, smoothstep(LEAD_IN.x, LEAD_IN.y, w)), w, 0.0))
		w += 0.5
	w = -RoadRamps.V_GORE
	while w < 0.0:
		raw.append(Vector3(RoadRamps.x_at(-w), w, RoadRamps.y_at(-w) + RoadRamps.LIFT))
		w += 0.5
	var turn := 0.0
	if kind == HALF:
		turn = PI
	elif kind == LAP:
		turn = TAU
	var a := 0.0
	var ring0 := raw.size()
	while a < turn:
		raw.append(Vector3(R * cos(a), R * sin(a), DECK_Y))
		a += 0.5 / R
	var ring1 := raw.size()
	var far := kind == HALF
	var out := PackedVector3Array()
	w = 0.0
	while w < RoadRamps.V_GORE:
		out.append(Vector3(RoadRamps.x_at(w), w, RoadRamps.y_at(w) + RoadRamps.LIFT))
		w += 0.5
	while w <= END_W:
		out.append(Vector3(lerpf(SLIP_X, LANE3, smoothstep(LEAD_OUT.x, LEAD_OUT.y, w)), w, 0.0))
		w += 0.5
	for p in out:
		raw.append(Vector3(-p.x, -p.y, p.z) if far else p)
	# one point a metre, by length along the ground
	var pts := PackedVector3Array()
	var ring_d := Vector2(-1.0, -1.0)
	var run := 0.0
	var next := 0.0
	for i in raw.size():
		if i > 0:
			run += Vector2(raw[i].x - raw[i - 1].x, raw[i].y - raw[i - 1].y).length()
		if i == ring0:
			ring_d.x = run
		if i == ring1:
			ring_d.y = run
		while run >= next:
			if i == 0:
				pts.append(raw[0])
			else:
				var seg := Vector2(raw[i].x - raw[i - 1].x, raw[i].y - raw[i - 1].y).length()
				var f := 1.0 - (run - next) / maxf(seg, 1e-6)
				pts.append(raw[i - 1].lerp(raw[i], f))
			next += STEP
	var n := pts.size()
	var yaw := PackedFloat32Array()
	var pitch := PackedFloat32Array()
	var cap := PackedFloat32Array()
	yaw.resize(n)
	pitch.resize(n)
	cap.resize(n)
	for i in n:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[mini(i + 1, n - 1)]
		var dx := p1.x - p0.x
		var dw := p1.y - p0.y
		yaw[i] = atan2(-dx, dw)
		pitch[i] = atan2(p1.z - p0.z, Vector2(dx, dw).length())
		var p := pts[i]
		var aw := absf(p.y)
		var v := INF
		if p.z > 0.05 or aw < RoadRamps.V_GORE:
			v = RAMP_V
		if (p.z > DECK_Y - 0.5 and absf(Vector2(p.x, p.y).length() - R) < 0.5) or aw < SLOW_W:
			v = RING_V
		cap[i] = v
	# plan back: never more than PLAN_DECEL to make the next limit
	for i in range(n - 2, -1, -1):
		cap[i] = minf(cap[i], sqrt(cap[i + 1] * cap[i + 1] + 2.0 * PLAN_DECEL * STEP))
	if kind == STRAIGHT:
		ring_d = Vector2(-1.0, -1.0)
	# past the top: the ring's end, or for STRAIGHT the ramp's top
	var mid := ring_d.y if kind != STRAIGHT else RoadRamps.V_GORE + 10.0
	var gw := -1.0
	var zone := -1.0
	var merge := -1.0
	var road_up := -1.0
	var road_down := -1.0
	for i in n:
		var p := pts[i]
		var di := float(i) * STEP
		if gw < 0.0 and p.y >= -GIVE_WAY_W:
			gw = di
		if zone < 0.0 and p.y >= -ZONE_W:
			zone = di
		if road_up < 0.0 and p.z > 0.05:
			road_up = di
		if di > mid and p.z <= 0.05:
			if road_down < 0.0:
				road_down = di
			var wo := -p.y if far else p.y
			if merge < 0.0 and wo >= LEAD_OUT.x:
				merge = di
	return {"kind": kind, "side": 1, "pts": pts, "yaw": yaw, "pitch": pitch, "cap": cap,
		"end": float(n - 1) * STEP, "gw": gw, "zone": zone, "merge": merge, "ring": ring_d,
		"road_up": road_up, "road_down": road_down,
		"p": Vector2(R, 0.0), "p_angle": 0.0, "zone_angle": -asin(ZONE_W / R),
		"end_dir": 1.0 if far else -1.0, "end_x": -LANE3 if far else LANE3}

## The same route from the -1 carriageway: turned half a circle about the
## ring's centre (anticlockwise stays anticlockwise).
static func _turned(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	var pts := PackedVector3Array()
	for p in (r.pts as PackedVector3Array):
		pts.append(Vector3(-p.x, -p.y, p.z))
	var yaw := PackedFloat32Array()
	for y in (r.yaw as PackedFloat32Array):
		yaw.append(wrapf(y + PI, -PI, PI))
	out["pts"] = pts
	out["yaw"] = yaw
	out["side"] = -1
	out["p"] = -(r.p as Vector2)
	out["p_angle"] = PI
	out["zone_angle"] = float(r.zone_angle) + PI
	out["end_dir"] = -float(r.end_dir)
	out["end_x"] = -float(r.end_x)
	return out

# ---------- reading a route ----------

## (x, w, y) at distance d along the route.
static func at(r: Dictionary, d: float) -> Vector3:
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var f := clampf(d / STEP, 0.0, float(n - 1))
	var i := mini(floori(f), n - 2)
	return pts[i].lerp(pts[i + 1], f - float(i))

static func yaw_at(r: Dictionary, d: float) -> float:
	var yaw: PackedFloat32Array = r.yaw
	var n := yaw.size()
	var f := clampf(d / STEP, 0.0, float(n - 1))
	var i := mini(floori(f), n - 2)
	return lerp_angle(yaw[i], yaw[i + 1], f - float(i))

static func pitch_at(r: Dictionary, d: float) -> float:
	var pitch: PackedFloat32Array = r.pitch
	return pitch[clampi(roundi(d / STEP), 0, pitch.size() - 1)]

static func cap_at(r: Dictionary, d: float) -> float:
	var cap: PackedFloat32Array = r.cap
	return cap[clampi(floori(d / STEP), 0, cap.size() - 1)]

## The distance along the route of the route point nearest (x, w), searched
## from `back` metres behind `d_guess` to `fwd` ahead.
static func project(r: Dictionary, x: float, w: float, d_guess: float, back := 4.0, fwd := 10.0) -> float:
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var i0 := clampi(floori((d_guess - back) / STEP), 0, n - 1)
	var i1 := clampi(ceili((d_guess + fwd) / STEP), 0, n - 1)
	var best := INF
	var bi := i0
	for i in range(i0, i1 + 1):
		var q := pts[i]
		var dd := (q.x - x) * (q.x - x) + (q.y - w) * (q.y - w)
		if dd < best:
			best = dd
			bi = i
	# refine between the neighbours
	var a := pts[maxi(bi - 1, 0)]
	var b := pts[mini(bi + 1, n - 1)]
	var ab := Vector2(b.x - a.x, b.y - a.y)
	var t := clampf(Vector2(x - a.x, w - a.y).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (float(maxi(bi - 1, 0)) + t * float(mini(bi + 1, n - 1) - maxi(bi - 1, 0))) * STEP

## Distance along the route, ahead of d (within `reach`), at which the point
## (x, w, y) is on it: within ON_ROUTE across and ON_DECK_Y up. INF if it is
## not. Every second point is enough at ON_ROUTE wide.
static func ahead_on(r: Dictionary, d: float, x: float, w: float, y: float, reach: float) -> float:
	var pts: PackedVector3Array = r.pts
	var n := pts.size()
	var i0 := clampi(floori(d / STEP), 0, n - 1)
	var i1 := clampi(ceili((d + reach) / STEP), 0, n - 1)
	var lim := ON_ROUTE * ON_ROUTE
	var i := i0
	while i <= i1:
		var q := pts[i]
		var dd := (q.x - x) * (q.x - x) + (q.y - w) * (q.y - w)
		if dd < lim and absf(q.z - y) < ON_DECK_Y:
			return float(i) * STEP - d
		# far off: skip ahead by what it takes to get close
		i += maxi(2, floori((sqrt(dd) - ON_ROUTE) / STEP))
	return INF

## Whether d is at road height (the slip lanes and the main road).
static func road_level(r: Dictionary, d: float) -> bool:
	return d < float(r.road_up) or d >= float(r.road_down)

## Whether d is on the ring proper (HALF and LAP only).
static func on_ring(r: Dictionary, d: float) -> bool:
	var rd: Vector2 = r.ring
	return rd.x >= 0.0 and d >= rd.x and d < rd.y

## The ring's length round the stretch where a ramp overlaps it (both sides
## of where they meet), metres.
static func zone_arc() -> float:
	return 2.0 * asin(ZONE_W / R) * R

## Seconds to cover `dist` metres from speed v, pulling away at GIVE_WAY_A up
## to RING_V.
static func time_to(dist: float, v: float) -> float:
	v = clampf(v, 0.0, RING_V)
	if dist <= 0.0:
		return 0.0
	var t_up := (RING_V - v) / GIVE_WAY_A
	var d_up := (v + RING_V) * 0.5 * t_up
	if dist <= d_up:
		return (sqrt(v * v + 2.0 * GIVE_WAY_A * dist) - v) / GIVE_WAY_A
	return t_up + (dist - d_up) / RING_V

## Metres round the ring (anticlockwise) from (x, w) to the conflict point at
## angle `p_angle`, for something on the ring's lane; INF when (x, w, y) is
## not on the ring's lane.
static func ring_arc_to(x: float, w: float, y: float, p_angle: float) -> float:
	if absf(y - DECK_Y) > ON_DECK_Y or absf(Vector2(x, w).length() - R) > 2.5:
		return INF
	return fposmod(p_angle - atan2(w, x), TAU) * R
