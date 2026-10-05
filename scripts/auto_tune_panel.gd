class_name AutoTunePanel
extends CanvasLayer

# Auto-Tune panel (step 6). Y opens it (GameState.AUTOTUNE, game paused like the
# raw T panel), Y or Esc closes it. Pick what to improve (goals, weight 0-3),
# lock what must not change, press Run; the search runs in a separate headless
# Godot process (AutoTuneJob) on the hidden test track and offers the best
# verified tune with before/after numbers. Apply writes it through
# CarSpec.set_param(), the same path as the raw T panel, which is unchanged.
#
# Debug tool, deliberately plain Godot default controls, like the raw panel.

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 40)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.02, 0.07, 0.94)
	bg.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)

	# --- left: goals, budget, buttons ---
	var left := VBoxContainer.new()
	columns.add_child(left)
	var title := Label.new()
	title.text = "AUTO-TUNE  -  Y or Esc to close, game paused"
	left.add_child(title)
	left.add_child(_heading("Goals (0 = off)"))
	var grid := GridContainer.new()
	grid.columns = 3
	left.add_child(grid)
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
		v.custom_minimum_size = Vector2(36, 0)
		grid.add_child(v)
		goal_labels[goal] = v
		_on_goal_changed(0, goal)
	budget_option = OptionButton.new()
	for b in BUDGETS:
		budget_option.add_item(b[0])
	budget_option.select(DEFAULT_BUDGET)
	left.add_child(budget_option)
	var row := HBoxContainer.new()
	left.add_child(row)
	run_button = _button(row, "Run", _on_run)
	cancel_button = _button(row, "Cancel", _on_cancel)
	apply_button = _button(row, "Apply", _on_apply)
	undo_button = _button(row, "Undo apply", _on_undo)
	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(320, 0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(status_label)

	# --- middle: locks ---
	var mid := VBoxContainer.new()
	columns.add_child(mid)
	mid.add_child(_heading("Lock (never changed)"))
	var locks := GridContainer.new()
	locks.columns = 2
	mid.add_child(locks)
	for path in TuneParams.auto_paths():
		var cb := CheckBox.new()
		cb.text = TuneParams.find(path).label
		locks.add_child(cb)
		lock_boxes[path] = cb

	# --- right: result ---
	result_label = Label.new()
	result_label.add_theme_font_override("font", _mono_font())
	result_label.custom_minimum_size = Vector2(420, 0)
	columns.add_child(result_label)

	game_state.state_changed.connect(_on_state_changed)
	_refresh_buttons()

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	return l

func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _mono_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	return f

# ---------- open / close ----------

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	visible = new_state == GameState.State.AUTOTUNE
	if visible:
		_refresh_lock_labels()
		_refresh_buttons()
	elif old_state == GameState.State.AUTOTUNE:
		if running:
			_on_cancel()  # leaving the panel stops the search
		# Sliders and checkboxes keep keyboard focus otherwise and eat game keys.
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

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

func _refresh_lock_labels() -> void:
	for path in lock_boxes:
		var e := TuneParams.find(path)
		lock_boxes[path].text = "%s  %.2f" % [e.label, TuneParams.get_value(player.spec, path)]

func _refresh_buttons() -> void:
	run_button.disabled = running
	cancel_button.disabled = not running
	apply_button.disabled = running or not result.get("improved", false)
	undo_button.disabled = running or undo_spec.is_empty()
	budget_option.disabled = running

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
		result_label.text = _result_text(result)
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
	_refresh_lock_labels()
	_refresh_buttons()

func _on_undo() -> void:
	if running or undo_spec.is_empty():
		return
	_write(undo_spec)
	undo_spec = {}
	status_label.text = "Undone."
	_refresh_lock_labels()
	_refresh_buttons()

## Writes every Auto-Tune value that differs, through the single write path.
func _write(spec: Dictionary) -> void:
	for p in TuneParams.auto_paths():
		var v := TuneParams.get_value(spec, p)
		if absf(TuneParams.get_value(player.spec, p) - v) > 1e-9:
			CarSpec.set_param(player, player.spec, p, v)
