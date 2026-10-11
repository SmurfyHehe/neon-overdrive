extends SceneTree

# Work board W0 (2026-10-11): the pay rules, the board draw and the bank pay.
#   R1 pay_for equals a hand-worked table, to the dollar, all multiples of $10
#   R2 no order pays outside 0.10-0.45 nights (skip exactly 0.30, late <= 0.15)
#   R4 the same (slot, day) always draws the same three cards
#   R5 3 distinct cards, never recent / locked / away, <= 1 scrap, <= 1 per giver
#   R6 day 1 card 1 is halloran_brakes, every seed
#   W1 pay_shop pays once per receipt, to the bank, never cash
#   W2 the bank and receipts survive a reload; an old wallet.json loads
#   <godot> --headless --path . -s res://tests/core/work_orders.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const WorkOrders := preload("res://scripts/core/work_orders.gd")

const ROOT := "user://test_work_orders"

## Brake job, band 0.20-0.40, scores 0 / 0.5 / 1 (hand worked: nights x $1,500
## x act x difficulty, rounded to $10, halves up).
const TABLE := {
	"weekend_warrior": {1: [300, 450, 600], 2: [600, 900, 1200], 3: [900, 1350, 1800], "free": [900, 1350, 1800]},
	"daily_driver": {1: [380, 560, 750], 2: [750, 1130, 1500], 3: [1130, 1690, 2250], "free": [1130, 1690, 2250]},
	"racer": {1: [260, 380, 510], 2: [510, 770, 1020], 3: [770, 1150, 1530], "free": [770, 1150, 1530]},
}
const BRAKES := {"pay": {"min": 0.20, "max": 0.40}, "favour": false}

