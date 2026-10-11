class_name BobbleSculpt
extends RefCounted

# Sculpts the dash bobble figures (interiors B1, 2026-10-11): the shapes behind
# every id in BobbleFigures. BobbleHead owns the slot, the spring and the
# shader; this file owns what a figure looks like.
#
# House style (the brief's rules): about 7 cm tall, the head about 45% of the
# height, a simple painted face, a round black base carrying the crew's mark
# (a bar in the crew's colour) or the shop's mark (a hex nut). Every figure
# has one oversized signature prop, one exaggerated feature and a pose that
# tells the character, in two or three colours from its crew's own palette.
# Silhouette first: no two figures share a pose or a head outline. Flat shaded
# vertex colours, well under 600 triangles, ONE mesh.
#
# Figure space: y up, y = 0 at the base's underside, +z toward the driver (the
# figure faces +z), +x toward the passenger door. The driver sees the figure
# from its front-left; the windscreen is at -z.
#
# Parts: build(id) returns an Array of {kit, w0, w1, y0, y1, pivot}. A part's
# vertices take the bob weight w0 below y0 rising to w1 above y1 (constant w0
# when y1 <= y0) and tilt about `pivot` (figure space). The standard person is
# body 0, neck 0 -> 1, head 1 about the neck's foot. Figures with their own
# spring somewhere else (the hula dancer's waist, the surfer's base) or extra
# loose bits (the skeleton's jaw, the cat's paw, the cop's finger) add parts.

# ---- palette (BobbleFigures has the shared ROADMAP colours) ----
const INK := BobbleFigures.INK
const BONE := BobbleFigures.BONE
const SILVER := BobbleFigures.SILVER
const NAVY := BobbleFigures.NAVY
const NAVY_DEEP := BobbleFigures.NAVY_DEEP
const SODIUM := BobbleFigures.SODIUM
const AMBER := BobbleFigures.AMBER
const RUST := BobbleFigures.RUST
const MOSS := BobbleFigures.MOSS
const CHARCOAL := BobbleFigures.CHARCOAL
const BRASS := BobbleFigures.BRASS
const SLATE := BobbleFigures.SLATE
const COPPER := BobbleFigures.COPPER
const OIL := BobbleFigures.OIL
const TAN := BobbleFigures.TAN
const GOLD := BobbleFigures.GOLD
const WOOD := BobbleFigures.WOOD
const FUR := BobbleFigures.FUR
const FUR_DARK := BobbleFigures.FUR_DARK
const RED := BobbleFigures.RED
const GREY := BobbleFigures.GREY
const POLICE_BLUE := BobbleFigures.POLICE_BLUE
const SKIN := BobbleFigures.SKIN
const SKIN_PALE := BobbleFigures.SKIN_PALE
const SKIN_DARK := BobbleFigures.SKIN_DARK

# ---- the standard person (m) ----
const BASE_R := 0.019
const BASE_H := 0.006
const LEG_Y0 := 0.006
const LEG_Y1 := 0.018
const TORSO_C := Vector3(0.0, 0.026, 0.0)
const TORSO_SIZE := Vector3(0.020, 0.016, 0.012)
const SHOULDER_Y := 0.032
const SHOULDER_X := 0.011
const NECK_Y0 := 0.034
const NECK_Y1 := 0.040
const NECK_R := 0.004
const HEAD_R := 0.0165
const HEAD_C := Vector3(0.0, 0.0565, 0.0)
const ARM_R := 0.0028

## One figure under construction: the three standard kits plus extra parts.
class Fig:
	var body := CockpitKit.new()
	var neck := CockpitKit.new()
	var head := CockpitKit.new()
	var extra: Array = []
	var neck_y0 := BobbleSculpt.NECK_Y0
	var neck_y1 := BobbleSculpt.NECK_Y1
	var head_c := BobbleSculpt.HEAD_C
	var head_r := BobbleSculpt.HEAD_R
	var head_scale := Vector3.ONE
	## The head pivot's x and z (the neck's foot); its y is neck_y0.
	var axis := Vector2.ZERO

	func pivot() -> Vector3:
		return Vector3(axis.x, neck_y0, axis.y)

	## Adds a part that swings on its own: weight `w` about `at`.
	func loose(kit: CockpitKit, w: float, at: Vector3) -> void:
		extra.append({"kit": kit, "w0": w, "w1": w, "y0": 0.0, "y1": 0.0, "pivot": at})

	func parts() -> Array:
		var p := pivot()
		var out: Array = [
			{"kit": body, "w0": 0.0, "w1": 0.0, "y0": 0.0, "y1": 0.0, "pivot": p},
			{"kit": neck, "w0": 0.0, "w1": 1.0, "y0": neck_y0, "y1": neck_y1, "pivot": p},
			{"kit": head, "w0": 1.0, "w1": 1.0, "y0": 0.0, "y1": 0.0, "pivot": p},
		]
		out.append_array(extra)
		return out

	## The z of the face's surface at the head's centre height.
	func front() -> float:
		return head_c.z + head_r * head_scale.z

# ---------- entry ----------

## The parts of figure `id` (see the file comment). Unknown ids build nothing.
static func build(id: String, spec: Dictionary) -> Array:
	var f := Fig.new()
	var s := BobbleSculpt.new()
	if not s.has_method("fig_" + id):
		return []
	s.call("fig_" + id, f, spec)
	return f.parts()

# ---------- shape helpers ----------

## A faceted ellipsoid: `segs` around, `rings` bands, flat shaded.
static func sphere(k: CockpitKit, c: Vector3, r: float, col: Color, scale := Vector3.ONE, segs := 8, rings := 5) -> void:
	var levels: Array = []
	for ri in range(1, rings):
		var th := PI * float(ri) / rings
		var ring := []
		for i in segs:
			var a := TAU * float(i) / segs
			ring.append(c + Vector3(cos(a) * sin(th) * r * scale.x, cos(th) * r * scale.y, sin(a) * sin(th) * r * scale.z))
		levels.append(ring)
	var top := c + Vector3(0.0, r * scale.y, 0.0)
	var bot := c - Vector3(0.0, r * scale.y, 0.0)
	var first: Array = levels[0]
	var last: Array = levels[levels.size() - 1]
	for i in segs:
		var j := (i + 1) % segs
		k.tri(top, first[j], first[i], col)
		k.tri(bot, last[i], last[j], col)
	for li in range(levels.size() - 1):
		var up: Array = levels[li]
		var lo: Array = levels[li + 1]
		for i in segs:
			var j := (i + 1) % segs
			k.quad(lo[i], up[i], up[j], lo[j], col)

## A closed truncated cone along +y from y0 (radius r0) to y0 + h (radius r1),
## optionally rotated about its foot.
static func frustum(k: CockpitKit, c: Vector3, r0: float, r1: float, h: float, col: Color, sides := 6, basis := Basis.IDENTITY) -> void:
	var bot := []
	var top := []
	for i in sides:
		var a := TAU * float(i) / sides
		var d := Vector3(cos(a), 0.0, sin(a))
		bot.append(c + basis * (d * r0))
		top.append(c + basis * (d * r1 + Vector3(0.0, h, 0.0)))
	for i in sides:
		var j := (i + 1) % sides
		k.quad(bot[i], top[i], top[j], bot[j], col)
	for i in range(1, sides - 1):
		k.tri(top[0], top[i + 1], top[i], col)
		k.tri(bot[0], bot[i], bot[i + 1], col)

## The basis whose +y runs from a to b (for limbs, poles, bats).
static func along(a: Vector3, b: Vector3) -> Basis:
	var y := (b - a).normalized()
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

## A square-section rod from a to b, `r` half-thick.
static func limb(k: CockpitKit, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 1e-5:
		return
	k.box(Vector3(r * 2.0, len, r * 2.0), (a + b) * 0.5, col, along(a, b))

## A round rod from a to b (poles, bats, chains).
static func rod(k: CockpitKit, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, sides := 6) -> void:
	var len := a.distance_to(b)
	if len < 1e-5:
		return
	frustum(k, a, r0, r1, len, col, sides, along(a, b))

## A flat ring: radii r0 < r1 about `c`, `thick` along the ring's own y, in `basis`.
static func ring(k: CockpitKit, c: Vector3, r0: float, r1: float, thick: float, col: Color, segs := 8, basis := Basis.IDENTITY) -> void:
	var ih := Vector3(0.0, thick * 0.5, 0.0)
	for s in segs:
		var t0 := TAU * float(s) / segs
		var t1 := TAU * float(s + 1) / segs
		var d0 := Vector3(cos(t0), 0.0, sin(t0))
		var d1 := Vector3(cos(t1), 0.0, sin(t1))
		var i0u := c + basis * (d0 * r0 + ih)
		var i1u := c + basis * (d1 * r0 + ih)
		var o0u := c + basis * (d0 * r1 + ih)
		var o1u := c + basis * (d1 * r1 + ih)
		var i0d := c + basis * (d0 * r0 - ih)
		var i1d := c + basis * (d1 * r0 - ih)
		var o0d := c + basis * (d0 * r1 - ih)
		var o1d := c + basis * (d1 * r1 - ih)
		k.quad(i0u, i1u, o1u, o0u, col)   # top
		k.quad(i1d, i0d, o0d, o1d, col)   # underside
		k.quad(o0d, o1d, o1u, o0u, col)   # outer wall
		k.quad(i1d, i1u, i0u, i0d, col)   # inner wall

## A disc facing +y (coins, dials, brims): a short cylinder.
static func disc(k: CockpitKit, c: Vector3, r: float, thick: float, col: Color, sides := 8, basis := Basis.IDENTITY) -> void:
	k.cylinder(r, -thick * 0.5, thick * 0.5, c, col, sides, basis)

static func rx(deg: float) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(deg))

static func ry(deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(deg))

static func rz(deg: float) -> Basis:
	return Basis(Vector3.BACK, deg_to_rad(deg))

## A basis that lays the +y axis along +z (discs that face the driver).
static func facing() -> Basis:
	return rx(90.0)

# ---------- the standard person's pieces ----------

## The round base with the group's mark: crew a bar in the accent colour on the
## front of the base, shop a hex nut (the Dunmore Auto mark).
func base(f: Fig, spec: Dictionary) -> void:
	f.body.cylinder(BASE_R, 0.0, BASE_H, Vector3.ZERO, INK, 8)
	if spec.get("group", "shop") == "crew":
		f.body.box(Vector3(0.009, 0.0014, 0.003), Vector3(0.0, BASE_H + 0.0007, 0.0145), spec.accent)
	else:
		f.body.cylinder(0.0028, 0.0, 0.0016, Vector3(0.0, BASE_H, 0.0145), SILVER, 6)

## Two legs from the base to the hips; `spread` half the stance, `fwd` moves the
## +x leg forward (a step), `lean` tilts both about x (degrees).
func legs(f: Fig, col: Color, spread := 0.0055, fwd := 0.0, lean := 0.0, y1 := LEG_Y1) -> void:
	for side in [-1.0, 1.0]:
		var z := fwd if side > 0.0 else 0.0
		f.body.box(Vector3(0.0068, y1 - LEG_Y0, 0.0078), Vector3(side * spread, (LEG_Y0 + y1) * 0.5, z), col, rx(lean))
		f.body.box(Vector3(0.0068, 0.0025, 0.0105), Vector3(side * spread, LEG_Y0 + 0.00125, z + 0.0015), INK)

func torso(f: Fig, col: Color, size := TORSO_SIZE, c := TORSO_C, basis := Basis.IDENTITY) -> void:
	f.body.box(size, c, col, basis)

## An arm: upper arm shoulder -> elbow in the sleeve colour, forearm elbow ->
## hand, a hand cube at the end.
func arm(f: Fig, shoulder: Vector3, elbow: Vector3, hand: Vector3, sleeve: Color, skin: Color, fore_col := Color(0, 0, 0, 0), r := ARM_R) -> void:
	limb(f.body, shoulder, elbow, r, sleeve)
	limb(f.body, elbow, hand, r, fore_col if fore_col.a > 0.0 else sleeve)
	f.body.box(Vector3.ONE * (r * 2.0 + 0.0012), hand, skin)

func shoulder(side: float) -> Vector3:
	return Vector3(side * SHOULDER_X, SHOULDER_Y, 0.0)

## Both arms hanging at the sides.
func arms_down(f: Fig, sleeve: Color, skin: Color) -> void:
	for side in [-1.0, 1.0]:
		arm(f, shoulder(side), Vector3(side * 0.0135, 0.025, 0.0015), Vector3(side * 0.0135, 0.0185, 0.003), sleeve, skin)

