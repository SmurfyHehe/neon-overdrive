extends SceneTree

# Engine start and stop test (2026-10-09, Roy), headless:
# - the "engine sound missing until you pause and resume" bug: pausing mutes the
#   Engine and Music buses, a restart from the pause menu reloads the scene with
#   the buses still muted, and nothing unmuted them. After a restart both must
#   follow the new run's state (unmuted).
# - X switches the engine off: the synth goes silent, the throttle does nothing,
#   the revs run down, fuel stops burning.
# - X again starts it: the starter is heard quietly while the engine turns over,
#   the needle rises, the camera gets a kick, then it catches (full volume, flare
#   to idle) and the throttle works again.
# - a stalled engine (manual gearbox) restarts with the same key.
# - the Ignition state machine alone: a press while cranking does nothing, and an
#   empty tank gives up instead of catching.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/engine_start_stop.gd

const TIMEOUT := 90.0

var fails := 0
var t := 0.0
var step := "boot"
var step_t := 0.0
var game: Node
var p: PlayerCar
var audio: EngineAudio
var old_scene_id := 0
var held_ticks := 0
var vals := {}

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	change_scene_to_file("res://Game.tscn")

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _go(s: String) -> void:
	step = s
	step_t = 0.0

func _engine_bus(muted: bool) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Engine")) == muted

