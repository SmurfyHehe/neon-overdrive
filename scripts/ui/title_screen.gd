class_name TitleScreen
extends CanvasLayer

# Title screen (menus A-list, 2026-10-08; "Kerbside" rebuild 2026-10-10): shown
# before the first drive of a session (GameState.TITLE).
#
# Behind the menu is the Kerbside scene (title_kerbside.gd): the player's own
# car parked under one street lamp. The world is already loaded and frozen, so
# the drive starts at once; while the title is up the camera looks at the
# Kerbside set only and the frame rate is held at 30, which keeps the title
# cheap. Roy's theme song (Full Boost) plays under it on the Music bus, muffled
# (PauseLook's low-pass); holding W opens the filter. It is the title's alone:
# no radio station carries it and it stops when the drive starts.
#
# On screen: the B4 mark and the BOOST wordmark top left with the Early Access
# tag, the menu bottom left, one line of late-night radio news along the
# bottom. A splash (the mark spools up and flutters, with a turbo whistle) runs
# first on every start, and a short Early Access card shows on the first launch
# only. No key hints, no maker name, no loading bar.

const GameInfo := preload("res://scripts/core/game_info.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const Freemode := preload("res://scripts/core/freemode.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")

const NAVY := Color("#0E1424")
const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")
const DIM := Color(0.79, 0.81, 0.84, 0.38)

const MARK_BODY := "res://assets/brand/logo_B4_mark_body.svg"
const MARK_WHEEL := "res://assets/brand/logo_B4_mark_wheel.svg"
const ShaderWarmup := preload("res://scripts/core/shader_warmup.gd")
const THEME := "res://assets/music/title_theme_full_boost.ogg"
const WHISTLE := "res://assets/ui/sfx/splash_whistle.wav"
const MENU_WHISTLE_LOOP := "res://assets/ui/sfx/menu_whistle_loop.wav"
const MENU_WHISTLE_FLUTTER := "res://assets/ui/sfx/menu_whistle_flutter.wav"
## The wheel's centre inside the mark's 256 x 256 drawing (tools/build_brand.py).
const WHEEL_AT := Vector2(105.0, 128.0)
## Where the mark sits inside that drawing.
const MARK_BOX := Rect2(14.0, 40.0, 228.0, 176.0)

## Everything is laid out for a 1080-line screen and scaled to the window.
const DESIGN_H := 1080.0
const TITLE_FPS := 30
const TICKER_H := 46.0
const TICKER_SPEED := 64.0     # design px per second
const TICKER_GAP := "      +++      "
const SYNTHWAVE_DIR := "s4_synthwave"
## The theme song's voicing: muffled at rest, opened by the turbo (boost 0..1).
const THEME_MUFFLE_HZ := 900.0
const THEME_MUFFLE_DB := -6.0
const THEME_OPEN_HZ := 20000.0
const THEME_OPEN_DB := 3.0
const THEME_CLOSE_SECS := 2.0  # open -> muffled after the turbo is let go
const THEME_DUCK_DB := -12.0   # under the start of the drive
const THEME_DUCK_SECS := 0.4
const DJ_NAME := "Dale"
const DJ_OLD_NAME := "Dave"

## Splash timing, matched to the whistle (tools/render_splash_whistle.gd):
## the turbo spools for SPOOL seconds, then the valve flutters.
const SPLASH_SOUND_AT := 0.2
const SPLASH_SPOOL := 1.45
const MENU_SPIN_MAX := 18.0    # rad/s, menu logo wheel while W is held
const MENU_SPIN_UP := 12.0     # rad/s^2
const MENU_SPIN_DOWN := 7.0
const MENU_FLUTTER_MIN := 6.0  # rad/s: slower than this, letting go is just a fade
const MENU_WHISTLE_DB := -8.0
const MENU_WHISTLE_IN := 0.3   # s to fade the held whistle in
const MENU_WHISTLE_OUT := 0.2  # s to fade it out on a slow release
const MENU_SHAKE_PX := 1.5     # held, at full spin
const MENU_SHAKE_RAD := 0.004
## "Turbo goes crazy": holding W builds menu_boost (0..1) over BOOST_SECS and
## it pays off on release. Everything below hangs off that one number.
const MENU_BLOWOFF := "res://assets/ui/sfx/menu_blowoff.wav"
const MENU_GRIND := "res://assets/ui/sfx/menu_overboost_grind.wav"
const BOOST_UP := 1.0 / 6.0           # per second while W is held
const BOOST_DOWN := 1.0 / 1.5         # per second when let go
const BOOST_SHAKE_FROM := 0.25        # 1.5 px / 0.004 rad ...
const BOOST_LIMITER := 0.85           # ... to 8 px / 0.02 rad here; judder above
const BOOST_SPARKS := 0.5             # sparks and the grind start here
const BOOST_BLOWOFF := 0.4            # letting go above this blows off
const MENU_SPIN_OVER := 26.0          # rad/s at full boost (18 at half)
const SHAKE_PX_MAX := 8.0
const SHAKE_RAD_MAX := 0.02
const LIMITER_STEP_HZ := 12.0         # the mark's offset updates this often
const LIMITER_DIP_SECS := 0.15        # whistle bounces off the limiter
const SPARK_COOLDOWN := 1.0           # no new sparks this long after a blow-off
const BLOWOFF_DB := -2.0
const BLOWOFF_FLUTTER_AT := 0.3       # s after the blow-off the flutter starts
const GRIND_DB := -13.0
## The B4 mark's hot ring in the 256 drawing (tools/build_brand.py): r 55.5,
## 5 px stroke round the wheel; the sparks leave the outlet's flame tip.
const RING_R := 55.5
const RING_W := 5.0
const OUTLET_AT := Vector2(238.0, 58.0)
const RING_AMBER_AT := 0.6
const SPLASH_FLUTTER := 0.6
const SPLASH_HOLD := 0.45
const SPLASH_FADE := 0.35
const FLUTTER_HZ := 21.0

## Once per start of the game, not again after Quit to title.
static var splash_done := false
## Off only for tools that measure the title's frame (tools/title_shots.gd).
static var cap_fps := true

var game_state: GameState
var panel: Control             # everything but the splash; hidden behind Settings
var stage: Control             # the 1080-line layout, scaled to the window
var slide: Control             # the lockup and the menu; slides in from the left
var drive_button: Button       # Continue
var new_game_button: Button
var load_button: Button
var settings_button: Button
var extras_button: Button
var quit_button: Button
var main_list: VBoxContainer
var load_list: VBoxContainer
var delete_list: VBoxContainer
var delete_button: Button
var extras_list: VBoxContainer
var confirm: ConfirmBox
var kerbside: TitleKerbside
var ticker_label: Label
var ticker_speaker: Label
var welcome: Control
var welcome_button: Button
var splash: Control
var splash_mark: Control
var splash_wheel: TextureRect
var splash_name: Control

var _splash_t := -1.0
var _wheel_speed := 0.0
var menu_wheel: TextureRect    # the menu lockup's wheel; spins while W is held
var menu_spin := 0.0           # its speed, rad/s
var _spin_held := false        # test hook: hold the throttle without a key event
var _mark_y := 0.0             # the splash mark's resting place
var _whistle: AudioStreamPlayer
var menu_mark: Control         # the menu lockup's mark; shakes with the whistle
var _mark_rest := Vector2.ZERO
var _menu_whistle: AudioStreamPlayer   # steady whistle while W is held
var _menu_flutter: AudioStreamPlayer   # valve chatter on letting go at speed
var _whistle_gain := 0.0       # 0..1 fade of the held whistle
var _was_live := false         # W was held (and the title listening) last frame
var _shake_clock := 0.0
var _flutter_t := -1.0         # >= 0 while the release shake runs
var _theme: AudioStreamPlayer  # Roy's theme song, Music bus, loops
var _theme_open := 0.0         # 0 muffled .. 1 open (follows the boost, 2 s back)
var _theme_tween: Tween        # the Continue duck
var menu_boost := 0.0          # 0..1, built by holding W; M2-M4 read this
var _menu_blowoff: AudioStreamPlayer
var _menu_grind: AudioStreamPlayer     # rough low layer under the whistle
var _sparks: CPUParticles2D
var _puff: CPUParticles2D
var _ring: Control             # additive copy of the hot ring, tinted by boost
var _spark_cooldown := 0.0
var _flutter_wait := -1.0      # >= 0: the flutter follows the blow-off
var _release_boost := 0.0      # boost at the moment W was let go
var _limiter_step := -1
var _judder := Vector2.ZERO    # (px, rad) of the current limiter step
var _limiter_t := 0.0
var _ticker_w := 0.0
var _lists: Array[VBoxContainer] = []

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10   # over the world; Settings (11) opens above it
	visible = false

	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.theme = UiTheme.font_theme()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stage)

	_build_shade()
	slide = Control.new()
	slide.set_anchors_preset(Control.PRESET_FULL_RECT)
	slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(slide)
	var lockup := _build_lockup(slide, Vector2(96.0, 84.0), 150.0)
	menu_mark = lockup[0]
	menu_wheel = lockup[1]
	_mark_rest = menu_mark.position
	_menu_whistle = _menu_player(MENU_WHISTLE_LOOP)
	_menu_flutter = _menu_player(MENU_WHISTLE_FLUTTER)
	_menu_blowoff = _menu_player(MENU_BLOWOFF)
	_menu_grind = _menu_player(MENU_GRIND)
	_build_boost_effects()
	_build_menu()
	_theme = AudioStreamPlayer.new()
	_theme.bus = &"Music"
	_theme.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_theme)
	_build_ticker()
	_build_welcome()

	confirm = ConfirmBox.new(game_state)
	add_child(confirm)
	_build_splash()

	get_viewport().size_changed.connect(_fit)
	_fit()
	game_state.state_changed.connect(_on_state_changed)

