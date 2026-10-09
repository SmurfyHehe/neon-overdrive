extends SceneTree

# Sound fixes test (2026-10-08, sound research 1b and 9), headless and silent:
# it asserts on levels, counts and filter cutoffs, never on sound. The listen
# pack (tests/audio/sound_listen_pack.gd) is how the sound itself gets judged.
#
# - window: holding the window key rolls it down over ~2.5 s, a tap rolls it
#   back up; in the cockpit the bus cutoffs open as it goes down (closed =
#   the old cockpit cutoffs, open = most of the way to outside), and the chase
#   view ignores it
# - wind in the cabin: window closed is quieter than open; the throb is
#   loudest cracked, gone closed and fully open; the seal whistle only with the
#   window up at speed; the mirror whistle only above ~140 km/h
# - tyres: each kind fed on one side plays on that side's player only
# - shifts: up and down shifts count separately; the thump and clack players
#   hold five random variants, and so does the chirp; every continuous wind and
#   road layer and the scrape run as two takes of different lengths
# - crashes: driving into a wall at 25 m/s is one hit of crunch size or more;
#   a reset that zeroes the velocity in the air is not a hit; sliding along a
#   wall scrapes
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/sound_fixes.gd

const TIMEOUT := 120.0  # a cold user://audio_cache rebuilds the car sounds at boot (~10 s)

