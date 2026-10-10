class_name AutoTunePanel
extends VBoxContainer

# Auto-Tune panel (step 6), the collapsible add-on section of the Tuner screen
# (scripts/ui/tuner_screen.gd). Y opens the screen with this section expanded
# (GameState.AUTOTUNE, game paused), T collapses it, Esc closes the screen. Pick what to improve (goals, weight 0-3),
# lock what must not change, press Run; the search runs in a separate headless
# Godot process (AutoTuneJob) on the hidden test track and offers the best
# verified tune with before/after numbers. Apply writes it through
# CarSpec.set_param(), the same path as the raw T panel, which is unchanged.
#
# Debug tool, deliberately plain Godot default controls, like the raw panel.

## The car's tune changed (Apply, Undo, a loaded slot): the sliders next to this
## section show the old values until they are told to refresh.
signal tune_changed

const BUDGETS := [["Quick (30 runs)", 30], ["Normal (60 runs)", 60], ["Thorough (120 runs)", 120]]
const DEFAULT_BUDGET := 1
const MAX_WEIGHT := 3
const POLL_SECS := 0.25

var player: PlayerCar
var game_state: GameState

var goal_sliders := {}      # goal -> HSlider
var goal_labels := {}       # goal -> Label
var lock_boxes := {}        # path -> CheckBox
var budget_option: OptionButton
var run_button: Button
var cancel_button: Button
var apply_button: Button
var undo_button: Button
var status_label: Label
var result_label: Label
var slot_name_edit: LineEdit
var discard_button: Button
## The goal sliders, search length and per-parameter locks: the Tuner screen's
## Mechanic page hides them behind its Advanced box (Tuner redesign PR 4) and
## drives them from its own simple controls. Shown when the panel stands alone.
var advanced_parts: Array[Control] = []
var advanced := true
var slot_list: ItemList
var save_button: Button
var load_button: Button
var delete_button: Button

## Named tune slots (step 7). Tests swap in one on a scratch file.
var slots := TuneSlots.new()

## Tests set this to run a smaller search than the Quick option.
var budget_override := 0

var running := false
var result := {}                 # the finished job's result, until applied
var undo_spec := {}              # the spec before the last Apply

var _job: AutoTuneJob
var _since_poll := 0.0
var _run_started_msec := 0

func _init(car: PlayerCar, state: GameState) -> void:
	player = car
	game_state = state

func _ready() -> void:
	theme = UiTheme.font_theme()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	add_child(columns)

	# --- left: goals, budget, buttons ---
	var left := VBoxContainer.new()
	columns.add_child(left)
	var goals_heading := _heading("Goals (0 = off)")
	left.add_child(goals_heading)
	var grid := GridContainer.new()
	grid.columns = 3
	left.add_child(grid)
	advanced_parts.append_array([goals_heading, grid])
	for goal in AutoTuneRules.GOALS:
		var l := Label.new()
		l.text = AutoTuneRules.GOALS[goal].label
		grid.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = MAX_WEIGHT
		s.step = 1
		s.custom_minimum_size = Vector2(120, 0)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_goal_changed.bind(goal))
		grid.add_child(s)
		goal_sliders[goal] = s
		var v := Label.new()
		UiTheme.apply(v, "numbers")
		v.custom_minimum_size = Vector2(36, 0)
		grid.add_child(v)
		goal_labels[goal] = v
		_on_goal_changed(0, goal)
	budget_option = OptionButton.new()
	for b in BUDGETS:
		budget_option.add_item(b[0])
	budget_option.select(DEFAULT_BUDGET)
	left.add_child(budget_option)
	advanced_parts.append(budget_option)
	var row := HBoxContainer.new()
	left.add_child(row)
	run_button = _button(row, "Run", _on_run)
	cancel_button = _button(row, "Cancel", _on_cancel)
	apply_button = _button(row, "Apply", _on_apply)
	discard_button = _button(row, "Discard", _on_discard)
	undo_button = _button(row, "Undo apply", _on_undo)
	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(320, 0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(status_label)

	# --- tune slots: save / load the whole tune by name ---
	left.add_child(_heading("Tune slots (whole tune, engine included)"))
	var save_row := HBoxContainer.new()
	left.add_child(save_row)
	slot_name_edit = LineEdit.new()
	slot_name_edit.placeholder_text = "slot name"
	slot_name_edit.max_length = TuneSlots.MAX_NAME_LENGTH
	slot_name_edit.custom_minimum_size = Vector2(180, 0)
	slot_name_edit.gui_input.connect(_on_slot_name_input)
	slot_name_edit.text_submitted.connect(func(_t: String) -> void:
		_on_save_slot()
		slot_name_edit.release_focus())
	save_row.add_child(slot_name_edit)
	save_button = _button(save_row, "Save", _on_save_slot)
	slot_list = ItemList.new()
	slot_list.custom_minimum_size = Vector2(0, 84)
	slot_list.item_selected.connect(_on_slot_selected)
	left.add_child(slot_list)
	var slot_row := HBoxContainer.new()
	left.add_child(slot_row)
	load_button = _button(slot_row, "Load", _on_load_slot)
	delete_button = _button(slot_row, "Delete", _on_delete_slot)

	# --- middle: locks ---
	var mid := VBoxContainer.new()
	columns.add_child(mid)
	advanced_parts.append(mid)
	mid.add_child(_heading("Lock (never changed)"))
	var locks := GridContainer.new()
	locks.columns = 2
	mid.add_child(locks)
	for path in TuneParams.auto_paths():
		var cb := CheckBox.new()
		cb.text = TuneParams.find(path).label
		locks.add_child(cb)
		lock_boxes[path] = cb

	# --- below: result ---
	result_label = Label.new()
	result_label.add_theme_font_override("font", _mono_font())
	result_label.custom_minimum_size = Vector2(420, 0)
	add_child(result_label)

	game_state.state_changed.connect(_on_state_changed)
	_refresh_slots()
	_refresh_buttons()

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.79, 0.81, 0.84))  # silver #C9CED6
	return l

