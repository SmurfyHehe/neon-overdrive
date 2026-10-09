class_name PersonKit
extends CockpitKit

# People pipeline, step 1 (2026-10-09): one generated body kit. Roy: "i hate
# that his lower body is just black legs". A person is built from code in the
# PS2 way (rigid segments, flat shading, vertex colours, no skinning, no
# textures) from a `look`: a small dictionary with one choice per row of the
# future character screen. The rows and their options are the tables below;
# `build()` turns a look into separate kits, one per rigid part, that the
# DriverModel seats on the pedals and the wheel and `standing()` stands up
# for the design sheet (tools/player_body_shots.gd).
#
# Proportions are a real adult fitted to the game: HEAD_H is one head and the
# average body stands about 7 heads tall (tests/view/person_kit.gd measures
# it); the height row scales every length but the head, the body row the
# widths. Male only for now (Roy, 2026-10-09). No helmet. The gloved mitten
# hands stay DriverModel's (hand_boxes): the sleeves here end at the cuff.
#
# Part spaces (each part is its own kit, so its own mesh and draw call):
#   torso     origin at the pelvis pivot, +y up the spine, -z the way he faces
#   head      origin at the top of the neck (the head's pivot)
#   upper_arm along +y from the shoulder to the elbow, ARM_UPPER long
#   forearm   along +y from the elbow to the wrist, ARM_LOWER long
#   thigh     along +y from the hip to the knee, THIGH long
#   shin      along +y from the knee to the ankle, SHIN long
#   foot      origin at the heel on the floor, the toe along -z, the ankle at
#             ANKLE (so a planted heel and a pedal pad pitch the foot)
# A limb is built along +y and aimed at its joints by DriverModel._aim; the
# left and right are built separately (mirrored geometry keeps its winding).
#
# Budget: under 1,500 triangles for the body kit (hands and trinkets apart),
# the whole seated driver with hands and bracelet under 3,000.

const HEAD_H := 0.255            # one head, chin to crown (a touch big, PS2 heads read)
const NECK := 0.05
const TORSO := 0.54              # pelvis pivot to the top of the shoulders
const SHOULDER_Y := 0.50         # the shoulder joint up the torso
const SHOULDER_X := 0.205        # half the distance between the shoulder joints (regular build)
const ARM_UPPER := 0.30
const ARM_LOWER := 0.26          # elbow to the cuff
const HIP_HALF := 0.09
const THIGH := 0.47
const SHIN := 0.45
const FOOT_LEN := 0.27           # heel to toe
const FOOT_W := 0.095
const SOLE_H := 0.025
const ANKLE := Vector3(0.0, 0.085, -0.055)   # the ankle joint over the heel, foot space

