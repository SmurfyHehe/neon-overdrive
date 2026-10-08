extends SceneTree

# Driving-feel pass, impacts (2026-10-08): hit-stop, sparks, camera shake
# slider. Headless and silent; asserts on counters and the simulation, not on
# pixels (headless drops MultiMesh data, so sparks are read from their sim).
#
# - settings: the shake strength and the sparks / hit_stop switches round-trip
#   through settings.cfg and keep the other sections
# - shake slider: at 0 the camera is not moved by shake even at full trauma;
#   at 0.5 the shake is half as big as at 1
# - a light hit (8 m/s) does not freeze
# - a wall at 25 m/s freezes once: Engine.time_scale drops, comes back to 1
#   within a blink of real time, and a burst of sparks flies
# - the same wall with hit_stop off ends close to the same (the shorter steps
#   do not break the car): upright, no runaway speed, similar end speed
# - sliding along a wall at 15 m/s throws a stream of sparks and does not freeze
# - driving free throws no sparks
# - pausing mid-freeze ends the freeze at once
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/driving_feel_impacts.gd

const TIMEOUT := 90.0
const CFG := "user://driving_feel_impacts_test.cfg"

var fails := 0
var game: Node
var t := 0.0
var step := "boot"
var step_t := 0.0
var p: PlayerCar
var crash: CrashAudio
var fx: FxPack
var cam: ChaseCamera
var wall: StaticBody3D
var quit_in := 0
var samples := {}
var min_scale := 1.0
var freeze_real_us := 0
var freeze_start_us := 0
var start_pos := Vector3.ZERO
var fwd := Vector3.ZERO

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	_check_settings()
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

func _hold(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _check_settings() -> void:
	AudioSettings.path = CFG
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "Master", 0.4)
	cfg.save(CFG)
	ViewSettings.set_shake(0.35)
	ViewSettings.save_settings()
	FxSettings.set_on("sparks", false)
	FxSettings.set_on("hit_stop", false)
	FxSettings.save_settings()
	ViewSettings.set_shake(1.0)
	FxSettings.set_on("sparks", true)
	FxSettings.set_on("hit_stop", true)
	ViewSettings.load_settings()
	FxSettings.load_settings()
	_check(absf(ViewSettings.shake - 0.35) < 0.001, "shake did not round-trip (%.2f)" % ViewSettings.shake)
	_check(not FxSettings.is_on("sparks") and not FxSettings.is_on("hit_stop"), "sparks / hit_stop switches did not round-trip")
	cfg = ConfigFile.new()
	cfg.load(CFG)
	_check(is_equal_approx(float(cfg.get_value("audio", "Master", 0.0)), 0.4), "saving view/fx lost the audio section")
	ViewSettings.set_shake(NAN)
	_check(ViewSettings.shake == ViewSettings.SHAKE_DEFAULT, "NaN shake should fall back to the default")
	ViewSettings.set_shake(3.0)
	_check(ViewSettings.shake == 1.0, "shake should clamp to 1")
	# Back to defaults for the drive: the game loads settings from the same
	# (now removed) test file, so it starts on defaults.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	ViewSettings.set_shake(1.0)
	FxSettings.set_on("sparks", true)
	FxSettings.set_on("hit_stop", true)

## A box wall `size` big at `pos`, on the default collision layer.
func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	game.add_child(b)
	b.global_position = pos
	return b

func _flat_fwd() -> Vector3:
	var f := -p.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

## Camera transform offset that _shake adds, at full trauma, for one shake strength.
func _shake_size(strength: float) -> float:
	ViewSettings.set_shake(strength)
	cam.trauma = 1.0
	cam._t = 3.7   # the same noise sample every time
	var before := cam.global_transform
	cam._shake(1.0 / 60.0)
	var after := cam.global_transform
	cam.global_transform = before
	return (after.origin - before.origin).length() + (after.basis.z - before.basis.z).length()

