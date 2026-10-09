extends RefCounted
class_name RoadBarriers

# Median barriers by area (R1, police build plan 2026-10-09 section 3d; Roy
# 07:53: "barriers by area as their own road PR"). Before this the middle had
# one look-only concrete bar on a random 30% of chunks, with no collision, so
# a car drove straight through it. Now:
#
# - The middle always has a barrier, and its type follows the district, the
#   way real highways pick by how much room there is (FHWA, median barriers):
#     downtown, industrial   concrete wall (Jersey shape)
#     residential, strip     steel guardrail (W-beam on posts)
#     wide middle            cable barrier, where the road layout opens the
#                            carriageways apart (RoadLayout splits, live once
#                            `splits_live` is on; until then nowhere)
# - About one emergency crossover per district (a district is 16 chunks,
#   800 m): a 25 m opening (stations GAP_FROM..GAP_TO) on a near-straight
#   chunk (GAP_MAX_K), clear of the district's first and blend chunks and of
#   any planned lane change, exit or split.
#   Both barrier ends at the opening get a crash cushion facing the traffic
#   that runs toward it. Cops will use the gaps to turn round (F2); the
#   chunk data says where they are (gap_chunk / gap_s).
# - Every type is real collision on the wall layer (one box per centreline
#   station, like the out-of-bounds walls), and each hits differently. The
#   surface does most of it (PhysicsMaterial per type); PlayerCar adds what a
#   material cannot (contact_effect, applied in its _integrate_forces):
#     concrete   frictionless, small bounce: you bounce along it
#     guardrail  a little friction, it scrapes speed off, and the piece you hit
#                stays dented for the run
#     cable      high friction, no bounce, and it drags the car down hard
#                while you are against it: catches you rather than bouncing
#     cushion    high friction, no bounce, crumples on a real hit (it gets
#                shorter, collision too) and stays crumpled for the run
#
# Frame cost: one MultiMesh per chunk for the barrier (its mesh is swapped
# per type, all three are shared static meshes), one for the two cushions,
# and the existing reflector MultiMesh. Every mesh and material is built once.
# The collision is one StaticBody per chunk with STATIONS boxes plus one with
# two cushion boxes; pieces in a gap are disabled, not freed.

const Districts := preload("res://scripts/world/districts.gd")

const CONCRETE := "concrete"
const GUARDRAIL := "guardrail"
const CABLE := "cable"
const NONE := ""

## District -> barrier type.
const BY_DISTRICT := {
	"downtown": CONCRETE, "industrial": CONCRETE,
	"residential": GUARDRAIL, "strip": GUARDRAIL,
}
## A median wider than this (m, extra over the normal one) gets the cable.
const CABLE_MEDIAN := 3.0

## Emergency crossover: stations GAP_FROM..GAP_TO of one chunk are open (5 m
## each, so 25 m), and a CUSHION_LEN cushion stands in front of each end,
## leaving 18 m to turn through. Real ones are about a mile apart, away from
## ramps and curves (TxDOT); ours are one per district, compressed.
const GAP_FROM := 3
const GAP_TO := 7
## Chunks of a district run that may hold its gap: not the first few (a run
## starts right after the previous district's blend) and not the last BLEND.
const GAP_FIRST := 4
const GAP_LAST := 11
## Curvature limit for the gap chunk and its neighbours, 1/m (radius 700 m:
## at 1.5 km only 3% of districts on a default-curvy road had a straight
## enough chunk; at 700 m about three in four do, with the layout clearance).
const GAP_MAX_K := 1.0 / 700.0
## Clear road kept before and after the gap from any planned layout change, m.
const GAP_CLEAR := 250.0

