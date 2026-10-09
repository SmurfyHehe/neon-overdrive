class_name GaugePod
extends Node3D

## The bolt-on gauge pod: two 68 mm aftermarket gauges, AFR and boost PSI,
## in a holder screwed to the dash top at the base of the driver's A-pillar
## clamped to the driver's A-pillar (2026-10-09, Roy: "comes free" with the
## first boost setup, so it is a bolt-on, not part of any car's own cluster).
## The numbers come from GaugeReadouts; this file is only the look.
##
## Every car gets its own pod (STYLES, by PlayerCar.chassis_kind()): the bezel,
## the face, its backlight, the needle and the holder's finish, and where on
## the dash it is screwed (MOUNTS, cabin space, with the face turned to the
## driver's eye). The per-car cabins work can move a pod by editing MOUNTS
## or by handing `GaugePod.new(kind, boost_max, mount)` its own transform.
##
## Geometry: each gauge is a flat backlit face, a bezel ring, ticks, zone
## sectors and a needle on a pivot, the same parts as the main cluster's
## dials but 68 mm across, plus a holder shell. About 300 triangles, two draw
## calls (static kit, glow kit) plus the two needles and the Label3Ds.
## About 1300 triangles (the ticks are boxes).

const GAUGE_R := 0.034        # 68 mm gauges, big enough to read from the seat
const SWEEP := 240.0          # degrees, lower left (empty) to lower right (full)
const PITCH := 0.080          # centre to centre
const PSI_MIN := 15.0         # the vacuum end of the PSI face (-15)
const AFR_STOICH_FRAC := (GaugeReadouts.STOICH - GaugeReadouts.AFR_MIN) / (GaugeReadouts.AFR_MAX - GaugeReadouts.AFR_MIN)

const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const RED := Color("#E5262B")
const NAVY := Color("#1B2A4A")
const NAVY_DEEP := Color("#0E1424")
const BLACK_FACE := Color("#0B0E14")
const PLASTIC := Color("#1C1F26")
const CHROME := Color("#D8DCE2")
const CARBON := Color("#15171B")
const CARBON_ALT := Color("#23262C")
const RUST := Color("#5A3A24")
const CREAM := Color("#E8D9B0")

## Per-car look. Every pod is amber-backlit (Roy, 2026-10-09: "bring back the
## amber light", bolt-on mods look their best until the mod tree): face_glow
## is how hard the face is lit, marks and most labels are AMBER, and the
## bezel, face tint, needle and holder tell the cars apart. alt is the bezel's
## weave colour (carbon), holder is the pod shell.
const STYLES := {
	"p0_beater":    {"bezel": RUST, "alt": Color(0, 0, 0, 0), "face": Color("#1A1A18"), "face_glow": 0.30, "needle": Color("#E0D6C0"), "marks": AMBER, "label": AMBER, "holder": Color("#2A2521"), "label_size": 16},
	"p1_coupe":     {"bezel": CHROME, "alt": Color(0, 0, 0, 0), "face": BLACK_FACE, "face_glow": 0.40, "needle": RED, "marks": AMBER, "label": AMBER, "holder": PLASTIC, "label_size": 16},
	"p2_hothatch":  {"bezel": PLASTIC, "alt": Color(0, 0, 0, 0), "face": Color("#2C2416"), "face_glow": 0.45, "needle": SODIUM, "marks": AMBER, "label": AMBER, "holder": PLASTIC, "label_size": 16},
	"p3_tuner":     {"bezel": CARBON, "alt": CARBON_ALT, "face": BLACK_FACE, "face_glow": 0.55, "needle": RED, "marks": AMBER, "label": AMBER, "holder": CARBON, "label_size": 15},
	"p4_kei":       {"bezel": CHROME, "alt": Color(0, 0, 0, 0), "face": NAVY, "face_glow": 0.35, "needle": AMBER, "marks": AMBER, "label": SILVER, "holder": PLASTIC, "label_size": 16},
	"p5_muscle":    {"bezel": CHROME, "alt": Color(0, 0, 0, 0), "face": Color("#3A2E14"), "face_glow": 0.45, "needle": CREAM, "marks": AMBER, "label": AMBER, "holder": Color("#979AA0"), "label_size": 17},
	"p6_crossover": {"bezel": PLASTIC, "alt": Color(0, 0, 0, 0), "face": NAVY_DEEP, "face_glow": 0.40, "needle": AMBER, "marks": AMBER, "label": SILVER, "holder": PLASTIC, "label_size": 16},
}
const DEFAULT_STYLE := "p1_coupe"

