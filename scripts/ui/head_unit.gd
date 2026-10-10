class_name HeadUnit
extends Node3D

# The touch-screen radio (UI direction blend, section 4; Roy signed off
# 2026-10-07). A self-contained head unit for the centre stack: everything it
# looks like lives here, so the interior redesign can restyle or replace it
# without touching the hand or radio logic. CockpitFrame places it and feeds it
# the radio's state; DriverModel's hand taps the points it reports.
#
# Node space: origin at the centre of the screen face, the screen faces +z
# (toward the driver), +x to the car's right (CockpitFrame only translates it).
#
# The screen: four station tiles, a now-playing line, a small level meter, a
# sodium frame on the playing tile only. Navy, sodium, amber and silver; no
# scanlines (it reads newer than the car). Drawn by a Control in a SubViewport,
# redrawn only when something on it changes (the meter at METER_HZ). Radio off:
# the screen dims. The car clock (NightClock) is the exception: it sits on its
# own layer, big, top right, and stays lit with the radio off like a real head
# unit's clock (Roy, 2026-10-09: he had not noticed it was there).
#
# Per car (STYLES): an older car gets an aftermarket tablet in a printed bezel,
# a little too bright, with a physical volume knob beside it (pressing the knob
# turns the radio off); a modern factory screen is touch only, and "off" is a
# power spot on the glass.

const PlaceNames := preload("res://scripts/world/place_names.gd")

const NAVY := Color("#1B2A4A")
const NAVY_DEEP := Color("#0E1424")
const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")
const BEZEL := Color("#202227")
const BEZEL_LINE := Color("#2A2C32")
const KNOB_DARK := Color("#15171C")

## ~10 inch 16:10 tablet.
const SCREEN_W := 0.216
const SCREEN_H := 0.135
const BEZEL_BORDER := 0.010
const BEZEL_DEPTH := 0.016
const PX := Vector2i(512, 320)
const METER_HZ := 15.0
const OFF_DIM := Color(0.26, 0.27, 0.32)
const KNOB_R := 0.014
const KNOB_DEPTH := 0.018
const KNOB_PRESS := 0.004
const TICK_SECS := 0.028
## How long the name of an area you cross into stays on the screen.
const AREA_SECS := 4.0

## Keyed by PlayerCar.chassis_kind(); DEFAULT_STYLE for anything unlisted.
##   aftermarket: printed bezel, tablet proud of the stack
##   knob: a physical volume knob beside the screen (old-car screens only)
##   brightness: screen gain (>1: the cheap tablet is a touch too bright)
const STYLES := {
	"p1_coupe": {"aftermarket": true, "knob": true, "brightness": 1.3},
	"test": {"aftermarket": false, "knob": false, "brightness": 1.0},
}
const DEFAULT_STYLE := "p1_coupe"

## Tile rects and the header, screen pixels.
const TILE_Y := 112.0
const TILE_H := 180.0
const TILE_GAP := 14.0
const MARGIN := 18.0
const POWER_SPOT := Vector2(322, 40)   # touch-only units: tap here for off (left of the clock)

var style: Dictionary
var has_knob := false
var station := -1
var now_playing := ""
var level := 0.0
var clock_text := ""     # the car clock, drawn top right (NightClock)
var area_name := ""      # the area just entered, shown for AREA_SECS (world step 4)
var area_t := 0.0
var taps := 0
var knob_presses := 0
var viewport: SubViewport
var canvas: ScreenCanvas
var clock_canvas: ClockCanvas   # the clock, over the dimming
var screen: MeshInstance3D
var knob: Node3D
var _tick: AudioStreamPlayer
var _meter_t := 0.0
var _knob_t := 0.0

static func style_for(kind: String) -> Dictionary:
	return STYLES[kind] if STYLES.has(kind) else STYLES[DEFAULT_STYLE]

func _init(car_kind: String) -> void:
	style = style_for(car_kind)
	has_knob = style.knob
	name = "Radio"

func _ready() -> void:
	_build_body()
	_build_screen()
	if has_knob:
		_build_knob()
	_build_tick()
	_redraw()

# ---------- build ----------