var fails := 0
var game: Node
var t := 0.0
var step := "boot"
var step_t := 0.0
var p: PlayerCar
var car: CarAudio
var crash: CrashAudio
var drive: DrivelineAudio
var persp: PerspectiveAudio
var wall: StaticBody3D
var scrape_peak := 0.0
var biggest_hit := ""
var biggest_dv := 0.0
var quit_in := 0
var samples := {}
var key_down := false

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
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
	match step:
		"boot":
			p = game.get("player")
			if p == null or step_t < 0.5:
				return false
			p.driver = _hold
			for c in p.get_children():
				if c is CarAudio: car = c
				if c is CrashAudio: crash = c
				if c is DrivelineAudio: drive = c
			persp = (game.get("camera") as ChaseCamera).perspective
			_check(car != null and crash != null and drive != null, "the player is missing a sound node")
			_check(persp != null and persp.car_audio == car, "PerspectiveAudio is not feeding the car's CarAudio")
			if fails > 0:
				_finish()
				return false
			_check_variants()
			# Window, chase view first: the key moves the window, the sound ignores it.
			persp.set_cockpit(false)
			_go("window_chase")
		"window_chase":
			# through the real key path: the camera polls the action every tick
			if step_t < 1.0:
				Input.action_press("window")
			else:
				_check(absf(persp.cutoff(&"Engine") - PerspectiveAudio.OPEN_HZ) < 1.0, "the chase view should ignore the window")
				Input.action_release("window")  # released after 1 s: not a tap, it stays down
				_check(persp.window > 0.3, "holding the window key 1 s should open it (%.2f)" % persp.window)
				_go("window_tap")
		"window_tap":
			# a tap: two ticks down, then up
			# released for a moment first, so the camera sees the long hold end
			if step_t > 0.2 and step_t < 0.3:
				Input.action_press("window")
			else:
				Input.action_release("window")
			if step_t >= 1.5:
				_check(persp.window == 0.0, "a tap should roll the window all the way up (%.2f)" % persp.window)
				persp.set_cockpit(true)
				_go("cabin")
		"cabin":
			# In the cockpit at 35 m/s: sample the wind at closed, cracked and open.
			car.forced = {"speed": 35.0, "on_road": 1.0}
			var marks := {"closed": 0.0, "cracked": 0.2, "open": 1.0}
			var i := int(step_t / 1.2)
			var names := marks.keys()
			if i >= names.size():
				_report_cabin()
				_go("whistle")
				return false
			persp.window = marks[names[i]]
			if fmod(step_t, 1.2) > 1.0 and not samples.has(names[i]):
				samples[names[i]] = {
					"cutoff": persp.cutoff(&"Engine"),
					"buffet": db_to_linear(car.get_node("BuffetAudio").volume_db),
					"throb": car.throb_level,
					"whistle": car.whistle_level,
				}
		"whistle":
			persp.window = 0.0
			persp.set_cockpit(false)
			car.forced = {"speed": 60.0 if samples.has("w20") else 20.0, "on_road": 1.0}
			if step_t > 1.0 and not samples.has("w20"):
				samples.w20 = car.whistle_level
			if step_t > 2.0:
				print("mirror whistle: %.2f at 20 m/s, %.2f at 60 m/s" % [samples.w20, car.whistle_level])
				_check(samples.w20 < 0.01, "no mirror whistle at 20 m/s (%.2f)" % samples.w20)
				_check(car.whistle_level > 0.5, "the mirror whistle should be up at 60 m/s (%.2f)" % car.whistle_level)
				_go("tyre_sides")
		"tyre_sides":
			car.forced = {"speed": 20.0, "on_road": 1.0, "squeal_l": 1.0, "lock_r": 1.0}
			if step_t > 1.0:
				var lv := [car.tyre.squeal[0], car.tyre.squeal[1], car.tyre.lock[0], car.tyre.lock[1], car.tyre.scrub[0], car.tyre.spin[1]]
				print("tyres, squeal left + lock right: squeal L %.2f R %.2f, lock L %.2f R %.2f, scrub L %.2f, spin R %.2f" % lv)
				_check(lv[0] > 0.9 and lv[1] < 0.01, "a left squeal should play on the left only")
				_check(lv[3] > 0.9 and lv[2] < 0.01, "a right lock-up should play on the right only")
				_check(lv[4] < 0.01 and lv[5] < 0.01, "kinds not fed should stay silent")
				_check(car.get_node("SquealLAudio").volume_db > -20.0 and car.get_node("SquealRAudio").volume_db <= -79.0, "the squeal players don't follow their side")
				car.forced = {"speed": 0.0, "spin_l": 1.0, "spin_r": 1.0}
				_go("chirp")
		"chirp":
			if step_t > 0.3:
				_check(car.chirp_count >= 1, "wheelspin snapping on should chirp")
				car.forced = {}
				_go("shift")
		"shift":
			var up := drive.upshift_count
			var down := drive.downshift_count
			p.linear_velocity = -p.global_transform.basis.z * 15.0
			p.shift(2 - p.current_gear)
			_go("shift_down")
			samples.up0 = up
			samples.down0 = down
		"shift_down":
			if step_t > 0.6 and not samples.has("mid"):
				samples.mid = true
				p.shift(-1)
			if step_t > 1.2:
				var ups: int = drive.upshift_count - samples.up0
				var downs: int = drive.downshift_count - samples.down0
				print("shifts: %d up, %d down" % [ups, downs])
				_check(downs >= 1, "a shift down should count as a downshift (up %d, down %d)" % [ups, downs])
				# driving along freely: no scrape, no hits
				print("driving free at %.1f m/s: scrape %.3f, hits %d" % [p.current_speed(), crash.scrape_level, crash.impact_count])
				_check(crash.scrape_level < 0.05, "driving on the road should not scrape (%.2f)" % crash.scrape_level)
				_check(crash.impact_count == 0, "driving on the road should not crash (%d)" % crash.impact_count)
				_go("reset_in_air")
		"reset_in_air":
			# A respawn-style reset in the air: velocity zeroed, nothing touched.
			# by frames, not time: a long frame must not skip a stage
			samples.air_frames = samples.get("air_frames", 0) + 1
			if samples.air_frames == 1:
				samples.hits0 = crash.impact_count
				p.global_position.y += 3.0
				p.linear_velocity = Vector3(0.0, 0.0, -25.0)
			elif samples.air_frames == 3:
				p.linear_velocity = Vector3.ZERO
			elif samples.air_frames >= 6:
				_check(crash.impact_count == samples.hits0, "zeroing the velocity in the air should not be a crash")
				_go("settle")
		"settle":
			if step_t > 2.0:
				# Into a wall at 25 m/s.
				var fwd := -p.global_transform.basis.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				var at := p.global_position + fwd * 14.0
				wall = _wall(at + Vector3(0.0, 1.0, 0.0), Vector3(12.0, 3.0, 1.0))
				wall.look_at(wall.global_position + fwd, Vector3.UP)
				p.linear_velocity = fwd * 25.0
				samples.hits0 = crash.impact_count
				_go("crash")
		"crash":
			if crash.last_dv > biggest_dv and crash.impact_count > samples.hits0:
				biggest_dv = crash.last_dv
				biggest_hit = crash.last_tier
			if step_t > 1.5:
				var hits: int = crash.impact_count - samples.hits0
				print("wall at 25 m/s: %d hit(s), biggest %s at %.1f m/s" % [hits, biggest_hit, biggest_dv])
				_check(hits >= 1, "driving into a wall at 25 m/s made no crash sound")
				_check(biggest_hit in ["crunch", "glass"], "a 25 m/s wall hit should crunch, got %s (%.1f m/s)" % [biggest_hit, biggest_dv])
				wall.queue_free()
				_go("scrape_setup")
		"scrape_setup":
			if step_t > 0.5:
				# A long wall along the car's right side; push the car along it.
				var b := p.global_transform.basis
				var fwd := -b.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				var right := fwd.cross(Vector3.UP)
				var bb := p.chassis_visual.get_meta("half_w", 0.9) as float
				wall = _wall(p.global_position + right * (bb + 0.55) + fwd * 30.0 + Vector3(0.0, 1.0, 0.0), Vector3(0.6, 3.0, 90.0))
				wall.look_at(wall.global_position + fwd, Vector3.UP)
				samples.fwd = fwd
				samples.right = right
				_go("scrape")
		"scrape":
			p.linear_velocity = samples.fwd * 15.0 + samples.right * 2.0
			scrape_peak = maxf(scrape_peak, crash.scrape_level)
			if step_t > 1.5:
				print("scrape along a wall at 15 m/s: level %.2f" % scrape_peak)
				_check(scrape_peak > 0.3, "sliding along a wall should scrape (%.2f)" % scrape_peak)
				_finish()
	return false