## Where the pod is clamped, in cabin space (the CockpitFrame's): on the
## driver's A-pillar, the classic spot, 40% of the way up, on a bracket that
## holds the faces 4.5 cm proud of the pillar (its bar is 9 cm deep) and 3 cm
## inboard of it, so no part of the bar is in front of a face (Roy,
## 2026-10-09: "pillars might be blocking out the gauges"), the two gauges
## stacked along the pillar ("along": the pillar's direction, so the pair
## follows it however the pillar leans in the driver's view) with each face
## turned to the driver's eye (yaw turns the faces to the right, pitch tips
## them up). The pillar zone (|x| > 0.55) is outside the dash-line rule
## tests/view/cockpit_interior.gd enforces, and the pod overlaps the pillar's
## own silhouette, so it costs little glass. The P1 pillar runs from
## (-0.78, 0.83, -0.69) to (-0.62, 1.345, -0.03) (CockpitFrame); the per-car
## cabins work can give each car its own entry here.
const P1_PILLAR := Vector3(0.16, 0.515, 0.66)
const MOUNTS := {
	"p0_beater":    {"pos": Vector3(-0.628, 1.043, -0.347), "yaw": 25.1, "pitch": 4.6, "along": P1_PILLAR},
	"p1_coupe":     {"pos": Vector3(-0.628, 1.043, -0.347), "yaw": 25.1, "pitch": 4.6, "along": P1_PILLAR},
	"p2_hothatch":  {"pos": Vector3(-0.628, 1.043, -0.347), "yaw": 25.1, "pitch": 4.6, "along": P1_PILLAR},
	"p3_tuner":     {"pos": Vector3(-0.628, 1.043, -0.347), "yaw": 25.1, "pitch": 4.6, "along": P1_PILLAR},
	"p4_kei":       {"pos": Vector3(-0.628, 1.043, -0.347), "yaw": 25.1, "pitch": 4.6, "along": P1_PILLAR},
	"p5_muscle":    {"pos": Vector3(-0.628, 1.043, -0.347), "yaw": 25.1, "pitch": 4.6, "along": P1_PILLAR},
	"p6_crossover": {"pos": Vector3(-0.628, 1.043, -0.347), "yaw": 25.1, "pitch": 4.6, "along": P1_PILLAR},
}

var kind := DEFAULT_STYLE
var style: Dictionary
var boost_max := 0.0         # bar, the setup the PSI face was scaled for
var psi_max := 15.0
var readouts := GaugeReadouts.new()
var afr_needle: Node3D
var psi_needle: Node3D
var along := Vector3.UP   # the pillar in the pod's frame; the pair is stacked along it
var roll := 0.0           # radians, the pair axis seen face-on, from +x (each face stays upright)

static func mount(for_kind: String) -> Transform3D:
	var m: Dictionary = MOUNTS.get(for_kind, MOUNTS[DEFAULT_STYLE])
	var b := Basis(Vector3.UP, deg_to_rad(m.yaw)) * Basis(Vector3.RIGHT, -deg_to_rad(m.pitch))   # +pitch tips the faces up
	return Transform3D(b, m.pos)

## The pillar's direction in the pod's own frame (the faces look along +z).
static func mount_along(for_kind: String) -> Vector3:
	var m: Dictionary = MOUNTS.get(for_kind, MOUNTS[DEFAULT_STYLE])
	return (mount(for_kind).basis.inverse() * (m.along as Vector3)).normalized()

## The PSI face runs -15 .. psi_max, where psi_max covers the setup's boost
## with headroom, in 15 psi steps: 15 up to a bar, 30 up to two.
static func psi_face_max(boost_bar: float) -> float:
	return maxf(15.0, ceilf(boost_bar * GaugeReadouts.PSI_PER_BAR * 1.3 / 15.0) * 15.0)

func _init(car_kind: String, boost_bar: float, at: Transform3D = Transform3D.IDENTITY) -> void:
	kind = car_kind
	style = STYLES.get(car_kind, STYLES[DEFAULT_STYLE])
	boost_max = boost_bar
	psi_max = psi_face_max(boost_bar)
	name = "GaugePod"
	transform = at if at != Transform3D.IDENTITY else mount(car_kind)
	along = (basis.inverse() * (MOUNTS.get(car_kind, MOUNTS[DEFAULT_STYLE]).along as Vector3)).normalized()
	roll = atan2(along.y, along.x)

func _ready() -> void:
	_build()