func _key_x(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_X
	ev.physical_keycode = KEY_X
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _bind() -> bool:
	game = current_scene
	if game == null or game.get("player") == null or game.get("game_state") == null:
		return false
	p = game.player
	audio = null
	for c in p.get_children():
		if c is EngineAudio:
			audio = c
	return audio != null

func _process(delta: float) -> bool:
	t += delta
	step_t += delta
	if t > TIMEOUT:
		_fail("timed out in step " + step)
		return _end()
	match step:
		"boot":
			if _bind() and step_t > 0.5:
				_check(_engine_bus(false), "the Engine bus should be unmuted on a fresh start")
				game.game_state.pause()
				_check(_engine_bus(true), "pausing should mute the Engine bus")
				old_scene_id = game.get_instance_id()
				game.game_state.restart()
				_go("restarted")
		"restarted":
			# The reload happens at the end of the frame; wait for the new scene.
			if current_scene != null and current_scene.get_instance_id() != old_scene_id and _bind():
				_check(_engine_bus(false), "BUG: after a restart from pause the Engine bus is still muted (no engine sound until pause/resume)")
				var music := AudioServer.get_bus_index(&"Music")
				if music >= 0:
					_check(not AudioServer.is_bus_mute(music), "BUG: after a restart from pause the Music bus is still muted")
				_go("idle")
		"idle":
			if step_t > 1.5:
				_check(p.engine_running and p.ignition.is_running(), "the car should start with the engine running")
				_check(audio.synth.volume > 0.4, "the engine should be audible at idle, volume %.2f" % audio.synth.volume)
				vals["idle"] = p.idle_rpm
				_check(p.motor_rpm > p.idle_rpm * 0.8, "idle rpm should be near idle, %d" % int(p.motor_rpm))
				Input.action_press("accelerate")   # held for the whole off/on test: the car must ignore it while off
				_go("press_off")
		"press_off":
			if step_t > 0.3:
				Input.action_release("accelerate")
				_key_x(true)
				held_ticks = 0
				_go("holding_off")
		"holding_off":
			held_ticks += 1
			if held_ticks >= 3:
				_key_x(false)
				Input.action_press("accelerate")
				_go("off")
		"off":
			if step_t > 0.4:
				_check(not p.engine_running, "X should switch the engine off")
				_check(p.ignition.state == Ignition.State.OFF, "ignition state should be OFF")
				_check(audio.synth.volume == 0.0, "an engine that is off should be silent, volume %.2f" % audio.synth.volume)
				_check(p.throttle_input == 0.0, "the throttle should be ignored while off, got %.2f" % p.throttle_input)
				vals["fuel"] = p.fuel.litres
			if step_t > 6.0:
				Input.action_release("accelerate")
				_check(p.current_speed() < 1.0, "full throttle with the engine off should not move the car, %.1f m/s" % p.current_speed())
				_check(p.motor_rpm < vals.idle * 0.2, "the revs should run down with the engine off, %d rpm" % int(p.motor_rpm))
				_check(is_equal_approx(p.fuel.litres, vals.fuel), "no fuel burns with the engine off")
				_key_x(true)
				held_ticks = 0
				_go("holding_on")
		"holding_on":
			held_ticks += 1
			if held_ticks >= 3:
				_key_x(false)
				vals["peak_rpm"] = 0.0
				vals["crank_vol"] = -1.0
				vals["shake"] = 0.0
				_go("cranking")
		"cranking":
			# Mid-crank: the starter is heard, quietly, and the needle is rising.
			vals.peak_rpm = maxf(vals.peak_rpm, p.motor_rpm)
			if p.ignition.is_cranking():
				vals.crank_vol = audio.synth.volume
			if step_t > 0.4 and not vals.has("mid"):
				vals["mid"] = true
				_check(p.ignition.is_cranking(), "X from off should start the starter")
				_check(not p.engine_running, "the engine should not run while the starter turns it over")
			if step_t > Ignition.CRANK_SECS + 1.2:
				_check(vals.crank_vol > 0.0 and vals.crank_vol < 0.5 * 0.9, "the starter should be heard quietly, volume %.2f" % vals.crank_vol)
				_check(vals.peak_rpm > 100.0, "the needle should rise while cranking, peak %d rpm" % int(vals.peak_rpm))
				_check(p.engine_running and p.ignition.is_running(), "the engine should catch after the crank")
				_check(audio.synth.volume > 0.4, "a running engine is audible again, volume %.2f" % audio.synth.volume)
				_check(p.motor_rpm > vals.idle * 0.8, "the engine should settle at idle after catching, %d rpm" % int(p.motor_rpm))
				_check(p.idle_rpm == vals.idle, "idle_rpm should be restored, %d" % int(p.idle_rpm))
				Input.action_press("accelerate")
				_go("drive")
		"drive":
			if step_t > 4.0:
				_check(p.current_speed() > 2.0, "the throttle should work again after the start, %.1f m/s" % p.current_speed())
				Input.action_release("accelerate")
				p.set_transmission_mode(PlayerCar.Transmission.MANUAL)
				p.engine_running = false   # a stall
				_key_x(true)
				held_ticks = 0
				_go("holding_stall")
		"holding_stall":
			held_ticks += 1
			if held_ticks >= 3:
				_key_x(false)
				_go("stall_restart")
		"stall_restart":
			if step_t > Ignition.CRANK_SECS + 1.0:
				_check(p.engine_running, "a stalled manual-gearbox engine should restart with X")
				_check(p.idle_rpm == vals.idle, "idle_rpm should be unchanged after a stall restart")
				_unit()
				return _end()
	return false

func _unit() -> void:
	var ig := Ignition.new()
	_check(ig.state == Ignition.State.RUN, "a new Ignition runs")
	ig.toggle()
	_check(ig.state == Ignition.State.OFF, "X while running switches off")
	ig.toggle()
	_check(ig.is_cranking(), "X while off starts the starter")
	ig.toggle()
	_check(ig.is_cranking(), "X while cranking does nothing")
	_check(not ig.step(0.1, true), "the engine does not catch before the crank is over")
	_check(ig.take_shake() >= Ignition.SHAKE_CRANK, "starting the starter kicks the camera")
	_check(ig.take_shake() == 0.0, "the kick is taken once")
	_check(ig.step(Ignition.CRANK_SECS, true) and ig.is_running(), "the engine catches at the end of the crank")
	_check(ig.take_shake() >= Ignition.SHAKE_CATCH, "catching kicks the camera")
	ig.toggle()
	ig.toggle()
	_check(not ig.step(Ignition.CRANK_SECS + 0.1, false) and ig.state == Ignition.State.OFF, "an empty tank gives up instead of catching")
	ig.sync_running(true)
	_check(ig.is_running(), "an engine started elsewhere syncs to RUN")

func _end() -> bool:
	print("engine_start_stop: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
	return true
