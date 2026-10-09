extends SceneTree

# Stage A audio test (2026-10-04): the generated loops are sane, and on a real
# drive of Game.tscn each layer of CarAudio follows what the car is doing.
# The car is driven through PlayerCar.driver (throttle, handbrake and a
# pure-pursuit lane keeper), not key events: the old bot steered bang-bang
# through the keyboard ramp and swerved +-0.3 rad across the road whenever a
# frame ran long, and that real slide squealed (flaked 1 run in 3 in the full
# suite, 5 of 6 under CPU load; fixed 2026-10-06).
#
# Phases:
#   idle   -- standing still: every layer silent
#   launch -- full throttle (automatic gearbox) to 30 m/s: wind and road follow speed
#   slide  -- handbrake + full lock at speed: tyres squeal
#   kerb   -- steer onto the sidewalk ("Dirt"): kerb rumble
#
# Asserts (exit code 1 on failure):
# - each loop: finite, peak 0.8 (normalised), no click at the loop point,
#   built in under 12 s total (about 3.8 s since the 2026-10-08 rebuild, once
#   per change: the game loads them from user://audio_cache after that; the
#   limit is only there to catch a runaway, and a busy machine must not fail)
# - idle: all four levels under 0.02
# - launch: wind tracks speed^WIND_EXP (r > 0.95), road tracks speed (r > 0.9);
#   at 30 m/s wind > 0.25 and road > 0.5; squeal stays under 0.15 while
#   cruising straight above 20 m/s
# - slide: squeal > 0.4 (after 1.25 s of sliding), and the tyre kind heard is
#   a sliding one (squeal or lock), not wheelspin
#   (2026-10-08: tyres are four kinds per side; squeal_level is all of them)
# - kerb: surface > 0.25
# - the whole drive (launch, handbrake spin, kerb) makes no crash sound and no
#   scrape (CrashAudio, 2026-10-08)
# - every looping player (tyre kinds per side, buffet, rush, whistle, throb,
#   road dark/bright, each wind/road layer's second take, surface) exists on
#   the World/Tires buses that exist, and plays exactly when it is audible
#   (2026-10-09: a silent loop is stopped, not mixed at -80 dB), so at the
#   standstill every one is stopped
# Also records the real mixed output (engine + these layers) from the Master
# bus to user://stage_a_drive.wav and reports how loud each phase is.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car_audio.gd

# Phase lengths are in seconds, not ticks: the suite runs at 60 Hz (NEON_TICKS=60)
# but the game ships at 120, and the levels are smoothed per second, so a
# tick count means different things at the two rates.
const MAX_SECONDS := 120

func _sec(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second)

var fails := 0
var game: Node
var audio: CarAudio
var phase := "idle"
var phase_ticks := 0
var ticks := 0
var speeds: PackedFloat32Array = []
var winds: PackedFloat32Array = []
var roads: PackedFloat32Array = []
var cruise_squeal := 0.0
var slide_squeal := 0.0
var kerb_surface := 0.0
var slide_kinds := {}
## What the driver callable feeds the car, set per phase.
var d_throttle := 0.0
var d_handbrake := 0.0
var d_steer := 0.0       # raw steering_input, used when d_lane_x is NAN
var d_lane_x := NAN      # hold this world x with the traffic lane keeper
var record: AudioEffectRecord
var phase_marks := {}  # phase -> seconds into the recording when it started
var t := 0.0
var quit_in := 0

func _initialize() -> void:
	_check_loops()
	record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	seed(777)
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = d_throttle
	c.brake_input = 0.0
	c.handbrake_input = d_handbrake
	if is_nan(d_lane_x):
		c.steering_input = d_steer
	else:
		c.steering_input = TrafficCar.lane_steer(c, d_lane_x, -1.0, 2.5)

func _check_loops() -> void:
	AudioDsp.use_cache = false  # time and check the real build, not the disk cache
	var t0 := Time.get_ticks_usec()
	var layers := ["buffet", "rush", "whistle", "throb", "road_dark", "road_bright", "surface"]
	for layer in CarAudio.PAIRED:
		layers.append(layer + "_b")
	for kind in CarAudio.KINDS:
		layers.append(kind + "_l")
		layers.append(kind + "_r")
	for layer in layers:
		CarAudio.stream(layer)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("loops built in %.0f ms" % ms)
	AudioDsp.use_cache = true
	if ms > 12000.0:
		_fail("building the loops took %.0f ms" % ms)
	for layer in layers:
		var wav := CarAudio.stream(layer)
		# wav.data returns a copy on every access: read it once.
		var data := wav.data
		# stereo tyre loops: check the near channel (left for _l, right for _r)
		var ch := 2 if wav.stereo else 1
		var off := 2 if layer.ends_with("_r") else 0
		var n := data.size() / (2 * ch)
		var s := PackedFloat32Array()
		s.resize(n)
		var peak := 0.0
		var diff_sq := 0.0
		for i in n:
			s[i] = data.decode_s16(i * 2 * ch + off) / 32767.0
			peak = maxf(peak, absf(s[i]))
			if i > 0:
				diff_sq += (s[i] - s[i - 1]) * (s[i] - s[i - 1])
		var typical_step := sqrt(diff_sq / (n - 1))
		var seam := absf(s[0] - s[n - 1])
		print("loop %-7s %d samples, peak %.3f, seam step %.4f vs typical %.4f" % [layer, n, peak, seam, typical_step])
		if absf(peak - 0.8) > 0.01:
			_fail("%s loop peak %.3f, expected 0.8" % [layer, peak])
		if seam > typical_step * 4.0 + 0.002:
			_fail("%s loop clicks at the seam (%.4f)" % [layer, seam])
		if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD or wav.loop_end != n:
			_fail("%s is not a full forward loop" % layer)

