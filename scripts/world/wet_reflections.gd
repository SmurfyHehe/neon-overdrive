extends RefCounted

# Fake wet-road reflections (docs/research/RESEARCH-cheap-pretty.md, item 7).
# A wet road mirrors every light above it as a streak that runs down the road
# toward the viewer. We draw the streak, not the mirror: one flat additive
# quad on the tarmac under each light, brightest under the lamp and fading
# along the road. No screen-space reflections, no extra lights, no per-frame
# CPU: the lamp smears are a MultiMesh built with each road chunk (next to
# "LampPools"), and each car carries a 2-instance MultiMesh behind its tail
# lamps that moves with the car for free. The only runtime writes are
# set_wetness() (two shader uniforms) and set_tail_brake() (one instance
# colour, only when a car's brake state flips).
#
# Everything scales with `wetness`, 0 (dry road: nothing drawn) to 1. The
# rain branch (scripts/world/weather.gd, PR #341) owns the weather; game.gd
# feeds its wetness in when that script is present, and NEON_WET=<0..1> or
# --wet=<0..1> (benchmark args) pins it either way. Without the rain branch
# the road is drawn wet (1.0) so the look can be judged.
# No class_name on purpose: preload it, so no class cache refresh is needed.

## Lamp smear quad, m: across the road, then along it.
const SMEAR_W := 2.2
const SMEAR_LEN := 26.0
## Just above the light pools (RoadChunkBuilder.POOL_Y 0.045); depth is never
## written or tested so this only keeps the maths tidy.
const SMEAR_Y := 0.055
## Tail smear quad, m: across, then how far it trails behind the lamp.
const TAIL_W := 0.7
const TAIL_LEN := 8.0
## Tail quads sit this far above the road at rest: the body dips under load
## and the road is depth-tested, so a quad at road level would vanish.
const TAIL_LIFT := 0.1
## Sodium orange and the sheet's tail red (tests/core/palette.gd), linear.
const LAMP_TINT := Color(1.0, 0.55, 0.2)
const TAIL_TINT := Color(1.0, 0.16, 0.05)
const LAMP_ENERGY := 1.4
const TAIL_ENERGY := 1.2
## Tail smears brighten this much over the running level under braking.
const BRAKE_GAIN := 1.5
## Lamp smears fade out between these distances, like the pools (110-170).
const FADE := Vector2(110.0, 170.0)

