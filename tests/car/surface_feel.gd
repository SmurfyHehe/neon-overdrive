extends SceneTree

# Tyre and surface feel (2026-10-11): SurfaceMap (which band a tyre is on) and
# SurfaceFeel (grip, slide and roughness per band, dry and wet), driven in the
# real Game.tscn.
#
# Rules, checked once on the first game:
# - dry asphalt with the tyres gripping changes nothing: every factor is 1
# - a tyre lets go earlier in the wet than in the dry, and takes longer to grip
#   again once it has stopped sliding
# - SurfaceMap reads lane, edge line, shoulder, kerb strip and lane dash where
#   RoadChunkBuilder draws them, with the lane counts game.gd builds from
#
# Drives, one fresh game each, the car placed and launched at speed:
#   off      -- SurfaceFeel switched off: GEVP's own numbers, for the stopping
#               distance the dry drive is compared with (within 5%)
#   dry      -- lane centre: every wheel on asphalt, GEVP's own friction to the
#               bit, no grit or water sound; then a full stop
#   wet      -- the same, soaked: friction at the wet row, water hiss on; the
#               stop is longer than the dry one
#   shoulder -- right wheels on the gritty shoulder: those two read grit and
#               carry less friction than the left pair, the grit sound and the
#               camera rumble come on, a slide there lays no rubber; the car
#               tugs toward the shoulder and a little steering holds the line
#               through a full stop
#   flick dry / flick wet -- the same half-second steering flick at 100 km/h:
#               the wet car spends longer sliding
# - zero errors logged, every number finite
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/surface_feel.gd

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

const K := SurfaceMap.Kind
const B := preload("res://scripts/world/road_chunk_builder.gd")
const DRIVES := ["off", "dry", "wet", "shoulder", "flick_dry", "flick_wet"]
const SETTLE := 60       # ticks standing before the car is placed
const COAST := 45        # ticks rolling before anything is measured
const MAX_TICKS := 60 * 25  # per drive

var logger := ErrorCounter.new()
var fails := 0
var game: Node
var drive_i := -1
var t := 0
var rules_done := false
var throttle := 0.0
var brake := 0.0
var steer := 0.0

var stop_dist := {}
var slide_ticks := {}
var slide_peak := {}
var dist := 0.0
var braking := false
var start_x := 0.0
var steer_sum := 0.0
var steer_n := 0
var off_line_max := 0.0
var grit_seen := 0.0
var wet_seen := 0.0
var rumble_seen := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_WET", "")
	OS.set_environment("NEON_SURFACE_FEEL", "")
	OS.add_logger(logger)
	seed(4711)
	_next_drive()

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _player() -> PlayerCar:
	return game.get("player")

func _next_drive() -> void:
	drive_i += 1
	t = 0
	dist = 0.0
	braking = false
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	if game:
		game.queue_free()
		game = null
	if drive_i >= DRIVES.size():
		return
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.steering_input = steer
	c.handbrake_input = 0.0

## Moves the standing car sideways to lateral position x (the harness's
## move_player_to_lane) and sets it rolling.
func _place(p: PlayerCar, x: float, speed: float) -> void:
	var offset := Vector3(x - p.global_position.x, 0.0, 0.0)
	p.global_position += offset
	p.previous_global_position += offset
	for w in p.wheel_array:
		w.previous_global_position += offset
		w.last_collision_point += offset
	TrafficCar.set_moving(p, speed)
	p.reset_physics_interpolation()

func _edge(p: PlayerCar) -> float:
	return SurfaceMap.edge_at(RoadFrame.s_at(RoadFrame.unroll(p.global_position).z), false)

func _lane_x(i: int) -> float:
	return B.MEDIAN_GAP + (float(i) + 0.5) * B.LANE_W

