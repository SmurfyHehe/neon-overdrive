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
# The screen: a ring of station cards (centre card framed in sodium, neighbours
# smaller and dimmer; at rest the song title and artist under it), a small
# three-bar level meter. Navy, sodium, amber and silver; no
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
##   brightness: screen gain (>1: the cheap tablet is a touch too bright; capped
##   at 1.1, more bloomed the amber text)
const STYLES := {
	"p1_coupe": {"aftermarket": true, "knob": true, "brightness": 1.1},
	"test": {"aftermarket": false, "knob": false, "brightness": 1.0},
}
const DEFAULT_STYLE := "p1_coupe"

## The ring of station cards (R2, 2026-10-11), screen pixels. The top strip
## (y 0-56) keeps the clock, weather, level meter and the area banner.
const MARGIN := 18.0
const STRIP_H := 56.0
const CARD_MOVING := Vector2(184, 214)   # centre card while the ring is in use
const CARD_REST := Vector2(150, 170)     # shrunk, 4 s after the last change
const CARD_CENTRE_Y := 171.0             # moving card's middle
const CARD_REST_Y := 148.0
const REST_AFTER := 4.0                  # s of quiet before the side cards fade
const REST_FADE := 0.4
const SONG_FADE := 0.1
const NEAR_SCALE := 0.62
## Ring anchors by |distance| from the centre: x offset, scale, brightness.
## Two cards out is dark, so nothing is ever cut by the glass edge (look pass,
## 2026-10-11); a card that still crosses MARGIN fades over EDGE_FADE px, so
## a longer dial (Breakline, the hidden 87.9) needs no new numbers.
const RING_X := [0.0, 160.0, 210.0, 290.0]
const RING_SCALE := [1.0, 0.62, 0.5, 0.5]
const RING_BRIGHT := [1.0, 0.55, 0.0, 0.0]
const EDGE_FADE := 24.0
const LINE_MAX_W := 470.0
## Text sizes, screen px: 1 px is 0.42 mm on the 216 mm glass, so 36 px is
## 15 mm tall, which reads from the seat at 1280x720 (about 17 px on screen)
## and 1920x1080 (25 px). The resting card scales its text half as much as
## its box (TEXT_SHRINK), so the name stays readable when the song lines are up.
const NAME_SIZE := 36
const DIAL_SIZE := 32
const SIDE_DIAL_SIZE := 26
const SIDE_NAME_SIZE := 19
const SONG_SIZE := 30
const ARTIST_SIZE := 25
const TEXT_SHRINK := 0.5
## The clock: DSEG7 has no M, so the time is LCD and the AM/PM suffix is set
## in the menu font beside it (Roy, 2026-10-11: it showed "P").
const CLOCK_SIZE := 30
const AMPM_FONT := "menu_strong"
const AMPM_SIZE := 22
const POWER_SPOT := Vector2(322, 40)   # touch-only units: tap here for off (left of the clock)

var style: Dictionary
var has_knob := false
var station := -1
var now_playing := ""
var level := 0.0
var clock_text := ""     # the car clock, drawn top right (NightClock)
var area_name := ""      # the area just entered, shown for AREA_SECS (world step 4)
var area_t := 0.0
var weather_level := 0   # Weather.Level: 1 rain, 2 storm get an icon, else none
## The ring: ring_pos is the card in the middle (in card units, it keeps
## counting up and wraps), animating is true while anything moves (the
## viewport then renders every frame, else once).
var ring_pos := 0.0
var ring_target := 0
var rest := 0.0          # 0 in use .. 1 at rest (side cards gone, song lines up)
var card_station := RadioStations.DEFAULT_STATION
var lit := false
var band := -1
var animating := false
var ring_slides := 0     # slides started (tests)
var _ring_from := 0.0
var _ring_t := 0.0
var _ring_dur := 0.0
var _quiet := 0.0
var _slides_seen := 0
var _first_ring := true
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

## Where the finger lands for a station change: the middle of the glass.
func centre_point() -> Vector3:
	return _px_to_local(Vector2(PX.x * 0.5, CARD_CENTRE_Y))

## Where the finger presses for "off": the knob's face, or the power spot.
func off_point() -> Vector3:
	if has_knob:
		return _knob_base() + Vector3(0.0, 0.0, KNOB_DEPTH)
	return _px_to_local(POWER_SPOT)

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

