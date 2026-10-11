extends RefCounted

# The tunnel and its trench (TN1): what a chunk draws where the map
# (road_map.gd) puts a tunnel. RoadChunkBuilder calls apply() for every
# chunk; off a dip it only hides what a recycled chunk may carry.
#
# A dip has two kinds of chunk (RoadMap.dip_at):
#
# - DIP_RAMP, the open trench: a retaining wall at each road edge from the
#   road up to the street, a parapet on top, and the pavement carried on at
#   street height behind it (the chunk's own kerb and pavement strips are
#   hidden; its buildings, lamps and walls are lifted to the street by the
#   builder). The ramp chunk next to a mouth also carries the cross street's
#   bridge deck over the trench, the lamp either side of the mouth, and the
#   light spilling out onto the road.
# - DIP_TUNNEL, under cover: two walls, a roof, a continuous light strip
#   along each wall, and one long wash of light on the road. The first and
#   last covered chunk each carry the building block the mouth is cut into
#   (a BuildingKit facade, like any downtown block).
#
# Everything here is decided from the chunk's place on the map and the edges
# the builder hands over, so a chunk rebuilt from the pool matches one built
# fresh and the same tunnel stands there every lap.
#
# Drawing. One ArrayMesh per chunk with up to three surfaces (concrete, the
# light strip, the additive light on the road), rewritten when a pooled chunk
# becomes a dip chunk; a MultiMesh of wall pieces would need a piece per
# height on the ramps. The concrete is unshaded with its light painted into
# the vertex colours (the game has no real lights along the road): warm and
# brightest at the strip inside, night-dark in the trench.
#
# Nothing in here blinks, and nothing bright repeats (SAFETY, photosensitive
# band 2.5-15 Hz): the light is one unbroken strip, not lamps. The only
# things that repeat along a wall are the strip's housing joints (thin,
# JOINT_DIM of the strip's brightness) and the grime (slow, GRIME of the
# wall's); tests/world/tunnel.gd holds both under FLICKER_MAX.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RoadMap := preload("res://scripts/world/road_map.gd")
const BuildingKit := preload("res://scripts/world/building_kit.gd")
const Districts := preload("res://scripts/world/districts.gd")

const L := 50.0
## Rows of the walls along a chunk, m. The deck and the spill are whole rows.
const ROW := 5.0
## Roof underside above the road, m.
const CLEAR_H := 5.0
const PARAPET_H := 1.0
const PARAPET_W := 0.35
## The cross street's bridge over the trench at each mouth: how far it
## reaches out from the mouth, its thickness, and how far the street is drawn
## to either side of the trench.
const DECK_LEN := 10.0
const DECK_T := 0.7
const CROSS_REACH := 45.0
## The light strip: its height on the wall, how far it stands off it, and
## its housings (a joint every JOINT_EVERY m, JOINT_W wide, at JOINT_DIM of
## the strip's brightness).
const STRIP_Y := Vector2(3.8, 4.1)
const STRIP_OUT := 0.06
const STRIP_ENERGY := 2.2
const JOINT_EVERY := 10.0
const JOINT_W := 0.16
const JOINT_DIM := 0.95
## Grime: how far the wall's brightness drifts along the tunnel (a share of
## it), over GRIME_WAVES metres and more.
const GRIME := 0.05
const GRIME_WAVES := Vector2(140.0, 57.0)
## The most any repeating thing here may change the brightness by.
const FLICKER_MAX := 0.1
## The building block a mouth is cut into: its length over the tunnel, how
## far it reaches past the building line each side, how much of it is below
## the street.
const BLOCK_LEN := 22.0
const BLOCK_SIDE := 16.0
const BLOCK_BELOW := 1.0
const POOL_Y := 0.05
## Light on the road this far out of a mouth, m.
const SPILL := 15.0
## The lamp either side of a mouth: post height above the parapet, head size.
const LAMP_POST := 2.6
const LAMP_HEAD := Vector3(0.6, 0.22, 0.34)
const LAMP_GLOW := 2.4

