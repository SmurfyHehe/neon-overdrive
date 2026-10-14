extends SceneTree

# Weather in the run save (WX0): the stage and its live values go into the
# night ("weather"), the seed lives in the slot's career (world.weather_seed),
# and a resume puts both back.
#   1 mid-rain    rain begins at 1 a.m. (a night whose plan has that change);
#                 saved at 1:30 a.m. while the road is still wetting
#   2 resume      stage, wetness and wipers match what was saved (the wetness
#                 is NOT snapped to the stage's target), the change is marked
#                 done, and its line is not said again
#   3 old save    a run with no weather block loads: the profile has no
#                 weather seed, so the road seed is used once and saved
#   4 newer save  a stage number this build does not know falls back to the
#                 plan's stage
#   5 new game    a slot with no weather seed picks one and saves it
#   6 repeatable  the plan comes back from seed + night alone
#   7 once a game with no run to resume (a restart) the seed stays; two dawns
#                 in a row keep the same seed; another slot picks its own
# Exit code 1 on failure. Run (headless, one Godot):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/world/weather_save.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")
const Weather := preload("res://scripts/world/weather.gd")
const Plan := preload("res://scripts/world/weather_plan.gd")
const TALK := 0   # Graveyard Radio, Dave's talk station
const MINUTES_130 := 330.0   # 1:30 a.m., minutes since 8 p.m.

var game: Node
var phase := 0
var ticks := 0
var fails: Array[String] = []
var night := 0
var seed_s := 0
var entry := {}
var wet_saved := 0.0
var saved_line := ""

func _initialize() -> void:
	# A night in act 2 whose plan has a rain change at 1 a.m.
	for n in range(11, 23):
		for s in range(1, 3000):
			var e := Plan.entry(n, s)
			if e.change_hour == 1 and e.change_to == Plan.RAIN:
				night = n
				seed_s = s
				entry = e
				break
		if night != 0:
			break
	OS.set_environment("NEON_WEATHER", "plan")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_ROAD_SEED", "")
	OS.set_environment("NEON_NIGHT", str(night))
	OS.set_environment("NEON_CLOCK", "00:50")
	NightClock.path = "user://test_weather_save.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	SaveStore.root = "user://test_weather_save"
	_wipe(ProjectSettings.globalize_path(SaveStore.root))
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveDirector.enabled = true
	SaveStore.select_slot(1)
	SaveStore.clear_run()
	SaveStore.load_meta()
	if night == 0:
		_fail("no night with a 1 a.m. rain change found in 3000 seeds")
		_finish()
		return
	print("weather_save: night %d, seed %d: start %d -> %d at 01:00" % [night, seed_s, entry.start, entry.change_to])
	_boot()

func _boot() -> void:
	if game != null:
		root.remove_child(game)
		game.free()
	Weather.reset()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)
	ticks = 0

func _fail(msg: String) -> void:
	fails.append(msg)
	printerr("FAIL: ", msg)

func _pass(msg: String) -> void:
	print("PASS: ", msg)