func _process(delta: float) -> bool:
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
	min_scale = minf(min_scale, Engine.time_scale)
	if Engine.time_scale < 1.0 and freeze_start_us == 0:
		freeze_start_us = Time.get_ticks_usec()
	elif Engine.time_scale >= 1.0 and freeze_start_us != 0:
		freeze_real_us = maxi(freeze_real_us, Time.get_ticks_usec() - freeze_start_us)
		freeze_start_us = 0
	match step:
		"boot":
			p = game.get("player")
			if p == null or step_t < 0.5:
				return false
			p.driver = _hold
			for c in p.get_children():
				if c is CrashAudio: crash = c
			fx = game.get("fx")
			cam = game.get("camera")
			_check(crash != null and fx != null and fx.sparks != null and fx.hit_stop != null, "sparks / hit-stop not built")
			if fails > 0:
				_finish()
				return false
			# Shake slider.
			var full := _shake_size(1.0)
			var half := _shake_size(0.5)
			var none := _shake_size(0.0)
			print("shake at full trauma: strength 1 %.4f, 0.5 %.4f, 0 %.4f" % [full, half, none])
			_check(full > 0.01, "full shake should move the camera (%.4f)" % full)
			_check(none < 0.00001, "shake 0 should leave the camera still (%.5f)" % none)
			_check(absf(half / full - 0.5) < 0.1, "shake 0.5 should be about half (%.2f)" % (half / full))
			ViewSettings.set_shake(1.0)
			cam.trauma = 0.0
			_go("free_drive")
		"free_drive":
			p.linear_velocity = _flat_fwd() * 15.0
			if step_t > 1.5:
				print("driving free: %d sparks" % fx.sparks.spawned)
				_check(fx.sparks.spawned == 0, "driving on the road should throw no sparks (%d)" % fx.sparks.spawned)
				_go("light_hit")
		"light_hit":
			# Direct call: a hit under the big tier never freezes.
			var before := fx.hit_stop.freeze_count
			fx.hit_stop.trigger(8.0)
			_check(fx.hit_stop.freeze_count == before and Engine.time_scale == 1.0, "an 8 m/s hit should not freeze")
			_go("settle")
		"settle":
			_hold(p)
			if step_t > 1.5:
				_crash_setup(true)
		"crash_freeze":
			if step_t > 3.0:
				samples.freeze_end = _end_state()
				print("wall at 25 m/s, freeze on: %d freeze(s), lowest time scale %.2f, longest %.0f ms real, %d sparks; after: %s" % [
					fx.hit_stop.freeze_count - samples.freezes, min_scale, freeze_real_us / 1000.0, fx.sparks.spawned - samples.sparks, samples.freeze_end])
				_check(fx.hit_stop.freeze_count - samples.freezes == 1, "a 25 m/s wall hit should freeze once (%d)" % (fx.hit_stop.freeze_count - samples.freezes))
				_check(min_scale <= HitStop.SCALE + 0.001, "the freeze should slow the world (lowest %.2f)" % min_scale)
				_check(Engine.time_scale == 1.0, "time scale should be back to 1")
				_check(freeze_real_us > 0 and freeze_real_us < 300000, "the freeze should be a blink (%.0f ms)" % (freeze_real_us / 1000.0))
				_check(fx.sparks.spawned - samples.sparks >= 8, "a 25 m/s wall hit should throw a burst of sparks (%d)" % (fx.sparks.spawned - samples.sparks))
				wall.queue_free()
				_go("settle2")
		"settle2":
			_hold(p)
			if step_t > 1.5:
				_crash_setup(false)
		"crash_nofreeze":
			if step_t > 3.0:
				var a: Dictionary = samples.freeze_end
				var b := _end_state()
				print("wall at 25 m/s, freeze off: %s" % b)
				_check(fx.hit_stop.freeze_count == samples.freezes, "hit_stop off should not freeze")
				for s in [a, b]:
					_check(s.up > 0.8, "the car should stay upright after the wall (%.2f)" % s.up)
					_check(s.speed < 8.0, "the car should not fly off after the wall (%.1f m/s)" % s.speed)
				_check(absf(a.speed - b.speed) < 3.0, "freeze on/off end speeds differ too much (%.1f vs %.1f)" % [a.speed, b.speed])
				_check(absf(a.travel - b.travel) < 2.0, "freeze on/off end positions differ too much (%.1f vs %.1f m)" % [a.travel, b.travel])
				wall.queue_free()
				FxSettings.set_on("hit_stop", true)
				fx.apply_settings()
				_go("scrape_setup")
		"scrape_setup":
			_hold(p)
			if step_t > 1.5:
				fwd = _flat_fwd()
				var right := fwd.cross(Vector3.UP)
				var bb := p.chassis_visual.get_meta("half_w", 0.9) as float
				wall = _wall(p.global_position + right * (bb + 0.55) + fwd * 30.0 + Vector3(0.0, 1.0, 0.0), Vector3(0.6, 3.0, 90.0))
				wall.look_at(wall.global_position + fwd, Vector3.UP)
				samples.right = right
				samples.sparks = fx.sparks.spawned
				samples.freezes = fx.hit_stop.freeze_count
				samples.live = 0
				_go("scrape")
		"scrape":
			# Steer in until the body touches, then lean on the wall lightly
			# (forcing 2 m/s into it every tick would be a fresh hit each tick).
			p.linear_velocity = fwd * 15.0 + samples.right * (0.4 if crash.scraping_contact() else 2.0)
			samples.live = maxi(samples.live, fx.sparks.live_count)
			if step_t > 1.5:
				var n: int = fx.sparks.spawned - samples.sparks
				print("scrape along a wall at 15 m/s: %d sparks, up to %d alive" % [n, samples.live])
				_check(n > 20, "sliding along a wall should throw a stream of sparks (%d)" % n)
				_check(samples.live > 5, "sparks should be alive while scraping (%d)" % samples.live)
				_check(fx.hit_stop.freeze_count == samples.freezes, "a scrape should not freeze")
				wall.queue_free()
				_go("pause_release")
		"pause_release":
			if step_t > 1.0:
				fx.hit_stop.trigger(25.0)
				_check(Engine.time_scale < 1.0, "a direct big hit should freeze")
				paused = true
				_go("paused")
		"paused":
			# delta is real here; process keeps running for ALWAYS nodes
			if step_t > 0.0:
				_check(Engine.time_scale == 1.0, "pausing should end the freeze (%.2f)" % Engine.time_scale)
				paused = false
				_finish()
	return false

func _crash_setup(freeze: bool) -> void:
	FxSettings.set_on("hit_stop", freeze)
	fx.apply_settings()
	fwd = _flat_fwd()
	start_pos = p.global_position
	var at := p.global_position + fwd * 14.0
	wall = _wall(at + Vector3(0.0, 1.0, 0.0), Vector3(12.0, 3.0, 1.0))
	wall.look_at(wall.global_position + fwd, Vector3.UP)
	p.linear_velocity = fwd * 25.0
	samples.freezes = fx.hit_stop.freeze_count
	samples.sparks = fx.sparks.spawned
	min_scale = 1.0
	freeze_real_us = 0
	_go("crash_freeze" if freeze else "crash_nofreeze")

func _end_state() -> Dictionary:
	return {"speed": snappedf(p.linear_velocity.length(), 0.01), "up": snappedf(p.global_transform.basis.y.y, 0.01),
		"travel": snappedf((p.global_position - start_pos).dot(fwd), 0.01)}

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	Engine.time_scale = 1.0
	print("driving_feel_impacts: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	game.queue_free()
	game = null
	quit_in = 30
