extends SceneTree

# Stage A audio test (2026-10-04): the generated loops are sane, and on a real
# drive of Game.tscn (held keys, the same InputMap path a keyboard uses) each
# layer of CarAudio follows what the car is doing.
#
# Phases:
#   idle   -- standing still: every layer silent
#   launch -- full throttle with upshifts to 30 m/s: wind and road follow speed
#   slide  -- handbrake + full lock at speed: tyres squeal
#   kerb   -- steer onto the sidewalk ("Dirt"): kerb rumble
#
# Asserts (exit code 1 on failure):
# - each loop: finite, peak 0.8 (normalised), no click at the loop point,
#   built in under 1 s total
# - idle: all four levels under 0.02
# - launch: wind tracks speed^WIND_EXP (r > 0.95), road tracks speed (r > 0.9);
#   at 30 m/s wind > 0.25 and road > 0.5; squeal stays under 0.15 while
#   cruising straight above 20 m/s
# - slide: squeal > 0.4 (after 1.25 s of sliding)
# - kerb: surface > 0.25
# - four players, playing, on the World/Tires buses that exist
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
var e_down := false
var record: AudioEffectRecord
var phase_marks := {}  # phase -> seconds into the recording when it started
var t := 0.0
var quit_in := 0

func _initialize() -> void:
	_check_loops()
	record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	seed(777)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _check_loops() -> void:
	var t0 := Time.get_ticks_usec()
	for layer in ["wind", "road", "squeal", "surface"]:
		CarAudio.stream(layer)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("loops built in %.0f ms" % ms)
	if ms > 1000.0:
		_fail("building the loops took %.0f ms" % ms)
	for layer in ["wind", "road", "squeal", "surface"]:
		var wav := CarAudio.stream(layer)
		# wav.data returns a copy on every access: read it once.
		var data := wav.data
		var n := data.size() / 2
		var s := PackedFloat32Array()
		s.resize(n)
		var peak := 0.0
		var diff_sq := 0.0
		for i in n:
			s[i] = data.decode_s16(i * 2) / 32767.0
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

func _hold_heading(p: PlayerCar, aim_x: float = 0.0, max_term: float = 0.05) -> void:
	var err: float = p.global_rotation.y + clampf((aim_x - p.global_position.x) * 0.02, -max_term, max_term)
	_press(KEY_A, err < -0.02)
	_press(KEY_D, err > 0.02)

## The handbrake slide leaves the car spun round and nearly stopped, and how it
## ends differs run to run (it sometimes sits sideways at 0 m/s and never gets
## to the sidewalk). The kerb phase only tests the surface layer, so start it
## from a known state: lane centre, facing down the road, 12 m/s in 2nd.
func _reset_for_kerb(p: PlayerCar) -> void:
	p.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, p.global_position.y, p.global_position.z))
	p.linear_velocity = Vector3(0.0, 0.0, -12.0)
	p.angular_velocity = Vector3.ZERO
	p.shift(2 - p.current_gear)

func _upshift(p: PlayerCar) -> void:
	if e_down:
		_press(KEY_E, false)
		e_down = false
	elif p.gear >= 1 and p.gear < 5 and p.linear_velocity.length() > 9.0 * p.gear and not p.is_shifting:
		_press(KEY_E, true)
		e_down = true

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
	p.automatic_transmission = false  # this bot shifts with E (the game default is automatic now)
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
				_press(KEY_W, true)
		"launch":
			_hold_heading(p)
			_upshift(p)
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
				_press(KEY_W, false)
				_press(KEY_SPACE, true)
				_press(KEY_A, true)
				_press(KEY_D, false)
			elif phase_ticks > _sec(45):
				_fail("launch never reached 30 m/s (%.1f)" % speed)
				_finish()
		"slide":
			slide_squeal = maxf(slide_squeal, audio.squeal_level)
			if phase_ticks >= _sec(1.25):
				print("slide: squeal max %.2f" % slide_squeal)
				if slide_squeal <= 0.4:
					_fail("handbrake slide at speed only squealed %.2f" % slide_squeal)
				_press(KEY_SPACE, false)
				_press(KEY_A, false)
				_next("kerb")
				_reset_for_kerb(p)
				_press(KEY_W, true)
		"kerb":
			_upshift(p)
			if speed > 8.0:
				_hold_heading(p, _sidewalk_x(p), 0.15)
			else:
				_hold_heading(p, p.global_position.x)
			kerb_surface = maxf(kerb_surface, audio.surface_level)
			# Two wheels on the sidewalk at ~10 m/s is ~0.25; silent is 0.
			if kerb_surface > 0.25 or phase_ticks > _sec(25):
				print("kerb: surface max %.2f" % kerb_surface)
				if kerb_surface <= 0.25:
					_fail("kerb rumble never came on (%.2f)" % kerb_surface)
				_finish()
	return false

func _check_players() -> void:
	var want := {"WindAudio": &"World", "RoadAudio": &"Tires", "SquealAudio": &"Tires", "SurfaceAudio": &"Tires"}
	for n in want:
		var player := audio.get_node_or_null(NodePath(n)) as AudioStreamPlayer
		if player == null:
			_fail("missing %s" % n)
		elif not player.playing or player.bus != want[n] or AudioServer.get_bus_index(want[n]) < 0:
			_fail("%s: playing=%s bus=%s" % [n, player.playing, player.bus])

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
