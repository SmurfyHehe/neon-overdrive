extends RefCounted
# Sprinklers in the dead hours (street life L9, 2026-10-14): on the strip
# of ground between the pavement and the houses (residential, hillside),
# the airport's verges and a few downtown planters, sprinkler heads tick on
# between 3:30 and 5:00 a.m. and throw fans of water through the lamp
# light; nobody about to see them but you.
#
# ZERO per-frame script work. One MultiMesh per chunk ("Sprinklers") of
# upright cards, one shared ShaderMaterial: the sweep is TIME, the hours are
# one `clock` uniform (minutes since 8 p.m.) that game.gd sets from the
# night clock. Outside the window the cards draw nothing. Where they stand
# is a hash of the chunk and slot.

const RoadChunkBuilder := preload("res://scripts/world/road_chunk_builder.gd")
const Junction := preload("res://scripts/world/junction.gd")

## Per district: chance (%) per side per chunk of a run of heads, and how
## many heads in the run. Left out: none.
const BY_DISTRICT := {
	"residential": {"chance": 55, "heads": 2},
	"hillside":    {"chance": 45, "heads": 2},
	"airport":     {"chance": 40, "heads": 2},
	"downtown":    {"chance": 10, "heads": 1},
	"lofts":       {"chance": 12, "heads": 1},
}
const CAP := 4                      # per chunk
const HEAD_GAP := 9.0               # m between heads in a run
const OFF_WALK := 0.9               # m past the pavement's outer edge
const CARD := Vector2(2.8, 1.4)     # the fan card, m
## Minutes since 8 p.m.: 3:30 to 5:00 a.m.
const WINDOW := Vector2(450.0, 540.0)
const RANGE_END := 110.0

static var enabled := true
static var _enabled_read := false
static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

static func _read_enabled() -> void:
	if _enabled_read:
		return
	_enabled_read = true
	if OS.has_environment("NEON_SPRINKLERS"):
		enabled = OS.get_environment("NEON_SPRINKLERS") != "0"

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform float clock = -1.0;
uniform vec2 window = vec2(450.0, 540.0);
varying float phase;
varying float depth;
void vertex() {
	phase = INSTANCE_CUSTOM.r;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	// the card: x across (-0.5..0.5), y up (0 at the head, 1 at the top)
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);
	float r = length(vec2(p.x, p.y * 0.8));
	float a = atan(p.x, p.y);                  // 0 straight up
	float sweep = sin(TIME * 0.9 + phase * 6.28) * 0.75;
	float lobe = 1.0 - smoothstep(0.45, 0.85, abs(a - sweep));
	// radial streaks that fly outward, over a faint mist (exaggerated: it
	// has to read from a car at 60 km/h)
	float streak = smoothstep(0.5, 0.8, fract(a * 9.0 + TIME * 0.3 + phase)) * smoothstep(0.3, 0.6, fract(r * 5.0 - TIME * 2.2));
	float arc = (1.0 - smoothstep(0.75, 1.0, r)) * smoothstep(0.03, 0.12, r);
	float on = smoothstep(window.x, window.x + 8.0, clock) * (1.0 - smoothstep(window.y - 8.0, window.y, clock));
	float near = smoothstep(3.0, 8.0, depth);
	ALBEDO = vec3(1.0, 0.88, 0.7);  // water lit amber by the lamps
	ALPHA = lobe * arc * on * near * (0.14 + 0.5 * streak);
}
"""

## A unit upright card (x across, y up, foot at the origin), scaled per
## instance to CARD; its AABB covers the scaled card.
static func mesh() -> ArrayMesh:
	if _mesh == null:
		var verts := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
		var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh.custom_aabb = AABB(Vector3(-0.5, 0.0, -0.1), Vector3(1.0, 1.0, 0.2))
	return _mesh

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("window", WINDOW)
	return _mat

## Minutes since 8 p.m., from the night clock (game.gd, each frame).
static func set_clock(minutes: float) -> void:
	material().set_shader_parameter("clock", minutes)

static func active(minutes: float) -> bool:
	return minutes >= WINDOW.x and minutes <= WINDOW.y

static func new_multimesh() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh()
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sprinklers"
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = RANGE_END
	return mmi

## [{x (signed), z, side, phase}]. walks: [own0, own1, onc0, onc1].
static func plan(chunk_index: int, district: String, walks: Array, covered: bool = false) -> Array:
	_read_enabled()
	var out := []
	if not enabled or covered or not BY_DISTRICT.has(district):
		return out
	var spec: Dictionary = BY_DISTRICT[district]
	for side in [1, -1]:
		if out.size() >= CAP:
			break
		if posmod(hash([chunk_index, side, "sprinklers"]), 100) >= int(spec.chance):
			continue
		var z0 := -6.0 - float(posmod(hash([chunk_index, side, "sprinkler z"]), 30))
		for k in int(spec.heads):
			if out.size() >= CAP:
				break
			var z := z0 - float(k) * HEAD_GAP
			if z < -RoadChunkBuilder.CHUNK_LEN + 1.0 or Junction.near(chunk_index, z, Junction.MOUTH_HALF + 2.0):
				continue
			var t: float = -z / RoadChunkBuilder.CHUNK_LEN
			var walk: float = lerpf(float(walks[0]), float(walks[1]), t) if side == 1 else lerpf(float(walks[2]), float(walks[3]), t)
			out.append({"x": (walk + OFF_WALK) * float(side), "z": z, "side": side,
				"phase": float(posmod(hash([chunk_index, side, k, "sprinkler phase"]), 53)) / 53.0})
	return out

static func update(root: Node3D, chunk_index: int, district: String, walks: Array, covered: bool = false) -> void:
	var mm: MultiMesh = (root.get_node(^"Sprinklers") as MultiMeshInstance3D).multimesh
	var list := plan(chunk_index, district, walks, covered)
	for i in list.size():
		var s: Dictionary = list[i]
		# the card stands along the road (its face toward the road)
		mm.set_instance_transform(i, RoadChunkBuilder._xf_up(float(s.x), 0.0, float(s.z), Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3(CARD.x, CARD.y, 1.0))))
		mm.set_instance_custom_data(i, Color(float(s.phase), 0.0, 0.0, 0.0))
	mm.visible_instance_count = list.size()
	root.set_meta("sprinklers", list)
