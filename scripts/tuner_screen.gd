class_name TunerScreen
extends CanvasLayer

# The Tuner (Tuner redesign PR 3, 2026-10-06; proposal approved by Roy, see
# docs/planning/tuner-redesign-proposal-2026-10-06.md). T opens it on Setup, Y on
# Mechanic, Esc closes; the game is paused while it is open (GameState.TUNING /
# AUTOTUNE).
#
#   +------------+------------------------------+-------------+
#   | page list  |   your car, on the bench     | stat panel  |
#   |            |   (TunerBench: camera, work  | before/now  |
#   |            |   light, the part outlined)  |             |
#   |            +------------------------------+             |
#   |            | the page: notch bars or a    |             |
#   |            | panel (Mechanic, Sound, Adv) |             |
#   |            | hint: what the setting does  |             |
#   +------------+------------------------------+-------------+
#
# Car on the bench (Tuner UI overhaul PR 1, 2026-10-08): the panels are plates
# round a clear middle where TunerBench shows the live car from a shop angle
# per page. The plates leave the car window as big as each page allows.
#
# Pages, settings, presets and the estimates live in TunerModel. The older
# panels keep their logic and tests and sit on their own pages: AutoTunePanel on
# Mechanic (PR 4 simplifies it), ExhaustPanel on Sound, TuningPanel (raw gearing
# and power, Copy values) on Advanced.
#
# Keyboard only, no key hints on screen (they are on the pause menu's Controls
# page): Q/E change page, Up/Down move between settings, Left/Right move one
# notch, Enter picks a preset. On the panel pages the arrows move between that
# panel's own controls. Look: "Gritty PS2 night", navy panel, silver labels,
# amber values, sodium orange for focus and the "now" bars.
#
# After a Test run the stat panel flips to a pit-wall result (UI direction blend,
# signed off by Roy 2026-10-07, docs/planning/ui-direction-blend-2026-10-07.md
# "Pit Wall"): the brake run's speed trace over the stock car's (silver = stock,
# amber = yours), thin throttle and brake strips, and a signed delta column. Any
# change to the car flips it back to the estimates.

const NAVY := Color("#0E1424")
const NAVY_LIGHT := Color("#1B2A4A")
const SILVER := Color("#C9CED6")
const DIM := Color(0.79, 0.81, 0.84, 0.35)
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const MARGIN := 16
## Width of the page graphic's plate at the right of the car window.
const GRAPHIC_W := 330.0

var player: PlayerCar
var game_state: GameState
var model: TunerModel
var manual: TuningPanel
var exhaust: ExhaustPanel
var auto: AutoTunePanel
var mechanic: MechanicPanel
var adv_gate: VBoxContainer
var adv_gate_button: Button
var watchdog: TuneWatchdog
var test_job: AutoTuneJob
var test_button: Button
var _test_poll := 0.0
var _test_hash := 0  # the setup the running test run is measuring
var _test_started_ms := 0
## A test run normally takes well under a minute; past this the worker is
## treated as hung and killed, so the button can never stick (settings safety,
## 2026-10-07).
var test_timeout_s := 120.0
## The stock car's Test run metrics (with its trace), measured once per screen:
## the first Test run drives stock as well, later ones reuse it.
var stock_run := {}
var pit_wall: PitWall

var page_ids: Array[String] = []
var page_index := 0
var row_index := 0
var page_labels: Array[Label] = []
var page_title: Label
var preset_label: Label
var car_label: Label
var hint: Label
## The focused setting's hint, right under its row (UI overhaul PR 2).
var row_hint: Label
var content: VBoxContainer   # rows of the current settings page
var panel_pages := {}        # page id -> Control (Setup, Mechanic, Sound, Advanced)
var rows: Array = []         # [{setting, name, value, bar}] on a settings page
var preset_buttons: Array[Button] = []
## The Grip to Drift dial's keyboard control, and setup sheets A-C (UI overhaul PR 4).
var character_slider: HSlider
var sheet_labels := {}   # sheet name -> Label
const SHEETS := ["Sheet A", "Sheet B", "Sheet C"]
const PRESET_LINES := {"Stock": "As it left the factory", "Street": "Forgiving, comfortable",
	"Grip": "Fast laps", "Drift": "Easy slides"}
var _ticket_poll := 0.0
var stats: PerformanceCard
## Notches and stats when the screen opened, shown as ghosts.
var before_notches := {}
var before_stats := {}
## The car on the bench, and the clear part of the screen it is framed in.
var bench: TunerBench
var car_window: Control
## The page's drawn graphic, on a plate at the right of the car window (PR 3).
var graphic_plate: PanelContainer
var graphics := {}   # page id -> PageGraphic
var page_plate: PanelContainer
var page_scroll: ScrollContainer
## The chase camera's view before the Tuner opened (cockpit is put back on close).
var _was_cockpit := false

