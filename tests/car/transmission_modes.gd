extends SceneTree

# Transmission modes (2026-10-06), headless and silent, driven by direct calls
# and a scripted driver (no key events):
# - "toggle_gearbox" (G) is bound and cycles AUTO -> SEMI -> MANUAL -> AUTO, and
#   the HUD letter follows (A / S / M); the old V clutch-model key is gone
# - SEMI: Q/E shift with no clutch pedal, the engine never stalls, and the car
#   pulls up through the gears to over 100 km/h
# - MANUAL: a shift with the clutch out is refused; with the clutch in it goes
#   through; the realistic clutch model (stall, starter) is on
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/transmission_modes.gd

const TIMEOUT_TICKS := 60 * 60

enum Step { BOOT, SEMI_DRIVE, MANUAL_STOP, MANUAL_NO_CLUTCH, MANUAL_CLUTCH, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var clutch := 0.0
var semi_top_gear := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.clutch_input = clutch
	c.steering_input = 0.0

func _cycle(p: PlayerCar) -> void:
	# What _read_keyboard does on G.
	p.set_transmission_mode((p.transmission_mode() + 1) % PlayerCar.Transmission.size())

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("game_state") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %d" % step)
	var p: PlayerCar = game.player
	var hud: Hud = null
	for c in game.get_children():
		if c is Hud:
			hud = c
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(InputMap.has_action("toggle_gearbox"), "no 'toggle_gearbox' action")
			_check(not InputMap.has_action("toggle_clutch_model"), "the old V clutch-model action should be gone")
			_check(p.transmission_mode() == PlayerCar.Transmission.AUTO, "the car should start in AUTO")
			var seen := []
			for i in 3:
				hud._refresh()
				seen.append(hud.lbl_mode.text)
				_cycle(p)
			_check(seen == ["A", "S", "M"], "G should cycle A, S, M on the HUD, got %s" % str(seen))
			_check(p.transmission_mode() == PlayerCar.Transmission.AUTO, "a third G should come back to AUTO")
			_cycle(p)  # SEMI
			_check(not p.automatic_transmission and not p.realistic_clutch, "SEMI: manual box, auto clutch")
			throttle = 1.0
			_go(Step.SEMI_DRIVE)
		Step.SEMI_DRIVE:
			if p.current_gear == 0 and not p.is_shifting:
				p.manual_shift(1)  # into first
			elif p.motor_rpm > p.max_rpm * 0.9 and p.current_gear < p.gear_ratios.size():
				p.manual_shift(1)
			semi_top_gear = maxi(semi_top_gear, p.current_gear)
			_check(p.engine_running, "SEMI: the engine stalled")
			if Hud.kmh(p.current_speed()) >= 100 or waited > 60 * 20:
				_check(Hud.kmh(p.current_speed()) >= 100, "SEMI: only reached %d km/h in 20 s" % Hud.kmh(p.current_speed()))
				_check(semi_top_gear >= 3, "SEMI: only got to gear %d" % semi_top_gear)
				throttle = 0.0
				_go(Step.MANUAL_STOP)
		Step.MANUAL_STOP:
			if waited == 1:
				_cycle(p)  # MANUAL
				_check(not p.automatic_transmission and p.realistic_clutch, "MANUAL: manual box and the realistic clutch")
				clutch = 1.0  # keep it from stalling while it brakes
				brake = 1.0
			if p.current_speed() < 0.5 and waited > 30:
				brake = 0.0
				clutch = 0.0
				_go(Step.MANUAL_NO_CLUTCH)
		Step.MANUAL_NO_CLUTCH:
			if waited == 30:
				var g := p.current_gear
				p.manual_shift(-1)
				_check(not p.is_shifting and p.current_gear == g, "MANUAL: a shift with the clutch out should be refused")
				_check(not p.toggle_reverse(), "MANUAL: reverse with the clutch out should be refused")
				p.set_transmission_mode(PlayerCar.Transmission.MANUAL)  # a stall above is fine; start clean
				clutch = 1.0
				_go(Step.MANUAL_CLUTCH)
		Step.MANUAL_CLUTCH:
			if waited == 30:
				var g := p.current_gear
				p.manual_shift(-1)
				_check(p.is_shifting or p.current_gear != g, "MANUAL: a shift with the clutch in should go through")
				_go(Step.DONE)
		Step.DONE:
			return _end("")
	return false

func _go(s: int) -> void:
	step = s
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	print("transmission_modes: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	for f in failures:
		print("  ", f)
	quit(0 if failures.is_empty() else 1)
	return true