func _build_body() -> void:
	var k := CockpitKit.new()
	var bw := SCREEN_W + 2.0 * BEZEL_BORDER
	var bh := SCREEN_H + 2.0 * BEZEL_BORDER
	k.box(Vector3(bw, bh, BEZEL_DEPTH), Vector3(0.0, 0.0, -BEZEL_DEPTH * 0.5 - 0.0005), BEZEL)
	if style.aftermarket:
		# printed bezel: faint layer lines across the top and bottom borders
		for i in 4:
			var dy := SCREEN_H * 0.5 + BEZEL_BORDER * (0.2 + 0.2 * i)
			for s in [-1.0, 1.0]:
				k.box(Vector3(bw - 0.002, 0.0008, 0.0006), Vector3(0.0, s * dy, 0.0001), BEZEL_LINE)
		# the mounting plate the tablet is screwed to, a little wider than the bezel
		var plate_w := bw + (2.0 * KNOB_R + 0.03 if has_knob else 0.012)
		var plate_x := -(KNOB_R + 0.015) if has_knob else 0.0
		k.box(Vector3(plate_w, bh + 0.008, 0.004), Vector3(plate_x, 0.0, -BEZEL_DEPTH - 0.002), BEZEL_LINE)
	add_child(k.instance(CockpitKit.material(0.55, 0.0, 0.25), "Bezel"))

func _build_screen() -> void:
	viewport = SubViewport.new()
	viewport.name = "ScreenViewport"
	viewport.size = PX
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	canvas = ScreenCanvas.new()
	canvas.unit = self
	canvas.size = Vector2(PX)
	viewport.add_child(canvas)
	clock_canvas = ClockCanvas.new()
	clock_canvas.unit = self
	clock_canvas.size = Vector2(PX)
	viewport.add_child(clock_canvas)
	add_child(viewport)
	var quad := QuadMesh.new()
	quad.size = Vector2(SCREEN_W, SCREEN_H)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	var b: float = style.brightness
	mat.albedo_color = Color(b, b, b)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	screen = MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = quad
	screen.material_override = mat
	screen.position = Vector3(0.0, 0.0, 0.0004)
	add_child(screen)

func _build_knob() -> void:
	knob = Node3D.new()
	knob.name = "Knob"
	knob.position = _knob_base()
	var k := CockpitKit.new()
	var face := Basis(Vector3.RIGHT, PI / 2.0)   # cylinder axis (y) along +z
	k.cylinder(KNOB_R + 0.003, 0.0, 0.004, Vector3.ZERO, BEZEL_LINE, 12, face)          # collar
	k.cylinder(KNOB_R, 0.0, KNOB_DEPTH, Vector3.ZERO, SILVER.darkened(0.35), 12, face)   # knurled grip
	k.cylinder(KNOB_R - 0.003, KNOB_DEPTH, KNOB_DEPTH + 0.001, Vector3.ZERO, KNOB_DARK, 12, face)
	k.box(Vector3(0.002, 0.007, 0.001), Vector3(0.0, KNOB_R - 0.006, KNOB_DEPTH + 0.0012), SODIUM)   # pointer
	knob.add_child(k.instance(CockpitKit.material(0.35, 0.6, 0.4), "KnobMesh"))
	add_child(knob)

## Knob centre at rest, node space: beside the screen on the driver's side (-x).
func _knob_base() -> Vector3:
	return Vector3(-SCREEN_W * 0.5 - BEZEL_BORDER - KNOB_R - 0.010, -SCREEN_H * 0.5 + KNOB_R + 0.004, -BEZEL_DEPTH)

## A short synthesized tick for a tap: a few cycles of a decaying 2.4 kHz click.
func _build_tick() -> void:
	var rate := 22050
	var n := int(TICK_SECS * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 220.0)
		var v := (sin(TAU * 2400.0 * t) * 0.7 + sin(TAU * 5100.0 * t) * 0.3) * env * 0.5
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	_tick = AudioStreamPlayer.new()
	_tick.name = "TapTick"
	_tick.stream = wav
	_tick.volume_db = -14.0
	_tick.bus = &"UI" if AudioServer.get_bus_index(&"UI") >= 0 else &"Master"
	add_child(_tick)

# ---------- touch points (node space; CockpitFrame maps them to car space) ----------

## Centre of tile i on the glass.
func tile_point(i: int) -> Vector3:
	var r := tile_rect(i)
	return _px_to_local(r.get_center())

## Where the finger presses for "off": the knob's face, or the power spot.
func off_point() -> Vector3:
	if has_knob:
		return _knob_base() + Vector3(0.0, 0.0, KNOB_DEPTH)
	return _px_to_local(POWER_SPOT)

static func tile_rect(i: int) -> Rect2:
	var n := RadioStations.station_count()
	var w := (PX.x - 2.0 * MARGIN - TILE_GAP * (n - 1)) / n
	return Rect2(MARGIN + i * (w + TILE_GAP), TILE_Y, w, TILE_H)

