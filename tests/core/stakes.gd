extends SceneTree

# Stakes test (S1, docs/planning/races-in-the-world-2026-10-14.md): race pay,
# escape pay and bust bills move real money.
#
# Part 1, the rules: pay and bill tables, difficulty, rounding, the stamp's
# bounce.
# Part 2, Stakes on stand-in race / police / heat / clock with a real wallet
# (its own save folder, test build off so money really moves):
# - a race win pays $450 cash, a loss pays nothing;
# - an escape pays by the HIGHEST heat the chase reached, not the last;
# - night one: the first bust is a warning (nothing charged, no hour), the
#   second is charged;
# - an honest bust takes the bill from the bank (never below 0), keeps the
#   cash and adds an hour;
# - a bust mid-race ends the race (busted() called);
# - a bad-cop bust takes all tonight's cash and leaves the bank.
# Part 3, the real game: Stakes is there and wired to the race and police.
#   <godot> --headless --path . -s res://tests/core/stakes.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const Stakes := preload("res://scripts/core/stakes.gd")
const TestBuild := preload("res://scripts/core/test_build.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const ROOT := "user://test_stakes"

class FakeRace extends Node:
	signal race_ended(result: int)
	var racing := false
	var busted_calls := 0
	func is_racing() -> bool:
		return racing
	func busted() -> void:
		busted_calls += 1
		racing = false

class FakePolice extends Node:
	signal pursuit_started
	signal pursuit_ended(escaped: bool)
	signal busted(cop: Node3D)

class FakeHeat extends Node:
	signal level_changed(level: int)
	var level := 0
	var bad_cops: Array[Node3D] = []
	func set_level(l: int) -> void:
		level = l
		level_changed.emit(l)

class FakeClock extends Node:
	var night := 1
	var minutes := 0.0
	func add_minutes(m: float) -> void:
		minutes += m

var failures: Array[String] = []
var game: Node
var ticks := 0

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	_rules()
	TestBuild.forced = 0
	_flow()
	TestBuild.forced = -1
	SaveStore.select_slot(2)
	game = Harness.boot(self, 0, 300.0, 5)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

# ---------- part 1 ----------

func _rules() -> void:
	_check(Stakes.race_pay(1) == 450 and Stakes.race_pay(2) == 0 and Stakes.race_pay(4) == 0, "race pay is not $450 for a win and 0 otherwise")
	_check(Stakes.race_pay(1, "rolling") == 250 and Stakes.race_pay(2, "rolling") == 0, "a rolling challenge win does not pay $250")
	var esc := [0, 75, 150, 225, 375, 525]
	for lvl in 6:
		_check(Stakes.escape_pay(lvl) == esc[lvl], "escape pay at heat %d is %d, want %d" % [lvl, Stakes.escape_pay(lvl), esc[lvl]])
	_check(Stakes.escape_pay(9) == 525, "escape pay past heat 5 is not capped")
	var ww := [120, 120, 225, 375, 600, 825]   # heat 0 bills as heat 1
	for lvl in 6:
		_check(Stakes.bust_bill(lvl, 1) == ww[lvl], "bust at heat %d is %d, want %d" % [lvl, Stakes.bust_bill(lvl, 1), ww[lvl]])
	_check(Stakes.bust_bill(5, 0) == 620 and Stakes.bust_bill(5, 2) == 1030, "difficulty: heat 5 bills %d / %d, want 620 / 1030" % [Stakes.bust_bill(5, 0), Stakes.bust_bill(5, 2)])
	for lvl in 6:
		for d in 3:
			_check(Stakes.bust_bill(lvl, d) % 5 == 0, "bill at heat %d difficulty %d is not a round $5" % [lvl, d])
	_check(Stakes.ticket_part(375) == 225, "ticket share of $375 is %d" % Stakes.ticket_part(375))
	_check(is_equal_approx(Stakes.stamp_scale(0.0), Stakes.STAMP_START_SCALE) and is_equal_approx(Stakes.stamp_scale(5.0), 1.0), "the stamp does not start big and end at size")
	var dipped := false
	for i in 23:
		if Stakes.stamp_scale(i * 0.01) < 0.95:
			dipped = true
	_check(dipped, "the stamp has no bounce under size")
	print("stakes: rules checked")

# ---------- part 2 ----------

func _flow() -> void:
	_wipe(ProjectSettings.globalize_path(SaveStore.slot_dir()))
	var w: Node = Wallet.new()
	root.add_child(w)
	var race := FakeRace.new()
	var pol := FakePolice.new()
	var heat := FakeHeat.new()
	var clock := FakeClock.new()
	for n in [race, pol, heat, clock]:
		root.add_child(n)
	var s: Node = Stakes.new()
	root.add_child(s)
	s.bind(race, pol, heat, w, clock)
	var got: Array = []
	s.paid.connect(func(a: int, acc: String, why: String) -> void: got.append([a, acc, why]))

	race.race_ended.emit(1)
	_check(w.cash == 450, "race win: cash %d, want 450" % w.cash)
	race.race_ended.emit(2)
	_check(w.cash == 450, "a lost race paid (cash %d)" % w.cash)

	# Escape: heat 1 -> 3 -> cooled to 0, paid at 3.
	heat.set_level(1)
	pol.pursuit_started.emit()
	heat.set_level(3)
	heat.set_level(2)
	heat.set_level(0)
	pol.pursuit_ended.emit(true)
	_check(w.cash == 675, "escape from peak heat 3: cash %d, want 675" % w.cash)
	pol.pursuit_ended.emit(true)
	_check(w.cash == 675, "a repeated escape signal paid twice (cash %d)" % w.cash)

	w.bank_night()   # $675 to the bank
	w.add_cash(100)

	# Night one: warning first.
	clock.night = 1
	_bust(pol, heat, 2)
	_check(w.bank == 675 and w.cash == 100 and clock.minutes == 0.0, "night one's first bust charged: bank %d cash %d minutes %.0f" % [w.bank, w.cash, clock.minutes])
	_bust(pol, heat, 2)
	_check(w.bank == 450 and w.cash == 100 and clock.minutes == 60.0, "night one's second bust: bank %d cash %d minutes %.0f, want 450 / 100 / 60" % [w.bank, w.cash, clock.minutes])

	# Night two, mid-race, heat 4 ($600) with only $450 in the bank.
	clock.night = 2
	race.racing = true
	_bust(pol, heat, 4)
	_check(race.busted_calls == 1 and not race.racing, "a bust mid-race did not end the race")
	_check(w.bank == 0 and w.cash == 100 and clock.minutes == 120.0, "heat 4 bust on a short bank: bank %d cash %d minutes %.0f, want 0 / 100 / 120" % [w.bank, w.cash, clock.minutes])
	_check(s.chasing == false, "still chasing after a bust")

	# Bad cop: all the cash, bank kept.
	w.pay_shop(300, "test:bank")
	w.add_cash(250)
	var bad := Node3D.new()
	root.add_child(bad)
	heat.bad_cops.append(bad)
	heat.set_level(3)
	pol.pursuit_started.emit()
	heat.set_level(0)
	pol.busted.emit(bad)
	pol.pursuit_ended.emit(false)
	_check(w.cash == 0 and w.bank == 300 and clock.minutes == 120.0, "bad cop: cash %d bank %d minutes %.0f, want 0 / 300 / 120" % [w.cash, w.bank, clock.minutes])
	_check(race.busted_calls == 1, "busted() called with no race on")

	var reasons: Array = got.map(func(e: Array) -> String: return e[2])
	_check(reasons == ["race", "escape", "warning", "bust", "bust", "bad_cop"], "announcements were %s" % str(reasons))
	_check(s.won == 450 and s.escaped_pay == 225 and s.bust_paid == 675 and s.bad_cop_taken == 350,
		"totals won %d escaped %d bust %d bad %d" % [s.won, s.escaped_pay, s.bust_paid, s.bad_cop_taken])
	# The stamp runs its queue down.
	for i in 400:
		s._process(1.0 / 30.0)
	_check(s._queue.is_empty() and s._stamp_t < 0.0, "the stamp queue did not empty (%d left, t %.2f)" % [s._queue.size(), s._stamp_t])
	for n in [s, race, pol, heat, clock, w, bad]:
		root.remove_child(n)
		n.free()
	print("stakes: flow checked")

func _bust(pol: FakePolice, heat: FakeHeat, lvl: int) -> void:
	heat.set_level(lvl)
	pol.pursuit_started.emit()
	heat.set_level(0)   # the patrol clears heat before it says busted
	pol.busted.emit(null)
	pol.pursuit_ended.emit(false)

# ---------- part 3 ----------

func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks == 30:
		var s: Node = game.get("stakes")
		_check(s != null and s.name == "Stakes", "the game has no Stakes node")
		var race: Node = game.get("race")
		if s != null and race != null:
			_check(race.race_ended.is_connected(s._on_race_ended), "Stakes is not wired to the race")
		var pol: Node = game.get("police")
		if s != null and pol != null:
			_check(pol.busted.is_connected(s._on_busted) and pol.pursuit_ended.is_connected(s._on_pursuit_ended), "Stakes is not wired to the police")
		return _end()
	return false

func _end() -> bool:
	for m in failures:
		printerr("FAIL: ", m)
	print("stakes: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
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
