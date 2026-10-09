class_name Hud
extends CanvasLayer

# HUD v1 (replaces the temporary debug readout that lived in game.gd).
# Bottom-right: gear + A/M, speed in km/h, an RPM bar, boost and engine status.
# Top-left: one small camera/traffic line. Bottom-left: a short controls hint
# (the full list lives on the pause menu's Controls page). Top-centre, chase
# view only: the rear strip, a mirror-image of the cockpit's rearview render
# (CockpitMirrors; nothing extra is rendered for it), framed in dusk, switched
# by FxSettings "rear_strip". Proximity cue (2026-10-06): as a car closes in
# behind, the strip's frame thickens and warms to sodium, and in the cockpit
# the rearview glass warms the same way; rear_threat() is the 0..1 level.
#
# Everything is anchored to the window edges, so it scales with the window.
# Palette: "Amber vs Dusk" (ROADMAP). The one exception is the RPM bar, which
# runs green -> amber -> red toward redline because Roy asked for it.
# It reads the car and owns no state.

const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const RED := Color("#E5262B")
const DUSK := Color("#0B1220")      # text outline, darker than the sky
const RPM_GREEN := Color("#3FD060") # RPM bar only (allowlisted in tests/core/palette.gd)

const KMH_PER_MS := 3.6
## Rear strip: the rearview render drawn at this size, this far below the top edge.
const STRIP_SIZE := Vector2(320, 96)
const STRIP_TOP := 12.0
const STRIP_BORDER := 2.0
## Proximity cue: a car behind, same way, within this corridor and range.
const THREAT_HALF_WIDTH := 4.5   # m either side (own lane and the next)
const THREAT_NEAR := 3.0         # m behind the car's origin: full cue
const THREAT_FAR := 25.0         # m: cue starts
const THREAT_RATE := 8.0         # 1/s smoothing
## Blind-spot cue (2026-10-07): a same-way car in the next lane, from a little
## ahead of the car's origin to a few lengths behind, lights that side's door
## mirror dot. Lanes are 3.2 m (RoadChunkBuilder.LANE_W).
const SIDE_X_MIN := 1.4          # m out from the centreline: clear of our own lane's middle
const SIDE_X_MAX := 5.0          # m: the next lane, not the one beyond
const SIDE_Z_AHEAD := 3.0        # m ahead of the origin (alongside)
const SIDE_Z_BEHIND := 8.0       # m behind
## Fraction of max_rpm where the manual shift cue lights.
const SHIFT_POINT := 0.92
## Fractions of max_rpm where the bar turns amber, then red.
const AMBER_FROM := 0.65
const RED_FROM := 0.85

var player: PlayerCar
var camera: ChaseCamera
var traffic: TrafficManager
## The night clock (living world step 1); null in tests that build a bare HUD.
var night_clock: NightClock

var lbl_gear: Label
var lbl_mode: Label
var lbl_speed: Label
var lbl_unit: Label
var lbl_status: Label
var lbl_boost: Label
var lbl_rpm: Label
var lbl_fuel: Label
var lbl_info: Label
var lbl_clock: Label
var lbl_hint: Label
var rpm_bar: RpmBar
var cluster: VBoxContainer   # the gear / speed / RPM block; hidden in the cockpit view
var rear_strip: TextureRect
var rear_frame: Panel
var rear_style: StyleBoxFlat
var rear_threat := 0.0   # 0..1, smoothed
var side_threat := [0.0, 0.0]   # left, right; 0..1, smoothed

