class_name SteeringWheel
extends Node3D

# The player's steering wheel (cockpit milestone, 2026-10-06). An aftermarket
# flat-bottom wheel in the style Roy sent, drawn from code, no files, no logo:
# black grips with a red stitch seam, carbon top and bottom sections, a row of
# 15 shift LEDs across the top that fill inward from both ends as the revs rise
# (green, amber, red) and all flash at the shift point, a small LCD at 12
# o'clock with rpm, km/h and the gear, a plain centre pad, backlit spoke buttons
# and two paddles behind the rim.
#
# Wheel space: X right, Y up, +Z toward the driver. The parent tilts and
# places it; set_angle() turns it about its own axis (+ = turning right, i.e.
# clockwise as the driver sees it). Draw calls: rim+spokes+pad+plate 1, LEDs
# and buttons 1 (a MultiMesh), LCD label 1, paddles 2.

const RADIUS := 0.175       # rim centreline, a 35 cm wheel
const GRIP_R := 0.017       # rim tube radius at the grips
const CARBON_R := 0.014     # a touch slimmer on the carbon sections
const FLAT_Y := -0.70       # the bottom chord, as a share of RADIUS
const LED_COUNT := 15
## LEDs start filling here (share of max_rpm) and are all lit at the shift point.
const RPM_FROM := 0.60
## Where the automatic is (GEVP full-throttle upshift) and the manual cue lights.
const SHIFT_POINT := Hud.SHIFT_POINT
const LED_ENERGY := 3.0

const LEATHER := Color("#141418")
const STITCH := Color("#E5262B")   # tail red
const CARBON := Color("#262B33")
const CARBON_ALT := Color("#1A1E25")
const PAD := Color("#0E1014")
const SPOKE := Color("#2A2E36")

## Per-car looks, set by CockpitFrame before the wheel is added (the beater's
## ivory rim on a painted-metal dash, Roy 2026-10-09); the defaults are the coupe's.
var rim_colour := LEATHER
var seam_colour := STITCH
var spoke_colour := SPOKE
var carbon_colour := CARBON
var carbon_alt_colour := CARBON_ALT
const LCD_BG := Color("#0A0C10")
const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")
const RED := Color("#E5262B")
const GREEN := Hud.RPM_GREEN       # the one allowed green (tests/core/palette.gd)

var body: MeshInstance3D
var leds: MultiMeshInstance3D
var lcd: Label3D
var paddle_l: Node3D
var paddle_r: Node3D
var angle := 0.0          # radians, + = right
var lit_count := 0
var flashing := false
var led_colours := PackedColorArray()   # per LED, alpha 1 = lit
var _paddle_t := {-1: 0.0, 1: 0.0}

func _ready() -> void:
	_build_body()
	_build_leds()
	_build_lcd()
	paddle_l = _paddle(-1.0)
	paddle_r = _paddle(1.0)

## Turn the wheel: + is right (clockwise for the driver).
func set_angle(a: float) -> void:
	angle = a
	rotation = Vector3(0.0, 0.0, -a)

## A point on the rim centreline at `deg` degrees (0 = 3 o'clock, counter-clockwise
## as the driver sees it), in the wheel's own space; turns with the wheel. The
## driver's hands (next PR) grip here at 0 and 180.
func rim_point(deg: float) -> Vector3:
	var p := _centreline(deg_to_rad(deg))
	return Vector3(p.x, p.y, 0.0)

## Rim centreline with the flat bottom.
func _centreline(t: float) -> Vector2:
	var p := Vector2(cos(t), sin(t)) * RADIUS
	p.y = maxf(p.y, FLAT_Y * RADIUS)
	return p

static func _is_grip(deg: float) -> bool:
	var d := fposmod(deg, 360.0)
	return d <= 50.0 or d >= 310.0 or (d >= 130.0 and d <= 230.0)

