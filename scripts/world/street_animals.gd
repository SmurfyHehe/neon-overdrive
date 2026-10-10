extends RefCounted

# Eyes in the headlights (world step 6, A1, 2026-10-10): a cat or a dog at a
# shop front or an alley mouth. Two eye dots shine back when the headlight
# beam sweeps over it, and after a moment in the light it slinks off along
# the wall or into the side street and is gone.
#
# Per chunk: one MultiMesh ("Animals", one draw call, only on a chunk with
# an animal) of a small dark body with two eye quads; the eyes' emission is
# the instance's custom data r, set from the CPU. Where they sit is hashed
# per chunk (a recycled chunk matches a fresh one, the road's random
# sequence is untouched). Per frame, StreetAnimals.step (from game.gd) does
# one dot product per animal on the three chunks round the car: the angle
# between the beam axis and the animal, against the spot's cone. Nothing
# else runs until an animal flees, and then it is one transform write.
#
# The beam is whatever the player's "Headlights" SpotLight3D says (its aim
# and spot_angle), so the low/high beam of the lights PR (#361) narrows and
# widens the shine without this file knowing.
#
# Picks are mine: the chances, the hold before it bolts, speeds, sizes.

const SideStreets := preload("res://scripts/world/side_streets.gd")

const CAPACITY := 3           # per chunk
const MOUTH_CHANCE := 60      # per cent: an animal at a side street's corner
const SHOP_CHANCE := 30       # per cent: at a shop / diner / garage front
const DOG_CHANCE := 30        # per cent, else a cat
const CAT_SCALE := 0.85
const DOG_SCALE := 1.35
const CAT_SPEED := 2.4        # m/s when it bolts
const DOG_SPEED := 3.2
const HOLD := 0.35            # s in the beam before it goes
const FLEE_TIME := 2.0        # s on the move, then hidden
const SEE_NEAR := 3.0         # m: closer than this the eyes are below the bonnet
const SEE_FAR := 75.0         # m: beyond this the dots are under a pixel anyway
const FADE_FROM := 50.0
const CHUNK_REACH := 170.0    # m: chunks further off are skipped whole
const EYE_COLOR := Color(1.0, 0.78, 0.38)  # amber eyeshine (palette's amber)
const FUR := Color(0.045, 0.04, 0.038)

## Switch (NEON_ANIMALS=0 turns them off, for before/after runs).
static var enabled := OS.get_environment("NEON_ANIMALS") != "0"

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

varying float eye;
varying float shine;

