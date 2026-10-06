extends SceneTree

# Tyre load sensitivity, tyre temperature and wear, clutch wear (Phase C), headless
# and silent:
# - pure model: a tyre heats with slip and cools without it, the grip window is
#   cold < warm < overheated, wear only builds with slip beyond the threshold,
#   grip never goes under its floor, the TYRE light follows temperature or wear
# - clutch wear builds only with slip power and weakens the clutch with a floor;
#   repair() resets everything
# - the real game: driving on the limiter in 1st heats the driven tyres, the grip
#   multipliers reach the wheels, the car still moves; the pause menu has a Service
#   button that resets wear
# - load sensitivity: a stiffer load exponent lowers peak cornering grip a little,
#   top speed is unchanged (TuneTrack)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/tyres.gd

const TIMEOUT_TICKS := 60 * 120

enum Step { BOOT, BURN, SERVICE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	_pure()
	change_scene_to_file("res://Game.tscn")

func _pure() -> void:
	var h := PowertrainHealth.new()
	for i in 60 * 120:  # two minutes of gentle driving: 25 m/s, slip 0.03, normal load
		h.step_tyre(0, 1.0 / 60.0, 25.0, 0.03, 3200.0)
	_check(h.tyre_temp[0] > 60.0 and h.tyre_temp[0] < 100.0, "gentle driving should warm the tyre into its window, got %.0f" % h.tyre_temp[0])
	_check(h.tyre_wear[0] < 0.001, "gentle driving should not wear (%.4f)" % h.tyre_wear[0])
	_check(h.tyre_grip[0] > 0.96, "a warm tyre should grip fully (%.2f)" % h.tyre_grip[0])
	var cold := PowertrainHealth.new()
	cold.step_tyre(0, 1.0 / 60.0, 0.0, 0.0, 3200.0)
	_check(cold.tyre_grip[0] < 0.92, "a cold tyre should grip less (%.2f)" % cold.tyre_grip[0])
	var slide := PowertrainHealth.new()
	var prev_wear := 0.0
	for i in 60 * 300:  # five minutes sliding hard
		slide.step_tyre(0, 1.0 / 60.0, 25.0, 0.3, 4500.0)
		_check(slide.tyre_wear[0] >= prev_wear - 1e-9, "wear must never go down")
		prev_wear = slide.tyre_wear[0]
		_check(slide.tyre_grip[0] >= PowertrainHealth.TYRE_FLOOR - 1e-6, "tyre grip below its floor")
	_check(slide.tyre_temp[0] > PowertrainHealth.WARN_TYRE_C, "hard sliding should overheat the tyre (%.0f)" % slide.tyre_temp[0])
	_check(slide.tyre_wear[0] > 0.2, "hard sliding should wear the tyre (%.3f)" % slide.tyre_wear[0])
	_check(slide.is_warning(PowertrainHealth.Warn.TYRE), "TYRE light expected")
	_check(slide.tyre_grip[0] < 0.95, "an overheated, worn tyre should grip less (%.2f)" % slide.tyre_grip[0])
	var c := PowertrainHealth.new()
	for i in 600:  # a closed clutch, no slip power
		c.step_clutch(1.0 / 60.0, 100.0)
	_check(c.clutch_wear == 0.0, "no slip should not wear the clutch")
	for i in 60 * 120:  # slipping hard for two minutes
		c.step_clutch(1.0 / 60.0, 60000.0)
	_check(c.clutch_wear > 0.9, "slipping should wear the clutch out (%.2f)" % c.clutch_wear)
	_check(c.clutch_cap < 0.7 and c.clutch_cap >= 0.55 - 1e-6, "a worn clutch holds less, within its floor (%.2f)" % c.clutch_cap)
	_check(c.is_warning(PowertrainHealth.Warn.CLUTCH), "CLT light expected")
	slide.repair()
	c.repair()
	_check(slide.tyre_wear[0] == 0.0 and slide.tyre_grip[0] == 1.0 and c.clutch_wear == 0.0 and c.clutch_cap == 1.0, "repair should reset wear")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > 600 and _end("Game never became ready")
	var p: PlayerCar = game.player
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			p.automatic_transmission = false
			p.current_gear = 1
			throttle = 1.0
			_go(Step.BURN)
		Step.BURN:
			p.current_gear = 1
			if waited >= 60 * 10:  # the car is still on the road at 10 s; a long run would crash into the scenery
				var rear_hot: float = maxf(p.health.tyre_temp[2], p.health.tyre_temp[3])
				print("1st gear on the limiter: rear tyre %.0f C, wear %.4f, grip %.3f, speed %.1f" % [rear_hot, maxf(p.health.tyre_wear[2], p.health.tyre_wear[3]), minf(p.health.tyre_grip[2], p.health.tyre_grip[3]), p.current_speed()])
				_check(rear_hot > 50.0, "driving on the limiter in 1st should heat the tyres (%.0f)" % rear_hot)
				_check(is_equal_approx(p.rear_left_wheel.grip_mult, p.health.tyre_grip[2]), "the grip multiplier should reach the wheel")
				_check(p.current_speed() > 1.0, "the car must still move")
				throttle = 0.0
				_go(Step.SERVICE)
		Step.SERVICE:
			if waited == 5:
				p.health.tyre_wear[2] = 0.5
				p.health.clutch_wear = 0.5
				var menu: PauseMenu = null
				for c in game.get_children():
					if c is PauseMenu:
						menu = c
				_check(menu != null, "no pause menu")
				if menu != null:
					menu._service_car()
				_check(p.health.tyre_wear[2] == 0.0 and p.health.clutch_wear == 0.0, "the Service button should reset wear")
				_go(Step.DONE)
				_run_tracks()
	return false

func _run_tracks() -> void:
	var track := TuneTrack.new()
	root.add_child(track)
	await process_frame
	var off := CarSpec.coupe_default()
	off["tyre_load_sensitivity"] = 0.0
	var strong := CarSpec.coupe_default()
	strong["tyre_load_sensitivity"] = 0.3
	var res: Array = await track.evaluate([off, strong])
	print("lateral g: no load sensitivity %.2f, 0.3 -> %.2f; top %.1f / %.1f" % [res[0].peak_lat_g, res[1].peak_lat_g, res[0].top_speed_kmh, res[1].top_speed_kmh])
	_check(res[1].peak_lat_g < res[0].peak_lat_g, "load sensitivity should lower peak cornering grip")
	_check(absf(res[1].top_speed_kmh / res[0].top_speed_kmh - 1.0) < 0.02, "top speed should barely change")
	_end("")

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("tyres: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