func neck(f: Fig, col := SILVER) -> void:
	f.neck.cylinder(NECK_R, f.neck_y0, f.neck_y1, Vector3(f.axis.x, 0.0, f.axis.y), col, 6)

func ball_head(f: Fig, col: Color, segs := 8, rings := 5) -> void:
	sphere(f.head, f.head_c, f.head_r, col, f.head_scale, segs, rings)

## Painted eyes on the face. style: dots, wide (whites and pupils), closed,
## half (bored lids), shades (one bar), round_shades, goggles, blank (lenses with
## nothing behind), one (a single big eye).
func eyes(f: Fig, style: String, col := INK, dy := 0.003, dx := 0.0055) -> void:
	var z := f.front()
	var c := f.head_c
	match style:
		"dots":
			for side in [-1.0, 1.0]:
				f.head.box(Vector3(0.0036, 0.0046, 0.003), c + Vector3(side * dx, dy, z + 0.0002), col)
		"wide":
			for side in [-1.0, 1.0]:
				f.head.box(Vector3(0.0066, 0.0072, 0.003), c + Vector3(side * dx, dy, z + 0.0002), BONE)
				f.head.box(Vector3(0.0028, 0.0034, 0.003), c + Vector3(side * dx, dy - 0.0006, z + 0.0012), col)
		"closed":
			for side in [-1.0, 1.0]:
				f.head.box(Vector3(0.0046, 0.0012, 0.003), c + Vector3(side * dx, dy - 0.0008, z + 0.0002), col, rz(side * -12.0))
		"half":
			for side in [-1.0, 1.0]:
				f.head.box(Vector3(0.0040, 0.0020, 0.003), c + Vector3(side * dx, dy - 0.0012, z + 0.0002), col)
				f.head.box(Vector3(0.0046, 0.0014, 0.003), c + Vector3(side * dx, dy + 0.0012, z + 0.0006), col)
		"shades":
			f.head.box(Vector3(0.0260, 0.0056, 0.0035), c + Vector3(0.0, dy, z), col)
		"round_shades":
			for side in [-1.0, 1.0]:
				disc(f.head, c + Vector3(side * dx, dy, z + 0.0008), 0.0042, 0.0025, col, 8, facing())
			f.head.box(Vector3(0.0030, 0.0012, 0.002), c + Vector3(0.0, dy, z + 0.0012), col)
		"goggles":
			for side in [-1.0, 1.0]:
				disc(f.head, c + Vector3(side * dx, dy, z + 0.001), 0.0050, 0.0035, SILVER, 8, facing())
				disc(f.head, c + Vector3(side * dx, dy, z + 0.0028), 0.0036, 0.0012, AMBER, 8, facing())
			f.head.box(Vector3(0.034, 0.004, 0.034), c + Vector3(0.0, dy, 0.0), col)
		"blank":
			for side in [-1.0, 1.0]:
				f.head.box(Vector3(0.0070, 0.0050, 0.003), c + Vector3(side * dx, dy, z + 0.0004), AMBER.lerp(BONE, 0.6))
			f.head.box(Vector3(0.0030, 0.0012, 0.002), c + Vector3(0.0, dy, z + 0.0012), col)
		"one":
			f.head.box(Vector3(0.0120, 0.0120, 0.003), c + Vector3(0.0, dy, z + 0.0002), BONE)
			f.head.box(Vector3(0.0050, 0.0056, 0.003), c + Vector3(0.0, dy - 0.0008, z + 0.0014), col)

## Painted mouth. style: line, smile, grin (teeth), o (surprise), frown, thin,
## smirk (one side up), open (a dark hole).
func mouth(f: Fig, style: String, col := INK, dy := -0.0062) -> void:
	var z := f.front()
	var c := f.head_c
	match style:
		"line":
			f.head.box(Vector3(0.008, 0.0024, 0.003), c + Vector3(0.0, dy, z + 0.0002), col)
		"thin":
			f.head.box(Vector3(0.007, 0.0012, 0.003), c + Vector3(0.0, dy, z + 0.0002), col)
		"smile":
			f.head.box(Vector3(0.008, 0.0020, 0.003), c + Vector3(0.0, dy, z + 0.0002), col)
			for side in [-1.0, 1.0]:
				f.head.box(Vector3(0.0022, 0.0020, 0.003), c + Vector3(side * 0.0048, dy + 0.0014, z + 0.0002), col)
		"grin":
			f.head.box(Vector3(0.016, 0.0064, 0.003), c + Vector3(0.0, dy, z + 0.0002), col)
			f.head.box(Vector3(0.013, 0.0030, 0.003), c + Vector3(0.0, dy + 0.0006, z + 0.0012), BONE)
		"o":
			f.head.box(Vector3(0.0070, 0.0070, 0.003), c + Vector3(0.0, dy, z + 0.0002), col)
			f.head.box(Vector3(0.0036, 0.0036, 0.003), c + Vector3(0.0, dy, z + 0.0012), col.lerp(RUST, 0.35))
		"frown":
			f.head.box(Vector3(0.008, 0.0020, 0.003), c + Vector3(0.0, dy, z + 0.0002), col)
			for side in [-1.0, 1.0]:
				f.head.box(Vector3(0.0022, 0.0020, 0.003), c + Vector3(side * 0.0048, dy - 0.0014, z + 0.0002), col)
		"smirk":
			f.head.box(Vector3(0.007, 0.0020, 0.003), c + Vector3(0.0015, dy, z + 0.0002), col, rz(-14.0))
		"open":
			f.head.box(Vector3(0.0090, 0.0070, 0.003), c + Vector3(0.0, dy - 0.0005, z + 0.0002), col)

## A short cap of hair on the crown, `col`, sitting `back` toward -z.
func hair_cap(f: Fig, col: Color, back := 0.0, h := 0.008) -> void:
	var r := f.head_r
	f.head.box(Vector3(r * 1.74, h, r * 1.78), f.head_c + Vector3(0.0, r * 0.60, -back), col)
	f.head.box(Vector3(r * 1.50, h * 0.7, r * 1.55), f.head_c + Vector3(0.0, r * 0.60 + h * 0.6, -back), col)

## A peaked cap: crown cylinder and a brim toward +z.
func cap(f: Fig, col: Color, brim_col := Color(0, 0, 0, 0), h := 0.009, brim := 0.013) -> void:
	var r := f.head_r
	f.head.cylinder(r * 1.06, r * 0.45, r * 0.45 + h, f.head_c, col, 8)
	var bc := brim_col if brim_col.a > 0.0 else col
	f.head.box(Vector3(r * 1.5, 0.002, brim), f.head_c + Vector3(0.0, r * 0.5, r * 0.95 + brim * 0.5), bc)

## The whole standard person: base, legs, torso, hanging arms, neck, head.
func person(f: Fig, spec: Dictionary, skin: Color, eye_style := "dots", mouth_style := "line") -> void:
	base(f, spec)
	legs(f, spec.body.darkened(0.3))
	torso(f, spec.body)
	arms_down(f, spec.body, skin)
	neck(f)
	ball_head(f, skin)
	eyes(f, eye_style)
	mouth(f, mouth_style)

# =====================================================================
# 1-9 the crews: won from the people you beat
# =====================================================================

## 1 Ledger, Ironbridge: leaning back, head thrown back laughing, a can raised
## in toast. Huge grin, slicked hair. Charcoal and brass. Bob: wild.
func fig_ledger(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	f.head_c = HEAD_C + Vector3(0.0, 0.0015, -0.004)
	f.axis = Vector2(0.0, -0.002)
	base(f, spec)
	legs(f, OIL, 0.006, 0.003, -8.0)
	torso(f, CHARCOAL, TORSO_SIZE, TORSO_C + Vector3(0.0, 0.0, -0.002), rx(-14.0))
	# left arm back on a hip, right arm up high with the can (the prop)
	arm(f, shoulder(-1.0) + Vector3(0.0, 0.0, -0.003), Vector3(-0.0145, 0.025, -0.004), Vector3(-0.010, 0.020, -0.001), CHARCOAL, skin)
	arm(f, shoulder(1.0) + Vector3(0.0, 0.0, -0.003), Vector3(0.0200, 0.0330, -0.002), Vector3(0.0225, 0.0420, 0.0), CHARCOAL, skin)
	f.body.cylinder(0.0046, 0.0, 0.0125, Vector3(0.0225, 0.0435, 0.0), BRASS, 8)
	f.body.cylinder(0.0030, 0.0, 0.0010, Vector3(0.0225, 0.0560, 0.0), SILVER, 8)
	f.body.box(Vector3(0.0092, 0.0036, 0.0094), Vector3(0.0225, 0.0495, 0.0), CHARCOAL)   # the label band
	neck(f)
	ball_head(f, skin)
	eyes(f, "closed", INK, 0.0045)
	mouth(f, "grin", INK, -0.0045)
	# slicked hair: flat on top, swept back to a point
	hair_cap(f, INK, 0.003, 0.0065)
	f.head.box(Vector3(0.020, 0.0085, 0.012), f.head_c + Vector3(0.0, 0.0085, -0.016), INK, rx(28.0))
	f.head.rotate(rx(-16.0), f.pivot())   # the head thrown back
	# a brass collar pin
	f.body.box(Vector3(0.0045, 0.0045, 0.0015), Vector3(0.006, 0.0305, 0.0062), BRASS, rx(-14.0))

## 2 Kasumi Run leader: crouched like in a bucket seat, both hands on a tiny
## deep-dish wheel. Headband with tails. Bone and moss. Bob: quick side to side.
func fig_kasumi_leader(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	f.head_c = HEAD_C + Vector3(0.0, -0.006, 0.004)
	f.neck_y0 = NECK_Y0 - 0.006
	f.neck_y1 = NECK_Y1 - 0.006
	f.axis = Vector2(0.0, 0.003)
	base(f, spec)
	# sitting: thighs forward, shins down
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0068, 0.0068, 0.0130), Vector3(side * 0.0060, 0.0145, 0.0060), MOSS.darkened(0.3))
		f.body.box(Vector3(0.0068, 0.0095, 0.0068), Vector3(side * 0.0060, 0.0095, 0.0115), MOSS.darkened(0.3))
	torso(f, BONE, Vector3(0.020, 0.014, 0.011), Vector3(0.0, 0.0245, 0.001), rx(10.0))
	f.body.box(Vector3(0.0225, 0.0045, 0.0115), Vector3(0.0, 0.0165, 0.0), MOSS)   # seat belt pad
	# the wheel (the prop): a deep dish toward the chest
	var hub := Vector3(0.0, 0.0255, 0.0150)
	var rim := CockpitKit.new()
	rim.ring_sector(0.0066, 0.0100, 0.0, TAU, -0.0015, 0.0015, INK, 10)
	rim.offset(hub)
	f.body.merge(rim)
	f.body.cylinder(0.0030, 0.0, 0.0115, Vector3(hub.x, hub.y, 0.0075), SILVER, 6, facing())   # dish
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0055, 0.0022, 0.0026), hub + Vector3(side * 0.0048, 0.0, 0.0), SILVER)   # spokes
		arm(f, shoulder(side) + Vector3(0.0, -0.005, 0.002), Vector3(side * 0.0120, 0.0235, 0.011), hub + Vector3(side * 0.0092, 0.0012, 0.0), BONE, skin)
	neck(f)
	ball_head(f, skin)
	eyes(f, "dots")
	mouth(f, "line")
	hair_cap(f, INK, 0.0015, 0.0075)
	f.head.box(Vector3(0.036, 0.0046, 0.036), f.head_c + Vector3(0.0, 0.0045, 0.0), MOSS)   # headband
	var knot := f.head_c + Vector3(0.0, 0.0045, -0.0185)
	f.head.box(Vector3(0.006, 0.006, 0.004), knot, MOSS)
	limb(f.head, knot, knot + Vector3(0.014, -0.004, -0.011), 0.0016, MOSS)   # tails flying back
	limb(f.head, knot, knot + Vector3(0.006, -0.010, -0.010), 0.0016, MOSS)