static func _px_to_local(p: Vector2) -> Vector3:
	return Vector3((p.x / PX.x - 0.5) * SCREEN_W, (0.5 - p.y / PX.y) * SCREEN_H, 0.0)

# ---------- state ----------

## Called every frame by the frame with the radio's state; redraws on change.
func show_state(s: int, track: String, lvl: float, delta: float) -> void:
	_meter_t -= delta
	var changed := s != station or track != now_playing
	if area_t > 0.0:
		area_t = maxf(area_t - delta, 0.0)
		if area_t == 0.0:
			changed = true   # the banner is over: back to the radio
	station = s
	now_playing = track
	if s >= 0 and _meter_t <= 0.0:
		_meter_t = 1.0 / METER_HZ
		level = lvl
		changed = true
	if changed:
		_redraw()
	if knob != null and _knob_t > 0.0:
		_knob_t = maxf(_knob_t - delta, 0.0)
		knob.position = _knob_base() - Vector3(0.0, 0.0, KNOB_PRESS * sin(_knob_t / 0.15 * PI))

## The car clock (NightClock text), top right of the screen; redraws on change.
func show_clock(t: String) -> void:
	if t != clock_text:
		clock_text = t
		if clock_canvas != null:
			clock_canvas.queue_redraw()
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## The car crossed into an area: its name takes the header for AREA_SECS
## (world step 4; the name comes from PlaceNames). Shows with the radio off too.
func show_area(area: String) -> void:
	area_name = area
	area_t = AREA_SECS
	_redraw()

## The finger touched the unit: tick, and push the knob in for an off press.
func tap(on_knob: bool) -> void:
	taps += 1
	if on_knob:
		knob_presses += 1
		_knob_t = 0.15
	if _tick != null and _tick.is_inside_tree():
		_tick.play()

func is_dimmed() -> bool:
	return station < 0

func _redraw() -> void:
	if canvas == null:
		return
	canvas.modulate = OFF_DIM if station < 0 else Color.WHITE
	canvas.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## The clock, on its own layer so the radio-off dimming (ScreenCanvas.modulate)
## leaves it lit. Big enough to read from the seat: 32 px on a 512 px screen
## is 13 mm tall on the 216 mm glass.
class ClockCanvas extends Control:
	var unit: HeadUnit

	func _draw() -> void:
		if unit.clock_text == "":
			return
		var font := UiTheme.font("lcd")
		draw_rect(Rect2(340, 6, 164, 46), HeadUnit.NAVY_DEEP)
		draw_string(font, Vector2(350, 41), unit.clock_text, HORIZONTAL_ALIGNMENT_RIGHT, 150, 32, HeadUnit.AMBER)

