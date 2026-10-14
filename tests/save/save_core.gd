extends SceneTree

# Save core S1 (scripts/save/save_core.gd): one save per slot, career + night
# + meta. Checks
# - round trip: every career block and night field comes back equal, blocks
#   and fields this build does not know included; every file says save_version 2
# - a torn career.json falls back to .bak1; backups rotate and stop at three
# - a kill at each step of a dawn commit: the bank is the old bank or the old
#   bank + tonight's cash, never doubled, never lost (SaveCore alone, and
#   through the Wallet)
# - a kill between the career and the night write of a commit: position and
#   cash come from the night, the car's state from the career
# - a slot saved by a newer build (save_version 99) is not loaded and its
#   files are byte-identical afterwards
# - tunes, the car picked and the car's dirt are per slot (bug 1: tunes were
#   shared by every slot)
# - wear, damage and fuel survive a save and reload (bug 2: a quit was a free
#   repair), as plain objects and in the booted game
# - nothing is written during a chase; a quit mid-chase is a bust on return
# - a career with 18 cars, 40 parts and 4 tunes each: under 200 KB; its commit
#   time is printed next to the 8 ms target (not met, see TARGET_COMMIT_MS)
# - the game boots from a fresh slot, and again from what it saved
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/save/save_core.gd

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const PlayerTune := preload("res://scripts/car/player_tune.gd")
const Wallet := preload("res://scripts/core/wallet.gd")

const ROOT := "user://test_save_core"
const MAX_BYTES := 200 * 1024
## The brief's target for a commit, and the ceiling this test fails at. The
## target is printed, not enforced: one crash-safe write of a tiny file already
## takes about 6 ms on Roy's laptop and a commit is three of them.
const TARGET_COMMIT_MS := 8.0
const MAX_COMMIT_MS := 400.0
## Named tunes per car in the size check, next to the live tune (4 tunes a car).
const NAMED_TUNES := 3

var failures: Array[String] = []
var game: Node
var phase := 0
var ticks := 0
var want := {}

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CAR", "")
	_round_trip()
	_backups()
	_dawn_kill()
	_dawn_kill_wallet()
	_mid_night_kill()
	_newer_version()
	_per_slot()
	_car_state()
	_chase()
	_size_and_time()
	# Part 2: the game itself, on a fresh slot, with everything in the slot.
	_fresh("game")
	SaveCore.persist = true
	SaveDirector.enabled = true
	PlayerTune.enabled = true
	ExhaustTune.save_path = ExhaustTune.DEFAULT_PATH
	CarDirt.path = CarDirt.DEFAULT_PATH
	NightClock.path = NightClock.DEFAULT_PATH
	_boot()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

## A new, empty save folder with slot 1 active, as on a first launch.
func _fresh(name: String) -> void:
	SaveCore.root = ROOT.path_join(name)
	SaveCore.slot = 0
	SaveCore.chase_active = false
	SaveCore.test_stop_after = 0
	SaveCore.select_slot(1)

## What a relaunch reads: both sides through JSON, so 2 and 2.0 compare equal.
func _canon(x: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(x, "", true, true)), "", true, true)