## 3 Gruppe 9 leader: standing dead straight, arms crossed, driving gloves in
## a pocket. Round sunglasses, flat cap. Slate and silver. Bob: small and stiff.
func fig_gruppe9_leader(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_PALE
	base(f, spec)
	legs(f, SLATE.darkened(0.35), 0.0038)
	torso(f, SLATE, Vector3(0.019, 0.017, 0.012))
	# arms folded across the chest
	for side in [-1.0, 1.0]:
		var sh := shoulder(side)
		var el := Vector3(side * 0.0190, 0.0265, 0.0070)
		limb(f.body, sh, el, ARM_R, SLATE)
		limb(f.body, el, Vector3(-side * 0.0085, 0.0275, 0.0078), ARM_R, SLATE)
		f.body.box(Vector3(0.0055, 0.0050, 0.0050), Vector3(-side * 0.0105, 0.0280, 0.0078), skin)
	f.body.box(Vector3(0.0070, 0.0085, 0.0028), Vector3(0.0075, 0.0165, 0.0068), INK)   # gloves peeking from the pocket
	f.body.box(Vector3(0.0070, 0.0030, 0.0030), Vector3(0.0075, 0.0215, 0.0070), INK)
	f.body.box(Vector3(0.0030, 0.0085, 0.0015), Vector3(0.0, 0.0245, 0.0065), SILVER)   # zip
	neck(f)
	ball_head(f, skin)
	eyes(f, "round_shades")
	mouth(f, "thin")
	# flat cap: a low wide disc, the peak low over the shades
	f.head.cylinder(0.0215, 0.0070, 0.0135, f.head_c, SLATE, 8)
	f.head.box(Vector3(0.034, 0.002, 0.014), f.head_c + Vector3(0.0, 0.0078, 0.0210), SLATE)
	f.head.box(Vector3(0.034, 0.003, 0.012), f.head_c + Vector3(0.0, 0.0055, 0.0080), SILVER)   # band

## 4 Diesel Row leader: wide stance, thumbs in the belt, a tow chain over the
## shoulder. Big moustache, trucker cap. Copper and oil black. Bob: slow, heavy.
func fig_diesel_leader(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_PALE
	base(f, spec)
	legs(f, OIL, 0.0100)
	torso(f, COPPER, Vector3(0.030, 0.016, 0.015))
	f.body.box(Vector3(0.0305, 0.0032, 0.0155), Vector3(0.0, 0.0185, 0.0), OIL)   # belt
	f.body.box(Vector3(0.0060, 0.0045, 0.0020), Vector3(0.0, 0.0185, 0.0078), BRASS)   # buckle
	for side in [-1.0, 1.0]:
		arm(f, shoulder(side) + Vector3(side * 0.005, 0.0, 0.0), Vector3(side * 0.0225, 0.0250, 0.004), Vector3(side * 0.0095, 0.0190, 0.0085), COPPER, skin, Color(0, 0, 0, 0), 0.0034)
	# the chain (the prop): fat links from the left shoulder down the back to the right hip, a hook in front
	var from := Vector3(-0.0115, 0.0345, -0.004)
	var to := Vector3(0.0120, 0.0160, -0.0075)
	for i in 6:
		var p := from.lerp(to, float(i) / 5.0)
		f.body.box(Vector3(0.0046, 0.0046, 0.0030) if i % 2 == 0 else Vector3(0.0030, 0.0046, 0.0046), p, SILVER, along(from, to))
	f.body.box(Vector3(0.0050, 0.0050, 0.0036), Vector3(-0.0120, 0.0330, 0.0035), SILVER)
	limb(f.body, Vector3(-0.0120, 0.0330, 0.0045), Vector3(-0.0140, 0.0245, 0.0085), 0.0017, SILVER)   # the hook's shank
	f.body.box(Vector3(0.0050, 0.0030, 0.0030), Vector3(-0.0120, 0.0225, 0.0095), SILVER)
	neck(f)
	ball_head(f, skin)
	eyes(f, "dots")
	# the moustache (the feature): wide, drooping ends
	var z := f.front()
	f.head.box(Vector3(0.0220, 0.0046, 0.0032), f.head_c + Vector3(0.0, -0.0040, z + 0.0004), OIL)
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0036, 0.0060, 0.0032), f.head_c + Vector3(side * 0.0115, -0.0075, z + 0.0004), OIL)
	# trucker cap: tall front panel, mesh back, big brim
	f.head.cylinder(0.0172, 0.0070, 0.0160, f.head_c, OIL, 8)
	f.head.box(Vector3(0.0220, 0.0080, 0.0030), f.head_c + Vector3(0.0, 0.0125, 0.0160), COPPER)
	f.head.box(Vector3(0.0300, 0.0020, 0.0190), f.head_c + Vector3(0.0, 0.0075, 0.0230), OIL, rx(-6.0))

## 5 Kess: hand on hip, bored, car keys spun on a finger. Long coat with the
## collar up. Tan and navy. Bob: barely moves.
func fig_kess(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	base(f, spec)
	legs(f, NAVY, 0.0045, 0.0, 0.0, 0.014)
	# the coat: long, to the knees, collar up around the neck
	torso(f, TAN, Vector3(0.019, 0.021, 0.013), Vector3(0.0, 0.0235, 0.0))
	frustum(f.body, Vector3(0.0, 0.0080, 0.0), 0.0150, 0.0105, 0.0080, TAN, 6)   # the coat's flare
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0060, 0.0085, 0.0028), Vector3(side * 0.0070, 0.0365, 0.0045), TAN.darkened(0.15), rz(side * -18.0))
		f.body.box(Vector3(0.0080, 0.0060, 0.0028), Vector3(side * 0.0115, 0.0355, -0.0035), TAN.darkened(0.15))
	f.body.box(Vector3(0.0030, 0.0180, 0.0015), Vector3(0.0, 0.0245, 0.0068), NAVY)   # the coat's edge
	# left hand on the hip, right arm out front spinning the keys
	arm(f, shoulder(-1.0), Vector3(-0.0215, 0.0240, 0.0), Vector3(-0.0125, 0.0180, 0.0040), TAN, skin)
	arm(f, shoulder(1.0), Vector3(0.0200, 0.0280, 0.0040), Vector3(0.0235, 0.0400, 0.0060), TAN, skin)
	limb(f.body, Vector3(0.0235, 0.0400, 0.0060), Vector3(0.0245, 0.0455, 0.0070), 0.0012, skin)   # the finger
	# the key ring (the prop): oversized, two keys hanging
	var kr := Vector3(0.0245, 0.0420, 0.0100)
	ring(f.body, kr, 0.0058, 0.0074, 0.0014, SILVER, 8, facing())
	limb(f.body, kr + Vector3(0.0, -0.0045, 0.0), kr + Vector3(0.0035, -0.0130, 0.0), 0.0012, SILVER)
	limb(f.body, kr + Vector3(0.0, -0.0045, 0.0), kr + Vector3(-0.0030, -0.0125, 0.0), 0.0012, NAVY)
	f.body.box(Vector3(0.0036, 0.0036, 0.0024), kr + Vector3(0.0038, -0.0140, 0.0), SILVER)
	f.body.box(Vector3(0.0036, 0.0036, 0.0024), kr + Vector3(-0.0032, -0.0135, 0.0), NAVY)
	neck(f)
	ball_head(f, skin)
	eyes(f, "half")
	mouth(f, "thin")
	hair_cap(f, NAVY_DEEP, 0.001, 0.007)
	f.head.box(Vector3(0.0050, 0.0120, 0.0300), f.head_c + Vector3(-0.0150, 0.0055, 0.0), NAVY_DEEP)   # hair down one side

