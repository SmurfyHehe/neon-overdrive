extends RefCounted
# Security floodlights (street life L6, 2026-10-14): a warehouse, garage or
# hangar front in the industrial districts carries a motion floodlight.
# Dark until the car is TRIGGER_M away, then it snaps on with a wide
# cool-white pool over the whole lot (arcade: the lot, not a cone), holds
# HOLD_S seconds after the car has passed and fades out.
#
# Per chunk: "FloodHeads" (the lamp box on the wall) and "FloodPools" (the
# pool on the ground), one MultiMesh each, drawn only on chunks that have
# one. Where they stand is a hash of the chunk and the building slot. Per
# frame, FloodLights.step (from game.gd) does one distance per light on the
# chunks round the car and writes the brightness (instance custom data r)
# only while a light is switching on or fading out: nothing else runs.

const RoadChunkBuilder := preload("res://scripts/world/road_chunk_builder.gd")

## Per district: chance (%) that a fitting building has one, and which
## types fit. Left out: none.
const BY_DISTRICT := {
	"industrial": {"chance": 45, "types": ["warehouse", "garage"]},
	"docks":      {"chance": 55, "types": ["warehouse", "garage", "hangar"]},
	"airport":    {"chance": 40, "types": ["hangar", "warehouse", "parking"]},
	"strip":      {"chance": 25, "types": ["garage"]},
	"lofts":      {"chance": 20, "types": ["warehouse", "garage"]},
	"canyon":     {"chance": 30, "types": ["warehouse", "garage"]},
}
const CAP := 2                 # per chunk
const TRIGGER_M := 38.0        # the car this close switches it on
const HOLD_S := 10.0           # stays on this long after the car has gone
const RISE_S := 0.15
const FALL_S := 1.2
const HEAD_H := 5.2            # on the wall, m (lower on a low building)
const HEAD_ENERGY := 4.0
const POOL_SPILL := 3.0        # the pool runs this far past the lot, over the pavement
const POOL_ALONG_EXTRA := 6.0
const CHUNK_REACH := 220.0     # chunks farther than this are not looked at
const RANGE_END := 220.0

const STATE_OFF := 0
const STATE_RISE := 1
const STATE_HOLD := 2
const STATE_FALL := 3

static var enabled := true
static var _enabled_read := false
static var _head_mesh: ArrayMesh
static var _head_mat: ShaderMaterial
static var _pool_mat: ShaderMaterial

static func _read_enabled() -> void:
	if _enabled_read:
		return
	_enabled_read = true
	if OS.has_environment("NEON_FLOOD_LIGHTS"):
		enabled = OS.get_environment("NEON_FLOOD_LIGHTS") != "0"

const HEAD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 color = vec3(0.85, 0.9, 1.0);
uniform vec3 off_color = vec3(0.1, 0.1, 0.11);
uniform float energy = 4.0;
varying float k;
varying float lamp;
void vertex() {
	k = INSTANCE_CUSTOM.r;
	lamp = UV2.x;
}
void fragment() {
	ALBEDO = lamp > 0.5 ? mix(off_color, color * energy, k) : vec3(0.16, 0.16, 0.17);
}
"""

const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled, cull_back;
uniform vec3 color = vec3(0.85, 0.9, 1.0);
uniform float gain = 0.55;
uniform vec2 fade = vec2(120.0, 190.0);
varying float k;
varying float depth;
void vertex() {
	k = INSTANCE_CUSTOM.r;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	// a flatter, harder-edged pool than a street lamp's: the lot is lit
	// end to end, soft only at the rim
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = 1.0 - smoothstep(0.55, 1.0, r);
	float far = 1.0 - smoothstep(fade.x, fade.y, depth);
	ALBEDO = color * gain * a * far * k;
}
"""

static func _box(st: SurfaceTool, tag: float, center: Vector3, size: Vector3) -> void:
	var h := size / 2.0
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.FORWARD, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
	]
	for f in faces:
		st.set_normal(f[0])
		st.set_uv2(Vector2(tag, 0.0))
		for i in [1, 2, 3, 1, 3, 4]:
			st.add_vertex(center + f[i])

## The lamp: a bracket out of the wall (local +x is into the lot, away from
## the wall) and the lamp box tilted at the lot. Origin on the wall face.
static func head_mesh() -> ArrayMesh:
	if _head_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(st, 0.0, Vector3(0.3, 0.0, 0.0), Vector3(0.6, 0.08, 0.08))
		_box(st, 0.0, Vector3(0.6, -0.1, 0.0), Vector3(0.12, 0.3, 0.12))
		_box(st, 1.0, Vector3(0.62, -0.3, 0.0), Vector3(0.36, 0.26, 0.5))
		_head_mesh = st.commit()
	return _head_mesh

static func head_material() -> ShaderMaterial:
	if _head_mat == null:
		var sh := Shader.new()
		sh.code = HEAD_SHADER
		_head_mat = ShaderMaterial.new()
		_head_mat.shader = sh
		_head_mat.set_shader_parameter("energy", HEAD_ENERGY)
	return _head_mat

static func pool_material() -> ShaderMaterial:
	if _pool_mat == null:
		var sh := Shader.new()
		sh.code = POOL_SHADER
		_pool_mat = ShaderMaterial.new()
		_pool_mat.shader = sh
	return _pool_mat

