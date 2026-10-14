extends SceneTree

# Free mode F0 (scripts/core/freemode.gd). Checks
# - a NEW save (no career file yet) starts in free mode from night 1; an old
#   career without the block stays a story one (Roy 1541, 2026-10-14)
# - story mode (NEON_FREEMODE=0 here): stops() is false and road_act() is -1
# - enter() sets the flag and entered_night 31; again changes nothing; the
#   on_entered hook fires once; KEEPS are not stopped, STOPS are
# - round trip through SaveCore: still free, entered_night kept, an unknown
#   field inside the block survives, a career with no block loads as not free
# - the dawn that ends night 30 enters free mode in the same commit that banks
#   the night (bank once), the plate says mode "free"; no write in a chase
# - plate lines by season (31 Winter, 59 Spring, 87 Summer, 115 Autumn, 143 Winter)
# - the game: a story boot is on act 1, the dawn of night 30 turns free mode on
#   and the clock goes on to night 31 and past, a free boot has the whole city
#   open (RoadMap.act == MAX_ACT), NEON_ACT still wins
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/core/freemode.gd

const SaveCore := preload("res://scripts/save/save_core.gd")
const Freemode := preload("res://scripts/core/freemode.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")

const ROOT := "user://test_freemode"

var failures: Array[String] = []
var game: Node
var phase := 0
var ticks := 0
var fired := 0

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_CAR", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_FREEMODE", "")
	_new_save()
	# The story machinery still works for a story career (forced with NEON_FREEMODE=0).
	OS.set_environment("NEON_FREEMODE", "0")
	_fresh("units")
	_units()
	_dawn()
	_chase()
	_plate_lines()
	# The game itself, on its own slot: a story boot first, then free boots.
	_fresh("game")
	_boot()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _fresh(name: String) -> void:
	SaveCore.root = ROOT.path_join(name)
	SaveCore.slot = 0
	SaveCore.chase_active = false
	SaveCore.test_stop_after = 0
	SaveCore.select_slot(1)
	Freemode.refresh({})

# ---------- units ----------

# ---------- a new save ----------

func _new_save() -> void:
	_fresh("new_save")
	var c := {}
	SaveCore.fill_career(c)
	_check(Freemode.active(c) and c.freemode.entered_night == 1, "a new career should start free at night 1: %s" % str(c.freemode))
	Freemode.refresh({})
	_check(Freemode.is_active() and Freemode.road_act() == RoadMap.MAX_ACT, "an empty slot should boot free")
	for id in Freemode.STOPS:
		_check(Freemode.stops(id), "%s should be stopped on a new save" % id)
	_check(SaveCore.commit("first"), "the first commit failed")
	SaveCore.forget()
	var back := SaveCore.career()
	_check(Freemode.active(back) and int(back.freemode.entered_night) == 1, "free mode did not persist: %s" % str(back.freemode))
	var p: Dictionary = SaveCore.summary(1).plate
	_check(p.mode == "free" and int(p.night) == 1 and p.freemode_season == "", "plate: %s" % str(p))
	_check(Freemode.plate_line(1) == "Free mode · night 1" and Freemode.plate_line(0) == "Free mode · night 1", "plate line before the first season")
	# Nights go on, the dawn at 30 changes nothing and fires nothing.
	SaveCore.set_cash(100)
	SaveCore.commit("dawn", {"close_night": 1})
	_check(Freemode.active(SaveCore.career()) and int(SaveCore.career().story.night) == 2, "night 1 should close into 2, still free")
	var hooked := [0]
	var cb := func(_n: int) -> void: hooked[0] += 1
	Freemode.on_entered.append(cb)
	SaveCore.commit("dawn", {"close_night": 30})
	_check(hooked[0] == 0 and int(SaveCore.career().freemode.entered_night) == 1, "the night 30 dawn should not re-enter free mode")
	Freemode.on_entered.erase(cb)
	# An old career (blocks on disk, none for free mode) stays a story career.
	var old := {"gen": 4, "wallet": {"bank": 10}}
	SaveCore.fill_career(old)
	_check(not Freemode.active(old) and old.freemode.unlocked == false, "an old career should stay story: %s" % str(old.freemode))
	# Story forced for a new slot (the road tests).
	OS.set_environment("NEON_FREEMODE", "0")
	var forced := {}
	SaveCore.fill_career(forced)
	Freemode.refresh({})
	_check(not Freemode.active(forced) and not Freemode.is_active(), "NEON_FREEMODE=0 should force a story start")
	OS.set_environment("NEON_FREEMODE", "")