## Shapes (m). Concrete: Jersey profile; guardrail: double-sided W-beam on
## posts; cable: three cables on thin posts; cushion: a stack of bays.
const CONCRETE_BASE := 0.6
const CONCRETE_TOP := 0.16
const CONCRETE_H := 0.81
const RAIL_H := 0.31
const RAIL_Y := 0.48        # bottom of the rail
const RAIL_X := 0.12        # rail face from the centre line
const RAIL_T := 0.05
const POST_W := 0.15
const POST_H := 0.79
const POSTS_PER_PIECE := 3
const CABLE_POST_W := 0.08
const CABLE_POST_H := 0.95
const CABLE_YS := [0.53, 0.7, 0.87]
const CABLE_R := 0.02
const CUSHION_LEN := 3.5
const CUSHION_W := 0.7
const CUSHION_H := 0.85
const CUSHION_BAYS := 5
## How short a crumpled cushion gets (fraction of CUSHION_LEN).
const CUSHION_CRUMPLED := 0.35

## Collision box per type: width, height. Taller than the look where it
## matters: at 45 m/s and 60 degrees a car rode 0.9 m up an 0.85 m box, so
## the guardrail and cable boxes reach 1.1 m (tests/barrier_hit.gd).
const COLLISION := {
	CONCRETE: Vector2(0.5, 0.9),
	GUARDRAIL: Vector2(0.34, 1.1),
	CABLE: Vector2(0.3, 1.1),
}

## PlayerCar contact effects.
## Cable: drag while touching, m/s^2 off the horizontal speed.
const CABLE_DRAG := 9.0
## Guardrail: sideways speed into the rail that dents it, m/s, and the dent
## per m/s over that, capped (m, visual only).
const DENT_FROM := 3.0
const DENT_PER := 0.03
const DENT_MAX := 0.18
## Cushion: closing speed that crumples it, m/s.
const CRUMPLE_FROM := 5.0

## Dents and crumples for this run, keyed by chunk index then station (or
## cushion 0 / 1). A chunk rebuilt from the pool reads them back, so a dent
## stays where it was hit. reset() clears them (a new run).
static var dents := {}
static var crumpled := {}
## Tests: one type everywhere (tests/barrier_hit.gd).
static var force_kind := NONE

static func reset() -> void:
	dents.clear()
	crumpled.clear()

# ---------- where ----------

## Barrier type for a chunk (NONE never, today: every chunk has one).
static func kind_at(chunk_index: int) -> String:
	if force_kind != NONE:
		return force_kind
	var lay := RoadFrame.layout
	if lay != null and lay.splits_live:
		var s := (float(chunk_index) + 0.5) * RoadChunkBuilder.CHUNK_LEN
		if lay.median_extra(s) > CABLE_MEDIAN:
			return CABLE
	return String(BY_DISTRICT.get(Districts.name_at(chunk_index), CONCRETE))

## The chunk holding district run `run`'s crossover, or -1 when no chunk of
## the run qualifies (every candidate bends or sits near a layout change).
## Pure function of the run and the road seed: the same every time it is asked.
static func gap_chunk(run: int) -> int:
	var first := run * Districts.RUN
	var n := GAP_LAST - GAP_FIRST + 1
	var start := posmod(hash([run, "crossover"]), n)
	for j in n:
		var c := first + GAP_FIRST + (start + j) % n
		if _gap_ok(c):
			return c
	return -1

static func has_gap(chunk_index: int) -> bool:
	return gap_chunk(Districts.run_of(chunk_index)) == chunk_index

## Distance along the road of run `run`'s crossover centre, or -1.
static func gap_s(run: int) -> float:
	var c := gap_chunk(run)
	if c < 0:
		return -1.0
	return float(c) * RoadChunkBuilder.CHUNK_LEN + (float(GAP_FROM + GAP_TO + 1) / 2.0) * RoadChunkBuilder.CHUNK_LEN / RoadChunkBuilder.STATIONS

static func _gap_ok(c: int) -> bool:
	for i in [c - 1, c, c + 1]:
		if absf(RoadFrame.curvature(i)) > GAP_MAX_K:
			return false
	var lay := RoadFrame.layout
	if lay != null:
		var s := float(c) * RoadChunkBuilder.CHUNK_LEN
		if not lay.changes_between(s - GAP_CLEAR, s + RoadChunkBuilder.CHUNK_LEN + GAP_CLEAR).is_empty():
			return false
	return true

