extends SceneTree

# The game on build 3 saves, after save core (one save per slot).
#   1 fresh slot   the game boots on an empty save folder, picks a weather
#                  seed and keeps it in the career
#   2 build 3 save the frozen build 3 slot (tests/save/fixtures/v1_build3:
#                  shop.json, wallet receipts, meta weather_seed, a run with
#                  weather, known stops and a manual gearbox in 3rd) is
#                  upgraded and the game boots into its saved night: same car,
#                  place, money, receipts, shop day, weather seed and rain,
#                  known stops, gearbox mode and gear, fitted parts
# The log must have no ERROR lines (the runner greps it).
# Exit code 1 on failure. Run (headless, one Godot):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/save/save_build3_boot.gd

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const PlayerTune := preload("res://scripts/car/player_tune.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const Weather := preload("res://scripts/world/weather.gd")
const ShopDay := preload("res://scripts/core/shop_day.gd")

const FIXTURE := "res://tests/save/fixtures/v1_build3"
const ROOT := "user://test_save_build3_boot"

var failures: Array[String] = []
var game: Node
var phase := 0
var ticks := 0
var old_run := {}

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CAR", "")
	OS.set_environment("NEON_SHOP", "1")
	OS.set_environment("NEON_WEATHER", "plan")
	SaveCore.persist = true
	SaveDirector.enabled = true
	PlayerTune.enabled = true
	# 1: an empty save folder.
	SaveCore.legacy_dir = ""
	SaveCore.root = ROOT.path_join("fresh/saves")
	SaveCore.slot = 0
	SaveCore.chase_active = false
	_boot()

func _boot() -> void:
	if game != null:
		root.remove_child(game)
		game.free()
	Weather.reset()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)
	ticks = 0

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		failures.append(msg)
		printerr("FAIL: ", msg)

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree() or game.get("player") == null:
		return false
	ticks += 1
	if phase == 0 and ticks == 30:
		_check(SaveStore.load_run().is_empty() or SaveDirector.valid_run(SaveStore.load_run()), "1 fresh slot: the game booted and drove 30 ticks")
		_check(game.weather_seed != 0 and SaveStore.weather_seed() == game.weather_seed, "1 fresh slot: a weather seed was picked and is in the career (%d)" % game.weather_seed)
		_check(not FileAccess.file_exists(SaveCore.slot_dir().path_join("wallet.json")) and FileAccess.file_exists(SaveCore.file("career")), "1 fresh slot: it writes career.json, not the old section files")
		# 2: the build 3 slot.
		_copy(FIXTURE, ROOT.path_join("b3"))
		SaveCore.legacy_dir = ROOT.path_join("b3/global")
		SaveCore.root = ROOT.path_join("b3/saves")
		SaveCore.slot = 0
		old_run = AtomicJson.read(FIXTURE.path_join("saves/slot_1/run.json")).data
		phase = 1
		_boot()
	elif phase == 1 and ticks == 2:
		var p: PlayerCar = game.player
		_check(PlayerCar.chassis_kind() == "p1_coupe", "2 build 3 save: the game booted in %s" % PlayerCar.chassis_kind())
		var want := SaveDirector.array_to_xform(old_run.car.xform)
		var slack := SaveDirector.v3(old_run.car.lin_vel).length() / Engine.physics_ticks_per_second * 2.0 + 0.01
		_check(p.global_position.distance_to(want.origin) <= slack, "2 build 3 save: the car is %.2f m from where the save left it" % p.global_position.distance_to(want.origin))
		_check(game.road_seed == int(old_run.road.seed) and game.night_clock.night == 7 and absf(game.night_clock.minutes - float(old_run.clock.minutes)) < 0.5,
			"2 build 3 save: the saved road and night (seed %d, night %d, %.1f min)" % [game.road_seed, game.night_clock.night, game.night_clock.minutes])
		_check(p.transmission_mode() == PlayerCar.Transmission.MANUAL and p.current_gear == 3, "2 build 3 save: manual gearbox in 3rd (mode %d, gear %d)" % [p.transmission_mode(), p.current_gear])
		var old_wallet: Dictionary = AtomicJson.read(FIXTURE.path_join("saves/slot_1/wallet.json")).data
		_check(game.wallet.bank == int(old_wallet.bank) and game.wallet.cash == int(old_wallet.cash), "2 build 3 save: bank %d cash %d" % [game.wallet.bank, game.wallet.cash])
		_check(game.wallet.receipts.size() == 3 and str(game.wallet.receipts) == str(old_wallet.receipts), "2 build 3 save: the 3 receipts %s" % str(game.wallet.receipts))
		_check(not game.wallet.pay_shop(100, str(old_wallet.receipts[2])) and game.wallet.bank == int(old_wallet.bank), "2 build 3 save: an old receipt cannot be paid again")
		_check(game.weather_seed == 12345 and SaveStore.weather_seed() == 12345, "2 build 3 save: the weather seed (%d)" % game.weather_seed)
		_check(Weather.level == 1, "2 build 3 save: it is still raining (stage %d)" % Weather.level)
		_check(RoadMap.known_stops.has("g2a") and RoadMap.known_stops.has("g5b") and RoadMap.known_stops.size() == 2, "2 build 3 save: the known stops %s" % str(RoadMap.known_stops.keys()))
		var old_shop: Dictionary = AtomicJson.read(FIXTURE.path_join("saves/slot_1/shop.json")).data
		var shop: Node = game.shop_day
		_check(shop.day() == int(old_shop.day) and shop.stage() == ShopDay.LATE_JOB and str(shop.card_ids()) == str(old_shop.cards)
			and str(shop.data.get("taken")) == str(old_shop.taken) and str(shop.data.get("late_taken")) == str(old_shop.late_taken),
			"2 build 3 save: the shop day (day %d, stage %s, taken %s, late %s)" % [shop.day(), shop.stage(), str(shop.data.get("taken")), str(shop.data.get("late_taken"))])
		_check(SaveStore.load_mod_tree().cars.get("p1_coupe", {}).get("installed") == ["exhaust_a", "turbo_s1"], "2 build 3 save: fitted parts %s" % str(SaveStore.load_mod_tree().cars))
		_check(not game.saver.busted and not SaveCore.locked(), "2 build 3 save: no bust, the slot is open")
		return _end()
	return false

func _end() -> bool:
	SaveDirector.enabled = false
	SaveCore.persist = false
	PlayerTune.enabled = false
	Weather.reset()
	print("save_build3_boot: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

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