# ---------- units ----------

func _units() -> void:
	var c := {"gen": 1}   # a career already on disk
	SaveCore.fill_career(c)
	_check(not Freemode.active(c) and c.freemode.unlocked == false and c.freemode.entered_night == 0, "an old career should not be free: %s" % str(c.freemode))
	Freemode.refresh(c)
	_check(not Freemode.is_active() and not Freemode.stops("pike_debt") and Freemode.road_act() == -1, "story mode: stops / road_act")
	var cb := func(_n: int) -> void: fired += 1
	Freemode.on_entered.append(cb)
	SaveCore.commit("test", {"bank": 500}, func(cc: Dictionary) -> void:
		Freemode.enter(cc, 31)
		cc.freemode.later_field = {"season": 2}
		Freemode.enter(cc, 40))   # again: nothing changes
	_check(fired == 1, "on_entered should fire once (%d)" % fired)
	var cur := SaveCore.career()
	_check(cur.freemode.unlocked == true and int(cur.freemode.entered_night) == 31, "enter: %s" % str(cur.freemode))
	_check(Freemode.is_active() and Freemode.road_act() == RoadMap.MAX_ACT, "active after enter / road_act")
	for id in Freemode.STOPS:
		_check(Freemode.stops(id), "%s should be stopped" % id)
	for id in Freemode.KEEPS:
		_check(not Freemode.stops(id), "%s should keep running" % id)
	# Round trip.
	SaveCore.forget()
	Freemode.refresh({})
	var back := SaveCore.career()
	_check(Freemode.active(back) and int(back.freemode.entered_night) == 31, "free mode did not come back")
	_check(back.freemode.get("later_field", {}).get("season") == 2, "an unknown freemode field was lost")
	_check(int(back.save_version) == 2 and int(back.wallet.bank) == 500, "the rest of the career moved")
	SaveCore.commit("later")   # a later commit by code that never heard of the field
	_check(SaveCore.career().freemode.get("later_field", {}).has("season"), "a later commit dropped the unknown field")
	# A career with no freemode block.
	_fresh("no_block")
	SaveCore.commit("seed")   # the slot has a career now, so the next fill is not a new one
	SaveCore.commit("test", {}, func(cc: Dictionary) -> void: cc.erase("freemode"))
	SaveCore.forget()
	_check(not SaveCore.career().has("freemode") and not Freemode.active(SaveCore.career()), "a career with no block should load as not free")
	SaveCore.commit("again")
	_check(SaveCore.career().freemode.unlocked == false, "the block should be filled with defaults")
	Freemode.on_entered.erase(cb)

# ---------- the dawn that ends night 30 ----------

func _dawn() -> void:
	_fresh("dawn")
	SaveCore.commit("test", {"bank": 1000})
	SaveCore.set_cash(250)
	SaveCore.commit("dawn", {"close_night": 29})
	_check(not Freemode.active(SaveCore.career()) and SaveCore.summary(1).plate.mode == "story", "night 29's dawn should leave the story on")
	SaveCore.set_cash(300)
	_check(SaveCore.commit("dawn", {"close_night": 30}), "the night 30 dawn failed")
	SaveCore.forget()
	var c := SaveCore.career()
	_check(Freemode.active(c) and int(c.freemode.entered_night) == 31, "night 30's dawn should enter free mode: %s" % str(c.freemode))
	_check(SaveCore.bank() == 1550 and int(c.story.night) == 31, "bank %d (want 1550, banked once) night %s" % [SaveCore.bank(), str(c.story.night)])
	var p: Dictionary = SaveCore.summary(1).plate
	_check(p.mode == "free" and p.freemode_season == "Winter" and Freemode.plate_line(int(p.night)) == "Free mode · Winter · night 31", "plate: %s" % str(p))
	# The calendar goes on, with no cap.
	SaveCore.set_cash(100)
	SaveCore.commit("dawn", {"close_night": 31})
	_check(int(SaveCore.career().story.night) == 32 and int(SaveCore.career().freemode.entered_night) == 31, "night 31 closes into 32, entered_night stays")
	_check(SaveCore.bank() == 1650, "bank after night 31: %d" % SaveCore.bank())