# ---------------------------------------------------------------- layout

## Scales the 1080-line layout to the window.
func _fit() -> void:
	var view := get_viewport().get_visible_rect().size
	var k := view.y / DESIGN_H
	for c: Control in [stage, splash.get_child(1) as Control]:
		c.scale = Vector2(k, k)
		c.position = Vector2.ZERO
		c.size = Vector2(view.x / k, DESIGN_H)

## Navy falls off from the left and from the bottom, so the name and the menu
## read against the street.
func _build_shade() -> void:
	for horizontal: bool in [true, false]:
		var grad := Gradient.new()
		grad.set_color(0, Color(NAVY, 0.9))
		grad.set_color(1, Color(NAVY, 0.0))
		grad.add_point(0.45, Color(NAVY, 0.62))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill_from = Vector2(0, 0) if horizontal else Vector2(0, 1)
		tex.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 0)
		tex.width = 64
		tex.height = 64
		var r := TextureRect.new()
		r.texture = tex
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		if horizontal:
			r.anchor_right = 0.5
		else:
			r.anchor_top = 0.55
		stage.add_child(r)

## The mark with BOOST over a spaced SIMCADE beside it. Returns [mark, wheel,
## name block] so the splash can move them.
func _menu_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"UI"
	p.volume_db = MENU_WHISTLE_DB
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p

## The hot ring is part of the mark's one body texture, so a tinted copy of just
## that ring is laid over it with an additive blend. Every target colour is at
## least as bright as sodium in each channel, so the tint is the difference.
class HotRing extends Control:
	var radius := 0.0
	var width := 0.0
	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color.WHITE, width, true)