var failures: Array[String] = []

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	_r1()
	_r2()
	_r4_r6()
	_r5()
	_wallet()
	for m in failures:
		printerr("FAIL: ", m)
	print("work_orders: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _r1() -> void:
	var n := 0
	for diff in TABLE:
		for act in TABLE[diff]:
			var want: Array = TABLE[diff][act]
			for i in 3:
				var got := WorkOrders.pay_for(BRAKES, [0.0, 0.5, 1.0][i], act, diff)
				n += 1
				_check(got == want[i], "R1 %s act %s score %s: $%d, expected $%d" % [diff, str(act), [0.0, 0.5, 1.0][i], got, want[i]])
				_check(got % 10 == 0, "R1 $%d is not a multiple of $10" % got)
	_check(WorkOrders.pay_for(BRAKES, 0.6, 1) == 480, "R1 brake job at 0.6 act 1 is not $480")
	_check(WorkOrders.pay_for(BRAKES, 0.6, 2) == 960, "R1 act 2 is not $960")
	_check(WorkOrders.pay_for(BRAKES, 0.6, 3) == 1440, "R1 act 3 is not $1,440")
	_check(WorkOrders.skip_pay(1) == 450 and WorkOrders.skip_pay(2) == 900 and WorkOrders.skip_pay(3) == 1350, "R1 skip is not $450 / $900 / $1,350")
	_check(WorkOrders.range_text({"pay": {"min": 0.20, "max": 0.45}, "favour": false}, 1) == "$300-$680", "R1 card range is %s" % WorkOrders.range_text({"pay": {"min": 0.20, "max": 0.45}, "favour": false}, 1))
	# A friend's favour pays 0.05 less: 0.25-0.40 -> 0.20-0.35.
	var fav := {"pay": {"min": 0.25, "max": 0.40}, "favour": true}
	_check(WorkOrders.pay_for(fav, 0.0, 1) == 300 and WorkOrders.pay_for(fav, 1.0, 1) == 530, "R1 favour: $%d-$%d" % [WorkOrders.pay_for(fav, 0.0, 1), WorkOrders.pay_for(fav, 1.0, 1)])
	_check(WorkOrders.act_for_night(1) == 1 and WorkOrders.act_for_night(10) == 1 and WorkOrders.act_for_night(11) == 2
			and WorkOrders.act_for_night(22) == 2 and WorkOrders.act_for_night(23) == 3 and WorkOrders.act_for_night(30) == 3
			and WorkOrders.act_for_night(31) == "free", "R1 act_for_night edges")
	print("work_orders R1: %d pays against the hand table" % n)

func _ref(nights: float) -> Dictionary:
	return {"pay": {"min": nights, "max": nights}, "favour": false}

func _r2() -> void:
	var orders := WorkOrders.load_orders()
	_check(orders.size() >= 11, "R2 data has %d orders" % orders.size())
	var n := 0
	for o in orders:
		for act in [1, 2, 3, "free"]:
			for diff in TABLE:
				var floor_d := WorkOrders.pay_for(_ref(0.10), 0.0, act, diff)
				var cap_d := WorkOrders.pay_for(_ref(0.45), 0.0, act, diff)
				var skip_d := WorkOrders.pay_for(_ref(0.30), 0.0, act, diff)
				var late_cap := WorkOrders.pay_for(_ref(0.15), 0.0, act, diff)
				for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var p := WorkOrders.pay_for(o, s, act, diff)
					n += 1
					_check(p >= floor_d and p <= cap_d, "R2 %s score %s %s act %s: $%d outside $%d-$%d" % [o.id, s, diff, str(act), p, floor_d, cap_d])
					var sk := WorkOrders.pay_for(o, s, act, diff, {"skip": true})
					_check(sk == skip_d, "R2 skip pays $%d, expected $%d" % [sk, skip_d])
					var late := WorkOrders.pay_for(o, s, act, diff, {"stay_late": true})
					_check(late <= late_cap, "R2 %s stay late $%d above $%d" % [o.id, late, late_cap])
	print("work_orders R2: %d pays inside the band" % n)

func _r4_r6() -> void:
	var same := 0
	for day in range(1, 1001):
		var slot := 1 + day % 3
		var a := WorkOrders.draw(slot, day, [])
		var b := WorkOrders.draw(slot, day, [])
		_check(a == b, "R4 slot %d day %d drew two boards" % [slot, day])
		same += 1
	for slot in range(1, 1001):
		var c := WorkOrders.draw(slot, 1, [])
		_check(c.size() == 3 and c[0] == "halloran_brakes", "R6 slot %d day 1 board is %s" % [slot, str(c)])
	print("work_orders R4/R6: %d repeat draws, 1000 day-1 seeds" % same)

func _r5() -> void:
	var orders := WorkOrders.load_orders()
	var by_id := {}
	for o in orders:
		by_id[o.id] = o
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var recent: Array = []
	var fills := 0
	for day in range(1, 1001):
		var cards := WorkOrders.draw(1, day, recent)
		_check(cards.size() == 3, "R5 day %d drew %d cards" % [day, cards.size()])
		var seen := {}
		var scraps := 0
		var givers := {}
		for id in cards:
			_check(not seen.has(id), "R5 day %d repeats %s" % [day, id])
			seen[id] = true
			var o: Dictionary = by_id[id]
			_check(WorkOrders.is_unlocked(o, day), "R5 day %d shows locked %s" % [day, id])
			_check(not WorkOrders.is_away(o, day), "R5 day %d shows away %s" % [day, id])
			_check(not id in recent, "R5 day %d shows recent %s" % [day, id])
			if o.kind == "scrap":
				scraps += 1
			if id.begins_with(WorkOrders.FILL_PREFIX):
				fills += 1
			else:
				_check(not givers.has(o.giver), "R5 day %d has two cards from %s" % [day, o.giver])
				givers[o.giver] = true
		_check(scraps <= 1, "R5 day %d has %d scrap cards" % [day, scraps])
		recent.append(cards[rng.randi() % 3])
		while recent.size() > 3:
			recent.remove_at(0)
	print("work_orders R5: 1000 days, %d fill cards" % fills)

# ---------- the wallet ----------

func _wallet() -> void:
	_wipe(ProjectSettings.globalize_path(SaveStore.slot_dir()))
	var w: Node = Wallet.new()
	root.add_child(w)
	w.add_cash(123)
	_check(w.pay_shop(450, "day4:halloran_brakes"), "W1 first pay_shop refused")
	_check(w.bank == 450 and w.cash == 123, "W1 bank %d cash %d, expected 450 / 123" % [w.bank, w.cash])
	_check(not w.pay_shop(450, "day4:halloran_brakes"), "W1 the same receipt paid twice")
	_check(w.bank == 450 and w.cash == 123, "W1 a second pay changed money (bank %d cash %d)" % [w.bank, w.cash])
	_check(not w.pay_shop(100, ""), "W1 an empty receipt paid")
	for i in 12:
		w.pay_shop(10, "day%d:x" % i)
	_check(w.receipts.size() == 10, "W1 %d receipts kept, expected 10" % w.receipts.size())
	var bank: int = w.bank
	var receipts: Array = w.receipts.duplicate()
	root.remove_child(w)
	w.free()
	# W2: a fresh wallet from the file.
	var r: Node = Wallet.new()
	root.add_child(r)
	_check(r.bank == bank and r.cash == 123, "W2 reload gave bank %d cash %d, expected %d / 123" % [r.bank, r.cash, bank])
	_check(r.receipts == receipts, "W2 receipts changed on reload: %s" % str(r.receipts))
	_check(not r.pay_shop(10, receipts.back()), "W2 a reloaded wallet paid an old receipt")
	root.remove_child(r)
	r.free()
	# An old wallet.json without receipts.
	var path := SaveStore.file("wallet")
	_wipe(ProjectSettings.globalize_path(SaveStore.slot_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveStore.slot_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(AtomicJson.encode({"cash": 7, "bank": 90}))  # no receipts key, as before W0
	f.close()
	SaveStore.SaveCore.forget()   # as a relaunch: the old slot is upgraded on load
	var old := SaveStore.load_wallet()
	_check(old.cash == 7 and old.bank == 90 and old.receipts == [], "W2 old wallet loaded as %s" % str(old))
	print("work_orders W1/W2: pay once, reload, old file")

func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	DirAccess.remove_absolute(path)