func _rules(p: PlayerCar) -> void:
	# 1. dry asphalt, gripping: nothing changes
	for col in [SurfaceFeel.PEAK, SurfaceFeel.STIFF, SurfaceFeel.LONG, SurfaceFeel.ASSIST, SurfaceFeel.ROLL, SurfaceFeel.BRAKE]:
		if SurfaceFeel.value(K.ASPHALT, col, 0.0) != 1.0:
			_fail("dry asphalt column %d is %.3f, expected 1" % [col, SurfaceFeel.value(K.ASPHALT, col, 0.0)])
	# 2. onset and recovery, dry against wet, at a slip between the two onsets
	var dt := 1.0 / 60.0
	var dry := 0.0
	var wet := 0.0
	for i in 30:
		dry = SurfaceFeel.next_slide(dry, 0.2, SurfaceFeel.value(K.ASPHALT, SurfaceFeel.ONSET, 0.0), 6.0, dt)
		wet = SurfaceFeel.next_slide(wet, 0.2, SurfaceFeel.value(K.ASPHALT, SurfaceFeel.ONSET, 1.0), 2.2, dt)
	print("rules: slide at 0.2 slip after 0.5 s: dry %.2f wet %.2f" % [dry, wet])
	if not (wet > dry + 0.2):
		_fail("the wet tyre should be well further gone than the dry one at the same slip (dry %.2f wet %.2f)" % [dry, wet])
	if SurfaceFeel.next_slide(0.0, 0.1, SurfaceFeel.value(K.ASPHALT, SurfaceFeel.ONSET, 0.0), 6.0, dt) != 0.0:
		_fail("a dry tyre under its onset must not start to slide")
	var dry_ticks := 0
	var wet_ticks := 0
	dry = 1.0
	wet = 1.0
	for i in 120:
		dry = SurfaceFeel.next_slide(dry, 0.0, 0.16, SurfaceFeel.value(K.ASPHALT, SurfaceFeel.RECOVER, 0.0), dt)
		wet = SurfaceFeel.next_slide(wet, 0.0, 0.11, SurfaceFeel.value(K.ASPHALT, SurfaceFeel.RECOVER, 1.0), dt)
		dry_ticks += 1 if dry > 0.05 else 0
		wet_ticks += 1 if wet > 0.05 else 0
	print("rules: ticks to grip again from a full slide: dry %d wet %d" % [dry_ticks, wet_ticks])
	if not (wet_ticks > dry_ticks * 2):
		_fail("a wet tyre should take over twice as long to grip again (dry %d wet %d ticks)" % [dry_ticks, wet_ticks])
	# every wet row grips no better than its dry row, and lets go no later
	for k in SurfaceFeel.DRY.size():
		if SurfaceFeel.WET[k][SurfaceFeel.PEAK] > SurfaceFeel.DRY[k][SurfaceFeel.PEAK] or SurfaceFeel.WET[k][SurfaceFeel.ONSET] > SurfaceFeel.DRY[k][SurfaceFeel.ONSET]:
			_fail("%s grips better or lets go later wet than dry" % SurfaceMap.NAMES[k])
	# 3. the bands, where the chunk builder draws them
	var u := RoadFrame.unroll(p.global_position)
	var s := RoadFrame.s_at(u.z)
	var idx := floori(s / B.CHUNK_LEN)
	for i in range(idx - 1, idx + 4):
		var cfg: Dictionary = game.call("_section_at", i)
		if SurfaceMap.lanes(i, false) != int(cfg.own_lanes) or SurfaceMap.lanes(i, true) != int(cfg.onc_lanes):
			_fail("chunk %d: SurfaceMap lanes %d/%d, the game builds %d/%d" % [i, SurfaceMap.lanes(i, false), SurfaceMap.lanes(i, true), cfg.own_lanes, cfg.onc_lanes])
	var edge := SurfaceMap.edge_at(s, false)
	# z of a dash centre and of a gap centre in this chunk
	var chunk_z := u.z + (s - float(idx) * B.CHUNK_LEN)
	var dash_z := chunk_z - B.DASH_SPACING * 2.5
	var gap_z := chunk_z - B.DASH_SPACING * 2.0
	var divider := B.MEDIAN_GAP + B.LANE_W
	var want := [
		["lane centre", Vector3(_lane_x(1), 0.0, dash_z), K.ASPHALT],
		["edge line", Vector3(edge - 0.05, 0.0, u.z), K.PAINT],
		["shoulder", Vector3(edge + 0.7, 0.0, u.z), K.GRIT],
		["kerb strip", Vector3(edge + B.SHOULDER_W + 0.15, 0.0, u.z), K.KERB],
		["oncoming shoulder", Vector3(-SurfaceMap.edge_at(s, true) - 0.7, 0.0, u.z), K.GRIT],
		["lane dash", Vector3(divider, 0.0, dash_z), K.PAINT],
		["gap between dashes", Vector3(divider, 0.0, gap_z), K.ASPHALT],
		["beside a dash", Vector3(divider + 0.5, 0.0, dash_z), K.ASPHALT],
	]
	for row in want:
		var got := SurfaceMap.kind_at(row[1])
		if got != row[2]:
			_fail("%s reads %s, expected %s" % [row[0], SurfaceMap.NAMES[got], SurfaceMap.NAMES[row[2]]])
	print("rules: lane edge %.2f m, bands checked" % edge)