## Whether station k of a gap chunk is open.
static func is_open(k: int) -> bool:
	return k >= GAP_FROM and k <= GAP_TO

# ---------- meshes (shared) ----------

static var _meshes := {}
static var _cushion_mesh: ArrayMesh
static var _materials := {}
static var _phys := {}

static func _mat(key: String) -> StandardMaterial3D:
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		match key:
			CONCRETE:
				# the old median's concrete, with its faint self-light so the
				# wall's line still reads at night
				m.albedo_color = Color(0.36, 0.355, 0.34)
				m.roughness = 0.9
				m.emission_enabled = true
				m.emission = m.albedo_color
				m.emission_energy_multiplier = 0.1
			GUARDRAIL:
				# galvanised steel, a little worn
				m.albedo_color = Color(0.5, 0.52, 0.54)
				m.metallic = 0.6
				m.roughness = 0.45
			CABLE:
				m.albedo_color = Color(0.42, 0.43, 0.45)
				m.metallic = 0.5
				m.roughness = 0.5
			"cushion":
				# amber reflective sheeting (Amber vs. Dusk amber #FFC066,
				# darkened), faintly self-lit so a crossover reads at night;
				# under the 1.0 glow threshold (no neon)
				m.albedo_color = Color(0.85, 0.55, 0.2)
				m.roughness = 0.6
				m.emission_enabled = true
				m.emission = Color(1.0, 0.75, 0.4)
				m.emission_energy_multiplier = 0.3
			"cushion_band":
				m.albedo_color = Color(0.1, 0.1, 0.11)
				m.roughness = 0.8
		_materials[key] = m
	return _materials[key]

## One barrier piece, one station long, centred on z = 0 with its base at y = 0.
static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var seg := RoadChunkBuilder.CHUNK_LEN / RoadChunkBuilder.STATIONS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		CONCRETE:
			# Jersey shape: steep foot, sloped face, narrow top.
			var hb := CONCRETE_BASE / 2.0
			var ht := CONCRETE_TOP / 2.0
			var profile := [Vector2(-hb, 0.0), Vector2(-hb + 0.03, 0.08), Vector2(-ht - 0.1, 0.33),
				Vector2(-ht, CONCRETE_H), Vector2(ht, CONCRETE_H), Vector2(ht + 0.1, 0.33),
				Vector2(hb - 0.03, 0.08), Vector2(hb, 0.0)]
			_extrude(st, profile, seg)
		GUARDRAIL:
			for side in [-1.0, 1.0]:
				var x: float = (RAIL_X + RAIL_T / 2.0) * side
				# The W: two ridges and a groove, as three boxes.
				RoadChunkBuilder._add_box(st, Vector3(x, RAIL_Y + RAIL_H * 0.25, 0.0), Vector3(RAIL_T, RAIL_H * 0.4, seg))
				RoadChunkBuilder._add_box(st, Vector3(x, RAIL_Y + RAIL_H * 0.75, 0.0), Vector3(RAIL_T, RAIL_H * 0.4, seg))
				RoadChunkBuilder._add_box(st, Vector3(x - 0.025 * side, RAIL_Y + RAIL_H * 0.5, 0.0), Vector3(RAIL_T, RAIL_H * 0.2, seg))
			for i in POSTS_PER_PIECE:
				var z := -seg / 2.0 + (float(i) + 0.5) * seg / POSTS_PER_PIECE
				RoadChunkBuilder._add_box(st, Vector3(0.0, POST_H / 2.0, z), Vector3(POST_W, POST_H, POST_W))
		CABLE:
			for i in 2:
				var z := -seg / 2.0 + (float(i) + 0.5) * seg / 2.0
				RoadChunkBuilder._add_box(st, Vector3(0.0, CABLE_POST_H / 2.0, z), Vector3(CABLE_POST_W, CABLE_POST_H, CABLE_POST_W))
			for j in CABLE_YS.size():
				var side := -1.0 if j % 2 == 0 else 1.0
				RoadChunkBuilder._add_box(st, Vector3((CABLE_POST_W / 2.0 + CABLE_R) * side, CABLE_YS[j], 0.0), Vector3(CABLE_R * 2.0, CABLE_R * 2.0, seg))
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _mat(kind))
	_meshes[kind] = m
	return m

