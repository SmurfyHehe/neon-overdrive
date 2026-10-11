extends SceneTree

# Work board W2 (2026-10-11): the day step at the shop, with NEON_GARAGE=1 and
# NEON_SHOP=1 and a throwaway save folder.
#
# Rig (a bare GameState + Wallet + NightClock + ShopDay, no world):
#   S1 after an order the bank grew by exactly the slip amount, cash did not
#      move, wallet.json matches
#   S2 a second normal order is impossible; stay late is offered once; after it
#      only Head out
#   S3 kill after the pay write but before the shop write: reload shows the
#      slip and the bank was paid once (and the other way round)
#   S4 quit mid-job: reload restarts the job, nothing paid
#   S5 after stay late the next night starts at 9 p.m.; without it, 8 p.m.
#   S6 NEON_SHOP=0 turns it off: dawn card -> garage, no board
# Real Game.tscn:
#   S8 a boot shows no board; the dawn after night 1 shows the board with
#      halloran_brakes first
#   S7 Go out with no order taken pays exactly Walt's flat pay once, and a
#      second Go out the same day pays nothing
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/core/shop_day.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const ShopDay := preload("res://scripts/core/shop_day.gd")
const WorkOrders := preload("res://scripts/core/work_orders.gd")

const ROOT := "user://test_shop_day"
const TIMEOUT_FRAMES := 1800
const HALLORAN_MARKS := [1.0, 1.0, 0.7, 1.0, 1.0]   # 0.94 -> 0.388 nights -> $580

