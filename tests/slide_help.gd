extends SceneTree

# Slide-catch help (2026-10-08). Headless and silent; drives through the
# keyboard path (no `driver`), since that is the only path the help is on.
#
# - settings: slide_help round-trips through [assist] and keeps other sections
# - driving straight it adds nothing; holding a key through a steady corner
#   gets (almost) no help, so it never fights ordinary cornering
# - a yaw kick at 25 m/s with no keys held, hard enough that the car spins
#   round without help: with it the slide is caught and the car ends straight
# - with the handbrake held it stands aside
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/slide_help.gd

const TIMEOUT := 90.0
const CFG := "user://slide_help_test.cfg"
const KICK := 4.5    # rad/s of yaw: without help the car spins round

var fails := 0
var game: Node
var t := 0.0
var step := "boot"
var step_t := 0.0
var p: PlayerCar
var quit_in := 0
var samples := {}
var fwd := Vector3.ZERO
var results := {}

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	AudioSettings.path = CFG
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "Master", 0.4)
	cfg.save(CFG)
	AssistSettings.slide_help = false
	AssistSettings.save_settings()
	AssistSettings.slide_help = true
	AssistSettings.load_settings()
	_check(not AssistSettings.slide_help, "slide_help off did not round-trip")
	cfg = ConfigFile.new()
	cfg.load(CFG)
	_check(is_equal_approx(float(cfg.get_value("audio", "Master", 0.0)), 0.4), "saving [assist] lost the audio section")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	AssistSettings.load_settings()
	_check(AssistSettings.slide_help, "slide help should default to on")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _go(s: String) -> void:
	step = s
	step_t = 0.0

func _slip_deg() -> float:
	var b := p.global_transform.basis
	var v := p.linear_velocity
	return rad_to_deg(atan2(v.dot(b.x), v.dot(-b.z)))

func _release_all() -> void:
	for a in ["accelerate", "brake", "handbrake", "steer_left", "steer_right"]:
		Input.action_release(a)

## Puts the car back on the road, pointing down it, at 25 m/s.
func _launch() -> void:
	p.angular_velocity = Vector3.ZERO
	p.global_basis = Basis.looking_at(fwd, Vector3.UP)
	p.linear_velocity = fwd * 25.0

func _physics_process(delta: float) -> bool:
	if quit_in > 0:
		quit_in -= 1
		if quit_in == 0:
			quit(0 if fails == 0 else 1)
		return false
	if game == null:
		return false
	t += delta
	step_t += delta
	if t > TIMEOUT:
		_fail("timed out in step %s" % step)
		_finish()
		return false
	match step:
		"boot":
			p = game.get("player")
			if p == null or step_t < 1.0:
				return false
			p.driver = Callable()
			_release_all()
			p.automatic_transmission = true
			fwd = -p.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			samples.max_amount = 0.0
			_launch()
			_go("straight")
		"straight":
			p.linear_velocity = fwd * 25.0
			samples.max_amount = maxf(samples.max_amount, absf(p.slide_help.amount))
			if step_t > 1.0:
				print("straight at 25 m/s: help %.3f" % samples.max_amount)
				_check(samples.max_amount < 0.001, "driving straight the help should add nothing (%.3f)" % samples.max_amount)
				AssistSettings.slide_help = true
				_go("corner_setup")
		"corner_setup":
			_launch()
			if step_t > 0.3:
				samples.max_amount = 0.0
				Input.action_press("steer_right")
				_go("corner")
		"corner":
			# 1.2 s: the car is ~8 degrees into a steady corner, short of the
			# roadside wall it reaches at ~1.4 s.
			samples.max_amount = maxf(samples.max_amount, absf(p.slide_help.amount))
			if step_t > 1.2:
				Input.action_release("steer_right")
				print("held D 1.2 s into a corner from 25 m/s: help %.3f, turning %.2f rad/s, slip %.1f deg, %.1f m/s" % [samples.max_amount, p.angular_velocity.y, _slip_deg(), p.linear_velocity.length()])
				_check(samples.max_amount < 0.05, "a steady corner should get no help (%.3f)" % samples.max_amount)
				_go("settle_on")
		"settle_on", "settle_off":
			_launch()
			if step_t > 0.3:
				p.angular_velocity = Vector3(0.0, KICK, 0.0)
				samples.peak = 0.0
				samples.help_peak = 0.0
				_go("kick_on" if step == "settle_on" else "kick_off")
		"kick_on", "kick_off":
			samples.peak = maxf(samples.peak, absf(_slip_deg()))
			samples.help_peak = maxf(samples.help_peak, absf(p.slide_help.amount))
			if step_t > 3.0:
				var on := step == "kick_on"
				results[on] = {"peak": samples.peak, "end": absf(_slip_deg()), "help": samples.help_peak, "speed": p.linear_velocity.length()}
				print("yaw kick %.1f rad/s at 25 m/s, help %s: peak slip %.1f deg, after 3 s %.1f deg, help peak %.2f, speed %.1f m/s" % [
					KICK, "on" if on else "off", samples.peak, absf(_slip_deg()), samples.help_peak, p.linear_velocity.length()])
				if on:
					AssistSettings.slide_help = false
					_go("settle_off")
				else:
					AssistSettings.slide_help = true
					var a: Dictionary = results[true]
					var b: Dictionary = results[false]
					_check(a.help > 0.1, "the help should countersteer in a slide (%.2f)" % a.help)
					_check(b.help < 0.001, "switched off it should add nothing (%.2f)" % b.help)
					_check(a.peak < b.peak, "the help should keep the slide smaller (%.1f vs %.1f deg)" % [a.peak, b.peak])
					_check(a.end < 10.0, "with the help the car should end close to straight (%.1f deg)" % a.end)
					_go("settle_hb")
		"settle_hb":
			_launch()
			if step_t > 0.3:
				Input.action_press("handbrake")
				p.angular_velocity = Vector3(0.0, KICK, 0.0)
				samples.help_peak = 0.0
				_go("hb")
		"hb":
			samples.help_peak = maxf(samples.help_peak, absf(p.slide_help.amount))
			if step_t > 0.6:
				Input.action_release("handbrake")
				print("handbrake slide: help peak %.3f" % samples.help_peak)
				_check(samples.help_peak < 0.001, "the help should stand aside with the handbrake held (%.3f)" % samples.help_peak)
				_finish()
	return false

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	_release_all()
	print("slide_help: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	game.queue_free()
	game = null
	quit_in = 30
