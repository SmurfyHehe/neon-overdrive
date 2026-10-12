extends SceneTree

# No roll ends a run (TM2, 2026-10-11): scripts/car/roll_righting.gd on the
# booted game, with the game's own RunEnd taking the roll's step.
#
# - ROOF: a car placed on its roof at rest is righted 3.0 s (+- 1 tick) after
#   it comes to rest, at the same spot and heading, lands on four wheels, never
#   rises faster than 3 m/s or bounces over 0.3 m after it is let go, and the
#   meter goes up 0.25 once.
# - SIDE: in the open the car does not stay on its side (it falls back onto
#   its wheels by itself: nothing righted, nothing charged); held on its side
#   by a wall it is righted the same way (WALL).
# - SLIDE: on its roof and still moving it is left alone until it stops (a
#   real slide, and the same from raw numbers for a 5 s tumble).
# - TWICE: two separate rolls add twice; going over again before it has been
#   upright for 1 s is the same roll and adds once.
# - WALL: on its side with its floor against the wall, it ends upright within
#   3 m, on the road side of the wall and not in it.
# - TOTAL: a roll at 0.80 totals the car (TM1's sequence runs), and a roll
#   during the sequence does nothing.
# - KINDS: the truck's roll is 0.20, the lowrider's 0.50, each booted and
#   rolled for real.
# - OFF: with the meter off (Wrecks = Off) the car is still righted and
#   nothing is charged.
#   <godot> --headless --fixed-fps 120 --path . -s res://tests/car/roll_righting.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const RunEnd := preload("res://scripts/core/run_end.gd")
const RollRighting := preload("res://scripts/car/roll_righting.gd")
const TotalledMeter := preload("res://scripts/car/totalled_meter.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const ROOT := "user://test_roll_righting"
const RATE := 120
const HOLD := 360   # 3.0 s at 120 Hz
const YAW := 0.35   # the cars are laid down a little across the road

var failures: Array[String] = []
var game: Node
var p: PlayerCar
var rr: Node
var run_end: Node
var home := Transform3D.IDENTITY
var totals := 0
var worst_up := 0.0
var worst_bounce := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_WRECK", "1")  # the meter counts (Game.wrecks_on)
	Engine.physics_ticks_per_second = RATE
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveStore.select_slot(1)
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
		d.remove(sub)

static func _coast(c: Vehicle) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.steering_input = 0.0
	c.handbrake_input = 0.0

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame

func _boot(kind: String) -> void:
	if game != null:
		game.queue_free()
		await _ticks(2)
	OS.set_environment("NEON_CAR", kind)
	game = Harness.boot(self, 0, 150.0, 79)
	await _ticks(RATE * 2)
	p = game.get("player")
	rr = game.get("roll_righting")
	run_end = game.get("run_end")
	run_end.restart_on_finish = false
	totals = 0
	run_end.totalled_started.connect(func(_loss: int, _free: bool) -> void: totals += 1)
	p.driver = _coast
	home = p.global_transform

## Upright and still at the start spot, the meter at `meter`, long enough for
## the last roll to be over.
func _reset(meter: float = 0.0) -> void:
	if game.game_state.state != GameState.State.PLAYING:
		game.game_state._set_state(GameState.State.PLAYING)
	_put(home, Vector3.ZERO)
	p.damage.garage_repair(null)
	p.damage.totalled = meter
	await _ticks(RATE * 2)
	_check(not rr.in_roll and rr.phase == RollRighting.Phase.WATCH, "the roll is over 2 s after the car is upright")

func _put(xf: Transform3D, vel: Vector3) -> void:
	p.global_transform = xf
	TrafficCar.set_moving(p, 0.0)
	p.linear_velocity = vel
	p.angular_velocity = Vector3.ZERO
	p.reset_physics_interpolation()

## The car laid down `up` metres over where it stands: roll PI is on its roof,
## PI/2 on its side.
func _lay(roll: float, up: float, vel: Vector3 = Vector3.ZERO) -> void:
	var b := home.basis * Basis(Vector3.UP, YAW) * Basis(Vector3.FORWARD, roll)
	_put(Transform3D(b, home.origin + Vector3(0.0, up, 0.0)), vel)

## Waits for the car to be righted. Returns what happened:
##   started   whether the move began at all
##   rest      ticks it lay tipped and at rest, in a row, before the move
##   moving    ticks it was tipped and NOT at rest before the move
##   early     the move began while it was still moving
##   from/to   the transforms the move began and ended at
##   up        peak upward speed after it was let go, m/s
##   bounce    the highest the origin got over where it came to rest, m
##   wheels    wheels on the ground at the end
## `watch_secs` is how long the drop is watched after the car is let go.
func _roll(label: String, watch_secs: float = 3.0, max_secs: float = 12.0) -> Dictionary:
	var r := {"started": false, "rest": 0, "moving": 0, "early": false, "up": 0.0, "bounce": 0.0, "wheels": 0}
	var began := [false]
	var ended := [false]
	var on_start := func() -> void: began[0] = true
	var on_end := func(_m: float, _resc: bool) -> void: ended[0] = true
	rr.righting_started.connect(on_start)
	rr.righted.connect(on_end)
	var rest := 0
	var was_moving := false
	for i in int(max_secs * RATE):
		# What the rule will see on this tick (it runs after this signal).
		var tipped: bool = p.global_transform.basis.y.y < RollRighting.TIP_UP
		var slow: bool = p.linear_velocity.length() * 3.6 < RollRighting.REST_KMH
		rest = rest + 1 if tipped and slow else 0
		was_moving = tipped and not slow
		if was_moving:
			r.moving += 1
		var from := p.global_transform
		await physics_frame
		if began[0]:
			r.started = true
			r.rest = rest
			r.early = was_moving
			r.from = from
			break
	rr.righting_started.disconnect(on_start)
	_check(r.started, "%s: the car is righted" % label)
	if not r.started:
		print("roll_righting: %s: not righted: up axis %.3f, %.2f km/h, %d ticks at rest, %d ticks moving" % [label, p.global_transform.basis.y.y, p.linear_velocity.length() * 3.6, rest, r.moving])
		rr.righted.disconnect(on_end)
		return r
	var lift := 0
	while not ended[0] and lift < RATE * 2:
		await physics_frame
		lift += 1
	rr.righted.disconnect(on_end)
	r.lift = lift
	r.to = p.global_transform
	var ys := PackedFloat32Array()
	for i in int(watch_secs * RATE):
		await physics_frame
		r.up = maxf(r.up, p.linear_velocity.y)
		ys.append(p.global_position.y)
	var rest_y := ys[ys.size() - 1]
	for y in ys:
		r.bounce = maxf(r.bounce, y - rest_y)
	for w in p.wheel_array:
		if (w as Wheel).is_colliding():
			r.wheels += 1
	worst_up = maxf(worst_up, r.up)
	worst_bounce = maxf(worst_bounce, r.bounce)
	print("roll_righting: %s: at rest %d ticks, moved in %d ticks, peak up %.2f m/s, highest %.3f m over rest, %d wheels down, up axis %.3f"
		% [label, r.rest, lift, r.up, r.bounce, r.wheels, p.global_transform.basis.y.y])
	return r

## The checks every righting shares.
func _landed(label: String, r: Dictionary, same_spot: bool = true) -> void:
	if not r.started:
		return
	_check(absi(r.rest - HOLD) <= 1, "%s: righted 3.0 s after it came to rest (%d ticks, want %d +- 1)" % [label, r.rest, HOLD])
	_check(absi(r.lift - RollRighting.ticks(RollRighting.LIFT_SECS)) <= 1, "%s: the move takes 0.6 s (%d ticks)" % [label, r.lift])
	_check(r.wheels == p.wheel_array.size(), "%s: it lands on all its wheels (%d)" % [label, r.wheels])
	_check(p.global_transform.basis.y.y > 0.95, "%s: it ends upright (%.3f)" % [label, p.global_transform.basis.y.y])
	_check(r.up < 3.0, "%s: peak upward speed under 3 m/s (%.2f)" % [label, r.up])
	_check(r.bounce < 0.3, "%s: never over 0.3 m above where it rests (%.3f)" % [label, r.bounce])
	_check(Harness.finite(p), "%s: finite" % label)
	if same_spot:
		var a: Transform3D = r.from
		var b: Transform3D = r.to
		var flat := Vector2(b.origin.x - a.origin.x, b.origin.z - a.origin.z).length()
		_check(flat < 0.05, "%s: same spot on the road (%.3f m off)" % [label, flat])
		var fa := Vector2(-a.basis.z.x, -a.basis.z.z).normalized()
		var fb := Vector2(-b.basis.z.x, -b.basis.z.z).normalized()
		_check(fa.dot(fb) > cos(deg_to_rad(2.0)), "%s: same heading (%.1f deg off)" % [label, rad_to_deg(acos(clampf(fa.dot(fb), -1.0, 1.0)))])
		_check(absf(b.basis.y.y - 1.0) < 0.001, "%s: let go level (%.4f)" % [label, b.basis.y.y])

func _meter_is(label: String, want: float) -> void:
	_check(is_equal_approx(p.damage.totalled, want), "%s: the meter is %.2f (is %.3f)" % [label, want, p.damage.totalled])

func _run() -> void:
	_numbers()
	await _boot("")
	_check(rr != null and run_end != null, "the game has the righting rule and the run end")
	if rr == null or run_end == null:
		_end()
		return
	var kind := PlayerCar.chassis_kind()
	_check(is_equal_approx(TotalledMeter.step_for_roll(kind), 0.25), "the default car's roll is 0.25 (%s)" % kind)
	var engine_before: Variant = p.get("engine_running")

	# ROOF
	await _reset()
	_lay(PI, 1.2)
	var r := await _roll("roof")
	_landed("roof", r)
	_meter_is("roof", 0.25)
	_check(rr.rolls == 1 and run_end.steps == 1, "roof: charged once (%d roll(s), %d step(s))" % [rr.rolls, run_end.steps])
	_check(run_end.phase == RunEnd.Phase.DRIVING and game.game_state.state == GameState.State.PLAYING, "roof: the run goes on")
	_check(p.get("engine_running") == engine_before, "roof: the engine is as it was")
	await _ticks(RATE * 4)
	_meter_is("roof, 4 s later", 0.25)
	_check(rr.rightings == 1, "roof: righted once (%d)" % rr.rightings)

	# SIDE
	# In the open this car does not stay on its side: it falls back onto its
	# wheels by itself. Then nothing is righted and nothing is charged. (The
	# car that does stay on its side, held by a wall, is WALL below.)
	await _reset()
	var before: int = rr.rightings
	_lay(PI * 0.5, 1.3)
	await _ticks(RATE * 6)
	if rr.rightings > before:
		_meter_is("side, righted", 0.25)
	else:
		print("roll_righting: side in the open: fell back onto its wheels by itself (up axis %.3f), not righted, not charged" % p.global_transform.basis.y.y)
		_check(p.global_transform.basis.y.y > 0.95, "side in the open: back on its wheels by itself")
		_meter_is("side in the open", 0.0)

	# SLIDE: on its roof at 60 km/h down the road.
	await _reset()
	_lay(PI, 1.2, -home.basis.z * (60.0 / 3.6))
	r = await _roll("slide")
	_check(not r.early, "slide: not righted while it is still moving")
	_check(r.moving > RATE / 4, "slide: it did slide (%d ticks)" % r.moving)
	_landed("slide", r)
	_meter_is("slide", 0.25)
	print("roll_righting: slide: tipped and moving for %.2f s before it stopped" % (float(r.moving) / RATE))

	# TWICE: two separate rolls.
	await _reset()
	_lay(PI, 1.2)
	r = await _roll("first of two")
	await _ticks(RATE * 2)
	_lay(PI, 1.2)
	r = await _roll("second of two")
	_landed("second of two", r)
	_meter_is("two rolls", 0.50)
	# ... and one roll that goes over again before it has been upright 1 s.
	await _reset()
	_lay(PI, 1.2)
	r = await _roll("tumble, first rest", 0.5)  # upright for 0.5 s only
	_lay(PI, 1.2)
	r = await _roll("tumble, second rest")
	_landed("tumble, second rest", r)
	_meter_is("one long tumble", 0.25)

	# WALL: on its side, floor to the own-side wall.
	await _reset()
	await _wall()

	# OFF: the meter off, the car still righted.
	await _reset()
	OS.set_environment("NEON_WRECK", "0")
	var rolls_before: int = rr.rolls
	_lay(PI, 1.2)
	r = await _roll("meter off")
	_landed("meter off", r)
	_meter_is("meter off", 0.0)
	_check(rr.rolls == rolls_before + 1, "meter off: the roll is still seen")
	OS.set_environment("NEON_WRECK", "1")

	# TOTAL: 0.80 + 0.25.
	await _reset(0.80)
	_lay(PI, 1.2)
	r = await _roll("at 0.80")
	_check(totals == 1, "at 0.80: the roll totals the car (%d)" % totals)
	_check(run_end.phase != RunEnd.Phase.DRIVING, "at 0.80: TM1's sequence runs")
	_check(p.global_transform.basis.y.y > 0.95, "at 0.80: the car is still put on its wheels")
	var rolls_at_total: int = rr.rolls
	var again := false
	for i in HOLD * 2:
		again = rr.step(-1.0, 0.0) or again
	_check(not again and rr.rolls == rolls_at_total and totals == 1, "a roll during the totalled sequence does nothing")

	# KINDS
	for k: String in ["m1_monster", "l1_lowrider"]:
		await _boot(k)
		_check(PlayerCar.chassis_kind() == k, "NEON_CAR=%s picked %s" % [k, PlayerCar.chassis_kind()])
		var want := 0.20 if k == "m1_monster" else 0.50
		_check(is_equal_approx(TotalledMeter.step_for_roll(k), want), "%s: the step is %.2f" % [k, want])
		await _reset()
		_lay(PI, 2.6 if k == "m1_monster" else 1.2)
		r = await _roll(k)
		_landed(k, r)
		_meter_is(k, want)
		_check(run_end.phase == RunEnd.Phase.DRIVING and totals == 0, "%s: a roll does not end the run" % k)
	OS.set_environment("NEON_CAR", "")
	print("roll_righting: worst peak upward speed %.2f m/s, worst height over rest %.3f m" % [worst_up, worst_bounce])
	_end()

func _wall() -> void:
	var u := RoadFrame.unroll(home.origin)
	var bounds: Vector2 = game.rescue._bounds_at(u.z)
	_check(bounds.x > 0.0, "the own-side wall is found")
	var across := RoadFrame.basis_at(u.z).x
	var fwd := -RoadFrame.basis_at(u.z).z
	# Up axis away from the wall: the floor faces it, 0.6 m off its face.
	var y := -across
	var z := -fwd
	var b := Basis(y.cross(z), y, z)
	var at := RoadFrame.roll(Vector3(bounds.x - 0.6, 1.3, u.z))
	_put(Transform3D(b, at), Vector3.ZERO)
	var r := await _roll("wall")
	if not r.started:
		return
	_landed("wall", r, false)
	var from: Transform3D = r.from
	var to: Transform3D = r.to
	var end_u := RoadFrame.unroll(to.origin)
	var shift := Vector2(to.origin.x - from.origin.x, to.origin.z - from.origin.z).length()
	print("roll_righting: wall: lay %.2f m from the wall face, put %.2f m sideways (rule says %.1f), ends %.2f m from the face, rescued %s"
		% [bounds.x - RoadFrame.unroll(from.origin).x, shift, rr.last_moved, bounds.x - end_u.x, rr.last_rescued])
	_check(rr.last_moved > 0.0 and not rr.last_rescued, "wall: its own spot was blocked and it was moved sideways")
	_check(shift <= 3.0 + 0.01, "wall: within 3 m (%.2f)" % shift)
	_check(end_u.x < bounds.x - 0.5, "wall: on the road side of the wall (%.2f m from its face)" % (bounds.x - end_u.x))
	_check(not rr._blocked(to), "wall: not inside the wall")
	_meter_is("wall", 0.25)

## The rule from raw numbers (no game): the clock, the rest speed, one charge
## per roll.
func _numbers() -> void:
	var seen: Array = []
	var n := RollRighting.new(null, "car")
	n.rolled.connect(func(s: float, counted: bool) -> void: seen.append([s, counted]))
	var fired := 0
	# A 5 s tumble: over and back, never at rest.
	for i in RATE * 5:
		if n.step(sin(float(i) * 0.05) * 0.9, 20.0):
			fired += 1
	_check(fired == 0 and seen.is_empty(), "numbers: a moving tumble is not righted or charged")
	_check(n.in_roll, "numbers: it is one roll")
	for i in HOLD - 1:
		if n.step(0.1, 1.9):
			fired += 1
	_check(fired == 0, "numbers: not righted one tick early")
	_check(n.step(0.1, 1.9) and seen.size() == 1, "numbers: righted and charged on tick %d" % HOLD)
	_check(is_equal_approx(seen[0][0], 0.25) and not seen[0][1], "numbers: a car's step is 0.25, uncounted with no run end")
	# At exactly the limits nothing counts.
	var m := RollRighting.new(null, "car")
	fired = 0
	for i in HOLD * 2:
		if m.step(0.3, 0.0) or m.step(0.1, 2.0):
			fired += 1
	_check(fired == 0, "numbers: basis.y.y 0.3 is not tipped and 2 km/h is not at rest")
	# Upright 1 s minus a tick is still the same roll; a full second ends it.
	for i in RATE - 1:
		n.step(0.9, 0.0)
	_check(n.in_roll, "numbers: upright under 1 s is the same roll")
	for i in HOLD:
		n.step(0.1, 0.0)
	_check(seen.size() == 1, "numbers: the same roll is not charged twice")
	for i in RATE:
		n.step(0.9, 0.0)
	_check(not n.in_roll, "numbers: upright 1 s ends the roll")
	for i in HOLD:
		n.step(0.1, 0.0)
	_check(seen.size() == 2, "numbers: the next roll is charged")
	n.free()
	m.free()

func _end() -> void:
	print("roll_righting: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
