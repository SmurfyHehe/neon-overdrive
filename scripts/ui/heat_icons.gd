class_name HeatIcons
extends CanvasLayer

# Police heat on screen (F0): one icon for the current level, drawn in code
# like the RPM bar. It sits at the top, just LEFT of the rear strip's place
# (2026-10-14, Roy: "we need a different place to put the cop warning, it
# blocks out the mirror"): top centre was exactly on the chase view's rear
# strip. Left of centre is clear in every view: the cockpit's rearview glass
# hangs right of centre and its door mirrors are at the far edges, half way
# down. A third bigger than it was, so it still reads at a glance from there. Each level has its own picture, so a glance
# says what is coming, not how many stars: one patrol car, two cars, a
# sawhorse, a spike strip, a helicopter (PoliceHeat.ICONS). No icon at 0 and
# none for bad cops. A new level flashes red/blue for FLASH_SECS.
#
# Also the caption for police lines (night one's warning and jab) when Dave's
# station is not on to say them.

const SILVER := Hud.SILVER
const POLICE_BLUE := Color("#2E4FD8")
const RED := Hud.RED
const DUSK := Hud.DUSK
const ICON_SIZE := Vector2(128, 70)
## Gap between the icon's right edge and the rear strip's frame.
const STRIP_GAP := 16.0
## Top of the icon, level with the rear strip (Hud.STRIP_TOP).
const TOP := 12.0

## Where the icon's top-left sits, relative to the top centre of the screen.
static func icon_offset() -> Vector2:
	return Vector2(-(Hud.STRIP_SIZE.x * 0.5 + Hud.STRIP_BORDER + STRIP_GAP + ICON_SIZE.x), TOP)
const FLASH_SECS := 2.0
const CAPTION_SECS := 7.0

var heat: PoliceHeat
var icon: HeatIcon
var caption: Label
## The bust ring (P5): a bar under the icon that fills while you are nearly
## stopped with a chasing cop beside you. Set by the game from PolicePatrol.
var patrol: PolicePatrol
var bust_bar: ColorRect
var _flash := 0.0
var _caption_t := 0.0

class HeatIcon extends Control:
	var kind := ""
	var flash := false

	func _draw() -> void:
		if kind == "":
			return
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(DUSK, 0.75))
		draw_rect(Rect2(Vector2.ZERO, s), RED if flash else SILVER, false, 2.0)
		match kind:
			"car":
				_car(Vector2(s.x * 0.5, s.y * 0.62), 1.0)
			"two_cars":
				_car(Vector2(s.x * 0.33, s.y * 0.66), 0.72)
				_car(Vector2(s.x * 0.68, s.y * 0.58), 0.72)
			"sawhorse":
				_sawhorse(Vector2(s.x * 0.5, s.y * 0.5))
			"spikes":
				_spikes(Vector2(s.x * 0.5, s.y * 0.6))
			"helicopter":
				_helicopter(Vector2(s.x * 0.5, s.y * 0.55))

	## A sedan from the side with a light bar on the roof.
	func _car(c: Vector2, k: float) -> void:
		var pts := PackedVector2Array([
			Vector2(-30, 6), Vector2(-30, -2), Vector2(-20, -4), Vector2(-11, -13),
			Vector2(11, -13), Vector2(19, -4), Vector2(30, -2), Vector2(30, 6)])
		for i in pts.size():
			pts[i] = c + pts[i] * k
		draw_colored_polygon(pts, SILVER)
		draw_rect(Rect2(c + Vector2(-8, -18) * k, Vector2(8, 4) * k), RED if flash else POLICE_BLUE)
		draw_rect(Rect2(c + Vector2(0, -18) * k, Vector2(8, 4) * k), POLICE_BLUE if flash else RED)
		for wx in [-18.0, 18.0]:
			draw_circle(c + Vector2(wx, 7) * k, 5.0 * k, DUSK)
			draw_circle(c + Vector2(wx, 7) * k, 3.0 * k, SILVER)

	## A roadblock sawhorse: striped plank on two A legs.
	func _sawhorse(c: Vector2) -> void:
		for lx in [-22.0, 22.0]:
			draw_line(c + Vector2(lx - 6, 18), c + Vector2(lx, -6), SILVER, 3.0)
			draw_line(c + Vector2(lx + 6, 18), c + Vector2(lx, -6), SILVER, 3.0)
		draw_rect(Rect2(c + Vector2(-34, -12), Vector2(68, 11)), SILVER)
		for i in 5:
			var x0 := -34.0 + i * 14.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(x0, -1), c + Vector2(x0 + 7, -1),
				c + Vector2(x0 + 12, -12), c + Vector2(x0 + 5, -12)]), RED)

	## A spike strip seen from the side: a bar with a row of teeth.
	func _spikes(c: Vector2) -> void:
		draw_rect(Rect2(c + Vector2(-38, 2), Vector2(76, 6)), SILVER)
		for i in 9:
			var x := -36.0 + i * 9.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(x, 2), c + Vector2(x + 7, 2),
				c + Vector2(x + 3.5, -10)]), SILVER)

	## A helicopter: cabin, tail boom, rotor, skids.
	func _helicopter(c: Vector2) -> void:
		var body := PackedVector2Array()
		for i in 16:
			var a := TAU * i / 16.0
			body.append(c + Vector2(cos(a) * 15.0 - 8.0, sin(a) * 9.0))
		draw_colored_polygon(body, SILVER)
		draw_line(c + Vector2(4, -2), c + Vector2(34, -6), SILVER, 4.0)
		draw_line(c + Vector2(34, -13), c + Vector2(34, 1), SILVER, 2.0)
		draw_line(c + Vector2(-8, -9), c + Vector2(-8, -14), SILVER, 2.0)
		draw_line(c + Vector2(-40, -15), c + Vector2(24, -15), SILVER, 2.0)
		draw_line(c + Vector2(-22, 13), c + Vector2(6, 13), SILVER, 2.0)
		draw_line(c + Vector2(-16, 9), c + Vector2(-16, 13), SILVER, 2.0)
		draw_line(c + Vector2(0, 9), c + Vector2(0, 13), SILVER, 2.0)
		draw_rect(Rect2(c + Vector2(-18, -5), Vector2(6, 5)), POLICE_BLUE if not flash else RED)

