extends SceneTree

# Player brake lamps and dash trinket in the real Game.tscn (2026-10-09), headless:
# - the P1 body's tail lamps are off at rest and while driving, light on the
#   brake pedal, stay lit while held, go out on release, and light on the
#   handbrake (shader instance uniform "brake" on the Body)
# - in reverse the tail lens shows the reverse lamp ("reverse" = 1, brake 0),
#   and the brake still wins when pressed
# - the trinket hangs from the mirror, is thrown forward by a hard stop, and
#   follows the pause-menu Trinket selector (and the selector saves)
# Own settings file; the real user://settings.cfg is never touched.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/player_brake_lamps.gd

const CFG := "user://player_brake_lamps_test.cfg"
const TIMEOUT_TICKS := 60 * 60
const SETTLE_TICKS := 30

enum Step { BOOT, DRIVE, BRAKE, HOLD, RELEASE, HANDBRAKE, REVERSE, REVERSE_BRAKE, MENU, DONE }

var step := Step.BOOT
var tick := 0
var step_start := 0
var failures: Array[String] = []
var swing_min := 0.0
var top_speed := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	AudioSettings.path = CFG
	DirAccess.remove_absolute(CFG)
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _go(s: Step) -> void:
	step = s
	step_start = tick

func _lamp(p: PlayerCar, key: String) -> float:
	var mi := p.chassis_visual.get_node(^"Body") as MeshInstance3D
	return float(mi.get_instance_shader_parameter(key))

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	var waited := tick - step_start
	if game == null or game.get("player") == null or game.get("camera") == null:
		return _timeout(waited)
	var p: PlayerCar = game.player
	var trinket: DashTrinket = game.camera.frame.trinket if game.camera.frame != null else null
	match step:
		Step.BOOT:
			if waited > SETTLE_TICKS:
				_check(trinket != null, "cockpit has no trinket")
				_check(p.chassis_visual.get_meta("kind", "") == "p1_coupe", "player is not the P1 coupe")
				_check(_lamp(p, "brake") == 0.0, "lamps should be off at rest")
				Input.action_press("accelerate")
				_go(Step.DRIVE)
		Step.DRIVE:
			top_speed = maxf(top_speed, p.current_speed())
			if p.current_speed() > 12.0 or waited > 60 * 12:
				_check(p.current_speed() > 12.0, "car never got moving (%.1f m/s)" % p.current_speed())
				_check(_lamp(p, "brake") == 0.0, "lamps should be off while driving on the throttle")
				Input.action_release("accelerate")
				Input.action_press("brake")
				_go(Step.BRAKE)
		Step.BRAKE:
			if trinket != null:
				swing_min = minf(swing_min, trinket.psi)
			if waited == 3:
				_check(_lamp(p, "brake") == 1.0, "brake pedal should light the lamps")
			if waited > 60 * 1:
				_go(Step.HOLD)
		Step.HOLD:
			if trinket != null:
				swing_min = minf(swing_min, trinket.psi)
			if waited > 60 * 6 or p.current_speed() < 0.3:
				_check(_lamp(p, "brake") == 1.0, "lamps should stay lit while the pedal is held")
				_check(swing_min < -0.05, "a hard stop should throw the trinket forward, min psi %.3f" % swing_min)
				Input.action_release("brake")
				_go(Step.RELEASE)
		Step.RELEASE:
			if waited == 4:
				_check(_lamp(p, "brake") == 0.0, "lamps should go out when the pedal is released")
				Input.action_press("handbrake")
			if waited == 8:
				_check(_lamp(p, "brake") == 1.0, "handbrake should light the lamps")
				Input.action_release("handbrake")
				_go(Step.HANDBRAKE)
		Step.HANDBRAKE:
			if waited == 4:
				_check(_lamp(p, "brake") == 0.0, "lamps should go out when the handbrake is released")
				Input.action_press("brake")   # hold it still for the reverse toggle
			if waited > 60 * 4 and p.current_speed() < 0.5:
				Input.action_release("brake")
				var ok := p.toggle_reverse()
				_check(ok, "toggle_reverse refused at a standstill")
				_go(Step.REVERSE)
			elif waited > 60 * 20:
				failures.append("never came to a stop for the reverse check (%.1f m/s)" % p.current_speed())
				return _finish()
		Step.REVERSE:
			if waited == 60:
				_check(p.gear == -1, "expected reverse gear, got %d" % p.gear)
				_check(_lamp(p, "reverse") == 1.0, "reverse gear should show the reverse lamp")
				_check(_lamp(p, "brake") == 0.0, "brake lamp should be off in reverse with no pedal")
				Input.action_press("brake")
				_go(Step.REVERSE_BRAKE)
		Step.REVERSE_BRAKE:
			if waited == 4:
				_check(_lamp(p, "brake") == 1.0, "brake should light the lamps in reverse")
				Input.action_release("brake")
				_go(Step.MENU)
		Step.MENU:
			if waited == 2:
				var menu: PauseMenu = null
				for c in game.get_children():
					if c is PauseMenu:
						menu = c
				_check(menu != null and menu.trinket_slider != null, "pause menu has no Trinket selector")
				if menu != null and menu.trinket_slider != null:
					var s := menu.trinket_slider
					_check(is_equal_approx(s.max_value, float(DashTrinket.IDS.size() - 1)) and is_equal_approx(s.step, 1.0),
						"selector should step through every design")
					s.value = float(DashTrinket.index_of("crystal"))
					_check(ViewSettings.dash_trinket == "crystal", "selector should set the setting, got %s" % ViewSettings.dash_trinket)
					var cfg := ConfigFile.new()
					_check(cfg.load(CFG) == OK and cfg.get_value("view", "dash_trinket", "") == "crystal", "selector should save the pick")
					_check(menu.trinket_label.text == DashTrinket.NAMES["crystal"], "label should name the pick")
			if waited == 6:
				_check(trinket.design == "crystal", "cockpit trinket should follow the setting, shows %s" % trinket.design)
				ViewSettings.set_dash_trinket("none")
			if waited == 10:
				_check(not trinket.is_shown(), "none should hide the trinket")
				return _finish()
	return _timeout(waited)

func _timeout(waited: int) -> bool:
	if tick > TIMEOUT_TICKS:
		failures.append("timed out in step %s" % Step.keys()[step])
		return _finish()
	return false

func _finish() -> bool:
	Input.action_release("accelerate")
	Input.action_release("brake")
	Input.action_release("handbrake")
	DirAccess.remove_absolute(CFG)
	print("player_brake_lamps: ", "FAIL" if not failures.is_empty() else "PASS", "  (top speed %.1f m/s, min trinket psi %.2f)" % [top_speed, swing_min])
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return true
