extends RefCounted

# Ramps at a ring site (ring sites R1, 2026-10-11).
#
# Every ring site on the map (RoadMap.rings) has, on each side of the road, a
# ramp up from the slip lane to a pad RAMP_H above the road and a ramp back
# down to the slip lane after it. In R1 the pad is a temporary paved bulb
# where a car can turn; R2 replaces the two pads with the ring over the road
# and the ramps join that instead (their top runs along x = X_TOP, where the
# ring's lane will be, 35 m out).
#
# A site is the same on both sides of the road and either way along it, so
# one quarter is described here and mirrored: `v` is metres from the ring's
# centre along the road (0 .. V_GORE), x metres out from the centre line.
#
#   v 200 (gore)  the ramp's deck starts on the slip lane, at road height
#   v 170 (nose)  the deck has moved a lane out and starts to climb; barriers
#                 on both sides from here, a crash cushion on the nose where
#                 traffic drives at it
#   v  70         the deck is as far out as it goes (X_TOP)
#   v  22         the climb ends at RAMP_H, where the deck meets the pad
#   v   0         the pad's widest point; the other ramp mirrors from here
#
# The climb is RAMP_H over 148 m with eased ends: 5.4 % at its steepest.
#
# Built per chunk like the roadside kit: laid out in the straight road
# description and put through the chunk's centreline frame, so it bends with
# the road (the ramp chunks are pinned level, RoadMap.PIN_LEVEL, so the grade
# is the ramp's own). Everything is decided from the chunk number and the
# map, so a pooled chunk rebuilt later matches.
#
# Cost: one mesh with one material (vertex colours; lamp heads and paint glow
# through the colour's alpha), one MultiMesh of fake light pools, a trimesh
# for the deck (group "Road": wheels and bodies) and boxes for the barriers
# (CarSpec.make_wall, from the ground to above the deck, so they are also the
# retaining walls). Chunks with no ramp show nothing and collide with nothing.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RoadMap := preload("res://scripts/world/road_map.gd")

const RoadPaint := preload("res://scripts/world/road_paint.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")

const L := 50.0
## The outside lane's outer edge on the plain 4-lane road (_lane_w(4)).
const X_LANE := 13.2
const HALF := RoadMap.AUX_W / 2.0
## Where the ramp's top runs: the ring's lane (R2), metres out.
const X_TOP := 31.5
const RAMP_H := 7.0
const V_GORE := RoadMap.RING_GORE
const V_NOSE := 170.0
## The deck has finished moving out by here, and finished climbing by V_TOP.
const V_LAT := 70.0
const V_TOP := 22.0
const EASE_IN := 20.0
const EASE_OUT := 15.0
## The pad: a bulb this far out and this big.
const PAD_X := 46.0
const PAD_R := 25.0
## The deck sits this far above the road where the two overlap.
const LIFT := 0.02
const PAINT_LIFT := 0.012
const ROW := 5.0
## Strips across a ramp's deck where it runs over the ring's leaning lane.
const TWIST_STRIPS := 4
const BARRIER_W := 0.3
const BARRIER_H := 0.85
const KERB_W := 0.25
const KERB_H := 0.12
## How far the walls reach below the road.
const SKIRT := 0.4
## The outside barrier grows from nothing over this much after the gore.
const BARRIER_TAPER := 5.0
const CUSHION_LEN := 3.5
const CUSHION_W := 0.7
const LAMP_VS: Array[float] = [185.0, 145.0, 105.0, 65.0]
const LAMP_PAD_DEG: Array[float] = [20.0, 70.0]
const LAMP_H := 6.5
const LAMP_ARM := 1.8
const POOL_CAPACITY := 12
const POOL_SIZE := Vector2(9.0, 13.0)
## The out-of-bounds wall beside the ramps, metres out, by |k| band.
const BOUND_NOSE := 27.0
const BOUND_RAMP := 38.0
const BOUND_PAD := 75.0

const C_DECK := Color(0.105, 0.105, 0.115, 0.0)
const C_WALL := Color(0.3, 0.295, 0.28, 0.0)
## The walls' colour while laying out (RingSite sets the district's).
static var wall_colour := C_WALL
const C_KERB := Color(0.42, 0.41, 0.39, 0.0)
const C_PAINT := Color(0.82, 0.82, 0.78, 0.07)
const C_POLE := Color(0.2, 0.2, 0.21, 0.0)
const C_HEAD := Color(1.0, 0.55, 0.2, 1.0)
const C_CUSHION := Color(0.86, 0.62, 0.12, 0.03)
const C_CUSHION_BAND := Color(0.07, 0.07, 0.07, 0.0)
## Kerb studs (ramps doc 2.5): small amber dots on the kerb at every row of a
## ramp and every piece of the ring's rims, what you steer by in the dark.
const C_STUD := Color(1.0, 0.62, 0.22, 0.45)
const STUD := 0.14
## The expansion joint where a ramp's deck meets the bridge slab (doc 2.2):
## a ridge JOINT_H high and JOINT_W wide across the lane at V_TOP, in the
## drawn deck and its collision, so each axle goes "ka-thunk" over it
## (SurfaceMap.Kind.JOINT, CarAudio.hit_deck_joint).
const JOINT_H := 0.015
const JOINT_W := 0.4
## The give-way row (doc 2.4): triangles painted across an up-ramp's deck
## this far before the ring's rim, pointing into the ring.
const GIVE_WAY_V := 1.0
const GIVE_WAY_N := 5
const GIVE_WAY_LEN := 0.9
## The painted marks (RoadPaint decals): the left-curving arrow this far
## from the ring's centre on an up-ramp, and the exit's word on the slip
## lane this far before the gore (about 50 m).
const ARROW_V := 40.0
const EXIT_WORD_BEFORE_GORE := 45.0