## Sparks at the housing outlet, a vapour puff for the blow-off, and the ring
## overlay. All are children of the menu mark (so they shake with it) and none
## touches the wordmark. Off until boost drives them.
func _build_boost_effects() -> void:
	var k := menu_mark.size.x / 256.0
	_ring = HotRing.new()
	_ring.radius = RING_R * k
	_ring.width = RING_W * k
	_ring.position = WHEEL_AT * k
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ring.material = add
	_ring.modulate = Color(0.0, 0.0, 0.0, 1.0)
	menu_mark.add_child(_ring)
	menu_mark.move_child(_ring, 1)   # over the body, under the wheel

	# Sparks: short amber/white streaks (a 2 x 10 px strip aligned to the
	# velocity), 64 at most, falling under gravity.
	var strip := Image.create(2, 10, false, Image.FORMAT_RGBA8)
	strip.fill(Color.WHITE)
	_sparks = CPUParticles2D.new()
	_sparks.texture = ImageTexture.create_from_image(strip)
	_sparks.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sparks.material = add
	_sparks.amount = 64
	_sparks.lifetime = 0.45
	_sparks.local_coords = true
	_sparks.emitting = false
	_sparks.position = OUTLET_AT * k
	_sparks.direction = Vector2(1.0, -0.45)
	_sparks.spread = 30.0
	_sparks.initial_velocity_min = 140.0
	_sparks.initial_velocity_max = 330.0
	_sparks.gravity = Vector2(0.0, 640.0)
	_sparks.particle_flag_align_y = true
	_sparks.scale_amount_min = 0.8
	_sparks.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#FFF1D6"))
	ramp.set_color(1, Color(AMBER, 0.0))
	ramp.add_point(0.4, AMBER)
	_sparks.color_ramp = ramp
	menu_mark.add_child(_sparks)

	# Vapour: 24 grey-white soft puffs, one burst, gone in 0.6 s.
	var soft := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	sg.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	soft.gradient = sg
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	_puff = CPUParticles2D.new()
	_puff.texture = soft
	_puff.amount = 24
	_puff.lifetime = 0.6
	_puff.one_shot = true
	_puff.explosiveness = 0.9
	_puff.local_coords = true
	_puff.emitting = false
	_puff.position = OUTLET_AT * k - Vector2(26.0, 6.0) * k
	_puff.direction = Vector2(1.0, -0.6)
	_puff.spread = 55.0
	_puff.initial_velocity_min = 60.0
	_puff.initial_velocity_max = 190.0
	_puff.damping_min = 70.0
	_puff.damping_max = 110.0
	_puff.gravity = Vector2(0.0, -40.0)
	_puff.scale_amount_min = 0.25
	_puff.scale_amount_max = 0.5
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.7))
	_puff.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.86, 0.88, 0.9, 0.7))
	fade.set_color(1, Color(0.86, 0.88, 0.9, 0.0))
	_puff.color_ramp = fade
	menu_mark.add_child(_puff)

func _build_lockup(parent: Control, at: Vector2, mark_px: float) -> Array:
	# mark_px is the height of the mark itself; its drawing is a 256 box with
	# the mark at MARK_BOX inside it.
	var box_px := mark_px * 256.0 / MARK_BOX.size.y
	var mark := Control.new()
	mark.position = at - MARK_BOX.position * (box_px / 256.0)
	mark.size = Vector2(box_px, box_px)
	mark.pivot_offset = mark.size * 0.5
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(mark)
	var body := TextureRect.new()
	body.texture = load(MARK_BODY)
	body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.stretch_mode = TextureRect.STRETCH_SCALE
	body.size = mark.size
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(body)
	var k := box_px / 256.0
	var wheel := TextureRect.new()
	wheel.texture = load(MARK_WHEEL)
	wheel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wheel.stretch_mode = TextureRect.STRETCH_SCALE
	wheel.size = Vector2(128.0, 128.0) * k
	wheel.position = WHEEL_AT * k - wheel.size * 0.5
	wheel.pivot_offset = wheel.size * 0.5
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(wheel)

	# The name comes from project.godot (GameInfo): first word big, rest spaced.
	var words := GameInfo.game_name().to_upper().split(" ", false)
	var block := Control.new()
	block.position = at + Vector2(mark_px * 1.56, -mark_px * 0.08)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	var big := Label.new()
	big.text = words[0] if words.size() > 0 else ""
	big.add_theme_font_override("font", _wordmark_font())
	big.add_theme_font_size_override("font_size", int(mark_px * 0.98))
	big.add_theme_color_override("font_color", AMBER)
	big.add_theme_constant_override("line_spacing", 0)
	big.position = Vector2(0.0, -mark_px * 0.13)
	block.add_child(big)
	var rest := Label.new()
	rest.text = " ".join(words.slice(1))
	var spaced := FontVariation.new()
	spaced.base_font = UiTheme.font("logo")
	spaced.spacing_glyph = int(mark_px * 0.085)
	rest.add_theme_font_override("font", spaced)
	rest.add_theme_font_size_override("font_size", int(mark_px * 0.27))
	rest.add_theme_color_override("font_color", SILVER)
	rest.position = Vector2(mark_px * 0.01, mark_px * 0.93)
	block.add_child(rest)
	# Early Access tag, on the SIMCADE line.
	var tag := Label.new()
	tag.name = "EarlyAccessTag"
	tag.text = "EARLY ACCESS"
	UiTheme.apply(tag, "logo", int(mark_px * 0.15))
	tag.add_theme_color_override("font_color", SODIUM)
	tag.add_theme_stylebox_override("normal", _outline_box(SODIUM, 8, 2))
	tag.position = Vector2(mark_px * 2.05, mark_px * 0.975)
	block.add_child(tag)
	return [mark, wheel, block]

## Barlow Condensed, made heavier: only the SemiBold weight is bundled.
static func _wordmark_font() -> Font:
	var f := FontVariation.new()
	f.base_font = UiTheme.font("logo")
	f.variation_embolden = 0.55
	return f