## The screen's contents.
class ScreenCanvas extends Control:
	var unit: HeadUnit

	func _draw() -> void:
		var font := UiTheme.font("menu_strong")
		var w := float(HeadUnit.PX.x)
		var h := float(HeadUnit.PX.y)
		draw_rect(Rect2(0, 0, w, h), HeadUnit.NAVY_DEEP)
		# header: now playing on the left, level meter on the right
		var on := unit.station >= 0
		draw_string(font, Vector2(HeadUnit.MARGIN, 34), "NOW PLAYING", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HeadUnit.SILVER.darkened(0.25))
		var title := "RADIO OFF"
		var sub := "press the knob to turn on" if unit.has_knob else ""
		if on:
			title = RadioStations.STATIONS[unit.station].name.to_upper()
			sub = unit.now_playing.replace("_", " ") if unit.now_playing != "" else ("ON AIR" if not RadioStations.has_music(unit.station) else "TUNING")
		if unit.area_t > 0.0:
			# the area just entered, in place of the radio's header
			draw_rect(Rect2(HeadUnit.MARGIN - 8, 12, 344, 80), HeadUnit.NAVY)
			draw_rect(Rect2(HeadUnit.MARGIN - 8, 12, 5, 80), HeadUnit.SODIUM)
			draw_string(font, Vector2(HeadUnit.MARGIN + 6, 34), HeadUnit.PlaceNames.ENTERING, HORIZONTAL_ALIGNMENT_LEFT, 320, 14, HeadUnit.SILVER.darkened(0.25))
			draw_string(font, Vector2(HeadUnit.MARGIN + 6, 78), unit.area_name, HORIZONTAL_ALIGNMENT_LEFT, 320, 38, HeadUnit.SODIUM)
		else:
			draw_string(font, Vector2(HeadUnit.MARGIN, 66), title, HORIZONTAL_ALIGNMENT_LEFT, 330, 26, HeadUnit.AMBER)
			if not on:
				sub = ""
			draw_string(font, Vector2(HeadUnit.MARGIN, 92), sub, HORIZONTAL_ALIGNMENT_LEFT, 330, 15, HeadUnit.SILVER)
		# the clock is drawn by ClockCanvas, over this; the meter sits under it
		var bars := 10
		for i in bars:
			var x := 372.0 + i * 12.0
			var lit := on and float(i) / bars < unit.level
			var col := (HeadUnit.SODIUM if i >= 7 else HeadUnit.AMBER) if lit else HeadUnit.NAVY
			draw_rect(Rect2(x, 64, 8, 30), col)
		if not unit.has_knob:
			draw_circle(HeadUnit.POWER_SPOT, 14.0, HeadUnit.NAVY)
			draw_arc(HeadUnit.POWER_SPOT, 8.0, -PI * 0.35, PI * 1.35, 16, HeadUnit.SILVER, 2.0)
			draw_line(HeadUnit.POWER_SPOT - Vector2(0, 11), HeadUnit.POWER_SPOT - Vector2(0, 3), HeadUnit.SILVER, 2.0)
		# tiles
		for i in RadioStations.station_count():
			var r := HeadUnit.tile_rect(i)
			var playing := i == unit.station
			draw_rect(r, HeadUnit.NAVY)
			_art(r, i)
			var name_s: String = RadioStations.STATIONS[i].name.to_upper()
			draw_multiline_string(font, Vector2(r.position.x + 6, r.position.y + r.size.y - 44), name_s,
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 12, 15, 2, HeadUnit.AMBER if playing else HeadUnit.SILVER)
			if playing:
				draw_rect(r.grow(-2.0), HeadUnit.SODIUM, false, 4.0)
		# a little glare across the glass, and a thumb smudge where it gets tapped
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.55, 0), Vector2(w * 0.72, 0), Vector2(w * 0.40, h), Vector2(w * 0.23, h)]), Color(1, 1, 1, 0.035))
		draw_circle(Vector2(w * 0.62, h * 0.62), 22.0, Color(1, 1, 1, 0.025))

	## Track art generated from the palette, one motif per station.
	func _art(r: Rect2, i: int) -> void:
		var a := Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, r.size.y - 70))
		draw_rect(a, HeadUnit.NAVY_DEEP)
		var c := a.get_center()
		match i % 4:
			0:   # drift: three slanted streaks
				for k in 3:
					var y := a.position.y + a.size.y * (0.3 + 0.2 * k)
					draw_line(Vector2(a.position.x + 8, y + 10), Vector2(a.end.x - 8, y - 10), HeadUnit.SODIUM if k == 1 else HeadUnit.AMBER.darkened(0.3), 4.0)
			1:   # dark: a low sodium moon behind a skyline
				draw_circle(c + Vector2(0, -6), a.size.y * 0.28, HeadUnit.SODIUM.darkened(0.45))
				for k in 5:
					var bw := a.size.x / 5.0
					var bh := a.size.y * (0.25 + 0.12 * ((k * 7) % 3))
					draw_rect(Rect2(a.position.x + k * bw, a.end.y - bh, bw - 2, bh), HeadUnit.NAVY)
			2:   # talk: a microphone
				draw_rect(Rect2(c.x - 8, c.y - 26, 16, 30), HeadUnit.SILVER.darkened(0.2))
				draw_arc(c + Vector2(0, -4), 15.0, 0.0, PI, 10, HeadUnit.SILVER.darkened(0.2), 2.0)
				draw_line(c + Vector2(0, 11), c + Vector2(0, 24), HeadUnit.SILVER.darkened(0.2), 2.0)
			3:   # synthwave: a striped sun over a horizon grid
				draw_circle(c + Vector2(0, -4), a.size.y * 0.3, HeadUnit.AMBER)
				for k in 3:
					draw_rect(Rect2(c.x - a.size.y * 0.3, c.y + 2 + 6 * k, a.size.y * 0.6, 2), HeadUnit.NAVY_DEEP)
				for k in 4:
					var y := c.y + a.size.y * 0.18 + k * 5
					draw_line(Vector2(a.position.x, y), Vector2(a.end.x, y), HeadUnit.SODIUM.darkened(0.3), 1.0)
