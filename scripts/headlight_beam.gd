class_name HeadlightBeam
extends Node3D

# Headlight beam (polish pass, 2026-10-08): the beam you can see in the haze.
# One faint additive cone per lamp (both walls drawn), brightest near the
# lens, fading to nothing by BEAM_LEN. The light on the road is still CarFx's
# SpotLight3D. GraphicsSettings flag "headlight_beam" switches the cones.

const BEAM_LEN := 22.0         # m
const BEAM_SPREAD := 0.26      # cone radius per metre (about 15 degrees)
const BEAM_DIP := 4.0          # degrees down, a touch above the light's own dip
const BEAM_FLAT := 0.3         # height of the beam as a share of its width
const BEAM_COLOR := Color(1.0, 0.92, 0.78)
const BEAM_ENERGY := 0.12

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 color : source_color;
uniform float energy = 0.12;
void fragment() {
	// UV.y runs 0 at the lens to 1 at the far end (CylinderMesh, flipped below).
	float along = 1.0 - UV.y;
	float fade = pow(1.0 - along, 1.6) * smoothstep(0.0, 0.04, along);
	// Seen end-on (the chase camera) the walls are at a grazing angle and
	// the haze is deep, so grazing counts most; face-on walls (a side view)
	// keep a third, so the cone never shows a hard outline.
	float graze = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = color * energy * fade * (0.35 + 0.65 * graze);
}
"""

static var _shader: Shader
static var _mesh: CylinderMesh

var cones: Array[MeshInstance3D] = []

## lamps: lens positions in the car's space. The cones point down the car's -Z.
func _init(lamps: Array) -> void:
	name = "HeadlightBeam"
	var mat := ShaderMaterial.new()
	mat.shader = _get_shader()
	mat.set_shader_parameter("color", BEAM_COLOR)
	mat.set_shader_parameter("energy", BEAM_ENERGY)
	for p in lamps:
		var mi := MeshInstance3D.new()
		mi.mesh = _get_mesh()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Cylinder axis is +Y: tip it forward (-Z), the narrow end at the lens,
		# and squash it top to bottom (local Z ends up vertical) into a wide,
		# shallow low beam that stays under the horizon.
		mi.basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0 - BEAM_DIP)) * Basis.from_scale(Vector3(1.0, 1.0, BEAM_FLAT))
		mi.position = p + mi.basis * Vector3(0.0, BEAM_LEN / 2.0, 0.0)
		add_child(mi)
		cones.append(mi)

func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)
	apply_graphics()

func apply_graphics() -> void:
	visible = GraphicsSettings.is_on("headlight_beam")

static func _get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = BEAM_SHADER
	return _shader

static func _get_mesh() -> CylinderMesh:
	if _mesh == null:
		_mesh = CylinderMesh.new()
		_mesh.top_radius = BEAM_SPREAD * BEAM_LEN   # +Y end: far away once tipped
		_mesh.bottom_radius = 0.08
		_mesh.height = BEAM_LEN
		_mesh.radial_segments = 16
		_mesh.rings = 1
		_mesh.cap_top = false
		_mesh.cap_bottom = false
	return _mesh