## The ring, every frame: the card to rest on, how many slides the radio has
## started and how long each takes, whether the radio is lit and the night band
## (Dave's segment). Drives the slide and the rest fade; the viewport renders
## every frame only while something moves.
func show_ring(card: int, slides: int, slide_secs: float, delta: float, is_lit: bool, night_band := -1) -> void:
	var n := RadioStations.station_count()
	var changed := false
	if _first_ring:
		_first_ring = false
		ring_target = card
		ring_pos = float(card)
		_ring_from = ring_pos
		changed = true
	if slides != _slides_seen:
		ring_target += maxi(slides - _slides_seen, 1)
		_slides_seen = slides
		ring_slides += 1
		_ring_from = ring_pos
		_ring_dur = maxf(slide_secs, 0.01)
		_ring_t = 0.0
		_quiet = 0.0
		changed = true
	if posmod(ring_target, n) != card:   # a jump (power on, a restore): no slide
		ring_target = card
		ring_pos = float(card)
		_ring_from = ring_pos
		_ring_t = _ring_dur
		_quiet = 0.0
		changed = true
	if is_lit != lit or card != card_station or night_band != band:
		changed = true
		if is_lit != lit:
			_quiet = 0.0
	lit = is_lit
	card_station = card
	band = night_band
	var moving := _ring_t < _ring_dur
	if moving:
		_ring_t = minf(_ring_t + delta, _ring_dur)
		var k := _ring_t / _ring_dur
		ring_pos = lerpf(_ring_from, float(ring_target), 1.0 - pow(1.0 - k, 3.0))   # ease-out cubic
		changed = true
	else:
		ring_pos = float(ring_target)
	# rest: 4 s after the last change the side cards fade out (0.4 s) and the
	# centre card shrinks; any change brings it back in SONG_FADE
	var want := 0.0
	if lit and not moving:
		_quiet += delta
		if _quiet >= REST_AFTER:
			want = 1.0
	else:
		_quiet = 0.0
	var step := delta / (REST_FADE if want > rest else SONG_FADE)
	var before := rest
	rest = move_toward(rest, want, step)
	if rest != before:
		changed = true
	var anim := _ring_t < _ring_dur or rest != want
	if anim != animating:
		animating = anim
		changed = true
	if changed:
		_redraw()

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

## Rain (1) or storm (2) icon beside the clock; anything else draws nothing.
func show_weather(level: int) -> void:
	var l := level if level == 1 or level == 2 else 0
	if l != weather_level:
		weather_level = l
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

## The ring's centre card, ring_pos rounded: which station it shows.
func centre_card() -> int:
	return posmod(roundi(ring_pos), RadioStations.station_count())

func _redraw() -> void:
	if canvas == null:
		return
	canvas.modulate = OFF_DIM if station < 0 else Color.WHITE
	canvas.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if animating else SubViewport.UPDATE_ONCE

## The clock text split into the time and its AM/PM suffix ("11:01 PM" ->
## ["11:01", "PM"]); no suffix gives "".
static func clock_parts(t: String) -> Array:
	var sp := t.rfind(" ")
	if sp < 0:
		return [t, ""]
	return [t.substr(0, sp), t.substr(sp + 1)]

## The clock, on its own layer so the radio-off dimming (ScreenCanvas.modulate)
## leaves it lit. Big enough to read from the seat: 30 px on a 512 px screen
## is 13 mm tall on the 216 mm glass; the AM/PM suffix sits beside it in the
## menu font (the LCD font cannot draw an M).
class ClockCanvas extends Control:
	var unit: HeadUnit

	func _draw() -> void:
		if unit.clock_text == "":
			return
		var parts := HeadUnit.clock_parts(unit.clock_text)
		draw_rect(Rect2(340, 6, 164, 46), HeadUnit.NAVY_DEEP)
		var right := 500.0
		if parts[1] != "":
			var small := UiTheme.font(HeadUnit.AMPM_FONT)
			var sw := small.get_string_size(parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, HeadUnit.AMPM_SIZE).x
			draw_string(small, Vector2(right - sw, 41), parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, HeadUnit.AMPM_SIZE, HeadUnit.AMBER)
			right -= sw + 6.0
		draw_string(UiTheme.font("lcd"), Vector2(344, 41), parts[0], HORIZONTAL_ALIGNMENT_RIGHT, right - 344.0, HeadUnit.CLOCK_SIZE, HeadUnit.AMBER)