## Segmented RPM bar. Draws itself from frac / shift_frac / cue.
class RpmBar extends Control:
	const SEGMENTS := 32
	var frac := 0.0
	var cue := false   # shift cue: the bar flashes and the shift tick brightens
	var blink := false

	func _init() -> void:
		custom_minimum_size = Vector2(320, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gap := 2.0
		var w := (size.x - gap * (SEGMENTS - 1)) / SEGMENTS
		for i in SEGMENTS:
			var t := (float(i) + 0.5) / SEGMENTS
			var c := Hud.rpm_colour(t)
			var lit := t <= frac
			if lit and cue and blink:
				c = Hud.SILVER
			if not lit:
				c = Color(c.r, c.g, c.b, 0.16)
			draw_rect(Rect2(i * (w + gap), 0.0, w, size.y), c)
		# Shift point tick, just above the bar.
		var x := size.x * Hud.SHIFT_POINT
		var tick := Hud.AMBER if cue else Color(Hud.SILVER.r, Hud.SILVER.g, Hud.SILVER.b, 0.7)
		draw_line(Vector2(x, -5.0), Vector2(x, -1.0), tick, 2.0)

## Bar colour at a fraction (0..1) of max_rpm: green, then amber, then red.
static func rpm_colour(t: float) -> Color:
	if t >= RED_FROM:
		return RED
	if t >= AMBER_FROM:
		return AMBER
	return RPM_GREEN

## "R", "N" or the gear number.
static func gear_text(g: int) -> String:
	if g < 0:
		return "R"
	if g == 0:
		return "N"
	return str(g)

## "FUEL ▮▮▮▯▯▯▯▯" with eight bars, rounded up so a drop left shows one bar.
static func fuel_text(f: FuelTank) -> String:
	var bars := clampi(ceili(f.fraction() * 8.0 - 0.001), 0, 8)
	return "FUEL " + "▮".repeat(bars) + "▯".repeat(8 - bars)

static func kmh(speed_ms: float) -> int:
	# Magnitude, not signed: reversing reads the same km/h as driving forward
	# (the R in the gear display says which way). Signed speed stays on
	# PlayerCar.current_speed() for gear logic, camera and sound.
	return int(round(absf(speed_ms) * KMH_PER_MS))

## Shift cue: manual box only, in a forward gear with a higher one to go to, at
## or past SHIFT_POINT. The cockpit's LED strip flashes on the same rule.
static func shift_cue(p: PlayerCar, frac: float) -> bool:
	return (not p.automatic_transmission and p.gear >= 1
		and p.gear < p.gear_ratios.size() and frac >= SHIFT_POINT)

## The fast blink every cue shares (90 ms on, 90 ms off).
static func blink() -> bool:
	return int(Time.get_ticks_msec() / 90) % 2 == 0

## Sets a control's font colour only when it changes. add_theme_color_override()
## re-themes the control every call, even with the same colour, and the HUD
## refreshes every frame (frame-rate pass, 2026-10-08).
static func set_font_color(c: Control, color: Color) -> void:
	if not c.has_theme_color_override("font_color") or c.get_theme_color("font_color") != color:
		c.add_theme_color_override("font_color", color)

func _init(car: PlayerCar, cam: ChaseCamera, traffic_mgr: TrafficManager) -> void:
	player = car
	camera = cam
	traffic = traffic_mgr

func _ready() -> void:
	layer = 5  # above the radio captions, below warning lights (9) and pause (10)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	lbl_info = _label(root, 14, Color(SILVER.r, SILVER.g, SILVER.b, 0.7))
	lbl_info.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	lbl_info.position = Vector2(16, 12)

	rear_frame = Panel.new()
	rear_frame.name = "RearFrame"
	rear_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rear_style = StyleBoxFlat.new()
	rear_style.bg_color = Color(DUSK, 0.85)
	rear_style.border_color = Color(SILVER, 0.35)
	rear_style.set_border_width_all(1)
	rear_frame.add_theme_stylebox_override("panel", rear_style)
	rear_frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	rear_frame.offset_left = -(STRIP_SIZE.x * 0.5 + STRIP_BORDER)
	rear_frame.offset_right = STRIP_SIZE.x * 0.5 + STRIP_BORDER
	rear_frame.offset_top = STRIP_TOP
	rear_frame.offset_bottom = STRIP_TOP + STRIP_SIZE.y + 2.0 * STRIP_BORDER
	rear_frame.visible = false
	root.add_child(rear_frame)
	rear_strip = TextureRect.new()
	rear_strip.name = "RearStrip"
	rear_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rear_strip.flip_h = true   # a mirror: left is right
	rear_strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rear_strip.stretch_mode = TextureRect.STRETCH_SCALE
	rear_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	rear_strip.offset_left = STRIP_BORDER
	rear_strip.offset_top = STRIP_BORDER
	rear_strip.offset_right = -STRIP_BORDER
	rear_strip.offset_bottom = -STRIP_BORDER
	rear_frame.add_child(rear_strip)

	lbl_hint = _label(root, 14, Color(SILVER.r, SILVER.g, SILVER.b, 0.7))
	lbl_hint.text = "Esc: pause · controls"
	lbl_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	lbl_hint.offset_left = 16.0
	lbl_hint.offset_top = -34.0   # relative to the bottom edge
	lbl_hint.offset_bottom = -14.0

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	root.add_child(margin)

	cluster = VBoxContainer.new()
	cluster.size_flags_horizontal = Control.SIZE_SHRINK_END
	cluster.size_flags_vertical = Control.SIZE_SHRINK_END
	cluster.add_theme_constant_override("separation", 4)
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cluster)

	# The car's clock, over the speedo (the head unit shows it in the cockpit).
	lbl_clock = _label(cluster, 18, AMBER)
	lbl_clock.name = "Clock"
	lbl_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Row: gear (+ A/M) on the left, speed on the right.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(row)

	var gear_col := VBoxContainer.new()
	gear_col.add_theme_constant_override("separation", -6)
	gear_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gear_col)
	lbl_gear = _label(gear_col, 56, AMBER)
	lbl_gear.custom_minimum_size = Vector2(52, 0)
	lbl_gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_mode = _label(gear_col, 16, SILVER)
	lbl_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var speed_col := VBoxContainer.new()
	speed_col.add_theme_constant_override("separation", -10)
	speed_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(speed_col)
	lbl_speed = _label(speed_col, 64, SILVER)
	lbl_speed.custom_minimum_size = Vector2(190, 0)
	lbl_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_unit = _label(speed_col, 16, SILVER)
	lbl_unit.text = "km/h"
	lbl_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Status line (ENGINE OFF / SHIFT), kept in the layout even when empty so
	# nothing jumps.
	lbl_status = _label(cluster, 18, AMBER)
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.custom_minimum_size = Vector2(0, 24)

	rpm_bar = RpmBar.new()
	cluster.add_child(rpm_bar)

	var under := HBoxContainer.new()
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(under)
	lbl_boost = _label(under, 14, AMBER)
	lbl_boost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_rpm = _label(under, 14, SILVER)
	lbl_rpm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Fuel gauge (Stage C): eight bars, amber, red and blinking when low.
	lbl_fuel = _label(cluster, 14, AMBER)
	lbl_fuel.name = "Fuel"
	lbl_fuel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

