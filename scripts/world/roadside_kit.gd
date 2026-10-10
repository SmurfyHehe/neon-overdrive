extends RefCounted
class_name RoadsideKit

# Roadside kit and barrier set (environment plan 2026-10-07, section 3 item
# 2: "fencing, guard rail, jersey barriers, cones, bins, dumpsters,
# hydrants"; Roy 2026-10-09: "more barriers, more roadside kit"). Small
# things at the kerb are the main speed cue after the posts, and barriers on
# the shoulder give the road edge a reason to be respected.
#
# Six kinds, every one a shared static mesh drawn from one MultiMesh per
# kind per chunk (six draw calls per chunk at most, and a kind with nothing
# in a chunk costs none: its instance is hidden). One vertex-coloured
# material for all of them, flat PS2 shading, nothing above the glow
# threshold.
#
#   hydrant   on the sidewalk by the kerb                      visual
#   bin       litter bin at the foot of a street lamp          visual
#   dumpster  against the back wall of a lot the car can enter collision, metal
#             (strip and industrial setbacks, and empty lots there)
#   cone      a taper of cones closing the shoulder ahead of a work zone
#   jersey    portable concrete barriers on the shoulder at that work zone
#                                                              collision, concrete
#   rail      one-sided W-beam guardrail on the kerb line, industrial
#                                                              collision, metal
#
# What goes where is the BY_DISTRICT table below: expected counts per side
# per chunk, scaled by `density` (0 turns the kit off). Positions come from
# the edges the chunk builder hands over (road edge, shoulder, kerb,
# sidewalk, lot), never from the width constants, so the kerb and width
# table work can move them without touching this file.
#
# Placement is a hash of the chunk index (like Districts), never the global
# random sequence, so the road layout is unchanged and a chunk rebuilt from
# the pool matches one built fresh. Every placement is also recorded in the
# chunk's "kit" meta (straight-road coordinates), because headless Godot
# returns identity from MultiMesh getters; tests/world/roadside_kit.gd reads
# that record.
#
# Collision: two StaticBodies per chunk on the wall layer, one metal (rail,
# dumpster: audio_surface "metal", guardrail physics, it scrapes speed off)
# and one concrete (jersey: the wall default, frictionless with a small
# bounce). Shapes are toggled, never freed. Neither carries the "barrier"
# meta: PlayerCar's barrier contact effects (dents, crumples) belong to the
# median only.

const Districts := preload("res://scripts/world/districts.gd")

const HYDRANT := "hydrant"
const BIN := "bin"
const DUMPSTER := "dumpster"
const CONE := "cone"
const JERSEY := "jersey"
const RAIL := "rail"
const KINDS := [HYDRANT, BIN, DUMPSTER, CONE, JERSEY, RAIL]

## Per district: hydrant / bin are expected counts per side per chunk (the
## fraction is a chance); dumpster is the chance per lot that can take one;
## workzone is the chance per side per chunk of a cone taper plus jersey run;
## rail is the chance per side per chunk of a guardrail along the kerb.
const BY_DISTRICT := {
	"downtown":    {"hydrant": 0.9, "bin": 1.4, "dumpster": 0.0, "workzone": 0.06, "rail": 0.0},
	"residential": {"hydrant": 0.8, "bin": 0.7, "dumpster": 0.0, "workzone": 0.04, "rail": 0.0},
	"strip":       {"hydrant": 0.4, "bin": 0.6, "dumpster": 0.7, "workzone": 0.06, "rail": 0.0},
	"industrial":  {"hydrant": 0.2, "bin": 0.1, "dumpster": 0.8, "workzone": 0.10, "rail": 0.55},
}

## Overall density, 0 (off) to about 2. NEON_KIT in the environment sets it
## (tests, benchmarks); a Settings slider can set it later.
static var density := 1.0
static var _density_read := false
## Tools and tests: keys here override the district table everywhere, for
## example {"workzone": 1.0, "rail": 1.0} (tools/roadside_kit_shots.gd).
static var force := {}