## 6 Pike: hands folded, perfectly upright, a ledger book under one arm. Thin
## smile, no eyes behind the glasses. Navy and gold. Bob: almost none.
func fig_pike(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_PALE
	f.neck_y1 = NECK_Y1 + 0.002
	f.head_c = HEAD_C + Vector3(0.0, 0.002, 0.0)
	f.head_scale = Vector3(0.82, 1.08, 0.86)
	base(f, spec)
	legs(f, NAVY_DEEP, 0.0035)
	torso(f, NAVY_DEEP, Vector3(0.015, 0.017, 0.011))
	f.body.box(Vector3(0.0030, 0.0120, 0.0016), Vector3(0.0, 0.0260, 0.0065), GOLD)   # the tie
	f.body.box(Vector3(0.0060, 0.0030, 0.0016), Vector3(0.0, 0.0325, 0.0066), BONE)   # collar
	# hands folded at the waist
	for side in [-1.0, 1.0]:
		arm(f, Vector3(side * 0.0085, SHOULDER_Y, 0.0), Vector3(side * 0.0100, 0.0220, 0.0060), Vector3(side * 0.0025, 0.0185, 0.0085), NAVY_DEEP, skin, Color(0, 0, 0, 0), 0.0024)
	# the ledger (the prop): a fat book clamped under the left arm
	f.body.box(Vector3(0.0070, 0.0250, 0.0170), Vector3(-0.0185, 0.0240, 0.0010), NAVY)
	f.body.box(Vector3(0.0072, 0.0225, 0.0150), Vector3(-0.0185, 0.0240, 0.0010), BONE)   # pages
	f.body.box(Vector3(0.0076, 0.0250, 0.0024), Vector3(-0.0185, 0.0240, -0.0075), GOLD)   # spine
	neck(f)
	ball_head(f, skin)
	eyes(f, "blank")
	mouth(f, "thin", INK, -0.0060)
	f.head.box(Vector3(0.0240, 0.0050, 0.0250), f.head_c + Vector3(0.0, 0.0115, -0.0020), GREY)   # neat grey hair, parted
	f.head.box(Vector3(0.0020, 0.0030, 0.0220), f.head_c + Vector3(0.0040, 0.0140, -0.0020), skin)

## 7 Rally king: leaning out reading the road, pace-note book held up. Helmet
## pushed up, mud down one side. Sodium and navy. Bob: bouncy.
func fig_rally_king(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	f.head_c = HEAD_C + Vector3(0.004, -0.001, 0.003)
	f.axis = Vector2(0.003, 0.002)
	base(f, spec)
	legs(f, NAVY, 0.0055, 0.0040)
	torso(f, SODIUM, TORSO_SIZE, TORSO_C + Vector3(0.0015, 0.0, 0.001), rx(12.0) * rz(-8.0))
	f.body.box(Vector3(0.0210, 0.0045, 0.0125), Vector3(0.0015, 0.0245, 0.001), NAVY, rx(12.0) * rz(-8.0))   # a stripe
	# right arm holds the book up by the face; left arm braces on the knee
	arm(f, shoulder(1.0) + Vector3(0.002, -0.001, 0.002), Vector3(0.0215, 0.0300, 0.0100), Vector3(0.0190, 0.0420, 0.0140), SODIUM, skin)
	arm(f, shoulder(-1.0) + Vector3(0.0, -0.002, 0.002), Vector3(-0.0150, 0.0230, 0.0060), Vector3(-0.0095, 0.0185, 0.0085), SODIUM, skin)
	# the pace notes (the prop): a tall open book held up, lines on the page
	var bk := Vector3(0.0180, 0.0470, 0.0165)
	f.body.box(Vector3(0.0150, 0.0210, 0.0024), bk, BONE, rx(-10.0))
	for i in 4:
		f.body.box(Vector3(0.0100, 0.0012, 0.0012), bk + Vector3(0.0, 0.0070 - 0.0038 * i, 0.0016), INK, rx(-10.0))
	f.body.box(Vector3(0.0016, 0.0210, 0.0030), bk + Vector3(0.0, 0.0, -0.0002), SODIUM, rx(-10.0))   # spine
	neck(f)
	ball_head(f, skin)
	eyes(f, "wide", INK, 0.0025, 0.0055)
	mouth(f, "o", INK, -0.0060)
	# the helmet pushed up on the back of the head, the open visor as a brim
	sphere(f.head, f.head_c + Vector3(0.0, 0.0060, -0.0085), 0.0165, NAVY, Vector3(1.08, 0.78, 1.08), 8, 4)
	f.head.box(Vector3(0.0300, 0.0030, 0.0120), f.head_c + Vector3(0.0, 0.0120, 0.0070), SODIUM, rx(-25.0))
	# mud (the feature): splashes down the left side
	for m in [[Vector3(-0.0135, 0.0040, 0.0090), 0.0050], [Vector3(-0.0160, -0.0030, 0.0040), 0.0040], [Vector3(-0.0120, -0.0085, 0.0100), 0.0035]]:
		f.head.box(Vector3.ONE * float(m[1]), f.head_c + (m[0] as Vector3), WOOD)
	f.body.box(Vector3(0.0055, 0.0045, 0.0030), Vector3(-0.0095, 0.0280, 0.0068), WOOD, rx(12.0) * rz(-8.0))

## 8 Top-speed king: bent forward and tucked, a tiny speedometer hugged to the
## chest. Goggles. Navy and amber. Bob: a fast shake.
func fig_topspeed_king(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_PALE
	f.head_c = HEAD_C + Vector3(0.0, -0.005, 0.0075)
	f.neck_y0 = NECK_Y0 - 0.004
	f.neck_y1 = NECK_Y1 - 0.004
	f.axis = Vector2(0.0, 0.005)
	base(f, spec)
	legs(f, NAVY_DEEP, 0.0040, 0.0, 10.0)
	torso(f, NAVY, Vector3(0.016, 0.017, 0.012), Vector3(0.0, 0.0245, 0.0025), rx(26.0))
	f.body.box(Vector3(0.0060, 0.0170, 0.0125), Vector3(0.0, 0.0245, 0.0025), AMBER, rx(26.0))   # the racing stripe
	# the speedometer (the prop): a big dial clasped to the chest
	var dial := Vector3(0.0, 0.0225, 0.0120)
	var db := rx(70.0)
	disc(f.body, dial, 0.0110, 0.0040, SILVER, 10, db)
	disc(f.body, dial + db * Vector3(0.0, 0.0022, 0.0), 0.0088, 0.0010, INK, 10, db)
	f.body.box(Vector3(0.0016, 0.0080, 0.0012), dial + db * Vector3(0.0025, 0.0030, 0.0030), AMBER, db * rz(-38.0))   # needle
	for side in [-1.0, 1.0]:
		arm(f, Vector3(side * 0.0085, 0.0280, 0.004), Vector3(side * 0.0100, 0.0200, 0.0100), dial + Vector3(side * 0.0070, -0.0030, 0.0045), NAVY, skin)
	neck(f)
	ball_head(f, skin)
	eyes(f, "goggles", INK, 0.0025)
	mouth(f, "line", INK, -0.0070)
	hair_cap(f, SKIN_PALE.darkened(0.55), 0.0015, 0.0045)   # cropped hair under the strap

## 9 Muscle king: arm out the window, cocky, fuzzy dice on the wrist. A tall
## quiff. Bone and sodium. Bob: a big nod.
func fig_muscle_king(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_DARK
	f.head_c = HEAD_C + Vector3(0.0, 0.0, 0.0)
	base(f, spec)
	legs(f, NAVY_DEEP, 0.0060, 0.0, 0.0)
	torso(f, BONE, Vector3(0.021, 0.016, 0.012))
	f.body.box(Vector3(0.0215, 0.0038, 0.0125), Vector3(0.0, 0.0195, 0.0), SODIUM)   # belt
	# the "door": a sill he rests the elbow on, out to the right
	f.body.box(Vector3(0.0080, 0.0030, 0.0150), Vector3(0.0215, 0.0235, 0.0), SODIUM.darkened(0.45))
	limb(f.body, Vector3(0.0215, 0.0060, 0.0), Vector3(0.0215, 0.0225, 0.0), 0.0022, SODIUM.darkened(0.45))
	arm(f, shoulder(1.0), Vector3(0.0215, 0.0265, 0.0020), Vector3(0.0260, 0.0180, 0.0040), BONE, skin, skin)
	arm(f, shoulder(-1.0), Vector3(-0.0140, 0.0240, 0.0010), Vector3(-0.0105, 0.0190, 0.0070), BONE, skin, skin)
	# the fuzzy dice (the prop): two fat cubes swinging from the wrist
	var wrist := Vector3(0.0262, 0.0190, 0.0040)
	var dice := CockpitKit.new()
	limb(dice, wrist, wrist + Vector3(0.0, -0.0050, 0.0), 0.0006, INK)
	for d in [Vector3(0.0, -0.0090, 0.0025), Vector3(0.0, -0.0090, -0.0030)]:
		var dc: Vector3 = wrist + (d as Vector3)
		dice.box(Vector3.ONE * 0.0055, dc, SODIUM, ry(20.0))
		dice.box(Vector3(0.0016, 0.0016, 0.0060), dc + Vector3(0.0, 0.0012, 0.0), BONE, ry(20.0))
		dice.box(Vector3(0.0060, 0.0016, 0.0016), dc + Vector3(0.0, -0.0012, 0.0), BONE, ry(20.0))
	f.loose(dice, 0.9, wrist)
	neck(f)
	ball_head(f, skin)
	eyes(f, "half", INK, 0.0030)
	mouth(f, "smirk")
	f.head.box(Vector3(0.0070, 0.0014, 0.0030), f.head_c + Vector3(-0.0055, 0.0085, f.front()), INK, rz(-16.0))   # a raised brow
	# the quiff (the feature): a tall wave of hair rolling up and forward
	hair_cap(f, INK, 0.002, 0.007)
	f.head.box(Vector3(0.0240, 0.0100, 0.0110), f.head_c + Vector3(0.0, 0.0110, 0.0070), INK, rx(-30.0))
	f.head.box(Vector3(0.0180, 0.0070, 0.0090), f.head_c + Vector3(0.0, 0.0140, 0.0150), INK, rx(-65.0))

# =====================================================================
# 10-17 the shop family and the local jokes
# =====================================================================

## 10 Walt: slightly hunched, hand on hip, his mug in the other. Grey stubble,
## reading glasses pushed up. Navy overalls, amber mug. Bob: slow and grumpy.
func fig_walt(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_PALE
	f.head_c = HEAD_C + Vector3(0.0, -0.003, 0.0045)
	f.neck_y0 = NECK_Y0 - 0.002
	f.neck_y1 = NECK_Y1 - 0.002
	f.axis = Vector2(0.0, 0.0025)
	base(f, spec)
	legs(f, NAVY, 0.0060)
	torso(f, NAVY, Vector3(0.022, 0.016, 0.013), TORSO_C + Vector3(0.0, 0.0, 0.001), rx(13.0))
	f.body.box(Vector3(0.0120, 0.0100, 0.0020), Vector3(0.0, 0.0290, 0.0085), NAVY.darkened(0.3), rx(13.0))   # bib
	f.body.box(Vector3(0.0260, 0.0040, 0.0150), Vector3(0.0, 0.0180, 0.001), SKIN_PALE.lerp(BONE, 0.5), rx(13.0))   # shirt showing under the bib
	# left hand on the hip, right hand holding the mug out
	arm(f, shoulder(-1.0) + Vector3(0.0, -0.001, 0.003), Vector3(-0.0175, 0.0240, 0.0), Vector3(-0.0125, 0.0180, 0.0045), NAVY, skin, skin)
	arm(f, shoulder(1.0) + Vector3(0.0, -0.001, 0.003), Vector3(0.0160, 0.0240, 0.0085), Vector3(0.0120, 0.0245, 0.0150), NAVY, skin, skin)
	# the mug (the prop): oversized, amber, a fat handle
	var mug := Vector3(0.0120, 0.0210, 0.0185)
	f.body.cylinder(0.0052, 0.0, 0.0100, mug, AMBER, 8)
	f.body.cylinder(0.0036, 0.0085, 0.0100, mug, WOOD, 8)   # coffee
	limb(f.body, mug + Vector3(0.0060, 0.0025, 0.0), mug + Vector3(0.0060, 0.0085, 0.0), 0.0012, AMBER)
	f.body.box(Vector3(0.0030, 0.0012, 0.0024), mug + Vector3(0.0055, 0.0025, 0.0), AMBER)
	f.body.box(Vector3(0.0030, 0.0012, 0.0024), mug + Vector3(0.0055, 0.0085, 0.0), AMBER)
	neck(f)
	ball_head(f, skin)
	eyes(f, "half", INK, 0.0025)
	mouth(f, "frown", INK, -0.0062)
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0060, 0.0012, 0.0030), f.head_c + Vector3(side * 0.0055, 0.0068, f.front()), GREY, rz(side * 18.0))   # heavy grey brows
	# stubble (the feature): a grey jaw
	f.head.box(Vector3(0.0210, 0.0060, 0.0040), f.head_c + Vector3(0.0, -0.0110, f.front() - 0.0030), GREY.lerp(skin, 0.45))
	# reading glasses pushed up into the hair
	hair_cap(f, GREY, 0.0040, 0.0040)
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0080, 0.0014, 0.0070), f.head_c + Vector3(side * 0.0055, 0.0140, 0.0085), INK, rx(-20.0))
		f.head.box(Vector3(0.0050, 0.0020, 0.0040), f.head_c + Vector3(side * 0.0055, 0.0145, 0.0085), AMBER.lerp(BONE, 0.5), rx(-20.0))
	f.head.box(Vector3(0.0030, 0.0010, 0.0010), f.head_c + Vector3(0.0, 0.0140, 0.0085), INK)

## 11 Moose: big and round, thumbs up, a wrench as long as his arm. Tiny head on
## huge shoulders. Navy and silver. Bob: gentle.
func fig_moose(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	f.head_r = 0.0120
	f.head_c = Vector3(0.0, 0.0580, 0.0)
	f.neck_y0 = 0.0400
	f.neck_y1 = 0.0450
	base(f, spec)
	legs(f, NAVY_DEEP, 0.0075, 0.0, 0.0, 0.016)
	# the body (the feature): one big navy ball with shoulders like a fridge
	sphere(f.body, Vector3(0.0, 0.0280, 0.0), 0.0150, NAVY, Vector3(1.30, 1.00, 1.05), 8, 5)
	f.body.box(Vector3(0.0390, 0.0070, 0.0160), Vector3(0.0, 0.0385, 0.0), NAVY)
	f.body.box(Vector3(0.0120, 0.0100, 0.0020), Vector3(0.0, 0.0300, 0.0150), SILVER.darkened(0.3))   # name patch
	# right arm up, thumb up; left arm down gripping the wrench
	arm(f, Vector3(0.0180, 0.0380, 0.0), Vector3(0.0240, 0.0320, 0.0060), Vector3(0.0215, 0.0420, 0.0085), NAVY, skin, skin, 0.0036)
	f.body.box(Vector3(0.0028, 0.0060, 0.0028), Vector3(0.0215, 0.0480, 0.0085), skin)   # the thumb
	arm(f, Vector3(-0.0180, 0.0380, 0.0), Vector3(-0.0230, 0.0270, 0.0030), Vector3(-0.0205, 0.0180, 0.0060), NAVY, skin, skin, 0.0036)
	# the wrench (the prop): a shaft the length of his arm, a big open jaw
	var lo := Vector3(-0.0205, 0.0080, 0.0075)
	var hi := Vector3(-0.0205, 0.0440, 0.0075)
	limb(f.body, lo, hi, 0.0020, SILVER)
	f.body.box(Vector3(0.0090, 0.0060, 0.0040), hi + Vector3(0.0, 0.0030, 0.0), SILVER)
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0030, 0.0055, 0.0040), hi + Vector3(side * 0.0030, 0.0085, 0.0), SILVER)
	neck(f, skin)
	ball_head(f, skin, 8, 4)
	eyes(f, "dots", INK, 0.0020, 0.0040)
	mouth(f, "smile", INK, -0.0045)
	f.head.cylinder(0.0128, 0.0040, 0.0105, f.head_c, NAVY, 8)   # a beanie
	f.head.box(Vector3(0.0260, 0.0030, 0.0260), f.head_c + Vector3(0.0, 0.0045, 0.0), SILVER)

