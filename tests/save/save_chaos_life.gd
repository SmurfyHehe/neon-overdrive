extends SceneTree

# Save chaos (stress layer D, 2026-10-13): ONE life of the game, which
# tests/save/save_chaos.py kills with kill -9 at a random moment and starts
# again. Run on its own it never ends; the runner is what stops it.
#
# Every life first checks what the last one left on disk, before anything
# writes, then plays on with random steps until it is killed. Each step writes
# a "begin" line to a ledger outside the save folder (what the save holds now,
# and what it must hold once the step is done), does the step through the
# game's own code, then an "end" line with what is really on disk. After a
# kill the next life reads the ledger:
#   - last line "end": the save must be exactly what that step left;
#   - last line "begin": the save must be what it was before the step, or what
#     it is after it. Anything in between (money paid and the part missing,
#     the night banked twice, a chase that is not a bust) is a failure.
# "What the save holds" (sig()) is read the way the game reads it: slot, bank,
# tonight's cash, night, nights closed, car, parts owned, parts fitted, shop
# receipts, special unlocks, busts waiting, chase open, a run to resume, and
# the car's fuel (compared only around a pump fill: it burns while driving).
# Every slot file's main copy must also read back whole (a torn .tmp is fine:
# that is a kill inside a write, and it is counted).
#
# Modes (CHAOS_MODE):
#   game     the real Game.tscn from the title: drive with autosaves, pause,
#            police chase, cash, shop pay, the 6 a.m. dawn on the real clock,
#            a garage part, a pump fill, restart, quit to title, slot switch,
#            car switch.
#   core     the same money and save steps without the scene, in a tight loop,
#            so most kills land inside a write.
#   upgrade  a version 1 save (tests/save/fixtures/v1) upgraded over and over;
#            a kill mid-upgrade must leave either the untouched old files or
#            the whole upgrade.
#
# Env: CHAOS_DIR (ledger and verdicts, outside user://), CHAOS_MODE,
# CHAOS_SEED, CHAOS_LIFE (life number), CHAOS_VERIFY_ONLY=1 (check and quit).
# The save folder is the real "user://saves", so run it with its own
# XDG_DATA_HOME (the runner does): it never touches a real player's saves.

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const GarageMods := preload("res://scripts/car/garage_mods.gd")
const TestBuild := preload("res://scripts/core/test_build.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const PlayerTune := preload("res://scripts/car/player_tune.gd")

const FIXTURE := "res://tests/save/fixtures/v1"
## Fields that drift on their own while driving; compared only where a step says.
const ALWAYS_LOOSE := ["fuel"]

var dir := ""
var mode := "game"
var life := 0
var rng := RandomNumberGenerator.new()
var ledger: FileAccess
var cur := {}          # the save as the last step left it (sig)
var step_no := 0
var fails := 0

# game mode
var game: Node
var bot: RefCounted
var phase := "boot"
var _busy := false
var _ticks := 0

# core mode
var wallet: Node
var fuel: Object
var core_car := "p1_coupe"

func _initialize() -> void:
	dir = OS.get_environment("CHAOS_DIR")
	mode = OS.get_environment("CHAOS_MODE") if OS.get_environment("CHAOS_MODE") != "" else "game"
	life = int(OS.get_environment("CHAOS_LIFE"))
	rng.seed = hash("%s:%d:%s" % [mode, life, OS.get_environment("CHAOS_SEED")])
	if dir == "":
		push_error("save_chaos_life: CHAOS_DIR is not set")
		quit(2)
		return
	# The shipped game's save settings, not test mode's.
	SaveCore.root = "user://saves"
	SaveCore.persist = true
	SaveCore.legacy_dir = "user://" if mode != "upgrade" else "user://chaos_v1_global"
	SaveCore.slot = 0
	SaveCore.chase_active = false
	SaveDirector.enabled = true
	TestBuild.forced = 0   # money is real: the sandbox pays everything for free
	# The clock, dirt and tunes in the slot, as in the game (test mode keeps
	# them in shared test_ files, which would leak between slots here).
	NightClock.path = NightClock.DEFAULT_PATH
	CarDirt.path = CarDirt.DEFAULT_PATH
	PlayerTune.enabled = true
	ExhaustTune.save_path = ExhaustTune.DEFAULT_PATH
	var ok := _verify()
	if OS.get_environment("CHAOS_VERIFY_ONLY") == "1":
		quit(0 if ok else 1)
		return
	ledger = FileAccess.open(dir.path_join("ledger.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(dir.path_join("ledger.jsonl")) else FileAccess.WRITE)
	ledger.seek_end()
	_log({"t": "life", "life": life, "mode": mode})
	match mode:
		"game":
			_game_boot()
		"core":
			_core_start()
		"upgrade":
			_upgrade_loop.call_deferred()

# ---------------------------------------------------------------- the save now

## What the save holds, read from disk the way the game reads it.
static func sig() -> Dictionary:
	SaveCore.forget()
	var keep_slot := SaveCore.slot
	SaveCore.slot = 0
	var n := SaveCore.active_slot()
	SaveCore.slot = keep_slot if keep_slot > 0 else n
	var s := sig_of(n)
	s.slot = n
	return s

static func sig_of(n: int) -> Dictionary:
	var c := SaveCore.career(n)
	var story := SaveCore._block(c, "story")
	var parts := {}
	var fitted := {}
	var cars := SaveCore._block(c, "cars")
	for id in cars:
		if cars[id] is Dictionary:
			var p: Array = SaveStore._string_list(cars[id].get("parts_owned"))
			var f: Array = SaveStore._string_list(cars[id].get("fitted"))
			p.sort()
			f.sort()
			if not p.is_empty():
				parts[str(id)] = p
			if not f.is_empty():
				fitted[str(id)] = f
	var special: Array = SaveStore.load_special(n).unlocked.keys()
	special.sort()
	var m := SaveCore.meta(n)
	var car := SaveCore.current_car(n)
	var fl: Variant = SaveCore._block(SaveCore.car_state(car, n), "fuel").get("litres")
	return {
		"locked": SaveCore.locked(n),
		"bank": SaveCore.bank(n), "cash": SaveCore.cash(n),
		"night": maxi(SaveCore._int(story.get("night", 1)), 1), "closed": SaveCore._int(story.get("night_closed")),
		"car": car, "parts": parts, "fitted": fitted,
		"receipts": SaveStore._receipts(n), "special": special,
		"busts": m.pending_busts, "chase": m.chase_open,
		"run": not SaveCore.run(n).is_empty(),
		"fuel": snappedf(float(fl), 0.01) if SaveCore._is_num(fl) else -1.0,
		# The night clock is on the story's night (a slot switch once leaked
		# another slot's clock in, and every autosave was then dropped).
		"clock_ok": int(SaveCore.clock(n).night) == maxi(SaveCore._int(story.get("night", 1)), 1),
	}

static func canon(x: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(x)), "", true)

static func same(a: Dictionary, b: Dictionary, loose: Array) -> bool:
	var x := a.duplicate(true)
	var y := b.duplicate(true)
	for k in loose + ALWAYS_LOOSE:
		x.erase(k)
		y.erase(k)
	return canon(x) == canon(y)

static func diff(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	for k in a:
		if canon(a.get(k)) != canon(b.get(k)):
			out.append("%s: %s vs %s" % [k, canon(a.get(k)), canon(b.get(k))])
	return out

## Every slot file's main copy reads back whole; counts .tmp copies (a kill
## inside a write) and torn ones.
static func files_report(allow_plain := false) -> Dictionary:
	var out := {"torn_main": [], "tmp": 0, "torn_tmp": 0}
	var root := ProjectSettings.globalize_path("user://saves")
	var dirs := [root]
	for n in range(1, SaveCore.SLOTS + 1):
		dirs.append(root.path_join("slot_%d" % n))
	for d in dirs:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			var p: String = d.path_join(f)
			if f.ends_with(".json"):
				var text := FileAccess.get_file_as_string(p)
				# Version 1 files are plain JSON with no header (upgrade mode).
				var plain := allow_plain and JSON.parse_string(text) is Dictionary
				if AtomicJson.decode(text) == null and not plain:
					out.torn_main.append(p.trim_prefix(root))
			elif f.ends_with(".json.tmp"):
				out.tmp += 1
				if AtomicJson.decode(FileAccess.get_file_as_string(p)) == null:
					out.torn_tmp += 1
	return out

# ---------------------------------------------------------------- the check

func _verify() -> bool:
	var lines := _read_ledger()
	var last := {}
	var last_life := {}
	for l in lines:
		if l.get("t") in ["begin", "end"]:
			last = l
		elif l.get("t") == "life":
			last_life = l
	var verdict := {"life": life, "mode": mode, "after_life": last_life.get("life", -1)}
	var files := files_report(mode == "upgrade")
	verdict.files = files
	# A kill while the upgrade mode lays the old save down again tears the
	# harness's own copies, not the game's.
	var resetting: bool = mode == "upgrade" and last.get("op") == "reset" and last.get("t") == "begin"
	var ok: bool = files.torn_main.is_empty() or resetting
	if mode == "upgrade":
		var u := _upgrade_check(last)
		ok = ok and u.ok
		verdict.merge(u, true)
	else:
		var s := sig()
		verdict.got = s
		if last.is_empty():
			verdict.case = "fresh"
		elif last.t == "end":
			verdict.case = "after:" + str(last.op)
			verdict.phase = last.get("phase", "")
			var want: Dictionary = last.sig
			ok = ok and same(s, want, [])
			if not same(s, want, []):
				verdict.diff = diff(s, want)
		else:
			verdict.case = "during:" + str(last.op)
			verdict.phase = last.get("phase", "")
			var before: Dictionary = last.before
			var after: Dictionary = last.after
			var loose: Array = last.get("loose", [])
			var hit := same(s, before, loose) or same(s, after, loose)
			if last.op == "refuel":
				hit = _refuel_ok(s, last)
			if not hit:
				verdict.diff_before = diff(s, before)
				verdict.diff_after = diff(s, after)
			ok = ok and hit
	verdict.ok = ok
	var f := FileAccess.open(dir.path_join("verdicts.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(dir.path_join("verdicts.jsonl")) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(verdict))
	f.close()
	print("CHAOS VERIFY life %d %s %s" % [life, "OK" if ok else "FAIL", verdict.get("case", "")])
	if not ok:
		print(JSON.stringify(verdict))
	return ok

## Paid fuel arrived, unpaid fuel did not: the bank and the tank move together.
static func _refuel_ok(s: Dictionary, l: Dictionary) -> bool:
	var b: Dictionary = l.before
	var rest := ["fuel", "bank"]
	if not same(s, b, rest + l.get("loose", [])):
		return false
	if int(s.bank) == int(b.bank):
		return float(s.fuel) <= float(b.fuel) + 0.5
	if int(s.bank) == int(b.bank) - int(l.cost):
		return float(s.fuel) >= float(b.fuel) + float(l.got) - 1.0
	return false

func _read_ledger() -> Array:
	var out := []
	var p := dir.path_join("ledger.jsonl")
	if not FileAccess.file_exists(p):
		return out
	for line in FileAccess.get_file_as_string(p).split("\n", false):
		var v: Variant = JSON.parse_string(line)
		if v is Dictionary:
			out.append(v)   # a line torn by the kill is skipped: its step had not started
	return out

func _log(d: Dictionary) -> void:
	ledger.store_line(JSON.stringify(d))
	ledger.flush()

# ---------------------------------------------------------------- steps

## Starts a step: `after` is what the save must hold once it is done.
func _begin(op: String, after: Dictionary, loose: Array = [], extra: Dictionary = {}) -> void:
	step_no += 1
	var d := {"t": "begin", "op": op, "phase": phase, "n": step_no, "before": cur, "after": after, "loose": loose}
	d.merge(extra)
	_log(d)

## Ends a step: checks the save against what it should hold.
func _end(op: String, after: Dictionary, loose: Array = []) -> void:
	var s := sig()
	var ok := same(s, after, loose)
	_log({"t": "end", "op": op, "phase": phase, "n": step_no, "sig": s, "ok": ok})
	if not ok:
		fails += 1
		print("CHAOS STEP FAIL life %d %s: %s" % [life, op, diff(s, after)])
	cur = s

func _with(changes: Dictionary) -> Dictionary:
	var a := cur.duplicate(true)
	a.merge(changes, true)
	return a

# ---------------------------------------------------------------- game mode

func _game_boot() -> void:
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_GARAGE", "0")
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_WRECK", "0")   # a wreck ends the run on its own
	cur = sig()
	# The boot itself is a step: a chase left open is a bust, the run is not resumed.
	var after := cur.duplicate(true)
	if cur.chase:
		after.busts = int(cur.busts) + 1
		after.chase = false
		after.run = false
	phase = "title"
	_begin("boot", after, ["run"] if cur.chase else [])
	_load_game()
	_game_loop.call_deferred(after)

func _load_game() -> void:
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game

func _wait(ticks: int) -> void:
	for i in ticks:
		await physics_frame

## The scene after a reload_current_scene (restart, quit to title, slot switch).
func _reloaded() -> void:
	await process_frame
	await process_frame
	while current_scene == null or current_scene == game or not current_scene.is_inside_tree():
		await process_frame
	game = current_scene
	await _wait(10)

func _game_loop(boot_after: Dictionary) -> void:
	await _wait(40)
	_end("boot", boot_after)
	while true:
		await _game_step()

func _gs() -> GameState:
	return game.game_state

func _driving() -> bool:
	return _gs().state == GameState.State.PLAYING

func _ensure_driving() -> void:
	if _gs().state == GameState.State.TITLE:
		phase = "title"
		_begin("title_wait", cur)
		await _wait(rng.randi_range(20, 120))
		_end("title_wait", cur)
		_begin("start_drive", cur)
		_gs().start_drive()
		await _wait(5)
		_end("start_drive", cur)
	if _driving() and bot == null:
		bot = TestDriver.start(game, "clean", {"speed": 120.0})
		# The police signals stay wired (the step emits them); their AI is off,
		# so a real pursuit or a bad cop never changes the save behind a step.
		for n in [game.get("police"), game.get("police_heat")]:
			if n != null:
				n.process_mode = Node.PROCESS_MODE_DISABLED

func _game_step() -> void:
	await _ensure_driving()
	if not _driving():
		await _wait(5)
		return
	var chase: bool = cur.chase
	var pick := rng.randi_range(0, 99)
	if chase:
		if pick < 45:
			await _g_drive("chase")
		elif pick < 70:
			await _g_chase_end()
		elif pick < 85:
			await _g_restart()
		else:
			await _g_quit_title()
		return
	if pick < 22:
		await _g_drive("race")
	elif pick < 30:
		await _g_pause()
	elif pick < 40:
		await _g_chase_begin()
	elif pick < 48:
		await _g_cash()
	elif pick < 55:
		await _g_shop_pay()
	elif pick < 66:
		await _g_dawn()
	elif pick < 74:
		await _g_buy()
	elif pick < 82:
		await _g_refuel()
	elif pick < 87:
		await _g_restart()
	elif pick < 92:
		await _g_quit_title()
	elif pick < 96:
		await _g_slot()
	else:
		await _g_car()

## Mid-race / mid-chase: drive with the autosave firing every half second
## (refused in a chase).
func _g_drive(p: String) -> void:
	phase = p
	var after := cur if cur.chase else _with({"run": true})
	_begin("drive", after)
	var until := Time.get_ticks_msec() + rng.randi_range(800, 4000)
	while Time.get_ticks_msec() < until:
		if game.saver._left > 0.5:
			game.saver._left = 0.5
		await physics_frame
	_end("drive", after)

## The pause menu: opening it saves the run (Esc refuses it in a chase).
func _g_pause() -> void:
	phase = "menu"
	var after := _with({"run": true})
	_begin("pause", after)
	_gs().toggle_pause()
	await _wait(rng.randi_range(5, 60))
	_gs().toggle_pause()
	await _wait(3)
	_end("pause", after)

func _g_chase_begin() -> void:
	phase = "chase"
	var after := _with({"chase": true})
	_begin("chase_begin", after)
	if game.police != null:
		game.police.pursuit_started.emit()
	else:
		SaveCore.begin_chase()
	await _wait(3)
	_end("chase_begin", after)

func _g_chase_end() -> void:
	phase = "chase"
	var after := _with({"chase": false})
	_begin("chase_end", after, ["run"])
	if game.police != null:
		game.police.pursuit_ended.emit(true)
	else:
		SaveCore.end_chase()
	await _wait(3)
	_end("chase_end", after, ["run"])

func _g_cash() -> void:
	phase = "race"
	var k := rng.randi_range(1, 400)
	var after := _with({"cash": int(cur.cash) + k})
	_begin("cash", after)
	game.wallet.add_cash(k)
	await _wait(2)
	_end("cash", after)

## Walt's shop pay: bank and receipt in one commit.
func _g_shop_pay() -> void:
	phase = "shop"
	var k := rng.randi_range(200, 3000)
	var r := "chaos:%d:%d" % [life, step_no + 1]
	var rec: Array = cur.receipts.duplicate()
	rec.append(r)
	while rec.size() > Wallet.RECEIPTS_KEPT:
		rec.remove_at(0)
	var after := _with({"bank": int(cur.bank) + k, "receipts": rec})
	_begin("shop_pay", after)
	game.wallet.pay_shop(k, r)
	await _wait(2)
	_end("shop_pay", after)

## 6 a.m. on the real clock: tonight's cash into the bank, the night closed.
func _g_dawn() -> void:
	phase = "dawn"
	var nc: Node = game.night_clock
	var n := int(nc.night)
	var after := _with({"bank": int(cur.bank) + int(cur.cash), "cash": 0, "closed": n, "night": n + 1})
	_begin("dawn", after, ["run"])
	var fired := [false]
	var on_end := func(_x: int) -> void: fired[0] = true
	nc.night_ended.connect(on_end)
	nc.set_time(nc.NIGHT_MINUTES - 0.02, n)
	var guard := 0
	while not fired[0] and guard < 600:
		await physics_frame
		guard += 1
	nc.night_ended.disconnect(on_end)
	await _wait(5)
	_end("dawn", after, ["run"])

## A garage part from the bank (mod tree panel's Buy).
func _g_buy() -> void:
	phase = "garage"
	var car := str(cur.car)
	var mods := GarageMods.new()
	if not mods.open(car, game.wallet):
		return
	var pick := ""
	for id in mods.items:
		if mods.state(id) == GarageMods.BUYABLE and mods.price(id) <= int(cur.bank) and mods.price(id) > 0:
			pick = id
			break
	if pick == "":
		await _g_shop_pay()   # money for the next one
		return
	var parts: Dictionary = cur.parts.duplicate(true)
	var mine: Array = parts.get(car, []).duplicate()
	mine.append("%s/%s" % [car, pick])
	mine.sort()
	parts[car] = mine
	var after := _with({"bank": int(cur.bank) - mods.price(pick), "parts": parts})
	_begin("buy", after, ["fitted"], {"part": pick})
	var r: Dictionary = mods.buy(pick)
	await _wait(2)
	_end("buy", after if r.ok else cur, ["fitted"])

## The pump: drain the tank (saved), then fill from the bank.
func _g_refuel() -> void:
	phase = "pump"
	var tank: Object = game.player.fuel
	var after := _with({"run": true})
	_begin("drain", after, ["fuel"])
	tank.litres = maxf(tank.litres - rng.randf_range(5.0, 30.0), 0.0)
	game.saver.save_now()
	_end("drain", after, ["fuel"])
	var room: float = tank.CAPACITY_L - tank.litres
	var want := int(ceil(room - 0.001))
	var buy := clampi(mini(want, floori(float(game.wallet.bank) / tank.PRICE_PER_LITRE)), 0, want)
	var got := minf(float(buy), room)
	var cost: int = buy * tank.PRICE_PER_LITRE
	after = _with({"bank": int(cur.bank) - cost, "fuel": snappedf(float(cur.fuel) + got, 0.01)})
	_begin("refuel", after, [], {"cost": cost, "got": got})
	tank.refuel(game.wallet)
	await _wait(2)
	var s := sig()
	var ok: bool = _refuel_ok(s, {"before": cur, "cost": cost, "got": got})
	_log({"t": "end", "op": "refuel", "phase": phase, "n": step_no, "sig": s, "ok": ok})
	if not ok:
		fails += 1
		print("CHAOS STEP FAIL life %d refuel: paid %d for %.1f L; save has bank %d (was %d), fuel %.2f (was %.2f)" % [life, cost, got, s.bank, cur.bank, s.fuel, cur.fuel])
	cur = s

## Restart (pause menu): the run ends; mid-chase it is a bust.
func _g_restart() -> void:
	phase = "restart"
	var after := _with({"run": false})
	if cur.chase:
		after = _with({"run": false, "chase": false, "busts": int(cur.busts) + 1})
	_begin("restart", after)
	bot = null
	_gs().restart()
	await _reloaded()
	await _wait(20)
	_end("restart", after)

## Quit to title: the run is saved and committed; mid-chase it is a bust.
func _g_quit_title() -> void:
	phase = "menu"
	var after := _with({"run": true})
	if cur.chase:
		after = _with({"run": false, "chase": false, "busts": int(cur.busts) + 1})
	_begin("quit_title", after)
	bot = null
	_gs().quit_to_title()
	await _reloaded()
	await _wait(30)
	_end("quit_title", after)

## The title's Load: switch to another slot (saves this one like a quit).
func _g_slot() -> void:
	phase = "menu"
	var n: int = int(cur.slot) % SaveCore.SLOTS + 1
	var after := sig_of(n)
	after.slot = n
	if after.chase:
		after.busts = int(after.busts) + 1
		after.chase = false
		after.run = false
	_begin("slot", after, [], {"from_run": true})
	bot = null
	# The title row's own path: a quit save, select, reload onto the road.
	_gs().quitting.emit()
	if SaveStore.select_slot(n):
		GameState.title_seen = true
		paused = false
		reload_current_scene()
		await _reloaded()
	await _wait(20)
	_end("slot", after)

## The Car page: another car, a commit.
func _g_car() -> void:
	phase = "menu"
	var ids := PlayerCars.ids()
	var to: String = ids[rng.randi_range(0, ids.size() - 1)]
	if PlayerCars.is_special(to):
		return
	var after := _with({"car": to})
	_begin("car", after, ["fuel"])
	PlayerCars.select(to)
	PlayerCars.save_settings()
	await _wait(2)
	_end("car", after, ["fuel"])

# ---------------------------------------------------------------- core mode

func _core_start() -> void:
	# What Game sets up, without the scene: the wallet, the director's boot read.
	cur = sig()
	var after := cur.duplicate(true)
	if cur.chase:
		after.busts = int(cur.busts) + 1
		after.chase = false
		after.run = false
	_begin("boot", after, ["run"] if cur.chase else [])
	SaveDirector.new(null).read_run()
	_end("boot", after)
	fuel = load("res://scripts/car/fuel_tank.gd").new()
	core_car = SaveCore.current_car()
	var st := SaveCore.car_state(core_car)
	if st.get("fuel") is Dictionary:
		fuel.from_dict(st.fuel)
	wallet = Wallet.new()
	if "car_live" in wallet:
		wallet.car_live = _core_live
	root.add_child(wallet)
	_core_loop.call_deferred()

func _core_live() -> Dictionary:
	return {"car": core_car, "fuel": fuel.to_dict()}

## A run as SaveDirector.capture writes it (only the fields the load checks).
func _core_run() -> Dictionary:
	return {"road": {"seed": 7, "curviness": 0.5, "hilliness": 0.5, "kicker_chance": 0.1, "id": 0, "s": rng.randf() * 1000.0, "dir": 1, "act": 1},
		"origin_index": rng.randi_range(0, 9), "car": {"xform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0], "lin_vel": [0, 0, 30], "ang_vel": [0, 0, 0], "gear": 3, "rpm": 4000},
		"car_live": _core_live(), "play_secs": step_no}

func _core_loop() -> void:
	while true:
		var pick := rng.randi_range(0, 99)
		if cur.chase:
			if pick < 40:
				phase = "chase"
				_begin("autosave", cur)
				SaveStore.save_run(_core_run())
				_end("autosave", cur)
			elif pick < 75:
				phase = "chase"
				var a := _with({"chase": false})
				_begin("chase_end", a)
				SaveCore.end_chase()
				_end("chase_end", a)
			else:
				_core_reboot()
		elif pick < 18:
			phase = "race"
			var a := _with({"run": true})
			_begin("autosave", a)
			SaveStore.save_run(_core_run())
			_end("autosave", a)
		elif pick < 28:
			phase = "race"
			var k := rng.randi_range(1, 400)
			var a := _with({"cash": int(cur.cash) + k})
			_begin("cash", a)
			wallet.add_cash(k)
			_end("cash", a)
		elif pick < 38:
			phase = "shop"
			var k := rng.randi_range(200, 3000)
			var r := "chaos:%d:%d" % [life, step_no + 1]
			var rec: Array = cur.receipts.duplicate()
			rec.append(r)
			while rec.size() > Wallet.RECEIPTS_KEPT:
				rec.remove_at(0)
			var a := _with({"bank": int(cur.bank) + k, "receipts": rec})
			_begin("shop_pay", a)
			wallet.pay_shop(k, r)
			_end("shop_pay", a)
		elif pick < 52:
			phase = "dawn"
			var n: int = int(cur.night)
			var a := _with({"bank": int(cur.bank) + int(cur.cash), "cash": 0, "closed": n, "night": n + 1, "run": false})
			_begin("dawn", a)
			wallet.bank_night(n)
			_end("dawn", a)
		elif pick < 64:
			_core_buy()
		elif pick < 74:
			_core_refuel()
		elif pick < 82:
			phase = "chase"
			var a := _with({"chase": true})
			_begin("chase_begin", a)
			SaveCore.begin_chase()
			_end("chase_begin", a)
		elif pick < 88:
			phase = "restart"
			var a := _with({"run": false})
			_begin("restart", a)
			SaveCore.commit("run_end", {"clear_run": true, "car_live": _core_live()})
			_end("restart", a)
		elif pick < 93:
			phase = "menu"
			var n: int = int(cur.slot) % SaveCore.SLOTS + 1
			var a := sig_of(n)
			a.slot = n
			_begin("slot", a)
			SaveCore.select_slot(n)
			_end("slot", a)
			_core_reboot()
		else:
			_core_reboot()
		await process_frame

## What a new boot does (the director's read), in the same process.
func _core_reboot() -> void:
	phase = "title"
	var a := cur.duplicate(true)
	if cur.chase:
		a.busts = int(cur.busts) + 1
		a.chase = false
		a.run = false
	_begin("boot", a, ["run"] if cur.chase else [])
	SaveCore.forget()
	SaveDirector.new(null).read_run()
	_end("boot", a)
	core_car = SaveCore.current_car()
	var st := SaveCore.car_state(core_car)
	if st.get("fuel") is Dictionary:
		fuel.from_dict(st.fuel)
	wallet.free()
	wallet = Wallet.new()
	if "car_live" in wallet:
		wallet.car_live = _core_live
	root.add_child(wallet)

func _core_buy() -> void:
	phase = "garage"
	var car := str(cur.car)
	var mods := GarageMods.new()
	if not mods.open(car, wallet):
		return
	var pick := ""
	var opts := []
	for id in mods.items:
		if mods.state(id) == GarageMods.BUYABLE and mods.price(id) > 0 and mods.price(id) <= int(cur.bank):
			opts.append(id)
	if opts.is_empty():
		return
	pick = opts[rng.randi_range(0, opts.size() - 1)]
	var parts: Dictionary = cur.parts.duplicate(true)
	var mine: Array = parts.get(car, []).duplicate()
	mine.append("%s/%s" % [car, pick])
	mine.sort()
	parts[car] = mine
	var a := _with({"bank": int(cur.bank) - mods.price(pick), "parts": parts})
	_begin("buy", a, ["fitted"], {"part": pick})
	var r: Dictionary = mods.buy(pick)
	_end("buy", a if r.ok else cur, ["fitted"])

func _core_refuel() -> void:
	phase = "pump"
	# Burn some, saved with the night (as driving and the autosave do).
	fuel.litres = maxf(fuel.litres - rng.randf_range(5.0, 30.0), 0.0)
	var a := _with({"run": true})
	_begin("drain", a, ["fuel"])
	SaveStore.save_run(_core_run())
	_end("drain", a, ["fuel"])
	var room: float = fuel.CAPACITY_L - fuel.litres
	var want := int(ceil(room - 0.001))
	var buy := clampi(mini(want, floori(float(wallet.bank) / fuel.PRICE_PER_LITRE)), 0, want)
	var got := minf(float(buy), room)
	var cost: int = buy * fuel.PRICE_PER_LITRE
	a = _with({"bank": int(cur.bank) - cost, "fuel": snappedf(float(cur.fuel) + got, 0.01)})
	_begin("refuel", a, [], {"cost": cost, "got": got})
	fuel.refuel(wallet)
	var s := sig()
	var ok: bool = _refuel_ok(s, {"before": cur, "cost": cost, "got": got})
	_log({"t": "end", "op": "refuel", "phase": phase, "n": step_no, "sig": s, "ok": ok})
	if not ok:
		fails += 1
		print("CHAOS STEP FAIL life %d refuel: paid %d for %.1f L; save has bank %d (was %d), fuel %.2f (was %.2f)" % [life, cost, got, s.bank, cur.bank, s.fuel, cur.fuel])
	cur = s

# ---------------------------------------------------------------- upgrade mode

## The upgraded save, from a clean copy of the fixture (the reference).
func _upgrade_reference() -> Dictionary:
	var keep_root := SaveCore.root
	var keep_legacy := SaveCore.legacy_dir
	var ref_root := "user://chaos_ref/saves"
	_wipe(ProjectSettings.globalize_path("user://chaos_ref"))
	_copy_tree(FIXTURE.path_join("saves"), ref_root)
	_copy_tree(FIXTURE.path_join("global"), "user://chaos_ref/global")
	SaveCore.legacy_dir = "user://chaos_ref/global"
	SaveCore.root = ref_root
	SaveCore.slot = 0
	var out := {}
	for n in range(1, SaveCore.SLOTS + 1):
		out[str(n)] = sig_of(n)
	SaveCore.root = keep_root
	SaveCore.legacy_dir = keep_legacy
	SaveCore.slot = 0
	return out

## After a kill: each slot is either untouched version 1 or the whole upgrade.
func _upgrade_check(last: Dictionary) -> Dictionary:
	var out := {"ok": true}
	if last.get("op") == "reset" and last.get("t") == "begin":
		out.case = "during:reset"
		return out   # the harness was laying the old save down again
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://saves")):
		out.case = "fresh"
		return out
	var ref := _upgrade_reference()
	out.case = ("during:" if last.get("t") == "begin" else "after:") + str(last.get("op", "none"))
	var states := []
	for n in range(1, SaveCore.SLOTS + 1):
		var slot_dir := "user://saves/slot_%d" % n
		var src := FIXTURE.path_join("saves/slot_%d" % n)
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(src)):
			continue
		# The old files are never changed or removed, upgraded or not.
		for f in DirAccess.get_files_at(src):
			if f == "meta.json":
				continue   # replaced by the new meta.json (its old copy is meta.json.bak1)
			if FileAccess.get_file_as_bytes(slot_dir.path_join(f)) != FileAccess.get_file_as_bytes(src.path_join(f)):
				out.ok = false
				out["changed_" + f] = n
		# A copy in pre_v1 is whole or not there.
		var pre := slot_dir.path_join("pre_v1")
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(pre)):
			for f in DirAccess.get_files_at(pre):
				if f.ends_with(".part"):
					continue   # a copy cut short, under its working name (never read)
				if FileAccess.get_file_as_bytes(pre.path_join(f)) != FileAccess.get_file_as_bytes(src.path_join(f)):
					out.ok = false
					out["torn_pre_v1_" + f] = n
		var upgraded := AtomicJson.any_exists(slot_dir.path_join("career.json"))
		states.append(upgraded)
	# Then load (which finishes an upgrade cut short) and compare with the reference.
	SaveCore.slot = 0
	for n in range(1, SaveCore.SLOTS + 1):
		if not ref.has(str(n)):
			continue
		var s := sig_of(n)
		if not same(s, ref[str(n)], []):
			out.ok = false
			out["diff_slot_%d" % n] = diff(s, ref[str(n)])
	out.upgraded_before_load = states
	return out

func _upgrade_loop() -> void:
	SaveCore.root = "user://saves"
	while true:
		phase = "title"
		_begin("reset", {})
		_wipe(ProjectSettings.globalize_path("user://saves"))
		_wipe(ProjectSettings.globalize_path("user://chaos_v1_global"))
		_copy_tree(FIXTURE.path_join("saves"), "user://saves")
		_copy_tree(FIXTURE.path_join("global"), "user://chaos_v1_global")
		_log({"t": "end", "op": "reset", "n": step_no, "sig": {}})
		_begin("upgrade", {})
		SaveCore.forget()
		SaveCore.slot = 0
		SaveCore.summary(1)   # the title's first read upgrades every old slot
		_log({"t": "end", "op": "upgrade", "n": step_no, "sig": {}})
		await process_frame

static func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

static func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for d in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(d), to.path_join(d))
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(from.path_join(f)), ProjectSettings.globalize_path(to.path_join(f)))