func _init(car: PlayerCar, state: GameState) -> void:
	player = car
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10  # same layer as the pause menu; they are never open together
	visible = false
	model = TunerModel.new(player, player.spec, CarSpec.coupe_default())
	# Auto-revert (settings safety part 4): its own layer next to this one, so
	# it still shows after the screen closes.
	watchdog = TuneWatchdog.new(player, game_state)
	get_parent().add_child.call_deferred(watchdog)
	for p in TunerModel.pages():
		page_ids.append(p.id)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 10
	frame.offset_top = 8
	frame.offset_right = -10
	frame.offset_bottom = -10
	frame.theme = UiTheme.get_theme()  # job sheet: shared plates, slabs and fonts (UI blend PR 2)
	# Clear: each column is its own near-opaque plate (bright buildings behind
	# made bare text unreadable) and the car shows between them.
	frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)

	var header_plate := _plate(6)
	column.add_child(header_plate)
	var header := HBoxContainer.new()
	header_plate.add_child(header)
	car_label = _label("JOB SHEET   P1 COUPE", SODIUM)
	car_label.add_theme_font_override("font", UiTheme.font("display"))
	car_label.add_theme_font_size_override("font_size", 32)
	car_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(car_label)
	preset_label = _label("", AMBER)
	preset_label.add_theme_font_override("font", UiTheme.font("mono"))
	header.add_child(preset_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	column.add_child(body)

	var list_plate := _plate(8)
	body.add_child(list_plate)
	var page_list := VBoxContainer.new()
	page_list.custom_minimum_size = Vector2(130, 0)
	list_plate.add_child(page_list)
	for p in TunerModel.pages():
		var l := _label(p.title, SILVER)
		page_list.add_child(l)
		page_labels.append(l)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 8)
	body.add_child(middle)
	car_window = Control.new()
	car_window.size_flags_vertical = Control.SIZE_EXPAND_FILL
	car_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(car_window)
	graphic_plate = _plate(8)
	graphic_plate.anchor_left = 1.0
	graphic_plate.anchor_right = 1.0
	graphic_plate.anchor_bottom = 1.0
	graphic_plate.offset_left = -GRAPHIC_W
	graphic_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car_window.add_child(graphic_plate)
	for p in TunerModel.pages():
		var g := PageGraphic.for_page(p.id)
		if g != null:
			g.visible = false
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
			graphic_plate.add_child(g)
			graphics[p.id] = g
	page_plate = _plate(8)
	middle.add_child(page_plate)
	var page_box := VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 6)
	page_plate.add_child(page_box)
	page_title = _label("", SODIUM)
	page_box.add_child(page_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	page_box.add_child(scroll)
	page_scroll = scroll
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	holder.add_child(content)

	# Panel pages, built once and shown/hidden.
	# Setup (UI overhaul PR 4): preset cards, the Grip to Drift dial, sheets A-C.
	var setup := VBoxContainer.new()
	setup.add_theme_constant_override("separation", 8)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	setup.add_child(cards)
	for name in TunerModel.PRESETS:
		var b := Button.new()
		b.text = "%s
%s" % [name.to_upper(), PRESET_LINES[name]]
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_on_preset.bind(name))
		cards.add_child(b)
		preset_buttons.append(b)
	var dial_row := HBoxContainer.new()
	dial_row.add_theme_constant_override("separation", 10)
	setup.add_child(dial_row)
	dial_row.add_child(_label("Grip", DIM))
	character_slider = HSlider.new()
	character_slider.min_value = 0
	character_slider.max_value = TunerModel.CHARACTER_NOTCHES - 1
	character_slider.step = 1
	character_slider.value = TunerModel.CHARACTER_STOCK
	character_slider.tick_count = TunerModel.CHARACTER_NOTCHES
	character_slider.ticks_on_borders = true
	character_slider.focus_mode = Control.FOCUS_ALL
	character_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	character_slider.value_changed.connect(_on_character)
	dial_row.add_child(character_slider)
	dial_row.add_child(_label("Drift", DIM))
	var sheets := HBoxContainer.new()
	sheets.add_theme_constant_override("separation", 8)
	setup.add_child(sheets)
	for sheet in SHEETS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sheets.add_child(col)
		var l := _label("", AMBER)
		l.add_theme_font_override("font", UiTheme.font("mono"))
		col.add_child(l)
		sheet_labels[sheet] = l
		var bs := HBoxContainer.new()
		col.add_child(bs)
		for act in ["Load", "Save"]:
			var b := Button.new()
			b.text = act
			b.focus_mode = Control.FOCUS_ALL
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect((load_sheet if act == "Load" else save_sheet).bind(sheet))
			bs.add_child(b)
	panel_pages["setup"] = setup
	auto = AutoTunePanel.new(player, game_state)
	var mech := VBoxContainer.new()
	mech.add_theme_constant_override("separation", 8)
	mechanic = MechanicPanel.new(auto)
	mech.add_child(mechanic)
	mech.add_child(auto)
	panel_pages["mechanic"] = mech
	var sound := VBoxContainer.new()
	sound.add_child(_label("Sound and looks only: nothing here changes how the car drives.", DIM))
	exhaust = ExhaustPanel.new(player)
	sound.add_child(exhaust)
	panel_pages["sound"] = sound
	var adv := VBoxContainer.new()
	adv.add_child(_label("Every raw number, out to the extremes. Peak torque and redline move to the garage later.", DIM))
	# The one-time confirm (settings safety part 4): until it is accepted the
	# page shows only this, not the sliders.
	adv_gate = VBoxContainer.new()
	adv_gate.add_theme_constant_override("separation", 8)
	var warn := _label("Values here go out to the extremes: the car can spin, crawl or refuse to stop. Reset to stock always works, and a tune that leaves the car undrivable is reverted.", AMBER)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(420, 0)
	adv_gate.add_child(warn)
	adv_gate_button = Button.new()
	adv_gate_button.text = "Open Advanced"
	adv_gate_button.focus_mode = Control.FOCUS_ALL
	adv_gate_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	adv_gate_button.pressed.connect(accept_advanced)
	adv_gate.add_child(adv_gate_button)
	adv.add_child(adv_gate)
	manual = TuningPanel.new(player, game_state)
	adv.add_child(manual)
	panel_pages["advanced"] = adv
	for id in panel_pages:
		holder.add_child(panel_pages[id])
		panel_pages[id].visible = false

	var right_plate := _plate(8)
	body.add_child(right_plate)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(250, 0)
	right_plate.add_child(right)
	stats = PerformanceCard.new()
	right.add_child(stats)
	pit_wall = PitWall.new()
	pit_wall.visible = false
	right.add_child(pit_wall)
	test_button = Button.new()
	test_button.text = "Test run"
	test_button.focus_mode = Control.FOCUS_ALL
	test_button.pressed.connect(start_test_run)
	right.add_child(test_button)

	hint = _label("", SILVER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 44)
	page_box.add_child(hint)

	bench = TunerBench.new(player)
	get_parent().add_child.call_deferred(bench)

	manual.tune_changed.connect(_on_panel_changed)
	auto.tune_changed.connect(_on_auto_changed)
	game_state.state_changed.connect(_on_state_changed)