static func _outline_box(colour: Color, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = colour
	sb.set_border_width_all(2)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb

# ---------------------------------------------------------------- menu

func _build_menu() -> void:
	main_list = _new_list()
	drive_button = _add_row(main_list, "CONTINUE", game_state.start_drive)
	new_game_button = _add_row(main_list, "NEW GAME", _new_game)
	load_button = _add_row(main_list, "LOAD", func() -> void: _show_list(load_list))
	settings_button = _add_row(main_list, "SETTINGS", _open_settings)
	extras_button = _add_row(main_list, "EXTRAS", func() -> void: _show_list(extras_list))
	quit_button = _add_row(main_list, "QUIT", func() -> void:
		confirm.ask("Quit to desktop?", "Quit", game_state.quit))

	load_list = _new_list()
	delete_list = _new_list()
	extras_list = _new_list()
	_add_row(extras_list, "ABOUT EARLY ACCESS", _show_welcome)
	_add_row(extras_list, "OPEN PHOTO FOLDER", _open_photos)
	_add_row(extras_list, "BACK", func() -> void: _show_list(main_list, extras_button))
	_show_list(main_list)

func _new_list() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.alignment = BoxContainer.ALIGNMENT_END
	list.add_theme_constant_override("separation", 6)
	# Bottom left, above the news line.
	list.anchor_top = 1.0
	list.anchor_bottom = 1.0
	list.offset_left = 96.0
	list.offset_right = 760.0
	list.offset_top = -TICKER_H - 56.0 - 420.0
	list.offset_bottom = -TICKER_H - 56.0
	list.visible = false
	slide.add_child(list)
	_lists.append(list)
	return list

## One menu row: plain text, amber with a sodium bar when it has the focus.
func _add_row(list: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(0.0, 54.0)
	UiTheme.apply(b, "logo", 44)
	b.add_theme_color_override("font_color", SILVER)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.add_theme_color_override("font_focus_color", AMBER)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_hover_pressed_color", AMBER)
	b.add_theme_color_override("font_disabled_color", DIM)
	var plain := StyleBoxEmpty.new()
	plain.content_margin_left = 22.0
	plain.content_margin_right = 22.0
	for s in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(s, plain)
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(0, 0, 0, 0)
	bar.border_color = SODIUM
	bar.border_width_left = 7
	bar.content_margin_left = 22.0
	bar.content_margin_right = 22.0
	bar.expand_margin_top = -9.0
	bar.expand_margin_bottom = -9.0
	b.add_theme_stylebox_override("focus", bar)
	b.pressed.connect(action)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and b.is_visible_in_tree():
			b.grab_focus())
	list.add_child(b)
	return b

func _show_list(list: VBoxContainer, focus: Button = null) -> void:
	if list == load_list:
		_fill_load_list()
	elif list == delete_list:
		_fill_delete_list()
	for l in _lists:
		l.visible = l == list
	if not is_inside_tree() or not visible:
		return
	if focus == null or focus.disabled:
		focus = _first_enabled(list)
	if focus != null:
		focus.grab_focus()

static func _first_enabled(list: VBoxContainer) -> Button:
	for c in list.get_children():
		if c is Button and not (c as Button).disabled:
			return c
	return null

## New Game and Load follow the save slots (SaveStore): New Game takes the first
## empty slot and is greyed when none is empty; Continue is greyed until the slot
## in use has something saved.
func _refresh_saves() -> void:
	var active := SaveStore.active_slot()
	var active_empty: bool = SaveStore.summary(active).empty
	drive_button.disabled = active_empty   # nothing to continue yet
	new_game_button.disabled = not active_empty and _first_empty_slot() == 0

func _first_empty_slot() -> int:
	for n in range(1, SaveStore.SLOTS + 1):
		if n != SaveStore.active_slot() and SaveStore.summary(n).empty:
			return n
	return 0

func _new_game() -> void:
	if SaveStore.summary(SaveStore.active_slot()).empty:
		game_state.start_drive()   # nothing saved yet: this slot is the new game
		return
	var n := _first_empty_slot()
	if n > 0:
		_switch_slot(n)

func _fill_load_list() -> void:
	for c in load_list.get_children():
		load_list.remove_child(c)
		c.queue_free()
	var active := SaveStore.active_slot()
	for n in range(1, SaveStore.SLOTS + 1):
		var s := SaveStore.summary(n)
		var text := "SAVE %d   EMPTY" % n
		if not s.empty:
			text = "SAVE %d   $%s" % [n, _thousands(int(s.cash))]
			if s.plate.get("mode") == "free":
				text = "SAVE %d   %s   $%s" % [n, Freemode.plate_line(int(s.plate.get("night", 31))), _thousands(int(s.cash))]
			if int(s.saved_at) > 0:
				text += "   %s" % Time.get_date_string_from_unix_time(int(s.saved_at))
		if n == active:
			text += "   IN USE"
		var row := _add_row(load_list, text, _load_slot.bind(n))
		row.disabled = s.empty and n != active
	delete_button = _add_row(load_list, "DELETE A SAVE", func() -> void: _show_list(delete_list))
	delete_button.disabled = not _any_save()
	_add_row(load_list, "BACK", func() -> void: _show_list(main_list, load_button))

func _any_save() -> bool:
	for n in range(1, SaveStore.SLOTS + 1):
		if not SaveStore.summary(n).empty:
			return true
	return false

## What a slot holds, in plain words (the delete rows and their question).
static func slot_text(n: int, s: Dictionary) -> String:
	var text := "$%s" % _thousands(int(s.cash))
	if int(s.saved_at) > 0:
		text += ", last played %s" % Time.get_date_string_from_unix_time(int(s.saved_at))
	return text

## Load > Delete a save: one row per save that holds something. Picking one
## asks first, and the question's focus starts on No (ConfirmBox).
func _fill_delete_list() -> void:
	for c in delete_list.get_children():
		delete_list.remove_child(c)
		c.queue_free()
	for n in range(1, SaveStore.SLOTS + 1):
		var s := SaveStore.summary(n)
		if s.empty:
			continue
		_add_row(delete_list, "DELETE SAVE %d   %s" % [n, slot_text(n, s).to_upper()], _ask_delete.bind(n))
	_add_row(delete_list, "BACK", func() -> void: _show_list(load_list))

func _ask_delete(n: int) -> void:
	var s := SaveStore.summary(n)
	var text := "Delete save %d? It holds %s." % [n, slot_text(n, s)]
	if n == SaveStore.active_slot():
		text += " It is the save in use: the game starts over on it."
	confirm.ask(text, "Delete save %d" % n, _delete_slot.bind(n))

func _delete_slot(n: int) -> void:
	var active := n == SaveStore.active_slot()
	if not SaveStore.delete_slot(n):
		return
	if active:
		# The world behind the title still holds the deleted save's run and
		# money: load it again, empty, without saving first.
		GameState.title_seen = false
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	_refresh_saves()
	_show_list(delete_list if _any_save() else load_list)

static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out

func _load_slot(n: int) -> void:
	if n == SaveStore.active_slot():
		game_state.start_drive()
	else:
		_switch_slot(n)

## Saves the slot in use like a quit, then loads the game again on slot n and
## goes straight to the road.
func _switch_slot(n: int) -> void:
	game_state.quitting.emit()
	if not SaveStore.select_slot(n):
		return
	_leave_title()
	GameState.title_seen = true
	get_tree().paused = false
	get_tree().reload_current_scene()

func _open_photos() -> void:
	var dir := ProjectSettings.globalize_path(TestMode.path("user://photos"))
	DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_open(dir)

# ---------------------------------------------------------------- news line

## One line of the night DJ's lines, scrolling along the bottom.
func _build_ticker() -> void:
	var bar := ColorRect.new()
	bar.name = "Ticker"
	bar.color = Color(NAVY, 0.88)
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -TICKER_H
	bar.clip_contents = true
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bar)
	var rule := ColorRect.new()
	rule.color = Color(SODIUM, 0.8)
	rule.anchor_right = 1.0
	rule.offset_bottom = 2.0
	bar.add_child(rule)

	var lines := news_lines()
	var speaker := ""
	var texts: PackedStringArray = []
	for l in lines:
		var cut := l.find(": ")
		if cut > 0 and cut < 16:
			speaker = l.left(cut)
			texts.append(l.substr(cut + 2))
		else:
			texts.append(l)
	ticker_label = Label.new()
	ticker_label.text = TICKER_GAP.join(texts) + TICKER_GAP
	UiTheme.apply(ticker_label, "tv", 30)
	ticker_label.add_theme_color_override("font_color", AMBER)
	ticker_label.position = Vector2(400.0, 8.0)
	bar.add_child(ticker_label)
	# The speaker's name stays put at the left, over the moving line.
	ticker_speaker = Label.new()
	ticker_speaker.text = " %s " % speaker.to_upper() if speaker != "" else ""
	UiTheme.apply(ticker_speaker, "tv", 30)
	ticker_speaker.add_theme_color_override("font_color", NAVY)
	var sb := StyleBoxFlat.new()
	sb.bg_color = SODIUM
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	ticker_speaker.add_theme_stylebox_override("normal", sb)
	ticker_speaker.position = Vector2(0.0, 2.0)
	ticker_speaker.size = Vector2(0.0, TICKER_H - 2.0)
	ticker_speaker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ticker_speaker.visible = speaker != ""
	bar.add_child(ticker_speaker)