func _run(z: float, night: int = 1) -> Dictionary:
	return {"road": {"seed": 7, "curviness": 0.5, "hilliness": 0.5, "kicker_chance": 0.0, "id": 0, "s": z, "dir": 1, "act": 1},
		"origin_index": 3, "recenter_count": 1, "sections": {},
		"car": {"xform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0.25, 0.5, z], "lin_vel": [0, 0, -20], "ang_vel": [0, 0, 0], "gear": 3, "rpm": 4200},
		"clock": {"minutes": 123.5, "night": night}, "radio": 2}

func _live(car: String, tyre: float) -> Dictionary:
	return {"car": car, "wear": {"engine_temp": 91.0, "brake_temp": 180.0, "clutch_wear": 0.25, "tyre_wear": [tyre, tyre, 0.1, 0.1]},
		"damage": {"radiator": 0.4, "steer_fl": 0.0, "steer_fr": 0.3, "susp_rl": 0.0, "susp_rr": 0.0, "body": 0.55, "lamps": [true, false, false, false], "patched_night": -1},
		"fuel": {"litres": 7.5}, "dirt": 0.4}

# ---------- 1: round trip ----------

func _round_trip() -> void:
	_fresh("round_trip")
	_check(SaveCore.summary(1).empty and SaveCore.gen() == 0 and SaveCore.run().is_empty(), "a new slot is not empty")
	var ok := SaveCore.commit("test", {"bank": 1830, "cash": 240, "current_car": "p0_beater"}, func(c: Dictionary) -> void:
		c.world.difficulty = "weekend_warrior"
		c.world.difficulty_next = "pro"
		c.wallet.receipts = [{"job": "tow", "pay": 90}]
		c.wallet.later_field = "kept"
		var car := SaveCore.car_entry(c, "p1_coupe")
		car.parts_owned = ["exhaust_a", "turbo_s1", "wheels_mesh"]
		car.fitted = ["exhaust_a", "turbo_s1"]
		c.tunes["p1_coupe"] = {"live": {"front_arb": 0.6}, "exhaust": {"loudness": 0.7}, "slots": {"Street": {"front_arb": 0.4}}}
		c.story.act = 2
		c.special.unlocked = {"m1_monster": true}
		c.walt.first_total_used = true
		c.stats.play_secs = 15400
		c.shop_from_a_later_pr = {"stock": ["a", "b"], "day": 4})
	_check(ok, "the first commit failed")
	var run := _run(-640.0)
	run.car_live = _live("p0_beater", 0.3)
	run.play_secs = 15460
	_check(SaveCore.write_night(run), "the night did not save")
	_check(SaveCore.commit("quit"), "the quit commit failed")
	var career := _canon(SaveCore.career())
	var night := _canon(SaveCore.night())
	var gen := SaveCore.gen()
	SaveCore.forget()   # as on a relaunch
	_check(_canon(SaveCore.career()) == career, "the career did not come back equal")
	_check(_canon(SaveCore.night()) == night, "the night did not come back equal")
	var c := SaveCore.career()
	_check(gen == 2 and SaveCore.gen() == 2, "gen should count commits (%d)" % SaveCore.gen())
	_check(SaveCore.bank() == 1830 and SaveCore.cash() == 240, "money: bank %d cash %d" % [SaveCore.bank(), SaveCore.cash()])
	_check(SaveCore.current_car() == "p0_beater", "current car %s" % SaveCore.current_car())
	_check(c.world.difficulty_next == "pro" and int(c.world.seed) >= 0 and c.world.has("seed"), "world block")
	_check(c.wallet.receipts.size() == 1 and c.wallet.later_field == "kept", "wallet receipts or an unknown wallet field were lost")
	_check(c.cars.p1_coupe.parts_owned == ["exhaust_a", "turbo_s1", "wheels_mesh"] and c.cars.p1_coupe.fitted == ["exhaust_a", "turbo_s1"], "parts: %s" % str(c.cars.p1_coupe))
	_check(c.tunes.p1_coupe.slots.Street.front_arb == 0.4 and c.tunes.p1_coupe.exhaust.loudness == 0.7, "tunes block")
	_check(int(c.story.act) == 2 and c.special.unlocked.m1_monster == true and c.walt.first_total_used == true, "story / special / walt blocks")
	_check(int(c.stats.play_secs) == 15460, "play_secs should take the night's (%s)" % str(c.stats.play_secs))
	_check(_canon(c.shop_from_a_later_pr) == _canon({"stock": ["a", "b"], "day": 4}), "a block this build does not know was not kept")
	# The quit commit folded the live car into the career.
	var beater: Dictionary = c.cars.p0_beater
	_check(beater.wear.tyre_wear[0] == 0.3 and beater.damage.body == 0.55 and beater.fuel.litres == 7.5 and beater.dirt == 0.4, "car_live was not folded into the career: %s" % str(beater))
	var n := SaveCore.run()
	_check(not n.is_empty() and n.car.xform[11] == -640.0 and int(n.radio) == 2 and n.clock.minutes == 123.5, "the run did not come back")
	_check(int(n.base_gen) == 2 and int(n.night) == 1, "night bookkeeping: base_gen %s night %s" % [str(n.get("base_gen")), str(n.get("night"))])
	for name in SaveCore.FILES:
		var d: Dictionary = AtomicJson.read(SaveCore.file(name)).get("data", {})
		_check(int(d.get("save_version", 0)) == 2, "%s.json has no save_version 2" % name)
	var s := SaveCore.summary(1)
	_check(not s.empty and s.cash == 240 and s.bank == 1830 and s.plate.car == "p0_beater" and int(s.plate.act) == 2 \
		and int(s.plate.play_secs) == 15460 and s.plate.mode == "free" and s.plate.difficulty == "weekend_warrior", "the plate: %s" % str(s))   # a new save starts in free mode (2026-10-14)
	# An unknown block survives later commits by code that never heard of it.
	SaveStore.save_garage(["exhaust_a", "turbo_s1", "wheels_mesh", "seat_b"])
	SaveCore.forget()
	_check(SaveCore.career().has("shop_from_a_later_pr") and SaveCore.career().wallet.later_field == "kept", "an unknown block was dropped by a later commit")
	_check(SaveCore.career().cars.p0_beater.parts_owned == ["seat_b"], "a new part should go to the car you drive")

# ---------- 2 + 6: fallback and backups ----------

func _backups() -> void:
	_fresh("backups")
	for i in 5:
		SaveCore.commit("test", {"bank": 100 * (i + 1)})
	var f := SaveCore.file("career")
	_check(FileAccess.file_exists(f + ".bak3") and not FileAccess.file_exists(f + ".bak4"), "career backups should stop at 3")
	_check(int(AtomicJson.decode(FileAccess.get_file_as_string(f + ".bak1")).gen) == 4, "career.json.bak1 should be the commit before")
	var text := FileAccess.get_file_as_string(f)
	_put(f, text.left(text.length() - 3))
	SaveCore.forget()
	_check(SaveCore.gen() == 4 and SaveCore.bank() == 400 and SaveCore.career_damaged(), "a torn career.json should fall back to .bak1 (gen %d bank %d)" % [SaveCore.gen(), SaveCore.bank()])

# ---------- 3: a kill at every step of a dawn commit ----------

func _dawn_kill() -> void:
	for stop in [1, 2, 3, 4, 0]:
		_fresh("dawn_kill_%d" % stop)
		SaveCore.commit("test", {"bank": 1000})
		SaveCore.write_night(_run(-900.0, 3))
		SaveCore.set_cash(250)
		SaveCore.test_stop_after = stop
		SaveCore.commit("dawn", {"close_night": 3})
		SaveCore.test_stop_after = 0
		SaveCore.forget()   # the game died; this is the relaunch
		var bank := SaveCore.bank()
		var cash := SaveCore.cash()
		var label := "dawn kill after step %d" % stop
		_check(bank == 1000 or bank == 1250, "%s: bank %d is neither the old bank nor old + tonight's" % [label, bank])
		_check(bank + cash == 1250, "%s: bank %d + cash %d, expected 1250 in all" % [label, bank, cash])
		if stop == 1:
			_check(not SaveCore.run().is_empty() and SaveCore.clock().night == 3, "%s: the night should resume" % label)
		else:
			_check(SaveCore.run().is_empty() and SaveCore.clock().night == 4 and SaveCore.clock().minutes == 0.0, "%s: the next night should start fresh (%s)" % [label, str(SaveCore.clock())])
			_check(int(SaveCore.career().story.night_closed) == 3 and int(SaveCore.career().story.night) == 4, "%s: story %s" % [label, str(SaveCore.career().story)])
		# Playing on: dawn comes (again, for the one that did not bank).
		if cash > 0:
			SaveCore.commit("dawn", {"close_night": 3})
		SaveCore.write_night(_run(-10.0, 4))
		SaveCore.forget()
		_check(SaveCore.bank() == 1250 and SaveCore.cash() == 0, "%s: after playing on, bank %d cash %d" % [label, SaveCore.bank(), SaveCore.cash()])

func _dawn_kill_wallet() -> void:
	for stop in [1, 2, 3, 4, 0]:
		_fresh("dawn_wallet_%d" % stop)
		SaveCore.commit("test", {"bank": 1000})
		var w: Node = Wallet.new()
		root.add_child(w)
		w.add_cash(250)
		SaveCore.test_stop_after = stop
		w.bank_night(1)
		SaveCore.test_stop_after = 0
		root.remove_child(w)
		w.free()
		SaveCore.forget()
		var r: Node = Wallet.new()
		_check(r.bank == 1000 or r.bank == 1250, "wallet dawn kill after step %d: bank %d" % [stop, r.bank])
		_check(r.bank + r.cash == 1250, "wallet dawn kill after step %d: bank %d + cash %d, expected 1250" % [stop, r.bank, r.cash])
		r.free()

# ---------- 4: a kill between the career and the night write ----------

func _mid_night_kill() -> void:
	_fresh("mid_night")
	SaveCore.commit("test", {"bank": 500})
	var a := _run(-100.0)
	a.car_live = _live("p1_coupe", 0.3)
	SaveCore.write_night(a)
	SaveCore.set_cash(40)
	SaveCore.commit("quit")
	var b := _run(-2500.0)
	b.car_live = _live("p1_coupe", 0.5)
	SaveCore.write_night(b)
	SaveCore.set_cash(60)
	var gen := SaveCore.gen()
	SaveCore.test_stop_after = 2   # the career is written, the night is not
	SaveCore.commit("test", {"car_live": _live("p1_coupe", 0.7)})
	SaveCore.test_stop_after = 0
	SaveCore.forget()
	_check(SaveCore.gen() == gen + 1 and int(AtomicJson.read(SaveCore.file("night")).data.base_gen) == gen, "the kill did not leave the night one gen behind")
	var run := SaveCore.run()
	_check(not run.is_empty() and run.car.xform[11] == -2500.0 and run.clock.minutes == 123.5 and int(run.radio) == 2, "position, clock and radio should come from the night")
	_check(SaveCore.cash() == 60, "cash should come from the night (%d)" % SaveCore.cash())
	_check(not run.has("car_live"), "the night's older car state should not be used")
	_check(SaveCore.car_state("p1_coupe").wear.tyre_wear[0] == 0.7, "the car's state should come from the career: %s" % str(SaveCore.car_state("p1_coupe").get("wear")))
	# The next night save sits on the new gen and resumes exactly from there on.
	var c := _run(-2600.0)
	c.car_live = _live("p1_coupe", 0.8)
	SaveCore.write_night(c)
	SaveCore.forget()
	_check(SaveCore.car_state("p1_coupe").wear.tyre_wear[0] == 0.8 and SaveCore.cash() == 60, "an equal gen should resume exactly")

# ---------- 5: a save from a newer build ----------

func _newer_version() -> void:
	_fresh("newer")
	SaveCore.commit("test", {"bank": 777, "cash": 33})
	SaveCore.write_night(_run(-50.0))
	var career: Dictionary = AtomicJson.read(SaveCore.file("career")).data
	career.save_version = 99
	career.something_new = {"a": 1}
	_put(SaveCore.file("career"), AtomicJson.encode(career))
	var before := _bytes(SaveCore.slot_dir())
	SaveCore.forget()
	print("(the warning below is expected: a save version 99 slot)")
	_check(SaveCore.career().is_empty() and SaveCore.run().is_empty() and SaveCore.bank() == 0 and SaveCore.cash() == 0, "a newer save was loaded")
	_check(SaveCore.summary(1).empty and SaveCore.current_car() == SaveCore.DEFAULT_CAR, "a newer save should boot as an empty slot")
	_check(not SaveCore.commit("test", {"bank": 1}) and not SaveCore.write_night(_run(0.0)) and not SaveCore.set_cash(5) \
		and not SaveStore.save_wallet(1, 1) and not SaveStore.save_garage(["x"]) and not SaveCore.set_tune("p1_coupe", "live", {"a": 1.0}) \
		and not SaveCore.set_clock(10.0, 2), "a write went through on a newer save")
	SaveCore.begin_chase()
	SaveCore.end_chase()
	SaveCore.settle_chase()
	SaveCore.mark_first_wreck()
	var w: Node = Wallet.new()
	root.add_child(w)
	w.add_cash(50)
	w.bank_night(1)
	root.remove_child(w)
	w.free()
	_check(_bytes(SaveCore.slot_dir()) == before, "a newer save's files changed")
	# The other slots still work.
	_check(SaveCore.select_slot(2) and SaveCore.commit("test", {"bank": 5}) and SaveCore.bank() == 5, "slot 2 should be usable next to a newer slot 1")

# ---------- 8: tunes, car pick and dirt are per slot ----------

func _per_slot() -> void:
	_fresh("per_slot")
	SaveCore.persist = true
	PlayerTune.enabled = true
	ExhaustTune.save_path = ExhaustTune.DEFAULT_PATH
	PlayerTune.kind = "p1_coupe"
	_check(PlayerTune.in_slot() and ExhaustTune.in_slot(), "the tunes are not pointed at the slot")
	var spec := CarSpec.coupe_default()
	TuneParams.set_gear_count((spec.gear_ratios as Array).size())
	var path := PlayerTune.paths()[0]
	var e := TuneParams.find(path)
	var stock: float = TuneParams.get_value(spec, path)
	var tuned: float = e.min if absf(stock - e.min) > 0.001 else e.max
	TuneParams.set_value(spec, path, tuned)
	_check(PlayerTune.save(spec), "the tune did not save")
	_check(ExhaustTune.save_car("p1_coupe", {"loudness": 0.9, "pops": 0.8}), "the exhaust tune did not save")
	var slots := TuneSlots.new(TuneSlots.DEFAULT_PATH)
	_check(slots.in_slot() and slots.save("Street", spec), "the named tune did not save")
	PlayerCars.select("p2_hothatch")
	PlayerCars.save_settings()
	PlayerCars.select("p1_coupe")   # the tunes below are still the coupe's
	SaveCore.commit("test", {"car_live": {"car": "p2_hothatch", "dirt": 0.4}})
	# Slot 2: a new game. No saved tunes, the default car, a clean car.
	SaveCore.select_slot(2)
	_check(PlayerTune.load_values().is_empty(), "slot 2 has slot 1's tune")
	_check(ExhaustTune.load_saved("p1_coupe").is_empty(), "slot 2 has slot 1's exhaust tune")
	_check(TuneSlots.new(TuneSlots.DEFAULT_PATH).names().is_empty(), "slot 2 has slot 1's named tunes")
	var fresh := CarSpec.coupe_default()
	_check(PlayerTune.apply_saved(fresh) == 0 and TuneParams.get_value(fresh, path) == stock, "slot 2's car is not stock")
	PlayerCars.load_settings()
	_check(PlayerCars.selected == PlayerCars.DEFAULT, "slot 2 remembers slot 1's car (%s)" % PlayerCars.selected)
	_check(not SaveCore.car_state("p2_hothatch").has("dirt"), "slot 2 has slot 1's dirt")
	# Back in slot 1 it is all there, also after a relaunch.
	SaveCore.select_slot(1)
	SaveCore.forget()
	_check(absf(float(PlayerTune.load_values().get(path, stock)) - tuned) < 0.0001, "slot 1 lost its tune")
	var again := CarSpec.coupe_default()
	_check(PlayerTune.apply_saved(again) > 0 and absf(TuneParams.get_value(again, path) - tuned) < 0.0001, "slot 1's tune did not apply")
	_check(_near(ExhaustTune.load_saved("p1_coupe").get("loudness"), 0.9), "slot 1 lost its exhaust tune")
	_check(TuneSlots.new(TuneSlots.DEFAULT_PATH).names() == ["Street"], "slot 1 lost its named tune")
	PlayerCars.load_settings()
	_check(PlayerCars.selected == "p2_hothatch", "slot 1 forgot its car (%s)" % PlayerCars.selected)
	_check(SaveCore.car_state("p2_hothatch").get("dirt") == 0.4, "slot 1 lost its dirt")
	# A tune change waits in the night until a commit, and survives a kill before it.
	_check(ExhaustTune.save_car("p1_coupe", {"loudness": 0.2}), "exhaust change")
	SaveCore.forget()
	_check(_near(ExhaustTune.load_saved("p1_coupe").get("loudness"), 0.2) and _near(SaveCore.career().tunes.p1_coupe.exhaust.loudness, 0.9), "a tune change should wait in the night")
	SaveCore.commit("quit")
	_check(_near(SaveCore.career().tunes.p1_coupe.exhaust.loudness, 0.2) and not SaveCore.night().has("tunes_live"), "a commit should fold the tune change into the career")
	PlayerCars.select(PlayerCars.DEFAULT)
	PlayerTune.enabled = false
	SaveCore.persist = false

# ---------- 9: wear, damage and fuel ----------

func _car_state() -> void:
	_fresh("car_state")
	var health := PowertrainHealth.new()
	health.tyre_wear[0] = 0.31
	health.tyre_wear[3] = 0.62
	health.clutch_wear = 0.44
	var damage := CarDamage.new()
	damage.parts[0] = 0.8
	damage.parts[5] = 0.35
	damage.lamps[1] = true
	damage.patched_night = 2
	var fuel := FuelTank.new()
	fuel.litres = 6.25
	var run := _run(-300.0)
	run.car_live = {"car": "p1_coupe", "wear": health.to_dict(), "damage": damage.to_dict(), "fuel": fuel.to_dict(), "dirt": 0.5}
	SaveCore.write_night(run)
	for pass_name in ["from the night", "from the career"]:
		SaveCore.forget()
		var st := SaveCore.car_state("p1_coupe")
		var h2 := PowertrainHealth.new()
		h2.from_dict(st.get("wear", {}))
		var d2 := CarDamage.new()
		d2.from_dict(st.get("damage", {}))
		var f2 := FuelTank.new()
		f2.from_dict(st.get("fuel", {}))
		_check(h2.tyre_wear == health.tyre_wear and h2.clutch_wear == 0.44, "%s: wear %s clutch %f" % [pass_name, str(h2.tyre_wear), h2.clutch_wear])
		_check(d2.parts == damage.parts and d2.lamps == damage.lamps and d2.patched_night == 2, "%s: damage %s %s" % [pass_name, str(d2.parts), str(d2.lamps)])
		_check(f2.litres == 6.25 and st.get("dirt") == 0.5, "%s: fuel %f dirt %s" % [pass_name, f2.litres, str(st.get("dirt"))])
		SaveCore.commit("run_end", {"clear_run": true})   # the second pass reads the career alone
		_check(SaveCore.run().is_empty() and not SaveCore.night().has("car_live"), "a run end should clear the run")

# ---------- 10: chases ----------

func _chase() -> void:
	_fresh("chase")
	SaveCore.commit("test", {"bank": 300, "cash": 20})
	SaveCore.write_night(_run(-70.0))
	_check(SaveCore.begin_chase(), "begin_chase failed")
	var before := _bytes(SaveCore.slot_dir(), ["career", "night"])
	_check(not SaveCore.commit("dawn", {"close_night": 1}) and not SaveCore.commit("quit") and not SaveCore.write_night(_run(-999.0)) \
		and not SaveCore.set_cash(500) and not SaveCore.set_clock(5.0, 1) and not SaveCore.set_tune("p1_coupe", "live", {"a": 1.0}) \
		and not SaveStore.save_wallet(1, 1) and not SaveStore.clear_run() and not SaveStore.save_special({"m1_monster": true}), "a write went through during a chase")
	_check(_bytes(SaveCore.slot_dir(), ["career", "night"]) == before, "career.json or night.json changed during a chase")
	# Quit mid-chase: the process ends with the chase open. Relaunch:
	SaveCore.chase_active = false
	SaveCore.forget()
	var meta := SaveCore.settle_chase()
	_check(meta.busted and meta.pending_busts == 1 and not SaveCore.settle_chase().busted, "a chase left open should bust on return, once: %s" % str(meta))
	_check(SaveStore.clear_run() and SaveCore.run().is_empty() and SaveCore.cash() == 20 and SaveCore.bank() == 300, "the bust should clear the run and keep the money")

# ---------- 11: size and time ----------

func _size_and_time() -> void:
	_fresh("big")
	var spec := CarSpec.coupe_default()
	TuneParams.set_gear_count((spec.gear_ratios as Array).size())
	var tune := PlayerTune.values_from(spec)
	var cars := 18
	SaveCore.commit("test", {"bank": 123456}, func(c: Dictionary) -> void:
		for i in cars:
			var id := "p%d_work_pickup" % i
			var car := SaveCore.car_entry(c, id)
			for p in 40:
				car.parts_owned.append("turbo_s%d_%02d" % [i, p])
			for p in 15:
				car.fitted.append("turbo_s%d_%02d" % [i, p])
			var live := _live(id, 0.2)
			for k in SaveCore.LIVE_KEYS:
				car[k] = live[k]
			var slots := {}
			for s in NAMED_TUNES:
				slots["Street tune %d" % s] = tune
			c.tunes[id] = {"live": tune, "exhaust": ExhaustTune.for_car("p1_coupe").to_dict(), "slots": slots})
	SaveCore.write_night(_run(-10.0))
	var big := _time_commits()
	var bytes := FileAccess.get_file_as_bytes(SaveCore.file("career")).size()
	var one_tune := AtomicJson.encode({"t": tune}).length()
	# The same on a career the game can make today: one car, one tune.
	_fresh("small")
	SaveCore.commit("test", {"bank": 500, "car_live": _live("p1_coupe", 0.2)}, func(c: Dictionary) -> void:
		c.tunes["p1_coupe"] = {"live": tune})
	SaveCore.write_night(_run(-10.0))
	var small := _time_commits()
	var small_bytes := FileAccess.get_file_as_bytes(SaveCore.file("career")).size()
	print("size and time: career.json with %d cars, 40 parts and %d tunes each (%d paths, about %.1f KB a tune): %d bytes (%.1f KB); commit avg %.1f ms, worst %.1f ms" % [cars, NAMED_TUNES + 1, tune.size(), one_tune / 1024.0, bytes, bytes / 1024.0, big[0], big[1]])
	print("size and time: career.json with 1 car and 1 tune: %d bytes (%.1f KB); commit avg %.1f ms, worst %.1f ms" % [small_bytes, small_bytes / 1024.0, small[0], small[1]])
	print("size and time: the 8 ms commit target is %s" % ("met" if big[0] < TARGET_COMMIT_MS else "MISSED (a commit is three crash-safe file writes; see docs/save-system.md)"))
	_check(bytes < MAX_BYTES, "career.json is %d bytes, over %d" % [bytes, MAX_BYTES])
	_check(big[0] < MAX_COMMIT_MS, "a commit takes %.1f ms on average, over %.0f" % [big[0], MAX_COMMIT_MS])

## [average, worst] ms of 10 commits on the active slot.
func _time_commits() -> Array:
	var worst := 0.0
	var total := 0.0
	for i in 10:
		var t := Time.get_ticks_usec()
		SaveCore.commit("quit")
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		worst = maxf(worst, ms)
		total += ms
	return [total / 10.0, worst]

# ---------- part 2: the game ----------

func _boot() -> void:
	if game != null:
		root.remove_child(game)
		game.free()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)
	ticks = 0

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	var p: PlayerCar = game.get("player")
	match phase:
		0:
			if ticks < 20:
				return false
			_check(p.health.tyre_wear[0] < 0.01 and p.damage.parts[0] == 0.0, "a fresh slot's car should be new")
			# A hard night: worn tyres and clutch, a bent radiator, a dead lamp, a
			# nearly empty tank, a dirty car, some cash.
			p.health.tyre_wear[0] = 0.45
			p.health.tyre_wear[2] = 0.7
			p.health.clutch_wear = 0.33
			p.damage.parts[0] = 0.6
			p.damage.parts[5] = 0.4
			p.damage.lamps[2] = true
			p.fuel.litres = 9.0
			game.fx.dirt.set_level(0.37)
			game.wallet.add_cash(120)
			want = {"tyre0": p.health.tyre_wear[0], "tyre2": p.health.tyre_wear[2], "clutch": 0.33}
			# Quit the way the pause menu does.
			game.game_state.quitting.emit()
			_check(SaveCore.gen() >= 1 and not SaveCore.run().is_empty(), "quit did not save the night and commit the career")
			_check(SaveCore.career().cars.get(PlayerCars.DEFAULT, {}).get("wear", {}).get("clutch_wear") == 0.33, "the quit commit did not fold the car into the career")
			phase = 1
			SaveCore.forget()
			_boot()
		1:
			if ticks < 3:
				return false
			_check(absf(p.health.tyre_wear[0] - 0.45) < 0.01 and absf(p.health.tyre_wear[2] - 0.7) < 0.01, "tyre wear after reload: %s" % str(p.health.tyre_wear))
			_check(absf(p.health.clutch_wear - 0.33) < 0.01, "clutch wear after reload: %f" % p.health.clutch_wear)
			_check(absf(p.damage.parts[0] - 0.6) < 0.001 and absf(p.damage.parts[5] - 0.4) < 0.001 and p.damage.lamps[2] and not p.damage.lamps[0], "damage after reload: %s %s" % [str(p.damage.parts), str(p.damage.lamps)])
			_check(absf(p.fuel.litres - 9.0) < 0.2, "fuel after reload: %f" % p.fuel.litres)
			_check(absf(game.fx.dirt.level - 0.37) < 0.01, "dirt after reload: %f" % game.fx.dirt.level)
			_check(game.wallet.cash == 120, "cash after reload: %d" % game.wallet.cash)
			# Restart ends the run: the car keeps its wear, the run is cleared.
			game.game_state.restarting.emit()
			_check(SaveCore.run().is_empty() and absf(float(SaveCore.car_state(PlayerCars.DEFAULT).wear.tyre_wear[2]) - 0.7) < 0.01, "a restart should clear the run and keep the car's wear")
			return _end()
	return false

func _end() -> bool:
	SaveDirector.enabled = false
	SaveCore.persist = false
	for m in failures:
		printerr("FAIL: ", m)
	print("save_core: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

# ---------- helpers ----------

func _near(x: Variant, y: float) -> bool:
	return (x is float or x is int) and absf(float(x) - y) < 0.0005

## name -> contents of every file in the slot folder (or only those whose name
## starts with one of `only`).
func _bytes(dir: String, only: Array = []) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(dir):
		var keep := only.is_empty()
		for o in only:
			keep = keep or f.begins_with(o)
		if keep:
			out[f] = FileAccess.get_file_as_bytes(dir.path_join(f))
	return out

func _put(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)

## Clears this test's own folder from a previous run.
func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