func _build_body() -> void:
	var kit := CockpitKit.new()
	# Rim: a tube swept round the D-shaped centreline, 8-sided, one colour per
	# face; the grips are leather with a red seam on the face that looks at the
	# driver and inward, the top and bottom sections carbon with alternating
	# shades for the weave.
	const SEGS := 56
	# Tube cross-section angles: 0 = outward, 90 = toward the driver, 180 =
	# inward; the narrow 118..130 face is the stitch seam (about 3.5 mm).
	const PHIS := [0.0, 45.0, 90.0, 118.0, 130.0, 180.0, 225.0, 270.0, 315.0]
	const SEAM := 3
	var SIDES := PHIS.size()
	var rings := []
	for s in SEGS + 1:
		var t := TAU * float(s % SEGS) / SEGS
		var deg := rad_to_deg(t)
		var c := _centreline(t)
		var r := GRIP_R if _is_grip(deg) else CARBON_R
		var radial := Vector3(cos(t), sin(t), 0.0)
		if c.y <= FLAT_Y * RADIUS + 1e-4:
			radial = Vector3(0.0, -1.0, 0.0)   # the flat chord: tube offset straight down
		var ring := []
		for j in SIDES:
			var phi := deg_to_rad(float(PHIS[j]))
			ring.append(Vector3(c.x, c.y, 0.0) + radial * (r * cos(phi)) + Vector3(0, 0, r * sin(phi)))
		rings.append(ring)
	for s in SEGS:
		var deg := rad_to_deg(TAU * (float(s) + 0.5) / SEGS)
		var grip := _is_grip(deg)
		for j in SIDES:
			var k := (j + 1) % SIDES
			var col := rim_colour
			if grip:
				if j == SEAM:
					col = seam_colour     # the seam, between the driver-facing and inward faces
			else:
				col = carbon_colour if (s % 2 == 0) else carbon_alt_colour
			kit.quad(rings[s][j], rings[s + 1][j], rings[s + 1][k], rings[s][k], col)
	# Top plate inside the rim that carries the LEDs (carbon), and the LCD bezel.
	kit.ring_sector(0.118, RADIUS - CARBON_R + 0.004, deg_to_rad(38.0), deg_to_rad(142.0), -0.006, 0.006, carbon_colour, 14, carbon_alt_colour)
	kit.box(Vector3(0.090, 0.046, 0.012), Vector3(0.0, 0.088, 0.004), LCD_BG)
	# Spokes: 9, 3 and 6 o'clock, flat bars from the pad to the rim.
	kit.box(Vector3(0.12, 0.034, 0.012), Vector3(-0.105, 0.0, 0.0), spoke_colour)
	kit.box(Vector3(0.12, 0.034, 0.012), Vector3(0.105, 0.0, 0.0), spoke_colour)
	kit.box(Vector3(0.034, 0.10, 0.012), Vector3(0.0, -0.085, 0.0), spoke_colour)
	# Centre pad (plain, no badge) and a hub ring behind it.
	kit.box(Vector3(0.115, 0.085, 0.030), Vector3(0.0, 0.0, 0.012), PAD)
	kit.cylinder(0.055, -0.03, 0.0, Vector3.ZERO, SPOKE, 10, Basis(Vector3.RIGHT, PI / 2.0))
	# Button housings on the side spokes (the lit dots are MultiMesh instances).
	for sx in [-1.0, 1.0]:
		kit.box(Vector3(0.028, 0.026, 0.006), Vector3(sx * 0.085, 0.0, 0.008), PAD)
	body = kit.instance(CockpitKit.material(0.7, 0.1, 0.15), "WheelBody")
	add_child(body)

## LED positions along the top plate, outer ends first (index 0 and 14 at the
## ends, 7 in the middle), plus the four button dots after them.
func _build_leds() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.011, 0.007, 0.004)
	mm.mesh = box
	mm.instance_count = LED_COUNT + 4
	led_colours.resize(LED_COUNT)
	for i in LED_COUNT:
		led_colours[i] = _led_colour(i, false, false)
		var deg := lerpf(138.0, 42.0, float(i) / (LED_COUNT - 1))
		var t := deg_to_rad(deg)
		var p := Vector3(cos(t), sin(t), 0.0) * 0.142
		var xf := Transform3D(Basis(Vector3.BACK, t - PI / 2.0), p + Vector3(0, 0, 0.008))
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, _led_colour(i, false, false))
	var b := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			mm.set_instance_transform(LED_COUNT + b, Transform3D(Basis().scaled(Vector3(0.5, 0.5, 0.5)), Vector3(sx * 0.085, sy * 0.006, 0.012)))
			mm.set_instance_color(LED_COUNT + b, Color(AMBER.r, AMBER.g, AMBER.b, 0.35))
			b += 1
	leds = MultiMeshInstance3D.new()
	leds.name = "Leds"
	leds.multimesh = mm
	leds.material_override = CockpitKit.glow_material(LED_ENERGY)   # instance colour, alpha = lit
	add_child(leds)

