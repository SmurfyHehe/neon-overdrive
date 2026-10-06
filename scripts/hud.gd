class_name Hud
extends CanvasLayer

# HUD v1 (replaces the temporary debug readout that lived in game.gd).
# Bottom-right: gear + A/M, speed in km/h, an RPM bar, boost and engine status.
# Top-left: one small camera/traffic line. Bottom-left: a short controls hint
# (the full list lives on the pause menu's Controls page).
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
const RPM_GREEN := Color("#3FD060") # RPM bar only (allowlisted in tests/palette.gd)

const KMH_PER_MS := 3.6
## Fraction of max_rpm where the manual shift cue lights.
const SHIFT_POINT := 0.92
## Fractions of max_rpm where the bar turns amber, then red.
const AMBER_FROM := 0.65
const RED_FROM := 0.85

var player: PlayerCar
var camera: ChaseCamera
var traffic: TrafficManager

var lbl_gear: Label
var lbl_mode: Label
var lbl_speed: Label
var lbl_unit: Label
var lbl_status: Label
var lbl_boost: Label
var lbl_rpm: Label
var lbl_info: Label
var lbl_hint: Label
var rpm_bar: RpmBar
var cluster: VBoxContainer   # the gear / speed / RPM block; hidden in the cockpit view

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

static func kmh(speed_ms: float) -> int:
	return int(round(maxf(speed_ms, 0.0) * KMH_PER_MS))

## Shift cue: manual box only, in a forward gear with a higher one to go to, at
## or past SHIFT_POINT. The cockpit's LED strip flashes on the same rule.
static func shift_cue(p: PlayerCar, frac: float) -> bool:
	return (not p.automatic_transmission and p.gear >= 1
		and p.gear < p.gear_ratios.size() and frac >= SHIFT_POINT)

## The fast blink every cue shares (90 ms on, 90 ms off).
static func blink() -> bool:
	return int(Time.get_ticks_msec() / 90) % 2 == 0

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
	var max_rpm := maxf(player.max_rpm, 1.0)
	var rpm := player.motor_rpm
	var frac := clampf(rpm / max_rpm, 0.0, 1.0)
	var gear := player.gear
	var engine_off: bool = player.realistic_clutch and not player.engine_running

	lbl_gear.text = gear_text(gear)
	lbl_mode.text = PlayerCar.TRANSMISSION_LETTERS[player.transmission_mode()]
	lbl_speed.text = str(kmh(player.current_speed()))
	lbl_rpm.text = "%d rpm" % int(rpm)

	# BUG FIX (2026-09-13): shift_flash_t was tracked since milestone 2 but
	# nothing read it, so shifting had no feedback. The gear now flashes.
	var shifting: bool = player.shift_flash_t > 0.0
	lbl_gear.add_theme_color_override("font_color", SILVER if shifting else AMBER)

	var cue := shift_cue(player, frac)
	var blink := Hud.blink()
	rpm_bar.frac = frac
	rpm_bar.cue = cue
	rpm_bar.blink = blink
	rpm_bar.queue_redraw()

	if engine_off:
		lbl_status.text = "ENGINE OFF · hold X to start"
		lbl_status.add_theme_color_override("font_color", RED)
	elif cue:
		lbl_status.text = "SHIFT" if blink else ""
		lbl_status.add_theme_color_override("font_color", AMBER)
	else:
		lbl_status.text = ""

	if player.turbo_boost_max > 0.0:
		lbl_boost.text = "BOOST %.2f / %.2f bar" % [player.boost, player.turbo_boost_max]
	else:
		lbl_boost.text = ""

	lbl_info.text = "%s cam · %d cars (%d full-sim)" % [
		camera.mode_name().to_lower(), traffic.cars.size(), traffic.detailed_count()]