func _check(ok: bool, msg: String) -> void:
	if ok:
		_pass(msg)
	else:
		_fail(msg)

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree() or game.get("night_clock") == null or game.get("radio") == null or game.get("saver") == null:
		return false
	ticks += 1
	var clock: NightClock = game.night_clock
	var hz := Engine.physics_ticks_per_second
	match phase:
		0:
			if ticks == 2:
				# A fresh game picked its own seed; pin the test's, then plan
				# the night again with it, as a game booted on that seed would.
				_check(game.weather_seed != 0 and SaveStore.weather_seed() == game.weather_seed, "5 new game: a weather seed was picked and saved (%d)" % game.weather_seed)
				game.weather_seed = seed_s
				SaveStore.set_weather_seed(seed_s)
				clock.speed = 0.0
				game.radio.station = TALK
				game._begin_night(true)
				_check(Weather.level == entry.start and Weather.wetness == Weather.STAGE[entry.start].wet,
					"1 mid-rain: the night starts at stage %d, wetness %.2f" % [Weather.level, Weather.wetness])
				# 1 a.m.: the rain begins
				clock.minutes = Plan.minutes_of(1) - 0.1
				clock.advance(1.0)
			elif ticks == 6:
				_check(Weather.level == Plan.RAIN, "1 mid-rain: rain began at 1 a.m. (stage %d)" % Weather.level)
				saved_line = Plan.change_line(entry)
				_check(str(game.radio.get("_announce_text")) == saved_line, "1 mid-rain: Dave said the change: %s" % saved_line)
			elif ticks == hz * 5:
				# 1:30 a.m., the road still wetting toward steady rain
				clock.minutes = MINUTES_130
				_check(Weather.wetness > Weather.STAGE[entry.start].wet and Weather.wetness < 0.74, "1 mid-rain: wetness %.3f is part-way" % Weather.wetness)
				wet_saved = Weather.wetness
				_check(game.saver.save_now(), "1 mid-rain: the run was saved at 1:30")
				var run := SaveStore.load_run()
				var w: Dictionary = run.get("weather", {})
				_check(int(w.get("stage", -1)) == Plan.RAIN and absf(float(w.get("wet", -1.0)) - wet_saved) < 1e-6 \
					and w.get("change_done", false) == true and w.has("fog") and w.has("rain") and w.has("snow_fall") and w.has("snow_cover"),
					"1 mid-rain: run.json has the weather block %s" % str(w))
				phase = 1
				_boot()
		1:
			if ticks == 3:
				_check(game.weather_seed == seed_s, "2 resume: the slot's weather seed came back (%d)" % game.weather_seed)
				_check(Weather.level == Plan.RAIN, "2 resume: still raining (stage %d)" % Weather.level)
				_check(absf(Weather.wetness - wet_saved) < 0.01 and absf(Weather.wetness - 0.75) > 0.05,
					"2 resume: wetness %.3f is what was saved (%.3f), not the stage's 0.75" % [Weather.wetness, wet_saved])
				_check(Weather.wipers() == "normal", "2 resume: wipers %s" % Weather.wipers())
				_check(game.get("_change_done") == true, "2 resume: the change is marked done")
				game.radio.station = TALK
				game.radio.set("_announce_text", "")
				_check(game._weather_change(1) == false and str(game.radio.get("_announce_text")) == "" and Weather.level == Plan.RAIN,
					"2 resume: the 1 a.m. change does not land or speak again")
			elif ticks == hz * 3:
				_check(str(game.radio.get("_announce_text")) == "", "2 resume: Dave said nothing in 3 s (no forecast, no change line)")
				# 3 old save: no weather block, no weather seed in the profile
				var run := SaveStore.load_run()
				run.erase("weather")
				SaveStore.save_run(run)
				SaveCore.commit("test", {}, func(c: Dictionary) -> void: c.world.erase("weather_seed"))
				_check(SaveStore.weather_seed() == 0, "3 old save: the profile has no weather seed now")
				phase = 2
				_boot()
		2:
			if ticks == 3:
				var e := Plan.entry(night, game.road_seed)
				_check(game.weather_seed == game.road_seed and SaveStore.weather_seed() == game.road_seed,
					"3 old save: it falls back to the road seed %d once and saves it (%d)" % [game.road_seed, SaveStore.weather_seed()])
				_check(night == clock.night and clock.minutes > 300.0, "3 old save: the clock came back (night %d, %.0f min)" % [clock.night, clock.minutes])
				_check(Weather.level == Plan.level_at(e, clock.minutes), "3 old save: the stage is the plan's for that seed (%d)" % Weather.level)
				var done: bool = e.change_hour >= 0 and clock.minutes >= Plan.minutes_of(e.change_hour)
				_check(game.get("_change_done") == done, "3 old save: change_done follows the clock (%s)" % done)
				# 4 a save from a newer build: a stage number this build lacks
				var run := SaveStore.load_run()
				run.weather = {"stage": 99, "wet": 0.9, "fog": 3.0, "rain": 1.0, "snow_fall": 0.0, "snow_cover": 0.0, "change_done": true}
				SaveStore.save_run(run)
				phase = 3
				_boot()
		3:
			if ticks == 3:
				var e := Plan.entry(night, game.weather_seed)
				_check(Weather.level == Plan.level_at(e, clock.minutes) and Weather.level != 99,
					"4 newer save: unknown stage 99 falls back to the plan's stage (%d)" % Weather.level)
				_check(absf(Weather.wetness - float(Weather.STAGE[Weather.level].wet)) < 0.02,
					"4 newer save: live values are the stage's, not the unknown block's (wet %.2f)" % Weather.wetness)
				# 6 repeatable: the same plan from seed and night alone
				_check(str(Plan.entry(night, game.weather_seed)) == str(Plan.generate(Plan.act_range(night).x, Plan.act_range(night).y, game.weather_seed)[night - Plan.act_range(night).x]),
					"6 repeatable: tonight's plan comes back from seed + night")
				# 7 once a game: no run to resume (a restart), the seed stays
				seed_s = game.weather_seed
				SaveStore.clear_run()
				phase = 4
				_boot()
		4, 5, 6:
			if ticks == 3:
				var what: String = ["a restart (no run to resume)", "the first dawn", "the second dawn in a row"][phase - 4]
				_check(SaveStore.load_run().is_empty() or phase == 4, "7 once a game: after %s the night has no run" % what)
				_check(game.weather_seed == seed_s and SaveStore.weather_seed() == seed_s,
					"7 once a game: after %s the weather seed is still %d (%d)" % [what, seed_s, game.weather_seed])
				if phase < 6:
					# Dawn: the night is banked and closed, night.json is left without a run.
					_check(SaveCore.commit("dawn", {"close_night": 0}), "7 once a game: the dawn commit went through")
				else:
					# A new game in another slot picks its own seed; slot 1 keeps its.
					SaveStore.select_slot(2)
				phase += 1
				_boot()
		7:
			if ticks == 3:
				var picked: int = game.weather_seed
				_check(picked != 0 and SaveStore.weather_seed() == picked and SaveStore.weather_seed(1) == seed_s,
					"5 new game: an empty slot picked and saved its own seed (%d); slot 1 kept %d" % [picked, SaveStore.weather_seed(1)])
				_finish()
	return false

## Clears this test's own save folder from a previous run.
func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

func _finish() -> void:
	SaveDirector.enabled = false
	Weather.reset()
	print("weather_save: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