func _report_cabin() -> void:
	for k in ["closed", "cracked", "open"]:
		var s: Dictionary = samples.get(k, {})
		if s.is_empty():
			_fail("no cabin sample for %s" % k)
			return
		print("cockpit, window %-7s: engine cutoff %5.0f Hz, buffet %.3f, throb %.2f, whistle %.2f" % [k, s.cutoff, s.buffet, s.throb, s.whistle])
	var c: Dictionary = samples.closed
	var k2: Dictionary = samples.cracked
	var o: Dictionary = samples.open
	_check(absf(c.cutoff - PerspectiveAudio.COCKPIT_HZ[&"Engine"]) < 5.0, "closed window should keep the cockpit cutoff")
	_check(c.cutoff < k2.cutoff and k2.cutoff < o.cutoff and o.cutoff > 10000.0, "the cutoff should open as the window goes down")
	_check(c.buffet < o.buffet * 0.5, "the wind should be much louder with the window open")
	_check(k2.throb > 0.3 and k2.throb > c.throb + 0.3 and k2.throb > o.throb + 0.3, "the throb should peak with the window cracked")
	_check(c.whistle > 0.2 and o.whistle < 0.05, "the seal whistle belongs to the closed window at speed")

func _check_variants() -> void:
	for n in ["ThumpAudio", "ClackUpAudio", "ClackDownAudio"]:
		var pl := drive.get_node_or_null(n) as AudioStreamPlayer
		var r := pl.stream as AudioStreamRandomizer if pl != null else null
		_check(r != null and r.streams_count == DrivelineAudio.VARIANTS, "%s should hold %d random variants" % [n, DrivelineAudio.VARIANTS])
	# crash pools: tests/audio/crash_variety.gd checks them take by take
	for pool in CrashAudio.POOLS:
		var pl: CrashAudio.Pool = crash._pools.get(pool)
		_check(pl != null and pl.streams.size() == CrashAudio.VARIANTS, "%s should hold %d variants" % [pool, CrashAudio.VARIANTS])
	var chirp := car.get_node("ChirpAudio").stream as AudioStreamRandomizer
	_check(chirp != null and chirp.streams_count == CarAudio.CHIRP_VARIANTS, "the chirp should hold %d variants" % CarAudio.CHIRP_VARIANTS)
	for layer in CarAudio.PAIRED:
		var a := car.get_node((layer as String).to_pascal_case() + "Audio") as AudioStreamPlayer
		var b := car.get_node((layer + "_b").to_pascal_case() + "Audio") as AudioStreamPlayer
		var la := (a.stream as AudioStreamWAV).loop_end
		var lb := (b.stream as AudioStreamWAV).loop_end
		_check(la != lb, "%s: the two takes should differ in length (%d, %d)" % [layer, la, lb])
	_check(crash.get_node_or_null("ScrapeConcreteBAudio") != null, "the scrape should have a second player to crossfade takes")

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	print("sound_fixes: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	game.queue_free()
	game = null
	quit_in = 30