## The cushion, CUSHION_LEN long along z from z = 0 (the barrier end) to
## z = +CUSHION_LEN (its nose), base at y = 0: bays of amber and dark bands.
static func cushion_mesh() -> ArrayMesh:
	if _cushion_mesh != null:
		return _cushion_mesh
	_cushion_mesh = ArrayMesh.new()
	var bay := CUSHION_LEN / CUSHION_BAYS
	# Two surfaces: the amber bays (and the nose), then the dark bands.
	for band in [false, true]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in CUSHION_BAYS:
			if (i % 2 == 1) != band:
				continue
			var w := CUSHION_W * (0.9 if band else 1.0)
			RoadChunkBuilder._add_box(st, Vector3(0.0, CUSHION_H / 2.0, (float(i) + 0.5) * bay), Vector3(w, CUSHION_H, bay * 0.98))
		st.generate_normals()
		st.commit(_cushion_mesh)
		_cushion_mesh.surface_set_material(_cushion_mesh.get_surface_count() - 1, _mat("cushion_band" if band else "cushion"))
	return _cushion_mesh

## Extrudes a closed profile (x, y), drawn left to right over the top, along
## z from -len/2 to +len/2, with both end caps.
static func _extrude(st: SurfaceTool, profile: Array, length: float) -> void:
	var z0 := -length / 2.0
	var z1 := length / 2.0
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		var a0 := Vector3(a.x, a.y, z0)
		var a1 := Vector3(a.x, a.y, z1)
		var b0 := Vector3(b.x, b.y, z0)
		var b1 := Vector3(b.x, b.y, z1)
		# outward-facing: clockwise seen from outside, Godot's front face
		st.add_vertex(a0); st.add_vertex(b1); st.add_vertex(a1)
		st.add_vertex(a0); st.add_vertex(b0); st.add_vertex(b1)
	# end caps: a fan over the convex profile
	for i in range(1, profile.size() - 1):
		var p0: Vector2 = profile[0]
		var p1: Vector2 = profile[i]
		var p2: Vector2 = profile[i + 1]
		st.add_vertex(Vector3(p0.x, p0.y, z1)); st.add_vertex(Vector3(p2.x, p2.y, z1)); st.add_vertex(Vector3(p1.x, p1.y, z1))
		st.add_vertex(Vector3(p0.x, p0.y, z0)); st.add_vertex(Vector3(p1.x, p1.y, z0)); st.add_vertex(Vector3(p2.x, p2.y, z0))

## Top of a piece of this type (where its reflectors sit), m above the road.
static func top(kind: String) -> float:
	match kind:
		GUARDRAIL:
			return RAIL_Y + RAIL_H
		CABLE:
			return CABLE_POST_H
	return CONCRETE_H

# ---------- collision ----------

static func physics_material(kind: String) -> PhysicsMaterial:
	if not _phys.has(kind):
		var m := PhysicsMaterial.new()
		match kind:
			GUARDRAIL:
				m.friction = 0.15
				m.bounce = 0.05
			CABLE, "cushion":
				m.friction = 0.9
				m.bounce = 0.0
				m.absorbent = true
			_:
				m.friction = 0.0
				m.bounce = 0.1
		_phys[kind] = m
	return _phys[kind]

