extends CanvasLayer

# Walt's board (work board W2, 2026-10-11): three screens in one scene, shown
# between the dawn card and the garage (GameState.State.WORKBOARD).
#
#   1 the board    three paper cards (who, which car, what is wrong, pay range)
#                  and two small tags: "Leave it to Walt" with his flat pay, and
#                  "To the garage"
#   2 the job      the card top-left, the steps list, the timing bar
#   3 the pay slip the order, each step's mark, the total, "Paid into the bank";
#                  then Stay late (once a day) and Head out
#
# Keyboard only: Left / Right (and Up / Down) move, accept takes. Nothing on
# screen names a key. Plain look first (no art pass yet): navy backdrop, one
# amber lamp glow, paper cards.
#
# No class_name on purpose: preload it.

const TimingBar := preload("res://scripts/ui/timing_bar.gd")
const WorkOrders := preload("res://scripts/core/work_orders.gd")
const ShopDay := preload("res://scripts/core/shop_day.gd")

const NAVY := Color("#1B2A4A")
const DUSK := Color("#0E1424")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const SILVER := Color("#C9CED6")
const PAPER := Color("#D8CFB6")
const RED := Color("#E5262B")
const CARD_SIZE := Vector2(300, 300)
const OUTLINE_DIR := "res://assets/ui/outlines/"
const OUTLINE_SIZE := Vector2(240, 120)
const LIFT := 14.0
## How long the last line of a job is shown before the slip, seconds.
var slip_delay := 0.9
## How long the bank takes to tick up on the slip, seconds.
const TICK_SECS := 0.8

var game_state: GameState
var shop: Node
var wallet: Node

var mode := ""   # "board", "job", "slip" while visible
var board_panel: Control
var job_panel: Control
var slip_panel: Control
var bar: Control
var day_label: Label
var bank_label: Label
var line_label: Label
var cards_row: HBoxContainer
var tags_col: VBoxContainer
var job_card_box: VBoxContainer
var steps_box: VBoxContainer
var job_line: Label
var slip_box: VBoxContainer
var donor_panel: Control
var donor_row: HBoxContainer
var donor_line: Label
## Scrap-yard order: wrong donors picked so far (never costs pay), the
## options on the panel, and whether the right one has been picked.
var donor_misses := 0
var donor_options: Array[String] = []
var _donor_ok := false

var _items: Array[Control] = []
var _acts: Array[Callable] = []
var _lines: Array[String] = []   # what the board shows under it for each item
var _sel := 0
var _marks: Array = []
var _step := 0
var _missed_any := false
var _step_labels: Array[Label] = []
var _bank_shown := 0.0
var _bank_target := 0.0
var _tick := 0.0