## The nose markers (alpha NOSE_ALPHA, RingSite.C_NOSE) pulse once a second
## (doc 2.5: "something is here" from 300 m), between BLINK_LOW and full. A
## slow sine, well under the photosensitive band (2.5-15 Hz, SAFETY), and
## nothing else in the colour's alpha range blinks.
const NOSE_ALPHA := 0.6
const BLINK_HZ := 1.0
const BLINK_LOW := 0.4
const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	float nose = step(0.55, COLOR.a) * step(COLOR.a, 0.65);
	float pulse = mix(1.0, 0.4 + 0.6 * (0.5 + 0.5 * sin(TIME * 6.2831853 * 1.0)), nose);
	EMISSION = COLOR.rgb * (0.07 + COLOR.a * 4.0 * pulse);
}
"""

static var enabled := true
## R2: the ramps join the ring (RingSite) and there is no pad. false = R1's
## temporary pads (tests of the pad alone).
static var ring := true

## The ring (R2): its lane's inner and outer edge, metres from its centre.
const RING_IN := 28.0
const RING_OUT := 35.0
## A ramp's deck and outer barrier run to where its outer edge has crossed
## the ring's rim, and its inner barrier to where its inner edge has: the
## mouth in the rim is between the two (whole rim pieces, see RingSite).
const RING_SEG_DEG := 5.625
const V_RING_OUT := 10.16    # RING_OUT * sin(3 pieces)
const V_RING_IN := 19.44     # RING_OUT * sin(6 pieces)
## The out-of-bounds wall beside the ring (and its spur).
const BOUND_RING := 56.0
## The ring's lane leans in (Roy, 1502, 2026-10-13): its inside edge is BANK
## lower per metre across than its outside edge, 4 %: 28 cm over the 7 m lane.
## The outside edge stays at RAMP_H, where the ramps and the spur meet it, and
## where a ramp's deck runs over the lane it takes the same lean, so each ramp
## twists into the ring over its last ~10 m. Only the deck's shape changes
## (0.04 g at the ring's speeds): the car leans in, the horizon tilts with it.
const BANK := 0.04
static var _material: ShaderMaterial

# the chunk being laid out
static var _verts := PackedVector3Array()
static var _norms := PackedVector3Array()
static var _cols := PackedColorArray()
static var _faces_own := PackedVector3Array()   # deck collision, own side
static var _faces_onc := PackedVector3Array()   # and the oncoming side
static var _boxes: Array = []   # [Transform3D, Vector3 size]
static var _pools: Array = []   # Transform3D
static var _k := 0
static var _lam := 1.0
static var _side := 1.0
## RingSite lays the ring out with the same tools in its own flat space
## (x across, y up, -z the way the chunks count) instead of a chunk's frame.
static var _flat := false
## Added to v in flat space (PocketSite lays a street's far arm out with the
## arm's own code, shifted to the far ring).
static var flat_v_off := 0.0

static func begin_flat() -> void:
	_verts = PackedVector3Array()
	_norms = PackedVector3Array()
	_cols = PackedColorArray()
	_faces_own = PackedVector3Array()
	_faces_onc = PackedVector3Array()
	_boxes = []
	_pools = []
	_k = 0
	_lam = 1.0
	_side = 1.0
	_flat = true
	flat_v_off = 0.0

## What was laid out since begin_flat(): {arrays, faces, boxes, pools}.
static func end_flat() -> Dictionary:
	_flat = false
	flat_v_off = 0.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _cols
	return {"arrays": arrays, "faces": _faces_own, "boxes": _boxes, "pools": _pools}

# ---------- the shape ----------

## Metres out of the deck's centre line, v metres from the ring's centre.
static func x_at(v: float) -> float:
	if v <= V_LAT:
		return X_TOP
	var t := clampf((v - V_LAT) / (V_GORE - V_LAT), 0.0, 1.0)
	return lerpf(X_TOP, X_LANE + HALF, t * t * (3.0 - 2.0 * t))

## The steepest the climb gets.
static func max_grade() -> float:
	return RAMP_H / (V_NOSE - V_TOP - (EASE_IN + EASE_OUT) * 0.5)

## Height of the deck above the road, v metres from the ring's centre.
static func y_at(v: float) -> float:
	var d := V_NOSE - v
	var run := V_NOSE - V_TOP
	if d <= 0.0:
		return 0.0
	if d >= run:
		return RAMP_H
	var g := max_grade()
	if d < EASE_IN:
		return g * d * d / (2.0 * EASE_IN)
	if d > run - EASE_OUT:
		return RAMP_H - g * (run - d) * (run - d) / (2.0 * EASE_OUT)
	return g * (d - EASE_IN * 0.5)

## How far the ring's deck is below RAMP_H, r metres from the ring's centre
## (0 at its outside edge and beyond; R1's pads are flat).
static func ring_drop(r: float) -> float:
	if not ring:
		return 0.0
	return BANK * clampf(RING_OUT - r, 0.0, RING_OUT - RING_IN)

## The expansion joint's ridge at v metres from the ring's centre: JOINT_H
## at V_TOP, nothing JOINT_W / 2 either side.
static func joint_lift(v: float) -> float:
	return JOINT_H * clampf(1.0 - absf(v - V_TOP) / (JOINT_W * 0.5), 0.0, 1.0) if ring else 0.0

## Height of a ramp's deck above the road at x metres out, v from the ring's
## centre: the climb, less the ring's lean where the deck runs over its lane,
## plus the joint's ridge.
static func deck_y(x: float, v: float) -> float:
	return y_at(v) + LIFT - ring_drop(Vector2(x, v).length()) + joint_lift(v)

## The ring deck's up direction at angle `a` (radians anticlockwise from the
## +x point), in the ring's flat space (x across, y up, -z the way the chunks
## count): tipped toward the centre by the lean.
static func ring_normal(a: float) -> Vector3:
	return Vector3(-BANK * cos(a), 1.0, BANK * sin(a)).normalized() if ring else Vector3.UP

## Where the lane ends and the pad begins (the pad's edge at the lane's outer edge).
static func v_pad() -> float:
	var dx := X_TOP + HALF - PAD_X
	return sqrt(PAD_R * PAD_R - dx * dx)

## Whether a ramp or pad stands beside this chunk.
static func zone(chunk_index: int) -> bool:
	return enabled and RoadMap.ramp_zone(chunk_index)

## The gore and nose chunks (the first and last of a site's ramp chunks):
## the road's own lamps and edge posts would stand in the ramp's lane.
static func nose(chunk_index: int) -> bool:
	if not zone(chunk_index):
		return false
	var k := RoadMap.ring_k(chunk_index)
	return k == -RoadMap.RAMP_CHUNKS or k == RoadMap.RAMP_CHUNKS - 1

## Whether a road lamp at chunk-local z of this chunk would stand under the
## ring's rim (its pole is taller than the bridge is high).
static func under_ring(chunk_index: int, z: float) -> bool:
	if not ring or not zone(chunk_index):
		return false
	var k := RoadMap.ring_k(chunk_index)
	if k != -1 and k != 0:
		return false
	var r := Vector2(17.0, float(k) * L - z).length()
	return r > RING_IN - 1.5 and r < RING_OUT + 1.5

## Where the out-of-bounds wall stands beside a ramp chunk, metres from the
## centre line (0 = no ramp here, the district's own line).
static func bound(chunk_index: int) -> float:
	if not zone(chunk_index):
		return 0.0
	var k := RoadMap.ring_k(chunk_index)
	var d := -k - 1 if k < 0 else k   # 0 at the pad .. 3 at the gore
	if d == 0:
		return BOUND_RING if ring else BOUND_PAD
	return BOUND_NOSE if d == RoadMap.RAMP_CHUNKS - 1 else BOUND_RAMP

## The pocket script (PocketSite), loaded when first asked for: it preloads
## this one, so this cannot preload it.
static var _pocket_script: Script

static func pocket_site() -> Script:
	if _pocket_script == null:
		_pocket_script = load("res://scripts/world/pocket_site.gd")
	return _pocket_script

## Where the out-of-bounds wall stands on `side` of a chunk a pocket (ramps
## doc step 7, RoadMap.POCKETS) reaches along: PocketSite.BOUND, or 0 where
## no pocket reaches. Beyond bound(): the chunk builder takes the larger.
static func pocket_bound(chunk_index: int, side: int) -> float:
	if not enabled or not ring or not RoadMap.is_loop():
		return 0.0
	var r := RoadMap.ring_at(chunk_index)
	if r < 0:
		return 0.0
	var pk := RoadMap.pocket_at(r, side)
	if pk.is_empty():
		return 0.0
	var ps := pocket_site()
	# the chunk's span, metres from the ring's centre, turned the arm's way
	var k := RoadMap.ring_k(chunk_index)
	var a := float(k) * L * float(pk.turn)
	var b := float(k + 1) * L * float(pk.turn)
	var lo := minf(a, b)
	var hi := maxf(a, b)
	if hi < -5.0 or lo >= float(ps.clear_v(pk)):
		return 0.0
	return float(ps.BOUND)

## A service street (PocketSite kind "street") along `side` of this chunk:
## the chunk's bounds (OffMapRescue) reach out to PocketSite.STREET_BOUND
## there, while the out-of-bounds wall and the buildings stay where they
## are: the street runs behind them, walled by its own kit. 0 where none.
static func street_bound(chunk_index: int, side: int) -> float:
	if not enabled or not ring or not RoadMap.is_loop():
		return 0.0
	var r := RoadMap.ring_at(chunk_index)
	if r < 0:
		return 0.0
	var pk := RoadMap.pocket_at(r, side)
	if pk.is_empty() or not RoadMap.is_street(pk):
		return 0.0
	var ps := pocket_site()
	var k := RoadMap.ring_k(chunk_index)
	var a := float(k) * L * float(pk.turn)
	var b := float(k + 1) * L * float(pk.turn)
	if maxf(a, b) < float(ps.STREET_V0) - 5.0 or minf(a, b) > float(ps.reach_v(pk)):
		return 0.0
	return float(ps.STREET_BOUND)

## Where a street's lane crosses the start of this chunk on `side`: the x
## range (out on that side) the boundary step wall leaves open there, or
## Vector2.ZERO where no street runs across it.
static func street_gap(chunk_index: int, side: int) -> Vector2:
	if street_bound(chunk_index, side) <= 0.0 or street_bound(chunk_index - 1, side) <= 0.0:
		return Vector2.ZERO
	var r := RoadMap.ring_at(chunk_index)
	var pk := RoadMap.pocket_at(r, side)
	var v := float(RoadMap.ring_k(chunk_index)) * L
	return pocket_site().lane_gap(pk, v)

## Where a point of a site is in road space: x metres out on `side` (+1 the
## carriageway driven the way the chunks count), `u` metres along the road
## from the ring's centre (+ = the way the chunks count), on the ramp or pad.
## Returns (x across signed, height above the road). Tests and put-back.
static func deck_point(side: int, u: float) -> Vector2:
	return Vector2(float(side) * x_at(absf(u)), deck_y(x_at(absf(u)), absf(u)))

# ---------- off the main road (R3) ----------
#
# A car on a ramp, the ring or a spur is "off the main road". place_of() says
# so from its position alone, against the site's footprint; game.gd keeps the
# player's in `player_place` every physics tick for traffic (which holds its
# flow while the player is up there), the police, the save and the put-back.
#
# A place: {} on the main road, else
#   site   index into RoadMap.rings()
#   id     the ring's id ("x3"): what the save writes
#   s      the ring's centre, metres along the road (the lap the car is on)
#   part   "ramp", "ring", "spur" or "pocket" (a pocket's arm or lot, step 7)
#   side   +1 / -1: which side of the road (ramps and spurs)
#   leg    -1 the ramp before the centre the way the chunks count, +1 after
#   v      ramps: metres from the ring's centre along the road
#   angle  ring: radians anticlockwise from the +x point (seen from above)
#   wrong_way  moving against the one way that part is driven (see wrong_way())

## How far over or under a deck a car's own height may read and still be on it.
const ON_DECK := 1.5
## Where the player is off the main road ({} on it). Written by game.gd.
static var player_place := {}

## The place of a point: `u` in road space (RoadFrame.unroll), `s` its metres
## along the road (RoadFrame.s_at(u.z)).
static func place_of(u: Vector3, s: float) -> Dictionary:
	if not enabled or not RoadMap.is_loop():
		return {}
	var near := RoadMap.ring_near(s)
	if int(near.index) < 0:
		return {}
	var w := s - float(near.s)
	var v := absf(w)
	if v > V_GORE and not pocket_reach(int(near.index), w):
		return {}
	var out := {"site": int(near.index), "id": String(RoadMap.rings()[int(near.index)].id), "s": float(near.s),
		"side": 1 if u.x >= 0.0 else -1, "leg": 1 if w >= 0.0 else -1, "v": v, "angle": 0.0, "wrong_way": false}
	if ring and absf(u.y - RAMP_H) < ON_DECK:
		var r := Vector2(u.x, w).length()
		if r > RING_IN - 0.5 and r < RING_OUT + 0.5:
			out["part"] = "ring"
			out["angle"] = fposmod(atan2(w, u.x), TAU)
			return out
		for spur in RoadMap.ring_spur_sides(int(near.index)):
			if u.x * float(spur) > RING_OUT and u.x * float(spur) < SPUR_REACH and v < 4.0:
				out["part"] = "spur"
				out["side"] = int(spur)
				return out
	# a pocket's arm and lot (ramps doc step 7): any height, its footprint
	if ring:
		var pk := RoadMap.pocket_at(int(near.index), 1 if u.x >= 0.0 else -1)
		if not pk.is_empty() and u.x * float(pk.side) > RING_OUT:
			var ps := pocket_site()
			var px := u.x * float(pk.side)
			if px < float(ps.BOUND) and u.y < RAMP_H + ON_DECK and ps.covers(pk, px, w):
				var dy := float(ps.deck_y_near(pk, px, w, u.y))
				if not is_inf(dy) and absf(u.y - dy) < ON_DECK:
					out["part"] = "pocket"
					out["side"] = int(pk.side)
					out["v"] = v
					return out
	if v > V_GORE:
		return {}
	if absf(absf(u.x) - x_at(v)) < HALF + 0.6 and absf(u.y - y_at(v)) < ON_DECK:
		out["part"] = "ramp"
		return out
	return {}

## How far out a spur's stub reaches (RingSite.SPUR_END, plus its barrier).
const SPUR_REACH := 50.5

## Whether a pocket off ring `index` reaches `w` metres from the ring's centre
## (signed, the way the chunks count).
static func pocket_reach(index: int, w: float) -> bool:
	for pk in RoadMap.pockets_of_ring(index):
		var t := w * float(pk.turn)
		if t > -5.0 and t < float(pocket_site().reach_v(pk)):
			return true
	return false

## Whether a car at `place` moving at `vel` (road space: RoadFrame.dir_to_road)
## is going the wrong way: clockwise on the ring, or against a ramp (each
## side's ramps are driven the way that carriageway flows). The same rule as
## on the highway; anticlockwise round the ring is the right way.
static func wrong_way(place: Dictionary, vel: Vector3, slack: float = 2.0) -> bool:
	if place.is_empty():
		return false
	var vw := -vel.z   # along the road, the way the chunks count
	match String(place.part):
		"ring":
			var a: float = place.angle
			return vel.x * -sin(a) + vw * cos(a) < -slack
		"ramp":
			return vw * float(place.side) < -slack
	return false

## Where to stand a car at `place`: on the ring's lane facing anticlockwise, on
## a ramp's centre line facing the way it is driven, on a spur facing the ring.
## World space, for the floating origin as it is now.
static func pose_of(place: Dictionary) -> Transform3D:
	var cz := float(RoadFrame.origin_index) * L - float(place.s)
	var ride := 0.5
	match String(place.part):
		"ring":
			# on the lane's centre line, tipped in with its lean
			var a: float = place.angle
			var xf := RoadFrame.pose(X_TOP * cos(a), RAMP_H - ring_drop(X_TOP) + ride, cz - X_TOP * sin(a), a)
			var road := xf.basis * Basis(Vector3.UP, a).inverse()
			var up := (road * ring_normal(a)).normalized()
			xf.basis = Basis(Quaternion(xf.basis.y.normalized(), up)) * xf.basis
			return xf
		"spur", "pocket":
			# at the top of the arm, facing the ring (a car put back from a
			# pocket drives back down the arm to get there, Roy 1506)
			var sd: float = float(place.side)
			return RoadFrame.pose(sd * (RING_OUT + 7.0), RAMP_H + ride, cz, PI * 0.5 * sd)
	var side: float = float(place.side)
	var v: float = clampf(float(place.v), 0.0, V_GORE)
	return RoadFrame.pose(side * x_at(v), deck_y(x_at(v), v) + ride, cz - float(place.leg) * v, 0.0 if side > 0.0 else PI)

## A place as the save writes it (plain values), and back. from_save() gives
## {} for a record this map no longer has a ring for.
static func to_save(place: Dictionary) -> Dictionary:
	if place.is_empty():
		return {}
	return {"id": place.id, "part": place.part, "side": place.side, "leg": place.leg, "v": place.v, "angle": place.angle}

static func from_save(rec: Dictionary, near_s: float) -> Dictionary:
	if not RoadMap.is_loop() or not (rec.get("id") is String) or not (rec.get("part") is String):
		return {}
	var rings := RoadMap.rings()
	for i in rings.size():
		if String(rings[i].id) == String(rec.id):
			var lap := RoadMap.length()
			var s := float(rings[i].s) + roundf((near_s - float(rings[i].s)) / lap) * lap
			return {"site": i, "id": String(rec.id), "s": s, "part": String(rec.part), "side": int(rec.get("side", 1)),
				"leg": int(rec.get("leg", 1)), "v": float(rec.get("v", 0.0)), "angle": float(rec.get("angle", 0.0)), "wrong_way": false}
	return {}

# ---------- nodes ----------

static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material

static func new_nodes(root: Node3D, pool_mesh: Mesh, pool_mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ramps"
	mi.mesh = ArrayMesh.new()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	root.add_child(mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pool_mesh
	mm.instance_count = POOL_CAPACITY
	mm.visible_instance_count = 0
	var pools := MultiMeshInstance3D.new()
	pools.name = "RampPools"
	pools.multimesh = mm
	pools.material_override = pool_mat
	pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pools)
	var deck := StaticBody3D.new()
	deck.name = "RampDeck"
	deck.add_to_group("Road")
	deck.set_meta(SurfaceMap.DECK_META, true)
	# One shape per side: a single shape's bounds would span the road between
	# them, and every car on it would be tested against the deck each tick.
	for shape_name in ["Shape", "ShapeOnc"]:
		var col := CollisionShape3D.new()
		col.name = shape_name
		var tri := ConcavePolygonShape3D.new()
		tri.backface_collision = true
		col.shape = tri
		col.disabled = true
		deck.add_child(col)
	root.add_child(deck)
	var walls := StaticBody3D.new()
	walls.name = "RampWalls"
	CarSpec.make_wall(walls)
	root.add_child(walls)

## What a built chunk's ramps consist of: {verts, faces, boxes, pools}. Tests
## compare a recycled chunk with a fresh one.
static func counts(root: Node3D) -> Dictionary:
	var mesh: ArrayMesh = (root.get_node(^"Ramps") as MeshInstance3D).mesh
	var verts := 0
	if mesh.get_surface_count() > 0:
		verts = (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var boxes := 0
	for c in root.get_node(^"RampWalls").get_children():
		if not (c as CollisionShape3D).disabled:
			boxes += 1
	var faces := 0
	for shape_name in ["Shape", "ShapeOnc"]:
		var tri: ConcavePolygonShape3D = (root.get_node(NodePath("RampDeck/" + shape_name)) as CollisionShape3D).shape
		@warning_ignore("integer_division")
		faces += tri.get_faces().size() / 3
	return {"verts": verts, "faces": faces, "boxes": boxes,
		"pools": (root.get_node(^"RampPools") as MultiMeshInstance3D).multimesh.visible_instance_count}

# ---------- per chunk ----------

## Lays out the chunk's ramps, pad, paint, lamps and their collision; hides
## and switches everything off on a chunk with none.
static func apply(root: Node3D, chunk_index: int) -> void:
	var ring := RoadMap.ring_at(chunk_index) if enabled else -1
	var had: bool = root.get_meta(&"ramps", false)
	if ring < 0:
		if had:
			_write(root, false)
			root.set_meta(&"ramps", false)
		return
	_verts = PackedVector3Array()
	_norms = PackedVector3Array()
	_cols = PackedColorArray()
	_faces_own = PackedVector3Array()
	_faces_onc = PackedVector3Array()
	_boxes = []
	_pools = []
	_k = RoadMap.ring_k(chunk_index)
	_lam = -1.0 if _k < 0 else 1.0
	var aux := RoadMap.aux(chunk_index)
	if RoadMap.ramp_zone(chunk_index):
		var d := -_k - 1 if _k < 0 else _k
		for side in [1.0, -1.0]:
			_side = side
			_leg(float(d) * L, float(d + 1) * L)
	elif aux.x > 0.0 or aux.y > 0.0:
		for side in [1.0, -1.0]:
			_side = side
			_slip_dashes(aux)
	_write(root, not _verts.is_empty())
	root.set_meta(&"ramps", true)

static func _write(root: Node3D, on: bool) -> void:
	var mi := root.get_node(^"Ramps") as MeshInstance3D
	var mesh: ArrayMesh = mi.mesh
	mesh.clear_surfaces()
	var decks: Array[CollisionShape3D] = [root.get_node(^"RampDeck/Shape"), root.get_node(^"RampDeck/ShapeOnc")]
	var walls: StaticBody3D = root.get_node(^"RampWalls")
	var mm: MultiMesh = (root.get_node(^"RampPools") as MultiMeshInstance3D).multimesh
	if not on:
		mi.visible = false
		for col in decks:
			col.disabled = true
			(col.shape as ConcavePolygonShape3D).set_faces(PackedVector3Array())
		for c in walls.get_children():
			(c as CollisionShape3D).disabled = true
		mm.visible_instance_count = 0
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.visible = true
	for i in 2:
		var f := _faces_own if i == 0 else _faces_onc
		(decks[i].shape as ConcavePolygonShape3D).set_faces(f)
		decks[i].disabled = f.is_empty()
	# Boxes are added the first time a chunk needs them and kept (switched
	# off) after that, like the barrier's.
	while walls.get_child_count() < _boxes.size():
		var c := CollisionShape3D.new()
		c.shape = BoxShape3D.new()
		walls.add_child(c)
	for i in walls.get_child_count():
		var c := walls.get_child(i) as CollisionShape3D
		if i < _boxes.size():
			(c.shape as BoxShape3D).size = _boxes[i][1]
			c.transform = _boxes[i][0]
			c.disabled = false
		else:
			c.disabled = true
	var n := mini(_pools.size(), mm.instance_count)
	for i in n:
		mm.set_instance_transform(i, _pools[i])
	mm.visible_instance_count = n

# ---------- laying out one quarter (one side, one chunk) ----------

## Chunk-local point for (x out on this side, y up, v from the ring's centre).
static func _p(x: float, y: float, v: float) -> Vector3:
	if _flat:
		return Vector3(x, y, -(v + flat_v_off))
	return RoadChunkBuilder._at(_side * x, y, float(_k) * L - _lam * v)

## A triangle seen from the `want` side (chunk-local direction).
static func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, want: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	# Godot's front faces are clockwise: geometric normal away from the viewer.
	if n.dot(want) > 0.0:
		var t := b
		b = c
		c = t
	else:
		n = -n
	_verts.append(a); _verts.append(b); _verts.append(c)
	_norms.append(n); _norms.append(n); _norms.append(n)
	_cols.append(col); _cols.append(col); _cols.append(col)

static func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, want: Vector3) -> void:
	_tri(a, b, c, col, want)
	_tri(b, d, c, col, want)

## A drivable quad: drawn and in the deck's collision.
static func _deck_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_quad(a, b, c, d, C_DECK, Vector3.UP)
	_deck_faces([a, b, c, b, d, c])

static func _deck_faces(pts: Array) -> void:
	if _side > 0.0:
		_faces_own.append_array(pts)
	else:
		_faces_onc.append_array(pts)

## A box given in the site's own description: centre (x, y, v), size (across,
## up, along).
static func _box(centre: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var pts: Array[Vector3] = []
	for dx in [-1.0, 1.0]:
		for dy in [-1.0, 1.0]:
			for dv in [-1.0, 1.0]:
				pts.append(_p(centre.x + dx * h.x, centre.y + dy * h.y, centre.z + dv * h.z))
	var mid := _p(centre.x, centre.y, centre.z)
	for f: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 4, 5], [2, 3, 6, 7], [0, 2, 4, 6], [1, 3, 5, 7]]:
		var fc: Vector3 = (pts[f[0]] + pts[f[1]] + pts[f[2]] + pts[f[3]]) * 0.25
		_quad(pts[f[0]], pts[f[1]], pts[f[2]], pts[f[3]], col, fc - mid)

static func _wall_box(a: Vector3, b: Vector3, bottom: float, top: float, width: float) -> void:
	var along := b - a
	along.y = 0.0
	var length := along.length()
	if length < 0.05 or top - bottom < 0.2:
		return
	var basis := Basis.looking_at(along / length, Vector3.UP)
	var mid := (a + b) * 0.5
	_boxes.append([Transform3D(basis, Vector3(mid.x, (bottom + top) * 0.5, mid.z)),
		Vector3(width, top - bottom, length + 0.1)])

## One edge of a deck: `pts` are (x, v, deck height) along it, `out` the unit
## direction (x, v) pointing off the deck at each, `hs` the barrier's height
## at each (0 = no barrier there yet). Draws kerb, barrier and the wall down
## to the ground, and adds the barrier's collision.
## `bottoms` (optional): how far down the wall goes at each point (a bridge:
## the deck's underside; default the ground). `faces` (optional): the colour
## of each piece's inside face.
static func _edge(pts: Array[Vector3], out: Array[Vector2], hs: PackedFloat32Array, bottoms: PackedFloat32Array = PackedFloat32Array(), faces: Array = []) -> void:
	for i in pts.size() - 1:
		if hs[i] <= 0.0 and hs[i + 1] <= 0.0:
			continue
		var rows: Array = []
		for j in [i, i + 1]:
			var p: Vector3 = pts[j]
			var o: Vector2 = out[j]
			var h: float = hs[j]
			var kh := minf(KERB_H, h)
			rows.append([
				_p(p.x - o.x * KERB_W, p.z, p.y - o.y * KERB_W),
				_p(p.x - o.x * KERB_W, p.z + kh, p.y - o.y * KERB_W),
				_p(p.x, p.z + kh, p.y),
				_p(p.x, p.z + h, p.y),
				_p(p.x + o.x * BARRIER_W, p.z + h, p.y + o.y * BARRIER_W),
				_p(p.x + o.x * BARRIER_W, bottoms[j] if j < bottoms.size() else -SKIRT, p.y + o.y * BARRIER_W),
			])
		var r0: Array = rows[0]
		var r1: Array = rows[1]
		var outward: Vector3 = (r0[4] as Vector3) - (r0[3] as Vector3)
		outward.y = 0.0
		var cols := [C_KERB, C_KERB, faces[i] if i < faces.size() else wall_colour, wall_colour, wall_colour]
		var wants := [-outward, Vector3.UP, -outward, Vector3.UP, outward]
		for q in 5:
			_quad(r0[q], r1[q], r0[q + 1], r1[q + 1], cols[q], wants[q])
		# a stud on the kerb's top at this row (and the last row's at the end)
		for j in ([i, i + 1] if i == pts.size() - 2 else [i]):
			if hs[j] > 0.0:
				_stud(pts[j], out[j], minf(KERB_H, hs[j]))
		var a: Vector3 = ((r0[3] as Vector3) + (r0[4] as Vector3)) * 0.5
		var b: Vector3 = ((r1[3] as Vector3) + (r1[4] as Vector3)) * 0.5
		_wall_box(a, b, minf((r0[5] as Vector3).y, (r1[5] as Vector3).y), maxf((r0[3] as Vector3).y, (r1[3] as Vector3).y), BARRIER_W)

## One kerb stud: a small amber dot on the kerb's top at `p` (x, v, deck
## height), the kerb being KERB_W wide on the deck side of `o`.
static func _stud(p: Vector3, o: Vector2, kh: float) -> void:
	var cx := p.x - o.x * KERB_W * 0.5
	var cv := p.y - o.y * KERB_W * 0.5
	var h := p.z + kh + 0.012
	var ax := Vector2(-o.y, o.x) * STUD * 0.5   # along the kerb
	var ao := o * STUD * 0.4                     # across it
	_quad(_p(cx - ax.x - ao.x, h, cv - ax.y - ao.y), _p(cx + ax.x - ao.x, h, cv + ax.y - ao.y),
		_p(cx - ax.x + ao.x, h, cv - ax.y + ao.y), _p(cx + ax.x + ao.x, h, cv + ax.y + ao.y), C_STUD, Vector3.UP)

## The give-way row across an up-ramp's deck: GIVE_WAY_N painted triangles
## side by side, pointing into the ring, GIVE_WAY_V before the rim where the
## inner barrier ends.
static func _give_way() -> void:
	var v0 := V_RING_IN + GIVE_WAY_V
	var x := x_at(v0)
	var w := (HALF * 2.0 - 0.9) / float(GIVE_WAY_N)
	for i in GIVE_WAY_N:
		var x0 := x - HALF + 0.45 + float(i) * w + 0.08
		var x1 := x0 + w - 0.16
		var xm := (x0 + x1) * 0.5
		var v1 := v0 - GIVE_WAY_LEN
		_tri(_p(x0, deck_y(x0, v0) + PAINT_LIFT, v0), _p(x1, deck_y(x1, v0) + PAINT_LIFT, v0),
			_p(xm, deck_y(xm, v1) + PAINT_LIFT, v1), C_PAINT, Vector3.UP)

## A flat painted quad on a surface at height y: x0..x1 across, v0..v1 along.
static func _paint(x0: float, x1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	_quad(_p(x0, y0 + PAINT_LIFT, v0), _p(x1, y0 + PAINT_LIFT, v0), _p(x0, y1 + PAINT_LIFT, v1), _p(x1, y1 + PAINT_LIFT, v1), C_PAINT, Vector3.UP)

static func _lamp(x: float, v: float, y: float, toward: Vector2, arm: float = LAMP_ARM) -> void:
	# pole outside the barrier, arm back over the deck, head and its pool
	var top := y + LAMP_H
	_box(Vector3(x, (top - SKIRT) * 0.5, v), Vector3(0.16, top + SKIRT, 0.16), C_POLE)
	var hx := x + toward.x * arm
	var hv := v + toward.y * arm
	_box(Vector3((x + hx) * 0.5, top, (v + hv) * 0.5), Vector3(absf(hx - x) + 0.1, 0.1, absf(hv - v) + 0.1), C_POLE)
	_box(Vector3(hx, top - 0.1, hv), Vector3(0.45, 0.12, 0.7), C_HEAD)
	# the pool lies on the deck under the head, tilted with the climb
	var px := x + toward.x * (arm + 1.2)
	var pv := v + toward.y * (arm + 1.2)
	var o := _p(px, y_at(pv) + LIFT + 0.03, pv)
	var ahead := _p(px, y_at(pv + 1.0) + LIFT + 0.03, pv + 1.0) - o
	var across := _p(px + 1.0, y_at(pv) + LIFT + 0.03, pv) - o
	var bz := ahead.normalized()
	var bx := across.normalized()
	var by := bz.cross(bx).normalized()
	if by.y < 0.0:   # the mirrored quarters: keep the pool face up and right-handed
		bx = -bx
		by = -by
	_pools.append(Transform3D(Basis(bx * POOL_SIZE.x, by, bz * POOL_SIZE.y), o))

## One side's ramp (and pad) between v_lo and v_hi metres from the centre.
static func _leg(v_lo: float, v_hi: float) -> void:
	var vp := V_RING_OUT if ring else v_pad()
	var pad := not ring and v_lo < vp
	# rows across the lane, every ROW metres, ending where the pad begins
	var vs := PackedFloat32Array()
	var v := v_hi
	while v > maxf(v_lo, vp) + 0.01:
		vs.append(v)
		v -= ROW
	vs.append(maxf(v_lo, vp))
	var extra := PackedFloat32Array()
	if ring and v_lo < V_RING_IN:
		# a row where the inner barrier ends, at the ring's rim
		extra.append(V_RING_IN)
	if ring:
		# rows for the joint's ridge where the deck meets the bridge slab
		for jv in [V_TOP - JOINT_W * 0.5, V_TOP, V_TOP + JOINT_W * 0.5]:
			if jv > v_lo and jv < v_hi and jv > vp:
				extra.append(jv)
	if not extra.is_empty():
		vs.append_array(extra)
		vs.sort()
		vs.reverse()
	# traffic drives at the nose on the leg it leaves the road by
	var diverge := _lam == -_side
	var inner: Array[Vector3] = []
	var outer: Array[Vector3] = []
	var inner_out: Array[Vector2] = []
	var outer_out: Array[Vector2] = []
	var inner_h := PackedFloat32Array()
	var outer_h := PackedFloat32Array()
	for i in vs.size():
		var x := x_at(vs[i])
		var past_rim: bool = ring and vs[i] < V_RING_IN - 0.01   # inside the ring's rim: its lane, no barrier
		if not past_rim:
			inner.append(Vector3(x - HALF, vs[i], deck_y(x - HALF, vs[i])))
			inner_out.append(Vector2(-1.0, 0.0))
		outer.append(Vector3(x + HALF, vs[i], deck_y(x + HALF, vs[i])))
		outer_out.append(Vector2(1.0, 0.0))
		# inside: from the nose (a short taper where traffic drives away from it)
		var ih := 0.0
		if vs[i] <= V_NOSE:
			ih = BARRIER_H if diverge else BARRIER_H * clampf((V_NOSE - vs[i]) / BARRIER_TAPER, 0.0, 1.0)
		if not past_rim:
			inner_h.append(ih)
		outer_h.append(BARRIER_H * clampf((V_GORE - vs[i]) / BARRIER_TAPER, 0.0, 1.0))
		if i > 0:
			var x0 := x_at(vs[i - 1])
			# across in strips where the deck runs over the leaning ring, so it
			# follows the lean (and lies on the ring's deck) instead of a chord
			var strips := TWIST_STRIPS if ring and vs[i] < RING_OUT else 1
			for k in strips:
				var t0 := float(k) / float(strips) * 2.0 - 1.0
				var t1 := float(k + 1) / float(strips) * 2.0 - 1.0
				_deck_quad(_p(x0 + t0 * HALF, deck_y(x0 + t0 * HALF, vs[i - 1]), vs[i - 1]), _p(x0 + t1 * HALF, deck_y(x0 + t1 * HALF, vs[i - 1]), vs[i - 1]),
					_p(x + t0 * HALF, deck_y(x + t0 * HALF, vs[i]), vs[i]), _p(x + t1 * HALF, deck_y(x + t1 * HALF, vs[i]), vs[i]))
			for e in [-1.0, 1.0]:
				var ex: float = e * (HALF - 0.45)
				_paint(x0 + ex - 0.06, x0 + ex + 0.06, vs[i - 1], vs[i], deck_y(x0 + ex, vs[i - 1]), deck_y(x + ex, vs[i]))
			# gore chevrons: bars across the wedge between the road and the deck
			if vs[i - 1] > V_NOSE:
				var vm := (vs[i - 1] + vs[i]) * 0.5
				var w := x_at(vm) - HALF - 0.1 - (X_LANE + 0.25)
				if w > 0.3:
					_paint(X_LANE + 0.25, X_LANE + 0.25 + w, vm + 0.4, vm - 0.4, 0.0, 0.0)
	if pad:
		# the lane's inside edge runs on to where the pad's edge crosses it
		var dxi := X_TOP - HALF - PAD_X
		var vi := sqrt(PAD_R * PAD_R - dxi * dxi)
		inner.append(Vector3(X_TOP - HALF, vi, RAMP_H + LIFT))
		inner_out.append(Vector2(-1.0, 0.0))
		inner_h.append(BARRIER_H)
	_edge(inner, inner_out, inner_h)
	_edge(outer, outer_out, outer_h)
	if diverge and v_hi >= V_NOSE and v_lo < V_NOSE:
		_cushion()
	if diverge and ring and v_lo < V_RING_IN + GIVE_WAY_V and v_hi >= V_RING_IN + GIVE_WAY_V:
		_give_way()
	for lv in LAMP_VS:
		if lv > v_lo and lv <= v_hi and lv > vp:
			_lamp(x_at(lv) + HALF + BARRIER_W + 0.15, lv, y_at(lv), Vector2(-1.0, 0.0))
	if pad:
		_pad()

## The crash cushion on the nose: amber and dark bays, and one box to hit.
static func _cushion() -> void:
	var x := x_at(V_NOSE) - HALF - BARRIER_W * 0.5
	var bay := CUSHION_LEN / 5.0
	for i in 5:
		var band := i % 2 == 1
		_box(Vector3(x, BARRIER_H * 0.5, V_NOSE + (float(i) + 0.5) * bay),
			Vector3(CUSHION_W * (0.9 if band else 1.0), BARRIER_H, bay * 0.98), C_CUSHION_BAND if band else C_CUSHION)
	_wall_box(_p(x, 0.0, V_NOSE), _p(x, 0.0, V_NOSE + CUSHION_LEN), 0.0, BARRIER_H, CUSHION_W)

## The pad's half on this chunk: a fan from its centre, the kerb and barrier
## round its edge, two lamps.
static func _pad() -> void:
	var y := RAMP_H + LIFT
	var vp := v_pad()
	var a_out := acos((X_TOP + HALF - PAD_X) / PAD_R)   # where the lane's outer edge meets it
	var a_in := acos((X_TOP - HALF - PAD_X) / PAD_R)    # and its inner edge
	var rim: Array[Vector2] = []
	var outer: Array[Vector3] = []
	var outer_out: Array[Vector2] = []
	var n_out := 12
	for i in n_out + 1:
		var a := a_out * float(i) / float(n_out)
		rim.append(Vector2(PAD_X + PAD_R * cos(a), PAD_R * sin(a)))
		outer.append(Vector3(rim[i].x, rim[i].y, y))
		outer_out.append(Vector2(cos(a), sin(a)))
	rim.append(Vector2(X_TOP - HALF, vp))
	var inner: Array[Vector3] = []
	var inner_out: Array[Vector2] = []
	var n_in := 5
	for i in n_in + 1:
		var a := lerpf(a_in, PI, float(i) / float(n_in))
		rim.append(Vector2(PAD_X + PAD_R * cos(a), PAD_R * sin(a)))
		inner.append(Vector3(PAD_X + PAD_R * cos(a), PAD_R * sin(a), y))
		inner_out.append(Vector2(cos(a), sin(a)))
	var c := _p(PAD_X, y, 0.0)
	for i in rim.size() - 1:
		var a := _p(rim[i].x, y, rim[i].y)
		var b := _p(rim[i + 1].x, y, rim[i + 1].y)
		_tri(c, a, b, C_DECK, Vector3.UP)
		_deck_faces([c, a, b])
	var full := PackedFloat32Array()
	full.resize(maxi(outer.size(), inner.size()))
	full.fill(BARRIER_H)
	_edge(outer, outer_out, full.slice(0, outer.size()))
	_edge(inner, inner_out, full.slice(0, inner.size()))
	for deg in LAMP_PAD_DEG:
		var a := deg_to_rad(deg)
		var r := PAD_R + BARRIER_W + 0.15
		# a short arm: the box that draws it is square to the road, not to the rim
		_lamp(PAD_X + r * cos(a), r * sin(a), RAMP_H, Vector2(-cos(a), -sin(a)), 0.5)

## The painted marks (RoadPaint decals) on chunk `chunk_index`, in the
## chunk's straight description: [{x, y, z, basis, cd}], `y` above the road
## at (x, z) (a mark on a ramp's deck sits on the deck, tilted with its
## climb). On each up-ramp a left-curving arrow at ARROW_V, and the exit's
## word ("EXIT 5") on the slip lane EXIT_WORD_BEFORE_GORE before its gore.
static func paint_marks(chunk_index: int) -> Array:
	var out: Array = []
	var ri := RoadMap.ring_at(chunk_index) if enabled else -1
	if ri < 0:
		return out
	var k := RoadMap.ring_k(chunk_index)
	var lam := -1.0 if k < 0 else 1.0
	var d := -k - 1 if k < 0 else k
	for side in [1.0, -1.0]:
		if lam != -side:
			continue   # the up-ramp's leg on this side is the one traffic leaves the road by
		var yaw := 0.0 if side > 0.0 else PI
		if RoadMap.ramp_zone(chunk_index):
			if ARROW_V >= float(d) * L and ARROW_V < float(d + 1) * L:
				var m := RoadPaint.item("#LEFT", side * x_at(ARROW_V), float(k) * L - lam * ARROW_V, yaw)
				# the slope of the deck along the chunk's z: tilt the decal with it
				var dy := (y_at(ARROW_V - 1.0) - y_at(ARROW_V + 1.0)) * 0.5   # per metre of v, as v falls
				m["y"] = deck_y(x_at(ARROW_V), ARROW_V) + RoadPaint.PAINT_Y
				m["basis"] = Basis(Vector3.RIGHT, atan(-lam * dy)) * (m.basis as Basis)
				out.append(m)
		else:
			var v := V_GORE + EXIT_WORD_BEFORE_GORE
			var aux := RoadMap.aux(chunk_index)
			if v >= float(d) * L and v < float(d + 1) * L and minf(aux.x, aux.y) >= RoadMap.AUX_W * 0.9:
				var m := RoadPaint.item(PlaceNames.exit_word(int(RoadMap.rings()[ri].number)), side * (X_LANE + HALF), float(k) * L - lam * v, yaw)
				m["y"] = RoadPaint.PAINT_Y
				out.append(m)
	return out

## The broken line between the outside lane and the slip lane, on a chunk
## where the slip lane is at least half open.
static func _slip_dashes(aux: Vector2) -> void:
	# v runs away from the ring's centre on both halves; the chunk's own
	# start-to-end is the other way round before the ring.
	var d := -_k - 1 if _k < 0 else _k
	var v := float(d) * L + 1.5
	while v < float(d + 1) * L:
		var t := (v - float(d) * L) / L        # 0 at the end nearer the ring
		var w := lerpf(aux.y, aux.x, t) if _k < 0 else lerpf(aux.x, aux.y, t)
		if w >= RoadMap.AUX_W * 0.5:
			_paint(X_LANE - 0.1, X_LANE + 0.1, v, v + 3.0, 0.0, 0.0)
		v += 9.0