func _build() -> void:
	var k := CockpitKit.new()
	var lit := CockpitKit.new()
	var glow: float = style.face_glow
	# The pair is stacked along the pillar. A raked pillar runs toward the eye
	# as it climbs, so the upper gauge sits that much further forward (both
	# faces stay square to the eye, each in its own can); the holder follows
	# the pillar's slant and the clamp strap goes round it.
	var axis := Vector3(cos(roll), sin(roll), 0.0)
	var slant := along.z / maxf(Vector2(along.x, along.y).length(), 0.05)
	var hy := (axis + Vector3.BACK * slant).normalized()
	var hx := Vector3(sin(roll), -cos(roll), 0.0)   # so hx x hy faces the eye (+z)
	var hb := Basis(hx, hy, hx.cross(hy).normalized())
	var holder_len := PITCH * sqrt(1.0 + slant * slant) + 2.0 * GAUGE_R + 0.012
	# The holder's front is 34 mm behind the face centres: tilted 55 degrees
	# to the faces, any nearer and its edge would stand in front of the lower
	# gauge's rim (tests/view/gauge_layout.gd). The cans bridge the gap.
	k.box(Vector3(2.0 * GAUGE_R + 0.016, holder_len, 0.044), hb * Vector3(0.0, 0.0, -0.056), style.holder, hb)
	k.box(Vector3(2.0 * GAUGE_R + 0.030, 0.016, 0.040), hb * Vector3(0.0, 0.0, -0.078), Color("#2A2C32"), hb)   # strap
	for sx in [-0.5, 0.5]:   # screw heads on the strap ends
		k.cylinder(0.003, 0.0, 0.004, hb * Vector3(sx * (2.0 * GAUGE_R + 0.030), 0.0, -0.056), Color("#82848A"), 6, hb)
	for g in 2:
		var d := -PITCH * 0.5 + PITCH * g
		var c := axis * d + Vector3.BACK * (d * slant)
		# the gauge can, its face (backlit), bezel ring and outer wall
		k.cylinder(GAUGE_R + 0.002, -0.060, -0.008, c, style.holder, 16, Basis(Vector3.RIGHT, PI / 2.0))
		lit.cylinder(GAUGE_R, -0.004, 0.0, c, Color((style.face as Color).lerp(AMBER, 0.35), glow), 20, Basis(Vector3.RIGHT, PI / 2.0))
		var bez := CockpitKit.new()
		bez.ring_sector(GAUGE_R, GAUGE_R + 0.006, 0.0, TAU, -0.010, 0.004, style.bezel, 20, style.alt)
		bez.offset(c)
		k.merge(bez)
		# ticks: 9 majors with minors between
		var ticks := 17
		for i in ticks:
			var t := float(i) / (ticks - 1)
			var a := deg_to_rad(210.0 - SWEEP * t)
			var major := i % 2 == 0
			var len := 0.0055 if major else 0.003
			var p := c + Vector3(cos(a), sin(a), 0.0) * (GAUGE_R - 0.004 - len * 0.5) + Vector3(0, 0, 0.0008)
			lit.box(Vector3(0.0016 if major else 0.001, len, 0.0012), p, Color(style.marks, 0.7 if major else 0.45), Basis(Vector3.BACK, a - PI / 2.0))
		# zone sectors just inside the ticks
		var zones := CockpitKit.new()
		if g == 0:
			# AFR: rich band (10..13) amber, lean band (16..20) red, stoich mark
			zones.ring_sector(GAUGE_R - 0.013, GAUGE_R - 0.0105, _ang(_afr_t(13.0)), _ang(0.0), 0.0, 0.0010, Color(AMBER, 0.55), 6)
			zones.ring_sector(GAUGE_R - 0.013, GAUGE_R - 0.0105, _ang(1.0), _ang(_afr_t(16.0)), 0.0, 0.0010, Color(RED, 0.55), 6)
			var sa := _ang(AFR_STOICH_FRAC)
			lit.box(Vector3(0.0024, 0.0075, 0.0014), c + Vector3(cos(sa), sin(sa), 0.0) * (GAUGE_R - 0.0085) + Vector3(0, 0, 0.0009), Color(SILVER, 0.9), Basis(Vector3.BACK, sa - PI / 2.0))
		else:
			# PSI: vacuum (-15..0) dim, boost (0..max) amber, top fifth red
			var zero := _psi_t(0.0)
			zones.ring_sector(GAUGE_R - 0.013, GAUGE_R - 0.0105, _ang(zero), _ang(0.0), 0.0, 0.0010, Color(SILVER, 0.22), 8)
			zones.ring_sector(GAUGE_R - 0.013, GAUGE_R - 0.0105, _ang(0.8), _ang(zero), 0.0, 0.0010, Color(AMBER, 0.55), 8)
			zones.ring_sector(GAUGE_R - 0.013, GAUGE_R - 0.0105, _ang(1.0), _ang(0.8), 0.0, 0.0010, Color(RED, 0.55), 4)
		zones.offset(c)
		lit.merge(zones)
	add_child(k.instance(CockpitKit.material(0.6, 0.3), "Holder"))
	add_child(lit.instance(CockpitKit.glow_material(SteeringWheel.LED_ENERGY), "Faces"))
	var ls: int = style.label_size
	var lc: Color = style.label
	var left := axis * (-PITCH * 0.5) + Vector3.BACK * (-PITCH * 0.5 * slant)    # AFR: the lower gauge on a pillar
	var right := axis * (PITCH * 0.5) + Vector3.BACK * (PITCH * 0.5 * slant)     # PSI: the upper
	_label("AFR", ls, left + Vector3(0.0, -0.011, 0.0012), lc)
	_label("10", ls - 5, left + _rim(0.0), lc)
	_label("14.7", ls - 6, left + _rim(AFR_STOICH_FRAC), lc)
	_label("20", ls - 5, left + _rim(1.0), lc)
	_label("PSI", ls, right + Vector3(0.0, -0.011, 0.0012), lc)
	_label("-15", ls - 5, right + _rim(0.0), lc)
	_label("0", ls - 5, right + _rim(_psi_t(0.0)), lc)
	_label("%d" % int(psi_max), ls - 5, right + _rim(1.0), lc)
	afr_needle = _needle(left + Vector3(0, 0, 0.0022), "AfrNeedle")
	psi_needle = _needle(right + Vector3(0, 0, 0.0022), "PsiNeedle")
	_point(afr_needle, 0.0)
	_point(psi_needle, _psi_t(0.0))