static func new_bodies(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "BarrierCol"
	CarSpec.make_wall(body)
	for k in RoadChunkBuilder.STATIONS:
		var col := CollisionShape3D.new()
		col.name = "Shape%d" % k
		col.shape = BoxShape3D.new()
		body.add_child(col)
	root.add_child(body)
	var cush := StaticBody3D.new()
	cush.name = "CushionCol"
	CarSpec.make_wall(cush)
	cush.physics_material_override = physics_material("cushion")
	cush.set_meta("barrier", "cushion")
	for i in 2:
		var col := CollisionShape3D.new()
		col.name = "Shape%d" % i
		col.shape = BoxShape3D.new()
		cush.add_child(col)
	root.add_child(cush)

# ---------- per chunk ----------

## Lays out the barrier, its reflectors, the cushions and their collision for
## one chunk. kind NONE hides everything (the old dashed centre line shows).
static func apply(root: Node3D, chunk_index: int, kind: String, gap: bool) -> void:
	var seg := RoadChunkBuilder.CHUNK_LEN / RoadChunkBuilder.STATIONS
	var f := RoadChunkBuilder._foundation()
	var bar := root.get_node(^"Barrier") as MultiMeshInstance3D
	var refl: MultiMesh = (bar.get_node(^"Reflectors") as MultiMeshInstance3D).multimesh
	var cush := root.get_node(^"Cushions") as MultiMeshInstance3D
	var body := root.get_node(^"BarrierCol") as StaticBody3D
	var cbody := root.get_node(^"CushionCol") as StaticBody3D
	body.set_meta("barrier", kind)
	body.set_meta("gap", gap)
	body.physics_material_override = physics_material(kind)
	bar.visible = kind != NONE
	bar.material_override = null  # each type's mesh carries its own material
	var chunk_dents: Dictionary = dents.get(chunk_index, {})
	var n := 0
	var nr := 0
	if kind != NONE:
		bar.multimesh.mesh = mesh(kind)
		# The reflector strip sits BARRIER_H / 2 + 0.03 up in its own space
		# (made for the old box centred on the piece); lift it to this type's top.
		var lift := top(kind) - RoadChunkBuilder.BARRIER_H / 2.0
		for k in RoadChunkBuilder.STATIONS:
			var col := body.get_node(NodePath("Shape%d" % k)) as CollisionShape3D
			var open := gap and is_open(k)
			col.disabled = open or kind == NONE
			if open:
				continue
			var z := -seg * (float(k) + 0.5)
			var dent: float = chunk_dents.get(k, 0.0)
			var xf := RoadChunkBuilder._xf(dent, 0.0, z)
			bar.multimesh.set_instance_transform(n, xf)
			refl.set_instance_transform(nr, xf * Transform3D(Basis(), Vector3(0.0, lift, 0.0)))
			n += 1
			nr += 1
			var size: Vector2 = COLLISION[kind]
			(col.shape as BoxShape3D).size = Vector3(size.x, size.y + f, seg + RoadChunkBuilder.BOUNDARY_OVERLAP)
			col.transform = RoadChunkBuilder._xf_up(0.0, (size.y - f) / 2.0, z)
	else:
		for k in RoadChunkBuilder.STATIONS:
			(body.get_node(NodePath("Shape%d" % k)) as CollisionShape3D).disabled = true
	bar.multimesh.visible_instance_count = n
	# Cushions: in front of each barrier end at the opening, facing the
	# traffic that drives toward that end (own side drives toward -z).
	var nc := 0
	var chunk_crumpled: Dictionary = crumpled.get(chunk_index, {})
	for i in 2:
		var col := cbody.get_node(NodePath("Shape%d" % i)) as CollisionShape3D
		var on := gap and kind != NONE
		col.disabled = not on
		if not on:
			continue
		var len := CUSHION_LEN * (CUSHION_CRUMPLED if chunk_crumpled.get(i, false) else 1.0)
		# i = 0: the end at the start of the opening, its nose toward -z
		# (oncoming traffic arrives from -z). i = 1: the far end, nose to +z.
		var end_z := -seg * float(GAP_FROM) if i == 0 else -seg * float(GAP_TO + 1)
		var dir := -1.0 if i == 0 else 1.0
		var turn := Basis(Vector3.UP, PI) if i == 0 else Basis()
		var xf := RoadChunkBuilder._xf(0.0, 0.0, end_z, turn) * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, len / CUSHION_LEN)), Vector3.ZERO)
		cush.multimesh.set_instance_transform(nc, xf)
		# a reflector strip along its top
		refl.set_instance_transform(nr, RoadChunkBuilder._xf(0.0, CUSHION_H - RoadChunkBuilder.BARRIER_H / 2.0, end_z + dir * len * 0.5) * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, len / seg)), Vector3.ZERO))
		nc += 1
		nr += 1
		(col.shape as BoxShape3D).size = Vector3(CUSHION_W, CUSHION_H + f, len)
		col.transform = RoadChunkBuilder._xf_up(0.0, (CUSHION_H - f) / 2.0, end_z + dir * len / 2.0)
		col.set_meta("cushion", i)
	cush.multimesh.visible_instance_count = nc
	refl.visible_instance_count = nr

