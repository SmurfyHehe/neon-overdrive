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
## Render layer the car's own meshes move to, so the blob shadow (which only
## projects onto layer 1) darkens the road under the car but not the car.
const CAR_LAYER := 2

## Contact shadow picture: one shared texture, so a preset change redraws it
## for every car at once (set_soft_shadow).
const BLOB_W := 64
const BLOB_H := 128
static var _blob_tex: ImageTexture
static var _soft := true

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

	var blob := Decal.new()
	blob.name = "BlobShadow"
	# Box the decal projects through: a bit wider and longer than the body,
	# deep enough to reach the road through suspension travel and body roll.
	var half_w := 0.9
	for n in v.get_children():
		if n.has_meta("half_w"):
			half_w = float(n.get_meta("half_w"))
	blob.size = Vector3(half_w * 2.0 + 0.6, 1.4, half_length * 2.0 + 0.6)
	blob.position = Vector3(0.0, 0.25, 0.0)
	blob.texture_albedo = _get_blob_tex()
	blob.modulate = Color(0.0, 0.0, 0.0, 0.9)
	blob.cull_mask = 1
	v.add_child(blob)

## Medium and High (CarPaint.set_preset): the shadow takes the car's
## footprint, darkest under the floor, so the car sits on the road. Low
## keeps the plain round blob.
static func set_soft_shadow(on: bool) -> void:
	if on == _soft:
		return
	_soft = on
	if _blob_tex != null:
		_blob_tex.update(_blob_image())

static func _get_blob_tex() -> ImageTexture:
	if _blob_tex == null:
		_soft = CarPaint.tier() >= CarPaint.TIER_MEDIUM
		_blob_tex = ImageTexture.create_from_image(_blob_image())
	return _blob_tex

static func _blob_image() -> Image:
	var img := Image.create(BLOB_W, BLOB_H, false, Image.FORMAT_RGBA8)
	for y in BLOB_H:
		for x in BLOB_W:
			var u := (float(x) + 0.5) / BLOB_W * 2.0 - 1.0
			var w := (float(y) + 0.5) / BLOB_H * 2.0 - 1.0
			var a: float
			if _soft:
				# A rounded box: full under the floor, gone at the decal's edge.
				var q := Vector2(maxf(absf(u) - 0.5, 0.0) / 0.5, maxf(absf(w) - 0.66, 0.0) / 0.34)
				a = 1.0 - smoothstep(0.0, 1.0, q.length())
				a *= a
			else:
				var d := Vector2(u, w).length()
				a = 1.0 if d <= 0.0 else clampf(lerpf(1.0, 0.7, d / 0.55) if d < 0.55 else lerpf(0.7, 0.0, (d - 0.55) / 0.45), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return img