## 12 Juno: pointing forward, one foot forward, a stopwatch. Ponytail flying out
## sideways. Sodium and bone. Bob: snappy.
func fig_juno(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_DARK
	base(f, spec)
	legs(f, BONE.darkened(0.25), 0.0055, 0.0060)
	torso(f, SODIUM, Vector3(0.019, 0.016, 0.011))
	f.body.box(Vector3(0.0195, 0.0050, 0.0115), Vector3(0.0, 0.0295, 0.0), BONE)   # a bone collar/shoulder panel
	# right arm straight out front, finger pointing; left hand with the stopwatch
	var hand := Vector3(0.0215, 0.0400, 0.0130)
	arm(f, shoulder(1.0), Vector3(0.0160, 0.0330, 0.0090), hand, SODIUM, skin)
	limb(f.body, hand, hand + Vector3(0.0035, 0.0040, 0.0045), 0.0012, skin)
	arm(f, shoulder(-1.0), Vector3(-0.0150, 0.0260, 0.0040), Vector3(-0.0115, 0.0235, 0.0095), SODIUM, skin)
	# the stopwatch (the prop): a big silver watch on a cord
	var sw := Vector3(-0.0115, 0.0170, 0.0110)
	disc(f.body, sw, 0.0078, 0.0030, SILVER, 10, facing())
	disc(f.body, sw + Vector3(0.0, 0.0, 0.0017), 0.0062, 0.0010, BONE, 10, facing())
	f.body.box(Vector3(0.0010, 0.0036, 0.0010), sw + Vector3(0.0, 0.0016, 0.0025), SODIUM)
	f.body.box(Vector3(0.0024, 0.0030, 0.0024), sw + Vector3(0.0, 0.0090, 0.0), SILVER)   # the button
	limb(f.body, sw + Vector3(0.0, 0.0100, 0.0), Vector3(-0.0115, 0.0235, 0.0095), 0.0006, INK)   # cord to the hand
	neck(f)
	ball_head(f, skin)
	eyes(f, "dots")
	mouth(f, "smile")
	# the ponytail (the feature): hair pulled back, tail flying out to the side
	hair_cap(f, INK, 0.0025, 0.0075)
	var knot := f.head_c + Vector3(0.0, 0.0060, -0.0170)
	f.head.box(Vector3(0.0060, 0.0060, 0.0050), knot, SODIUM)
	limb(f.head, knot, knot + Vector3(-0.0210, 0.0050, -0.0020), 0.0030, INK)
	limb(f.head, knot + Vector3(-0.0200, 0.0050, -0.0020), knot + Vector3(-0.0280, 0.0020, 0.0020), 0.0022, INK)

## 13 Pilar: calm, eyes half closed, a lug nut held between two fingers. A big
## hood up. Moss and bone. Bob: a smooth sway.
func fig_pilar(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	base(f, spec)
	legs(f, INK, 0.0050)
	torso(f, MOSS, Vector3(0.022, 0.017, 0.013))
	f.body.box(Vector3(0.0130, 0.0050, 0.0020), Vector3(0.0, 0.0205, 0.0068), MOSS.darkened(0.3))   # kangaroo pocket
	# right hand holds the nut up at chest height; left hand in the pocket
	var hand := Vector3(0.0105, 0.0300, 0.0110)
	arm(f, shoulder(1.0), Vector3(0.0150, 0.0245, 0.0060), hand, MOSS, skin)
	limb(f.body, hand, hand + Vector3(0.0, 0.0030, 0.0030), 0.0010, skin)
	limb(f.body, hand, hand + Vector3(0.0, 0.0050, 0.0010), 0.0010, skin)
	arm(f, shoulder(-1.0), Vector3(-0.0140, 0.0245, 0.0040), Vector3(-0.0060, 0.0205, 0.0080), MOSS, skin, MOSS)
	# the lug nut (the prop): a big hex nut pinched in the fingers
	f.body.cylinder(0.0045, 0.0, 0.0045, hand + Vector3(0.0, 0.0040, 0.0050), SILVER, 6, facing())
	f.body.cylinder(0.0020, 0.0, 0.0050, hand + Vector3(0.0, 0.0040, 0.0048), INK, 6, facing())
	neck(f)
	ball_head(f, skin)
	eyes(f, "half", INK, 0.0025)
	mouth(f, "thin", INK, -0.0060)
	# the hood (the feature): a big shell around the head, the face deep inside
	sphere(f.head, f.head_c + Vector3(0.0, -0.0020, -0.0060), f.head_r, MOSS, Vector3(1.28, 1.10, 1.15), 8, 5)
	f.head.box(Vector3(0.0200, 0.0120, 0.0100), f.head_c + Vector3(0.0, -0.0160, -0.0040), MOSS)   # the hood's throat
	f.head.box(Vector3(0.0380, 0.0040, 0.0160), f.head_c + Vector3(0.0, 0.0150, 0.0060), MOSS, rx(-20.0))   # the brim over the eyes

## 14 Teo: hunched over an open laptop, screen lit amber, headphones round the
## neck. Big nervous eyes. Navy and amber. Bob: jittery.
func fig_teo(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_PALE
	f.head_c = HEAD_C + Vector3(0.0, -0.0045, 0.0070)
	f.neck_y0 = NECK_Y0 - 0.004
	f.neck_y1 = NECK_Y1 - 0.004
	f.axis = Vector2(0.0, 0.0045)
	base(f, spec)
	# sitting cross-legged on the base
	f.body.box(Vector3(0.0280, 0.0075, 0.0120), Vector3(0.0, 0.0097, 0.0040), NAVY_DEEP)
	torso(f, NAVY, Vector3(0.021, 0.016, 0.012), Vector3(0.0, 0.0215, 0.0020), rx(30.0))
	# the laptop (the prop): a wide base on the knees, the screen lit amber
	var lap := Vector3(0.0, 0.0145, 0.0115)
	f.body.box(Vector3(0.0320, 0.0016, 0.0150), lap, SILVER.darkened(0.4))
	f.body.box(Vector3(0.0320, 0.0170, 0.0016), lap + Vector3(0.0, 0.0085, -0.0060), SILVER.darkened(0.4), rx(-18.0))
	f.body.box(Vector3(0.0280, 0.0130, 0.0016), lap + Vector3(0.0, 0.0085, -0.0050), AMBER, rx(-18.0))
	for side in [-1.0, 1.0]:
		arm(f, shoulder(side) + Vector3(0.0, -0.0045, 0.0030), Vector3(side * 0.0200, 0.0200, 0.0100), lap + Vector3(side * 0.0100, 0.0030, 0.0040), NAVY, skin)
	# headphones round the neck
	ring(f.body, Vector3(0.0, 0.0305, 0.0030), 0.0060, 0.0080, 0.0020, INK, 8)
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0050, 0.0060, 0.0060), Vector3(side * 0.0085, 0.0290, 0.0050), AMBER)
	neck(f)
	ball_head(f, skin)
	eyes(f, "wide", INK, 0.0025, 0.0058)
	mouth(f, "thin", INK, -0.0068)
	hair_cap(f, FUR_DARK, 0.0010, 0.0090)   # a messy mop
	f.head.box(Vector3(0.0300, 0.0050, 0.0070), f.head_c + Vector3(0.0, 0.0115, 0.0130), FUR_DARK, rx(-10.0))   # fringe over the eyes

## 15 Dave: leaning on a mic stand, a microphone, huge studio headphones. Navy
## and amber. Bob: sways like he hears music.
func fig_dave(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	f.head_c = HEAD_C + Vector3(0.0035, -0.0010, 0.0)
	f.axis = Vector2(0.0030, 0.0)
	base(f, spec)
	legs(f, NAVY_DEEP, 0.0050, 0.0, 0.0)
	torso(f, NAVY, TORSO_SIZE, TORSO_C + Vector3(0.0015, 0.0, 0.0), rz(-10.0))
	f.body.box(Vector3(0.0120, 0.0100, 0.0020), Vector3(0.0015, 0.0255, 0.0065), AMBER, rz(-10.0))   # shirt print
	# the mic stand (the prop): a tall pole he hangs an arm over, the mic up top
	var foot := Vector3(0.0190, 0.0060, 0.0040)
	var top := Vector3(0.0190, 0.0560, 0.0040)
	disc(f.body, foot + Vector3(0.0, 0.0010, 0.0), 0.0065, 0.0020, SILVER.darkened(0.3), 8)
	limb(f.body, foot, top, 0.0014, SILVER)
	f.body.box(Vector3(0.0050, 0.0110, 0.0050), top + Vector3(0.0, 0.0030, 0.0), INK, rx(-20.0))   # the mic body
	sphere(f.body, top + Vector3(0.0, 0.0100, 0.0025), 0.0046, AMBER, Vector3.ONE, 6, 3)   # the grille
	arm(f, shoulder(1.0) + Vector3(0.0015, 0.0, 0.0), Vector3(0.0190, 0.0330, 0.0070), Vector3(0.0215, 0.0265, 0.0085), NAVY, skin)
	arm(f, shoulder(-1.0) + Vector3(0.0015, 0.0, 0.0), Vector3(-0.0130, 0.0240, 0.0040), Vector3(-0.0080, 0.0195, 0.0080), NAVY, skin)
	neck(f)
	ball_head(f, skin)
	eyes(f, "closed", INK, 0.0030)
	mouth(f, "smile")
	hair_cap(f, FUR_DARK, 0.0, 0.0060)
	# the headphones (the feature): cups as big as his fists, a thick band
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0085, 0.0140, 0.0140), f.head_c + Vector3(side * 0.0195, 0.0, 0.0), AMBER)
		f.head.box(Vector3(0.0045, 0.0100, 0.0100), f.head_c + Vector3(side * 0.0245, 0.0, 0.0), INK)
		f.head.box(Vector3(0.0050, 0.0130, 0.0070), f.head_c + Vector3(side * 0.0190, 0.0115, 0.0), INK, rz(side * 30.0))
	f.head.box(Vector3(0.0300, 0.0050, 0.0070), f.head_c + Vector3(0.0, 0.0165, 0.0), INK)

## 16 Dunmore Auto mascot: a cartoon spark plug with arms, waving, its own spark.
## One big eye. Silver and sodium. Bob: bouncy.
func fig_dunmore_mascot(f: Fig, spec: Dictionary) -> void:
	f.head_r = 0.0150
	f.head_c = Vector3(0.0, 0.0505, 0.0)
	f.head_scale = Vector3(0.95, 1.05, 0.95)
	f.neck_y0 = 0.0380
	f.neck_y1 = 0.0420
	base(f, spec)
	# the plug: thread at the foot, the hex nut, the ceramic insulator up top
	f.body.cylinder(0.0105, 0.0060, 0.0170, Vector3.ZERO, SILVER.darkened(0.35), 8)
	ring(f.body, Vector3(0.0, 0.0115, 0.0), 0.0100, 0.0118, 0.0012, SILVER, 8)
	f.body.cylinder(0.0115, 0.0060, 0.0075, Vector3.ZERO, SILVER, 8)
	f.body.cylinder(0.0160, 0.0170, 0.0270, Vector3.ZERO, SILVER, 6)   # the hex nut
	f.body.cylinder(0.0110, 0.0270, 0.0380, Vector3.ZERO, BONE, 8)   # ceramic
	ring(f.body, Vector3(0.0, 0.0330, 0.0), 0.0105, 0.0125, 0.0025, SODIUM, 8)   # a band
	# arms out of the nut, one up waving
	arm(f, Vector3(-0.0150, 0.0240, 0.0), Vector3(-0.0230, 0.0200, 0.0030), Vector3(-0.0215, 0.0130, 0.0060), SILVER, SILVER)
	arm(f, Vector3(0.0150, 0.0240, 0.0), Vector3(0.0230, 0.0320, 0.0020), Vector3(0.0205, 0.0440, 0.0040), SILVER, SILVER)
	f.body.box(Vector3(0.0060, 0.0040, 0.0030), Vector3(0.0205, 0.0485, 0.0040), SILVER)   # fingers spread
	neck(f, BONE)
	# the head: the top of the insulator, one big eye, a grin
	ball_head(f, BONE, 8, 5)
	eyes(f, "one", INK, 0.0030)
	mouth(f, "smile", INK, -0.0085)
	# the terminal and its spark (the prop)
	f.head.cylinder(0.0040, 0.0145, 0.0175, f.head_c, SILVER, 6)
	f.head.box(Vector3(0.0070, 0.0030, 0.0070), f.head_c + Vector3(0.0, 0.0180, 0.0), SILVER)
	var s0 := f.head_c + Vector3(0.0, 0.0195, 0.0)
	var s1 := s0 + Vector3(0.0060, 0.0014, 0.0)
	var s2 := s1 + Vector3(-0.0100, 0.0014, 0.0)
	var s3 := s2 + Vector3(0.0070, 0.0014, 0.0)
	limb(f.head, s0, s1, 0.0010, SODIUM)
	limb(f.head, s1, s2, 0.0010, SODIUM)
	limb(f.head, s2, s3, 0.0010, SODIUM)