## Buffer sizes per chunk (worst case, allocated once).
const CAP := {HYDRANT: 6, BIN: 8, DUMPSTER: 6, CONE: 16, JERSEY: 10, RAIL: 20}

## Shapes (m).
const HYDRANT_H := 0.75
const HYDRANT_W := 0.26
const HYDRANT_FROM_KERB := 0.45   # centre from the kerb's outer edge, on the sidewalk
const BIN_H := 0.9
const BIN_W := 0.5
const BIN_FROM_KERB := 0.55
const BIN_BEHIND_LAMP := 1.1      # m along the road from the lamp pole
const DUMPSTER_SIZE := Vector3(1.8, 1.3, 1.1)  # frontage, height, depth
const DUMPSTER_WALL_GAP := 0.25   # from the lot's back wall
const CONE_H := 0.7
const CONE_BASE := 0.36
const CONE_SPACING := 2.5
const CONES_IN_TAPER := 5
const JERSEY_LEN := 3.0
const JERSEY_BASE := 0.6
const JERSEY_TOP := 0.2
const JERSEY_H := 0.8
const JERSEY_RUN := 4             # pieces in a work zone
const JERSEY_ON_SHOULDER := 0.45  # centre inside the kerb's inner edge
const RAIL_H := 0.31
const RAIL_Y := 0.5
const RAIL_T := 0.05
const RAIL_POST_W := 0.14
const RAIL_POST_H := 0.78
const RAIL_POSTS := 2             # per 5 m piece
## Minimum lot depth (the district setback) a dumpster needs to stand in.
const DUMPSTER_MIN_SETBACK := 2.5
## Clear kept from lamp poles and between kit pieces along the road.
const CLEAR := 1.2

## Collision boxes: width across the road, height. The rail reaches above
## its look like the median rail (a car rode up an 0.85 m box at speed,
## tests/world/barrier_hit.gd).
const COL_JERSEY := Vector2(JERSEY_BASE, 0.9)
const COL_RAIL := Vector2(0.3, 1.1)

## Colours (Amber vs. Dusk: warm greys, sodium orange and amber, no neon).
const C_HYDRANT := Color(0.66, 0.3, 0.09)
const C_HYDRANT_CAP := Color(0.5, 0.5, 0.48)
const C_BIN := Color(0.17, 0.2, 0.17)
const C_BIN_RIM := Color(0.34, 0.34, 0.32)
const C_DUMPSTER := Color(0.13, 0.21, 0.17)
const C_DUMPSTER_LID := Color(0.19, 0.28, 0.23)
const C_CONE := Color(0.95, 0.42, 0.1)
const C_CONE_BAND := Color(0.9, 0.88, 0.82)
const C_CONE_BASE := Color(0.08, 0.08, 0.08)
const C_JERSEY := Color(0.4, 0.39, 0.37)
const C_JERSEY_STRIPE := Color(0.95, 0.6, 0.2)
const C_RAIL := Color(0.5, 0.52, 0.54)
const C_RAIL_POST := Color(0.32, 0.3, 0.28)

static var _meshes := {}
static var _material: ShaderMaterial
static var _rng := RandomNumberGenerator.new()

