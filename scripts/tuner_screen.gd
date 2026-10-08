class_name TunerScreen
extends CanvasLayer

# The Tuner (Tuner redesign PR 3, 2026-10-06; proposal approved by Roy, see
# docs/planning/tuner-redesign-proposal-2026-10-06.md). T opens it on Setup, Y on
# Mechanic, Esc closes; the game is paused while it is open (GameState.TUNING /
# AUTOTUNE).
#
#   +------------+------------------------------+-------------+
#   | page list  | the page: notch bars or a    | stat panel  |
#   |            | panel (Mechanic, Sound, Adv) | before/now  |
#   +------------+------------------------------+-------------+
#   | hint: what the focused setting does                      |
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

const NAVY := Color("#0E1424")
const NAVY_LIGHT := Color("#1B2A4A")
const SILVER := Color("#C9CED6")
const DIM := Color(0.79, 0.81, 0.84, 0.35)
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const MARGIN := 16

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

var page_ids: Array[String] = []
var page_index := 0
var row_index := 0
var page_labels: Array[Label] = []
var page_title: Label
var preset_label: Label
var car_label: Label
var hint: Label
var content: VBoxContainer   # rows of the current settings page
var panel_pages := {}        # page id -> Control (Setup, Mechanic, Sound, Advanced)
var rows: Array = []         # [{setting, name, value, bar}] on a settings page
var preset_buttons: Array[Button] = []
var stats: TunerStats
## Notches and stats when the screen opened, shown as ghosts.
var before_notches := {}
var before_stats := {}

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
	frame.offset_left = MARGIN
	frame.offset_top = 8
	frame.offset_right = -MARGIN
	frame.offset_bottom = -MARGIN
	frame.theme = UiTheme.get_theme()  # job sheet: shared plates, slabs and fonts (UI blend PR 2)
	var bg := UiTheme.plate_panel()  # near-opaque: bright buildings behind made the text unreadable
	bg.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", bg)
	add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
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
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)

	var page_list := VBoxContainer.new()
	page_list.custom_minimum_size = Vector2(130, 0)
	body.add_child(page_list)
	for p in TunerModel.pages():
		var l := _label(p.title, SILVER)
		page_list.add_child(l)
		page_labels.append(l)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(middle)
	page_title = _label("", SODIUM)
	middle.add_child(page_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	middle.add_child(scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	holder.add_child(content)

	# Panel pages, built once and shown/hidden.
	var setup := VBoxContainer.new()
	setup.add_theme_constant_override("separation", 6)
	setup.add_child(_label("Presets start from the car's stock setup. Pick one, then change anything you like.", SILVER))
	for name in TunerModel.PRESETS:
		var b := Button.new()
		b.text = name
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(_on_preset.bind(name))
		setup.add_child(b)
		preset_buttons.append(b)
	setup.add_child(_label("Saved setups live on the Mechanic page for now.", DIM))
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

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(250, 0)
	body.add_child(right)
	stats = TunerStats.new()
	right.add_child(stats)
	test_button = Button.new()
	test_button.text = "Test run"
	test_button.focus_mode = Control.FOCUS_ALL
	test_button.pressed.connect(start_test_run)
	right.add_child(test_button)

	hint = _label("", SILVER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 44)
	column.add_child(hint)

	manual.tune_changed.connect(_on_panel_changed)
	auto.tune_changed.connect(_on_auto_changed)
	game_state.state_changed.connect(_on_state_changed)

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
		show_page("mechanic" if new_state == GameState.State.AUTOTUNE else "setup")
	else:
		# Sliders and buttons keep keyboard focus otherwise and eat the arrow keys.
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

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
	return {"setting": s, "name": name, "value": value, "bar": bar, "line": line, "path": path}

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
	return {"setting": RESET_ROW, "name": name}

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
	if not test_job.start(CarSpec.clone_spec(player.spec), {"goals": {"accel": 1.0}, "locks": locks}, 1):
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
		stats.measured_for = _test_hash  # changed meanwhile: _refresh drops it again
		_refresh()
	else:
		test_button.text = "Test run failed"

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
	else:
		hint.text = {
			"setup": "Stock: as it left the factory. Street: forgiving and comfortable. Grip: fast laps. Drift: easy slides.",
			"mechanic": "The mechanic tries setups on a closed track and keeps what scores best for your goals.",
			"sound": "How the exhaust sounds, and the flames. Purely cosmetic.",
			"advanced": "Every raw number, out to the extremes: gearing, power, tyres, suspension, diff, brakes, aero, assists.",
		}.get(page.id, "")
	if stats.measured_for != player.spec.hash():
		stats.measured = {}  # measured on a setup the car no longer has
	stats.measured_for = player.spec.hash()
	stats.stock = TunerModel.estimate(model.stock)
	stats.set_values(before_stats, TunerModel.estimate(player.spec))

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

## Right-hand stat panel: before (dim) and now (orange) bars with the change.
class TunerStats extends VBoxContainer:
	const ROWS := [
		["top", "Top speed", "~%d km/h", 150.0, 320.0, false],
		["accel", "0-100", "~%.1f s", 10.0, 2.5, false],
		["brake", "100-0", "~%d m", 60.0, 25.0, false],
		["grip", "Grip", "~%.2f g", 0.8, 2.0, false],
		["balance", "Balance", "%s", -1.0, 1.0, true],
	]
	var labels := {}
	var bars := {}
	## "vs stock" column: signed difference from the car's factory setup.
	var vs := {}
	var stock := {}
	## Track numbers from a Test run, for the setup they were measured on; any
	## change to the car clears them back to estimates.
	var measured := {}
	var measured_for := 0

	func _ready() -> void:
		add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		add_child(head)
		var title := UiTheme.title_label("DYNO SHEET", 26, UiTheme.AMBER)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var vs_head := Label.new()
		vs_head.text = "VS STOCK"
		vs_head.add_theme_font_override("font", UiTheme.font("mono"))
		vs_head.add_theme_color_override("font_color", TunerScreen.DIM)
		head.add_child(vs_head)
		add_child(UiTheme.floor_tape())
		for r in ROWS:
			var line := HBoxContainer.new()
			add_child(line)
			var l := Label.new()
			l.add_theme_color_override("font_color", TunerScreen.SILVER)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(l)
			var d := Label.new()
			d.add_theme_font_override("font", UiTheme.font("mono"))
			line.add_child(d)
			vs[r[0]] = d
			labels[r[0]] = l
			var b := StatBar.new()
			b.custom_minimum_size = Vector2(0, 12)
			b.centred = r[5]
			add_child(b)
			bars[r[0]] = b
		var note := Label.new()
		note.text = "~ = estimate"
		note.add_theme_color_override("font_color", TunerScreen.DIM)
		add_child(note)

	func set_values(before: Dictionary, now: Dictionary) -> void:
		if labels.is_empty() or now.is_empty():
			return
		for r in ROWS:
			var k: String = r[0]
			var v: float = now[k]
			var b: float = before.get(k, v)
			var text: String
			if k == "balance":
				text = "Understeer" if v < -0.15 else ("Oversteer" if v > 0.15 else "Neutral")
				text = "%s  %s" % [r[1], text]
			elif _measured_value(k) != null:
				v = _measured_value(k)
				text = "%s  %s" % [r[1], (r[2] as String).replace("~", "") % v]
			else:
				text = "%s  %s" % [r[1], r[2] % v]
				var d := v - b
				if absf(d) > 0.005 * maxf(absf(b), 1.0):
					text += ("   %+.0f" if k == "top" or k == "brake" else "   %+.2f") % d
			labels[k].text = text
			_set_vs(k, float(now[k]))
			bars[k].now = inverse_lerp(r[3], r[4], v)
			bars[k].before = inverse_lerp(r[3], r[4], b)
			bars[k].queue_redraw()

	## Signed delta against the stock estimate; amber up-arrow = better, dim down-arrow = worse.
	func _set_vs(k: String, v: float) -> void:
		var d: Label = vs[k]
		if k == "balance" or not stock.has(k):
			d.text = ""
			return
		var diff: float = v - float(stock[k])
		var lower_is_better: bool = k == "accel" or k == "brake"
		var step: float = 0.5 if k == "top" else (0.05 if k == "grip" else 0.05)
		if k == "brake":
			step = 0.5
		if absf(diff) < step:
			d.text = "stock"
			d.add_theme_color_override("font_color", TunerScreen.DIM)
			return
		var better: bool = (diff < 0.0) == lower_is_better
		var fmt: String = "%+.0f" if (k == "top" or k == "brake") else "%+.2f"
		d.text = (fmt % diff) + (" ▲" if better else " ▼")
		d.add_theme_color_override("font_color", TunerScreen.AMBER if better else TunerScreen.DIM)

	func _measured_value(k: String) -> Variant:
		var key: String = {"top": "top_speed_kmh", "accel": "t_0_100", "brake": "brake_dist_100", "grip": "peak_lat_g"}.get(k, "")
		return float(measured[key]) if key != "" and measured.has(key) else null

	class StatBar extends Control:
		var now := 0.5
		var before := 0.5
		var centred := false

		func _draw() -> void:
			draw_rect(Rect2(Vector2.ZERO, size), TunerScreen.NAVY_LIGHT)
			var n := clampf(now, 0.0, 1.0)
			var b := clampf(before, 0.0, 1.0)
			if centred:
				var mid := size.x * 0.5
				draw_rect(Rect2(mid - 1.0, 0.0, 2.0, size.y), TunerScreen.DIM)
				draw_rect(Rect2(size.x * n - 3.0, 0.0, 6.0, size.y), TunerScreen.SODIUM)
				draw_rect(Rect2(size.x * b - 1.0, size.y - 3.0, 2.0, 3.0), TunerScreen.SILVER)
				return
			draw_rect(Rect2(0.0, 0.0, size.x * b, size.y), TunerScreen.DIM)
			draw_rect(Rect2(0.0, 2.0, size.x * n, size.y - 4.0), TunerScreen.SODIUM)