## 17 Traffic cone: a cone with a face, arms out, surprised; its own hazard
## stripe. Mouth open in an O. Sodium and bone. Bob: wobbly.
func fig_traffic_cone(f: Fig, spec: Dictionary) -> void:
	f.neck_y0 = 0.0380
	f.neck_y1 = 0.0400
	f.head_c = Vector3(0.0, 0.0500, 0.0)
	f.head_r = 0.0110
	base(f, spec)
	f.body.box(Vector3(0.0340, 0.0030, 0.0340), Vector3(0.0, 0.0075, 0.0), SODIUM.darkened(0.25))   # the square foot
	frustum(f.body, Vector3(0.0, 0.0090, 0.0), 0.0150, 0.0105, 0.0205, SODIUM, 8)
	frustum(f.body, Vector3(0.0, 0.0295, 0.0), 0.0105, 0.0088, 0.0085, BONE, 8)   # the stripe
	# arms (the pose): stubby, flung out and up
	for side in [-1.0, 1.0]:
		limb(f.body, Vector3(side * 0.0110, 0.0240, 0.0), Vector3(side * 0.0200, 0.0340, 0.0020), 0.0026, SODIUM)
		f.body.box(Vector3(0.0062, 0.0062, 0.0050), Vector3(side * 0.0225, 0.0365, 0.0025), BONE)
	# the neck is the cone's own stripe line, hidden in the cone
	frustum(f.neck, Vector3(0.0, 0.0380, 0.0), 0.0088, 0.0084, 0.0020, SODIUM, 8)
	# the head: the cone's tip
	frustum(f.head, Vector3(0.0, 0.0400, 0.0), 0.0084, 0.0036, 0.0260, SODIUM, 8)
	frustum(f.head, Vector3(0.0, 0.0470, 0.0), 0.0066, 0.0056, 0.0040, BONE, 8)   # second stripe
	f.head.box(Vector3(0.0070, 0.0030, 0.0070), Vector3(0.0, 0.0675, 0.0), SODIUM.darkened(0.2))   # the tip's cap
	# the face on the cone: wide eyes and an O mouth
	var z := 0.0078
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0046, 0.0060, 0.0030), Vector3(side * 0.0036, 0.0570, z - 0.0005), BONE, rx(8.0))
		f.head.box(Vector3(0.0020, 0.0026, 0.0030), Vector3(side * 0.0036, 0.0565, z + 0.0008), INK, rx(8.0))
	f.head.box(Vector3(0.0060, 0.0060, 0.0030), Vector3(0.0, 0.0440, 0.0082), INK, rx(8.0))
	f.head.box(Vector3(0.0032, 0.0032, 0.0030), Vector3(0.0, 0.0440, 0.0092), INK.lerp(RUST, 0.35), rx(8.0))

# =====================================================================
# 18-29 the dash classics, our own versions (the shop set)
# =====================================================================

## 18 Nodding dog: a long-eared dachshund with a sad face and a bow tie, head
## on the spring. Brown and amber. Bob: a long slow nod.
func fig_nodding_dog(f: Fig, spec: Dictionary) -> void:
	f.head_r = 0.0145
	f.head_c = Vector3(0.0, 0.0420, 0.0075)
	f.head_scale = Vector3(1.0, 0.95, 1.10)
	f.neck_y0 = 0.0260
	f.neck_y1 = 0.0300
	f.axis = Vector2(0.0, 0.0070)
	base(f, spec)
	# the long body back along -z, four stubby legs, the tail up
	f.body.box(Vector3(0.0130, 0.0115, 0.0270), Vector3(0.0, 0.0185, -0.0010), FUR)
	for z in [0.0075, -0.0120]:
		for side in [-1.0, 1.0]:
			f.body.box(Vector3(0.0045, 0.0075, 0.0050), Vector3(side * 0.0045, 0.0095, z), FUR_DARK)
	limb(f.body, Vector3(0.0, 0.0230, -0.0140), Vector3(0.0, 0.0330, -0.0190), 0.0016, FUR_DARK)
	# the bow tie (a shop joke: he is dressed for dinner)
	f.body.box(Vector3(0.0040, 0.0040, 0.0030), Vector3(0.0, 0.0245, 0.0105), AMBER.darkened(0.2))
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0065, 0.0055, 0.0030), Vector3(side * 0.0050, 0.0245, 0.0100), AMBER, rz(side * 8.0))
	neck(f, FUR)
	ball_head(f, FUR)
	# the snout, the nose, the sad brows and the mouth
	var snout := f.head_c + Vector3(0.0, -0.0040, 0.0170)
	f.head.box(Vector3(0.0100, 0.0080, 0.0110), snout, FUR.lerp(AMBER, 0.4))
	f.head.box(Vector3(0.0046, 0.0032, 0.0030), snout + Vector3(0.0, 0.0028, 0.0060), INK)
	f.head.box(Vector3(0.0060, 0.0014, 0.0030), snout + Vector3(0.0, -0.0025, 0.0060), INK)
	eyes(f, "dots", INK, 0.0025, 0.0060)
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0050, 0.0014, 0.0030), f.head_c + Vector3(side * 0.0060, 0.0062, f.front() - 0.0010), INK, rz(side * 22.0))   # sad brows
	# the ears (the feature): long flaps hanging past the chin
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0045, 0.0260, 0.0090), f.head_c + Vector3(side * 0.0160, -0.0075, -0.0010), FUR_DARK, rz(side * -6.0))

## 19 Hula dancer: the spring at the WAIST, the hips and grass skirt sway, the
## head stays still. Arms up, grass skirt in strands. Moss skirt, sodium lei.
func fig_hula_dancer(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_DARK
	var waist := Vector3(0.0, 0.0220, 0.0)
	base(f, spec)
	# upper body (still): chest, arms raised, head and neck with weight 0
	torso(f, skin, Vector3(0.0165, 0.0090, 0.0100), Vector3(0.0, 0.0270, 0.0))
	f.body.box(Vector3(0.0170, 0.0045, 0.0105), Vector3(0.0, 0.0290, 0.0), SODIUM)   # the top
	for side in [-1.0, 1.0]:
		arm(f, Vector3(side * 0.0095, 0.0310, 0.0), Vector3(side * 0.0190, 0.0400, 0.0), Vector3(side * 0.0120, 0.0520, 0.0010), skin, skin, skin, 0.0024)
	# the lei: beads round the neck
	for i in 7:
		var a := TAU * float(i) / 7.0
		f.body.box(Vector3.ONE * 0.0032, Vector3(cos(a) * 0.0085, 0.0320 - 0.0015 * sin(a), sin(a) * 0.0075), SODIUM if i % 2 == 0 else BONE)
	# the head does not bob: build it into the body kit (weight 0)
	f.neck_y0 = 0.0340
	f.neck_y1 = 0.0400
	f.head_c = Vector3(0.0, 0.0565, 0.0)
	f.body.cylinder(NECK_R, 0.0340, 0.0400, Vector3.ZERO, skin, 6)
	sphere(f.body, f.head_c, f.head_r, skin)
	var z := f.front()
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0046, 0.0012, 0.003), f.head_c + Vector3(side * 0.0055, 0.0022, z + 0.0002), INK, rz(side * -12.0))
	f.body.box(Vector3(0.008, 0.0020, 0.003), f.head_c + Vector3(0.0, -0.0062, z + 0.0002), INK)
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0022, 0.0020, 0.003), f.head_c + Vector3(side * 0.0048, -0.0048, z + 0.0002), INK)
	f.body.box(Vector3(0.0310, 0.0110, 0.0300), f.head_c + Vector3(0.0, 0.0110, -0.0020), INK)   # hair
	f.body.box(Vector3(0.0120, 0.0250, 0.0070), f.head_c + Vector3(0.0, -0.0050, -0.0160), INK)   # long hair down the back
	f.body.box(Vector3(0.0070, 0.0070, 0.0040), f.head_c + Vector3(0.0125, 0.0100, 0.0120), SODIUM)   # a flower
	# the hips and skirt (the spring): weight 1 about the waist
	var hips := CockpitKit.new()
	hips.box(Vector3(0.0190, 0.0060, 0.0120), waist + Vector3(0.0, -0.0010, 0.0), MOSS.darkened(0.3))
	for i in 12:
		var a := TAU * float(i) / 12.0
		var top := waist + Vector3(cos(a) * 0.0100, -0.0030, sin(a) * 0.0068)
		var bot := waist + Vector3(cos(a) * 0.0135, -0.0150, sin(a) * 0.0095)
		limb(hips, top, bot, 0.0013, MOSS if i % 3 != 0 else MOSS.lightened(0.25))
	for side in [-1.0, 1.0]:
		hips.box(Vector3(0.0060, 0.0090, 0.0070), Vector3(side * 0.0045, 0.0105, 0.0), skin)   # legs showing through
	f.loose(hips, 1.0, waist)
	# the standard neck/head kits stay empty: nothing above the waist bobs

## 20 Sports nodder: a generic ballplayer with a bat on the shoulder, a bigger
## head on a quick nod. No team. Bone and navy. Bob: big head, quick nod.
func fig_sports_nodder(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	f.head_r = 0.0190
	f.head_c = Vector3(0.0, 0.0560, 0.0)
	base(f, spec)
	legs(f, BONE, 0.0055)
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0070, 0.0040, 0.0080), Vector3(side * 0.0055, 0.0085, 0.0), NAVY)   # socks
	torso(f, BONE, Vector3(0.020, 0.016, 0.012))
	f.body.box(Vector3(0.0022, 0.0160, 0.0016), Vector3(0.0, 0.0260, 0.0062), NAVY)   # the button line
	for i in 2:
		f.body.box(Vector3(0.0205, 0.0014, 0.0125), Vector3(0.0, 0.0215 + 0.0060 * i, 0.0), NAVY)   # pinstripes
	# the bat (the prop) rests on the right shoulder; both hands on the handle
	var knob := Vector3(0.0070, 0.0220, 0.0120)
	var tip := Vector3(0.0215, 0.0640, -0.0060)
	rod(f.body, knob, tip, 0.0018, 0.0036, WOOD, 6)
	disc(f.body, knob, 0.0028, 0.0016, WOOD.darkened(0.3), 6, along(knob, tip))
	arm(f, shoulder(1.0), Vector3(0.0150, 0.0245, 0.0070), knob + Vector3(0.0020, 0.0030, 0.0), BONE, skin)
	arm(f, shoulder(-1.0), Vector3(-0.0130, 0.0235, 0.0070), knob + Vector3(-0.0010, 0.0060, -0.0010), BONE, skin)
	neck(f)
	ball_head(f, skin)
	eyes(f, "dots", INK, 0.0025)
	mouth(f, "smile", INK, -0.0075)
	f.head.box(Vector3(0.0120, 0.0024, 0.0030), f.head_c + Vector3(0.0, -0.0010, f.front()), INK)   # eye black
	cap(f, NAVY, NAVY, 0.0090, 0.0140)
	f.head.box(Vector3(0.0036, 0.0036, 0.0020), f.head_c + Vector3(0.0, 0.0125, 0.0180), BONE)   # a plain button

## 21 Waving lucky cat: a round cat with one paw raised and a coin on its chest.
## Bone, amber and red. Bob: the paw waves steadily.
func fig_lucky_cat(f: Fig, spec: Dictionary) -> void:
	f.head_r = 0.0160
	f.head_c = Vector3(0.0, 0.0520, 0.0010)
	f.head_scale = Vector3(1.22, 0.90, 1.0)
	f.neck_y0 = 0.0330
	f.neck_y1 = 0.0370
	base(f, spec)
	sphere(f.body, Vector3(0.0, 0.0215, 0.0), 0.0150, BONE, Vector3(1.30, 1.05, 1.0), 8, 5)
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0065, 0.0045, 0.0085), Vector3(side * 0.0065, 0.0080, 0.0085), BONE)   # paws at the front
	f.body.box(Vector3(0.0050, 0.0050, 0.0100), Vector3(0.0130, 0.0085, -0.0120), AMBER, ry(30.0))   # the tail
	# the collar and the coin (the prop)
	ring(f.body, Vector3(0.0, 0.0335, 0.0), 0.0060, 0.0085, 0.0024, RED, 8)
	f.body.box(Vector3(0.0036, 0.0036, 0.0036), Vector3(0.0, 0.0310, 0.0085), AMBER)   # the bell
	var coin := Vector3(0.0, 0.0200, 0.0135)
	disc(f.body, coin, 0.0095, 0.0024, AMBER, 10, rx(80.0))
	f.body.box(Vector3(0.0070, 0.0030, 0.0016), coin + Vector3(0.0, 0.0, 0.0022), AMBER.darkened(0.35), rx(80.0))
	# the left arm hugs the coin
	limb(f.body, Vector3(-0.0135, 0.0280, 0.0030), Vector3(-0.0090, 0.0210, 0.0120), 0.0030, BONE)
	# the waving paw (the feature): its own swing about the shoulder, larger than the head's
	var paw := CockpitKit.new()
	var sh := Vector3(0.0135, 0.0290, 0.0020)
	limb(paw, sh, sh + Vector3(0.0040, 0.0150, 0.0040), 0.0030, BONE)
	paw.box(Vector3(0.0080, 0.0070, 0.0075), sh + Vector3(0.0040, 0.0190, 0.0045), BONE)
	paw.box(Vector3(0.0082, 0.0030, 0.0040), sh + Vector3(0.0040, 0.0160, 0.0075), AMBER)   # the pad
	f.loose(paw, 1.4, sh)
	neck(f, BONE)
	ball_head(f, BONE)
	eyes(f, "closed", INK, 0.0025, 0.0062)
	f.head.box(Vector3(0.0036, 0.0026, 0.0030), f.head_c + Vector3(0.0, -0.0020, f.front()), RED.darkened(0.2))   # nose
	f.head.box(Vector3(0.0300, 0.0010, 0.0012), f.head_c + Vector3(0.0, -0.0032, f.front() - 0.0014), INK)   # whiskers
	f.head.box(Vector3(0.0060, 0.0014, 0.0030), f.head_c + Vector3(0.0, -0.0065, f.front()), INK)   # a tiny mouth
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0110, 0.0110, 0.0045), f.head_c + Vector3(side * 0.0135, 0.0150, 0.0), BONE, rz(side * 45.0))   # ears
		f.head.box(Vector3(0.0060, 0.0060, 0.0020), f.head_c + Vector3(side * 0.0130, 0.0135, 0.0025), AMBER, rz(side * 45.0))
	f.head.box(Vector3(0.0040, 0.0070, 0.0040), f.head_c + Vector3(0.0, 0.0030, -0.0150), AMBER)   # a spot

