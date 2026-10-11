extends RefCounted
class_name CarFx

# Headlights and a blob shadow for a car (stage A, 2026-10-04). The world is
# dark on purpose now (Look Board B), so the road ahead needs real light on
# it to read, and the car needs something under it so it sits on the road
# instead of floating -- the cheap version from docs/research/RESEARCH-cheap-pretty.md
# item 5, not a shadow map. Written for any Vehicle, so traffic and police can
# reuse it later (they may want headlights off for cost; see the flag).

const HEADLIGHT_RANGE := 55.0
const HEADLIGHT_ANGLE := 30.0   # degrees, half-angle of the cone
const HEADLIGHT_ENERGY := 28.0
const HEADLIGHT_DIP := 5.0      # degrees down from level
# NIGHT LIGHTING PASS (2026-10-11): the spot alone barely showed on the road.
# Its light arrives at the asphalt at a 5-10 degree grazing angle, the asphalt
# albedo is 0.085, and the fog darkens the rest, so the lit wedge measured
# RGB 13-20 against 6-18 unlit (tools/night_shots.gd, 2030_spot3). Pushing
# the energy up far enough to fix that blew out the car in front instead. So
# the road beam is now painted: a Decal projecting a warm emissive wedge onto
# whatever is under it (the road, over hills too), the PS2 trick. The spot
# stays for lighting cars, walls and posts in the beam. One decal per car with
# headlights; the blob shadow below is already one, so the cost is known.
const BEAM_LENGTH := 34.0       # m of road the painted beam covers
const BEAM_WIDTH := 11.0        # m across at the far end
const BEAM_ENERGY := 0.7
const BEAM_COLOR := Color(1.0, 0.8, 0.55)    # warm halogen, towards amber (baked into the texture: Decal.modulate tints albedo only)
## Render layer the car's own meshes move to, so the blob shadow (which only
## projects onto layer 1) darkens the road under the car but not the car.
const CAR_LAYER := 2

static var _blob_tex: GradientTexture2D
static var _beam_tex: ImageTexture

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
		spot.spot_angle_attenuation = 0.85
		spot.light_energy = HEADLIGHT_ENERGY
		spot.light_color = Color(1.0, 0.94, 0.82)
		spot.shadow_enabled = false
		v.add_child(spot)

		var beam := Decal.new()
		beam.name = "HeadlightBeam"
		# Starts at the bumper, reaches BEAM_LENGTH ahead. Deep enough (y) to
		# keep painting the road over a crest or dip within that distance.
		beam.size = Vector3(BEAM_WIDTH, 3.0, BEAM_LENGTH)
		beam.position = Vector3(0.0, 0.3, -half_length - BEAM_LENGTH / 2.0 + 0.5)
		beam.texture_emission = _get_beam_tex()
		beam.emission_energy = BEAM_ENERGY
		beam.albedo_mix = 0.0
		beam.cull_mask = 1  # the road, not the car (CAR_LAYER)
		v.add_child(beam)

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

## The beam's footprint: narrow and hot at the bumper, wider and fading by the
## far end, with soft edges. +V (down the image) is the car's forward (-Z).
static func _get_beam_tex() -> ImageTexture:
	if _beam_tex == null:
		var w := 64
		var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for y in h:
			var t := float(y) / float(h - 1)            # 0 bumper .. 1 far end
			var half := lerpf(0.22, 0.5, t)            # beam half-width, in UV
			var along := 1.0 - smoothstep(0.2, 1.0, t)   # brightest at the bumper, gone by the far end
			along *= smoothstep(0.0, 0.06, t)           # and does not start inside the bumper
			for x in w:
				var u := absf(float(x) / float(w - 1) - 0.5)
				var across := 1.0 - smoothstep(half * 0.45, half, u)
				var c := along * across
				img.set_pixel(x, y, BEAM_COLOR * c)
		_beam_tex = ImageTexture.create_from_image(img)
	return _beam_tex

## Damage: a dead head lamp dims both the spot and the painted beam.
static func set_headlight_share(v: Vehicle, share: float) -> void:
	var spot := v.get_node_or_null("Headlights") as SpotLight3D
	if spot != null:
		spot.light_energy = HEADLIGHT_ENERGY * share
		spot.visible = share > 0.0
	var beam := v.get_node_or_null("HeadlightBeam") as Decal
	if beam != null:
		beam.emission_energy = BEAM_ENERGY * share
		beam.visible = share > 0.0

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