## One material for the whole kit: vertex colours, flat lambert, and a
## faint self-light (SELF_LIGHT of the colour) so a piece still reads at
## night the way the concrete median does (0.1; the posts have 0.35); well
## under the 1.0 glow threshold, so nothing blooms (no neon).
const SELF_LIGHT := 0.1
const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float self_light = 0.1;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	EMISSION = COLOR.rgb * self_light;
}
"""

static func _read_density() -> void:
	if _density_read:
		return
	_density_read = true
	var e := OS.get_environment("NEON_KIT")
	if e != "":
		density = maxf(0.0, float(e))

# ---------- meshes (shared) ----------

static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		var light := SELF_LIGHT
		if OS.get_environment("NEON_KIT_LIGHT") != "":  # tuning shots only
			light = float(OS.get_environment("NEON_KIT_LIGHT"))
		_material.set_shader_parameter("self_light", light)
	return _material

## Adds a box with flat normals in the given colour.
static func _box(st: SurfaceTool, color: Color, center: Vector3, size: Vector3) -> void:
	st.set_color(color)
	RoadChunkBuilder._add_box(st, center, size)

## A four-sided frustum (a cone's body) from y0 to y1, square sides w0 at the
## bottom and w1 at the top, flat normals.
static func _frustum(st: SurfaceTool, color: Color, y0: float, y1: float, w0: float, w1: float) -> void:
	st.set_color(color)
	var h0 := w0 / 2.0
	var h1 := w1 / 2.0
	var dirs := [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]
	for i in 4:
		var d: Vector3 = dirs[i]
		var t: Vector3 = dirs[(i + 1) % 4]
		var a := d * h0 - t * h0 + Vector3.UP * y0
		var b := d * h0 + t * h0 + Vector3.UP * y0
		var c := d * h1 + t * h1 + Vector3.UP * y1
		var e := d * h1 - t * h1 + Vector3.UP * y1
		# a sloping side leans its normal up by how much it narrows
		st.set_normal((d * (y1 - y0) + Vector3.UP * (h0 - h1)).normalized())
		# clockwise seen from outside (Godot's front face), like _add_box
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(e)
	st.set_normal(Vector3.UP)
	var p := [Vector3(-h1, y1, h1), Vector3(-h1, y1, -h1), Vector3(h1, y1, -h1), Vector3(h1, y1, h1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(p[i])

## Extrudes a closed profile (x, y, drawn left to right over the top) along
## z over `length`, both caps, flat normals, one colour.
static func _extrude(st: SurfaceTool, color: Color, profile: Array, length: float) -> void:
	var z0 := -length / 2.0
	var z1 := length / 2.0
	st.set_color(color)
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		# the profile runs clockwise (up the left, over the top, down the
		# right), so its outward normal is the edge turned a quarter left
		var n := Vector3(-(b.y - a.y), b.x - a.x, 0.0).normalized()
		st.set_normal(n)
		var a0 := Vector3(a.x, a.y, z0)
		var a1 := Vector3(a.x, a.y, z1)
		var b0 := Vector3(b.x, b.y, z0)
		var b1 := Vector3(b.x, b.y, z1)
		st.add_vertex(a0); st.add_vertex(b1); st.add_vertex(a1)
		st.add_vertex(a0); st.add_vertex(b0); st.add_vertex(b1)
	# caps: a fan from the profile's centre (the Jersey foot has a kink, so a
	# fan from a corner would fold); clockwise seen from outside
	var centre := Vector2.ZERO
	for q in profile:
		centre += q
	centre /= float(profile.size())
	for i in profile.size():
		var p1: Vector2 = profile[i]
		var p2: Vector2 = profile[(i + 1) % profile.size()]
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(centre.x, centre.y, z1)); st.add_vertex(Vector3(p1.x, p1.y, z1)); st.add_vertex(Vector3(p2.x, p2.y, z1))
		st.set_normal(Vector3.FORWARD)
		st.add_vertex(Vector3(centre.x, centre.y, z0)); st.add_vertex(Vector3(p2.x, p2.y, z0)); st.add_vertex(Vector3(p1.x, p1.y, z0))

## One piece of a kind, base at y = 0, centred on x = z = 0 unless noted.
## The rail runs along z (one station long); its face is at x = 0 and its
## posts stand at +x (the instance turns it so +x is away from the road).
## The jersey runs along z too. The dumpster's frontage is along z (it stands
## with its back to the lot wall, its long side facing the road).
static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		HYDRANT:
			_box(st, C_HYDRANT, Vector3(0.0, 0.3, 0.0), Vector3(HYDRANT_W, 0.6, HYDRANT_W))
			_box(st, C_HYDRANT, Vector3(0.0, 0.42, 0.0), Vector3(HYDRANT_W + 0.22, 0.12, 0.16))  # the two side nozzles
			_box(st, C_HYDRANT_CAP, Vector3(0.0, 0.66, 0.0), Vector3(HYDRANT_W + 0.06, 0.08, HYDRANT_W + 0.06))
			_frustum(st, C_HYDRANT_CAP, 0.7, HYDRANT_H, HYDRANT_W, 0.1)
		BIN:
			_box(st, C_BIN, Vector3(0.0, BIN_H / 2.0, 0.0), Vector3(BIN_W, BIN_H, BIN_W))
			_box(st, C_BIN_RIM, Vector3(0.0, BIN_H - 0.04, 0.0), Vector3(BIN_W + 0.06, 0.08, BIN_W + 0.06))
		DUMPSTER:
			var s := DUMPSTER_SIZE
			_box(st, C_DUMPSTER, Vector3(0.0, s.y / 2.0 - 0.1, 0.0), Vector3(s.z, s.y - 0.2, s.x))
			_box(st, C_DUMPSTER_LID, Vector3(0.0, s.y - 0.1, 0.0), Vector3(s.z + 0.06, 0.2, s.x + 0.06))
			# a lip along the road-facing side's top edge
			_box(st, C_DUMPSTER_LID, Vector3(-s.z / 2.0, s.y - 0.35, 0.0), Vector3(0.1, 0.1, s.x))
		CONE:
			_box(st, C_CONE_BASE, Vector3(0.0, 0.025, 0.0), Vector3(CONE_BASE, 0.05, CONE_BASE))
			_frustum(st, C_CONE, 0.05, 0.3, 0.26, 0.19)
			_frustum(st, C_CONE_BAND, 0.3, 0.42, 0.19, 0.155)
			_frustum(st, C_CONE, 0.42, CONE_H, 0.155, 0.07)
		JERSEY:
			var hb := JERSEY_BASE / 2.0
			var ht := JERSEY_TOP / 2.0
			var profile := [Vector2(-hb, 0.0), Vector2(-hb + 0.03, 0.08), Vector2(-ht - 0.08, 0.3),
				Vector2(-ht, JERSEY_H), Vector2(ht, JERSEY_H), Vector2(ht + 0.08, 0.3),
				Vector2(hb - 0.03, 0.08), Vector2(hb, 0.0)]
			_extrude(st, C_JERSEY, profile, JERSEY_LEN)
			# an orange stripe near each end, on both faces
			for z in [-JERSEY_LEN / 2.0 + 0.4, JERSEY_LEN / 2.0 - 0.4]:
				_box(st, C_JERSEY_STRIPE, Vector3(0.0, 0.58, z), Vector3(JERSEY_TOP + 0.03, 0.22, 0.14))
		RAIL:
			var seg := RoadChunkBuilder.CHUNK_LEN / RoadChunkBuilder.STATIONS
			# W-beam: two ridges and the groove between, as three boxes, face at x = 0
			_box(st, C_RAIL, Vector3(RAIL_T / 2.0, RAIL_Y + RAIL_H * 0.25, 0.0), Vector3(RAIL_T, RAIL_H * 0.4, seg))
			_box(st, C_RAIL, Vector3(RAIL_T / 2.0, RAIL_Y + RAIL_H * 0.75, 0.0), Vector3(RAIL_T, RAIL_H * 0.4, seg))
			_box(st, C_RAIL, Vector3(RAIL_T / 2.0 + 0.025, RAIL_Y + RAIL_H * 0.5, 0.0), Vector3(RAIL_T, RAIL_H * 0.2, seg))
			for i in RAIL_POSTS:
				var z := -seg / 2.0 + (float(i) + 0.5) * seg / RAIL_POSTS
				_box(st, C_RAIL_POST, Vector3(RAIL_T + RAIL_POST_W / 2.0, RAIL_POST_H / 2.0, z), Vector3(RAIL_POST_W, RAIL_POST_H, RAIL_POST_W))
	var m := st.commit()
	m.surface_set_material(0, material())
	_meshes[kind] = m
	return m

# ---------- nodes ----------

static func _mmi_name(kind: String) -> String:
	return "Kit_" + kind

static func new_nodes(root: Node3D) -> void:
	for kind in KINDS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh(kind)
		mm.instance_count = int(CAP[kind])
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = _mmi_name(kind)
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Small things vanish before they are a pixel; the barriers carry further.
		mmi.visibility_range_end = 120.0 if kind in [HYDRANT, BIN, CONE] else 220.0
		mmi.visible = false
		root.add_child(mmi)
	var metal := StaticBody3D.new()
	metal.name = "KitColMetal"
	CarSpec.make_wall(metal)
	metal.physics_material_override = RoadBarriers.physics_material(RoadBarriers.GUARDRAIL)
	metal.set_meta(&"audio_surface", "metal")
	for i in int(CAP[RAIL]) + int(CAP[DUMPSTER]):
		var col := CollisionShape3D.new()
		col.name = "Shape%d" % i
		col.shape = BoxShape3D.new()
		col.disabled = true
		metal.add_child(col)
	root.add_child(metal)
	var concrete := StaticBody3D.new()
	concrete.name = "KitColConcrete"
	CarSpec.make_wall(concrete)
	for i in int(CAP[JERSEY]):
		var col := CollisionShape3D.new()
		col.name = "Shape%d" % i
		col.shape = BoxShape3D.new()
		col.disabled = true
		concrete.add_child(col)
	root.add_child(concrete)

# ---------- per chunk ----------

## A chunk's kit. `edges` per side (1 own, -1 oncoming): {"road": [start, end],
## "curb_in": [..], "curb_out": [..], "walk": [..]} as distances from the
## centre line at the chunk's start and end (the builder tapers between
## them); `setback` the district's lot depth behind the sidewalk; `lamps`
## the lamp poles' chunk-local z per side; `lots` the empty or set-back
## building slots per side as [z, frontage] (from _update_building's infos).
static func apply(root: Node3D, chunk_index: int, edges: Dictionary, setback: float, lamps: Dictionary, lots: Dictionary) -> void:
	_read_density()
	var spec: Dictionary = BY_DISTRICT.get(Districts.name_at(chunk_index), BY_DISTRICT["downtown"]).duplicate()
	spec.merge(force, true)
	_rng.seed = hash([chunk_index, "roadside kit"])
	var placed: Array = []  # {kind, side, x, y, z, yaw, len}
	var f := RoadChunkBuilder._foundation()
	var L := RoadChunkBuilder.CHUNK_LEN
	var seg := L / RoadChunkBuilder.STATIONS
	var d := density
	for side in [1, -1]:
		var e: Dictionary = edges[side]
		var taken: Array = []  # [z_from, z_to] along the road already used on this side
		for lz in lamps[side]:
			taken.append([float(lz) + CLEAR, float(lz) - CLEAR])
		# Work zone: cones taper the shoulder shut, then a run of jersey
		# barriers on it. Upstream is +z on the own side (traffic drives
		# toward -z) and -z on the oncoming side.
		if _rng.randf() < float(spec.workzone) * d:
			var run_len := JERSEY_RUN * JERSEY_LEN
			var taper_len := CONES_IN_TAPER * CONE_SPACING
			var total := run_len + taper_len
			# the zone spans z_top (nearest the chunk start) to z_top - total
			var z_top := -_rng.randf_range(2.0, L - total - 2.0)
			var ok := true
			var zz := z_top
			while zz >= z_top - total:
				if Junction.in_mouth(chunk_index, zz):
					ok = false
				zz -= 2.0
			if ok:
				# upstream is +z on the own side, -z on the oncoming side; the
				# taper starts upstream and the jersey run follows it
				var up := 1.0 if side == 1 else -1.0
				var z_start := z_top if side == 1 else z_top - total
				for i in CONES_IN_TAPER:
					var t := float(i) / float(CONES_IN_TAPER)
					var z := z_start - up * float(i) * CONE_SPACING
					var tt := -z / L
					var road: float = _lerp(e.road, tt)
					var curb: float = _lerp(e.curb_in, tt)
					var x: float = lerpf(curb - 0.25, road + 0.35, t)
					placed.append(_rec(CONE, side, x, 0.0, z, 0.0, CONE_BASE))
				for j in JERSEY_RUN:
					var z := z_start - up * (taper_len + (float(j) + 0.5) * JERSEY_LEN)
					var tt := -z / L
					var x: float = _lerp(e.curb_in, tt) - JERSEY_ON_SHOULDER
					placed.append(_rec(JERSEY, side, x, 0.0, z, 0.0, JERSEY_LEN))
				taken.append([z_top + 1.0, z_top - total - 1.0])
		# Guardrail along the kerb line, one piece per station, none across
		# the crossing's mouth.
		if _rng.randf() < float(spec.rail) * d:
			for k in RoadChunkBuilder.STATIONS:
				var z := -seg * (float(k) + 0.5)
				if Junction.in_mouth(chunk_index, z) or Junction.in_mouth(chunk_index, z + seg / 2.0) or Junction.in_mouth(chunk_index, z - seg / 2.0):
					continue
				var tt := -z / L
				# posts on the kerb, the beam's face at the kerb's inner edge
				var x: float = _lerp(e.curb_in, tt)
				placed.append(_rec(RAIL, side, x, 0.0, z, 0.0, seg))
		# Bins at the foot of the lamps.
		var bins := _count(float(spec.bin) * d)
		var lamp_zs: Array = lamps[side].duplicate()  # picked with our RNG, never the global one
		for i in mini(bins, lamp_zs.size()):
			var pick := _rng.randi_range(0, lamp_zs.size() - 1)
			var lz: float = float(lamp_zs[pick])
			lamp_zs.remove_at(pick)
			var z := lz - BIN_BEHIND_LAMP * (1.0 if side == 1 else -1.0)
			if Junction.in_mouth(chunk_index, z):
				continue
			var tt := -z / L
			var x: float = _lerp(e.curb_out, tt) + BIN_FROM_KERB
			placed.append(_rec(BIN, side, x, 0.0, z, 0.0, BIN_W))
			taken.append([z + 0.6, z - 0.6])
		# Hydrants on the sidewalk, clear of lamps, bins and the work zone.
		var hydrants := _count(float(spec.hydrant) * d)
		for i in hydrants:
			for attempt in 6:
				var z := -_rng.randf_range(1.0, L - 1.0)
				if Junction.in_mouth(chunk_index, z) or _taken(taken, z):
					continue
				var tt := -z / L
				var x: float = _lerp(e.curb_out, tt) + HYDRANT_FROM_KERB
				placed.append(_rec(HYDRANT, side, x, 0.0, z, 0.0, HYDRANT_W))
				taken.append([z + CLEAR, z - CLEAR])
				break
		# Dumpsters: against the back wall of a lot deep enough to drive into,
		# long side to the road.
		if setback >= DUMPSTER_MIN_SETBACK and float(spec.dumpster) > 0.0:
			for lot in lots[side]:
				if _rng.randf() >= float(spec.dumpster) * d:
					continue
				var lz: float = float(lot[0])
				var frontage: float = float(lot[1])
				var z := lz + _rng.randf_range(-0.3, 0.3) * frontage
				if Junction.cleared(chunk_index, z + DUMPSTER_SIZE.x / 2.0, z - DUMPSTER_SIZE.x / 2.0):
					continue
				var tt := -z / L
				var x: float = _lerp(e.walk, tt) + RoadChunkBuilder.BUILDING_GAP + setback - DUMPSTER_WALL_GAP - DUMPSTER_SIZE.z / 2.0
				placed.append(_rec(DUMPSTER, side, x, 0.0, z, 0.0, DUMPSTER_SIZE.x))
	# Clamp to the buffers, then write transforms, collision and the record.
	var counts := {}
	for kind in KINDS:
		counts[kind] = 0
	var kept: Array = []
	for r in placed:
		var kind: String = r.kind
		if int(counts[kind]) >= int(CAP[kind]):
			continue
		counts[kind] = int(counts[kind]) + 1
		kept.append(r)
	var n := {}
	for kind in KINDS:
		n[kind] = 0
	var metal := root.get_node(^"KitColMetal") as StaticBody3D
	var concrete := root.get_node(^"KitColConcrete") as StaticBody3D
	var n_metal := 0
	var n_concrete := 0
	for r in kept:
		var kind: String = r.kind
		var side := float(r.side)
		var mm: MultiMesh = (root.get_node(NodePath(_mmi_name(kind))) as MultiMeshInstance3D).multimesh
		# The mesh's +x is "away from the road"; on the own side that is +x
		# already, on the oncoming side the piece is turned round.
		var turn := Basis() if side > 0.0 else Basis(Vector3.UP, PI)
		var xf := RoadChunkBuilder._xf_up(float(r.x) * side, 0.0, float(r.z), turn)
		mm.set_instance_transform(int(n[kind]), xf)
		n[kind] = int(n[kind]) + 1
		match kind:
			RAIL:
				var col := metal.get_node(NodePath("Shape%d" % n_metal)) as CollisionShape3D
				(col.shape as BoxShape3D).size = Vector3(COL_RAIL.x, COL_RAIL.y + f, float(r.len) + RoadChunkBuilder.BOUNDARY_OVERLAP)
				col.transform = RoadChunkBuilder._xf_up((float(r.x) + COL_RAIL.x / 2.0 - 0.02) * side, (COL_RAIL.y - f) / 2.0, float(r.z))
				col.disabled = false
				n_metal += 1
			DUMPSTER:
				var col := metal.get_node(NodePath("Shape%d" % n_metal)) as CollisionShape3D
				(col.shape as BoxShape3D).size = Vector3(DUMPSTER_SIZE.z, DUMPSTER_SIZE.y + f, DUMPSTER_SIZE.x)
				col.transform = RoadChunkBuilder._xf_up(float(r.x) * side, (DUMPSTER_SIZE.y - f) / 2.0, float(r.z))
				col.disabled = false
				n_metal += 1
			JERSEY:
				var col := concrete.get_node(NodePath("Shape%d" % n_concrete)) as CollisionShape3D
				(col.shape as BoxShape3D).size = Vector3(COL_JERSEY.x, COL_JERSEY.y + f, JERSEY_LEN)
				col.transform = RoadChunkBuilder._xf_up(float(r.x) * side, (COL_JERSEY.y - f) / 2.0, float(r.z))
				col.disabled = false
				n_concrete += 1
	for i in range(n_metal, metal.get_child_count()):
		(metal.get_child(i) as CollisionShape3D).disabled = true
	for i in range(n_concrete, concrete.get_child_count()):
		(concrete.get_child(i) as CollisionShape3D).disabled = true
	for kind in KINDS:
		var mmi := root.get_node(NodePath(_mmi_name(kind))) as MultiMeshInstance3D
		mmi.multimesh.visible_instance_count = int(n[kind])
		mmi.visible = int(n[kind]) > 0
	root.set_meta("kit", kept)

static func _rec(kind: String, side: int, x: float, y: float, z: float, yaw: float, length: float) -> Dictionary:
	return {"kind": kind, "side": side, "x": x, "y": y, "z": z, "yaw": yaw, "len": length}

static func _lerp(pair: Array, t: float) -> float:
	return lerpf(float(pair[0]), float(pair[1]), t)

## An expected count: the whole part, plus one more with the fraction's chance.
static func _count(expected: float) -> int:
	var whole := floori(expected)
	return whole + (1 if _rng.randf() < expected - float(whole) else 0)

static func _taken(taken: Array, z: float) -> bool:
	for t in taken:
		if z <= float(t[0]) and z >= float(t[1]):
			return true
	return false

## Whether a kind is real collision (for tests and tools).
static func collides(kind: String) -> bool:
	return kind in [RAIL, DUMPSTER, JERSEY]