## A near-opaque work plate with `pad` pixels inside.
func _plate(pad: int) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := UiTheme.plate_panel()
	bg.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", bg)
	return p

func _label(text: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	return l

# ---------- open / close ----------

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	visible = GameState.is_tuner(new_state)
	if visible:
		var was_open := GameState.is_tuner(old_state)
		if not was_open:
			exhaust.refresh()
			manual.refresh_from_player()
			before_stats = TunerModel.estimate(player.spec)
			before_notches = {}
			for p in TunerModel.pages():
				for s in p.settings:
					before_notches[s.id] = model.notch(s)
			_open_bench()
		show_page("mechanic" if new_state == GameState.State.AUTOTUNE else "setup")
	else:
		_close_bench()
		# Sliders and buttons keep keyboard focus otherwise and eat the arrow keys.
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

# ---------- the car on the bench ----------

func _open_bench() -> void:
	if bench == null or not bench.is_inside_tree():
		return
	var chase: Variant = get_parent().get("camera")
	_was_cockpit = chase is ChaseCamera and chase.view == ChaseCamera.View.COCKPIT
	if _was_cockpit:
		chase.set_view(ChaseCamera.View.CHASE)  # the body is hidden in the cockpit
	var layers := []
	for c in get_parent().get_children():
		if c is Hud or c is WarningLights:
			layers.append(c)
	bench.open(layers)

func _close_bench() -> void:
	if bench == null or not bench.is_open:
		return
	bench.close()
	var chase: Variant = get_parent().get("camera")
	if _was_cockpit and chase is ChaseCamera:
		chase.set_view(ChaseCamera.View.COCKPIT)
	_was_cockpit = false

## How tall the page plate's scroll area is on each page: settings pages fit
## their rows, the panel pages get more, and the car keeps the rest.
func _page_height(id: String) -> float:
	match id:
		"setup": return 200.0
		"mechanic", "advanced": return 360.0
		"sound": return 300.0
	return minf(36.0 * (TunerModel.page(id).settings.size() + 1) + 56.0, 330.0)  # rows, reset, the hint

func current_page() -> String:
	return page_ids[page_index]

func show_page(id: String) -> void:
	page_index = page_ids.find(id)
	row_index = 0
	var page := TunerModel.page(id)
	page_title.text = page.title.to_upper()
	for i in page_labels.size():
		page_labels[i].text = ("> " if i == page_index else "  ") + TunerModel.pages()[i].title
		page_labels[i].add_theme_color_override("font_color", SODIUM if i == page_index else SILVER)
	for pid in panel_pages:
		panel_pages[pid].visible = pid == id
	page_scroll.custom_minimum_size = Vector2(0, _page_height(id))
	for gid in graphics:
		graphics[gid].visible = gid == id
	graphic_plate.visible = graphics.has(id)
	if bench != null and bench.outline != null:
		bench.show_page(id)
	for c in content.get_children():
		c.queue_free()
	rows = []
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused:
		focused.release_focus()
	for s in page.settings:
		rows.append(_add_row(s))
	if not page.settings.is_empty():
		rows.append(_add_reset_row())
		row_hint = _label("", SILVER)
		row_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_hint.custom_minimum_size = Vector2(420, 0)
		row_hint.add_theme_font_size_override("font_size", 15)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 12)
		pad.add_theme_constant_override("margin_bottom", 4)
		pad.add_child(row_hint)
		content.add_child(pad)
	_refresh()
	if id == "setup":
		preset_buttons[0].grab_focus()
	elif id == "mechanic":
		(mechanic.goal_buttons.values()[0] as Control).grab_focus()
	elif id == "sound":
		(exhaust.sliders.values()[0] as Control).grab_focus()
	elif id == "advanced":
		var ok := TunerGate.advanced_ok()
		adv_gate.visible = not ok
		manual.visible = ok
		if ok:
			(manual.sliders["final_drive"] as Control).grab_focus()
		else:
			adv_gate_button.grab_focus()