func _chase() -> void:
	_fresh("chase")
	SaveCore.commit("test", {"bank": 100})
	SaveCore.set_cash(50)
	SaveCore.begin_chase()
	var ok := SaveCore.commit("dawn", {"close_night": 30})
	_check(not ok and not Freemode.active(SaveCore.career()), "nothing should be written in a chase (the flag included)")
	SaveCore.forget()
	var m := SaveCore.settle_chase()   # a quit mid-chase is a bust on return
	_check(m.busted == true and not Freemode.active(SaveCore.career()), "bust on return should still apply")
	SaveCore.commit("dawn", {"close_night": 30})
	_check(Freemode.active(SaveCore.career()), "after the chase the dawn should go through")

func _plate_lines() -> void:
	var want := {31: "Winter", 58: "Winter", 59: "Spring", 87: "Summer", 115: "Autumn", 143: "Winter"}
	for n in want:
		_check(Freemode.plate_line(n) == "Free mode · %s · night %d" % [want[n], n], "plate line for night %d: %s" % [n, Freemode.plate_line(n)])
	_check(Freemode.season_name(30) == "", "no season in the story")

# ---------- the game ----------

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
	match phase:
		0:
			if ticks < 10:
				return false
			_check(RoadMap.act == 1 and not Freemode.is_active(), "a story boot (NEON_FREEMODE=0) should be on act 1 (act %d)" % RoadMap.act)
			var clock: NightClock = game.night_clock
			game.wallet.add_cash(300)
			clock.night = 30
			clock.minutes = NightClock.NIGHT_MINUTES - 0.5
			clock.advance(10.0)
			_check(clock.night == 31, "the clock should read night 31 (%d)" % clock.night)
			_check(Freemode.active(SaveCore.career()) and int(SaveCore.career().freemode.entered_night) == 31, "the game's dawn should enter free mode")
			_check(SaveCore.bank() == 300, "bank should hold tonight's cash once (%d)" % SaveCore.bank())
			_check(SaveCore.summary(1).plate.mode == "free", "the plate should say free")
			# And on: nights 32, 33 with no cap.
			for i in 2:
				clock.minutes = NightClock.NIGHT_MINUTES - 0.5
				clock.advance(10.0)
			_check(clock.night == 33 and SaveCore.bank() == 300, "the calendar should count on (night %d bank %d)" % [clock.night, SaveCore.bank()])
			phase = 1
			_boot()
		1:
			if ticks < 10:
				return false
			_check(Freemode.is_active() and RoadMap.act == RoadMap.MAX_ACT, "a free boot should have the whole city (act %d)" % RoadMap.act)
			OS.set_environment("NEON_ACT", "1")
			phase = 2
			_boot()
		2:
			if ticks < 10:
				return false
			_check(RoadMap.act == 1, "NEON_ACT should still win (act %d)" % RoadMap.act)
			# A brand-new slot, no env: free, the whole city, from the first boot.
			OS.set_environment("NEON_ACT", "")
			OS.set_environment("NEON_FREEMODE", "")
			_fresh("new_boot")
			phase = 3
			_boot()
		3:
			if ticks < 10:
				return false
			_check(Freemode.is_active() and RoadMap.act == RoadMap.MAX_ACT, "a new-save boot should have the whole city (act %d)" % RoadMap.act)
			return _end()
	return false

func _end() -> bool:
	for m in failures:
		printerr("FAIL: ", m)
	print("freemode: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
		DirAccess.remove_absolute(dir.path_join(d))