## Lateral position of the middle of the right-hand sidewalk where the car is
## now (lane counts change chunk to chunk, so it is looked up, not fixed).
func _sidewalk_x(p: PlayerCar) -> float:
	var idx := int(floor(-p.global_position.z / RoadChunkBuilder.CHUNK_LEN)) + int(game.get("origin_index"))
	var cfg: Dictionary = game.call("_section_at", idx)
	return RoadChunkBuilder._lane_w(cfg.own_lanes) + RoadChunkBuilder.SHOULDER_W + RoadChunkBuilder.CURB_W + RoadChunkBuilder.SIDEWALK_W / 2.0

## The handbrake slide leaves the car spun round and nearly stopped, and how it
## ends differs run to run (it sometimes sits sideways at 0 m/s and never gets
## to the sidewalk). The kerb phase only tests the surface layer, so start it
## from a known state: lane centre, facing down the road, 12 m/s in 2nd.
func _reset_for_kerb(p: PlayerCar) -> void:
	p.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, p.global_position.y, p.global_position.z))
	p.linear_velocity = Vector3(0.0, 0.0, -12.0)
	p.angular_velocity = Vector3.ZERO
	p.shift(2 - p.current_gear)

func _next(name: String) -> void:
	phase = name
	phase_ticks = 0
	phase_marks[name] = t

func _process(delta: float) -> bool:
	t += delta
	if quit_in > 0:
		quit_in -= 1
		if quit_in == 0:
			quit(0 if fails == 0 else 1)
			return true
	return false

func _physics_process(_delta: float) -> bool:
	if game == null:
		return false
	ticks += 1
	phase_ticks += 1
	if ticks > _sec(MAX_SECONDS):
		_fail("timed out in phase %s" % phase)
		_finish()
		return false
	var p: PlayerCar = game.get("player")
	p.driver = _drive
	if audio == null:
		for c in p.get_children():
			if c is CarAudio:
				audio = c
		if audio == null:
			_fail("player has no CarAudio")
			_finish()
			return false
		phase_marks["idle"] = t
		# Recording starts with the idle phase, so phase times map straight
		# onto positions in the recording.
		record.set_recording_active(true)
	var speed := p.current_speed()
	match phase:
		"idle":
			if phase_ticks == _sec(1.5):
				print("idle: wind %.3f road %.3f squeal %.3f surface %.3f" % [audio.wind_level, audio.road_level, audio.squeal_level, audio.surface_level])
				for lv in [audio.wind_level, audio.road_level, audio.squeal_level, audio.surface_level]:
					if lv > 0.02:
						_fail("a layer is audible at a standstill (%.3f)" % lv)
						break
				_check_players()
				_next("launch")
				d_throttle = 1.0
				d_lane_x = 0.0
		"launch":
			speeds.append(speed)
			winds.append(audio.wind_level)
			roads.append(audio.road_level)
			if speed > 20.0 and phase_ticks > _sec(1.0) and not p.is_shifting:
				cruise_squeal = maxf(cruise_squeal, audio.squeal_level)
			if speed >= 30.0:
				var sq := PackedFloat32Array()
				for v in speeds:
					sq.append(pow(v, CarAudio.WIND_EXP))
				var rw := _corr(sq, winds)
				var rr := _corr(speeds, roads)
				print("launch: 30 m/s after %.1f s: wind %.2f (r=%.3f vs speed^1.5), road %.2f (r=%.3f vs speed), cruise squeal max %.3f" % [phase_ticks / float(Engine.physics_ticks_per_second), audio.wind_level, rw, audio.road_level, rr, cruise_squeal])
				if rw < 0.95:
					_fail("wind does not follow speed^WIND_EXP (r=%.3f)" % rw)
				if rr < 0.9:
					_fail("road roar does not follow speed (r=%.3f)" % rr)
				if audio.wind_level < 0.25 or audio.road_level < 0.5:
					_fail("too quiet at 30 m/s: wind %.2f road %.2f" % [audio.wind_level, audio.road_level])
				if cruise_squeal >= 0.15:
					_fail("tyres squeal while cruising straight (%.3f)" % cruise_squeal)
				_next("slide")
				d_throttle = 0.0
				d_handbrake = 1.0
				d_lane_x = NAN
				d_steer = 1.0  # full lock
			elif phase_ticks > _sec(45):
				_fail("launch never reached 30 m/s (%.1f)" % speed)
				_finish()
		"slide":
			slide_squeal = maxf(slide_squeal, audio.squeal_level)
			for kind in CarAudio.KINDS:
				slide_kinds[kind] = maxf(slide_kinds.get(kind, 0.0), maxf(audio.tyre[kind][0], audio.tyre[kind][1]))
			if phase_ticks >= _sec(1.25):
				print("slide: squeal max %.2f, by kind %s" % [slide_squeal, slide_kinds])
				if slide_squeal <= 0.4:
					_fail("handbrake slide at speed only squealed %.2f" % slide_squeal)
				if maxf(slide_kinds.squeal, slide_kinds.lock) <= 0.4:
					_fail("a handbrake slide should sound as a squeal or a lock-up, got %s" % slide_kinds)
				if slide_kinds.spin > maxf(slide_kinds.squeal, slide_kinds.lock):
					_fail("a handbrake slide sounded mostly like wheelspin %s" % slide_kinds)
				d_handbrake = 0.0
				d_steer = 0.0
				_next("kerb")
				_reset_for_kerb(p)
				d_throttle = 1.0
		"kerb":
			# Aim at the sidewalk once moving; until then hold the line.
			d_lane_x = _sidewalk_x(p) if speed > 8.0 else p.global_position.x
			kerb_surface = maxf(kerb_surface, audio.surface_level)
			# Two wheels on the sidewalk at ~10 m/s is ~0.25; silent is 0.
			if kerb_surface > 0.25 or phase_ticks > _sec(25):
				print("kerb: surface max %.2f" % kerb_surface)
				if kerb_surface <= 0.25:
					_fail("kerb rumble never came on (%.2f)" % kerb_surface)
				_finish()
	return false

