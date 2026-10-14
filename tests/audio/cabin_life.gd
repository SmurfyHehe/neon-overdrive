extends SceneTree

# Cabin life test (more-alive MA1, 2026-10-11). Silent and headless: it checks
# the logic and the schedule, never the sound itself.
#
# Part 1, scripted (CabinLifeAudio.step(), no car):
# - key-off after a hot run schedules metal ticks that thin out and stop
#   inside 45 s, with the fan running on 3-8 s; a short cold run ticks for a
#   shorter time than a long hot one
# - starting the engine again stops the ticks and the fan at once
# - a 0.8 g stop rolls the can once; a second stop 5 s later does not; one
#   after 20 s (and after it has rolled back) does; cornering at 0.8 g rolls it;
#   a gentle 0.4 g stop does nothing
# - rough road makes coin bursts, capped; smooth road makes none; nothing
#   starts while a can is sounding (one cabin sound at a time)
# - a front hit above the crash audio's big-hit level sets the glovebox open and
#   latches; a side hit or a small one does not; reset_cabin() shuts it
# Part 2, on the real Game.tscn player:
# - the car has a CabinLifeAudio under its CarAudio
# - X (key_off) starts the cooling, starting the engine ends it
# - driving at 20 m/s into a wall opens the glovebox through CrashAudio
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/cabin_life.gd

const DT := 1.0 / 60.0
const TIMEOUT := 120.0
const G := 9.81

var fails := 0
var game: Node
var p: PlayerCar
var cabin: CabinLifeAudio
var t := 0.0
var step := "boot"
var step_t := 0.0
var quit_in := 0
var wall: StaticBody3D
var scripted_done := false

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _fresh() -> CabinLifeAudio:
	var c := CabinLifeAudio.new()
	var holder := Node.new()
	root.add_child(holder)
	holder.add_child(c)
	return c

func _run(c: CabinLifeAudio, seconds: float, running: bool, throttle := 0.0, rpm := 0.0, accel := Vector3.ZERO, rough := 0.0, speed := 0.0) -> void:
	for i in int(seconds / DT):
		c.step(DT, running, throttle, rpm, accel, rough, speed)

func _stop(c: CabinLifeAudio, g: float) -> void:
	# half a second of braking at g (braking while going forward is +z), then calm
	_run(c, 0.5, true, 0.0, 0.2, Vector3(0.0, 0.0, g * G), 0.0, 10.0)