## Row 0, height: scales every length but the head (so a short man is a
## little under 7 heads, a tall one a little over, as people are).
const HEIGHTS := {"short": 0.93, "average": 1.0, "tall": 1.07}
## Row 1, body: build. Width and depth scales on the torso and limbs, a belly.
const BODIES := {
	"lean": {"w": 0.92, "d": 0.94, "belly": 0.0},
	"regular": {"w": 1.0, "d": 1.0, "belly": 0.0},
	"broad": {"w": 1.10, "d": 1.06, "belly": 0.015},
	"heavy": {"w": 1.16, "d": 1.14, "belly": 0.045},
}
## Row 2, skin: sodium-lit tones (the driver's #B9896A is the reference).
const SKINS := {
	"light": Color("#D2A98B"),
	"tan": Color("#B9896A"),
	"brown": Color("#8C5A3C"),
	"dark": Color("#5A3A28"),
}
## Row 3, hair or cap: a style and its colour.
const HAIRS := {
	"crop_dark": {"style": "crop", "col": Color("#2A1E16")},
	"crop_fair": {"style": "crop", "col": Color("#9A7A4A")},
	"crop_grey": {"style": "crop", "col": Color("#8E8E90")},
	"slick_dark": {"style": "slick", "col": Color("#1A120E")},
	"cap_navy": {"style": "cap", "col": Color("#1B1E25")},
	"cap_amber": {"style": "cap", "col": Color("#B8742A")},
	"beanie": {"style": "beanie", "col": Color("#2C3038")},
	"bald": {"style": "bald", "col": Color("#000000")},
}
## Row 4, jacket: the outfit. The jacket sets the trousers and shoes with it,
## so every combination reads as one person who dressed himself.
const JACKETS := {
	"bomber": {"style": "bomber", "jacket": Color("#1E2229"), "trim": Color("#FF8A1F"), "zip": Color("#C9CED6"),
		"trousers": Color("#1C2232"), "hem": Color("#232A3A"), "shoe": Color("#15171C"), "sole": Color("#C9CED6"), "lace": Color("#2C3038")},
	"denim": {"style": "denim", "jacket": Color("#2E3D5C"), "trim": Color("#3D4E70"), "zip": Color("#B8742A"),
		"trousers": Color("#12161E"), "hem": Color("#1A1F2A"), "shoe": Color("#2A2016"), "sole": Color("#4A3A2A"), "lace": Color("#8A5A2A")},
	"leather": {"style": "leather", "jacket": Color("#121318"), "trim": Color("#1E2026"), "zip": Color("#C9CED6"),
		"trousers": Color("#15171C"), "hem": Color("#15171C"), "shoe": Color("#0E0F12"), "sole": Color("#2C3038"), "lace": Color("#0E0F12")},
	"work": {"style": "work", "jacket": Color("#3A2E22"), "trim": Color("#FFC066"), "zip": Color("#2C3038"),
		"trousers": Color("#2F2A26"), "hem": Color("#3A342E"), "shoe": Color("#2A2016"), "sole": Color("#1A1612"), "lace": Color("#8A5A2A")},
}
## Row 5, gloves: colour of the glove and of the cuff band (DriverModel
## builds the hands). "car" takes the car's own pair (DriverModel.GLOVE_STYLES).
const GLOVES := {
	"car": {},
	"black_leather": {"glove": Color("#111216"), "cuff": Color("#8A5A2A")},
	"grey_fabric": {"glove": Color("#2A2E36"), "cuff": Color("#C9CED6")},
	"tan_leather": {"glove": Color("#8A5A2A"), "cuff": Color("#3A2E22")},
	"work": {"glove": Color("#3A2E22"), "cuff": Color("#FFC066")},
}
## Row 6, trinket: bracelet (the gold Cuban link, DriverModel), watch (left
## wrist, here), chain (round the neck, here), none.
const TRINKETS := ["bracelet", "watch", "chain", "none"]

const ROWS := ["height", "body", "skin", "hair", "jacket", "gloves", "trinket"]
const DEFAULT_LOOK := {"height": "average", "body": "regular", "skin": "tan", "hair": "cap_navy", "jacket": "bomber", "gloves": "car", "trinket": "bracelet"}
const BRACELET_TRI_RESERVE := 400   # the DriverModel bracelet, outside the body budget

const SILVER := Color("#C9CED6")
const GOLD := Color("#D9A441")
const BELT := Color("#0E0F12")
const BUCKLE := Color("#8E8E90")

## The options a row offers, in order.
static func options(row: String) -> Array:
	match row:
		"height": return HEIGHTS.keys()
		"body": return BODIES.keys()
		"skin": return SKINS.keys()
		"hair": return HAIRS.keys()
		"jacket": return JACKETS.keys()
		"gloves": return GLOVES.keys()
		"trinket": return TRINKETS.duplicate()
	return []

## A look with every row set: `partial` over the defaults, unknown choices
## dropped back to the default.
static func complete(partial: Dictionary) -> Dictionary:
	var look := DEFAULT_LOOK.duplicate()
	for row in ROWS:
		if partial.has(row) and options(row).has(partial[row]):
			look[row] = partial[row]
	return look

# ---------- primitives ----------

## Four points round a rectangle at height y: (-x,+z), (+x,+z), (+x,-z), (-x,-z).
static func ring(hx: float, hz: float, y: float, dx := 0.0, dz := 0.0) -> Array:
	return [Vector3(-hx + dx, y, hz + dz), Vector3(hx + dx, y, hz + dz), Vector3(hx + dx, y, -hz + dz), Vector3(-hx + dx, y, -hz + dz)]