## 22 Dancing flower: a flower in a pot wearing sunglasses, leaves out, head
## swaying. Moss and amber. Bob: sways.
func fig_dancing_flower(f: Fig, spec: Dictionary) -> void:
	f.head_r = 0.0100
	f.head_c = Vector3(0.0, 0.0560, 0.0)
	f.neck_y0 = 0.0330
	f.neck_y1 = 0.0450
	base(f, spec)
	# the pot
	frustum(f.body, Vector3(0.0, 0.0060, 0.0), 0.0110, 0.0145, 0.0160, RUST, 8)
	ring(f.body, Vector3(0.0, 0.0225, 0.0), 0.0130, 0.0165, 0.0035, RUST.lightened(0.15), 8)
	f.body.cylinder(0.0130, 0.0215, 0.0235, Vector3.ZERO, WOOD.darkened(0.3), 8)   # soil
	limb(f.body, Vector3(0.0, 0.0230, 0.0), Vector3(0.0, 0.0330, 0.0), 0.0020, MOSS)   # the stem's foot
	# the stem is the spring: a tall thin neck
	f.neck.cylinder(0.0020, 0.0330, 0.0450, Vector3.ZERO, MOSS, 6)
	# the leaves ride the stem (they flap with it)
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0150, 0.0020, 0.0070), Vector3(side * 0.0095, 0.0440, 0.0), MOSS, rz(side * 28.0))
	# the flower: a ring of fat petals, a face in the middle
	for i in 8:
		var a := TAU * float(i) / 8.0
		f.head.box(Vector3(0.0075, 0.0075, 0.0030), f.head_c + Vector3(cos(a) * 0.0125, sin(a) * 0.0125, -0.0010), AMBER if i % 2 == 0 else SODIUM, rz(rad_to_deg(a)))
	disc(f.head, f.head_c, 0.0092, 0.0045, WOOD, 10, facing())
	eyes(f, "shades", INK, 0.0020)
	mouth(f, "smile", INK, -0.0045)

## 23 Drinking bird: a tall bird in a top hat dipping toward a tiny cup. Sodium
## and silver. Bob: a slow tip forward and back.
func fig_drinking_bird(f: Fig, spec: Dictionary) -> void:
	var pivot_y := 0.0300
	f.neck_y0 = pivot_y
	f.neck_y1 = pivot_y + 0.0020
	f.head_c = Vector3(0.0, 0.0545, 0.0030)
	f.head_r = 0.0105
	base(f, spec)
	# the stand: two legs to a crossbar at the pivot, the cup out front
	for side in [-1.0, 1.0]:
		limb(f.body, Vector3(side * 0.0120, 0.0060, 0.0), Vector3(side * 0.0060, pivot_y, 0.0), 0.0014, SILVER)
	f.body.box(Vector3(0.0160, 0.0024, 0.0024), Vector3(0.0, pivot_y, 0.0), SILVER)
	f.body.cylinder(0.0045, 0.0060, 0.0130, Vector3(0.0, 0.0, 0.0125), SILVER, 8)   # the cup
	f.body.cylinder(0.0032, 0.0120, 0.0130, Vector3(0.0, 0.0, 0.0125), NAVY, 8)   # water
	# everything on the pivot bobs: the bulb, the tube, the head, the hat
	var bird := CockpitKit.new()
	sphere(bird, Vector3(0.0, 0.0175, -0.0010), 0.0090, SODIUM, Vector3.ONE, 8, 4)   # the bulb
	limb(bird, Vector3(0.0, 0.0255, -0.0005), Vector3(0.0, 0.0450, 0.0020), 0.0018, SILVER)   # the tube
	sphere(bird, f.head_c, f.head_r, SODIUM)
	bird.box(Vector3(0.0036, 0.0030, 0.0140), f.head_c + Vector3(0.0, -0.0025, 0.0150), SODIUM.darkened(0.3), rx(-25.0))   # the long beak
	for side in [-1.0, 1.0]:
		bird.box(Vector3(0.0030, 0.0040, 0.0030), f.head_c + Vector3(side * 0.0050, 0.0020, 0.0088), INK)
	# the top hat (the prop)
	disc(bird, f.head_c + Vector3(0.0, 0.0075, -0.0010), 0.0160, 0.0016, SILVER, 10)
	bird.cylinder(0.0090, 0.0080, 0.0205, f.head_c + Vector3(0.0, 0.0, -0.0010), SILVER, 10)
	ring(bird, f.head_c + Vector3(0.0, 0.0110, -0.0010), 0.0088, 0.0098, 0.0024, SODIUM, 10)   # the band
	f.loose(bird, 1.0, Vector3(0.0, pivot_y, 0.0))

## 24 Tiki: a carved block with a big open mouth and a headdress, short wobble.
## Wood brown and amber. Bob: rigid.
func fig_tiki(f: Fig, spec: Dictionary) -> void:
	f.neck_y0 = 0.0340
	f.neck_y1 = 0.0360
	base(f, spec)
	# the lower block: the crossed arms carved in, a belly
	f.body.box(Vector3(0.0300, 0.0280, 0.0210), Vector3(0.0, 0.0200, 0.0), WOOD)
	f.body.box(Vector3(0.0320, 0.0050, 0.0230), Vector3(0.0, 0.0255, 0.0), WOOD.darkened(0.3))   # a carved groove
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0060, 0.0140, 0.0040), Vector3(side * 0.0090, 0.0170, 0.0100), WOOD.lightened(0.12))   # hands
	f.body.box(Vector3(0.0100, 0.0040, 0.0040), Vector3(0.0, 0.0115, 0.0100), AMBER)   # a belly button stone
	f.neck.box(Vector3(0.0280, 0.0020, 0.0190), Vector3(0.0, 0.0350, 0.0), WOOD.darkened(0.45))   # the neck groove
	# the head block (the feature): a big open mouth with teeth, heavy brow
	f.head.box(Vector3(0.0310, 0.0260, 0.0220), Vector3(0.0, 0.0490, 0.0), WOOD)
	f.head.box(Vector3(0.0170, 0.0100, 0.0030), Vector3(0.0, 0.0430, 0.0095), INK)   # the mouth
	f.head.box(Vector3(0.0150, 0.0026, 0.0030), Vector3(0.0, 0.0462, 0.0105), AMBER)   # teeth
	f.head.box(Vector3(0.0150, 0.0026, 0.0030), Vector3(0.0, 0.0398, 0.0105), AMBER)
	f.head.box(Vector3(0.0330, 0.0045, 0.0060), Vector3(0.0, 0.0570, 0.0110), WOOD.darkened(0.35))   # the brow
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0060, 0.0040, 0.0030), Vector3(side * 0.0070, 0.0530, 0.0105), AMBER)   # the eyes
		f.head.box(Vector3(0.0030, 0.0030, 0.0030), Vector3(side * 0.0070, 0.0530, 0.0115), INK)
	f.head.box(Vector3(0.0050, 0.0080, 0.0040), Vector3(0.0, 0.0500, 0.0115), WOOD.lightened(0.12))   # the nose
	# the headdress (the prop): amber leaves fanned up
	for i in [-2.0, -1.0, 0.0, 1.0, 2.0]:
		f.head.box(Vector3(0.0050, 0.0110, 0.0030), Vector3(i * 0.0072, 0.0655 - absf(i) * 0.0015, 0.0), AMBER, rz(i * -20.0))

## 25 Little alien: a big-eyed grey alien waving, head on the spring. Silver and
## navy. Bob: light.
func fig_little_alien(f: Fig, spec: Dictionary) -> void:
	f.head_r = 0.0175
	f.head_c = Vector3(0.0, 0.0540, 0.0)
	f.head_scale = Vector3(1.25, 1.10, 1.0)
	f.neck_y0 = 0.0300
	f.neck_y1 = 0.0350
	base(f, spec)
	legs(f, NAVY_DEEP, 0.0038, 0.0, 0.0, 0.015)
	torso(f, NAVY_DEEP, Vector3(0.0130, 0.0150, 0.0090), Vector3(0.0, 0.0225, 0.0))
	f.body.box(Vector3(0.0135, 0.0030, 0.0095), Vector3(0.0, 0.0180, 0.0), SILVER)   # a belt
	arm(f, Vector3(0.0075, 0.0290, 0.0), Vector3(0.0190, 0.0300, 0.0010), Vector3(0.0260, 0.0360, 0.0030), GREY, GREY, GREY, 0.0016)
	for i in 3:
		limb(f.body, Vector3(0.0260, 0.0375, 0.0030), Vector3(0.0235 + 0.0030 * i, 0.0440, 0.0030), 0.0008, GREY)   # three long fingers
	arm(f, Vector3(-0.0075, 0.0290, 0.0), Vector3(-0.0130, 0.0220, 0.0010), Vector3(-0.0120, 0.0160, 0.0030), GREY, GREY, GREY, 0.0016)
	neck(f, GREY)
	ball_head(f, GREY)
	frustum(f.head, f.head_c + Vector3(0.0, -0.0220, 0.0010), 0.0040, 0.0130, 0.0080, GREY, 8)   # the pointed chin
	# the eyes (the feature): two huge black almonds
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0085, 0.0120, 0.0030), f.head_c + Vector3(side * 0.0075, 0.0010, f.front() - 0.0004), INK, rz(side * 20.0))
	mouth(f, "thin", INK, -0.0100)

## 26 Skeleton: a skull on the spring with a loose jaw, sunglasses, thumbs up.
## Bone and ink. Bob: loose.
func fig_skeleton(f: Fig, spec: Dictionary) -> void:
	base(f, spec)
	for side in [-1.0, 1.0]:
		limb(f.body, Vector3(side * 0.0045, 0.0060, 0.0), Vector3(side * 0.0045, 0.0170, 0.0), 0.0018, BONE)   # shin bones
		f.body.box(Vector3(0.0050, 0.0022, 0.0090), Vector3(side * 0.0045, 0.0071, 0.0020), BONE)   # feet
	f.body.box(Vector3(0.0130, 0.0040, 0.0080), Vector3(0.0, 0.0180, 0.0), BONE)   # pelvis
	limb(f.body, Vector3(0.0, 0.0180, 0.0), Vector3(0.0, 0.0340, 0.0), 0.0020, BONE)   # spine
	for i in 4:
		f.body.box(Vector3(0.0160 - 0.0020 * i, 0.0020, 0.0090 - 0.0012 * i), Vector3(0.0, 0.0225 + 0.0035 * i, 0.0), BONE)   # ribs
	f.body.box(Vector3(0.0200, 0.0026, 0.0036), Vector3(0.0, 0.0340, 0.0), BONE)   # collar bones
	# thumbs up (the pose): the right arm up, a fist and thumb
	arm(f, Vector3(0.0095, 0.0335, 0.0), Vector3(0.0215, 0.0300, 0.0070), Vector3(0.0215, 0.0450, 0.0095), BONE, BONE, BONE, 0.0015)
	f.body.box(Vector3(0.0025, 0.0070, 0.0025), Vector3(0.0215, 0.0505, 0.0095), BONE)
	arm(f, shoulder(-1.0), Vector3(-0.0140, 0.0240, 0.0020), Vector3(-0.0115, 0.0180, 0.0060), BONE, BONE, BONE, 0.0016)
	neck(f, BONE)
	# the skull: a dome, cheekbones, a nose hole, the shades
	sphere(f.head, f.head_c + Vector3(0.0, 0.0010, 0.0), f.head_r, BONE, Vector3(1.0, 1.0, 0.95))
	f.head.box(Vector3(0.0240, 0.0070, 0.0160), f.head_c + Vector3(0.0, -0.0105, 0.0040), BONE)   # the cheeks
	f.head.box(Vector3(0.0036, 0.0046, 0.0030), f.head_c + Vector3(0.0, -0.0040, f.front() - 0.0010), INK)   # nose hole
	eyes(f, "shades", INK, 0.0030)
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0040, 0.0020, 0.0180), f.head_c + Vector3(side * 0.0150, 0.0030, 0.0070), INK)   # the arms of the shades
	# the jaw (the feature): its own pivot at the hinge, swings more than the skull
	var jaw := CockpitKit.new()
	var hinge := f.head_c + Vector3(0.0, -0.0120, -0.0020)
	jaw.box(Vector3(0.0200, 0.0050, 0.0140), hinge + Vector3(0.0, -0.0040, 0.0060), BONE)
	jaw.box(Vector3(0.0150, 0.0020, 0.0030), hinge + Vector3(0.0, -0.0010, 0.0135), INK)   # the gap
	for i in 4:
		jaw.box(Vector3(0.0016, 0.0024, 0.0020), hinge + Vector3(-0.0054 + 0.0036 * i, 0.0005, 0.0138), BONE)   # teeth
	f.loose(jaw, 1.7, hinge)

