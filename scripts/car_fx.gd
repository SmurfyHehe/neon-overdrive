extends RefCounted
class_name CarFx

# Headlights and a blob shadow for a car (stage A, 2026-10-04). The world is
# dark on purpose now (Look Board B), so the road ahead needs real light on
# it to read, and the car needs something under it so it sits on the road
# instead of floating -- the cheap version from RESEARCH-cheap-pretty.md
# item 5, not a shadow map. Written for any Vehicle, so traffic and police can
# reuse it later (they may want headlights off for cost; see the flag).

const HEADLIGHT_RANGE := 60.0
## Polish pass (2026-10-08): wider (was 30) with a softer edge, so the lit
## patch reaches the lane edges and fades instead of ending in a hard oval.
## (A low-beam projector texture was tried: on the Mobile renderer it blacked
## the light out entirely, so the shape stays the plain cone.)
const HEADLIGHT_ANGLE := 38.0   # degrees, half-angle of the cone
const HEADLIGHT_ENERGY := 30.0
const HEADLIGHT_DIP := 5.0      # degrees down from level
## Render layer the car's own meshes move to, so the blob shadow (which only
## projects onto layer 1) darkens the road under the car but not the car.
const CAR_LAYER := 2

static var _blob_tex: GradientTexture2D

static func attach(v: Vehicle, half_length: float, headlights: bool = true) -> void:
	for n in v.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 << (CAR_LAYER - 1)

	if headlights:
		var spot := SpotLight3D.new()
		spot.name = "Headlights"
		# A SpotLight3D shines along its local -Z, the car's forward.
		spot.position = Vector3(0.0, 0.62, -half_length + 0.1)
		spot.rotation_degrees = Vector3(-HEADLIGHT_DIP, 0.0, 0.0)
		spot.spot_range = HEADLIGHT_RANGE
		spot.spot_angle = HEADLIGHT_ANGLE
		spot.spot_angle_attenuation = 0.5
		spot.light_energy = HEADLIGHT_ENERGY
		spot.light_color = Color(1.0, 0.94, 0.82)
		spot.shadow_enabled = false
		v.add_child(spot)
		v.add_child(HeadlightBeam.new(_lamp_positions(v, half_length)))

	var blob := Decal.new()
	blob.name = "BlobShadow"
	# Box the decal projects through: a bit wider and longer than the body,
	# deep enough to reach the road through suspension travel and body roll.
	blob.size = Vector3(2.3, 1.4, half_length * 2.0 + 0.5)
	blob.position = Vector3(0.0, 0.25, 0.0)
	blob.texture_albedo = _get_blob_tex()
	blob.modulate = Color(0.0, 0.0, 0.0, 0.8)
	blob.cull_mask = 1
	v.add_child(blob)

## Headlight lens positions in the car's space: the body's "headlights" meta
## (P1 coupe) when it has one, else two lamps either side of the nose.
static func _lamp_positions(v: Vehicle, half_length: float) -> Array:
	for n in v.get_children():
		if n is Node3D and n.has_meta("headlights"):
			var out := []
			for p in n.get_meta("headlights"):
				out.append((n as Node3D).transform * Vector3(p))
			return out
	return [Vector3(-0.6, 0.62, -half_length), Vector3(0.6, 0.62, -half_length)]

static func _get_blob_tex() -> GradientTexture2D:
	if _blob_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
		_blob_tex = GradientTexture2D.new()
		_blob_tex.gradient = grad
		_blob_tex.fill = GradientTexture2D.FILL_RADIAL
		_blob_tex.fill_from = Vector2(0.5, 0.5)
		_blob_tex.fill_to = Vector2(1.0, 0.5)
		_blob_tex.width = 64
		_blob_tex.height = 64
	return _blob_tex