func _physics_process(delta: float) -> bool:
	if drive_i >= DRIVES.size():
		return _finish()
	var p := _player()
	if p == null:
		return false
	if not p.driver.is_valid():
		p.driver = _drive
	t += 1
	var name: String = DRIVES[drive_i]
	var feel := p.surface_feel
	var audio := p.get_node_or_null(^"CarAudio") as CarAudio
	if audio == null:
		for c in p.get_children():
			if c is CarAudio:
				audio = c
	var cam := game.get("camera") as ChaseCamera
	if t == SETTLE:
		if not rules_done:
			rules_done = true
			_rules(p)
		SurfaceMap.wetness = 1.0 if name in ["wet", "flick_wet"] else 0.0
		SurfaceFeel.enabled = name != "off"
		var x := _lane_x(1)
		if name == "shoulder":
			var half_track := 0.0
			for w in p.wheel_array:
				half_track = maxf(half_track, p.to_local(w.global_position).x)
			x = _edge(p) + 0.7 - half_track
		elif name.begins_with("flick"):
			x = _lane_x(2)
		_place(p, x, 28.0 if name.begins_with("flick") else 30.0)
		start_x = x
		grit_seen = 0.0
		wet_seen = 0.0
		rumble_seen = 0.0
		slide_ticks[name] = 0
		slide_peak[name] = 0.0
		return false
	if t < SETTLE:
		return false
	var since := t - SETTLE
	dist += p.linear_velocity.length() * delta if braking else 0.0
	if audio != null:
		grit_seen = maxf(grit_seen, audio.grit_level)
		wet_seen = maxf(wet_seen, audio.wet_level)
	if cam != null:
		rumble_seen = maxf(rumble_seen, cam.surface_t)
	if not p.global_position.is_finite() or not p.linear_velocity.is_finite():
		_fail("%s: the car's position or speed stopped being a number" % name)
		_next_drive()
		return false
	if t > MAX_TICKS:
		_fail("%s: timed out" % name)
		_next_drive()
		return false

	if name.begins_with("flick"):
		steer = 1.0 if since >= COAST and since < COAST + 30 else 0.0
		if since >= COAST:
			slide_peak[name] = maxf(slide_peak[name], feel.slide_max())
			if feel.slide_max() > 0.2:
				slide_ticks[name] += 1
		if since == COAST + 60 * 5:
			print("%s: peak slide %.2f, %d ticks sliding" % [name, slide_peak[name], slide_ticks[name]])
			_next_drive()
		return false

	# dry / wet / shoulder: coast, check, then stop
	if name == "shoulder":
		# Hold the line like a player would: steer against the drift and the yaw.
		var off_line := p.global_position.x - start_x
		steer = clampf(0.8 * off_line - 2.0 * p.global_rotation.y, -1.0, 1.0)
		steer_sum += absf(steer)
		steer_n += 1
		off_line_max = maxf(off_line_max, absf(off_line))
	if since == COAST:
		_check_coast(name, p, feel)
		brake = 1.0
		braking = true
	if braking and p.linear_velocity.length() < 1.0:
		stop_dist[name] = dist
		print("%s: stopped from 108 km/h in %.1f m, %.2f m sideways, turned %.1f deg; grit sound %.2f, water sound %.2f, camera rumble %.2f" % [name, dist, p.global_position.x - start_x, rad_to_deg(p.global_rotation.y), grit_seen, wet_seen, rumble_seen])
		if name == "shoulder":
			print("shoulder: held within %.2f m of the line, mean steering %.3f of full lock" % [off_line_max, steer_sum / float(maxi(steer_n, 1))])
		_check_stop(name, absf(rad_to_deg(p.global_rotation.y)))
		_next_drive()
	return false