func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _mono_font() -> Font:
	return UiTheme.font("numbers")

# ---------- open / close ----------

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	if GameState.is_tuner(new_state):
		refresh_lock_labels()
		_refresh_buttons()
	elif GameState.is_tuner(old_state) and running:
		_on_cancel()  # leaving the Tuner screen stops the search

# ---------- request ----------

func _on_goal_changed(value: float, goal: String) -> void:
	goal_labels[goal].text = "off" if value < 1.0 else "x%d" % int(value)

## The request the UI currently describes (see AutoTuneRules).
func request() -> Dictionary:
	var goals := {}
	for goal in goal_sliders:
		if goal_sliders[goal].value >= 1.0:
			goals[goal] = goal_sliders[goal].value
	var locks := {}
	for path in lock_boxes:
		if lock_boxes[path].button_pressed:
			locks[path] = true
	return {"goals": goals, "locks": locks}

func budget() -> int:
	return budget_override if budget_override > 0 else BUDGETS[budget_option.selected][1]

## The Lock checkboxes show the car's current value; the Tuner screen calls this
## when the gearing sliders change it.
func refresh_lock_labels() -> void:
	for path in lock_boxes:
		var e := TuneParams.find(path)
		lock_boxes[path].text = "%s  %.2f" % [e.label, TuneParams.get_value(player.spec, path)]

func _refresh_buttons() -> void:
	run_button.disabled = running
	cancel_button.disabled = not running
	apply_button.disabled = running or not result.get("improved", false)
	discard_button.disabled = running or result.is_empty()
	undo_button.disabled = running or undo_spec.is_empty()
	budget_option.disabled = running
	var picked := not slot_list.get_selected_items().is_empty()
	load_button.disabled = running or not picked
	delete_button.disabled = not picked
	save_button.disabled = running

# ---------- run ----------

func _on_run() -> void:
	if running:
		return
	var req := request()
	if AutoTuneRules.active_goals(req).is_empty():
		status_label.text = "Pick at least one goal (slider above 0)."
		return
	result = {}
	result_label.text = ""
	_job = AutoTuneJob.new()
	if not _job.start(CarSpec.clone_spec(player.spec), req, budget()):
		status_label.text = _job.error
		_refresh_buttons()
		return
	running = true
	_since_poll = 0.0
	_run_started_msec = Time.get_ticks_msec()
	status_label.text = "Starting the search..."
	_refresh_buttons()

func _process(delta: float) -> void:
	if not running:
		return
	_since_poll += delta
	if _since_poll < POLL_SECS:
		return
	_since_poll = 0.0
	_poll()

## One look at the job. Public so tests can drive it without waiting for _process.
func _poll() -> void:
	var st := _job.poll()
	if st == AutoTuneJob.State.RUNNING:
		var p := _job.progress
		status_label.text = "Searching... %d / %d runs, best so far %+.1f%%" % [int(p.done), int(p.total), float(p.best) * 100.0]
		return
	running = false
	if st == AutoTuneJob.State.DONE:
		result = _job.result
		var secs := (Time.get_ticks_msec() - _run_started_msec) / 1000.0
		status_label.text = "Done: %d runs in %.0f s." % [int(result.evals), secs]
		result_label.text = _result_text(result) if advanced else plain_result_text(result)
	elif st == AutoTuneJob.State.FAILED:
		status_label.text = "Search failed: %s" % _job.error
	_refresh_buttons()