## Needle angle (radians) for a fraction across the face.
static func _ang(t: float) -> float:
	return deg_to_rad(210.0 - SWEEP * t)

func _afr_t(afr: float) -> float:
	return (afr - GaugeReadouts.AFR_MIN) / (GaugeReadouts.AFR_MAX - GaugeReadouts.AFR_MIN)

func _psi_t(psi: float) -> float:
	return (psi + PSI_MIN) / (psi_max + PSI_MIN)

## A numeral's spot: just inside the rim at the fraction's angle.
func _rim(t: float) -> Vector3:
	var a := _ang(t)
	return Vector3(cos(a), sin(a), 0.0) * (GAUGE_R - 0.0135) + Vector3(0, 0, 0.0012)

func _needle(at: Vector3, node_name: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = at
	var k := CockpitKit.new()
	k.box(Vector3(0.0022, GAUGE_R - 0.006, 0.0012), Vector3(0.0, (GAUGE_R - 0.006) * 0.5 - 0.003, 0.0), Color(style.needle, 1.0))
	k.box(Vector3(0.002, 0.005, 0.0012), Vector3(0.0, -0.0045, 0.0), Color(style.needle, 0.6))
	k.cylinder(0.0035, -0.0008, 0.0010, Vector3.ZERO, Color(CHROME, 0.25), 8, Basis(Vector3.RIGHT, PI / 2.0))
	pivot.add_child(k.instance(CockpitKit.glow_material(SteeringWheel.LED_ENERGY)))
	add_child(pivot)
	return pivot

func _label(text: String, size: int, at: Vector3, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0003
	l.modulate = col
	l.outline_size = 0
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = at
	add_child(l)
	return l

static func _point(needle: Node3D, t: float) -> void:
	needle.rotation = Vector3(0.0, 0.0, deg_to_rad(120.0 - SWEEP * clampf(t, 0.0, 1.0)))

## The two faces' centres in the pod's own space (AFR, then PSI), for the
## layout checks: nothing may sit between a face and the driver's eye.
func gauge_centres() -> Array[Vector3]:
	return [afr_needle.position - Vector3(0, 0, 0.0022), psi_needle.position - Vector3(0, 0, 0.0022)]

## Each tick: read the car, move the needles.
func update(car: Vehicle, delta: float) -> void:
	readouts.update(car, delta)
	_point(afr_needle, readouts.afr_frac())
	_point(psi_needle, readouts.psi_frac(PSI_MIN, psi_max))

func triangle_count() -> int:
	var n := 0
	for m in find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				n += (mesh as ArrayMesh).surface_get_array_len(s) / 3
	return n