## Accepts the Advanced confirm once and for all, and opens the sliders.
func accept_advanced() -> void:
	TunerGate.set_advanced_ok(true)
	if current_page() == "advanced":
		show_page("advanced")

func _add_row(s: Dictionary) -> Dictionary:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	content.add_child(block)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	block.add_child(h)
	var name := _label(s.label, SILVER)
	name.custom_minimum_size = Vector2(170, 0)
	h.add_child(name)
	var lo := _label(s.lo_word if s.kind == "range" else "", DIM)
	lo.custom_minimum_size = Vector2(48, 0)
	lo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(lo)
	var bar := NotchBar.new()
	bar.custom_minimum_size = Vector2(176, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.choices = s.options.size() if s.kind == "choice" else TunerModel.NOTCHES
	h.add_child(bar)
	var hi := _label(s.hi_word if s.kind == "range" else "", DIM)
	hi.custom_minimum_size = Vector2(48, 0)
	h.add_child(hi)
	var value := _label("", AMBER)
	value.add_theme_font_override("font", UiTheme.font("mono"))
	h.add_child(value)
	# Against stock, beside the real number: "Stock" in steel blue, "+2 stiffer".
	var rel := _label("", TunerColours.STOCK)
	rel.add_theme_font_size_override("font_size", 14)
	h.add_child(rel)
	bar.stock = model.stock_notch(s)
	# Settings safety part 3: the bar's notches carry their danger zone, and a
	# risky setting gets a consequence line under it that follows the value.
	var path: String = s.paths[0] if s.kind == "range" else ""
	if path != "":
		for n in TunerModel.NOTCHES:
			bar.zones.append(SettingDanger.level(path, _notch_value(s, n)))
	var line: Label = null
	if SettingDanger.LINES.has(path):
		line = _label("", DIM)
		line.add_theme_font_size_override("font_size", 13)
		line.custom_minimum_size = Vector2(0, 0)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 178)
		pad.add_child(line)
		block.add_child(pad)
	return {"setting": s, "name": name, "value": value, "rel": rel, "bar": bar, "line": line, "path": path, "node": block}

## The last row of every settings page: Right or Enter on it puts the page back
## to stock (settings safety part 4). Other pages stay as they are.
const RESET_ROW := {"id": "_reset", "kind": "reset", "label": "Reset page to stock",
	"hint": "Puts every setting on this page back to how the car left the factory. The other pages stay as they are."}

