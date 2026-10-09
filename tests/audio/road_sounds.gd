extends SceneTree

# Road sounds test (2026-10-08, Roy's small ideas), headless and silent:
# - highway joints: a front and a rear hit every CarAudio.JOINT_SPACING m, so
#   at 20 m/s for 3 s about 2 x 60 / 15 = 8, and the chase camera gets bumps
# - a manhole cover in the left wheels' path: one clank per left wheel
# - a bridge deck zone brings the metal hum up, leaving it lets it go
# - radio in a tunnel: reception falls to nothing and the music drops out;
#   back outside it recovers; under a bridge it breaks up with drop-outs
# - cooling ticks: hot engine switched off while stopped ticks, quickly at
#   first and slower later; a cold engine doesn't
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/road_sounds.gd

const TIMEOUT := 90.0

var fails := 0
var game: Node
var t := 0.0
var step := "boot"
var step_t := 0.0
var p: PlayerCar
var car: CarAudio
var drive: DrivelineAudio
var cam: ChaseCamera
var radio: RadioManager
var zone: SoundZone
var vals := {}
var quit_in := 0

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
	c.throttle_input = vals.get("throttle", 0.0)
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = TrafficCar.lane_steer(c, c.global_position.x if not vals.has("lane") else vals.lane, -1.0, 2.5) if c.current_speed() > 2.0 else 0.0

