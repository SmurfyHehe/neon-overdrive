extends SceneTree

# Work board W2/W3 (2026-10-11): Walt's board screens, driven with the keys the
# player has (Left / Right + accept), on a bare GameState + Wallet + ShopDay.
#
# - every card, Walt's tag, the garage tag, Stay late and Head out are
#   reachable with Left / Right and taken with accept;
# - no label on the board, the job, the slip or the late board names a key;
# - the pause screen never opens on the board (Esc, slow frames);
# - 600 frames on the board and 600 in a job average under 0.5 ms of process;
# - screenshots of the board, a job and a slip go to user://screens/ when a
#   window exists (a headless run cannot render: it says so).
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/ui/work_board.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const ShopDay := preload("res://scripts/core/shop_day.gd")
const WorkOrders := preload("res://scripts/core/work_orders.gd")
const BoardScreen := preload("res://scripts/ui/work_board_screen.gd")

const ROOT := "user://test_work_board"
const FRAMES := 600
const BUDGET_MS := 0.5
## Words that name a key. "Press out" / "Press in" are the workshop's press
## (data/work_orders.json step labels), not a key: step labels are exempt.
const KEY_WORDS := ["enter", "space", "esc", "escape", "shift", "ctrl", "arrow", "press", "hold", "key", "keys", "tab", "return"]