# ---------- hits (PlayerCar) ----------

## Called by PlayerCar for each contact with a barrier body: the effect a
## surface material alone cannot give. Returns the velocity change to apply
## (m/s, horizontal). `shape` is the contact's shape index on that body;
## `before` is the car's velocity before the hit (how hard it was).
static func contact_effect(body: CollisionObject3D, shape: int, car_pos: Vector3, velocity: Vector3, before: Vector3, dt: float) -> Vector3:
	var kind := String(body.get_meta("barrier", NONE))
	var root := body.get_parent() as Node3D
	var col := body.shape_owner_get_owner(body.shape_find_owner(shape)) as CollisionShape3D
	var vh := Vector3(velocity.x, 0.0, velocity.z)
	match kind:
		CABLE:
			var sp := vh.length()
			if sp < 0.01:
				return Vector3.ZERO
			return -vh / sp * minf(sp, CABLE_DRAG * dt)
		GUARDRAIL:
			if root != null and col != null:
				# Which side of the rail the car is on, and how fast it closes,
				# in the chunk's own frame (x across the road).
				var side := signf(root.to_local(car_pos).x)
				var into := -side * (root.global_basis.inverse() * Vector3(before.x, 0.0, before.z)).x
				if into > DENT_FROM:
					var k := int(String(col.name).trim_prefix("Shape"))
					_dent(root, k, -side * minf((into - DENT_FROM) * DENT_PER, DENT_MAX))
		"cushion":
			if root != null and col != null and Vector2(before.x, before.z).length() > CRUMPLE_FROM:
				_crumple(root, int(col.get_meta("cushion", 0)))
	return Vector3.ZERO

static func _dent(root: Node3D, k: int, amount: float) -> void:
	var c := int(root.get_meta("chunk_index", 0))
	var d: Dictionary = dents.get(c, {})
	var old: float = d.get(k, 0.0)
	# Only deeper: a second lighter hit does not pull it back out.
	if absf(amount) <= absf(old):
		return
	d[k] = amount
	dents[c] = d
	_reapply(root)

static func _crumple(root: Node3D, i: int) -> void:
	var c := int(root.get_meta("chunk_index", 0))
	var d: Dictionary = crumpled.get(c, {})
	if d.get(i, false):
		return
	d[i] = true
	crumpled[c] = d
	_reapply(root)

## Re-lays the chunk's barrier after a dent or crumple. Deferred: called from
## inside a physics callback, where shapes must not change.
static func _reapply(root: Node3D) -> void:
	var c := int(root.get_meta("chunk_index", 0))
	var body := root.get_node(^"BarrierCol") as Node
	var kind := String(body.get_meta("barrier", NONE))
	var gap := bool(body.get_meta("gap", false))
	(func() -> void:
		if is_instance_valid(root) and int(root.get_meta("chunk_index", 0)) == c:
			# The builder lays out against the frames of the chunk it built
			# last; point them at this chunk's centreline first.
			RoadChunkBuilder._curve = (root.get_node(^"Centerline") as Path3D).curve
			RoadChunkBuilder._cache_frames(RoadChunkBuilder._curve)
			apply(root, c, kind, gap)
			RoadChunkBuilder.sync_collision(root)
	).call_deferred()