static func _new_mm(node_name: String, mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = RANGE_END
	return mmi

static func new_nodes() -> Array:
	return [_new_mm("FloodHeads", head_mesh(), head_material()),
		_new_mm("FloodPools", RoadChunkBuilder._get_pool_mesh(), pool_material())]

## Which buildings carry one: [{x (signed, the wall face), z, side, y,
## pool_x (signed centre), pool_w (across), pool_l (along)}]. walks: the
## pavement's outer edge per side at the chunk's start and end
## [own0, own1, onc0, onc1].
static func plan(chunk_index: int, district: String, infos: Array, walks: Array) -> Array:
	_read_enabled()
	var out := []
	if not enabled or not BY_DISTRICT.has(district):
		return out
	var spec: Dictionary = BY_DISTRICT[district]
	var k := 0
	for info in infos:
		if out.size() >= CAP:
			break
		k += 1
		if bool(info.get("empty", true)) or not info.has("front_x_abs"):
			continue
		if not (String(info.type) in spec.types):
			continue
		if posmod(hash([chunk_index, "flood light", k]), 100) >= int(spec.chance):
			continue
		var side := int(info.side)
		var z := float(info.z)
		var t: float = -z / RoadChunkBuilder.CHUNK_LEN
		var walk: float = lerpf(float(walks[0]), float(walks[1]), t) if side == 1 else lerpf(float(walks[2]), float(walks[3]), t)
		var wall := float(info.front_x_abs)
		var y := minf(HEAD_H, float(info.get("h", HEAD_H + 1.0)) - 0.6)
		var lot := maxf(wall - walk, 0.0)
		out.append({"x": wall * float(side), "z": z, "side": side, "y": y,
			"pool_x": ((wall + walk) / 2.0 - POOL_SPILL / 2.0) * float(side),
			"pool_w": lot + POOL_SPILL, "pool_l": float(info.d) + POOL_ALONG_EXTRA})
	return out

static func update(root: Node3D, chunk_index: int, district: String, infos: Array, walks: Array) -> void:
	var heads: MultiMesh = (root.get_node(^"FloodHeads") as MultiMeshInstance3D).multimesh
	var pools: MultiMesh = (root.get_node(^"FloodPools") as MultiMeshInstance3D).multimesh
	var list := plan(chunk_index, district, infos, walks)
	var floods := []
	for i in list.size():
		var f: Dictionary = list[i]
		var side := int(f.side)
		# local +x is away from the wall: toward the road on the own side
		var turn := Basis(Vector3.UP, PI) if side == 1 else Basis()
		var head_xf := RoadChunkBuilder._xf_up(float(f.x), float(f.y), float(f.z), turn)
		heads.set_instance_transform(i, head_xf)
		heads.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
		pools.set_instance_transform(i, RoadChunkBuilder._xf(float(f.pool_x), RoadChunkBuilder.POOL_Y + 0.01, float(f.z), Basis.from_scale(Vector3(float(f.pool_w), 1.0, float(f.pool_l)))))
		pools.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
		floods.append({"pos": head_xf.origin, "state": STATE_OFF, "t": 0.0, "i": i})
	heads.visible_instance_count = list.size()
	pools.visible_instance_count = list.size()
	root.set_meta("floods", floods)

static func _write(root: Node3D, i: int, k: float) -> void:
	var c := Color(k, 0.0, 0.0, 0.0)
	(root.get_node(^"FloodHeads") as MultiMeshInstance3D).multimesh.set_instance_custom_data(i, c)
	(root.get_node(^"FloodPools") as MultiMeshInstance3D).multimesh.set_instance_custom_data(i, c)

## Once a frame from game.gd: chunks is the chunk pool ({root, index} or
## the roots), player the car. Writes only while a light switches.
static func step(chunks: Array, player: Node3D, delta: float) -> void:
	if not enabled or player == null:
		return
	var p := player.global_position
	for c in chunks:
		var root: Node3D = c.root if c is Dictionary else c
		if not root.has_meta("floods"):
			continue
		var list: Array = root.get_meta("floods")
		if list.is_empty():
			continue
		var g := root.global_transform
		if g.origin.distance_to(p) > CHUNK_REACH:
			continue
		for f in list:
			var near := (g * (f.pos as Vector3)).distance_to(p) < TRIGGER_M
			match int(f.state):
				STATE_OFF:
					if near:
						f.state = STATE_RISE
						f.t = 0.0
				STATE_RISE:
					f.t = float(f.t) + delta
					var k := minf(float(f.t) / RISE_S, 1.0)
					_write(root, int(f.i), k)
					if k >= 1.0:
						f.state = STATE_HOLD
						f.t = 0.0
				STATE_HOLD:
					if near:
						f.t = 0.0
					else:
						f.t = float(f.t) + delta
						if float(f.t) >= HOLD_S:
							f.state = STATE_FALL
							f.t = 0.0
				STATE_FALL:
					f.t = float(f.t) + delta
					var k := 1.0 - minf(float(f.t) / FALL_S, 1.0)
					_write(root, int(f.i), k)
					if k <= 0.0:
						f.state = STATE_OFF
						f.t = 0.0