## A closed loft between two 4-point rings `a` (near) and `b` (far), both
## ordered like ring(): the tapered boxes limbs and shoes are made of.
func loft(a: Array, b: Array, col: Color, basis := Basis.IDENTITY, origin := Vector3.ZERO) -> void:
	var pa := []
	var pb := []
	for i in 4:
		pa.append(origin + basis * (a[i] as Vector3))
		pb.append(origin + basis * (b[i] as Vector3))
	quad(pb[0], pb[1], pb[2], pb[3], col)
	quad(pa[3], pa[2], pa[1], pa[0], col)
	for i in 4:
		var j := (i + 1) % 4
		quad(pa[j], pb[j], pb[i], pa[i], col)

## A box that tapers from (hx0, hz0) at y0 to (hx1, hz1) at y1, centred on x = z = 0.
func taper(hx0: float, hz0: float, y0: float, hx1: float, hz1: float, y1: float, col: Color, basis := Basis.IDENTITY, origin := Vector3.ZERO, dz0 := 0.0, dz1 := 0.0) -> void:
	loft(ring(hx0, hz0, y0, 0.0, dz0), ring(hx1, hz1, y1, 0.0, dz1), col, basis, origin)

## Stretches everything built so far along y (the height row).
func scale_y(by: float) -> void:
	for i in _v.size():
		_v[i].y *= by

# ---------- the kit ----------

## Builds a look. Returns {"parts": name -> PersonKit, "joints": {...},
## "lengths": {torso, neck, arm_upper, arm_lower, thigh, shin, head} for this
## height, "tris": int (the body kit, hands and trinkets apart), "outfit":
## the jacket's dictionary, "look": the completed look}. Part names: torso,
## head, upper_arm_l/r, forearm_l/r, thigh_l/r, shin_l/r, foot_l/r, and watch
## when the trinket asks for it (hand space, the left hand); the chain is
## part of the torso.
static func build(partial: Dictionary) -> Dictionary:
	var look := complete(partial)
	var body: Dictionary = BODIES[look.body]
	var skin: Color = SKINS[look.skin]
	var hair: Dictionary = HAIRS[look.hair]
	var outfit: Dictionary = JACKETS[look.jacket]
	var h: float = HEIGHTS[look.height]
	var w: float = body.w
	var d: float = body.d
	var L := {"torso": TORSO * h, "neck": NECK * h, "arm_upper": ARM_UPPER * h, "arm_lower": ARM_LOWER * h,
		"thigh": THIGH * h, "shin": SHIN * h, "head": HEAD_H}
	var parts := {}
	parts["torso"] = _torso(outfit, skin, w, d, body.belly, look.trinket == "chain", h)
	parts["head"] = _head(skin, hair)
	for side in [-1, 1]:
		var s := "_l" if side < 0 else "_r"
		parts["upper_arm" + s] = _upper_arm(outfit, w, L.arm_upper)
		parts["forearm" + s] = _forearm(outfit, w, L.arm_lower)
		parts["thigh" + s] = _thigh(outfit, w, d, L.thigh)
		parts["shin" + s] = _shin(outfit, w, L.shin)
		parts["foot" + s] = _foot(outfit, side)
	if look.trinket == "watch":
		parts["watch"] = _watch()
	var tris := 0
	for p in parts.values():
		tris += (p as PersonKit).tri_count()
	var joints := {
		"neck": Vector3(0.0, L.torso + L.neck, 0.0),
		"shoulder_l": Vector3(-SHOULDER_X * w, SHOULDER_Y * h, 0.0),
		"shoulder_r": Vector3(SHOULDER_X * w, SHOULDER_Y * h, 0.0),
		"hip_l": Vector3(-HIP_HALF * w, 0.05, 0.0),
		"hip_r": Vector3(HIP_HALF * w, 0.05, 0.0),
		"ankle": ANKLE,
	}
	return {"parts": parts, "joints": joints, "lengths": L, "tris": tris, "outfit": outfit, "look": look}

## Standing height of a built body, heel to crown, in metres and in heads.
static func standing_height(built: Dictionary) -> float:
	var j: Dictionary = built.joints
	var L: Dictionary = built.lengths
	return ANKLE.y + L.shin + L.thigh - (j.hip_l as Vector3).y + (j.neck as Vector3).y + HEAD_H