func _add_reset_row() -> Dictionary:
	var name := _label(RESET_ROW.label, SILVER)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_child(name)
	content.add_child(pad)
	return {"setting": RESET_ROW, "name": name, "node": pad}

## Resets the page on screen; true if anything changed.
func reset_current_page() -> bool:
	if not model.reset_page(current_page()):
		return false
	manual.refresh_from_player()
	auto.refresh_lock_labels()
	_refresh()
	return true

static func _notch_value(s: Dictionary, n: int) -> float:
	var t := float(n) / float(TunerModel.NOTCHES - 1)
	return lerpf(s.lo, s.hi, 1.0 - t if s.invert else t)

# ---------- keyboard ----------

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	if game_state.typing_in_text():
		return  # a text box has the keys (tune slot names)
	var key: int = (event as InputEventKey).keycode
	match key:
		KEY_Q:
			show_page(page_ids[(page_index + page_ids.size() - 1) % page_ids.size()])
		KEY_E:
			show_page(page_ids[(page_index + 1) % page_ids.size()])
		_:
			if rows.is_empty():
				return  # panel pages: their own controls take the arrows
			match key:
				KEY_UP: row_index = maxi(row_index - 1, 0)
				KEY_DOWN: row_index = mini(row_index + 1, rows.size() - 1)
				KEY_LEFT: _nudge(-1)
				KEY_RIGHT: _nudge(1)
				KEY_ENTER, KEY_KP_ENTER:
					if rows[row_index].setting.kind != "reset":
						return
					_nudge(1)
				_: return
			_refresh()
	get_viewport().set_input_as_handled()

func _nudge(step: int) -> void:
	if rows[row_index].setting.kind == "reset":
		if step > 0:
			reset_current_page()
		return
	if model.nudge(rows[row_index].setting, step):
		manual.refresh_from_player()
		auto.refresh_lock_labels()

# ---------- test run ----------

## Drives the current setup once round the hidden test track (an Auto-Tune job
## with everything locked: it measures the starting tune and stops) and swaps
## the estimates for measured numbers.
func start_test_run() -> void:
	if test_running():
		cancel_test_run("Test run cancelled")
		return
	var locks := {}
	for p in TuneParams.auto_paths():
		locks[p] = true
	test_job = AutoTuneJob.new()
	var options := {"trace": true}
	if stock_run.is_empty():
		options.stock = CarSpec.clone_spec(model.stock)
	if not test_job.start(CarSpec.clone_spec(player.spec), {"goals": {"accel": 1.0}, "locks": locks}, 1, options):
		test_button.text = "Test run failed"
		return
	_test_hash = player.spec.hash()
	_test_started_ms = Time.get_ticks_msec()
	test_button.text = "Testing... (cancel)"

func test_running() -> bool:
	return test_job != null and test_job.state == AutoTuneJob.State.RUNNING

## Kills a running test run and says why on the button.
func cancel_test_run(why: String) -> void:
	if not test_running():
		return
	test_job.cancel()
	test_button.text = why

func _process(delta: float) -> void:
	if visible and current_page() == "mechanic":
		_ticket_poll += delta
		if _ticket_poll > 0.25:  # the job ticket follows the mechanic's laps
			_ticket_poll = 0.0
			_refresh_graphic(TunerModel.estimate(player.spec))
	if visible and bench != null and car_window != null:
		var r := car_window.get_global_rect()
		if graphic_plate.visible:
			r.size.x -= GRAPHIC_W + 8.0  # frame the car beside the graphic
		bench.frame_rect = r
	if not test_running():
		return
	if Time.get_ticks_msec() - _test_started_ms > test_timeout_s * 1000.0:
		cancel_test_run("Test run timed out")
		return
	_test_poll += delta
	if _test_poll < 0.25:
		return
	_test_poll = 0.0
	var st := test_job.poll()
	if st == AutoTuneJob.State.RUNNING:
		return
	test_button.text = "Test run"
	if st == AutoTuneJob.State.DONE and not test_job.result.base_metrics.is_empty():
		stats.measured = test_job.result.base_metrics
		if test_job.result.has("stock_metrics"):
			stock_run = test_job.result.stock_metrics
		stats.measured_for = _test_hash  # changed meanwhile: _refresh drops it again
		_refresh()
	else:
		test_button.text = "Test run failed"

## The Grip to Drift dial moved: the setup becomes stock blended toward Grip or
## Drift by that much (TunerModel.set_character).
func _on_character(v: float) -> void:
	model.set_character(roundi(v))
	manual.refresh_from_player()
	auto.refresh_lock_labels()
	_refresh()