## The rear strip shows in the chase view when the flag is on and the cockpit
## has mirrors to render; the cockpit view has the rearview mirror itself.
func _refresh_rear_strip() -> void:
	var mirrors: CockpitMirrors = camera.frame.mirrors if camera.frame != null else null
	var show := camera.view == ChaseCamera.View.CHASE and FxSettings.is_on("rear_strip") and mirrors != null and mirrors.enabled
	if show and rear_strip.texture == null:
		rear_strip.texture = mirrors.rear_texture()
	rear_frame.visible = show
	if mirrors != null and mirrors.strip != show:
		mirrors.set_strip(show)

## Closest car behind, going the same way, in the corridor: 0 none or far,
## 1 right on the bumper. Raw, unsmoothed.
func rear_threat_now() -> float:
	var to_car := player.global_transform.affine_inverse()
	var fwd := -player.global_transform.basis.z
	var worst := 0.0
	for c in traffic.cars:
		var car := c as Node3D
		if not car.visible:
			continue
		if (-car.global_transform.basis.z).dot(fwd) < 0.3:
			continue   # oncoming or crossing
		var local := to_car * car.global_position
		if absf(local.x) > THREAT_HALF_WIDTH or local.z < THREAT_NEAR or local.z > THREAT_FAR:
			continue
		worst = maxf(worst, 1.0 - (local.z - THREAT_NEAR) / (THREAT_FAR - THREAT_NEAR))
	return worst