## One shader for both: `along` is 0 at the light, 1 at the far end of the
## quad. Lamp smears run both ways from the lamp (UV.y 0.5 is the lamp);
## tail smears run one way (UV.y 0 is the lamp). COLOR is the MultiMesh
## instance colour, white x brake gain for tails, unused (white) for lamps.
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform vec3 tint = vec3(1.0, 0.55, 0.2);
uniform float energy = 0.55;
uniform float wet = 1.0;
uniform float one_sided = 0.0;
uniform vec2 fade = vec2(110.0, 170.0);
varying float v_k;
void vertex() {
	float d = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	v_k = 1.0 - smoothstep(fade.x, fade.y, d);
}
void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float along = mix(abs(UV.y * 2.0 - 1.0), UV.y, one_sided);
	// A narrow bright core across, a long soft fall-off along.
	float across = exp(-x * x * 7.0);
	float len = 1.0 - smoothstep(0.0, 1.0, along);
	len *= len;
	ALBEDO = tint * energy * wet * v_k * across * len * COLOR.rgb;
}
"""

const RoadWet := preload("res://scripts/world/road_wet.gd")

static var wetness := 1.0
static var _lamp_mat: ShaderMaterial
static var _tail_mat: ShaderMaterial
static var _quad: PlaneMesh
static var _tail_points := {}  # "kind|build" -> Array[Vector3], NPC tail lamp centres

## 0 dry .. 1 soaked: the one entry point for every wet-road visual. Two
## uniform writes here, plus the asphalt and puddles (road_wet.gd); nothing
## else moves.
static func set_wetness(w: float) -> void:
	wetness = clampf(w, 0.0, 1.0)
	if _lamp_mat != null:
		_lamp_mat.set_shader_parameter("wet", wetness)
	if _tail_mat != null:
		_tail_mat.set_shader_parameter("wet", wetness)
	RoadWet.set_wetness(wetness)

static func is_on() -> bool:
	return wetness > 0.0

## The unit quad both smears scale from: PlaneMesh lies in XZ with UV 0..1,
## UV.y running along -Z to +Z.
static func quad_mesh() -> PlaneMesh:
	if _quad == null:
		_quad = PlaneMesh.new()
		_quad.size = Vector2.ONE
	return _quad

static func lamp_mat() -> ShaderMaterial:
	if _lamp_mat == null:
		_lamp_mat = _make_mat(LAMP_TINT, LAMP_ENERGY, 0.0)
	return _lamp_mat

static func tail_mat() -> ShaderMaterial:
	if _tail_mat == null:
		_tail_mat = _make_mat(TAIL_TINT, TAIL_ENERGY, 1.0)
	return _tail_mat

static func _make_mat(tint: Color, energy: float, one_sided: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("wet", wetness)
	m.set_shader_parameter("one_sided", one_sided)
	m.set_shader_parameter("fade", FADE)
	return m

## Scale for a lamp smear: the unit quad stretched to SMEAR_W x SMEAR_LEN.
static func lamp_smear_basis() -> Basis:
	return Basis.from_scale(Vector3(SMEAR_W, 1.0, SMEAR_LEN))

# ---------- tail smears ----------

## Puts a "TailSmears" MultiMesh under `vis` (a chassis visual): one quad
## behind each tail lamp, on the ground, trailing TAIL_LEN m behind the car
## (+Z is the car's rear). `lamps` are the lamp centres in vis space,
## `ground_y` the road at rest in vis space. Returns null when the car has no
## tail lamps we know of.
static func attach_tail(vis: Node3D, lamps: Array, ground_y: float) -> MultiMeshInstance3D:
	if lamps.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad_mesh()
	mm.instance_count = lamps.size()
	var rear_z := -INF
	for p in lamps:
		rear_z = maxf(rear_z, (p as Vector3).z)
	for i in lamps.size():
		var p: Vector3 = lamps[i]
		# UV.y 0 (the lamp end) is the quad's -Z edge: the quad spans
		# z = rear_z - 0.3 .. rear_z - 0.3 + TAIL_LEN, so it starts just
		# under the bumper and trails out behind.
		var z0 := rear_z - 0.3
		var xf := Transform3D(Basis.from_scale(Vector3(TAIL_W, 1.0, TAIL_LEN)), Vector3(p.x, ground_y + TAIL_LIFT, z0 + TAIL_LEN / 2.0))
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TailSmears"
	mmi.multimesh = mm
	mmi.material_override = tail_mat()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = TAIL_LEN
	vis.add_child(mmi)
	return mmi

## Brake 0..1 for one car's tail smears. Callers only call this when the
## brake state actually changes (see TrafficCar._update_lamps).
static func set_tail_brake(vis: Node3D, brake: float) -> void:
	var mmi := vis.get_node_or_null(^"TailSmears") as MultiMeshInstance3D
	if mmi == null:
		return
	var c := Color.WHITE * (1.0 + BRAKE_GAIN * clampf(brake, 0.0, 1.0))
	for i in mmi.multimesh.instance_count:
		mmi.multimesh.set_instance_color(i, c)

## Tail lamp centres and the ground height for a chassis visual, in its
## space: the P1 coupe's "tail_lights" meta, or a sheet car's tail flares
## (NpcCarBuilder builds one flare quad per lamp, every corner at the lamp's
## centre, as the body mesh's last surface). {} when unknown.
static func tail_info(vis: Node3D) -> Dictionary:
	if vis.has_meta("tail_lights"):
		return {"lamps": Array(vis.get_meta("tail_lights")), "ground_y": P1CoupeBuilder.BODY_LIFT}
	if vis.has_meta("kind") and vis.has_meta("build"):
		var kind := String(vis.get_meta("kind"))
		var build := String(vis.get_meta("build"))
		var body := vis.get_node_or_null(^"Body") as MeshInstance3D
		if body == null:
			return {}
		return {"lamps": _npc_tail_points(kind, build, body), "ground_y": body.position.y}
	return {}

static func _npc_tail_points(kind: String, build: String, body: MeshInstance3D) -> Array:
	var key := "%s|%s" % [kind, build]
	if _tail_points.has(key):
		return _tail_points[key]
	var out := []
	var mesh := body.mesh as ArrayMesh
	if mesh != null and mesh.get_surface_count() > 0:
		var last := mesh.get_surface_count() - 1
		var arrays := mesh.surface_get_arrays(last)
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		if uvs != null:  # only the flare surface carries UVs
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := v + body.position
				if not out.has(p):
					out.append(p)
	_tail_points[key] = out
	return out