## Setup sheets A-C: three fixed tune slots, shared with the Mechanic's list.
func save_sheet(sheet: String) -> void:
	auto.slots.save(sheet, player.spec)
	auto._refresh_slots()
	_refresh()

func load_sheet(sheet: String) -> bool:
	if not auto.slots.apply(sheet, player):
		return false
	model.preset = sheet
	model.modified = false
	manual.refresh_from_player()
	exhaust.refresh()
	auto.refresh_lock_labels()
	_refresh()
	return true

func _on_preset(name: String) -> void:
	model.apply_preset(name)
	manual.refresh_from_player()
	exhaust.refresh()
	auto.refresh_lock_labels()
	_refresh()

func _on_panel_changed() -> void:
	model.modified = true
	auto.refresh_lock_labels()
	_refresh()

func _on_auto_changed() -> void:
	model.modified = true
	manual.refresh_from_player()
	exhaust.refresh()
	_refresh()

# ---------- drawing ----------

func _refresh() -> void:
	preset_label.text = "Setup: " + model.preset_label()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var s: Dictionary = r.setting
		var focused := i == row_index
		r.name.text = ("> " if focused else "  ") + s.label
		r.name.add_theme_color_override("font_color", SODIUM if focused else SILVER)
		if s.kind == "reset":
			continue
		r.value.text = model.value_text(s)
		var rel_text := model.relative_text(s)
		r.rel.text = "" if rel_text == r.value.text else rel_text
		r.rel.add_theme_color_override("font_color", TunerColours.STOCK if rel_text == "Stock" else DIM)
		var danger := SettingDanger.Level.GREEN
		if r.path != "":
			var v := TuneParams.get_value(player.spec, r.path)
			danger = SettingDanger.level(r.path, v)
			if r.line != null:
				r.line.text = SettingDanger.consequence(r.path, v, TuneParams.get_value(model.stock, r.path))
				r.line.add_theme_color_override("font_color", DIM if danger == SettingDanger.Level.GREEN else SettingDanger.colour(danger))
		r.value.add_theme_color_override("font_color", AMBER if danger == SettingDanger.Level.GREEN else SettingDanger.colour(danger))
		r.bar.now = model.notch(s)
		r.bar.before = before_notches.get(s.id, r.bar.now)
		r.bar.focused = focused
		r.bar.queue_redraw()
	var page := TunerModel.page(current_page())
	if not rows.is_empty():
		hint.text = rows[row_index].setting.hint
		hint.visible = false
		# the hint sits right under the focused row, where the eye already is
		var holder: Node = row_hint.get_parent()
		content.move_child(holder, mini(rows[row_index].node.get_index() + 1, content.get_child_count() - 1))
		row_hint.text = hint.text
	else:
		hint.visible = true
		hint.text = {
			"setup": "Presets and the Grip to Drift dial start from stock: pick one, then change anything you like. Save a setup to a sheet to come back to it.",
			"mechanic": "The mechanic tries setups on a closed track and keeps what scores best for your goals.",
			"sound": "How the exhaust sounds, and the flames. Purely cosmetic.",
			"advanced": "Every raw number, out to the extremes: gearing, power, tyres, suspension, diff, brakes, aero, assists.",
		}.get(page.id, "")
	if stats.measured_for != player.spec.hash():
		stats.measured = {}  # measured on a setup the car no longer has
	stats.measured_for = player.spec.hash()
	stats.stock = TunerModel.estimate(model.stock)
	if character_slider != null:
		character_slider.set_value_no_signal(model.character)
		for sheet in SHEETS:
			sheet_labels[sheet].text = "%s  %s" % [sheet.right(1), "saved" if auto.slots.has(sheet) else "empty"]
	var est := TunerModel.estimate(player.spec)
	stats.set_values(before_stats, est)
	_refresh_graphic(est)
	var flip := stats.measured.has("trace") and stock_run.has("trace")
	stats.visible = not flip
	pit_wall.visible = flip
	if flip:
		pit_wall.show_result(stats.measured, stock_run)