## Same-way cars in the blind spot: [left, right], each 1 when a car is in
## that zone, else 0. Raw, unsmoothed.
func side_threat_now() -> Array:
	var to_car := player.global_transform.affine_inverse()
	var fwd := -player.global_transform.basis.z
	var out := [0.0, 0.0]
	for c in traffic.cars:
		var car := c as Node3D
		if not car.visible:
			continue
		if (-car.global_transform.basis.z).dot(fwd) < 0.3:
			continue   # oncoming or crossing
		var local := to_car * car.global_position
		var ax := absf(local.x)
		if ax < SIDE_X_MIN or ax > SIDE_X_MAX or local.z < -SIDE_Z_AHEAD or local.z > SIDE_Z_BEHIND:
			continue
		out[0 if local.x < 0.0 else 1] = 1.0
	return out

func _refresh_side_cue() -> void:
	var k := 1.0 - exp(-THREAT_RATE * get_process_delta_time())
	var now := side_threat_now()
	for i in 2:
		side_threat[i] = lerpf(side_threat[i], now[i], k)
		if camera.frame != null:
			camera.frame.mirrors.set_side_cue(i, side_threat[i])

func _refresh_rear_cue() -> void:
	var delta := get_process_delta_time()
	rear_threat = lerpf(rear_threat, rear_threat_now(), 1.0 - exp(-THREAT_RATE * delta))
	var level := rear_threat if rear_threat > 0.02 else 0.0
	rear_style.border_color = Color(SILVER, 0.35).lerp(SODIUM, level)
	rear_style.set_border_width_all(1 + int(round(3.0 * level)))
	if camera.frame != null:
		camera.frame.mirrors.set_rear_cue(level)

func _label(parent: Control, font_size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", DUSK)
	l.add_theme_constant_override("outline_size", 4 if font_size >= 40 else 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	# In the cockpit the wheel's LCD and the cluster carry speed, gear and rpm
	# (Roy, 2026-10-06); the warning lights and radio toast are other layers.
	cluster.visible = camera.view != ChaseCamera.View.COCKPIT
	_refresh_rear_strip()
	_refresh_rear_cue()
	_refresh_side_cue()
	var max_rpm := maxf(player.max_rpm, 1.0)
	var rpm := player.motor_rpm
	var frac := clampf(rpm / max_rpm, 0.0, 1.0)
	var gear := player.gear
	var engine_off: bool = player.realistic_clutch and not player.engine_running

	lbl_clock.text = night_clock.text() if night_clock != null else ""
	lbl_gear.text = gear_text(gear)
	lbl_mode.text = PlayerCar.TRANSMISSION_LETTERS[player.transmission_mode()]
	lbl_speed.text = str(kmh(player.current_speed()))
	lbl_rpm.text = "%d rpm" % int(rpm)

	# BUG FIX (2026-09-13): shift_flash_t was tracked since milestone 2 but
	# nothing read it, so shifting had no feedback. The gear now flashes.
	var shifting: bool = player.shift_flash_t > 0.0
	Hud.set_font_color(lbl_gear, SILVER if shifting else AMBER)

	var cue := shift_cue(player, frac)
	var blink := Hud.blink()
	rpm_bar.frac = frac
	rpm_bar.cue = cue
	rpm_bar.blink = blink
	rpm_bar.queue_redraw()

	if engine_off:
		lbl_status.text = "ENGINE OFF · hold X to start"
		Hud.set_font_color(lbl_status, RED)
	elif player.limp.is_limping():
		lbl_status.text = "LIMP · " + LimpMode.cause_name(player.limp.cause)
		Hud.set_font_color(lbl_status, RED)
	elif cue:
		lbl_status.text = "SHIFT" if blink else ""
		Hud.set_font_color(lbl_status, AMBER)
	else:
		lbl_status.text = ""

	lbl_fuel.text = fuel_text(player.fuel) if player.fuel.enabled else ""
	lbl_fuel.add_theme_color_override("font_color", RED if player.fuel.is_low() else AMBER)
	lbl_fuel.modulate.a = 1.0 if not player.fuel.is_low() or blink or player.fuel.is_empty() else 0.25

	if player.turbo_boost_max > 0.0:
		lbl_boost.text = "BOOST %.2f / %.2f bar" % [player.boost, player.turbo_boost_max]
	else:
		lbl_boost.text = ""

	lbl_info.text = "%s cam · %d cars (%d full-sim)" % [
		camera.mode_name().to_lower(), traffic.cars.size(), traffic.detailed_count()]