const SODIUM := Color(1.0, 0.55, 0.2)
## Concrete at night with no light of its own on it (the trench).
const TRENCH := Color(0.082, 0.076, 0.067)
const PAVEMENT := Color(0.07, 0.068, 0.064)
const ASPHALT := Color(0.04, 0.04, 0.044)
## Concrete under the strip, at its brightest.
const LIT := Color(0.6, 0.39, 0.185)
const POOL := Color(0.2, 0.108, 0.04)

static var _concrete_mat: StandardMaterial3D
static var _strip_mat: StandardMaterial3D
static var _pool_mat: StandardMaterial3D

static func concrete_mat() -> StandardMaterial3D:
	if _concrete_mat == null:
		_concrete_mat = StandardMaterial3D.new()
		_concrete_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_concrete_mat.vertex_color_use_as_albedo = true
		# Faces are few and seen from one side or the other as the car goes
		# in, through and out: both sides drawn, no winding to get wrong.
		_concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _concrete_mat

static func strip_mat() -> StandardMaterial3D:
	if _strip_mat == null:
		_strip_mat = StandardMaterial3D.new()
		_strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_strip_mat.vertex_color_use_as_albedo = true
		_strip_mat.albedo_color = Color(SODIUM.r * STRIP_ENERGY, SODIUM.g * STRIP_ENERGY, SODIUM.b * STRIP_ENERGY)
		_strip_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _strip_mat

static func pool_mat() -> StandardMaterial3D:
	if _pool_mat == null:
		_pool_mat = StandardMaterial3D.new()
		_pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_pool_mat.vertex_color_use_as_albedo = true
		_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_pool_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_pool_mat.disable_fog = true
	return _pool_mat

# ---------- where ----------

## Metres the road is below the street, every metre along the chunk (51
## values); empty off a dip. The street is the straight line between the two
## ends of the dip, so it is what the road would have been without it.
static func depths(chunk_index: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var span := RoadMap.dip_span(chunk_index)
	if span.y == 0:
		return out
	out.resize(int(L) + 1)
	var a := RoadFrame.align
	if a == null:
		return out  # a flat road: no dip to be in
	var h0 := a.start_height(span.x)
	var h1 := a.start_height(span.x + span.y)
	for i in out.size():
		var t := (float(chunk_index - span.x) * L + float(i)) / (float(span.y) * L)
		out[i] = maxf(lerpf(h0, h1, t) - a.height_at(chunk_index, float(i)), 0.0)
	return out

## Whether a mouth is at this chunk's start / end: the chunk is under cover
## and the one before / after is not.
static func mouth_at_start(chunk_index: int) -> bool:
	return RoadMap.dip_at(chunk_index) == RoadMap.DIP_TUNNEL and RoadMap.dip_at(chunk_index - 1) != RoadMap.DIP_TUNNEL

static func mouth_at_end(chunk_index: int) -> bool:
	return RoadMap.dip_at(chunk_index) == RoadMap.DIP_TUNNEL and RoadMap.dip_at(chunk_index + 1) != RoadMap.DIP_TUNNEL

## The cross street over the trench on this (ramp) chunk, as chunk-local z:
## Vector2(nearer the chunk's start, further). Vector2.ZERO when it has none.
static func cross_street(chunk_index: int) -> Vector2:
	if RoadMap.dip_at(chunk_index) != RoadMap.DIP_RAMP:
		return Vector2.ZERO
	if RoadMap.dip_at(chunk_index + 1) == RoadMap.DIP_TUNNEL:
		return Vector2(-(L - DECK_LEN), -L)
	if RoadMap.dip_at(chunk_index - 1) == RoadMap.DIP_TUNNEL:
		return Vector2(0.0, -DECK_LEN)
	return Vector2.ZERO

## Whether a building standing from z0 down to z1 (chunk-local) is in the
## cross street's way.
static func cleared(chunk_index: int, z0: float, z1: float) -> bool:
	var c := cross_street(chunk_index)
	return c != Vector2.ZERO and z1 < c.x + 1.0 and z0 > c.y - 1.0

## The wall's brightness drift at s metres round the loop (about 1).
static func grime(s: float, side: int) -> float:
	var ph := 1.7 if side > 0 else 4.1
	return 1.0 + GRIME * (0.62 * sin(s * TAU / GRIME_WAVES.x + ph) + 0.38 * sin(s * TAU / GRIME_WAVES.y + ph * 2.3))

## Brightness along the light strip at s metres into a chunk: 1, or
## JOINT_DIM on a housing joint.
static func strip_level(s: float) -> float:
	var m := fposmod(s, JOINT_EVERY)
	return JOINT_DIM if m < JOINT_W * 0.5 or m > JOINT_EVERY - JOINT_W * 0.5 else 1.0

# ---------- nodes ----------

class Buf extends RefCounted:
	var v := PackedVector3Array()
	var c := PackedColorArray()

	## A quad a-b-c-d (going round it), a colour per corner.
	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, ca: Color, cb: Color, c_c: Color, cd: Color) -> void:
		v.append(a)
		v.append(b)
		v.append(cc)
		v.append(a)
		v.append(cc)
		v.append(d)
		c.append(ca)
		c.append(cb)
		c.append(c_c)
		c.append(ca)
		c.append(c_c)
		c.append(cd)

	func flat(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color) -> void:
		quad(a, b, cc, d, col, col, col, col)

	## An upright box from `lo` to `hi` (chunk-local corners), one colour.
	func box(lo: Vector3, hi: Vector3, col: Color) -> void:
		var p := [
			Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
		for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
			flat(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col)

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if v.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_COLOR] = c
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