func _build_lcd() -> void:
	lcd = Label3D.new()
	lcd.name = "Lcd"
	lcd.text = "0 rpm\n0 km/h  N"
	lcd.font = UiTheme.font("lcd")   # DSEG7: car digital displays
	lcd.font_size = 30
	lcd.pixel_size = 0.00048
	lcd.modulate = AMBER
	lcd.outline_size = 0
	lcd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lcd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lcd.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	lcd.position = Vector3(0.0, 0.088, 0.011)
	add_child(lcd)

## A paddle behind the rim at 9 (side -1) or 3 (side +1); pivots at its inner end.
func _paddle(side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "PaddleL" if side < 0.0 else "PaddleR"
	pivot.position = Vector3(side * 0.075, -0.005, -0.028)
	var kit := CockpitKit.new()
	kit.box(Vector3(0.095, 0.036, 0.005), Vector3(side * 0.0475, 0.0, 0.0), CARBON)
	kit.box(Vector3(0.012, 0.028, 0.012), Vector3(side * 0.012, 0.0, 0.004), SPOKE)
	pivot.add_child(kit.instance(CockpitKit.material(0.6, 0.2)))
	add_child(pivot)
	return pivot

## Which LEDs are on at a share of max_rpm: pair k (0..7) lights from the ends
## inward, the middle one last, exactly at the shift point.
static func lit_count_for(frac: float) -> int:
	var n := 0
	for k in 8:
		var at := RPM_FROM + (SHIFT_POINT - RPM_FROM) * float(k) / 7.0
		if frac >= at - 1e-6:
			n += 1 if k == 7 else 2
	return n

## Green at the ends, amber, then red in the middle.
static func led_base_colour(i: int) -> Color:
	var k := mini(i, LED_COUNT - 1 - i)
	if k >= 6:
		return RED
	if k >= 3:
		return AMBER
	return GREEN

func _led_colour(i: int, lit: bool, flash: bool) -> Color:
	var c := SILVER if (lit and flash) else led_base_colour(i)
	return Color(c.r, c.g, c.b, 1.0 if lit else 0.0)

## Per frame from the cockpit: rpm share, the HUD's shift cue and blink, and
## what the LCD shows.
func update(frac: float, cue: bool, blink: bool, rpm: float, kmh: int, gear_text: String) -> void:
	lit_count = lit_count_for(frac)
	flashing = cue and blink
	var mm := leds.multimesh
	for i in LED_COUNT:
		var k := mini(i, LED_COUNT - 1 - i)
		var lit := lit_count == LED_COUNT if k == 7 else lit_count >= 2 * (k + 1)
		var c := _led_colour(i, lit, flashing)
		led_colours[i] = c   # what the MultiMesh was given (headless can't read it back)
		mm.set_instance_color(i, c)
	lcd.text = "%d rpm\n%d km/h  %s" % [int(rpm), kmh, gear_text]

## Flick a paddle (-1 left/down, +1 right/up): it rotates toward the driver's
## pull and springs back over ~0.25 s.
func flick(side: int) -> void:
	_paddle_t[side] = 0.25

func _process(delta: float) -> void:
	for side in [-1, 1]:
		var t: float = _paddle_t[side]
		if t <= 0.0:
			continue
		t = maxf(t - delta, 0.0)
		_paddle_t[side] = t
		var k := sin(t / 0.25 * PI)     # out and back
		var p: Node3D = paddle_l if side < 0 else paddle_r
		p.rotation = Vector3(0.0, -float(side) * 0.35 * k, 0.0)

func triangle_count() -> int:
	var n := 0
	for m in find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				n += (mesh as ArrayMesh).surface_get_array_len(s) / 3
	n += 12 * (LED_COUNT + 4)
	return n