## The lines the news line runs: the talk station's own, then tonight's bands.
static func news_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for st: Dictionary in RadioStations.STATIONS:
		if st.get("kind", "") == "talk":
			for l: String in st.get("dj", []):
				out.append(l)
	for band: Array in NightBands.BAND_LINES:
		if not band.is_empty():
			out.append(str(band[0]))
	return out

func _run_ticker(delta: float) -> void:
	if _ticker_w <= 0.0:
		_ticker_w = ticker_label.get_minimum_size().x
	ticker_label.position.x -= TICKER_SPEED * delta
	if ticker_label.position.x < -_ticker_w:
		ticker_label.position.x = stage.size.x

# ---------------------------------------------------------------- first launch

func _build_welcome() -> void:
	welcome = ColorRect.new()
	(welcome as ColorRect).color = Color(NAVY, 0.72)
	welcome.name = "Welcome"
	welcome.set_anchors_preset(Control.PRESET_FULL_RECT)
	welcome.visible = false
	stage.add_child(welcome)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1B2A4A")
	sb.border_color = SODIUM
	sb.border_width_left = 7
	sb.set_content_margin_all(40.0)
	card.add_theme_stylebox_override("panel", sb)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(820.0, 0.0)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	welcome.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	card.add_child(col)
	var head := Label.new()
	head.text = "EARLY ACCESS"
	UiTheme.apply(head, "logo", 54)
	head.add_theme_color_override("font_color", AMBER)
	col.add_child(head)
	var body := Label.new()
	body.text = ("%s is not finished. This is an early build: expect rough edges, "
		+ "missing pieces, and changes from one version to the next.\n\n"
		+ "Thanks for driving it early.") % GameInfo.game_name()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.apply(body, "menu", 28)
	body.add_theme_color_override("font_color", SILVER)
	col.add_child(body)
	var ver := Label.new()
	ver.text = "Version %s" % GameInfo.version()
	UiTheme.apply(ver, "numbers", 20)
	ver.add_theme_color_override("font_color", DIM)
	col.add_child(ver)
	welcome_button = _add_row(col as VBoxContainer, "OK", _close_welcome)

## True until the player has closed the card once (kept in the settings file).
static func welcome_due() -> bool:
	if TestMode.active() and OS.get_environment("NEON_WELCOME") != "1":
		return false
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	return not bool(cfg.get_value("title", "welcome_seen", false))

func _show_welcome() -> void:
	welcome.visible = true
	slide.visible = false
	welcome_button.grab_focus()

func _close_welcome() -> void:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)   # keep the other sections; a missing file is fine
	cfg.set_value("title", "welcome_seen", true)
	cfg.save(AudioSettings.path)
	welcome.visible = false
	slide.visible = true
	_show_list(main_list)

# ---------------------------------------------------------------- splash

func _build_splash() -> void:
	splash = Control.new()
	splash.name = "Splash"
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash.theme = UiTheme.font_theme()
	splash.visible = false
	add_child(splash)
	var bg := ColorRect.new()
	bg.color = NAVY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash.add_child(bg)
	var s_stage := Control.new()
	s_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.add_child(s_stage)
	# The same lockup as the boot image, centred, so the splash picks up where
	# the engine's boot image leaves off.
	var holder := Control.new()
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 0.5
	holder.anchor_bottom = 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s_stage.add_child(holder)
	var parts := _build_lockup(holder, Vector2(-462.0, -118.0), 236.0)
	splash_mark = parts[0]
	splash_wheel = parts[1]
	splash_name = parts[2]
	_mark_y = splash_mark.position.y
	(splash_name.get_node("EarlyAccessTag") as Control).visible = false
	_whistle = AudioStreamPlayer.new()
	_whistle.bus = &"UI"
	_whistle.volume_db = -8.0
	if ResourceLoader.exists(WHISTLE):
		_whistle.stream = load(WHISTLE)
	add_child(_whistle)

## Every start of the game; tests skip it unless they ask (NEON_SPLASH=1).
static func splash_due() -> bool:
	if splash_done:
		return false
	return not TestMode.active() or OS.get_environment("NEON_SPLASH") == "1"

func _start_splash() -> void:
	splash_done = true
	_splash_t = 0.0
	_wheel_speed = 0.0
	splash.visible = true
	splash.modulate.a = 1.0
	panel.visible = false
	# Shader warm-up (shader_warmup.gd): compiles what the drive will need
	# while the splash covers the screen.
	get_parent().add_child.call_deferred(ShaderWarmup.new())

func _end_splash() -> void:
	_splash_t = -1.0
	splash.visible = false
	splash_mark.position.y = _mark_y
	splash_mark.rotation = 0.0
	if _whistle.playing:
		_whistle.stop()
	panel.visible = true
	_enter_menu()