func _init(h: PoliceHeat) -> void:
	heat = h

func _ready() -> void:
	layer = 9
	icon = HeatIcon.new()
	icon.name = "HeatIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	icon.size = ICON_SIZE
	icon.position = icon_offset()
	icon.visible = false
	add_child(icon)
	bust_bar = ColorRect.new()
	bust_bar.name = "BustBar"
	bust_bar.color = RED
	bust_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bust_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bust_bar.position = icon_offset() + Vector2(0.0, ICON_SIZE.y + 4)
	bust_bar.size = Vector2(0, 6)
	bust_bar.visible = false
	add_child(bust_bar)
	# Above Dave's caption (bottom centre), same width and colour family.
	caption = Label.new()
	caption.name = "PoliceCaption"
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	caption.size = Vector2(720, 60)
	caption.position = Vector2(-360, -190)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.apply(caption, "menu", 20)
	caption.add_theme_color_override("font_color", Hud.AMBER)
	caption.add_theme_color_override("font_outline_color", DUSK)
	caption.add_theme_constant_override("outline_size", 4)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.visible = false
	add_child(caption)
	if heat != null:
		heat.level_changed.connect(_on_level)
		heat.warning_started.connect(_on_warning)
		heat.warning_ended.connect(_on_warning_end)
		_on_level(heat.level)

func say(text: String) -> void:
	caption.text = text
	caption.visible = true
	_caption_t = CAPTION_SECS

## P2: a warning shows the first icon dim, with no heat behind it.
func _on_warning(_cop: Node3D, _kind: int) -> void:
	icon.kind = PoliceHeat.icon_for(PoliceHeat.ONE_CAR)
	icon.modulate = Color(1, 1, 1, 0.4)
	icon.visible = true
	icon.queue_redraw()

func _on_warning_end(_complied: bool) -> void:
	icon.modulate = Color.WHITE
	_on_level(heat.level)

func _on_level(lvl: int) -> void:
	icon.modulate = Color.WHITE
	var k := PoliceHeat.icon_for(lvl)
	if k != "" and k != icon.kind:
		_flash = FLASH_SECS if lvl > PoliceHeat.ICONS.find(icon.kind) else 0.0
	icon.kind = k
	icon.visible = k != ""
	icon.queue_redraw()

func _process(delta: float) -> void:
	var fill := patrol.bust_fill if patrol != null and is_instance_valid(patrol) else 0.0
	bust_bar.visible = fill > 0.0
	if fill > 0.0:
		bust_bar.size = Vector2(ICON_SIZE.x * fill, 6)
	if _caption_t > 0.0:
		_caption_t -= delta
		caption.visible = _caption_t > 0.0
	if _flash > 0.0:
		_flash -= delta
		var f := _flash > 0.0 and int(Time.get_ticks_msec() / 250) % 2 == 0
		if f != icon.flash:
			icon.flash = f
			icon.queue_redraw()