func _init(state: GameState, shop_day: Node, w: Node) -> void:
	game_state = state
	shop = shop_day
	wallet = w
	name = "WorkBoardScreen"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false

	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, DUSK)
	grad.set_color(1, NAVY)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	bg.texture = gt
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)

	# One amber lamp glow at the top.
	var glow := TextureRect.new()
	var gg := Gradient.new()
	gg.set_color(0, Color(AMBER, 0.28))
	gg.set_color(1, Color(AMBER, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = gg
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 512
	gtex.height = 512
	glow.texture = gtex
	glow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	glow.position = Vector2(-640, -320)
	glow.size = Vector2(1280, 640)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(glow)

	var root_box := MarginContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.theme = UiTheme.font_theme()
	for side in ["left", "right", "top", "bottom"]:
		root_box.add_theme_constant_override("margin_" + side, 56)
	add_child(root_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	root_box.add_child(col)

	# Header: the day top-left, the bank top-right in silver.
	var head := HBoxContainer.new()
	col.add_child(head)
	day_label = UiTheme.title_label("", 40, AMBER)
	day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(day_label)
	bank_label = Label.new()
	UiTheme.apply(bank_label, "numbers", 26)
	bank_label.add_theme_color_override("font_color", SILVER)
	head.add_child(bank_label)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stack)

	# 1: the board.
	board_panel = VBoxContainer.new()
	board_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_panel.add_theme_constant_override("separation", 22)
	stack.add_child(board_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	board_panel.add_child(row)
	cards_row = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 24)
	row.add_child(cards_row)
	tags_col = VBoxContainer.new()
	tags_col.add_theme_constant_override("separation", 14)
	tags_col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(tags_col)
	line_label = Label.new()
	UiTheme.apply(line_label, "menu", 24)
	line_label.add_theme_color_override("font_color", SILVER)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size = Vector2(760, 60)
	line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lc := CenterContainer.new()
	lc.add_child(line_label)
	board_panel.add_child(lc)

	# 2: the job.
	job_panel = VBoxContainer.new()
	job_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	job_panel.add_theme_constant_override("separation", 20)
	stack.add_child(job_panel)
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 40)
	job_panel.add_child(jrow)
	job_card_box = VBoxContainer.new()
	job_card_box.custom_minimum_size = Vector2(320, 0)
	jrow.add_child(job_card_box)
	steps_box = VBoxContainer.new()
	steps_box.add_theme_constant_override("separation", 6)
	jrow.add_child(steps_box)
	var bar_wrap := CenterContainer.new()
	bar_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	job_panel.add_child(bar_wrap)
	bar = TimingBar.new()
	bar.custom_minimum_size = Vector2(760, 54)
	bar_wrap.add_child(bar)
	job_line = Label.new()
	UiTheme.apply(job_line, "menu", 24)
	job_line.add_theme_color_override("font_color", SILVER)
	job_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	job_panel.add_child(job_line)
	bar.step_done.connect(_on_step_done)
	bar.step_missed.connect(_on_step_missed)

	# 2b: the scrap yard (W3): pick the donor car from three wreck outlines.
	donor_panel = VBoxContainer.new()
	donor_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	donor_panel.add_theme_constant_override("separation", 22)
	stack.add_child(donor_panel)
	var drow_wrap := CenterContainer.new()
	drow_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	donor_panel.add_child(drow_wrap)
	donor_row = HBoxContainer.new()
	donor_row.add_theme_constant_override("separation", 24)
	drow_wrap.add_child(donor_row)
	donor_line = Label.new()
	UiTheme.apply(donor_line, "menu", 26)
	donor_line.add_theme_color_override("font_color", SILVER)
	donor_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	donor_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	donor_line.custom_minimum_size = Vector2(760, 70)
	donor_panel.add_child(donor_line)

	# 3: the pay slip.
	slip_panel = CenterContainer.new()
	slip_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(slip_panel)
	slip_box = VBoxContainer.new()
	slip_box.add_theme_constant_override("separation", 8)
	slip_panel.add_child(slip_box)

	game_state.state_changed.connect(_on_state_changed)
	if wallet != null and wallet.has_signal("changed"):
		wallet.changed.connect(func(_c: int, b: int) -> void: _bank_target = b)
	if wallet != null:
		_bank_target = wallet.bank
		_bank_shown = wallet.bank
	_show_only(null)

func _process(delta: float) -> void:
	if not visible or wallet == null:
		return
	if _bank_shown < _bank_target:
		_tick = minf(_tick + delta / TICK_SECS, 1.0)
		_bank_shown = minf(lerpf(_bank_shown, _bank_target, _tick), _bank_target)
		if _tick >= 1.0 or _bank_target - _bank_shown < 1.0:
			_bank_shown = _bank_target
		_bank_text()

func _bank_text() -> void:
	bank_label.text = "Bank %s" % WorkOrders.money(int(round(_bank_shown)))

func _show_only(panel: Control) -> void:
	board_panel.visible = panel == board_panel
	job_panel.visible = panel == job_panel
	slip_panel.visible = panel == slip_panel
	donor_panel.visible = panel == donor_panel
	bar.running = bar.running and panel == job_panel
	_items.clear()
	_acts.clear()
	_lines.clear()
	_sel = 0

func _on_state_changed(new_state: GameState.State, _old: GameState.State) -> void:
	visible = new_state == GameState.State.WORKBOARD
	if visible:
		_open()

## Opens on whichever stage today is at (a reopened board or a reload).
func _open() -> void:
	if wallet != null:
		_bank_shown = wallet.bank
		_bank_target = wallet.bank
	_bank_text()
	day_label.text = "Day %d" % shop.day()
	match shop.stage():
		ShopDay.BOARD:
			_show_board(false)
		ShopDay.LATE_BOARD:
			_show_board(true)
		ShopDay.JOB, ShopDay.LATE_JOB:
			_start_job()
		ShopDay.SLIP, ShopDay.LATE_SLIP:
			_show_slip()
		_:
			game_state.close_workboard.call_deferred()

# ---------- screen 1: the board ----------

func _show_board(late: bool) -> void:
	_show_only(board_panel)
	mode = "board"
	_donor_ok = false
	day_label.text = "Day %d, late" % shop.day() if late else "Day %d" % shop.day()
	for c in cards_row.get_children():
		cards_row.remove_child(c)
		c.queue_free()
	for c in tags_col.get_children():
		tags_col.remove_child(c)
		c.queue_free()
	var cards: Array = shop.late_cards() if late else shop.cards()
	for o in cards:
		var card := _make_card(o)
		cards_row.add_child(card)
		_items.append(card)
		var id: String = o.id
		_acts.append(func() -> void: _pick(id))
		_lines.append(str(o.lines.get("card", "")))
	if not late:
		var walt := _make_tag("Leave it to Walt", WorkOrders.money(shop.walt_pay()))
		tags_col.add_child(walt)
		_items.append(walt)
		_acts.append(_walt)
		_lines.append("Walt does it. Flat pay, no fuss.")
		var garage := _make_tag("To the garage", "")
		tags_col.add_child(garage)
		_items.append(garage)
		_acts.append(_to_garage)
		_lines.append("")
	else:
		var out := _make_tag("Head out", "")
		tags_col.add_child(out)
		_items.append(out)
		_acts.append(_head_out)
		_lines.append("")
	_select(0)

func _make_card(o: Dictionary) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = CARD_SIZE + Vector2(0, LIFT)
	var panel := PanelContainer.new()
	panel.size = CARD_SIZE
	panel.position = Vector2(0, LIFT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.set_border_width_all(4)
	sb.border_color = DUSK
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	wrap.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var who := _card_label(str(o.customer), 26, "display", DUSK)
	v.add_child(who)
	v.add_child(_car_picture(o, NAVY))
	var prob := _card_label(str(o.problem), 20, "menu", DUSK)
	prob.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prob.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(prob)
	if o.get("favour", false):
		v.add_child(_card_label("+ owes you one", 18, "menu_strong", SODIUM))
	v.add_child(_card_label(shop.range_text(o), 28, "numbers", NAVY))
	wrap.set_meta("panel", panel)
	wrap.set_meta("style", sb)
	return wrap

## The car's outline (tools/render_car_outlines.gd), or its name as text if
## the picture is missing.
func _car_picture(o: Dictionary, tint: Color) -> Control:
	var tex := outline_texture(str(o.car))
	if tex == null:
		return _card_label(_car_line(o), 18, "numbers", tint)
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = OUTLINE_SIZE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.modulate = Color(NAVY) if tint == NAVY else Color.WHITE
	return r

static func outline_texture(car_id: String) -> Texture2D:
	var p := OUTLINE_DIR + car_id + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

func _car_line(o: Dictionary) -> String:
	return str(o.car).replace("_", " ")

func _card_label(text: String, size: int, role: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.apply(l, role, size)
	l.add_theme_color_override("font_color", colour)
	return l

func _make_tag(title: String, sub: String) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NAVY, 0.9)
	sb.set_border_width_all(3)
	sb.border_color = DUSK
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(210, 0)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(_card_label(title, 22, "menu_strong", SILVER))
	if sub != "":
		v.add_child(_card_label(sub, 22, "numbers", AMBER))
	panel.set_meta("style", sb)
	return panel

func _select(i: int) -> void:
	if _items.is_empty():
		return
	_sel = clampi(i, 0, _items.size() - 1)
	for n in _items.size():
		var item := _items[n]
		var on := n == _sel
		if item.has_meta("style"):
			(item.get_meta("style") as StyleBoxFlat).border_color = AMBER if on else DUSK
		if item.has_meta("panel"):
			(item.get_meta("panel") as Control).position.y = 0.0 if on else LIFT
	if mode == "board":
		line_label.text = _lines[_sel] if _sel < _lines.size() else ""

func _pick(order_id: String) -> void:
	if shop.take(order_id):
		_start_job()

func _walt() -> void:
	shop.skip()
	_show_slip()

func _to_garage() -> void:
	game_state.close_workboard()

func _head_out() -> void:
	shop.head_out()
	game_state.close_workboard()

# ---------- screen 2: the job ----------

func _start_job() -> void:
	_show_only(job_panel)
	mode = "job"
	var order: Dictionary = shop.current_order()
	if order.is_empty():
		shop.head_out()
		game_state.close_workboard.call_deferred()
		return
	var late: bool = shop.stage() == ShopDay.LATE_JOB
	day_label.text = "Day %d, late" % shop.day() if late else "Day %d" % shop.day()
	if str(order.get("kind", "bench")) == "scrap" and not _donor_ok:
		_show_donor(order)
		return
	for c in job_card_box.get_children():
		job_card_box.remove_child(c)
		c.queue_free()
	job_card_box.add_child(_job_label(str(order.customer), 30, "display", AMBER))
	job_card_box.add_child(_car_picture(order, SILVER))
	var prob := _job_label(str(order.problem), 20, "menu", SILVER)
	prob.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_card_box.add_child(prob)
	for c in steps_box.get_children():
		steps_box.remove_child(c)
		c.queue_free()
	_step_labels.clear()
	for s in order.steps:
		var l := _job_label(str(s.label), 22, "menu_strong", DUSK.lerp(SILVER, 0.55))
		steps_box.add_child(l)
		_step_labels.append(l)
	_marks = []
	_step = 0
	_missed_any = false
	job_line.text = str(order.lines.get("start", ""))
	_begin_step()

# ---------- screen 2b: the scrap yard ----------

## Three wreck outlines, one of them the car the order wants. A wrong pick
## shows the giver's miss line and you pick again: no timer, no lamps, no pay
## lost (it plays like any other job once the donor is right).
func _show_donor(order: Dictionary) -> void:
	_show_only(donor_panel)
	mode = "donor"
	var d: Dictionary = order.get("donor", {})
	var want := str(d.get("want", ""))
	var ids: Array = [want] + Array(d.get("decoys", []))
	# A stable shuffle, so a reload shows the same three in the same places.
	var day_n: int = shop.day()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return hash([a, day_n]) < hash([b, day_n]))
	donor_options.clear()
	for c in donor_row.get_children():
		donor_row.remove_child(c)
		c.queue_free()
	for id in ids:
		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(OUTLINE_SIZE.x + 40, OUTLINE_SIZE.y + 60)
		var panel := PanelContainer.new()
		panel.size = wrap.custom_minimum_size
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(NAVY, 0.9)
		sb.set_border_width_all(4)
		sb.border_color = DUSK
		sb.set_content_margin_all(18)
		panel.add_theme_stylebox_override("panel", sb)
		wrap.add_child(panel)
		var pic := TextureRect.new()
		pic.texture = outline_texture(str(id))
		pic.custom_minimum_size = OUTLINE_SIZE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(pic)
		wrap.set_meta("style", sb)
		donor_row.add_child(wrap)
		_items.append(wrap)
		donor_options.append(str(id))
		var pick: String = str(id)
		_acts.append(func() -> void: _pick_donor(pick, want))
		_lines.append("")
	donor_line.text = str(order.problem)
	_select(0)

func _pick_donor(picked: String, want: String) -> void:
	if picked == want:
		_donor_ok = true
		_start_job()
		return
	donor_misses += 1
	var order: Dictionary = shop.current_order()
	donor_line.text = str(order.lines.get("miss", "Wrong car."))

func _job_label(text: String, size: int, role: String, colour: Color) -> Label:
	return _card_label(text, size, role, colour)

func _begin_step() -> void:
	var order: Dictionary = shop.current_order()
	var step: Dictionary = order.steps[_step]
	_step_labels[_step].add_theme_color_override("font_color", AMBER)
	bar.setup(step)

func _on_step_missed(_n: int) -> void:
	_missed_any = true
	if _step < _step_labels.size():
		_step_labels[_step].add_theme_color_override("font_color", RED)

func _on_step_done(mark: float) -> void:
	if mode != "job":
		return
	if mark <= 0.0:
		_missed_any = true
	_marks.append(mark)
	var l := _step_labels[_step]
	l.add_theme_color_override("font_color", AMBER if mark > 0.0 else RED)
	l.text = "%s  %s" % [l.text.split("  ")[0], _mark_word(mark)]
	_step += 1
	var order: Dictionary = shop.current_order()
	if _step < order.steps.size():
		_begin_step()
		return
	var lines: Dictionary = order.lines
	job_line.text = str(lines.get("miss", "")) if _missed_any else str(lines.get("done", ""))
	shop.finish_job(_marks)
	_donor_ok = false
	if slip_delay <= 0.0:
		_show_slip()
	else:
		var t := get_tree().create_timer(slip_delay, true, false, true)
		t.timeout.connect(func() -> void:
			if mode == "job" and visible:
				_show_slip())

static func _mark_word(m: float) -> String:
	if m >= WorkOrders.MARK_CLEAN:
		return "Clean"
	if m > 0.0:
		return "Good"
	return "Missed"

# ---------- screen 3: the pay slip ----------

func _show_slip() -> void:
	_show_only(slip_panel)
	mode = "slip"
	var late: bool = shop.stage() == ShopDay.LATE_SLIP
	day_label.text = "Day %d, late" % shop.day() if late else "Day %d" % shop.day()
	for c in slip_box.get_children():
		slip_box.remove_child(c)
		c.queue_free()
	var d: Dictionary = shop.data
	var walted: bool = d.get("walted", false) and not late
	var paid := int(d.get("late_paid" if late else "paid", 0))
	var paper := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.set_border_width_all(4)
	sb.border_color = DUSK
	sb.set_content_margin_all(22)
	paper.add_theme_stylebox_override("panel", sb)
	paper.custom_minimum_size = Vector2(440, 0)
	slip_box.add_child(paper)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	paper.add_child(v)
	if walted:
		v.add_child(_card_label("Walt did it.", 30, "display", DUSK))
		v.add_child(_card_label("%s into the bank." % WorkOrders.money(paid), 26, "numbers", NAVY))
	else:
		var order: Dictionary = shop.current_order()
		v.add_child(_card_label(str(order.get("customer", "")), 30, "display", DUSK))
		v.add_child(_card_label(str(order.get("problem", "")), 18, "menu", NAVY))
		var steps: Array = order.get("steps", [])
		var marks: Array = d.get("late_marks" if late else "marks", [])
		for i in steps.size():
			var m: float = float(marks[i]) if i < marks.size() else 0.0
			var word := _mark_word(m) if i < marks.size() else ""
			v.add_child(_card_label("%s   %s" % [str(steps[i].label), word], 20, "menu_strong", DUSK))
		v.add_child(UiTheme.floor_tape())
		if paid >= 0:
			v.add_child(_card_label(WorkOrders.money(paid), 36, "numbers", NAVY))
		v.add_child(_card_label("Paid into the bank", 22, "menu_strong", DUSK))
	# Bank ticks up in silver.
	if wallet != null:
		_bank_target = wallet.bank
		_bank_shown = float(maxi(wallet.bank - maxi(paid, 0), 0))
		_tick = 0.0
		_bank_text()
	if shop.offer_stay_late():
		var late_tag := _make_tag("Stay late", "Night starts at 9 p.m.")
		slip_box.add_child(late_tag)
		_items.append(late_tag)
		_acts.append(_stay_late)
	var out := _make_tag("Head out", "")
	slip_box.add_child(out)
	_items.append(out)
	_acts.append(_head_out)
	_select(0)

func _stay_late() -> void:
	if shop.start_stay_late():
		_show_board(true)

# ---------- input ----------

func _input(event: InputEvent) -> void:
	if not visible or mode == "job":
		return
	for a in [&"ui_left", &"ui_up"]:
		if event.is_action_pressed(a, false):
			press(&"left")
			return
	for a in [&"ui_right", &"ui_down"]:
		if event.is_action_pressed(a, false):
			press(&"right")
			return
	if event.is_action_pressed(&"ui_accept", false):
		press(&"accept")
	elif event.is_action_pressed(&"ui_cancel", false) and mode == "board" and shop.stage() == ShopDay.BOARD:
		press(&"cancel")

## left / right / accept / cancel, the same path the keys take (tests use it).
func press(what: StringName) -> void:
	match what:
		&"left":
			_select(_sel - 1)
		&"right":
			_select(_sel + 1)
		&"accept":
			if _sel < _acts.size():
				_acts[_sel].call()
		&"cancel":
			_to_garage()
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()

## Every label text on the three screens (the no-key-names test reads it).
func all_texts() -> Array[String]:
	var out: Array[String] = []
	_collect(self, out)
	return out

func _collect(n: Node, out: Array[String]) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect(c, out)