func _run_splash(delta: float) -> void:
	var before := _splash_t
	_splash_t += delta
	if before < SPLASH_SOUND_AT and _splash_t >= SPLASH_SOUND_AT and _whistle.stream != null:
		_whistle.play()
	var t := _splash_t - SPLASH_SOUND_AT
	var vent_at := SPLASH_SPOOL
	if t < vent_at:
		# Spooling: the wheel winds up with the whistle.
		_wheel_speed = 34.0 * smoothstep(0.0, 1.0, clampf(t / vent_at, 0.0, 1.0))
	elif t < vent_at + SPLASH_FLUTTER:
		# Throttle shut: the valve chatters, the mark shakes, the wheel stalls in steps.
		var f := (t - vent_at) / SPLASH_FLUTTER
		var beat := sin((t - vent_at) * TAU * FLUTTER_HZ)
		splash_mark.position.y = _mark_y + beat * 5.0 * (1.0 - f)
		splash_mark.rotation = beat * 0.012 * (1.0 - f)
		_wheel_speed = 34.0 * (1.0 - f) * (0.45 + 0.55 * maxf(0.0, beat))
	else:
		splash_mark.position.y = _mark_y
		splash_mark.rotation = 0.0
		_wheel_speed = move_toward(_wheel_speed, 0.6, delta * 20.0)
		_start_theme()   # the flutter is over: the song comes in under the hold
	splash_wheel.rotation += _wheel_speed * delta
	var end := SPLASH_SOUND_AT + vent_at + SPLASH_FLUTTER + SPLASH_HOLD
	if _splash_t > end and ShaderWarmup.busy():
		_splash_t = end   # hold the last pose until the shaders are ready (bounded there)
	if _splash_t > end:
		splash.modulate.a = 1.0 - clampf((_splash_t - end) / SPLASH_FADE, 0.0, 1.0)
		panel.visible = true
	if _splash_t > end + SPLASH_FADE:
		_end_splash()

func splash_running() -> bool:
	return _splash_t >= 0.0

# ---------------------------------------------------------------- running

func _process(delta: float) -> void:
	if not visible:
		return
	# Settings re-applies the player's own frame cap; the title takes it back.
	if _caps_fps() and Engine.max_fps != TITLE_FPS:
		Engine.max_fps = TITLE_FPS
	if splash_running():
		_run_splash(delta)
	if panel.visible:
		_run_ticker(delta)
		if not splash_running():
			_run_menu_spin(delta)
	_run_menu_voice(delta)
	_run_theme(delta)
	if kerbside != null:
		# the turbo's wind blows the litter, moths and bat; 0 boost = the default breeze
		kerbside.set_title_wind(lerpf(TitleKerbside.WIND_REST, TitleKerbside.WIND_MAX, menu_boost))

# Hold W (the throttle) and the menu logo's wheel spools up; let go and it
# eases to a stop. Polled, because the tree is paused behind the title and
# no car is reading the throttle.
func _run_menu_spin(delta: float) -> void:
	var held := _throttle_held()
	var rate := MENU_SPIN_UP if held else MENU_SPIN_DOWN
	# Past half boost the wheel keeps creeping from 18 towards 26 rad/s.
	var top := lerpf(MENU_SPIN_MAX, MENU_SPIN_OVER, clampf((menu_boost - BOOST_SPARKS) / 0.5, 0.0, 1.0))
	menu_spin = move_toward(menu_spin, top if held else 0.0, rate * delta)
	if menu_wheel != null and menu_spin != 0.0:
		var speed := menu_spin
		if _flutter_t >= 0.0 and not held:
			# Throttle shut at speed: the wheel stalls in steps, as in the splash.
			var beat := sin(_flutter_t * TAU * FLUTTER_HZ)
			speed *= 0.45 + 0.55 * maxf(0.0, beat)
		menu_wheel.rotation = wrapf(menu_wheel.rotation + speed * delta, -PI, PI)

func _throttle_held() -> bool:
	return _spin_held or Input.is_action_pressed("accelerate")

## The title is listening to W: no splash, no Settings, Load list, welcome
## card or confirm box in the way.
func _menu_live() -> bool:
	return visible and panel.visible and not splash_running() 			and not load_list.visible and not welcome.visible and not confirm.is_open()

## The turbo whistle, the logo's shake and the boost that go with holding W.
## Held: menu_boost climbs over six seconds; the whistle rises, the mark shakes
## harder and its hot ring heats up, sparks fly from half boost and a low grind
## joins the whistle. Above the limiter the shake judders in steps and the
## whistle bounces. Let go above BOOST_BLOWOFF: a blow-off, then the valve
## flutters and the mark shakes out, scaled by the boost. Let go lower: the
## whistle just fades.
func _run_menu_voice(delta: float) -> void:
	if menu_mark == null:
		return
	var live := _menu_live()
	var held := live and _throttle_held()
	_spark_cooldown = maxf(_spark_cooldown - delta, 0.0)
	if not live:
		if _was_live or _flutter_t >= 0.0 or _flutter_wait >= 0.0 or _whistle_gain > 0.0 				or menu_boost > 0.0:
			_stop_menu_voice()
		return
	var k := clampf(menu_spin / MENU_SPIN_MAX, 0.0, 1.0)
	if held:
		if _flutter_t >= 0.0:
			_end_flutter()
			_menu_flutter.stop()   # W pressed again mid-chatter
		_flutter_wait = -1.0
		_was_live = true
		menu_boost = minf(menu_boost + BOOST_UP * delta, 1.0)
		_shake_clock += delta
		_shake_mark(k)
		_set_ring_heat(menu_boost)
		_whistle_gain = move_toward(_whistle_gain, 1.0, delta / MENU_WHISTLE_IN)
		if not _menu_whistle.playing and _menu_whistle.stream != null:
			_menu_whistle.play()
		_play_whistle(k, delta)
		_play_grind()
		_run_sparks(true)
		return
	_run_sparks(false)
	if _was_live:
		_was_live = false
		_rest_mark()
		_menu_grind.stop()
		_release_boost = menu_boost
		if menu_boost > BOOST_BLOWOFF:
			_menu_whistle.stop()
			_whistle_gain = 0.0
			_blow_off(menu_boost)
		else:
			_flutter_t = -1.0
	menu_boost = move_toward(menu_boost, 0.0, BOOST_DOWN * delta)
	_set_ring_heat(menu_boost)
	if _flutter_wait >= 0.0:
		_flutter_wait -= delta
		if _flutter_wait < 0.0:
			if _menu_flutter.stream != null:
				_menu_flutter.volume_db = MENU_WHISTLE_DB 						+ linear_to_db(lerpf(0.4, 1.0, _release_boost))
				_menu_flutter.play()
			_flutter_t = 0.0
	if _flutter_t >= 0.0:
		var f := _flutter_t / SPLASH_FLUTTER
		if f >= 1.0:
			_end_flutter()
		else:
			var beat := sin(_flutter_t * TAU * FLUTTER_HZ)
			var s := 0.5 + 1.1 * _release_boost   # 5 px / 0.012 rad at 0.45, 8 / 0.02 at full
			menu_mark.position = _mark_rest + Vector2(0.0, beat * 5.0 * s * (1.0 - f))
			menu_mark.rotation = beat * 0.012 * s * (1.0 - f)
			_flutter_t += delta
	# A slow release: fade the loop out, then let it go.
	if _whistle_gain > 0.0:
		_whistle_gain = move_toward(_whistle_gain, 0.0, delta / MENU_WHISTLE_OUT)
		_menu_whistle.volume_db = MENU_WHISTLE_DB + linear_to_db(maxf(_whistle_gain, 0.0001))
		if _whistle_gain <= 0.0:
			_menu_whistle.stop()

