extends SceneTree

# W1 wiring in the real game (NEON_WEATHER=plan runs the deck with rain still
# off by default): the night's weather is taken from the deck at boot and at
# every new night, the one mid-night change lands on its hour, traffic thins
# in a storm, Dave gives the forecast a few seconds into the night, and the
# head unit shows the rain/storm icon.
# Run (headless): Godot --headless --fixed-fps 60 --path . -s res://tests/world/weather_plan_game.gd

const Weather := preload("res://scripts/world/weather.gd")
const Plan := preload("res://scripts/world/weather_plan.gd")
const TALK := 0   # Graveyard Radio, Dave's talk station
const TIMEOUT_TICKS := 1800

enum Step { BOOT, ROLL, CHANGE, TRAFFIC, FORECAST, DONE }

var step := Step.BOOT
var tick := 0
var step_start := 0
var failures: Array[String] = []
var game: Node
var target := {}
var dry_share := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_WEATHER", "plan")
	OS.set_environment("NEON_CLOCK", "20:00")
	OS.set_environment("NEON_ROAD_SEED", "4242")
	OS.set_environment("NEON_TRAFFIC", "16")
	NightClock.path = "user://test_weather_plan.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	# head unit icon rules, no game needed
	var hu := HeadUnit.new("sedan")
	hu.show_weather(1)
	_check(hu.weather_level == 1, "rain icon on for level 1")
	hu.show_weather(2)
	_check(hu.weather_level == 2, "storm icon on for level 2")
	hu.show_weather(Weather.Level.DAMP)
	_check(hu.weather_level == 0, "no icon for a damp road")
	hu.show_weather(0)
	_check(hu.weather_level == 0, "no icon when dry")
	# WX0: fog, drizzle, snow and slush have icons; clear, haze and damp none
	var icons := {Weather.Level.DRY: 0, Weather.Level.RAIN: 1, Weather.Level.DOWNPOUR: 2, Weather.Level.DAMP: 0,
		Weather.Level.HAZE: 0, Weather.Level.FOG: 5, Weather.Level.DRIZZLE: 6, Weather.Level.SNOW: 7, Weather.Level.SLUSH: 8}
	var icon_bad := []
	for st in icons:
		hu.show_weather(st)
		if hu.weather_level != icons[st]:
			icon_bad.append("%d -> %d" % [st, hu.weather_level])
	hu.show_weather(99)
	_check(icon_bad.is_empty() and hu.weather_level == 0, "icon per stage: fog, drizzle, snow, slush drawn; clear, haze, damp, unknown none %s" % str(icon_bad))
	hu.show_frost(true)
	_check(hu.frost_on, "frost flake on")
	hu.show_frost(false)
	_check(not hu.frost_on, "frost flake off")
	hu.free()
	# Boot on night 16 (a fixed fog night): the plan owns it
	OS.set_environment("NEON_NIGHT", "16")
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	if step == Step.DONE:
		return false
	game = current_scene
	if game == null or game.get("traffic") == null or game.get("radio") == null or game.get("night_clock") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var clock: NightClock = game.night_clock
	var waited := tick - step_start
	match step:
		Step.BOOT:
			var e: Dictionary = Weather.tonight
			_check(not e.is_empty() and e.night == clock.night, "tonight's entry is taken at boot (night %s)" % [e.get("night")])
			_check(Weather.level == Plan.level_at(e, clock.minutes), "boot level follows the deck (%d)" % Weather.level)
			# night 16 is a fog night: it starts as fog, or as the haze fog rolls in from
			_check(e.night == 16 and Plan.is_fog_night(16, game.weather_seed) and (e.start == Plan.FOG or e.start == Plan.HAZE),
				"night 16 is a fog night in the plan (start %d)" % e.get("start", -1))
			_check(absf(Weather.fog - float(Weather.STAGE[Weather.level].fog)) < 1e-6 and Weather.snow_cover == 0.0,
				"boot snaps the live fog to the stage (%.2f)" % Weather.fog)
			_check(game.weather_seed == game.road_seed, "tests use the road seed as the weather seed (saving is off)")
			# find a night in act 2 with a change and a storm-less start
			var seed: int = game.road_seed
			for n in range(11, 23):
				var c := Plan.entry(n, seed)
				if c.change_hour >= 0 and c.start != c.change_to and c.level == Plan.STORM:
					target = c
					break
			if target.is_empty():
				for n in range(11, 23):
					var c2 := Plan.entry(n, seed)
					if c2.change_hour >= 0 and c2.start != c2.change_to:
						target = c2
						break
			_check(not target.is_empty(), "the test road seed has a night with a mid-night change in act 2")
			if target.is_empty():
				return _end("")
			clock.speed = 0.0
			game.radio.station = TALK
			print("weather_plan_game: night %d start %d -> %d at %d:00" % [target.night, target.start, target.change_to, target.change_hour])
			_roll_to(clock, target.night)
			_go(Step.ROLL)
		Step.ROLL:
			_check(clock.night == target.night, "the clock is on night %d (%d)" % [target.night, clock.night])
			_check(Weather.tonight.get("night", -1) == target.night, "the new night's entry is taken at 8 p.m.")
			_check(Weather.level == target.start, "the night starts at its start level (%d vs %d)" % [Weather.level, target.start])
			_go(Step.CHANGE)
		Step.CHANGE:
			if waited == 1:
				clock.minutes = Plan.minutes_of(target.change_hour) - 0.1
				clock.advance(1.0)
			elif waited == 3:
				_check(Weather.level == target.change_to, "the change lands on its hour (level %d, wanted %d)" % [Weather.level, target.change_to])
				# the head unit's icon is the new stage's icon
				var hu := _find_head_unit(game)
				if hu == null:
					print("NOTE: no head unit in this build of the scene; icon check skipped")
				else:
					var want_icon: int = {1: 1, 2: 2, 5: 5, 6: 6, 7: 7, 8: 8}.get(Weather.level, 0)
					_check(hu.weather_level == want_icon, "the head unit shows the stage's icon (stage %d, icon %d)" % [Weather.level, hu.weather_level])
				# Dave's change line lands once: the same hour again says nothing
				var said := str(game.radio.get("_announce_text"))
				var line := Plan.change_line(target)
				_check(line == "" or said == line, "Dave said the change line once the hour struck: %s" % line)
				game.radio.set("_announce_text", "")
				game._weather_change(int(target.change_hour))
				_check(str(game.radio.get("_announce_text")) == "" and game.get("_change_done") == true, "the same hour again says nothing (change done)")
				# traffic: dry share vs this level's share at the same time
				Weather.set_level(Weather.Level.DRY, true)
			elif waited == 6:
				dry_share = game.traffic.active_share
				Weather.set_level(Weather.Level.DOWNPOUR, true)
			elif waited == 9:
				var want: float = dry_share * Weather.STAGE[Weather.Level.DOWNPOUR].traffic
				_check(absf(game.traffic.active_share - want) < 0.01, "a storm thins the traffic share %.3f -> %.3f (want %.3f)" % [dry_share, game.traffic.active_share, want])
				Weather.set_level(Weather.Level.DRY, true)
				# a fresh night near its start: the forecast comes ~8 s in
				_roll_to(clock, target.night + 1)
				clock.minutes = 1.0
				_go(Step.FORECAST)
		Step.FORECAST:
			var e2: Dictionary = Weather.tonight
			if waited > 90 and waited < 120 and game.radio.get("_announce_left") != null:
				pass
			if waited == int(Engine.physics_ticks_per_second * 10.0):   # 10 s of game time
				var line := Plan.forecast_line(e2)
				_check(str(game.radio.get("_announce_text")) == line or game.radio.get("_announce_text") == Plan.change_line(e2), "Dave read the forecast: %s (radio has: %s, tonight night %s)" % [line, str(game.radio.get("_announce_text")), str(e2.get("night"))])
				return _end("")
	return false

## Plays the end of the night before `night` and rolls into it, the way the
## clock does in a real game (the 5 a.m. hour is seen first, so 8 p.m. fires).
func _roll_to(clock: NightClock, night: int) -> void:
	clock.night = night - 1
	clock.minutes = NightClock.NIGHT_MINUTES - 1.0
	clock.advance(0.0)
	clock.minutes = NightClock.NIGHT_MINUTES - 0.1
	clock.advance(1.0)

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		failures.append(msg)
		printerr("FAIL: ", msg)

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
	step = Step.DONE
	print("weather_plan_game: ", "PASS" if failures.is_empty() else "FAIL")
	for f in failures:
		printerr("  ", f)
	quit(1 if not failures.is_empty() else 0)
	return true

## The cockpit's head unit, if the scene has one.
func _find_head_unit(n: Node) -> HeadUnit:
	if n is HeadUnit:
		return n
	for c in n.get_children():
		var f := _find_head_unit(c)
		if f != null:
			return f
	return null