static func _new_nodes(root: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Tunnel"
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = ArrayMesh.new()
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(shell)
	for k in 2:
		var block := MeshInstance3D.new()
		block.name = "Block%d" % k
		block.mesh = BuildingKit.unit_box()
		block.visible = false
		holder.add_child(block)
	root.add_child(holder)
	return holder

## Chunk-local point x across the road, y straight up from the road surface,
## s metres into the chunk the builder is laying out.
static func _p(x: float, y: float, s: float) -> Vector3:
	var f := RoadChunkBuilder._frame(s)
	return f.origin + f.basis.x * x + Vector3(0.0, y, 0.0)

static func _mul(col: Color, k: float) -> Color:
	return Color(col.r * k, col.g * k, col.b * k, 1.0)

static func _dep(dep: PackedFloat32Array, s: float) -> float:
	var sc := clampf(s, 0.0, L)
	var i := mini(int(sc), int(L) - 1)
	return lerpf(dep[i], dep[i + 1], sc - float(i))

## Lays out chunk `chunk_index`'s tunnel or trench. `wall` is where the walls
## stand, |x| from the centre line: [own at the chunk's start, own at its end,
## oncoming start, oncoming end]; `out` the same for the building line.
## Called by RoadChunkBuilder._apply with its centreline frames in place.
static func apply(root: Node3D, chunk_index: int, wall: PackedFloat32Array, out: PackedFloat32Array) -> void:
	var kind := RoadMap.dip_at(chunk_index)
	var holder := root.get_node_or_null(^"Tunnel") as Node3D
	if kind == RoadMap.DIP_NONE:
		if holder != null:
			holder.visible = false
		root.set_meta(&"tunnel", {})
		return
	if holder == null:
		holder = _new_nodes(root)
	holder.visible = true
	var dep := depths(chunk_index)
	var concrete := Buf.new()
	var strip := Buf.new()
	var pool := Buf.new()
	var s_lap := float(RoadMap.lap_chunk(chunk_index)) * L
	var rows := int(L / ROW)
	var deck := cross_street(chunk_index)
	for b in 2:
		(holder.get_node(NodePath("Block%d" % b)) as MeshInstance3D).visible = false
	# What a test can read back (a headless run keeps no mesh data to look at).
	var n_walls := 0
	var n_blocks := 0
	var strip_levels := PackedFloat32Array()
	var wall_levels := PackedFloat32Array()
	if kind == RoadMap.DIP_TUNNEL:
		for side: int in [1, -1]:
			var sx := float(side)
			var w0: float = wall[0] if side == 1 else wall[2]
			var w1: float = wall[1] if side == 1 else wall[3]
			# the wall: floor, dado, under the strip, roof
			var ys: Array[float] = [-0.1, 1.1, 3.4, CLEAR_H]
			var ks: Array[float] = [0.3, 0.55, 1.0, 0.72]
			for r in rows:
				var sa := float(r) * ROW
				var sb := sa + ROW
				var xa := lerpf(w0, w1, sa / L) * sx
				var xb := lerpf(w0, w1, sb / L) * sx
				var ga := grime(s_lap + sa, side)
				var gb := grime(s_lap + sb, side)
				if side == 1:
					wall_levels.append(ga)
					if r == rows - 1:
						wall_levels.append(gb)
				for j in ys.size() - 1:
					concrete.quad(_p(xa, ys[j], sa), _p(xb, ys[j], sb), _p(xb, ys[j + 1], sb), _p(xa, ys[j + 1], sa),
						_mul(LIT, ks[j] * ga), _mul(LIT, ks[j] * gb), _mul(LIT, ks[j + 1] * gb), _mul(LIT, ks[j + 1] * ga))
				n_walls += 1
			# the light strip: one unbroken band, a thin joint between housings
			var cuts := PackedFloat32Array()
			var n_joints := int(L / JOINT_EVERY)
			for j in n_joints + 1:
				var sj := float(j) * JOINT_EVERY
				if sj - JOINT_W * 0.5 > 0.0:
					cuts.append(sj - JOINT_W * 0.5)
				if sj + JOINT_W * 0.5 < L:
					cuts.append(sj + JOINT_W * 0.5)
			var prev := 0.0
			cuts.append(L)
			for cut in cuts:
				var k := strip_level((prev + cut) * 0.5)
				if side == 1:
					strip_levels.append(k)
				var xa2 := (lerpf(w0, w1, prev / L) - STRIP_OUT) * sx
				var xb2 := (lerpf(w0, w1, cut / L) - STRIP_OUT) * sx
				var col := Color(k, k, k, 1.0)
				strip.flat(_p(xa2, STRIP_Y.x, prev), _p(xb2, STRIP_Y.x, cut), _p(xb2, STRIP_Y.y, cut), _p(xa2, STRIP_Y.y, prev), col)
				prev = cut
		# the roof, and the one long wash of light on the road
		var roof_k: Array[float] = [0.6, 0.4, 0.2, 0.4, 0.6]
		var pool_k: Array[float] = [1.0, 0.8, 0.55, 0.8, 1.0]
		for r in rows:
			var sa := float(r) * ROW
			var sb := sa + ROW
			var xa := _across(wall, sa)
			var xb := _across(wall, sb)
			for j in 4:
				concrete.quad(_p(xa[j], CLEAR_H, sa), _p(xb[j], CLEAR_H, sb), _p(xb[j + 1], CLEAR_H, sb), _p(xa[j + 1], CLEAR_H, sa),
					_mul(LIT, roof_k[j]), _mul(LIT, roof_k[j]), _mul(LIT, roof_k[j + 1]), _mul(LIT, roof_k[j + 1]))
				pool.quad(_p(xa[j], POOL_Y, sa), _p(xb[j], POOL_Y, sb), _p(xb[j + 1], POOL_Y, sb), _p(xa[j + 1], POOL_Y, sa),
					_mul(POOL, pool_k[j]), _mul(POOL, pool_k[j]), _mul(POOL, pool_k[j + 1]), _mul(POOL, pool_k[j + 1]))
		# the block each mouth is cut into
		if mouth_at_start(chunk_index):
			_block(holder.get_node(^"Block0") as MeshInstance3D, chunk_index, 0, 0.0, BLOCK_LEN, dep, out)
			n_blocks += 1
		if mouth_at_end(chunk_index):
			_block(holder.get_node(^"Block1") as MeshInstance3D, chunk_index, 1, L - BLOCK_LEN, L, dep, out)
			n_blocks += 1
	else:
		var s_deck0 := -deck.x   # metres into the chunk, when there is a deck
		var s_deck1 := -deck.y
		var has_deck := deck != Vector2.ZERO
		for side: int in [1, -1]:
			var sx := float(side)
			var w0: float = wall[0] if side == 1 else wall[2]
			var w1: float = wall[1] if side == 1 else wall[3]
			var o0: float = out[0] if side == 1 else out[2]
			var o1: float = out[1] if side == 1 else out[3]
			for r in rows:
				var sa := float(r) * ROW
				var sb := sa + ROW
				var xa := lerpf(w0, w1, sa / L) * sx
				var xb := lerpf(w0, w1, sb / L) * sx
				var da := _dep(dep, sa)
				var db := _dep(dep, sb)
				var ga := grime(s_lap + sa, side)
				var gb := grime(s_lap + sb, side)
				var under := has_deck and sa >= s_deck0 - 0.01 and sb <= s_deck1 + 0.01
				# the retaining wall, road to street
				concrete.quad(_p(xa, -0.1, sa), _p(xb, -0.1, sb), _p(xb, db, sb), _p(xa, da, sa),
					_mul(TRENCH, 0.7 * ga), _mul(TRENCH, 0.7 * gb), _mul(TRENCH, gb), _mul(TRENCH, ga))
				n_walls += 1
				if under:
					continue  # the deck stands on the wall here
				# parapet: face, top, back; then the pavement at street height
				var pa := xa + PARAPET_W * sx
				var pb := xb + PARAPET_W * sx
				concrete.quad(_p(xa, da, sa), _p(xb, db, sb), _p(xb, db + PARAPET_H, sb), _p(xa, da + PARAPET_H, sa),
					_mul(TRENCH, ga), _mul(TRENCH, gb), _mul(TRENCH, 1.15 * gb), _mul(TRENCH, 1.15 * ga))
				concrete.flat(_p(xa, da + PARAPET_H, sa), _p(xb, db + PARAPET_H, sb), _p(pb, db + PARAPET_H, sb), _p(pa, da + PARAPET_H, sa), _mul(TRENCH, 1.35))
				concrete.flat(_p(pa, da + PARAPET_H, sa), _p(pb, db + PARAPET_H, sb), _p(pb, db, sb), _p(pa, da, sa), _mul(TRENCH, 0.9))
				concrete.flat(_p(pa, da, sa), _p(pb, db, sb), _p(lerpf(o0, o1, sb / L) * sx, db, sb), _p(lerpf(o0, o1, sa / L) * sx, da, sa), PAVEMENT)
			# where the trench begins and ends: a parapet across the pavement
			for end: float in [0.0, L]:
				var outside := RoadMap.dip_at(chunk_index - 1 if end == 0.0 else chunk_index + 1) == RoadMap.DIP_NONE
				if not outside:
					continue
				var s1 := end
				var s2 := end + (PARAPET_W if end == 0.0 else -PARAPET_W)
				var xw := lerpf(w0, w1, end / L) * sx
				var xo := lerpf(o0, o1, end / L) * sx
				var d := _dep(dep, end)
				var a := _p(xw, d - 0.1, minf(s1, s2))
				var b := _p(xo, d + PARAPET_H, maxf(s1, s2))
				concrete.box(Vector3(minf(a.x, b.x), a.y, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), b.y, maxf(a.z, b.z)), _mul(TRENCH, 1.15))
		if has_deck:
			_deck(concrete, strip, pool, wall, out, dep, s_deck0, s_deck1, RoadMap.dip_at(chunk_index + 1) == RoadMap.DIP_TUNNEL)
	var mesh := (holder.get_node(^"Shell") as MeshInstance3D).mesh as ArrayMesh
	mesh.clear_surfaces()
	concrete.commit(mesh, concrete_mat())
	strip.commit(mesh, strip_mat())
	pool.commit(mesh, pool_mat())
	root.set_meta(&"tunnel", {"kind": kind, "depth": [dep[0], dep[int(L)]], "walls": n_walls, "strip_levels": strip_levels,
		"wall_levels": wall_levels, "deck": deck, "blocks": n_blocks, "surfaces": mesh.get_surface_count()})

