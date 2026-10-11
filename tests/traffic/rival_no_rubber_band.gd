extends SceneTree

# Rival driver: no rubber band (rival driver build spec, step 1). The same
# seeded bendy road, no traffic, driven twice in one run: once with the player
# held 150 m BEHIND the rival, once held 150 m AHEAD of it, in the rival's own
# lane both times (outside the 30 m in which the rival treats the player as a
# car in the way). The rival's throttle, brake and steering are logged every
# physics tick for 60 s. The two logs must be identical, value for value: the
# driver does not know where the player is.
#
# Exit code 1 on failure. Run (about 2 min):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --path . -s res://tests/traffic/rival_no_rubber_band.gd

const R := preload("res://tests/traffic/rival_harness.gd")

const SECONDS := 60
## Player's road distance minus the rival's. 150 m, not the spec's 300: the
## game only builds the road 200 m behind and 300 m ahead of the player, and a
## rival past that drives on bare ground (no kerbs, drains or puddles), which
## is a different road, not a different driver.
const OFFSETS: Array[float] = [-150.0, -150.0]
const START_S := 200.0
const LANE := 1

var failures: Array[String] = []
var game: Node
var rival: TrafficCar
var phase := 0
var state := 0      # 0 boot, 1 wait for the tick to line up, 2 running, 3 tearing down
var wait := 0
var n := 0
var logs: Array[PackedFloat32Array] = []
var metres: Array[float] = []
var braked: Array[int] = []
var where: Array[PackedFloat32Array] = []
var player_y := 0.0
var warm_up := true

func _initialize() -> void:
	R.env([], 5)
	OS.set_environment("NEON_RACE_SEED", "99")
	state = 3
	wait = 100

func _physics_process(_delta: float) -> bool:
	wait += 1
	match state:
		0:
			if wait == 30 and warm_up:
				# The first game a process boots fills one-time caches and draws
				# from the global random stream doing it, so what it scatters on
				# the road (drains, patches) lands differently from every later
				# boot. Both measured runs are later boots.
				warm_up = false
				R.teardown(game)
				game = null
				wait = 0
				state = 3
			elif wait == 30:
				if not R.ready(game):
					_fail("run %d: the game did not boot in 30 ticks" % phase)
					return _finish()
				player_y = RoadFrame.unroll(game.player.global_position).y
				R.hold_player(game.player)
				state = 1
		1:
			# Both runs: the game boots on a tick that is a multiple of 120 and
			# the rival starts exactly 240 ticks later, so every staggered clock
			# (AI stride, plan tick, traffic bookkeeping) and everything the game
			# times from its own boot lines up the same way.
			if wait == 240:
				rival = R.spawn_rival(game, "p2_hothatch", LANE, START_S, 30.0, 0.84, 99)
				logs.append(PackedFloat32Array())
				where.append(PackedFloat32Array())
				braked.append(0)
				n = 0
				state = 2
				_park()
		2:
			var run_log := logs[phase]
			run_log.append(rival.throttle_input)
			run_log.append(rival.brake_input)
			run_log.append(rival.steering_input)
			logs[phase] = run_log
			var w := where[phase]
			w.append(R.s_of(rival))
			w.append(RoadFrame.unroll(rival.global_position).x)
			w.append(rival.racer.line_error)
			w.append(rival.current_speed())
			where[phase] = w
			if rival.brake_input > 0.05:
				braked[phase] += 1
			n += 1
			_park()
			if not rival.detailed:
				_fail("run %d: the rival left the full sim at tick %d" % [phase, n])
			if n >= SECONDS * 120:
				metres.append(R.s_of(rival) - START_S)
				if rival.wrecked:
					_fail("run %d: the rival wrecked" % phase)
				print("run %d (player %+.0f m): rival drove %.0f m in %d s, braking on %d ticks, %s" % [
					phase, OFFSETS[phase], metres[phase], SECONDS, braked[phase], rival.racer.cost_summary()])
				R.teardown(game)
				game = null
				rival = null
				phase += 1
				wait = 0
				state = 3
		3:
			if phase >= OFFSETS.size():
				return _finish()
			if wait > 20 and Engine.get_physics_frames() % 120 == 0:
				game = R.boot(self)
				wait = 0
				state = 0
	return false

func _park() -> void:
	R.park_player(game.player, TrafficManager.lane_centre(LANE, false), R.s_of(rival) + OFFSETS[phase], player_y)

func _finish() -> bool:
	var a := logs[0]
	var b := logs[1]
	if a.size() != b.size():
		_fail("logs differ in length (%d vs %d)" % [a.size(), b.size()])
	else:
		var first := -1
		var worst := 0.0
		for i in a.size():
			var d := absf(a[i] - b[i])
			if d > 0.0 and first < 0:
				first = i
			worst = maxf(worst, d)
		if first >= 0:
			@warning_ignore("integer_division")
			_fail("inputs differ: first at tick %d (%s, %.6f vs %.6f), %.0f m down the road, largest difference %.6f" % [
				first / 3, ["throttle", "brake", "steer"][first % 3], a[first], b[first], where[0][first / 3 * 4], worst])
			for t in range(first / 3 - 6, first / 3 + 3):
				print("tick %d: s %.2f x %.3f err %.3f v %.2f | x %.3f err %.3f v %.2f | steer %.5f %.5f" % [t, where[0][t * 4], where[0][t * 4 + 1], where[0][t * 4 + 2], where[0][t * 4 + 3], where[1][t * 4 + 1], where[1][t * 4 + 2], where[1][t * 4 + 3], a[t * 3 + 2], b[t * 3 + 2]])
		else:
			@warning_ignore("integer_division")
			print("inputs identical over %d ticks x 3 values, player 150 m behind vs 150 m ahead" % (a.size() / 3))
	if metres.size() == 2 and absf(metres[0] - metres[1]) > 0.001:
		_fail("the rival covered %.3f m with the player behind and %.3f m with the player ahead" % [metres[0], metres[1]])
	if metres.size() == 2 and metres[0] < 1500.0:
		_fail("the rival barely drove (%.0f m in %d s)" % [metres[0], SECONDS])
	RoadAlignment.scripted = []
	print("rival_no_rubber_band: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _fail(what: String) -> void:
	if failures.size() < 20:
		failures.append(what)
		printerr("FAIL: ", what)