void vertex() {
	eye = UV2.y;
	shine = INSTANCE_CUSTOM.r;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	// the eye quads are black until the beam finds them
	EMISSION = eye > 0.5 ? vec3(1.0, 0.78, 0.38) * shine * 1.7 : vec3(0.0);
}
"""

static var _mesh: ArrayMesh
static var _material: ShaderMaterial

static func mesh() -> ArrayMesh:
	if _mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# a crouched cat-sized shape, 1 unit = a cat; nose along -Z
		SideStreets._box(st, Vector3(0.0, 0.17, 0.02), Vector3(0.18, 0.2, 0.44), FUR, 0)
		SideStreets._box(st, Vector3(0.0, 0.26, -0.26), Vector3(0.15, 0.14, 0.14), FUR, 0)
		SideStreets._box(st, Vector3(0.0, 0.12, 0.32), Vector3(0.05, 0.05, 0.22), FUR, 0)  # tail
		for ex in [-0.04, 0.04]:
			_eye(st, Vector3(ex, 0.28, -0.335), 0.028)
		_mesh = st.commit()
	return _mesh

## An eye: a small square facing -Z, tagged UV2.y = 1 so the shader lights it.
static func _eye(st: SurfaceTool, c: Vector3, r: float) -> void:
	var p := [c + Vector3(-r, -r, 0.0), c + Vector3(r, -r, 0.0), c + Vector3(r, r, 0.0), c + Vector3(-r, r, 0.0)]
	SideStreets._face(st, p, Vector3.FORWARD, [Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK], Vector2(0.0, 1.0))

static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material

static func new_multimesh() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh()
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Animals"
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

# ---------- placement (at chunk build) ----------

## Places this chunk's animals and writes their state to the root's
## "animals" meta: [{pos, basis, flee, speed, scale, shine, hold, t, state}]
## in chunk-local space (state 0 sitting, 1 fleeing, 2 gone). walks:
## [start_own, end_own, start_onc, end_onc] pavement outer edges.
static func update(root: Node3D, chunk_index: int, infos: Array, mouths: Array, walks: Array, setback: float) -> void:
	var mm: MultiMesh = (root.get_node(^"Animals") as MultiMeshInstance3D).multimesh
	var list := []
	if enabled:
		var k := 0
		for m in mouths:
			if list.size() >= CAPACITY:
				break
			if posmod(hash([chunk_index, "animal_mouth", k]), 100) >= MOUTH_CHANCE:
				k += 1
				continue
			var side := int(m.side)
			var z := float(m.z)
			var corner := 1.0 if posmod(hash([chunk_index, "animal_corner", k]), 2) == 0 else -1.0
			var t: float = -z / RoadChunkBuilder.CHUNK_LEN
			var walk: float = lerpf(walks[0], walks[1], t) if side == 1 else lerpf(walks[2], walks[3], t)
			# on the main pavement at the mouth's corner, by the kerb of the
			# side street, facing the road; it bolts into the side street
			var az := z + corner * (SideStreets.MOUTH_HALF + 0.5)
			var ax := walk - 0.5
			list.append(_make(chunk_index, k, ax * float(side), az, side, Vector3(float(side), 0.0, 0.0), 0.0))
			k += 1
		for info in infos:
			if list.size() >= CAPACITY:
				break
			if bool(info.empty) or not (String(info.type) in ["shop", "diner", "garage"]):
				continue
			if posmod(hash([chunk_index, "animal_shop", k]), 100) >= SHOP_CHANCE:
				k += 1
				continue
			var side := int(info.side)
			var d := float(info.d)
			var corner := 1.0 if posmod(hash([chunk_index, "animal_end", k]), 2) == 0 else -1.0
			# tucked against the front wall near one end, facing along the
			# wall; it bolts along the wall toward the far end
			var ax := float(info.front_x_abs) - 0.4
			var az := float(info.z) + corner * (d / 2.0 - 1.0)
			list.append(_make(chunk_index, k, ax * float(side), az, side, Vector3(0.0, 0.0, -corner), -corner))
			k += 1
	for i in list.size():
		var a: Dictionary = list[i]
		mm.set_instance_transform(i, _xf(a))
		mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
	mm.visible_instance_count = list.size()
	root.set_meta("animals", list)

## One animal at road-description (x, z), facing `face` (+1 = up the road
## toward the car, -1 = away, 0 = across toward the road) and fleeing along
## `flee` (road-description direction, x across, z along).
static func _make(chunk_index: int, k: int, x: float, z: float, side: int, flee: Vector3, face: float) -> Dictionary:
	var dog := posmod(hash([chunk_index, "animal_kind", k]), 100) < DOG_CHANCE
	# -Z is the nose: face +1 looks up the road (+z), 0 looks at the road
	var look := Vector3(-float(side), 0.0, 0.0) if face == 0.0 else Vector3(0.0, 0.0, face)
	var xf := RoadChunkBuilder._xf_up(x, 0.0, z, Basis.looking_at(look, Vector3.UP))
	var flee_xf := RoadChunkBuilder._xf_up(x, 0.0, z, Basis())
	return {
		"pos": xf.origin, "basis": xf.basis, "up": flee_xf.basis,
		"flee": (flee_xf.basis * flee).normalized(),
		"speed": DOG_SPEED if dog else CAT_SPEED, "scale": DOG_SCALE if dog else CAT_SCALE,
		"shine": 0.0, "hold": 0.0, "t": 0.0, "state": 0,
	}

static func _xf(a: Dictionary) -> Transform3D:
	var s: float = a.scale if int(a.state) < 2 else 0.0
	return Transform3D((a.basis as Basis).scaled(Vector3(s, s, s)), a.pos)

# ---------- per frame ----------

## The beam: [origin, direction, cos(half angle), on]. From the player's
## "Headlights" spot when it has one, else the car's forward.
static func beam_of(player: Node3D) -> Array:
	var on := true
	if player.get("headlights_on") != null:
		on = bool(player.get("headlights_on"))
	var spot := player.get_node_or_null("Headlights") as SpotLight3D
	if spot != null:
		var g := spot.global_transform
		return [g.origin, -g.basis.z.normalized(), cos(deg_to_rad(spot.spot_angle)), on and spot.visible and spot.light_energy > 0.0]
	var pg := player.global_transform
	return [pg.origin + Vector3(0.0, 0.6, 0.0), -pg.basis.z.normalized(), cos(deg_to_rad(30.0)), on]

## Shine for an animal `dist` m away at cos(angle) `c` from the beam axis
## with cone edge cos `edge`: full inside the inner half of the cone, off at
## its edge; fades out past FADE_FROM.
static func shine_for(c: float, edge: float, dist: float) -> float:
	if dist < SEE_NEAR or dist > SEE_FAR:
		return 0.0
	var inner := cos(acos(edge) * 0.5)
	var a := smoothstep(edge, inner, c)
	var d := 1.0 - smoothstep(FADE_FROM, SEE_FAR, dist)
	return a * d

## Advances every animal on the chunks near the player. chunks: game.gd's
## chunk_pool ([{root, index}]) or a plain Array of roots.
static func step(chunks: Array, player: Node3D, delta: float) -> void:
	if not enabled or player == null:
		return
	var beam := beam_of(player)
	var origin: Vector3 = beam[0]
	var axis: Vector3 = beam[1]
	var edge: float = beam[2]
	var on: bool = beam[3]
	for c in chunks:
		var root: Node3D = c.root if c is Dictionary else c
		if not root.has_meta("animals"):
			continue
		var list: Array = root.get_meta("animals")
		if list.is_empty():
			continue
		var g := root.global_transform
		if g.origin.distance_to(origin) > CHUNK_REACH:
			continue
		var mm: MultiMesh = (root.get_node(^"Animals") as MultiMeshInstance3D).multimesh
		for i in list.size():
			var a: Dictionary = list[i]
			if int(a.state) == 2:
				continue
			var wp: Vector3 = g * (a.pos as Vector3)
			var v := wp - origin
			var dist := v.length()
			var target := 0.0
			if on and dist > 0.001:
				target = shine_for(v.dot(axis) / dist, edge, dist)
			if int(a.state) == 1:
				target *= clampf(1.0 - float(a.t) / FLEE_TIME, 0.0, 1.0)
			var shine: float = lerpf(float(a.shine), target, minf(1.0, delta * 12.0))
			if absf(shine - float(a.shine)) > 0.002:
				a.shine = shine
				mm.set_instance_custom_data(i, Color(shine, 0.0, 0.0, 0.0))
			if int(a.state) == 0:
				a.hold = float(a.hold) + delta if shine > 0.6 else 0.0
				if float(a.hold) >= HOLD:
					a.state = 1
					a.t = 0.0
					a.basis = _facing(a)
			if int(a.state) == 1:
				a.t = float(a.t) + delta
				a.pos = (a.pos as Vector3) + (a.flee as Vector3) * float(a.speed) * delta
				if float(a.t) >= FLEE_TIME:
					a.state = 2
				mm.set_instance_transform(i, _xf(a))

## The basis of an animal turned to run along its flee direction (chunk-local).
static func _facing(a: Dictionary) -> Basis:
	var up: Basis = a.up
	var f: Vector3 = a.flee
	return Basis.looking_at(f, up.y)