var failures: Array[String] = []
var gs: GameState
var wallet: Node
var clock: NightClock
var shop: Node
var screen: CanvasLayer
var texts: Array[String] = []
var step_labels: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_GARAGE", "1")
	OS.set_environment("NEON_SHOP", "1")
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	NightClock.path = ROOT.path_join("clock.cfg")
	for o in WorkOrders.load_orders():
		for s in o.steps:
			step_labels.append(str(s.label))
	_run.call_deferred()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _run() -> void:
	_rig()
	await _walk()
	await _frames_budget()
	await _shots()
	for m in failures:
		printerr("FAIL: ", m)
	print("work_board: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _rig() -> void:
	wallet = Wallet.new()
	root.add_child(wallet)
	clock = NightClock.new()
	root.add_child(clock)
	clock.speed = 0.0
	gs = GameState.new()
	gs.garage_enabled = true
	root.add_child(gs)
	shop = ShopDay.new(wallet, clock)
	shop.enabled = true
	root.add_child(shop)
	shop.reload()
	gs.workboard_gate = shop.want_board
	screen = BoardScreen.new(gs, shop, wallet)
	screen.slip_delay = 0.0
	root.add_child(screen)

func _collect() -> void:
	for t in screen.all_texts():
		if not t in texts:
			texts.append(t)

func _all_steps_clean(order: Dictionary) -> void:
	var bar: Control = screen.bar
	bar.auto = false
	for i in order.steps.size():
		_check(bar.running, "step %d: the bar is not running" % i)
		bar.advance(0.3)
		bar.center = bar.needle
		bar.press()

# ---------- the walk ----------

func _walk() -> void:
	gs.request_dawn(1)
	gs.dawn_continue()
	await process_frame
	_check(gs.state == GameState.State.WORKBOARD and screen.visible and screen.mode == "board",
		"the board did not open (state %d, mode %s)" % [gs.state, screen.mode])
	_collect()
	# Three cards, Walt's tag, the garage tag: all reachable with Left / Right.
	var n: int = screen._items.size()
	_check(n == 5, "board has %d selectable things, expected 5" % n)
	for i in n:
		_check(screen._sel == i, "moving right %d times stands on %d" % [i, screen._sel])
		screen.press(&"right")
	_check(screen._sel == n - 1, "Right past the end moved to %d" % screen._sel)
	for i in n:
		screen.press(&"left")
	_check(screen._sel == 0, "Left back to the start stands on %d" % screen._sel)
	# A real key event takes the same path.
	var ev := InputEventAction.new()
	ev.action = &"ui_right"
	ev.pressed = true
	screen._input(ev)
	_check(screen._sel == 1, "ui_right event moved to %d" % screen._sel)
	screen.press(&"left")
	# Walt's tag shows his flat pay; the garage tag is the last item.
	_check("$450" in screen.all_texts(), "Walt's flat pay is not on the board")
	var first: String = shop.card_ids()[0]
	_check(first == "halloran_brakes", "first card is %s" % first)
	_check(screen.all_texts().has("$300-$680") == false and screen.all_texts().has(WorkOrders.range_text(WorkOrders.find("halloran_brakes"), 1)),
		"Halloran's card does not show its pay range %s" % WorkOrders.range_text(WorkOrders.find("halloran_brakes"), 1))
	# Take card 1 with accept: the job.
	screen.press(&"accept")
	await process_frame
	_check(screen.mode == "job" and shop.stage() == "job", "accept on a card did not start the job (mode %s)" % screen.mode)
	_collect()
	var order: Dictionary = shop.current_order()
	_check(order.id == "halloran_brakes", "job is %s" % order.id)
	# Pause never opens on the board or in a job.
	gs.toggle_pause()
	for i in 200:
		gs.feed_frame(0.05)
	_check(gs.state == GameState.State.WORKBOARD, "the pause screen opened in a job (state %d)" % gs.state)
	# A miss redoes the step, then clean marks all the way.
	screen.bar.auto = false
	screen.bar.advance(0.2)
	screen.bar.center = screen.bar.needle + 0.5
	screen.bar.press()
	_check(screen.bar.misses == 1 and screen.bar.running, "a miss in the job did not redo the step")
	_all_steps_clean(order)
	await process_frame
	_check(screen.mode == "slip" and shop.stage() == "slip", "the last step did not lead to the slip (mode %s, stage %s)" % [screen.mode, shop.stage()])
	_collect()
	_check(screen._items.size() == 2, "the slip has %d things, expected Stay late + Head out" % screen._items.size())
	_check(wallet.bank > 0 and wallet.cash == 0, "bank %d cash %d after the slip" % [wallet.bank, wallet.cash])
	# Stay late with accept (it is the first item), then pick a late card.
	screen.press(&"accept")
	await process_frame
	_check(screen.mode == "board" and shop.stage() == "late_board", "Stay late did not open the late board (mode %s)" % screen.mode)
	_collect()
	_check(screen._items.size() == 3, "the late board has %d things, expected 2 cards + Head out" % screen._items.size())
	screen.press(&"accept")
	await process_frame
	_check(screen.mode == "job" and shop.stage() == "late_job", "a late card did not start a job (stage %s)" % shop.stage())
	_collect()
	_all_steps_clean(shop.current_order())
	await process_frame
	_check(screen.mode == "slip" and shop.stage() == "late_slip", "the late job did not end on a slip (stage %s)" % shop.stage())
	_check(screen._items.size() == 1, "after the late order the slip has %d things, expected Head out only" % screen._items.size())
	_collect()
	# Head out closes the board into the garage.
	screen.press(&"accept")
	await process_frame
	_check(gs.state == GameState.State.GARAGE and shop.stage() == "done" and not screen.visible,
		"Head out did not reach the garage (state %d, stage %s)" % [gs.state, shop.stage()])
	# No label names a key.
	for t in texts:
		var low := t.to_lower()
		var is_step := false
		for s in step_labels:
			if low.begins_with(s.to_lower()):
				is_step = true
		var words := low.split(" ", false)
		for w in words:
			var word := w.strip_edges().trim_suffix(".").trim_suffix(",")
			if word in KEY_WORDS and not is_step:
				failures.append("a label names a key: '%s'" % t)
		var re := RegEx.new()
		re.compile("[\"'“”‘’][A-Z][\"'“”‘’]")
		if re.search(t) != null:
			failures.append("a label names a single key: '%s'" % t)
	print("work_board: %d labels read, no key names" % texts.size())

# ---------- frame cost ----------

func _frames_budget() -> void:
	# A fresh day on the board, then in a job.
	shop.data = {}
	shop.begin_day(2)
	# What the bare rig costs (state machine, clock, wallet) with the board hidden.
	var base_ms := await _avg_process_ms()
	gs.open_workboard()   # from the garage the walk ended in
	await process_frame
	_check(gs.state == GameState.State.WORKBOARD and screen.mode == "board", "Walt's board row did not reopen the board")
	var board_ms := await _avg_process_ms() - base_ms
	_check(board_ms < BUDGET_MS, "the board takes %.3f ms per frame, budget %.1f" % [board_ms, BUDGET_MS])
	screen.press(&"accept")
	var job_ms := await _avg_process_ms() - base_ms
	_check(screen.mode == "job", "frame test: not in a job (mode %s)" % screen.mode)
	_check(job_ms < BUDGET_MS, "a job takes %.3f ms per frame, budget %.1f" % [job_ms, BUDGET_MS])
	print("work_board: rig alone %.3f ms; board +%.3f ms, job +%.3f ms per frame (budget %.1f)" % [base_ms, board_ms, job_ms, BUDGET_MS])

func _avg_process_ms() -> float:
	var total := 0.0
	for i in 20:
		await process_frame   # warm up
	for i in FRAMES:
		await process_frame
		total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return total / FRAMES

# ---------- screenshots ----------

func _shots() -> void:
	if DisplayServer.get_name() == "headless":
		print("work_board: headless, so no screenshots (a window is needed to render them)")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://screens"))
	_save_shot("board")
	screen.press(&"accept")
	await process_frame
	await process_frame
	_save_shot("job")
	_all_steps_clean(shop.current_order())
	await process_frame
	await process_frame
	_save_shot("slip")

func _save_shot(shot: String) -> void:
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://screens/work_board_%s.png" % shot)

func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	DirAccess.remove_absolute(path)