static func heads_tall(built: Dictionary) -> float:
	return standing_height(built) / HEAD_H

## Torso, pelvis up: trousers at the hips, a belt, the jacket's body, chest,
## shoulders and collar, the neck. The jacket's trim is where the styles
## differ: the bomber's sodium shoulder stripes and chest flashes, the denim's
## pocket flaps and collar, the leather's lapels, the work jacket's amber
## reflective bands.
static func _torso(o: Dictionary, skin: Color, w: float, d: float, belly: float, chain: bool, h: float) -> PersonKit:
	var k := PersonKit.new()
	var J: Color = o.jacket
	# hips and seat in the trousers; the belt over them
	k.taper(0.17 * w, 0.115 * d, 0.0, 0.18 * w, 0.12 * d, 0.11, o.trousers, Basis.IDENTITY, Vector3.ZERO, 0.0, 0.0)
	k.box(Vector3(0.37 * w, 0.03, 0.25 * d), Vector3(0.0, 0.125, 0.0), BELT)
	k.box(Vector3(0.035, 0.028, 0.012), Vector3(0.0, 0.125, -0.125 * d), BUCKLE)
	# the jacket: waist up to the chest, the belly on the front
	k.taper(0.185 * w, 0.12 * d, 0.14, 0.215 * w, 0.135 * d, 0.34, J, Basis.IDENTITY, Vector3.ZERO, -belly, -belly * 0.5)
	# chest and shoulders: wider, a little forward at the top
	k.taper(0.215 * w, 0.135 * d, 0.34, 0.235 * w, 0.125 * d, 0.46, J, Basis.IDENTITY, Vector3.ZERO, -belly * 0.5, 0.0)
	k.taper(0.235 * w, 0.125 * d, 0.46, 0.205 * w, 0.105 * d, 0.53, J)
	# collar and neck
	k.box(Vector3(0.17 * w, 0.045, 0.16 * d), Vector3(0.0, 0.545, 0.005), J)
	k.cylinder(0.05, 0.53, TORSO + NECK + 0.01, Vector3.ZERO, skin, 8)
	# zip or placket down the front
	k.box(Vector3(0.014, 0.36, 0.008), Vector3(0.0, 0.33, -(0.135 * d + belly * 0.5 + 0.001)), o.zip)
	var front := -(0.135 * d + 0.004)   # the chest's face (he faces -z)
	match String(o.style):
		"bomber":
			for sx in [-1.0, 1.0]:
				k.box(Vector3(0.05, 0.012, 0.24 * d), Vector3(sx * 0.19 * w, 0.535, 0.0), o.trim)        # shoulder stripes
				k.box(Vector3(0.028, 0.07, 0.012), Vector3(sx * 0.10 * w, 0.40, front - belly * 0.5), o.trim)   # chest flashes
			k.box(Vector3(0.38 * w, 0.03, 0.25 * d), Vector3(0.0, 0.155, 0.0), Color("#15181E"))             # ribbed hem
		"denim":   # pocket flaps, seams, a pointed collar
			for sx in [-1.0, 1.0]:
				k.box(Vector3(0.09, 0.02, 0.01), Vector3(sx * 0.10 * w, 0.42, front), o.trim)              # flaps
				k.box(Vector3(0.006, 0.26, 0.009), Vector3(sx * 0.055 * w, 0.30, front), o.trim)           # seams
				k.box(Vector3(0.07, 0.06, 0.012), Vector3(sx * 0.06 * w, 0.52, front + 0.02), o.trim)      # collar points
		"leather":   # lapels and a yoke
			for sx in [-1.0, 1.0]:
				k.box(Vector3(0.055, 0.14, 0.012), Vector3(sx * 0.045 * w, 0.44, front), o.trim, Basis(Vector3.BACK, sx * 0.35))
			k.box(Vector3(0.40 * w, 0.05, 0.26 * d), Vector3(0.0, 0.49, 0.0), o.trim)
		_:   # work: reflective bands round the chest and the hem
			k.box(Vector3(0.44 * w, 0.025, 0.26 * d + 0.004), Vector3(0.0, 0.42, -belly * 0.4), o.trim)
			k.box(Vector3(0.38 * w, 0.025, 0.25 * d + 0.004), Vector3(0.0, 0.17, -belly * 0.5), o.trim)
	if chain:
		# a chain round the collar hanging to the chest: a V of flat links
		var n := 7
		for i in n:
			var t := float(i) / float(n - 1)
			var x := lerpf(-0.07, 0.07, t) * w
			var y := 0.52 - 0.07 * sin(t * PI)
			k.box(Vector3(0.012, 0.012, 0.006), Vector3(x, y, front - 0.002), SILVER, Basis(Vector3.BACK, 0.6 if i % 2 == 0 else -0.6))
		k.box(Vector3(0.02, 0.024, 0.006), Vector3(0.0, 0.445, front - 0.003), GOLD)   # the pendant
	k.scale_y(h)
	return k