func _scripted() -> void:
	# --- cooling
	var c := _fresh()
	_run(c, 150.0, true, 0.8, 0.6)
	_check(c.heat > 0.4, "a hot run should read hot, got heat %.2f" % c.heat)
	_check(not c.cooling, "ticks before the engine went off")
	_run(c, 0.1, false)
	_check(c.cooling, "key-off did not start the cooling")
	_check(c.cool_length >= CabinLifeAudio.COOL_MIN_S and c.cool_length <= CabinLifeAudio.COOL_MAX_S, "run length %.1f s out of range" % c.cool_length)
	_check(c.fan_left >= CabinLifeAudio.FAN_MIN_S - 0.2 and c.fan_left <= CabinLifeAudio.FAN_MAX_S, "fan %.1f s out of 3-8" % c.fan_left)
	var hot_len := c.cool_length
	_run(c, 46.0, false)
	_check(not c.cooling, "still cooling after 46 s")
	var third := c.cool_length / 3.0
	var early := 0
	var late := 0
	var last := 0.0
	for a in c.tick_log:
		last = maxf(last, a)
		if a < third:
			early += 1
		elif a >= 2.0 * third:
			late += 1
	print("hot run: heat->%.2f, %.0f s, %d ticks (%d early, %d late), last at %.1f s, fan on for %.1f s" % [c.heat, hot_len, c.tick_count, early, late, last, c.fan_left])
	_check(c.tick_count >= 8, "a hot engine should tick a good few times, got %d" % c.tick_count)
	_check(early > late, "ticks should thin out: %d early vs %d late" % [early, late])
	_check(last < 45.0, "a tick at %.1f s, past 45 s" % last)
	_check(c.fan_left == 0.0, "the fan never ran down")
	# a short cold run
	var cold := _fresh()
	_run(cold, 5.0, true, 0.0, 0.15)
	_run(cold, 0.1, false)
	_check(cold.cooling and cold.cool_length < hot_len, "a cold engine should tick for less time (%.1f vs %.1f)" % [cold.cool_length, hot_len])
	# restart stops it at once
	var r := _fresh()
	_run(r, 90.0, true, 0.7, 0.5)
	_run(r, 6.0, false)
	var n0 := r.tick_count
	_check(r.cooling, "restart test: not cooling after 6 s")
	_run(r, 0.05, true, 0.0, 0.15)
	_check(not r.cooling and r.fan_left == 0.0, "restart did not stop the cooling")
	_run(r, 10.0, true, 0.0, 0.15)
	_check(r.tick_count == n0, "ticks went on after the engine restarted")
	# --- the can
	var k := _fresh()
	_run(k, 2.0, true)
	_stop(k, 0.4)
	_run(k, 2.0, true)
	_check(k.can_clunks == 0, "a 0.4 g stop should not roll the can")
	_stop(k, 0.8)
	_check(k.can_clunks == 1 and k.last_event == "can", "a 0.8 g stop should roll the can once, got %d" % k.can_clunks)
	# one cabin sound at a time: coins wait while the can is sounding
	_run(k, 0.3, true, 0.0, 0.2, Vector3.ZERO, 1.0, 20.0)
	_check(k.busy() or k.coin_bursts == 0, "coins started under the can")
	_check(k.coin_bursts == 0, "coins played while the can was sounding")
	_run(k, 2.0, true)   # rolled back
	_check(not k.can_forward, "the can did not roll back under 0.3 g")
	_stop(k, 0.8)
	_check(k.can_clunks == 1, "a second stop inside 20 s rolled it again")
	_run(k, 20.0, true)
	_stop(k, 0.8)
	_check(k.can_clunks == 2, "a stop after 20 s should roll it, got %d" % k.can_clunks)
	_run(k, 21.0, true)
	_run(k, 0.5, true, 0.0, 0.2, Vector3(0.8 * G, 0.0, 0.0), 0.0, 15.0)
	_check(k.can_clunks == 3, "cornering at 0.8 g should roll it, got %d" % k.can_clunks)
	# no rolling back means no second roll even after the cooldown
	var hold := _fresh()
	_run(hold, 1.0, true)
	_run(hold, 0.5, true, 0.0, 0.2, Vector3(0.0, 0.0, 0.8 * G), 0.0, 10.0)
	_run(hold, 25.0, true, 0.0, 0.2, Vector3(0.0, 0.0, 0.5 * G), 0.0, 10.0)   # never calm
	_check(hold.can_clunks == 1, "it rolled again without rolling back")
	# --- coins
	var coin := _fresh()
	_run(coin, 10.0, true, 0.3, 0.3, Vector3.ZERO, 0.0, 15.0)
	_check(coin.coin_bursts == 0, "coins on smooth road")
	_run(coin, 10.0, true, 0.3, 0.3, Vector3.ZERO, 0.6, 15.0)
	print("coins: %d bursts in 10 s of rough road" % coin.coin_bursts)
	_check(coin.coin_bursts >= 2, "coins did not chatter on rough road")
	_check(coin.coin_bursts <= int(10.0 / CabinLifeAudio.COIN_GAP) + 1, "coins are not capped: %d" % coin.coin_bursts)
	# --- the glovebox
	var gb := _fresh()
	gb.hit(3.0, true)
	gb.hit(12.0, false)
	_check(not gb.glovebox_open, "a small or a side hit opened the glovebox")
	gb.hit(CrashAudio.CRUNCH_DV + 2.0, true)
	_check(gb.glovebox_open and gb.latch_count == 1 and gb.last_event == "latch", "a big front hit should open it")
	_run(gb, 5.0, true)
	_check(gb.glovebox_open, "the glovebox shut by itself")
	gb.reset_cabin()
	_check(not gb.glovebox_open, "reset_cabin did not shut it")
	print("scripted: ticks %d, can %d, coins %d, latch %d" % [c.tick_count, k.can_clunks, coin.coin_bursts, gb.latch_count])

func _process(delta: float) -> bool:
	if quit_in > 0:
		quit_in -= 1
		if quit_in == 0:
			quit(0 if fails == 0 else 1)
		return false
	if game == null:
		return false
	if not scripted_done:
		scripted_done = true   # the nodes are ready only once the tree has run a frame
		_scripted()
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
			p.driver = _hold
			cabin = CabinLifeAudio.of(p)
			_check(cabin != null, "the player has no CabinLifeAudio under its CarAudio")
			if cabin == null:
				_finish()
				return false
			p.engine_running = true
			p.motor_rpm = p.idle_rpm
			_go("running")
		"running":
			if step_t > 1.0:
				_check(not cabin.cooling, "cooling while the engine ran")
				var off := p.key_off()
				_check(off, "key_off refused at rest")
				_go("off")
		"off":
			if step_t > 3.0:
				print("real car: engine off, cooling %s, %d tick(s), fan %.1f s left" % [cabin.cooling, cabin.tick_count, cabin.fan_left])
				_check(cabin.cooling, "X did not start the cooling on the real car")
				p.ignition_on()
				p.engine_running = true
				_go("restarted")
		"restarted":
			if step_t > 0.3:
				_check(not cabin.cooling, "the engine restarted but the ticks went on")
				cabin.reset_cabin()
				_go("wall")
		"wall":
			if not wall:
				var fwd := _fwd()
				wall = StaticBody3D.new()
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(12.0, 3.0, 1.0)
				cs.shape = box
				wall.add_child(cs)
				game.add_child(wall)
				wall.global_position = p.global_position + fwd * 14.0 + Vector3(0.0, 1.0, 0.0)
				wall.look_at(wall.global_position + fwd, Vector3.UP)
				p.linear_velocity = fwd * 20.0
			if step_t > 2.5:
				print("real car: wall at 20 m/s -> glovebox_open=%s, latch %d" % [cabin.glovebox_open, cabin.latch_count])
				_check(cabin.glovebox_open, "a 20 m/s front hit did not open the glovebox")
				wall.queue_free()
				_finish()
	return false

func _go(s: String) -> void:
	step = s
	step_t = 0.0

func _hold(c: Vehicle) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _fwd() -> Vector3:
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized()

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	print("cabin_life: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	game.queue_free()
	game = null
	quit_in = 3
