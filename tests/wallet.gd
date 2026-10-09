extends SceneTree

# Money counter test (police build plan F0, 2026-10-09: "cash in, dawn banks
# it, save and load; 3 amounts x bank / no bank x reload; fails if any money
# is lost or doubled").
#
# Part 1, the wallet on its own (its own save folder):
# - for each amount, banked or not: add the cash, reload a fresh wallet from
#   the file, and the cash and bank are exactly what they should be; then a
#   second bank_night adds nothing (no doubling);
# - take_cash / take_bank never go below 0 and say what they took;
# - during a chase the save is refused and the wallet keeps the change, then
#   writes it on its own once the chase ends; a reload sees it;
# - money() formats "$0", "$999", "$1,250", "$1,000,000".
# Part 2, the real game: cash added in the game shows on the HUD, the clock
# rolled past 6 a.m. moves it into the bank, and the pause screen shows it.
#   <godot> --headless --path . -s res://tests/wallet.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const Wallet := preload("res://scripts/wallet.gd")
const Harness := preload("res://tests/traffic_harness.gd")

const ROOT := "user://test_wallet"
const AMOUNTS := [1, 250, 98765]

var failures: Array[String] = []
var game: Node
var ticks := 0

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	_format()
	_sweep()
	_take()
	_chase()
	# Part 2 boots the game on a fresh slot of the same folder.
	SaveStore.select_slot(2)
	game = Harness.boot(self, 0, 300.0, 5)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _wallet() -> Node:
	var w: Node = Wallet.new()
	root.add_child(w)  # _ready loads the file
	return w

func _drop(w: Node) -> void:
	root.remove_child(w)
	w.free()

func _clear_slot() -> void:
	_wipe(ProjectSettings.globalize_path(SaveStore.slot_dir()))

func _format() -> void:
	for pair in [[0, "$0"], [999, "$999"], [1250, "$1,250"], [1000000, "$1,000,000"], [-1250, "-$1,250"]]:
		_check(Wallet.money(pair[0]) == pair[1], "money(%d) is %s, expected %s" % [pair[0], Wallet.money(pair[0]), pair[1]])

func _sweep() -> void:
	for amount in AMOUNTS:
		for do_bank in [false, true]:
			_clear_slot()
			var w := _wallet()
			_check(w.cash == 0 and w.bank == 0, "fresh slot starts with %d cash, %d bank" % [w.cash, w.bank])
			w.add_cash(amount)
			w.add_cash(0)
			w.add_cash(-5)  # ignored
			if do_bank:
				w.bank_night()
			_drop(w)
			var r := _wallet()
			var want_cash: int = 0 if do_bank else amount
			var want_bank: int = amount if do_bank else 0
			var label := "%d %s" % [amount, "banked" if do_bank else "not banked"]
			_check(r.cash == want_cash and r.bank == want_bank, "%s: reload gave cash %d bank %d, expected %d / %d" % [label, r.cash, r.bank, want_cash, want_bank])
			# Banking again (a second dawn, a repeated signal) moves nothing new.
			r.bank_night()
			r.bank_night()
			_check(r.cash == 0 and r.bank == amount, "%s: banking twice gave cash %d bank %d, expected 0 / %d" % [label, r.cash, r.bank, amount])
			_drop(r)
			var r2 := _wallet()
			_check(r2.cash + r2.bank == amount, "%s: after reload the total is %d, expected %d" % [label, r2.cash + r2.bank, amount])
			_drop(r2)
	print("wallet: %d amounts x bank / no bank x reload" % AMOUNTS.size())

func _take() -> void:
	_clear_slot()
	var w := _wallet()
	w.add_cash(300)
	w.bank_night()
	w.add_cash(40)
	_check(w.take_cash(100) == 40 and w.cash == 0, "take_cash took more than there was")
	_check(w.take_bank(120) == 120 and w.bank == 180, "take_bank 120 of 300 left %d" % w.bank)
	_check(w.take_bank(1000) == 180 and w.bank == 0, "take_bank emptied wrongly (%d left)" % w.bank)
	_drop(w)
	var r := _wallet()
	_check(r.cash == 0 and r.bank == 0, "takes not saved (cash %d bank %d)" % [r.cash, r.bank])
	_drop(r)

func _chase() -> void:
	_clear_slot()
	var w := _wallet()
	w.add_cash(100)
	SaveStore.begin_chase()
	w.add_cash(50)  # refused by the store: the wallet must hold on to it
	_check(w.cash == 150, "the wallet lost the chase cash (%d)" % w.cash)
	_check(int(SaveStore.load_wallet().cash) == 100, "a save went through during a chase")
	SaveStore.end_chase()
	w._process(0.0)  # the next frame writes the held change
	_check(int(SaveStore.load_wallet().cash) == 150, "the held cash was not written after the chase (%d)" % int(SaveStore.load_wallet().cash))
	_drop(w)

# ---------- part 2 ----------

func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks == 30:
		var w: Node = game.get("wallet")
		_check(w != null, "the game has no wallet")
		if w == null:
			return _end()
		w.add_cash(1250)
		var hud_cash := _find(game, "Cash") as Label
		_check(hud_cash != null, "no Cash label on the HUD")
	if ticks == 32:
		var w: Node = game.get("wallet")
		var hud_cash := _find(game, "Cash") as Label
		if hud_cash != null:
			_check(hud_cash.text == "$1,250", "HUD cash reads '%s'" % hud_cash.text)
		var clock: NightClock = game.get("night_clock")
		var bank_before: int = w.bank
		# Roll to 6 a.m.: the rest of the night in one step.
		clock.advance((NightClock.NIGHT_MINUTES - clock.minutes + 1.0) * NightClock.REAL_SECONDS_PER_HOUR / 60.0)
		_check(w.cash == 0 and w.bank == bank_before + 1250, "6 a.m. left cash %d bank %d (bank was %d)" % [w.cash, w.bank, bank_before])
		_check(int(SaveStore.load_wallet().bank) == w.bank, "the banked night was not saved")
		var gs: GameState = game.get("game_state")
		gs.pause()
	if ticks == 36:
		var w: Node = game.get("wallet")
		var bank_lbl := _find(game, "Bank") as Label
		_check(bank_lbl != null and bank_lbl.visible and bank_lbl.text.contains(Wallet.money(w.bank)), "pause screen bank reads '%s'" % (bank_lbl.text if bank_lbl != null else "<none>"))
		return _end()
	return false

func _find(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var f := _find(c, name)
		if f != null:
			return f
	return null

func _end() -> bool:
	for m in failures:
		printerr("FAIL: ", m)
	print("wallet: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	DirAccess.remove_absolute(path)