## The head, neck top up: a jawed skull, a nose, ears and brows, no face
## (faces are an open question, 2026-10-09). The hair row adds a crop, a
## slicked-back shell, a cap with a peak, a beanie, or nothing.
static func _head(skin: Color, hair: Dictionary) -> PersonKit:
	var k := PersonKit.new()
	# jaw to cheekbones, cheekbones to the crown
	k.taper(0.065, 0.075, 0.0, 0.085, 0.10, 0.10, skin, Basis.IDENTITY, Vector3.ZERO, -0.012, 0.0)
	k.taper(0.085, 0.10, 0.10, 0.082, 0.098, 0.18, skin)
	k.taper(0.082, 0.098, 0.18, 0.055, 0.07, HEAD_H, skin)
	k.box(Vector3(0.032, 0.045, 0.028), Vector3(0.0, 0.085, -0.108), skin)     # nose
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.016, 0.035, 0.022), Vector3(sx * 0.09, 0.11, 0.005), skin)   # ears
		k.box(Vector3(0.032, 0.010, 0.014), Vector3(sx * 0.038, 0.135, -0.097), hair.col if hair.style != "bald" else Color("#2A1E16"))   # brows
	var c: Color = hair.col
	match String(hair.style):
		"crop":
			k.taper(0.084, 0.102, 0.135, 0.088, 0.105, 0.19, c, Basis.IDENTITY, Vector3(0.0, 0.0, 0.004))   # sides and back
			k.taper(0.088, 0.105, 0.19, 0.060, 0.072, HEAD_H + 0.012, c, Basis.IDENTITY, Vector3(0.0, 0.0, 0.004))
			k.box(Vector3(0.16, 0.02, 0.03), Vector3(0.0, 0.17, -0.09), c)        # hairline over the brow
		"slick":
			k.taper(0.086, 0.104, 0.14, 0.09, 0.108, 0.195, c, Basis.IDENTITY, Vector3(0.0, 0.0, 0.01))
			k.taper(0.09, 0.108, 0.195, 0.06, 0.08, HEAD_H + 0.018, c, Basis.IDENTITY, Vector3(0.0, 0.0, 0.02))
			k.box(Vector3(0.17, 0.016, 0.05), Vector3(0.0, 0.178, -0.085), c)     # swept back from the brow
		"cap":
			k.taper(0.086, 0.104, 0.155, 0.09, 0.108, 0.20, c, Basis.IDENTITY, Vector3(0.0, 0.0, 0.004))   # crown band
			k.taper(0.09, 0.108, 0.20, 0.055, 0.07, HEAD_H + 0.02, c, Basis.IDENTITY, Vector3(0.0, 0.0, 0.004))
			k.box(Vector3(0.17, 0.012, 0.085), Vector3(0.0, 0.16, -0.14), c)       # peak
			k.box(Vector3(0.02, 0.012, 0.02), Vector3(0.0, HEAD_H + 0.026, 0.004), c)   # button
			# a little hair under the band at the back and sides
			k.taper(0.084, 0.100, 0.135, 0.087, 0.104, 0.158, Color("#2A1E16"), Basis.IDENTITY, Vector3(0.0, 0.0, 0.006))
		"beanie":
			k.taper(0.088, 0.106, 0.135, 0.094, 0.112, 0.20, c, Basis.IDENTITY, Vector3(0.0, 0.0, 0.004))
			k.taper(0.094, 0.112, 0.20, 0.06, 0.075, HEAD_H + 0.04, c, Basis.IDENTITY, Vector3(0.0, 0.0, 0.006))
			k.box(Vector3(0.19, 0.03, 0.22), Vector3(0.0, 0.15, 0.004), c.darkened(0.15))   # the folded brim
		_:
			pass
	return k