## The mark's shake (the mark only, never the wordmark): the old small jitter
## up to BOOST_SHAKE_FROM, then 1.5 px / 0.004 rad growing to 8 px / 0.02 rad
## at the limiter, and above it hard 12-per-second steps.
func _shake_mark(k: float) -> void:
	var px := MENU_SHAKE_PX * k
	var rad := MENU_SHAKE_RAD * k
	if menu_boost >= BOOST_SHAKE_FROM:
		var t := clampf((menu_boost - BOOST_SHAKE_FROM) / (BOOST_LIMITER - BOOST_SHAKE_FROM), 0.0, 1.0)
		px = lerpf(MENU_SHAKE_PX, SHAKE_PX_MAX, t)
		rad = lerpf(MENU_SHAKE_RAD, SHAKE_RAD_MAX, t)
	if menu_boost > BOOST_LIMITER:
		var step := int(_shake_clock * LIMITER_STEP_HZ)
		if step != _limiter_step:
			_limiter_step = step
			_judder = Vector2(_hash(step * 2) * 2.0 - 1.0, _hash(step * 2 + 1) * 2.0 - 1.0)
		menu_mark.position = _mark_rest + Vector2(0.0, _judder.x * px)
		menu_mark.rotation = _judder.y * rad
	else:
		_limiter_step = -1
		var beat := sin(_shake_clock * TAU * FLUTTER_HZ)
		menu_mark.position = _mark_rest + Vector2(0.0, beat * px)
		menu_mark.rotation = beat * rad

static func _hash(n: int) -> float:
	var r := sin(float(n) * 12.9898) * 43758.5453
	return r - floorf(r)

## Pitch follows the wheel up to 1.0, then keeps rising to 1.3 at full boost;
## above the limiter it dips in volume and pitch every LIMITER_DIP_SECS.
func _play_whistle(k: float, delta: float) -> void:
	var pitch := lerpf(0.7, 1.0, k)
	if menu_boost > BOOST_SPARKS:
		pitch = lerpf(1.0, 1.3, (menu_boost - BOOST_SPARKS) / (1.0 - BOOST_SPARKS))
	var dip := 0.0
	if menu_boost > BOOST_LIMITER:
		_limiter_t += delta
		dip = 0.5 - 0.5 * cos(TAU * fmod(_limiter_t, LIMITER_DIP_SECS) / LIMITER_DIP_SECS)
	else:
		_limiter_t = 0.0
	_menu_whistle.pitch_scale = pitch * (1.0 - 0.07 * dip)
	_menu_whistle.volume_db = MENU_WHISTLE_DB + linear_to_db(maxf(_whistle_gain, 0.0001)) - 5.0 * dip

## A rough low layer from half boost, swelling and rising in pitch.
func _play_grind() -> void:
	if menu_boost <= BOOST_SPARKS:
		if _menu_grind.playing:
			_menu_grind.stop()
		return
	var t := (menu_boost - BOOST_SPARKS) / (1.0 - BOOST_SPARKS)
	if not _menu_grind.playing and _menu_grind.stream != null:
		_menu_grind.play()
	_menu_grind.pitch_scale = lerpf(0.85, 1.25, t)
	_menu_grind.volume_db = GRIND_DB + linear_to_db(maxf(minf(t * 3.0, 1.0), 0.0001))

## Sparks leave the outlet from half boost, faster the higher it goes, and not
## for SPARK_COOLDOWN after a blow-off.
func _run_sparks(held: bool) -> void:
	var on := held and menu_boost > BOOST_SPARKS and _spark_cooldown <= 0.0
	if _sparks.emitting != on:
		_sparks.emitting = on
	if on:
		_sparks.speed_scale = lerpf(0.8, 1.8, (menu_boost - BOOST_SPARKS) / (1.0 - BOOST_SPARKS))

## Sodium at BOOST_SHAKE_FROM, amber at RING_AMBER_AT, near white at 1.0.
func _set_ring_heat(b: float) -> void:
	var target := SODIUM
	if b >= RING_AMBER_AT:
		target = AMBER.lerp(Color("#FFF1D6"), (b - RING_AMBER_AT) / (1.0 - RING_AMBER_AT))
	elif b > BOOST_SHAKE_FROM:
		target = SODIUM.lerp(AMBER, (b - BOOST_SHAKE_FROM) / (RING_AMBER_AT - BOOST_SHAKE_FROM))
	_ring.modulate = Color(target.r - SODIUM.r, target.g - SODIUM.g, target.b - SODIUM.b, 1.0)

## Let go at speed: the valve blows off (loud, scaled by boost) with a vapour
## puff, then the flutter follows.
func _blow_off(boost: float) -> void:
	if _menu_blowoff.stream != null:
		_menu_blowoff.volume_db = BLOWOFF_DB + linear_to_db(boost)
		_menu_blowoff.play()
	_puff.restart()
	_puff.emitting = true
	_spark_cooldown = SPARK_COOLDOWN
	_flutter_wait = BLOWOFF_FLUTTER_AT
	_flutter_t = -1.0

func _rest_mark() -> void:
	menu_mark.position = _mark_rest
	menu_mark.rotation = 0.0

func _end_flutter() -> void:
	_flutter_t = -1.0
	_rest_mark()