## Hands the page graphic the car's setup, stock, and the next notch of the
## focused setting; the performance card shows that next notch too.
func _refresh_graphic(est: Dictionary) -> void:
	var preview := {}
	var focus: Dictionary = rows[row_index].setting if not rows.is_empty() else {}
	if not focus.is_empty() and focus.kind != "reset":
		var probe_spec := CarSpec.clone_spec(player.spec)
		var probe := TunerModel.new(null, probe_spec, model.stock)
		if probe.nudge(focus, 1):
			preview = probe_spec
	var preview_est := TunerModel.estimate(preview) if not preview.is_empty() else {}
	stats.set_preview(est, preview_est, String(focus.get("label", "")))
	var g: PageGraphic = graphics.get(current_page())
	if g == null:
		return
	var compound := model.choice_index(TunerModel.page("tyres").settings[0])
	var goal_name := ""
	for gl in MechanicPanel.GOALS:
		if gl[0] == mechanic.goal:
			goal_name = gl[1]
	var job: AutoTuneJob = auto._job
	g.show_setup(player.spec, model.stock, {
		"character": model.character, "label": model.preset_label(), "goal": goal_name, "running": auto.running,
		"done": int(job.progress.done) if job != null else 0, "total": int(job.progress.total) if job != null else 0,
		"result": auto.result if not auto.running else {},
		"preview": preview, "focus": focus.get("id", ""), "est": est, "stock_est": stats.stock,
		"preview_est": preview_est, "wheel_r": PlayerCar.CFG.wheel_r, "compound": compound,
		"auto_bias": player.front_axle.brake_bias if player.is_ready else 0.55,
	})

# ---------- small drawn widgets ----------

## An 11-notch bar (or one segment per choice): filled up to "now" in sodium
## orange, a dim tick where the setting was when the screen opened. With zones
## (one SettingDanger.Level per notch) each notch has a strip along its top in
## green, amber or red, so the bar reads green to red toward its risky ends.
class NotchBar extends Control:
	const ZONE_STRIP := 3.0
	var choices := 11
	var now := 0
	var before := 0
	var focused := false
	var zones: Array = []
	## The car's stock notch: a steel-blue frame round it (-1 = none).
	var stock := -1

	func _draw() -> void:
		var gap := 2.0
		var w := (size.x - gap * (choices - 1)) / choices
		for i in choices:
			var r := Rect2(i * (w + gap), 0.0, w, size.y)
			var on := i == now if choices <= 4 else i <= now
			var c := TunerScreen.SODIUM if on else Color(TunerScreen.NAVY_LIGHT, 1.0)
			if on and not focused:
				c = TunerScreen.AMBER
			draw_rect(r, c)
			if i < zones.size():
				var zc := SettingDanger.colour(zones[i])
				zc.a = 1.0 if i == now else 0.55
				draw_rect(Rect2(r.position, Vector2(w, ZONE_STRIP)), zc)
			if i == before and before != now:
				draw_rect(Rect2(r.position.x, size.y - 3.0, w, 3.0), TunerScreen.SILVER)
			if i == stock:
				draw_rect(r.grow(1.0), TunerColours.STOCK, false, 2.0)