## Upper arm, shoulder down: the sleeve, with the seam at the shoulder.
static func _upper_arm(o: Dictionary, w: float, len: float) -> PersonKit:
	var k := PersonKit.new()
	k.taper(0.055 * w, 0.058 * w, 0.0, 0.046 * w, 0.048 * w, len, o.jacket)
	k.box(Vector3(0.12 * w, 0.03, 0.125 * w), Vector3(0.0, 0.015, 0.0), o.jacket)   # the shoulder cap
	return k

## Forearm, elbow to the cuff: the sleeve narrowing to the wrist.
static func _forearm(o: Dictionary, w: float, len: float) -> PersonKit:
	var k := PersonKit.new()
	k.box(Vector3(0.09 * w, 0.05, 0.095 * w), Vector3(0.0, 0.0, 0.0), o.jacket)       # elbow
	k.taper(0.046 * w, 0.048 * w, 0.02, 0.036 * w, 0.038 * w, len, o.jacket)
	return k

## Thigh, hip to the knee: the trouser leg, a seam down the outside.
static func _thigh(o: Dictionary, w: float, d: float, len: float) -> PersonKit:
	var k := PersonKit.new()
	k.taper(0.085 * w, 0.09 * d, 0.0, 0.07 * w, 0.075 * d, len, o.trousers)
	k.box(Vector3(0.17 * w, 0.06, 0.18 * d), Vector3(0.0, 0.02, 0.0), o.trousers)   # the hip joint, filled
	return k

## Shin, knee to the ankle: the knee, the leg, the hem over the shoe.
static func _shin(o: Dictionary, w: float, len: float) -> PersonKit:
	var k := PersonKit.new()
	k.box(Vector3(0.13 * w, 0.07, 0.14 * w), Vector3(0.0, 0.015, 0.0), o.trousers)       # knee
	k.taper(0.062 * w, 0.066 * w, 0.03, 0.052 * w, 0.056 * w, len - 0.05, o.trousers)
	k.taper(0.052 * w, 0.056 * w, len - 0.05, 0.056 * w, 0.06 * w, len + 0.01, o.hem)   # the hem flares over the shoe
	return k

## A shoe, heel on the floor at the origin, the toe along -z: sole, heel
## block, upper tapering to a toe cap, the tongue and laces up the front.
static func _foot(o: Dictionary, side: int) -> PersonKit:
	var k := PersonKit.new()
	var sx := float(side)
	# built along +y then turned so +y runs to -z (the toe) and +z is up
	var b := Basis(Vector3.RIGHT, -PI / 2.0)
	var hw := FOOT_W * 0.5
	# sole: the heel end a little narrower, lifted at the toe
	k.loft(ring(hw * 0.85, SOLE_H * 0.5, 0.0, 0.0, SOLE_H * 0.5), ring(hw, SOLE_H * 0.5, FOOT_LEN, 0.0, SOLE_H * 0.5 + 0.012), o.sole, b)
	# heel counter and the quarter (over the ankle), the vamp down to the toe cap
	k.loft(ring(hw * 0.88, 0.055, 0.0, 0.0, SOLE_H + 0.055), ring(hw * 0.95, 0.045, 0.12, 0.0, SOLE_H + 0.05), o.shoe, b)
	k.loft(ring(hw * 0.95, 0.045, 0.12, 0.0, SOLE_H + 0.05), ring(hw * 0.9, 0.028, 0.22, 0.0, SOLE_H + 0.034), o.shoe, b)
	k.loft(ring(hw * 0.9, 0.028, 0.22, 0.0, SOLE_H + 0.034), ring(hw * 0.6, 0.012, FOOT_LEN, 0.0, SOLE_H + 0.024), o.shoe, b)
	# the tongue, and three laces across it
	k.loft(ring(hw * 0.5, 0.012, 0.10, 0.0, SOLE_H + 0.102), ring(hw * 0.45, 0.008, 0.20, 0.0, SOLE_H + 0.066), o.lace, b)
	for i in 3:
		var y := 0.115 + 0.03 * i
		k.box(Vector3(hw * 1.1, 0.006, 0.006), b * Vector3(0.0, y, SOLE_H + 0.106 - 0.012 * i), o.lace)
	# the ankle collar on the inside leans in a touch (left and right differ)
	k.box(Vector3(0.012, 0.03, 0.04), b * Vector3(sx * hw * 0.8, 0.05, SOLE_H + 0.08), o.shoe)
	return k