## The screen's contents.
class ScreenCanvas extends Control:
	var unit: HeadUnit

	## A small cloud with falling drops (rain) or a bolt (storm), left of the
	## clock, in the head unit's own silver and amber.
	func _draw_weather(l: int) -> void:
		var c := Vector2(352, 26)
		var cloud := HeadUnit.SILVER
		draw_circle(c + Vector2(-6, 2), 5.0, cloud)
		draw_circle(c + Vector2(1, -2), 6.5, cloud)
		draw_circle(c + Vector2(8, 2), 5.0, cloud)
		draw_rect(Rect2(c + Vector2(-6, 2), Vector2(14, 5)), cloud)
		if l == 2:
			draw_polyline(PackedVector2Array([c + Vector2(3, 6), c + Vector2(-1, 12), c + Vector2(3, 12), c + Vector2(-1, 18)]), HeadUnit.AMBER, 2.0)
		else:
			for dx in [-4.0, 1.0, 6.0]:
				draw_line(c + Vector2(dx, 9), c + Vector2(dx - 2, 15), HeadUnit.AMBER, 1.5)

	func _draw() -> void:
		var font := UiTheme.font("menu_strong")
		var w := float(HeadUnit.PX.x)
		var h := float(HeadUnit.PX.y)
		draw_rect(Rect2(0, 0, w, h), HeadUnit.NAVY_DEEP)
		var on := unit.station >= 0
		# top strip: the area just entered takes the left
		if unit.area_t > 0.0:
			draw_rect(Rect2(10, 6, 250, 48), HeadUnit.NAVY)
			draw_rect(Rect2(10, 6, 5, 48), HeadUnit.SODIUM)
			draw_string(font, Vector2(22, 22), HeadUnit.PlaceNames.ENTERING, HORIZONTAL_ALIGNMENT_LEFT, 230, 12, HeadUnit.SILVER.darkened(0.25))
			draw_string(font, Vector2(22, 48), unit.area_name, HORIZONTAL_ALIGNMENT_LEFT, 230, _fit(font, unit.area_name, 230.0, 26), HeadUnit.SODIUM)
		if unit.weather_level > 0:
			_draw_weather(unit.weather_level)
		# the clock is drawn by ClockCanvas, over this; three short level bars sit beside it
		for i in 3:
			var bar_on := on and unit.level > (float(i) + 0.5) / 3.5
			var bh := 10.0 + 8.0 * i
			draw_rect(Rect2(272 + i * 11, 46.0 - bh, 7, bh), (HeadUnit.SODIUM if i == 2 else HeadUnit.AMBER) if bar_on else HeadUnit.NAVY)
		if not unit.has_knob:
			draw_circle(HeadUnit.POWER_SPOT, 14.0, HeadUnit.NAVY)
			draw_arc(HeadUnit.POWER_SPOT, 8.0, -PI * 0.35, PI * 1.35, 16, HeadUnit.SILVER, 2.0)
			draw_line(HeadUnit.POWER_SPOT - Vector2(0, 11), HeadUnit.POWER_SPOT - Vector2(0, 3), HeadUnit.SILVER, 2.0)
		# the ring: far cards first, the centre card on top
		var n := RadioStations.station_count()
		var order: Array = []
		for i in n:
			var d := fposmod(float(i) - unit.ring_pos + n * 0.5, float(n)) - n * 0.5
			order.append([absf(d), d, i])
		order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var rest := unit.rest
		for o in order:
			_card(font, o[1], o[2], rest, on)
		# at rest: song title and artist (or Dave's segment) under the card
		if rest > 0.01 and on:
			var lines := _song_lines()
			var cy := lerpf(HeadUnit.CARD_CENTRE_Y, HeadUnit.CARD_REST_Y, rest)
			var base := cy + lerpf(HeadUnit.CARD_MOVING.y, HeadUnit.CARD_REST.y, rest) * 0.5
			var t1 := _ellipsize(font, lines[0], HeadUnit.SONG_SIZE, HeadUnit.LINE_MAX_W)
			var t2 := _ellipsize(font, lines[1], HeadUnit.ARTIST_SIZE, HeadUnit.LINE_MAX_W)
			draw_string(font, Vector2(0, base + 32), t1, HORIZONTAL_ALIGNMENT_CENTER, w, HeadUnit.SONG_SIZE, _dim(HeadUnit.AMBER, rest))
			draw_string(font, Vector2(0, base + 60), t2, HORIZONTAL_ALIGNMENT_CENTER, w, HeadUnit.ARTIST_SIZE, _dim(HeadUnit.SILVER, rest))
		# a little glare across the glass, and a thumb smudge where it gets tapped
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.55, 0), Vector2(w * 0.72, 0), Vector2(w * 0.40, h), Vector2(w * 0.23, h)]), Color(1, 1, 1, 0.035))
		draw_circle(Vector2(w * 0.62, h * 0.62), 22.0, Color(1, 1, 1, 0.025))

	## Title and artist for the lines under the resting card.
	func _song_lines() -> Array:
		if not RadioStations.has_music(unit.station):
			var seg := NightBands.band_name(unit.band) if unit.band >= 0 else "On air"
			return ["with Dave", seg]
		if unit.now_playing == "":
			return ["Tuning", RadioStations.STATIONS[unit.station].name]
		var info := RadioStations.song_info(unit.station, unit.now_playing)
		return [info.title, info.artist]

	static func _fit(font: Font, text: String, max_w: float, size: int) -> int:
		while size > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			size -= 1
		return size

	static func _ellipsize(font: Font, text: String, size: int, max_w: float) -> String:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			return text
		var t := text
		while t.length() > 1 and font.get_string_size(t + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			t = t.substr(0, t.length() - 1)
		return t.strip_edges() + "..."

	static func _lerp_anchors(arr: Array, d: float) -> float:
		var i := clampi(int(floor(d)), 0, arr.size() - 2)
		return lerpf(float(arr[i]), float(arr[i + 1]), clampf(d - float(i), 0.0, 1.0))

	static func _dim(col: Color, b: float) -> Color:
		return HeadUnit.NAVY_DEEP.lerp(col, clampf(b, 0.0, 1.0))

	## One card of the ring: d = its distance from the centre (signed cards).
	func _card(font: Font, d: float, idx: int, rest: float, on: bool) -> void:
		var ad := absf(d)
		var near := _lerp_anchors(HeadUnit.RING_SCALE, ad)
		var bright := _lerp_anchors(HeadUnit.RING_BRIGHT, ad)
		# at rest the side cards fade out; the middle one shrinks and moves up
		var centre_w := clampf(1.0 - ad, 0.0, 1.0)   # 1 on the centre card, 0 a card away
		var cs := HeadUnit.CARD_MOVING.lerp(HeadUnit.CARD_REST, rest)
		var cy := lerpf(HeadUnit.CARD_CENTRE_Y, HeadUnit.CARD_REST_Y, rest)
		var size := (HeadUnit.CARD_MOVING * near).lerp(cs, centre_w)
		bright = lerpf(bright * (1.0 - rest), 1.0, centre_w)
		if bright <= 0.01:
			return
		var x := 256.0 + signf(d) * _lerp_anchors(HeadUnit.RING_X, ad)
		var c := Vector2(x, lerpf(HeadUnit.CARD_CENTRE_Y, cy, centre_w))
		var r := Rect2(c - size * 0.5, size)
		# a card crossing the glass margin fades out rather than being cut
		var edge := minf(r.position.x - HeadUnit.MARGIN, float(HeadUnit.PX.x) - HeadUnit.MARGIN - r.end.x)
		if edge < 0.0:
			bright *= clampf(1.0 + edge / HeadUnit.EDGE_FADE, 0.0, 1.0)
			if bright <= 0.01:
				return
		var k := size.y / HeadUnit.CARD_MOVING.y
		var kt := lerpf(1.0, k, HeadUnit.TEXT_SHRINK)   # text shrinks less than the box
		var st: Dictionary = RadioStations.STATIONS[idx]
		draw_rect(r, _dim(HeadUnit.NAVY, bright))
		var is_centre := ad < 0.5
		if ad < 1.0:
			var art_b := bright * clampf(1.0 - ad * 1.6, 0.0, 1.0)
			if art_b > 0.02:
				_art(Rect2(r.position + Vector2(10, 10) * k, Vector2(r.size.x - 20.0 * k, 96.0 * k)), st.id, art_b)
		var name_s: String = str(st.name) if (on or not is_centre) else "OFF"
		if not is_centre:
			# side cards: the dial number big (it is short and reads from the
			# seat), the name under it
			var lcd_s := UiTheme.font("lcd")
			draw_string(lcd_s, Vector2(r.position.x, c.y - 2.0), str(st.dial), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, HeadUnit.SIDE_DIAL_SIZE, _dim(HeadUnit.SILVER, bright))
			var nsz := maxi(_fit(font, name_s, r.size.x - 10.0, HeadUnit.SIDE_NAME_SIZE), 14)
			var side_s := _ellipsize(font, name_s, nsz, r.size.x - 10.0)
			draw_string(font, Vector2(r.position.x, c.y + 22.0), side_s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, nsz, _dim(HeadUnit.SILVER.darkened(0.15), bright))
		else:
			var ncol := _dim(HeadUnit.AMBER if on else HeadUnit.SILVER, bright)
			var nsz2 := _fit(font, name_s, r.size.x - 12.0, int(round(HeadUnit.NAME_SIZE * kt)))
			draw_string(font, Vector2(r.position.x, r.position.y + 148.0 * k), name_s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, nsz2, ncol)
			if on:
				var lcd := UiTheme.font("lcd")
				draw_string(lcd, Vector2(r.position.x, r.position.y + 194.0 * k), str(st.dial), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(round(HeadUnit.DIAL_SIZE * kt)), _dim(HeadUnit.SODIUM, bright))
			draw_rect(r.grow(-2.0), _dim(HeadUnit.SODIUM, bright), false, 4.0)

	static func _uv(a: Rect2, u: float, v: float) -> Vector2:
		return a.position + Vector2(u * a.size.x, v * a.size.y)

	## Card art drawn from the palette, one motif per station, sized to the
	## art box (164x96 on the moving card) so it still reads at 80 px on the
	## glass from the seat: Slipstream streaks, Undertow a low moon over water,
	## Afterglow a striped sun over street lamps, Grey Hour wipers on wet
	## glass, Graveyard Radio a microphone. Anything else on the dial
	## (Breakline 94.1, the hidden 87.9) gets a tuning scale until it has art.
	func _art(a: Rect2, id: String, b: float) -> void:
		draw_rect(a, HeadUnit.NAVY_DEEP)
		var s := a.size.y / 96.0   # line weights follow the box
		var amb := _dim(HeadUnit.AMBER, b)
		var sod := _dim(HeadUnit.SODIUM, b)
		var sil := _dim(HeadUnit.SILVER.darkened(0.15), b)
		var nav := _dim(HeadUnit.NAVY, b)
		match id:
			"slipstream":   # drift: three speed streaks, thick at the head, tailing off left
				for k in 3:
					var y0 := 0.34 + 0.2 * k
					var y1 := y0 - 0.2
					var th := (0.055 if k == 1 else 0.04)
					var col := sod if k == 1 else amb.darkened(0.3)
					draw_colored_polygon(PackedVector2Array([_uv(a, 0.06, y0), _uv(a, 0.94, y1 - th), _uv(a, 0.94, y1 + th)]), col)
				draw_line(_uv(a, 0.06, 0.9), _uv(a, 0.94, 0.9), nav.lightened(0.15), 2.0 * s)
			"undertow":   # dark: a low moon half set in black water, its reflection broken up
				draw_circle(_uv(a, 0.5, 0.5), a.size.y * 0.3, sod.darkened(0.25))
				draw_rect(Rect2(_uv(a, 0.0, 0.56), Vector2(a.size.x, a.size.y * 0.44)), nav.darkened(0.35))
				draw_line(_uv(a, 0.0, 0.56), _uv(a, 1.0, 0.56), sil.darkened(0.3), 1.5 * s)
				for k in 5:
					var v := 0.63 + 0.08 * k
					var half := 0.24 - 0.035 * k
					var jig := 0.025 * (1 if k % 2 == 0 else -1)
					draw_line(_uv(a, 0.5 + jig - half, v), _uv(a, 0.5 + jig + half, v), sod.darkened(0.45 + 0.08 * k), 2.5 * s)
			"graveyard":   # talk: a stand microphone, a live light beside it
				var head := _uv(a, 0.5, 0.3)
				var hr := a.size.y * 0.17
				draw_circle(head, hr, sil)
				draw_rect(Rect2(head - Vector2(hr, 0.0), Vector2(hr * 2.0, a.size.y * 0.2)), sil)
				for k in 3:
					var gy := head.y - hr * 0.5 + k * hr * 0.5
					draw_line(Vector2(head.x - hr * 0.8, gy), Vector2(head.x + hr * 0.8, gy), HeadUnit.NAVY_DEEP, 1.5 * s)
				draw_arc(_uv(a, 0.5, 0.5), a.size.y * 0.26, 0.0, PI, 12, sil, 2.5 * s)
				draw_line(_uv(a, 0.5, 0.76), _uv(a, 0.5, 0.94), sil, 2.5 * s)
				draw_line(_uv(a, 0.36, 0.94), _uv(a, 0.64, 0.94), sil, 3.0 * s)
				draw_circle(_uv(a, 0.84, 0.2), 3.5 * s, sod)
			"afterglow":   # synthwave: a striped sun setting over a row of street lamps
				var sc := _uv(a, 0.5, 0.42)
				var sr := a.size.y * 0.3
				draw_circle(sc, sr, amb)
				for k in 4:
					var gy := sc.y + sr * (0.08 + 0.24 * k)
					draw_rect(Rect2(sc.x - sr, gy, sr * 2.0, (1.5 + k) * s), HeadUnit.NAVY_DEEP)
				draw_rect(Rect2(_uv(a, 0.0, 0.70), Vector2(a.size.x, a.size.y * 0.3)), HeadUnit.NAVY_DEEP)
				draw_line(_uv(a, 0.0, 0.70), _uv(a, 1.0, 0.70), sod.darkened(0.3), 1.5 * s)
				for u in [0.18, 0.5, 0.82]:
					draw_line(_uv(a, u, 0.98), _uv(a, u, 0.76), sil.darkened(0.2), 2.0 * s)
					draw_rect(Rect2(_uv(a, u, 0.76) - Vector2(5.0 * s, 1.5 * s), Vector2(10.0 * s, 3.5 * s)), sod)
					draw_circle(_uv(a, u, 0.76), 6.0 * s, Color(sod, 0.18))
			"greyhour":   # rain: one wiper mid-sweep, the glass wet outside its arc
				draw_rect(a, nav.darkened(0.3))
				var rs := 7
				for k in 34:
					rs = (rs * 1103515245 + 12345) & 0x7fffffff
					var u := float(rs % 1000) / 1000.0
					rs = (rs * 1103515245 + 12345) & 0x7fffffff
					var v := float(rs % 1000) / 1000.0 * 0.96
					var dp := _uv(a, u, v)
					draw_circle(dp, 1.8 * s, amb.darkened(0.4))
					draw_line(dp, dp + Vector2(-1.0, 4.5) * s, amb.darkened(0.55), 1.2 * s)
				# the swept sector is clean glass: pivot under the box, the arc inside it
				var piv := _uv(a, 0.5, 1.1)
				var bl := a.size.y * 0.9
				var pts := PackedVector2Array([piv])
				for k in 11:
					var ang := deg_to_rad(-140.0 + 10.0 * k)
					pts.append(piv + Vector2(cos(ang), sin(ang)) * bl)
				draw_colored_polygon(pts, HeadUnit.NAVY_DEEP)
				draw_arc(piv, bl, deg_to_rad(-140.0), deg_to_rad(-40.0), 14, sil.darkened(0.5), 1.5 * s)
				var tip := piv + Vector2(cos(deg_to_rad(-112.0)), sin(deg_to_rad(-112.0))) * bl
				draw_line(piv, tip, sil, 3.5 * s)
				draw_line(piv + (tip - piv) * 0.45, tip, HeadUnit.NAVY_DEEP, 1.0 * s)
			_:   # no art yet: a tuning scale with the needle on it
				draw_line(_uv(a, 0.1, 0.55), _uv(a, 0.9, 0.55), sil, 2.0 * s)
				for k in 9:
					var u := 0.1 + 0.1 * k
					var tall := k % 4 == 0
					draw_line(_uv(a, u, 0.55), _uv(a, u, 0.55 - (0.16 if tall else 0.08)), sil, 1.5 * s)
				draw_line(_uv(a, 0.62, 0.28), _uv(a, 0.62, 0.8), sod, 3.0 * s)