## The pit-wall result of a Test run: speed trace of this run over the stock run,
## throttle and brake strips under it, and a delta column against stock.
class PitWall extends VBoxContainer:
	## [metric key, name, value format, delta format, +1 if higher is better]
	const ROWS := [
		["top_speed_kmh", "Top", "%.0f km/h", "%+.1f", 1],
		["t_0_100", "0-100", "%.2f s", "%+.2f", -1],
		["brake_dist_100", "100-0", "%.1f m", "%+.1f", -1],
		["peak_lat_g", "Grip", "%.2f g", "%+.2f", 1],
	]
	var trace: SpeedTrace
	var values := {}   # metric key -> Label (name and value)
	var deltas := {}   # metric key -> Label (signed delta and arrow)
	## The result in words under the numbers (UI overhaul PR 4).
	var verdict: Label

	func _ready() -> void:
		add_theme_constant_override("separation", 4)
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		var title := Label.new()
		title.text = "TEST RUN VS STOCK"
		title.add_theme_color_override("font_color", TunerScreen.SILVER)
		add_child(title)
		var what := Label.new()
		what.text = "Launch to 100, then full brakes"
		what.add_theme_color_override("font_color", TunerScreen.DIM)
		add_child(what)
		trace = SpeedTrace.new()
		trace.custom_minimum_size = Vector2(0, 130)
		add_child(trace)
		for r in ROWS:
			var h := HBoxContainer.new()
			add_child(h)
			var v := Label.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_theme_font_override("font", mono)
			v.add_theme_color_override("font_color", TunerScreen.SILVER)
			h.add_child(v)
			values[r[0]] = v
			var d := Label.new()
			d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			d.add_theme_font_override("font", mono)
			h.add_child(d)
			deltas[r[0]] = d
		verdict = Label.new()
		verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		verdict.custom_minimum_size = Vector2(230, 0)
		verdict.add_theme_color_override("font_color", TunerScreen.AMBER)
		add_child(verdict)

	## `mine` and `stock` are Test run metrics, each with its trace.
	## The Test run against stock in one or two plain sentences: what got
	## better, what got worse, what stayed the same.
	static func verdict_words(mine: Dictionary, stock: Dictionary) -> String:
		var better := []
		var worse := []
		var same := []
		var phrase := {
			"t_0_100": ["quicker to 100 by %.2f s", "slower to 100 by %.2f s", "0-100", 0.02],
			"top_speed_kmh": ["%.0f km/h more top speed", "%.0f km/h less top speed", "top speed", 0.5],
			"brake_dist_100": ["stops %.1f m shorter", "stops %.1f m longer", "braking", 0.2],
			"peak_lat_g": ["%.2f g more grip", "%.2f g less grip", "grip", 0.01],
		}
		for r in ROWS:
			var k: String = r[0]
			if not mine.has(k) or not stock.has(k):
				continue
			var d := float(mine[k]) - float(stock[k])
			var p: Array = phrase[k]
			if absf(d) < p[3]:
				same.append(p[2])
			elif (d > 0.0) == (r[4] > 0):
				better.append(p[0] % absf(d))
			else:
				worse.append(p[1] % absf(d))
		var out := []
		if not better.is_empty():
			out.append(_join(better).capitalize().left(1) + _join(better).substr(1) + ".")
		if not worse.is_empty():
			out.append("But " + _join(worse) + ".")
		if better.is_empty() and worse.is_empty():
			out.append("Same as stock on the test track.")
		elif not same.is_empty():
			out.append(_join(same).left(1).to_upper() + _join(same).substr(1) + " the same.")
		return " ".join(out)

	static func _join(parts: Array) -> String:
		if parts.size() <= 1:
			return "".join(parts)
		return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + str(parts[-1])

	func show_result(mine: Dictionary, stock: Dictionary) -> void:
		verdict.text = verdict_words(mine, stock)
		trace.mine = mine.trace
		trace.stock = stock.trace
		trace.queue_redraw()
		for r in ROWS:
			var k: String = r[0]
			if not mine.has(k) or not stock.has(k):
				values[k].text = "%-6s --" % r[1]
				deltas[k].text = ""
				continue
			var d := float(mine[k]) - float(stock[k])
			values[k].text = "%-6s %s" % [r[1], r[2] % float(mine[k])]
			# Below the shown precision counts as level: "stock", no arrow.
			var res := TunerColours.delta(d, r[4] > 0, r[3])
			deltas[k].text = res.text
			deltas[k].add_theme_color_override("font_color", res.colour)

	## Speed against time, both runs on the same scale, then the throttle and
	## brake strips of this run.
	class SpeedTrace extends Control:
		const STRIP := 5.0
		var mine := {}
		var stock := {}

		func _draw() -> void:
			if mine.is_empty() or stock.is_empty():
				return
			var plot_h := size.y - 2.0 * (STRIP + 3.0)
			draw_rect(Rect2(0.0, 0.0, size.x, plot_h), TunerScreen.NAVY_LIGHT)
			var n := maxi(mine.speed.size(), stock.speed.size())
			var top := 110.0
			for v in mine.speed + stock.speed:
				top = maxf(top, float(v) * 1.08)
			for kmh: float in [50.0, 100.0]:  # grid lines
				var y := plot_h * (1.0 - kmh / top)
				draw_line(Vector2(0.0, y), Vector2(size.x, y), TunerScreen.DIM, 1.0)
			_line(stock.speed, n, top, plot_h, TunerColours.STOCK)
			_line(mine.speed, n, top, plot_h, TunerColours.YOURS)
			var w := size.x / maxf(n - 1, 1)
			for i in mine.speed.size():
				var x := float(i) * w
				var t: float = mine.throttle[i]
				var b: float = mine.brake[i]
				if t > 0.0:
					draw_rect(Rect2(x, plot_h + 3.0, w + 0.5, STRIP), Color(TunerScreen.AMBER, t))
				if b > 0.0:
					draw_rect(Rect2(x, plot_h + STRIP + 6.0, w + 0.5, STRIP), Color(TunerScreen.SODIUM, b))

		func _line(speed: Array, n: int, top: float, h: float, c: Color) -> void:
			var pts := PackedVector2Array()
			for i in speed.size():
				pts.append(Vector2(size.x * i / maxf(n - 1, 1), h * (1.0 - float(speed[i]) / top)))
			if pts.size() >= 2:
				draw_polyline(pts, c, 2.0, true)