func _on_cancel() -> void:
	if not running:
		return
	_job.cancel()
	running = false
	status_label.text = "Cancelled."
	_refresh_buttons()

# ---------- result ----------

func _result_text(res: Dictionary) -> String:
	var lines: Array[String] = []
	var b: Dictionary = res.base_metrics
	if not res.improved:
		for n in res.notes:
			lines.append(n)
		lines.append("Nothing changed.")
		var rejected := false
		for v in res.verified:
			if not rejected:
				lines.append("")
				lines.append("Tried and rejected:")
				rejected = true
			lines.append("  %s" % v.why)
		return "\n".join(lines)
	var m: Dictionary = res.metrics
	lines.append("                 before   after")
	lines.append("Top speed km/h  %7.1f %7.1f" % [b.top_speed_kmh, m.top_speed_kmh])
	lines.append("0-100 km/h  s   %7.2f %7.2f" % [b.t_0_100, m.t_0_100])
	lines.append("100-0 km/h  m   %7.1f %7.1f" % [b.brake_dist_100, m.brake_dist_100])
	lines.append("Peak lateral g  %7.2f %7.2f" % [b.peak_lat_g, m.peak_lat_g])
	lines.append("")
	lines.append("Score %+.1f%% on your goals. Changes:" % (float(res.score) * 100.0))
	for p in TuneParams.auto_paths():
		var old := TuneParams.get_value(player.spec, p)
		var now := float(res.values[p])
		if absf(old - now) > 1e-9:
			lines.append("  %-22s %.3f -> %.3f" % [TuneParams.find(p).label, old, now])
	var ok_count := 0
	for v in res.verified:
		if v.accepted:
			ok_count += 1
	lines.append("")
	lines.append("Verified on the full track: %d of %d candidates passed." % [ok_count, res.verified.size()])
	return "\n".join(lines)

func _on_apply() -> void:
	if running or not result.get("improved", false):
		return
	undo_spec = CarSpec.clone_spec(player.spec)
	_write(_job.result_spec(player.spec))
	status_label.text = "Applied. The car now drives with this tune."
	result = {}
	result_label.text = ""
	refresh_lock_labels()
	_refresh_buttons()

func _on_discard() -> void:
	if running:
		return
	result = {}
	result_label.text = ""
	status_label.text = "Discarded. The car is as it was."
	_refresh_buttons()

## Shows or hides the raw controls (goal weights, search length, per-parameter
## locks) and switches the result between plain words and the raw table.
func set_advanced(on: bool) -> void:
	advanced = on
	for c in advanced_parts:
		c.visible = on
	if not result.is_empty():
		result_label.text = _result_text(result) if on else plain_result_text(result)
	result_label.add_theme_font_override("font", _mono_font()) if on else result_label.remove_theme_font_override("font")

## The result in words a player knows: one line per change, then what the
## track measured, all changes together (the search does not measure them one by
## one, so the effect is shown once, for the whole set).
func plain_result_text(res: Dictionary) -> String:
	if not res.get("improved", false):
		var lines: Array[String] = ["The mechanic found nothing better for that goal. Your setup stays as it is."]
		for n in res.get("notes", []):
			lines.append(n)
		return "\n".join(lines)
	var lines: Array[String] = ["The mechanic suggests:"]
	for p in TuneParams.auto_paths():
		var old := TuneParams.get_value(player.spec, p)
		var now := float(res.values[p])
		if absf(old - now) > 1e-6:
			lines.append("  " + change_words(p, old, now))
	var b: Dictionary = res.base_metrics
	var m: Dictionary = res.metrics
	var effects: Array[String] = []
	var d_acc: float = m.t_0_100 - b.t_0_100
	if absf(d_acc) >= 0.02:
		effects.append("0-100 %.2f s %s" % [absf(d_acc), "quicker" if d_acc < 0.0 else "slower"])
	var d_top: float = m.top_speed_kmh - b.top_speed_kmh
	if absf(d_top) >= 0.5:
		effects.append("top speed %d km/h %s" % [roundi(absf(d_top)), "higher" if d_top > 0.0 else "lower"])
	var d_brk: float = m.brake_dist_100 - b.brake_dist_100
	if absf(d_brk) >= 0.2:
		effects.append("stops %.1f m %s" % [absf(d_brk), "shorter" if d_brk < 0.0 else "longer"])
	var d_lat: float = m.peak_lat_g - b.peak_lat_g
	if absf(d_lat) >= 0.01:
		effects.append("grip %+.2f g" % d_lat)
	lines.append("")
	lines.append("Measured on the track: " + (", ".join(effects) if not effects.is_empty() else "about the same") + ".")
	lines.append("Apply keeps it, Discard throws it away.")
	return "\n".join(lines)

