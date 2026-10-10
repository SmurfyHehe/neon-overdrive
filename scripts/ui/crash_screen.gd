extends CanvasLayer

# The crash screen (ending a run, 2026-10-10): what the player sees and hears
# when a hard hit ends the run. All from the driver's own seat:
#
#   crack()  the windscreen cracks and the ears ring (the camera shake is the
#            chase camera's own trauma, set by run_end.gd)
#   black()  hard cut to black, with the tail of a scrape still sounding
#   say()    Dave's line on the black
#   card()   the morning card (who picked you up, what it cost)
#
# No slow motion and no outside view: nothing here moves a camera or touches
# the time scale. The layer sits above every other screen in the game.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const LAYER := 50
const SILVER := Color(0.82, 0.85, 0.9)
const AMBER := Color(1.0, 0.75, 0.4)      # #FFC066
const SODIUM := Color(1.0, 0.54, 0.12)    # #FF8A1F

const RING_SECS := 2.6
const RING_HZ := 3400.0
const RING_RATE := 22050
const SCRAPE_TAIL_SECS := 1.4
const SCRAPE_LAYER := "loop_metal0"
const SFX_BUS := &"UI"

# The cracks: drawn lines, no texture.
class Glass extends Control:
	var origin := Vector2(0.36, 0.42)  # where the hit landed, as a share of the screen
	var seed_value := 1

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var centre := origin * size
		var reach := size.length()
		var spokes := 13
		var ends: Array[PackedVector2Array] = []
		for s in spokes:
			var angle := TAU * (s + rng.randf_range(-0.3, 0.3)) / spokes
			var pts := PackedVector2Array([centre])
			var r := 0.0
			var length := reach * rng.randf_range(0.35, 0.95)
			while r < length:
				r += reach * rng.randf_range(0.03, 0.08)
				angle += rng.randf_range(-0.16, 0.16)
				pts.append(centre + Vector2.from_angle(angle) * r)
			ends.append(pts)
			draw_polyline(pts, Color(SILVER, 0.75), 2.0, true)
			draw_polyline(pts, Color(1, 1, 1, 0.35), 1.0, true)
		# Rings: short straight pieces between neighbouring spokes.
		for ring in 4:
			var at := 2 + ring * 2
			for s in spokes:
				if rng.randf() < 0.3:
					continue
				var a := ends[s]
				var b := ends[(s + 1) % spokes]
				if at < a.size() and at < b.size():
					draw_line(a[at], b[at], Color(SILVER, 0.5), 1.5, true)
		draw_circle(centre, 9.0, Color(1, 1, 1, 0.5))

var _glass: Glass
var _black: ColorRect
var _line: Label
var _card: VBoxContainer
var _hold: ColorRect
var _ring: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _scrape_left := 0.0

func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_glass = Glass.new()
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.visible = false
	add_child(_glass)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.visible = false
	add_child(_black)
	_line = Label.new()
	_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_line.custom_minimum_size = Vector2(760, 0)
	_line.position = Vector2(-380, -40)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_color_override("font_color", SODIUM)  # Dave's caption colour
	_line.add_theme_font_size_override("font_size", 22)
	_line.visible = false
	add_child(_line)
	_card = VBoxContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.custom_minimum_size = Vector2(760, 0)
	_card.position = Vector2(-380, -120)
	_card.add_theme_constant_override("separation", 14)
	_card.visible = false
	add_child(_card)
	# Fills while S is held on the morning card. No key hint (Controls page).
	_hold = ColorRect.new()
	_hold.color = AMBER
	_hold.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hold.position = Vector2(0, -4)
	_hold.size = Vector2(0, 4)
	_hold.visible = false
	add_child(_hold)
	_ring = AudioStreamPlayer.new()
	_ring.bus = SFX_BUS
	add_child(_ring)
	_scrape = AudioStreamPlayer.new()
	_scrape.bus = SFX_BUS
	add_child(_scrape)

func _process(delta: float) -> void:
	if _scrape_left > 0.0:
		_scrape_left -= delta
		var t := clampf(_scrape_left / SCRAPE_TAIL_SECS, 0.0, 1.0)
		_scrape.volume_db = linear_to_db(maxf(t * t, 0.0001))
		if _scrape_left <= 0.0:
			_scrape.stop()

## The windscreen cracks and the ears ring.
func crack(seed_value: int = 1) -> void:
	_glass.seed_value = seed_value
	_glass.visible = true
	_glass.queue_redraw()
	_ring.stream = ring_stream()
	_ring.play()

## Hard cut to black: no fade. The scrape carries on for a moment and dies.
func black() -> void:
	_glass.visible = false
	_black.visible = true
	_scrape.stream = CrashAudio.stream(SCRAPE_LAYER)
	_scrape.volume_db = 0.0
	_scrape.play()
	_scrape_left = SCRAPE_TAIL_SECS

## Dave's line on the black. "" clears it.
func say(text: String) -> void:
	_line.text = text
	_line.visible = text != ""

## The morning card: a title and its lines, on the black.
func card(title: String, lines: Array) -> void:
	say("")
	for c in _card.get_children():
		c.queue_free()
	_card.add_child(_text(title, 30, AMBER))
	for l in lines:
		_card.add_child(_text(str(l), 20, SILVER))
	_card.visible = true

## How far the hold-to-skip has got, 0..1.
func set_hold(share: float) -> void:
	_hold.visible = share > 0.0
	_hold.size.x = get_viewport().get_visible_rect().size.x * clampf(share, 0.0, 1.0)

func is_cracked() -> bool:
	return _glass.visible

func is_black() -> bool:
	return _black.visible

func line_text() -> String:
	return _line.text if _line.visible else ""

func card_texts() -> Array[String]:
	var out: Array[String] = []
	if _card.visible:
		for c in _card.get_children():
			if c is Label and not c.is_queued_for_deletion():
				out.append((c as Label).text)
	return out

func scrape_playing() -> bool:
	return _scrape.playing

func _text(text: String, font_size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(760, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", font_size)
	return l

## The ear ring: two close high tones beating against each other, dying away.
static var _ring_stream: AudioStreamWAV
static func ring_stream() -> AudioStreamWAV:
	if _ring_stream == null:
		var n := int(RING_SECS * RING_RATE)
		var data := PackedByteArray()
		data.resize(n * 2)
		for i in n:
			var t := float(i) / RING_RATE
			var env := minf(t / 0.02, 1.0) * exp(-t * 1.7)
			var v := (sin(TAU * RING_HZ * t) * 0.6 + sin(TAU * (RING_HZ + 37.0) * t) * 0.4) * env * 0.35
			data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
		_ring_stream = AudioStreamWAV.new()
		_ring_stream.format = AudioStreamWAV.FORMAT_16_BITS
		_ring_stream.mix_rate = RING_RATE
		_ring_stream.stereo = false
		_ring_stream.data = data
	return _ring_stream
