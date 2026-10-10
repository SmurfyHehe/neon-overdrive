class_name TitleScreen
extends CanvasLayer

# Title screen (menus A-list, 2026-10-08; "Kerbside" rebuild 2026-10-10): shown
# before the first drive of a session (GameState.TITLE).
#
# Behind the menu is the Kerbside scene (title_kerbside.gd): the player's own
# car parked under one street lamp. The world is already loaded and frozen, so
# the drive starts at once; while the title is up the camera looks at the
# Kerbside set only and the frame rate is held at 30, which keeps the title
# cheap. The synthwave station plays under it, muffled (PauseLook).
#
# On screen: the B4 mark and the BOOST wordmark top left with the Early Access
# tag, the menu bottom left, one line of late-night radio news along the
# bottom. A splash (the mark spools up and flutters, with a turbo whistle) runs
# first on every start, and a short Early Access card shows on the first launch
# only. No key hints, no maker name, no loading bar.

const GameInfo := preload("res://scripts/core/game_info.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")

const NAVY := Color("#0E1424")
const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")
const DIM := Color(0.79, 0.81, 0.84, 0.38)

const MARK_BODY := "res://assets/brand/logo_B4_mark_body.svg"
const MARK_WHEEL := "res://assets/brand/logo_B4_mark_wheel.svg"
const WHISTLE := "res://assets/ui/sfx/splash_whistle.wav"
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
const DJ_NAME := "Dale"
const DJ_OLD_NAME := "Dave"

## Splash timing, matched to the whistle (tools/render_splash_whistle.gd):
## the turbo spools for SPOOL seconds, then the valve flutters.
const SPLASH_SOUND_AT := 0.2
const SPLASH_SPOOL := 1.45
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
var _mark_y := 0.0             # the splash mark's resting place
var _whistle: AudioStreamPlayer
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
	_build_lockup(slide, Vector2(96.0, 84.0), 150.0)
	_build_menu()
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
			if int(s.saved_at) > 0:
				text += "   %s" % Time.get_date_string_from_unix_time(int(s.saved_at))
		if n == active:
			text += "   IN USE"
		var row := _add_row(load_list, text, _load_slot.bind(n))
		row.disabled = s.empty and n != active
	_add_row(load_list, "BACK", func() -> void: _show_list(main_list, load_button))

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
## The DJ is Dale (decided 2026-10-10); the radio data still says Dave, so the
## name is swapped here until that data is renamed.
static func news_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for st: Dictionary in RadioStations.STATIONS:
		if st.get("kind", "") == "talk":
			for l: String in st.get("dj", []):
				out.append(l.replace(DJ_OLD_NAME, DJ_NAME))
	for band: Array in NightBands.BAND_LINES:
		if not band.is_empty():
			out.append(str(band[0]).replace(DJ_OLD_NAME, DJ_NAME))
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
	splash_wheel.rotation += _wheel_speed * delta
	var end := SPLASH_SOUND_AT + vent_at + SPLASH_FLUTTER + SPLASH_HOLD
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
		var s := _synthwave_station()
		if s >= 0:
			radio.borrow(s)   # saves still keep the player's own station
	_refresh_saves()
	if splash_due():
		_start_splash()
	else:
		panel.visible = true
		_enter_menu()

func _enter_menu() -> void:
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
	if splash_running():
		_end_splash()
	if kerbside != null:
		kerbside.queue_free()
		kerbside = null
	var radio: Variant = get_parent().get("radio")
	if radio != null:
		radio.give_back()
	if _caps_fps():
		Engine.max_fps = GraphicsSettings.fps_cap

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
