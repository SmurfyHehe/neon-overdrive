extends SceneTree

# Save upgrades (save core S2; scripts/save/save_upgrade.gd). Old saves are
# kept as frozen fixtures, one folder per save version:
#   tests/save/fixtures/v<N>/saves/    a save folder as that version wrote it
#   tests/save/fixtures/v<N>/global/   what that version kept outside the slots
#   tests/save/fixtures/v<N>/expect.json   what must still be true after loading it
# Checks
# - the guard: there is an upgrade step for every version below
#   CURRENT_SAVE_VERSION. Raising the version without adding
#   upgrade_<N>_to_<N+1> fails here.
# - every fixture folder upgrades to the current version and loads: the bank,
#   tonight's cash and the owned part ids are unchanged, and the night resumes
# - version 1 in detail: fitted parts, the special vehicle, the free-wreck
#   flag, the car picked, the run's position, the clock, the tunes, the dirt;
#   pre_v1/ holds the old files byte for byte and the old files outside the
#   slots are untouched; the slot that was not being played gets no tunes;
#   nothing is upgraded twice; later commits rotate career.json.bak1..3
# - a build 3 save in detail (fixtures/v1_build3: version 1 files plus
#   shop.json, wallet receipts, meta weather_seed, and a run with weather,
#   known stops and the gearbox fields): the receipts, the shop day, the
#   weather seed, the owned and fitted parts (both id forms), the known stops
#   and the gearbox are all carried over; pre_v1/ holds shop.json too
# - the game boots from the upgraded save, in the saved car at the saved place
#   (the build 3 save's boot is tests/save/save_build3_boot.gd)
#
# When the save format changes: add the step to save_upgrade.gd, bump
# CURRENT_SAVE_VERSION, and freeze a save of the old version as a new fixture
# folder (never edit an old one).
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/save/save_upgrade.gd

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveUpgrade := preload("res://scripts/save/save_upgrade.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const PlayerTune := preload("res://scripts/car/player_tune.gd")

const FIXTURES := "res://tests/save/fixtures"
const ROOT := "user://test_save_upgrade"

var failures: Array[String] = []
var game: Node
var ticks := 0
var v1_run := {}

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CAR", "")
	_guard()
	var folders := DirAccess.get_directories_at(FIXTURES)
	_check(folders.has("v1"), "the version 1 fixture is missing")
	for name in folders:
		_fixture(name)
	if not failures.is_empty():
		_end()   # the detail checks below assume the fixtures loaded
		return
	_v1_details()
	if folders.has("v1_build3"):
		_b3_details()
	_open("v1", false)   # part 2 boots the version 1 save
	# Part 2: the game boots from the upgraded version 1 save.
	SaveCore.persist = true
	SaveDirector.enabled = true
	PlayerTune.enabled = true
	ExhaustTune.save_path = ExhaustTune.DEFAULT_PATH
	CarDirt.path = CarDirt.DEFAULT_PATH
	NightClock.path = NightClock.DEFAULT_PATH
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

# ---------- the guard ----------

func _guard() -> void:
	_check(SaveCore.SAVE_VERSION == SaveUpgrade.CURRENT_SAVE_VERSION, "SaveCore writes a different version than the upgrades reach")
	for v in range(1, SaveUpgrade.CURRENT_SAVE_VERSION):
		_check(SaveUpgrade.has_step(v), "CURRENT_SAVE_VERSION is %d but save_upgrade.gd has no upgrade_%d_to_%d: add the step with the version bump" % [SaveUpgrade.CURRENT_SAVE_VERSION, v, v + 1])
	_check(not SaveUpgrade.has_step(SaveUpgrade.CURRENT_SAVE_VERSION), "there is an upgrade step past CURRENT_SAVE_VERSION: bump the version")
	_check(DirAccess.dir_exists_absolute(FIXTURES.path_join("v%d" % maxi(SaveUpgrade.CURRENT_SAVE_VERSION - 1, 1))), "no frozen fixture for the version before the current one")

# ---------- every fixture ----------

## Copies the fixture into this test's folder and points the save system at it.
func _open(name: String, copy: bool = true) -> void:
	var dir := ROOT.path_join(name)
	if copy:
		_copy(FIXTURES.path_join(name), dir)
	SaveCore.legacy_dir = dir.path_join("global")
	SaveCore.root = dir.path_join("saves")
	SaveCore.slot = 0
	SaveCore.chase_active = false

func _fixture(name: String) -> void:
	var expect := _plain(FIXTURES.path_join(name).path_join("expect.json"))
	_check(not expect.is_empty(), "%s: no expect.json" % name)
	_open(name)
	var n := SaveCore.active_slot()
	_check(not SaveCore.locked() and not SaveCore.career().is_empty(), "%s: did not load" % name)
	for f in SaveCore.FILES:
		var d: Dictionary = AtomicJson.read(SaveCore.file(f)).get("data", {})
		_check(int(d.get("save_version", 0)) == SaveUpgrade.CURRENT_SAVE_VERSION, "%s: %s.json is save version %s, not %d" % [name, f, str(d.get("save_version")), SaveUpgrade.CURRENT_SAVE_VERSION])
	_check(SaveCore.bank() == int(expect.get("bank", -1)), "%s: bank %d, was %s" % [name, SaveCore.bank(), str(expect.get("bank"))])
	_check(SaveCore.cash() == int(expect.get("cash", -1)), "%s: cash %d, was %s" % [name, SaveCore.cash(), str(expect.get("cash"))])
	var owned: Array = SaveStore.load_garage().owned_parts.duplicate()
	owned.sort()
	var want: Array = expect.get("owned_parts", []).duplicate()
	want.sort()
	_check(str(owned) == str(want), "%s: owned parts %s, were %s" % [name, str(owned), str(want)])
	var run := SaveStore.load_run()
	_check(SaveDirector.valid_run(run) == (expect.get("night_resumes", true) == true), "%s: the night does not resume" % name)
	_check(SaveCore.summary(n).cash == SaveCore.cash() and SaveCore.summary(n).bank == SaveCore.bank() and not SaveCore.summary(n).empty, "%s: the slot plate is wrong: %s" % [name, str(SaveCore.summary(n))])
	print("fixture %s: loads as save version %d, bank %d, cash %d, %d parts, night %s" % [name, SaveUpgrade.CURRENT_SAVE_VERSION, SaveCore.bank(), SaveCore.cash(), owned.size(), "resumes" if SaveDirector.valid_run(run) else "does not resume"])

# ---------- version 1 in detail ----------

func _v1_details() -> void:
	var src := FIXTURES.path_join("v1")
	_open("v1", false)   # as _fixture left it: upgraded once
	var c := SaveCore.career()
	_check(SaveCore.gen() == 1, "an upgraded career should be gen 1 (%d)" % SaveCore.gen())
	_check(SaveStore.load_mod_tree().cars.get("p1_coupe", {}).get("installed") == ["exhaust_a", "turbo_s1"], "fitted parts: %s" % str(SaveStore.load_mod_tree()))
	_check(c.cars.p1_coupe.parts_owned == ["exhaust_a", "turbo_s1"], "a car should own what it has fitted: %s" % str(c.cars.p1_coupe))
	_check(c.cars.p2_hothatch.parts_owned == ["wheels_mesh"], "an unfitted part should go to the car you drive: %s" % str(c.cars.get("p2_hothatch")))
	_check(SaveStore.load_special().unlocked == {"l1_lowrider": true}, "special vehicles: %s" % str(SaveStore.load_special()))
	_check(SaveStore.first_wreck_used() and c.walt.first_total_used == true, "the free-wreck flag was lost")
	_check(SaveCore.current_car() == "p2_hothatch", "the car picked: %s" % SaveCore.current_car())
	# The run, upgraded, not thrown away.
	v1_run = AtomicJson.read(src.path_join("saves/slot_1/run.json")).data
	var run := SaveStore.load_run()
	_check(not run.has("version") and str(run.get("car")) == str(v1_run.car) and str(run.get("road")) == str(v1_run.road) \
		and int(run.get("origin_index", -1)) == int(v1_run.origin_index) and int(run.get("radio", -1)) == int(v1_run.radio), "the run changed in the upgrade")
	_check(SaveCore.clock().minutes == float(v1_run.clock.minutes) and SaveCore.clock().night == 7, "the clock: %s" % str(SaveCore.clock()))
	_check(int(c.story.night) == 7 and int(c.story.night_closed) == 6, "the story's night: %s" % str(c.story))
	# Tunes: each car's own file to that car; the named tunes to the car you drive.
	# (Version 1 kept one exhaust tune, under the coupe's id, whatever car was
	# driven: EngineAudio.START_PRESET. It stays under that id.)
	var coupe := SaveCore.tune("p1_coupe")
	_check(coupe.get("live", {}).get("final_drive") == _plain(src.path_join("global/player_tune.json")).values.final_drive and coupe.get("exhaust", {}).get("loudness") == 0.8, "the coupe's tunes: %s" % str(coupe))
	var hatch := SaveCore.tune("p2_hothatch")
	_check(hatch.get("live", {}).get("final_drive") == 3.25 and hatch.get("slots", {}).has("Street") and not coupe.has("slots"), "the hatch's tunes: %s" % str(hatch))
	_check(SaveCore.car_state("p2_hothatch").get("dirt") == 0.42, "the dirt: %s" % str(SaveCore.car_state("p2_hothatch").get("dirt")))
	# Nothing old was moved or changed.
	var pre := SaveCore.slot_dir(1).path_join("pre_v1")
	for f in DirAccess.get_files_at(src.path_join("saves/slot_1")):
		var old := FileAccess.get_file_as_bytes(src.path_join("saves/slot_1").path_join(f))
		_check(FileAccess.get_file_as_bytes(pre.path_join(f)) == old, "pre_v1/%s is not the old file" % f)
		if f != "meta.json":   # the one name both versions use
			_check(FileAccess.get_file_as_bytes(SaveCore.slot_dir(1).path_join(f)) == old, "the old %s was changed or moved" % f)
	for f in DirAccess.get_files_at(src.path_join("global")):
		_check(FileAccess.get_file_as_bytes(SaveCore.legacy_dir.path_join(f)) == FileAccess.get_file_as_bytes(src.path_join("global").path_join(f)), "the old %s outside the slots was changed" % f)
	# The slot that was not being played: its money and parts, the same car
	# pick, and a clean start otherwise: no saved tunes, no dirt.
	_check(SaveCore.bank(2) == 400 and SaveCore.cash(2) == 15 and SaveStore.load_garage(2).owned_parts == ["seat_b"], "slot 2's money or parts: bank %d cash %d %s" % [SaveCore.bank(2), SaveCore.cash(2), str(SaveStore.load_garage(2))])
	_check(SaveCore.current_car(2) == "p2_hothatch" and SaveCore.career(2).tunes.is_empty() and not SaveCore.car_state("p2_hothatch", 2).has("dirt"), "slot 2 should have the car pick and no tunes or dirt: %s" % str(SaveCore.career(2).get("tunes")))
	_check(FileAccess.file_exists(SaveCore.slot_dir(2).path_join("pre_v1/wallet.json")) and SaveCore.summary(3).empty, "slot 2 has no pre_v1 copy, or slot 3 is not empty")
	# A relaunch does not upgrade again.
	var career_bytes := FileAccess.get_file_as_bytes(SaveCore.file("career"))
	var pre_files := DirAccess.get_files_at(pre)
	SaveCore.forget()
	_check(SaveCore.gen() == 1 and FileAccess.get_file_as_bytes(SaveCore.file("career")) == career_bytes and DirAccess.get_files_at(pre) == pre_files, "the slot was upgraded twice")
	# Later commits rotate the career's backups; pre_v1 stays.
	for i in 4:
		SaveCore.commit("test")
	var f := SaveCore.file("career")
	_check(FileAccess.file_exists(f + ".bak1") and FileAccess.file_exists(f + ".bak3") and not FileAccess.file_exists(f + ".bak4"), "career.json.bak1..3 should rotate after the upgrade")
	_check(int(AtomicJson.decode(FileAccess.get_file_as_string(f + ".bak1")).gen) == 4 and DirAccess.get_files_at(pre) == pre_files, "the backups or pre_v1 are wrong after later commits")
	_check(SaveCore.bank() == 1830 and SaveCore.cash() == 240 and SaveDirector.valid_run(SaveStore.load_run()), "later commits changed the money or dropped the night")

# ---------- a build 3 save in detail ----------

func _b3_details() -> void:
	var src := FIXTURES.path_join("v1_build3/saves/slot_1")
	_open("v1_build3", false)   # as _fixture left it: upgraded once
	var c := SaveCore.career()
	var old_wallet: Dictionary = AtomicJson.read(src.path_join("wallet.json")).data
	var old_shop: Dictionary = AtomicJson.read(src.path_join("shop.json")).data
	var old_run: Dictionary = AtomicJson.read(src.path_join("run.json")).data
	# Money and receipts.
	var w := SaveStore.load_wallet()
	_check(w.bank == int(old_wallet.bank) and w.cash == int(old_wallet.cash), "build 3: bank %d cash %d" % [w.bank, w.cash])
	_check(old_wallet.receipts.size() == 3 and str(w.receipts) == str(old_wallet.receipts) and str(c.wallet.receipts) == str(old_wallet.receipts), "build 3: the receipts: %s" % str(w.receipts))
	_check(not c.wallet.has("cash"), "build 3: tonight's cash should not be in the career wallet")
	# Walt's board.
	_check(not old_shop.is_empty() and str(SaveStore.load_shop()) == str(old_shop), "build 3: the shop day changed: %s" % str(SaveStore.load_shop()))
	_check(int(c.shop.day) == 6 and str(c.shop.stage) == "late_job" and c.shop.cards.size() == 3 and c.shop.taken is String and c.shop.late_taken is String,
		"build 3: the shop block: %s" % str(c.get("shop")))
	# The weather seed: in the career, out of meta.json.
	_check(SaveStore.weather_seed() == 12345 and int(c.world.weather_seed) == 12345, "build 3: the weather seed: %d" % SaveStore.weather_seed())
	_check(not AtomicJson.read(SaveCore.file("meta")).data.has("weather_seed") and c.world.has("seed") and c.world.has("difficulty"), "build 3: meta.json still has the weather seed, or the world block is not whole: %s" % str(c.world))
	# Parts: owned as "id" or "<car>/id", fitted either way.
	_check(SaveStore.load_mod_tree().cars.get("p1_coupe", {}).get("installed") == ["exhaust_a", "turbo_s1"], "build 3: fitted parts: %s" % str(SaveStore.load_mod_tree()))
	_check(c.cars.p1_coupe.parts_owned == ["p1_coupe/exhaust_a", "turbo_s1", "wheels_mesh"] and c.cars.p1_coupe.fitted == ["exhaust_a", "turbo_s1"], "build 3: the coupe's parts: %s" % str(c.cars.p1_coupe))
	_check(c.cars.get("p2_hothatch", {}).get("parts_owned") == ["p2_hothatch/seat_b"], "build 3: a car's own unfitted part should stay with that car: %s" % str(c.cars.get("p2_hothatch")))
	# The run: weather, known stops and the gearbox, as they were.
	var run := SaveStore.load_run()
	_check(str(run.get("weather")) == str(old_run.weather) and int(run.weather.stage) == 1, "build 3: the run's weather block: %s" % str(run.get("weather")))
	_check(run.get("known_stops") == ["g2a", "g5b"], "build 3: the known stops: %s" % str(run.get("known_stops")))
	_check(int(run.car.get("box", -1)) == 2 and int(run.car.gear) == 3 and run.car.has("demand"), "build 3: the gearbox fields: %s" % str([run.car.get("box"), run.car.get("gear"), run.car.get("demand")]))
	_check(str(run.car) == str(old_run.car) and str(run.road) == str(old_run.road) and SaveCore.clock().night == 7, "build 3: the run changed in the upgrade")
	# pre_v1 holds every old file, shop.json too, and the old files are in place.
	var pre := SaveCore.slot_dir(1).path_join("pre_v1")
	_check(FileAccess.file_exists(pre.path_join("shop.json")), "build 3: pre_v1/ has no shop.json")
	for f in DirAccess.get_files_at(src):
		var old := FileAccess.get_file_as_bytes(src.path_join(f))
		_check(FileAccess.get_file_as_bytes(pre.path_join(f)) == old, "build 3: pre_v1/%s is not the old file" % f)
		if f != "meta.json":
			_check(FileAccess.get_file_as_bytes(SaveCore.slot_dir(1).path_join(f)) == old, "build 3: the old %s was changed or moved" % f)
	# Later commits keep all of it; a relaunch does not upgrade again.
	_check(SaveCore.commit("test") and SaveCore.commit("dawn", {"close_night": 0}), "build 3: commits after the upgrade")
	SaveCore.forget()
	_check(SaveCore.gen() == 3 and SaveStore.weather_seed() == 12345 and str(SaveStore.load_wallet().receipts) == str(old_wallet.receipts)
		and str(SaveStore.load_shop()) == str(old_shop) and SaveCore.bank() == int(old_wallet.bank) + int(old_wallet.cash),
		"build 3: after two commits and a relaunch: gen %d, seed %d, bank %d, receipts %s" % [SaveCore.gen(), SaveStore.weather_seed(), SaveCore.bank(), str(SaveStore.load_wallet().receipts)])

# ---------- part 2: the game on the upgraded save ----------

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	if ticks < 2:
		return false
	var p: PlayerCar = game.get("player")
	_check(PlayerCar.chassis_kind() == "p2_hothatch", "the game booted in %s" % PlayerCar.chassis_kind())
	var want := SaveDirector.array_to_xform(v1_run.car.xform)
	var slack := SaveDirector.v3(v1_run.car.lin_vel).length() / Engine.physics_ticks_per_second * 2.0 + 0.01
	_check(p.global_position.distance_to(want.origin) <= slack, "the car is %.2f m from where the old save left it" % p.global_position.distance_to(want.origin))
	_check(game.road_seed == int(v1_run.road.seed) and game.origin_index == int(v1_run.origin_index), "the road is not the saved one")
	_check(game.wallet.cash == 240 and game.wallet.bank == 1830, "the wallet: cash %d bank %d" % [game.wallet.cash, game.wallet.bank])
	_check(absf(game.night_clock.minutes - float(v1_run.clock.minutes)) < 0.5 and game.night_clock.night == 7, "the clock: %.1f night %d" % [game.night_clock.minutes, game.night_clock.night])
	_check(absf(game.fx.dirt.level - 0.42) < 0.01, "the dirt: %f" % game.fx.dirt.level)
	_check(absf(TuneParams.get_value(p.spec, "final_drive") - 3.25) < 0.001, "the hatch's tune was not applied (final drive %f)" % TuneParams.get_value(p.spec, "final_drive"))
	_check(absf(float(p.spec.exhaust.loudness) - 0.8) < 0.001, "the exhaust tune was not applied (%s)" % str(p.spec.exhaust))
	_check(game.game_state.special_unlocked.get("l1_lowrider", false) == true, "the special vehicle is not unlocked in the game")
	return _end()

func _end() -> bool:
	SaveDirector.enabled = false
	SaveCore.persist = false
	for m in failures:
		printerr("FAIL: ", m)
	print("save_upgrade: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

# ---------- helpers ----------

func _plain(path: String) -> Dictionary:
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data

func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for sub in DirAccess.get_directories_at(from):
		_copy(from.path_join(sub), to.path_join(sub))
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(from.path_join(f)), ProjectSettings.globalize_path(to.path_join(f)))

## Clears this test's own folder from a previous run.
func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