func _check_players() -> void:
	var want := {"BuffetAudio": &"World", "RushAudio": &"World", "WhistleAudio": &"World", "ThrobAudio": &"World",
		"RoadDarkAudio": &"Tires", "RoadBrightAudio": &"Tires", "SurfaceAudio": &"Tires"}
	for layer in CarAudio.PAIRED:
		want[(layer + "_b").to_pascal_case() + "Audio"] = want[layer.to_pascal_case() + "Audio"]
	for kind in CarAudio.KINDS:
		want[kind.capitalize() + "LAudio"] = &"Tires"
		want[kind.capitalize() + "RAudio"] = &"Tires"
	for n in want:
		var player := audio.get_node_or_null(NodePath(n)) as AudioStreamPlayer
		if player == null:
			_fail("missing %s" % n)
		elif player.bus != want[n] or AudioServer.get_bus_index(want[n]) < 0:
			_fail("%s: bus=%s" % [n, player.bus])
		elif player.playing != (player.volume_db > -79.0):
			_fail("%s: playing=%s at %.1f dB (a loop should play exactly when audible)" % [n, player.playing, player.volume_db])

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	record.set_recording_active(false)
	var wav := record.get_recording()
	if wav == null or wav.data.is_empty():
		print("recording: nothing captured (the audio driver may not mix here)")
	else:
		var path := "user://stage_a_drive.wav"
		var err := wav.save_to_wav(path)
		print("recording: %.1f s -> %s (error %d)" % [wav.data.size() / 4.0 / AudioServer.get_mix_rate(), ProjectSettings.globalize_path(path), err])
		_report_loudness(wav)
	var p: PlayerCar = game.get("player")
	for c in p.get_children():
		if c is CrashAudio:
			print("crash sounds during the drive: %d (last %s %.1f m/s)" % [c.impact_count, c.last_tier, c.last_dv])
			if c.impact_count > 0:
				_fail("a normal drive made %d crash sound(s)" % c.impact_count)
	print("car_audio: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	# Free the game (and its playing generators) first, quit a few frames later.
	game.queue_free()
	game = null
	quit_in = 30

## RMS of the recorded mix per phase, so the report says how loud each part
## of the drive actually was (engine included).
func _report_loudness(wav: AudioStreamWAV) -> void:
	var rate := AudioServer.get_mix_rate()
	var data := wav.data  # a copy per access: read it once
	var frames := data.size() / 4  # 16-bit stereo
	var names := ["idle", "launch", "slide", "kerb"]
	for i in names.size():
		if not phase_marks.has(names[i]):
			continue
		var a := int((phase_marks[names[i]] - phase_marks["idle"]) * rate)
		var b := frames
		if i + 1 < names.size() and phase_marks.has(names[i + 1]):
			b = int((phase_marks[names[i + 1]] - phase_marks["idle"]) * rate)
		a = clampi(a, 0, frames)
		b = clampi(b, a, frames)
		var sum := 0.0
		for f in range(a, b):
			var v := data.decode_s16(f * 4) / 32767.0
			sum += v * v
		var rms := sqrt(sum / maxi(1, b - a))
		print("recorded %-6s %.1f s, RMS %.3f" % [names[i], float(b - a) / rate, rms])

func _corr(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(saa * sbb) if saa > 0.0 and sbb > 0.0 else 0.0