## Five x positions across the tunnel at s: oncoming wall, 2.5 m in, the
## centre line, 2.5 m in from the own wall, the own wall.
static func _across(wall: PackedFloat32Array, s: float) -> PackedFloat32Array:
	var own := lerpf(wall[0], wall[1], s / L)
	var onc := lerpf(wall[2], wall[3], s / L)
	return PackedFloat32Array([-onc, -onc + 2.5, 0.0, own - 2.5, own])

## The cross street's bridge over the trench, s0 to s1 into the chunk, with
## the mouth at s1 (`mouth_ahead`) or at s0: fascia and parapet on the side
## away from the mouth, the street on top carried out to both sides, the lamp
## at each end of the fascia and the tunnel's light spilling out underneath.
static func _deck(concrete: Buf, strip: Buf, pool: Buf, wall: PackedFloat32Array, out: PackedFloat32Array, dep: PackedFloat32Array, s0: float, s1: float, mouth_ahead: bool) -> void:
	var s_face := s0 if mouth_ahead else s1
	var s_mouth := s1 if mouth_ahead else s0
	var toward := 1.0 if mouth_ahead else -1.0   # +s is toward the mouth
	var df := _dep(dep, s_face)
	var dm := _dep(dep, s_mouth)
	var xf := _across(wall, s_face)
	var xm := _across(wall, s_mouth)
	var own_out := lerpf(out[0], out[1], s_face / L)
	var onc_out := lerpf(out[2], out[3], s_face / L)
	var lamp_wash := Color(0.3, 0.185, 0.085)
	var face_cols: Array[Color] = [lamp_wash, _mul(TRENCH, 1.5), _mul(TRENCH, 1.3), _mul(TRENCH, 1.5), lamp_wash]
	var under_face: Array[float] = [0.34, 0.22, 0.14, 0.22, 0.34]
	for j in 4:
		# fascia: the beam the mouth is seen under, and the parapet on it
		concrete.quad(_p(xf[j], df - DECK_T, s_face), _p(xf[j + 1], df - DECK_T, s_face), _p(xf[j + 1], df + PARAPET_H, s_face), _p(xf[j], df + PARAPET_H, s_face),
			_mul(face_cols[j], 0.8), _mul(face_cols[j + 1], 0.8), face_cols[j + 1], face_cols[j])
		# underside: lit from the tunnel end
		concrete.quad(_p(xf[j], df - DECK_T, s_face), _p(xf[j + 1], df - DECK_T, s_face), _p(xm[j + 1], dm - DECK_T, s_mouth), _p(xm[j], dm - DECK_T, s_mouth),
			_mul(LIT, under_face[j] * 0.5), _mul(LIT, under_face[j + 1] * 0.5), _mul(LIT, under_face[j + 1]), _mul(LIT, under_face[j]))
	# parapet top and back, then the street
	var s_in := s_face + PARAPET_W * toward
	concrete.flat(_p(xf[0], df + PARAPET_H, s_face), _p(xf[4], df + PARAPET_H, s_face), _p(xf[4], df + PARAPET_H, s_in), _p(xf[0], df + PARAPET_H, s_in), _mul(TRENCH, 1.35))
	concrete.flat(_p(xf[0], df + PARAPET_H, s_in), _p(xf[4], df + PARAPET_H, s_in), _p(xf[4], df, s_in), _p(xf[0], df, s_in), _mul(TRENCH, 0.9))
	var far := Color(ASPHALT.r * 0.5, ASPHALT.g * 0.5, ASPHALT.b * 0.5)
	concrete.flat(_p(xf[0], df, s_in), _p(xf[4], df, s_in), _p(xm[4], dm, s_mouth), _p(xm[0], dm, s_mouth), ASPHALT)
	concrete.quad(_p(xf[4], df, s_face), _p(own_out + CROSS_REACH, df, s_face), _p(own_out + CROSS_REACH, dm, s_mouth), _p(xm[4], dm, s_mouth), ASPHALT, far, far, ASPHALT)
	concrete.quad(_p(xf[0], df, s_face), _p(-onc_out - CROSS_REACH, df, s_face), _p(-onc_out - CROSS_REACH, dm, s_mouth), _p(xm[0], dm, s_mouth), ASPHALT, far, far, ASPHALT)
	# a sodium lamp at each end of the fascia: post, head, and its glow
	for j: int in [0, 4]:
		var inward := 1.0 if j == 0 else -1.0
		var base := _p(xf[j] + 0.7 * inward, df + PARAPET_H, s_face + PARAPET_W * 0.5 * toward)
		concrete.box(base + Vector3(-0.07, 0.0, -0.07), base + Vector3(0.07, LAMP_POST, 0.07), _mul(TRENCH, 0.8))
		var head := base + Vector3(0.0, LAMP_POST, 0.0)
		strip.box(head - LAMP_HEAD * 0.5, head + LAMP_HEAD * 0.5, Color.WHITE)
		var glow := Color(0.5, 0.275, 0.1)
		var dark := Color(0.0, 0.0, 0.0)
		var gz := Vector3(0.0, 0.0, 0.2 * toward)   # just on the approach side of the head
		for q in 4:
			var a0 := float(q) * PI * 0.5
			var a1 := a0 + PI * 0.5
			pool.v.append(head + gz)
			pool.v.append(head + gz + Vector3(cos(a0), sin(a0), 0.0) * LAMP_GLOW)
			pool.v.append(head + gz + Vector3(cos(a1), sin(a1), 0.0) * LAMP_GLOW)
			pool.c.append(glow)
			pool.c.append(dark)
			pool.c.append(dark)
	# the tunnel's light on the road outside the mouth, fading out
	var s_far := s_mouth - SPILL * toward
	var xs := _across(wall, s_far)
	var pool_k: Array[float] = [1.0, 0.8, 0.55, 0.8, 1.0]
	for j in 4:
		pool.quad(_p(xs[j], POOL_Y, s_far), _p(xs[j + 1], POOL_Y, s_far), _p(xm[j + 1], POOL_Y, s_mouth), _p(xm[j], POOL_Y, s_mouth),
			Color(0, 0, 0), Color(0, 0, 0), _mul(POOL, pool_k[j + 1]), _mul(POOL, pool_k[j]))