func _zone(kind: SoundZone.Kind, at: Vector3, box: Vector3) -> SoundZone:
	var z := SoundZone.make(kind, box)
	game.add_child(z)
	z.global_position = at
	return z

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
				if c is DrivelineAudio: drive = c
			cam = game.get("camera")
			radio = game.get("radio")
			_check(car != null and drive != null and cam != null and radio != null, "missing a sound node")
			if fails > 0:
				_finish()
				return false
			vals.j0 = car.joint_count
			vals.bump = 0.0
			_go("joints")
		"joints":
			car.forced = {"speed": 20.0, "on_road": 1.0}
			vals.bump = maxf(vals.bump, cam.bump)
			if step_t >= 3.0:
				var n: int = car.joint_count - vals.j0
				print("joints: %d axle hits in 3 s at 20 m/s (expect ~8), camera bump max %.2f" % [n, vals.bump])
				_check(n >= 6 and n <= 10, "joints at 20 m/s for 3 s: %d axle hits, expected about 8" % n)
				_check(vals.bump > 0.1, "joints should bump the camera (%.2f)" % vals.bump)
				car.forced = {}
				_go("manhole_setup")
		"manhole_setup":
			# a real drive at ~12 m/s, a cover where the left wheels will roll
			var left_x := 0.0
			var n := 0
			for w in p.wheel_array:
				if p.to_local(w.global_position).x < 0.0:
					left_x += w.global_position.x
					n += 1
			left_x /= maxf(n, 1)
			vals.lane = p.global_position.x
			p.linear_velocity = -p.global_transform.basis.z * 12.0
			vals.throttle = 0.3
			var ahead := p.global_position - p.global_transform.basis.z * 20.0
			zone = _zone(SoundZone.Kind.MANHOLE, Vector3(left_x, ahead.y - 0.3, ahead.z), Vector3(0.9, 1.6, 0.9))
			vals.m0 = car.manhole_count
			_go("manhole")
		"manhole":
			if step_t >= 3.0:
				var n: int = car.manhole_count - vals.m0
				print("manhole: %d clank(s) driving over a cover with the left wheels" % n)
				_check(n == 2, "a cover under the left wheels should clank twice (front and rear), got %d" % n)
				zone.queue_free()
				vals.throttle = 0.0
				vals.erase("lane")
				zone = _zone(SoundZone.Kind.BRIDGE_DECK, p.global_position, Vector3(30.0, 10.0, 400.0))
				_go("deck")
		"deck":
			car.forced = {"speed": 20.0, "on_road": 1.0, "deck": 1.0 if step_t < 1.5 else 0.0}
			if step_t > 1.4 and not vals.has("deck_on"):
				vals.deck_on = car.deck_level
			if step_t >= 3.0:
				print("bridge deck hum: %.2f on the deck, %.2f after" % [vals.deck_on, car.deck_level])
				_check(vals.deck_on > 0.5, "the bridge deck should hum (%.2f)" % vals.deck_on)
				_check(car.deck_level < 0.05, "the hum should go after the deck (%.2f)" % car.deck_level)
				zone.queue_free()
				car.forced = {}
				# the zone check on the real car: a deck zone around it
				zone = _zone(SoundZone.Kind.BRIDGE_DECK, p.global_position, Vector3(30.0, 10.0, 400.0))
				_go("deck_zone")
		"deck_zone":
			if step_t > 0.3:
				_check(SoundZone.find(SoundZone.Kind.BRIDGE_DECK, p.global_position) != null, "the car should be inside the deck zone")
				zone.queue_free()
				radio.next_station()   # tune the first station so drop-outs can happen
				zone = _zone(SoundZone.Kind.TUNNEL, p.global_position, Vector3(40.0, 20.0, 400.0))
				vals.d0 = radio.dropout_count
				_go("tunnel")
		"tunnel":
			if step_t >= 2.5:
				print("tunnel: reception %.2f, music share %.2f, drop-outs %d" % [radio.reception, radio.signal_gain(), radio.dropout_count - vals.d0])
				_check(radio.reception < 0.05 and radio.signal_gain() < 0.01, "in a tunnel the radio should lose the signal")
				zone.queue_free()
				_go("out")
		"out":
			if step_t >= 2.0:
				print("out of the tunnel: reception %.2f, music share %.2f" % [radio.reception, radio.signal_gain()])
				_check(radio.reception > 0.9 and radio.signal_gain() > 0.9, "the radio should come back after the tunnel")
				zone = _zone(SoundZone.Kind.UNDER_BRIDGE, p.global_position, Vector3(40.0, 20.0, 400.0))
				vals.d0 = radio.dropout_count
				_go("bridge")
		"bridge":
			if step_t >= 4.0:
				var d: int = radio.dropout_count - vals.d0
				print("under a bridge: reception %.2f, %d drop-outs in 4 s" % [radio.reception, d])
				_check(absf(radio.reception - 0.35) < 0.05, "under a bridge reception should sit near 0.35 (%.2f)" % radio.reception)
				_check(d >= 2, "under a bridge the radio should drop out now and then (%d)" % d)
				zone.queue_free()
				p.linear_velocity = Vector3.ZERO
				drive.heat = 1.0
				p.engine_running = false
				vals.k0 = drive.tick_count
				_go("cool")
		"cool":
			if step_t >= 5.0 and not vals.has("early"):
				vals.early = drive.tick_count - vals.k0
				drive.cooling = 40.0  # jump ahead: 40 s after stopping
				vals.k1 = drive.tick_count
			if step_t >= 10.0:
				var late: int = drive.tick_count - vals.k1
				print("cooling ticks: %d in the first 5 s, %d in 5 s from 40 s on" % [vals.early, late])
				_check(vals.early >= 6, "a hot engine should tick quickly just after stopping (%d in 5 s)" % vals.early)
				_check(late < vals.early, "ticks should slow down as it cools (%d then %d)" % [vals.early, late])
				drive.heat = 0.0
				drive.cooling = 0.0
				vals.k2 = drive.tick_count
				_go("cold")
		"cold":
			if step_t >= 3.0:
				_check(drive.tick_count == vals.k2, "a cold engine should not tick")
				p.engine_running = true
				_finish()
	return false

func _finish() -> void:
	if quit_in > 0 or game == null:
		return
	print("road_sounds: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	game.queue_free()
	game = null
	quit_in = 30