func _check_coast(name: String, p: PlayerCar, feel: SurfaceFeel) -> void:
	var kinds := []
	for i in p.wheel_array.size():
		kinds.append(SurfaceMap.NAMES[feel.kind[i]])
	print("%s: wheels on %s" % [name, kinds])
	for i in p.wheel_array.size():
		var w: Wheel = p.wheel_array[i]
		var base: float = w.coefficient_of_friction[w.surface_type]
		var right := p.to_local(w.global_position).x > 0.0
		match name:
			"off":
				if w.current_cof != base:
					_fail("off: wheel %d friction %.4f, GEVP's own is %.4f" % [i, w.current_cof, base])
			"dry":
				if feel.kind[i] != K.ASPHALT:
					_fail("dry: wheel %d on %s, expected asphalt" % [i, SurfaceMap.NAMES[feel.kind[i]]])
				if w.current_cof != base or w.current_tire_stiffness != 1000000.0 + 8000000.0 * w.tire_stiffnesses[w.surface_type]:
					_fail("dry: wheel %d friction %.4f, GEVP's own is %.4f (must match to the bit)" % [i, w.current_cof, base])
			"wet":
				var ratio := w.current_cof / base
				if ratio > SurfaceFeel.WET[K.ASPHALT][SurfaceFeel.PEAK] + 0.001 or ratio < 0.6:
					_fail("wet: wheel %d friction is %.3f of dry, expected about %.2f" % [i, ratio, SurfaceFeel.WET[K.ASPHALT][SurfaceFeel.PEAK]])
			"shoulder":
				if right and feel.kind[i] != K.GRIT:
					_fail("shoulder: right wheel %d on %s, expected grit" % [i, SurfaceMap.NAMES[feel.kind[i]]])
				if not right and feel.kind[i] == K.GRIT:
					_fail("shoulder: left wheel %d reads grit" % i)
				if right and not (w.current_cof < base * 0.95):
					_fail("shoulder: right wheel %d friction %.3f, expected under 95%% of %.3f" % [i, w.current_cof, base])
	match name:
		"dry":
			if grit_seen > 0.02 or wet_seen > 0.02 or rumble_seen > 0.02:
				_fail("dry: grit %.2f / water %.2f sound or camera rumble %.2f on clean dry asphalt" % [grit_seen, wet_seen, rumble_seen])
		"wet":
			if wet_seen < 0.3:
				_fail("wet: water sound only reached %.2f at 108 km/h" % wet_seen)
		"shoulder":
			if grit_seen < 0.15:
				_fail("shoulder: grit sound only reached %.2f" % grit_seen)
			if rumble_seen < 0.05 or rumble_seen > 0.3:
				_fail("shoulder: camera rumble %.2f, expected a light 0.05..0.3" % rumble_seen)
			if p.surface_feel.lays_rubber(0) and p.surface_feel.lays_rubber(1) and p.surface_feel.lays_rubber(2) and p.surface_feel.lays_rubber(3):
				_fail("shoulder: every wheel would still lay rubber")

func _check_stop(name: String, turned: float) -> void:
	if name == "off":
		return
	var dry: float = stop_dist.get("dry", 0.0)
	var mine: float = stop_dist[name]
	if name == "dry":
		var off: float = stop_dist.get("off", 0.0)
		if absf(mine - off) > off * 0.05:
			_fail("dry stop %.1f m is more than 5%% off the %.1f m without SurfaceFeel" % [mine, off])
		return
	if name == "wet" and not (mine > dry * 1.08):
		_fail("wet stop %.1f m is not clearly longer than the dry %.1f m" % [mine, dry])
	if name == "shoulder":
		if mine < dry:
			_fail("shoulder stop %.1f m is shorter than the dry %.1f m" % [mine, dry])
		# Two wheels on grit tug the car (toward the shoulder rolling, away from
		# it under the brakes); a little steering holds it, none is not an option.
		if off_line_max > 0.35 or turned > 12.0:
			_fail("shoulder: with steering the car still left its line by %.2f m and turned %.1f deg" % [off_line_max, turned])
		var effort := steer_sum / float(maxi(steer_n, 1))
		if effort < 0.002 or effort > 0.25:
			_fail("shoulder: mean steering to hold the line %.4f of full lock, expected a tug of 0.002..0.25" % effort)

func _finish() -> bool:
	if slide_ticks.has("flick_dry") and slide_ticks.has("flick_wet"):
		if not (slide_ticks.flick_wet > slide_ticks.flick_dry):
			_fail("the wet flick slid for %d ticks, the dry one %d: wet should slide longer" % [slide_ticks.flick_wet, slide_ticks.flick_dry])
		if slide_peak.flick_wet < 0.5:
			_fail("the wet flick never really let go (peak slide %.2f)" % slide_peak.flick_wet)
	SurfaceMap.wetness = 0.0
	SurfaceFeel.enabled = true
	for e in logger.errors:
		_fail("logged error: " + e)
	print("surface_feel: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	OS.remove_logger(logger)
	quit(0 if fails == 0 else 1)
	return true
