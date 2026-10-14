class_name HeatIcons
extends CanvasLayer

# Police heat on screen (F0): one icon for the current level, top centre,
# drawn in code like the RPM bar. Each level has its own picture, so a glance
# says what is coming, not how many stars: one patrol car, two cars, a
# sawhorse, a heavy ramming truck, a helicopter (PoliceHeat.ICONS; there are
# no spike strips anywhere, Roy 2026-10-10). No icon at 0 and
# none for bad cops. A new level flashes red/blue for FLASH_SECS.
#
# Also the caption for police lines (night one's warning and jab) when Dave's
# station is not on to say them.

const SILVER := Hud.SILVER
const POLICE_BLUE := Color("#2E4FD8")
const RED := Hud.RED
const DUSK := Hud.DUSK
const ICON_SIZE := Vector2(96, 52)
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
			"heavy_truck":
				_heavy_truck(Vector2(s.x * 0.5, s.y * 0.6))
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

	## The heavy unit (heat 4): a tall boxy patrol SUV from the side, light
	## bar on the roof and a push bar standing proud of its nose (on the left,
	## the way the car icons face).
	func _heavy_truck(c: Vector2) -> void:
		var pts := PackedVector2Array([
			Vector2(-28, 8), Vector2(-28, -4), Vector2(-21, -6), Vector2(-15, -18),
			Vector2(26, -18), Vector2(29, -6), Vector2(29, 8)])
		for i in pts.size():
			pts[i] = c + pts[i]
		draw_colored_polygon(pts, SILVER)
		# push bar: two uprights and a cross bar ahead of the nose
		draw_line(c + Vector2(-34, -8), c + Vector2(-34, 9), SILVER, 3.0)
		draw_line(c + Vector2(-34, -6), c + Vector2(-28, -6), SILVER, 2.0)
		draw_line(c + Vector2(-34, 6), c + Vector2(-28, 6), SILVER, 2.0)
		draw_rect(Rect2(c + Vector2(-4, -23), Vector2(9, 5)), RED if flash else POLICE_BLUE)
		draw_rect(Rect2(c + Vector2(5, -23), Vector2(9, 5)), POLICE_BLUE if flash else RED)
		for wx in [-17.0, 18.0]:
			draw_circle(c + Vector2(wx, 9), 6.5, DUSK)
			draw_circle(c + Vector2(wx, 9), 4.0, SILVER)

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
	icon.position = Vector2(-ICON_SIZE.x * 0.5, 14)
	icon.visible = false
	add_child(icon)
	bust_bar = ColorRect.new()
	bust_bar.name = "BustBar"
	bust_bar.color = RED
	bust_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bust_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bust_bar.position = Vector2(-ICON_SIZE.x * 0.5, 14 + ICON_SIZE.y + 4)
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