var failures: Array[String] = []
var game: Node
var rig: Dictionary = {}

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_GARAGE", "1")
	OS.set_environment("NEON_SHOP", "1")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	NightClock.path = ROOT.path_join("clock.cfg")
	_run.call_deferred()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _run() -> void:
	_s1_s2()
	_s3()
	_s4()
	_s5()
	_s6()
	_close_rig()
	await _real_game()
	for m in failures:
		printerr("FAIL: ", m)
	print("shop_day: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

# ---------- the rig ----------

## A fresh slot: wallet, clock, shop and a GameState with the board gate wired.
func _new_rig(shop_on := true, keep_files := false) -> void:
	_close_rig()
	if not keep_files:
		_wipe(ProjectSettings.globalize_path(SaveStore.slot_dir()))
	var w: Node = Wallet.new()
	root.add_child(w)
	var clock := NightClock.new()
	root.add_child(clock)
	clock.speed = 0.0
	var gs := GameState.new()
	gs.garage_enabled = true
	root.add_child(gs)
	var shop: Node = ShopDay.new(w, clock)
	shop.enabled = shop_on
	root.add_child(shop)
	shop.reload()
	if shop_on:
		gs.workboard_gate = shop.want_board
	rig = {"wallet": w, "clock": clock, "gs": gs, "shop": shop}

func _close_rig() -> void:
	for k in rig:
		var n: Node = rig[k]
		if is_instance_valid(n):
			root.remove_child(n)
			n.free()
	rig = {}
	paused = false

## A second ShopDay + Wallet read back from the files, like a relaunch.
func _reload_shop() -> Node:
	root.remove_child(rig.shop)
	rig.shop.free()
	root.remove_child(rig.wallet)
	rig.wallet.free()
	var w: Node = Wallet.new()
	root.add_child(w)
	var shop: Node = ShopDay.new(w, rig.clock)
	shop.enabled = true
	root.add_child(shop)
	shop.reload()
	rig.wallet = w
	rig.shop = shop
	return shop

func _to_board(night: int) -> void:
	rig.gs.request_dawn(night)
	_check(rig.gs.state == GameState.State.DAWN, "request_dawn(%d) did not open the dawn card (state %d)" % [night, rig.gs.state])
	rig.gs.dawn_continue()

# ---------- S1, S2 ----------

func _s1_s2() -> void:
	_new_rig()
	var w: Node = rig.wallet
	var shop: Node = rig.shop
	var gs: GameState = rig.gs
	w.add_cash(77)
	_to_board(1)
	_check(gs.state == GameState.State.WORKBOARD, "S1 the dawn after night 1 did not open the board (state %d)" % gs.state)
	_check(shop.card_ids().size() == 3 and shop.card_ids()[0] == "halloran_brakes", "S1 first card is %s" % str(shop.card_ids()))
	_check(shop.take("halloran_brakes") and shop.stage() == "job", "S1 taking the card did not start the job")
	var bank0: int = w.bank
	var amount: int = shop.finish_job(HALLORAN_MARKS)
	_check(amount == 580, "S1 the slip is $%d, hand worked $580" % amount)
	_check(w.bank == bank0 + amount and w.cash == 77, "S1 bank %d cash %d, expected %d / 77" % [w.bank, w.cash, bank0 + amount])
	var f := SaveStore.load_wallet()
	_check(f.bank == w.bank and f.cash == 77 and "day1:halloran_brakes" in f.receipts, "S1 wallet.json is %s" % str(f))
	_check(shop.stage() == "slip" and int(SaveStore.load_shop().get("paid", -2)) == amount, "S1 shop.json is %s" % str(SaveStore.load_shop()))
	# S2: a second normal order is impossible, stay late once, then only Head out.
	_check(not shop.take("moose_gearbox"), "S2 a second normal order was taken")
	_check(shop.skip() == 0 and w.bank == bank0 + amount, "S2 Walt paid after an order")
	_check(shop.offer_stay_late(), "S2 stay late not offered after the order")
	_check(shop.start_stay_late() and shop.stage() == "late_board", "S2 stay late did not open the late board")
	var left: Array = shop.late_cards()
	var left_ids: Array = left.map(func(o: Dictionary) -> String: return o.id)
	_check(left.size() == 2 and not "halloran_brakes" in left_ids, "S2 the late board shows %s" % str(left_ids))
	_check(not shop.offer_stay_late(), "S2 stay late offered twice")
	var late_id: String = left[0].id
	_check(shop.take(late_id), "S2 late card refused")
	var bank1: int = w.bank
	var late_amount: int = shop.finish_job([1.0, 1.0, 1.0, 1.0, 1.0] if shop.current_order().steps.size() == 5 else _all(shop.current_order().steps.size(), 1.0))
	var order := WorkOrders.find(late_id)
	var want := WorkOrders.pay_for(order, 1.0, 1, "weekend_warrior", {"stay_late": true})
	_check(late_amount == want and w.bank == bank1 + want, "S2 late pay $%d, expected $%d (bank %d)" % [late_amount, want, w.bank])
	_check("day1:late:%s" % late_id in w.receipts, "S2 no late receipt")
	_check(not shop.offer_stay_late() and shop.stage() == "late_slip", "S2 stay late offered after the late order")
	shop.head_out()
	gs.close_workboard()
	_check(shop.stage() == "done" and not shop.can_reopen() and gs.state == GameState.State.GARAGE, "S2 Head out did not settle the day")
	_check(not shop.take("moose_gearbox") and shop.settle_for_exit() == 0, "S2 a settled day paid again")
	# One more dawn the same night does not start a new day (a reload).
	_check(not shop.want_board(1), "S2 a settled day opened the board again")

func _all(n: int, v: float) -> Array:
	var a: Array = []
	for i in n:
		a.append(v)
	return a

# ---------- S3: the kill between the two writes ----------

func _s3() -> void:
	# (a) pay written, shop file not: the slip comes back, nothing paid twice.
	_new_rig()
	var w: Node = rig.wallet
	_to_board(1)
	rig.shop.take("halloran_brakes")
	w.pay_shop(580, "day1:halloran_brakes")   # the pay write went through ...
	var bank: int = w.bank                    # ... and the process died before the shop write
	var shop := _reload_shop()
	_check(shop.stage() == "slip", "S3a reload stage is %s, expected slip" % shop.stage())
	_check(rig.wallet.bank == bank and bank == 580, "S3a bank is %d after reload, expected 580 once" % rig.wallet.bank)
	_check(shop.card_ids()[0] == "halloran_brakes", "S3a the board changed")
	# (b) shop file written, pay not: reload pays it, once.
	_new_rig()
	w = rig.wallet
	_to_board(1)
	rig.shop.take("halloran_brakes")
	var before := SaveStore.load_wallet()
	var paid: int = rig.shop.finish_job(HALLORAN_MARKS)
	SaveStore.save_wallet(before.cash, before.bank, before.receipts)   # the pay write is lost
	shop = _reload_shop()
	_check(rig.wallet.bank == paid, "S3b bank %d after reload, expected %d" % [rig.wallet.bank, paid])
	shop = _reload_shop()
	_check(rig.wallet.bank == paid, "S3b a second reload paid again (%d)" % rig.wallet.bank)

# ---------- S4: quit mid-job ----------

func _s4() -> void:
	_new_rig()
	_to_board(1)
	rig.shop.take("halloran_brakes")
	var bank: int = rig.wallet.bank
	var shop := _reload_shop()
	_check(shop.stage() == "job", "S4 reload stage is %s, expected job" % shop.stage())
	_check(shop.current_order().get("id", "") == "halloran_brakes", "S4 the job came back as %s" % str(shop.current_order().get("id", "")))
	_check(rig.wallet.bank == bank and rig.wallet.receipts.is_empty(), "S4 something was paid mid-job")

# ---------- S5: stay late moves the next night to 9 p.m. ----------

func _s5() -> void:
	_new_rig()
	var clock: NightClock = rig.clock
	clock.set_time(0.0, 2)
	_to_board(1)
	rig.shop.take("halloran_brakes")
	rig.shop.finish_job(HALLORAN_MARKS)
	_check(clock.minutes == 0.0, "S5 clock is %f after a normal order, expected 0 (8 p.m.)" % clock.minutes)
	rig.shop.start_stay_late()
	var id: String = rig.shop.late_cards()[0].id
	rig.shop.take(id)
	rig.shop.finish_job(_all(WorkOrders.find(id).steps.size(), 1.0))
	_check(clock.minutes == 60.0 and clock.night == 2, "S5 clock is %f night %d after stay late, expected 60 / 2" % [clock.minutes, clock.night])
	# A relaunch puts the clock back at 8 p.m. (the run save): the late slip
	# restores the 9 p.m. start while it is still on screen.
	clock.set_time(0.0, 2)
	_reload_shop()
	_check(clock.minutes == 60.0, "S5 reload on the late slip left the clock at %f" % clock.minutes)

# ---------- S6: shop off ----------

func _s6() -> void:
	_new_rig(false)
	_check(rig.shop.want_board(1) == false, "S6 a disabled shop wants the board")
	_to_board(1)
	_check(rig.gs.state == GameState.State.GARAGE, "S6 shop off: dawn card went to state %d, expected the garage" % rig.gs.state)
	OS.set_environment("NEON_SHOP", "0")
	_check(not ShopDay.wants_shop(true), "S6 NEON_SHOP=0 did not turn the shop off")
	OS.set_environment("NEON_SHOP", "1")
	_check(ShopDay.wants_shop(false), "S6 NEON_SHOP=1 did not turn the shop on")
	OS.set_environment("NEON_SHOP", "")
	_check(ShopDay.wants_shop(true) and not ShopDay.wants_shop(false), "S6 the shop does not follow the garage")
	OS.set_environment("NEON_SHOP", "1")
	# A boot or a forecourt visit never shows the board, shop on or not.
	_new_rig()
	rig.gs.garage_entry = GameState.ENTRY_BOOT
	rig.gs.request_dawn(1)
	rig.gs.garage_entry = GameState.ENTRY_BOOT
	rig.gs.dawn_continue()
	_check(rig.gs.state == GameState.State.GARAGE, "S8 a boot entry went to state %d, expected the garage" % rig.gs.state)

# ---------- S8, S7 on the real game ----------

func _real_game() -> void:
	_close_rig()
	_wipe(ProjectSettings.globalize_path(ROOT.path_join("saves")))
	SaveStore.slot = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))   # the rig left night 2 here
	SaveDirector.enabled = true
	GameState.title_seen = false
	GameState.garage_seen = false
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await physics_frame
	var gs: GameState = game.game_state
	var shop: Node = game.shop_day
	var wallet: Node = game.wallet
	var reached := await _wait_until(func() -> bool: return gs.state == GameState.State.DAWN)
	_check(reached, "S8 the boot dawn card never opened (state %d)" % gs.state)
	_check(shop.enabled and gs.workboard_gate.is_valid(), "S8 the shop is not on in the real game")
	gs.dawn_continue()
	await physics_frame
	var screen: Node = _find(game, "WorkBoardScreen")
	var garage: GarageScreen = _find(game, "GarageScreen")
	_check(gs.state == GameState.State.GARAGE and not screen.visible, "S8 a boot showed the board (state %d)" % gs.state)
	# The forecourt visit: no board either.
	gs.leave_garage()
	await physics_frame
	_check(gs.open_garage() and gs.state == GameState.State.GARAGE and not screen.visible, "S8 the forecourt showed the board")
	gs.leave_garage()
	await physics_frame
	# The dawn after night 1.
	game.night_clock.end_night()
	await physics_frame
	_check(gs.state == GameState.State.DAWN and gs.garage_entry == GameState.ENTRY_DAWN, "S8 6 a.m. did not open the dawn card (state %d)" % gs.state)
	gs.dawn_continue()
	await physics_frame
	_check(gs.state == GameState.State.WORKBOARD and screen.visible, "S8 the dawn after night 1 did not show the board (state %d)" % gs.state)
	_check(shop.card_ids()[0] == "halloran_brakes", "S8 first card is %s" % str(shop.card_ids()))
	_check(garage.board_button != null, "S7 no Walt's board row in the garage")
	# Esc does nothing on the board.
	gs.toggle_pause()
	_check(gs.state == GameState.State.WORKBOARD, "S8 Esc left the board")
	# To the garage, then Go out with nothing taken.
	screen.press(&"cancel")
	await physics_frame
	_check(gs.state == GameState.State.GARAGE and garage.board_button.visible, "S7 the garage did not show Walt's board row (state %d)" % gs.state)
	garage.out_delay = 0.0
	var bank0: int = wallet.bank
	var skip := WorkOrders.skip_pay(WorkOrders.act_for_night(1))
	_check(skip == 450, "S7 flat pay is $%d, expected $450" % skip)
	garage.out_button.pressed.emit()
	await physics_frame
	_check(gs.state == GameState.State.PLAYING, "S7 Go out did not leave (state %d)" % gs.state)
	_check(wallet.bank == bank0 + 450 and "day1:walt" in wallet.receipts, "S7 bank %d, expected %d with a Walt receipt" % [wallet.bank, bank0 + 450])
	_check(shop.stage() == "done", "S7 the day is %s, expected done" % shop.stage())
	# A second Go out the same day pays nothing.
	_check(gs.open_garage(), "S7 the forecourt did not open")
	await physics_frame
	_check(not garage.board_button.visible, "S7 Walt's board row shows on a settled day")
	var bank1: int = wallet.bank
	garage.out_button.pressed.emit()
	await physics_frame
	_check(wallet.bank == bank1 and gs.state == GameState.State.PLAYING, "S7 a second Go out paid (bank %d, was %d)" % [wallet.bank, bank1])
	print("shop_day: real game boot / dawn / Go out ok")

# ---------- helpers ----------

func _wait_until(cond: Callable) -> bool:
	for i in TIMEOUT_FRAMES:
		if cond.call():
			return true
		await physics_frame
	return false

func _find(n: Node, cls_or_name: String) -> Node:
	var sc: Script = n.get_script()
	if n.name == cls_or_name or (sc != null and sc.get_global_name() == cls_or_name):
		return n
	for c in n.get_children():
		var f := _find(c, cls_or_name)
		if f != null:
			return f
	return null

func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	DirAccess.remove_absolute(path)