## One change in plain words, with the raw numbers after it.
static func change_words(path: String, old: float, now: float) -> String:
	var up := now > old
	var nums := " (%.2f to %.2f)" % [old, now]
	if path == "final_drive":
		return ("Shorter gearing" if up else "Longer gearing") + nums
	if path.begins_with("gear_ratios/"):
		return "Gear %d %s" % [int(path.get_slice("/", 1)) + 1, "shorter" if up else "longer"] + nums
	match path:
		"coefficient_of_drag": return ("More drag" if up else "Less drag") + nums
		"aero_downforce_coefficient_front": return ("More front downforce" if up else "Less front downforce") + nums
		"aero_downforce_coefficient_rear": return ("More rear wing" if up else "Less rear wing") + nums
		"brake_force_multiplier": return ("Harder brakes" if up else "Softer brakes") + nums
		"tire_stiffnesses/Road": return ("Stiffer tyres" if up else "Softer tyres") + nums
		"coefficient_of_friction/Road": return ("Grippier tyres" if up else "Less grippy tyres") + nums
		"lateral_grip_assist/Road": return ("More cornering grip" if up else "Less cornering grip") + nums
		"longitudinal_grip_ratio/Road": return ("More launch and braking grip" if up else "Less launch and braking grip") + nums
	return "%s %s%s" % [TuneParams.find(path).get("label", path), "up" if up else "down", nums]

func _on_undo() -> void:
	if running or undo_spec.is_empty():
		return
	_write(undo_spec)
	undo_spec = {}
	status_label.text = "Undone."
	refresh_lock_labels()
	_refresh_buttons()

## Writes every tunable value that differs, through the single write path. All
## paths, not just Auto-Tune's: Undo must also revert a slot load, which can
## carry engine values.
func _write(spec: Dictionary) -> void:
	for e in TuneParams.all():
		var v := TuneParams.get_value(spec, e.path)
		if absf(TuneParams.get_value(player.spec, e.path) - v) > 1e-9:
			CarSpec.set_param(player, player.spec, e.path, v)
	tune_changed.emit()

# ---------- tune slots ----------

func _refresh_slots(select := "") -> void:
	slot_list.clear()
	for n in slots.names():
		slot_list.add_item(n)
		if n == select:
			slot_list.select(slot_list.item_count - 1)
	_refresh_buttons()

func _selected_slot() -> String:
	var sel := slot_list.get_selected_items()
	return "" if sel.is_empty() else slot_list.get_item_text(sel[0])

## Esc in the name field leaves the field (GameState ignores that Esc, so the
## Tuner screen stays open); a second Esc closes the screen.
func _on_slot_name_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		slot_name_edit.release_focus()
		slot_name_edit.accept_event()

func _on_slot_selected(index: int) -> void:
	slot_name_edit.text = slot_list.get_item_text(index)
	_refresh_buttons()

func _on_save_slot() -> void:
	var n := TuneSlots.clean_name(slot_name_edit.text)
	if n == "":
		status_label.text = "Type a name for the slot first."
		return
	var replacing := slots.has(n)
	if not slots.save(n, player.spec):
		status_label.text = "Could not save the slot (see the Godot console)."
		return
	status_label.text = "%s slot '%s'." % ["Replaced" if replacing else "Saved", n]
	_refresh_slots(n)

func _on_load_slot() -> void:
	var n := _selected_slot()
	if running or n == "":
		return
	var before := CarSpec.clone_spec(player.spec)
	if not slots.apply(n, player):
		status_label.text = "Slot '%s' is empty or missing." % n
		return
	undo_spec = before
	result = {}
	result_label.text = ""
	status_label.text = "Loaded '%s'. The car now drives with this tune." % n
	if not AutoTuneRules.violations(player.spec, {}, player.spec).is_empty():
		status_label.text += " (Its gears are out of order or out of range.)"
	refresh_lock_labels()
	_refresh_buttons()
	tune_changed.emit()

func _on_delete_slot() -> void:
	var n := _selected_slot()
	if n == "":
		return
	slots.delete(n)
	status_label.text = "Deleted slot '%s'." % n
	_refresh_slots()