## The downtown block over a mouth: a BuildingKit facade across the whole
## road, from the street up, s0 to s1 into the chunk.
static func _block(mi: MeshInstance3D, chunk_index: int, which: int, s0: float, s1: float, dep: PackedFloat32Array, out: PackedFloat32Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([RoadMap.lap_chunk(chunk_index), which, "tunnel block"])
	var across := 2.0 * (maxf(maxf(out[0], out[1]), maxf(out[2], out[3])) + BLOCK_SIDE)
	var info := BuildingKit.dress(mi, rng, false, 0.85, across, s1 - s0, Districts.spec("downtown"))
	var h: float = info.h
	var s_mid := (s0 + s1) * 0.5
	var s_mouth := s0 if which == 0 else s1
	var street := _p(0.0, _dep(dep, s_mouth), s_mouth).y
	var size := Vector3(across, h + BLOCK_BELOW, s1 - s0)
	mi.set_instance_shader_parameter("size", size)
	mi.set_instance_shader_parameter("base", BLOCK_BELOW)
	var f := RoadChunkBuilder._frame(s_mid)
	var fwd := -f.basis.z
	fwd.y = 0.0
	var at := f.origin
	at.y = street + (h - BLOCK_BELOW) * 0.5
	mi.transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP) * Basis.from_scale(size), at)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = true
	mi.set_meta("building_type", "tunnel_block")
	for k in ["sign_word", "shop_front", "landmark"]:
		if mi.has_meta(k):
			mi.remove_meta(k)