## Everything quiet and the mark home: Settings opened, the title left, or
## the splash took over.
func _stop_menu_voice() -> void:
	_was_live = false
	_whistle_gain = 0.0
	_flutter_t = -1.0
	_flutter_wait = -1.0
	menu_boost = 0.0
	_limiter_t = 0.0
	_limiter_step = -1
	if _menu_whistle != null:
		_menu_whistle.stop()
		_menu_flutter.stop()
		_menu_blowoff.stop()
		_menu_grind.stop()
	if _sparks != null:
		_sparks.emitting = false
		_puff.emitting = false
		_set_ring_heat(0.0)
	if menu_mark != null:
		_rest_mark()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if splash_running():
		# Any key or click skips the splash.
		if (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) \
				and event.is_pressed() and not event.is_echo():
			get_viewport().set_input_as_handled()
			_end_splash()
		return
	if not panel.visible or confirm.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		if welcome.visible:
			get_viewport().set_input_as_handled()
			_close_welcome()
		elif load_list.visible:
			get_viewport().set_input_as_handled()
			_show_list(main_list, load_button)
		elif delete_list.visible:
			get_viewport().set_input_as_handled()
			_show_list(load_list)
		elif extras_list.visible:
			get_viewport().set_input_as_handled()
			_show_list(main_list, extras_button)

## No frame cap in headless runs: tests would only take longer.
static func _caps_fps() -> bool:
	return cap_fps and DisplayServer.get_name() != "headless"

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	var was := visible
	visible = new_state == GameState.State.TITLE
	var hud := _sibling("Hud")
	if hud != null and (visible or old_state == GameState.State.TITLE):
		hud.visible = not visible  # no speedo over the title
	if visible and not was:
		_arrive()
	elif was and not visible:
		_leave_title()

## The title has just come up: build the street, tune the radio, cap the frames.
func _arrive() -> void:
	if kerbside == null:
		kerbside = TitleKerbside.new(PlayerCar.chassis_kind())
		get_parent().add_child(kerbside)
	kerbside.camera.make_current()   # after PauseLook's own camera took over
	var radio: Variant = get_parent().get("radio")
	if radio != null:
		radio.borrow(-1)   # the song replaces the radio; saves keep the player's station
	_refresh_saves()
	if splash_due():
		_start_splash()
	else:
		panel.visible = true
		_enter_menu()

func _enter_menu() -> void:
	_start_theme()
	slide.visible = true
	_show_list(main_list)
	MenuMotion.slide_in(slide, Vector2.LEFT)
	var sfx: Variant = get_parent().get("menu_sfx")
	if sfx != null:
		sfx.squelch()
	if welcome_due():
		_show_welcome()

## Leaving for the road: the street goes, the radio and the frame cap come back.
func _leave_title() -> void:
	_stop_menu_voice()
	_end_theme()
	if splash_running():
		_end_splash()
	if kerbside != null:
		kerbside.queue_free()
		kerbside = null
	var radio: Variant = get_parent().get("radio")
	if radio != null:
		radio.give_back()
	if _caps_fps():
		Engine.max_fps = GraphicsSettings.engine_fps()

# ---------------------------------------------------------------- theme song

## Starts the song once per visit (idempotent): after the splash flutter, or at
## the menu when the splash is skipped or not due.
func _start_theme() -> void:
	if _theme == null or (_theme.playing and _theme_tween == null):
		return
	if _theme_tween != null:   # back on the title before the duck finished
		_theme_tween.kill()
		_theme_tween = null
		_theme.stop()
	if _theme.stream == null:
		var st := load(THEME) as AudioStreamOggVorbis
		if st == null:
			return
		st.loop = true
		_theme.stream = st
	_theme_open = 0.0
	_theme.volume_db = 0.0
	_theme.play()
	_voice_theme(0.0)

func theme_playing() -> bool:
	return _theme != null and _theme.playing

## How far the turbo is open, 0..1. The hook for menu_boost: when the menu
## turbo lands, return its value here. Until then it is the logo wheel's spin
## fraction, and only while W is listening (not under Settings or the Load list).
func _theme_boost() -> float:
	if not _menu_live():
		return 0.0
	return clampf(menu_boost, 0.0, 1.0)   # the menu turbo (M1) has landed

func _run_theme(delta: float) -> void:
	if not theme_playing() or _theme_tween != null:
		return
	var boost := _theme_boost()
	if boost >= _theme_open:
		_theme_open = boost   # opens as fast as the turbo spools
	else:
		_theme_open = move_toward(_theme_open, boost, delta / THEME_CLOSE_SECS)
	_voice_theme(_theme_open)

## The Music bus's pause low-pass, set to the song's voicing (900 Hz and
## -6 dB muffled, 20 kHz and +3 dB open), geometric in frequency.
func _voice_theme(open: float) -> void:
	var look := _sibling("PauseLook") as PauseLook
	if look != null:
		look.set_muffle(THEME_MUFFLE_HZ * pow(THEME_OPEN_HZ / THEME_MUFFLE_HZ, open),
			lerpf(THEME_MUFFLE_DB, THEME_OPEN_DB, open))

## The drive starts: duck -12 dB over 0.4 s under the start, then stop.
func _end_theme() -> void:
	if _theme == null or not _theme.playing:
		return
	if _theme_tween != null:
		_theme_tween.kill()
	_theme_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_theme_tween.tween_property(_theme, "volume_db", THEME_DUCK_DB, THEME_DUCK_SECS)
	_theme_tween.tween_callback(func() -> void:
		_theme.stop()
		_theme_tween = null)

static func _synthwave_station() -> int:
	for i in RadioStations.STATIONS.size():
		if str(RadioStations.STATIONS[i].get("dir", "")).ends_with(SYNTHWAVE_DIR):
			return i
	return -1

func _open_settings() -> void:
	var menu := _sibling("PauseMenu") as PauseMenu
	if menu == null:
		return
	panel.visible = false
	menu.settings.closed.connect(_back_from_settings, CONNECT_ONE_SHOT)
	menu.show_settings()

func _back_from_settings() -> void:
	if not visible:
		return
	panel.visible = true
	# The player may have picked another car in Settings: park that one.
	if kerbside != null and kerbside.kind != PlayerCar.chassis_kind():
		kerbside.set_car(PlayerCar.chassis_kind())
	_show_list(main_list, settings_button)
	MenuMotion.slide_in(slide, Vector2.LEFT)

func _sibling(cls: String) -> Node:
	for c in get_parent().get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null