## 27 Cowboy: a huge hat tipping, head and hat on the spring. Rust and bone.
## Bob: a slow tip.
func fig_cowboy(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN
	base(f, spec)
	for side in [-1.0, 1.0]:
		limb(f.body, Vector3(side * 0.0060, LEG_Y1, 0.0), Vector3(side * 0.0120, 0.0075, 0.0), 0.0036, RUST.darkened(0.35))   # bow legs
		f.body.box(Vector3(0.0080, 0.0055, 0.0110), Vector3(side * 0.0120, 0.0085, 0.0015), WOOD.darkened(0.3))   # boots
	torso(f, BONE, Vector3(0.020, 0.016, 0.012))
	f.body.box(Vector3(0.0210, 0.0160, 0.0070), Vector3(0.0, 0.0260, -0.0035), RUST)   # the vest, open at the front
	for side in [-1.0, 1.0]:
		f.body.box(Vector3(0.0065, 0.0160, 0.0060), Vector3(side * 0.0075, 0.0260, 0.0035), RUST)
	f.body.box(Vector3(0.0210, 0.0030, 0.0125), Vector3(0.0, 0.0190, 0.0), WOOD.darkened(0.2))   # belt
	f.body.box(Vector3(0.0055, 0.0045, 0.0020), Vector3(0.0, 0.0190, 0.0068), BRASS)   # buckle
	# thumbs hooked in the belt
	for side in [-1.0, 1.0]:
		arm(f, shoulder(side), Vector3(side * 0.0160, 0.0240, 0.0030), Vector3(side * 0.0075, 0.0195, 0.0080), BONE, skin, skin)
	neck(f)
	ball_head(f, skin)
	eyes(f, "half", INK, 0.0020)
	mouth(f, "line", INK, -0.0065)
	f.head.box(Vector3(0.0060, 0.0014, 0.0030), f.head_c + Vector3(0.0, -0.0105, f.front() - 0.0020), WOOD)   # a bit of chin beard
	f.head.cylinder(0.0075, -0.0175, -0.0145, f.head_c, RED, 8)   # bandana
	f.head.box(Vector3(0.0040, 0.0060, 0.0030), f.head_c + Vector3(-0.0040, -0.0190, 0.0130), RED)   # its knot
	# the hat (the prop): a brim wider than the base, tipped over one eye
	var hb := rx(14.0) * rz(-10.0)
	var hc := f.head_c + Vector3(0.0, 0.0050, 0.0)
	disc(f.head, hc, 0.0235, 0.0024, RUST, 10, hb)
	for side in [-1.0, 1.0]:
		f.head.box(Vector3(0.0050, 0.0050, 0.0160), hc + hb * Vector3(side * 0.0220, 0.0025, -0.0030), RUST, hb)   # the curled rim
	frustum(f.head, hc + hb * Vector3(0.0, 0.0010, 0.0), 0.0130, 0.0115, 0.0095, RUST, 8, hb)   # the crown
	f.head.box(Vector3(0.0120, 0.0045, 0.0120), hc + hb * Vector3(0.0, 0.0100, 0.0), RUST.darkened(0.25), hb)   # the dent
	frustum(f.head, hc + hb * Vector3(0.0, 0.0020, 0.0), 0.0136, 0.0132, 0.0030, BONE, 8, hb)   # the band

## 28 Surfer: the whole body on a spring base, riding a tiny board, arms out.
## Sodium and navy. Bob: the whole figure.
func fig_surfer(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_DARK
	base(f, spec)
	# the spring sits at the base: the board and everything on it swing
	var rider := CockpitKit.new()
	var deck := Vector3(0.0, 0.0085, 0.0)
	rider.box(Vector3(0.0420, 0.0030, 0.0130), deck, SODIUM, ry(15.0))
	rider.box(Vector3(0.0380, 0.0032, 0.0030), deck, BONE, ry(15.0))   # the stripe
	rider.box(Vector3(0.0080, 0.0030, 0.0060), deck + Vector3(0.0170, 0.0, -0.0040), SODIUM, ry(15.0) * rx(-30.0))   # the nose kicks up
	rider.box(Vector3(0.0030, 0.0060, 0.0030), deck + Vector3(-0.0170, -0.0030, 0.0045), INK)   # the fin
	# knees bent, feet apart along the board
	for side in [-1.0, 1.0]:
		var foot := deck + Vector3(side * 0.0095, 0.0015, side * 0.0020)
		rider.box(Vector3(0.0070, 0.0025, 0.0095), foot, skin)
		limb(rider, foot + Vector3(0.0, 0.0010, 0.0), foot + Vector3(side * 0.0010, 0.0090, 0.0040), 0.0028, skin)
		limb(rider, foot + Vector3(side * 0.0010, 0.0090, 0.0040), Vector3(side * 0.0045, 0.0165, 0.0), 0.0030, NAVY)   # shorts
	rider.box(Vector3(0.0160, 0.0050, 0.0110), Vector3(0.0, 0.0175, 0.0), NAVY)
	rider.box(Vector3(0.0170, 0.0130, 0.0100), Vector3(0.0, 0.0265, 0.0), skin, rz(8.0))   # the chest
	# arms out wide for balance
	limb(rider, Vector3(0.0090, 0.0310, 0.0), Vector3(0.0230, 0.0330, -0.0030), 0.0024, skin)
	limb(rider, Vector3(-0.0090, 0.0300, 0.0), Vector3(-0.0210, 0.0200, 0.0040), 0.0024, skin)
	rider.box(Vector3(0.0045, 0.0045, 0.0045), Vector3(0.0240, 0.0335, -0.0030), skin)
	rider.box(Vector3(0.0045, 0.0045, 0.0045), Vector3(-0.0220, 0.0190, 0.0045), skin)
	# the head (sun-bleached mop) on a short neck; no second spring
	var hc := Vector3(0.0, 0.0510, 0.0)
	rider.cylinder(NECK_R, 0.0330, 0.0360, Vector3.ZERO, skin, 6)
	sphere(rider, hc, 0.0160, skin)
	rider.box(Vector3(0.0310, 0.0100, 0.0300), hc + Vector3(0.0, 0.0115, -0.0020), AMBER)
	rider.box(Vector3(0.0320, 0.0060, 0.0080), hc + Vector3(0.0, 0.0085, 0.0140), AMBER, rx(-12.0))
	for side in [-1.0, 1.0]:
		rider.box(Vector3(0.0036, 0.0046, 0.003), hc + Vector3(side * 0.0055, 0.0025, 0.0162), INK)
	rider.box(Vector3(0.0100, 0.0030, 0.003), hc + Vector3(0.0, -0.0050, 0.0162), INK)
	rider.box(Vector3(0.0060, 0.0016, 0.003), hc + Vector3(0.0, -0.0042, 0.0172), BONE)   # a grin
	f.loose(rider, 1.0, Vector3(0.0, BASE_H, 0.0))
	f.neck_y0 = BASE_H
	f.neck_y1 = BASE_H + 0.001

## 29 Traffic cop nodder: a cartoon cop with a whistle, finger wagging. Police
## blue and silver. Bob: the head, the finger wags along.
func fig_traffic_cop(f: Fig, spec: Dictionary) -> void:
	var skin := SKIN_PALE
	base(f, spec)
	legs(f, POLICE_BLUE.darkened(0.45), 0.0055)
	torso(f, POLICE_BLUE, Vector3(0.021, 0.017, 0.012))
	f.body.box(Vector3(0.0215, 0.0030, 0.0125), Vector3(0.0, 0.0190, 0.0), INK)   # belt
	f.body.box(Vector3(0.0040, 0.0040, 0.0020), Vector3(-0.0055, 0.0280, 0.0065), SILVER)   # the badge
	for i in 3:
		f.body.box(Vector3(0.0018, 0.0018, 0.0016), Vector3(0.0, 0.0215 + 0.0045 * i, 0.0065), SILVER)   # buttons
	arm(f, shoulder(1.0), Vector3(0.0150, 0.0245, 0.0030), Vector3(0.0120, 0.0190, 0.0075), POLICE_BLUE, skin, POLICE_BLUE)
	# the wagging finger (the feature): the forearm swings about the elbow
	var elbow := Vector3(-0.0165, 0.0260, 0.0075)
	limb(f.body, shoulder(-1.0), elbow, ARM_R, POLICE_BLUE)
	var fore := CockpitKit.new()
	limb(fore, elbow, elbow + Vector3(-0.0050, 0.0170, 0.0040), ARM_R, POLICE_BLUE)
	fore.box(Vector3(0.0068, 0.0068, 0.0060), elbow + Vector3(-0.0050, 0.0205, 0.0050), skin)
	limb(fore, elbow + Vector3(-0.0050, 0.0235, 0.0050), elbow + Vector3(-0.0050, 0.0310, 0.0055), 0.0014, skin)
	f.loose(fore, 1.5, elbow)
	neck(f)
	ball_head(f, skin)
	eyes(f, "dots", INK, 0.0030)
	# the whistle (the prop): fat, silver, on a cord, in the mouth
	var wh := f.head_c + Vector3(0.0030, -0.0065, f.front() + 0.0030)
	f.head.box(Vector3(0.0070, 0.0050, 0.0070), wh, SILVER)
	f.head.cylinder(0.0032, 0.0, 0.0035, wh + Vector3(0.0, 0.0025, -0.0010), SILVER, 6)
	f.head.box(Vector3(0.0070, 0.0030, 0.0030), wh + Vector3(0.0, -0.0040, -0.0010), skin.darkened(0.25))   # the lower lip
	limb(f.head, wh + Vector3(0.0030, 0.0, 0.0), wh + Vector3(0.0120, -0.0110, -0.0080), 0.0006, INK)   # the cord
	# a peaked cap, the badge on the front, a chin strap
	f.head.cylinder(0.0172, 0.0075, 0.0160, f.head_c, POLICE_BLUE, 8)
	f.head.box(Vector3(0.0300, 0.0050, 0.0300), f.head_c + Vector3(0.0, 0.0150, -0.0020), POLICE_BLUE)   # the high flat top
	f.head.box(Vector3(0.0260, 0.0020, 0.0150), f.head_c + Vector3(0.0, 0.0080, 0.0210), INK)
	f.head.box(Vector3(0.0060, 0.0060, 0.0020), f.head_c + Vector3(0.0, 0.0130, 0.0170), SILVER)
	f.head.box(Vector3(0.0350, 0.0030, 0.0350), f.head_c + Vector3(0.0, 0.0078, 0.0), INK)   # the band
	f.head.box(Vector3(0.0020, 0.0070, 0.0030), f.head_c + Vector3(-0.0110, -0.0070, f.front() - 0.0060), INK, rz(-25.0))   # the moustache end
	f.head.box(Vector3(0.0120, 0.0030, 0.0030), f.head_c + Vector3(-0.0050, -0.0030, f.front()), INK)   # the moustache