## A wristwatch for the left hand, hand space (DriverModel._hand_mesh: the
## wrist runs along +z, the cuff from CUFF_Z0 to CUFF_Z1 at radius CUFF_R).
static func _watch() -> PersonKit:
	var k := PersonKit.new()
	var r := 0.031 + 0.004
	var z := 0.078
	var c := Vector3(-0.03, 0.0, 0.0)   # the left hand's wrist centre (side -1 * WRIST_X)
	k.ring_sector(0.031, r, 0.0, TAU, z - 0.007, z + 0.007, Color("#15171C"), 10)   # the strap
	k.offset(c)
	k.box(Vector3(0.026, 0.008, 0.026), c + Vector3(0.0, r + 0.001, z), Color("#2C3038"))   # the case, on top of the wrist
	k.box(Vector3(0.02, 0.004, 0.02), c + Vector3(0.0, r + 0.007, z), SILVER)
	return k

# ---------- standing figure ----------

## The body kit stood up on the floor at the origin, facing -z, arms at the
## sides: the design sheet and the height test. Every part on `mat`.
static func standing(partial: Dictionary, mat: Material) -> Node3D:
	var built := build(partial)
	var parts: Dictionary = built.parts
	var j: Dictionary = built.joints
	var L: Dictionary = built.lengths
	var fig := Node3D.new()
	fig.name = "Person"
	var hip_y: float = ANKLE.y + L.shin + L.thigh - (j.hip_l as Vector3).y
	var pelvis := Vector3(0.0, hip_y, 0.0)
	var torso := (parts.torso as PersonKit).instance(mat, "Torso")
	torso.position = pelvis
	fig.add_child(torso)
	var head := (parts.head as PersonKit).instance(mat, "Head")
	head.position = pelvis + (j.neck as Vector3)
	fig.add_child(head)
	for side in [-1, 1]:
		var s := "_l" if side < 0 else "_r"
		var sx := float(side)
		var hip: Vector3 = pelvis + (j["hip" + s] as Vector3)
		var down := Basis(Vector3.RIGHT, PI)   # +y pointing down
		var thigh := (parts["thigh" + s] as PersonKit).instance(mat, "Thigh" + s.to_upper())
		thigh.transform = Transform3D(down, hip)
		fig.add_child(thigh)
		var knee := hip + Vector3(0.0, -L.thigh, 0.0)
		var shin := (parts["shin" + s] as PersonKit).instance(mat, "Shin" + s.to_upper())
		shin.transform = Transform3D(down, knee)
		fig.add_child(shin)
		var foot := (parts["foot" + s] as PersonKit).instance(mat, "Foot" + s.to_upper())
		foot.position = knee + Vector3(0.0, -L.shin, 0.0) - ANKLE
		fig.add_child(foot)
		var shoulder: Vector3 = pelvis + (j["shoulder" + s] as Vector3)
		var arm_down := Basis(Vector3.BACK, sx * -0.08) * down  # a touch out from the body
		var upper := (parts["upper_arm" + s] as PersonKit).instance(mat, "UpperArm" + s.to_upper())
		upper.transform = Transform3D(arm_down, shoulder)
		fig.add_child(upper)
		var elbow := shoulder + arm_down * Vector3(0.0, L.arm_upper, 0.0)
		var fore := (parts["forearm" + s] as PersonKit).instance(mat, "Forearm" + s.to_upper())
		fore.transform = Transform3D(arm_down, elbow)
		fig.add_child(fore)
	return fig
