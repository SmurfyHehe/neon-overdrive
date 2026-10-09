extends SceneTree

# Water in the game (Part 2 of the 2026-10-09 water note): Game.tscn in a
# downpour (NEON_WEATHER=downpour) at the game's 120 Hz, the scripted player
# holding the passing lane at 140-150 km/h, CARS traffic cars around it.
#   9  player   every tick: each tyre's water multiplier is at least 55%, an
#               axle's two wheels are within 10%, no wheel moves faster than
#               WetGrip.RATE, and what the wheel gets is health's grip times
#               the water's; the run crosses deep puddles, aquaplaning speed
#               included, and off puddles the tyres sit at the downpour's 0.80
#   10 traffic  every full-sim traffic car's wheels carry its water
#               multiplier, the same rules as the player's; with nothing
#               ahead the drivers hold no more than 85% of their dry target
#               speed (+3%), and they keep driving
#   CPU         the whole WetGrip.step() on the real cars, per car per tick,
#               under STEP_BUDGET_US
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/water_drive.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Weather := preload("res://scripts/world/weather.gd")
const Puddles := preload("res://scripts/world/puddles.gd")
const WetGrip := preload("res://scripts/car/wet_grip.gd")

const RATE := 120
const CARS := 24
const TICKS := RATE * 25
const SETTLE_TICKS := RATE * 8  # traffic eases down to its wet speed first
const TIMEOUT_TICKS := TICKS * 2
const PLAYER_LANE := 0
const LAUNCH := 140.0 / 3.6
const MAX_SPEED := 150.0 / 3.6
const EPS := 1e-4
## The whole step() on a real car, us: 5% of the cheapest full-sim car tick
## (190 us, docs/planning/world-building-vision-2026-10-07.md).
const STEP_BUDGET_US := 10.0

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var tick := 0
var fails: Array[String] = []
var prev := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
# 9
var min_mult := 1.0
var max_pair := 0.0
var max_rate := 0.0
var max_write_err := 0.0
var deep_ticks := 0
var shallow_ticks := 0
var aqua_ticks := 0
var dry_patch_err := 0.0
var top_kmh := 0.0
# 10
var npc_write_err := 0.0
var npc_rule_bad := 0
var npc_dry_patch_max := 0.0
var npc_ratios := PackedFloat32Array()
var npc_wet_ticks := 0
var npc_prev := {}
# CPU
var probe := {}
var step_n := 0
## Per tick: us per car for that tick's probe calls, all cars timed together.
## Medians, not means: on a busy laptop the main thread is sometimes switched
## out for milliseconds, and one of those in a 1 us call swamps a mean (a
## mean read 25-50 us here on 2026-10-09 with stray `find` processes running).
var tick_us := PackedFloat32Array()

func _initialize() -> void:
	OS.add_logger(logger)
	OS.set_environment("NEON_WEATHER", "downpour")
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 4242)

func _setup() -> void:
	traffic = game.get("traffic")
	traffic.own_lanes_used = [1, 2, 3]
	traffic.set_car_count(CARS)
	var p: PlayerCar = game.get("player")
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, MAX_SPEED)
	Harness.move_player_to_lane(p, Harness.lane_x(PLAYER_LANE))
	Harness.launch_player(p, LAUNCH)

func _physics_process(_delta: float) -> bool:
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		printerr("FAIL: timed out after ", Engine.get_physics_frames(), " ticks")
		quit(1)
		return true
	if traffic == null:
		if game.get("player") == null:
			return false
		_setup()
		return false
	tick += 1
	_check_player(game.get("player"))
	_check_traffic()
	if tick >= TICKS:
		_end()
	return false

## Reads the state the cars left after their own physics tick (the cars run
## after the SceneTree's _physics_process, so this sees the previous tick).
func _check_player(p: PlayerCar) -> void:
	if not Harness.finite(p):
		fails.append("non-finite player at tick %d" % tick)
		return
	if tick < 3:
		prev = p.wet.mult.duplicate()
		return
	var dt := 1.0 / RATE
	var m := p.wet.mult
	var hit_deep := false
	var hit_any := false
	for i in 4:
		min_mult = minf(min_mult, m[i])
		max_rate = maxf(max_rate, absf(m[i] - prev[i]) / dt)
		var d := p.wet.depth[i]
		hit_deep = hit_deep or d == Puddles.Depth.DEEP
		hit_any = hit_any or d != Puddles.Depth.NONE
		# What the wheel got: health's tyre grip times the water's, with the floor.
		var g: float = p.health.tyre_grip[i] if p.health.enabled else 1.0
		var want := maxf(g * m[i], minf(g, WetGrip.MIN_GRIP))
		max_write_err = maxf(max_write_err, absf(p.wheel_array[i].grip_mult - want))
	max_pair = maxf(max_pair, maxf(absf(m[0] - m[1]), absf(m[2] - m[3])))
	var speed := p.linear_velocity.length()
	top_kmh = maxf(top_kmh, speed * 3.6)
	if hit_deep:
		deep_ticks += 1
		if speed > WetGrip.AQUA_START:
			aqua_ticks += 1
	elif hit_any:
		shallow_ticks += 1
	# Well clear of water (all wheels dry, and settled since): the downpour alone.
	var still := true
	for i in 4:
		still = still and absf(m[i] - prev[i]) < 1e-6
	if not hit_any and still:
		for i in 4:
			dry_patch_err = maxf(dry_patch_err, absf(m[i] - Weather.rain_grip()))
	prev = m.duplicate()

func _check_traffic() -> void:
	var batch: Array[TrafficCar] = []
	for car: TrafficCar in traffic.cars:
		if not car.detailed or not car.visible:
			continue
		if not Harness.finite(car):
			fails.append("non-finite traffic car at tick %d" % tick)
			return
		var m := car.wet.mult
		var any_water := false
		for i in mini(4, car.wheel_array.size()):
			npc_write_err = maxf(npc_write_err, absf(car.wheel_array[i].grip_mult - m[i]))
			any_water = any_water or car.wet.depth[i] != Puddles.Depth.NONE
			if m[i] < WetGrip.MIN_GRIP - EPS:
				npc_rule_bad += 1
		if absf(m[0] - m[1]) > WetGrip.MAX_SIDE_DIFF + EPS or absf(m[2] - m[3]) > WetGrip.MAX_SIDE_DIFF + EPS:
			npc_rule_bad += 1
		# Off water and settled (unchanged since last tick): the downpour alone.
		var last: Variant = npc_prev.get(car)
		if any_water:
			npc_wet_ticks += 1
		elif last != null and last == m:
			npc_dry_patch_max = maxf(npc_dry_patch_max, maxf(maxf(m[0], m[1]), maxf(m[2], m[3])))
		npc_prev[car] = m.duplicate()
		# Free road ahead: the wet speed is the driver's choice, not a queue's.
		if tick > SETTLE_TICKS and car.lead_gap == INF and car.target_speed > 5.0 and not car.changing:
			npc_ratios.append(car.linear_velocity.length() / car.target_speed)
		batch.append(car)
	_time_steps(batch)

## CPU: the real step() on each car, on a probe of its own so the car itself
## is untouched (step() only writes the WetGrip it is called on).
func _time_steps(batch: Array[TrafficCar]) -> void:
	if batch.is_empty():
		return
	var wgs: Array[WetGrip] = []
	for car in batch:
		var wg: WetGrip = probe.get(car)
		if wg == null:
			wg = WetGrip.new()
			probe[car] = wg
		wgs.append(wg)
		# In the game the car's own _drive has already unrolled its position
		# this tick by the time step() runs (RoadFrame memoises it); here the
		# probe runs first, so warm that untimed to measure what the game pays.
		RoadFrame.unroll(car.global_position)
	var t0 := Time.get_ticks_usec()
	for k in batch.size():
		wgs[k].step(batch[k], 1.0 / RATE)
	tick_us.append(float(Time.get_ticks_usec() - t0) / batch.size())
	step_n += batch.size()

func _end() -> void:
	var dt := 1.0 / RATE
	var ok9 := min_mult >= WetGrip.MIN_GRIP - EPS and max_pair <= WetGrip.MAX_SIDE_DIFF + EPS \
		and max_rate <= WetGrip.RATE + 0.01 and max_write_err < EPS and deep_ticks > 0 and aqua_ticks > 0 \
		and dry_patch_err < 0.01
	print("%s: 9 player: lowest %.3f, widest pair %.3f, fastest change %.2f/s (limit %.1f), write error %.5f;" % [
		"PASS" if ok9 else "FAIL", min_mult, max_pair, max_rate, WetGrip.RATE, max_write_err])
	print("      ticks in deep water %d (%d above 110 km/h), shallow %d, top %.0f km/h, off-puddle error vs %.2f: %.4f" % [
		deep_ticks, aqua_ticks, shallow_ticks, top_kmh, Weather.rain_grip(), dry_patch_err])
	if not ok9:
		fails.append("9 player")
	var st := Harness.stats(npc_ratios)
	var ok10: bool = npc_write_err < EPS and npc_rule_bad == 0 and npc_dry_patch_max <= Weather.rain_grip() + EPS \
		and st.n > 100 and st.p95 <= Weather.ai_speed_factor() + 0.03 and st.p50 > 0.5
	print("%s: 10 traffic: write error %.5f, rule breaks %d, off-puddle grip max %.3f, wheel-ticks in water %d;" % [
		"PASS" if ok10 else "FAIL", npc_write_err, npc_rule_bad, npc_dry_patch_max, npc_wet_ticks])
	print("      free-road speed / dry target: p50 %.3f, p95 %.3f over %d samples (limit %.2f + 0.03)" % [
		st.p50, st.p95, st.n, Weather.ai_speed_factor()])
	if not ok10:
		fails.append("10 traffic")
	var ct := Harness.stats(tick_us)
	var okc: bool = step_n > 1000 and ct.p50 < STEP_BUDGET_US
	print("%s: CPU: WetGrip.step per car per tick: median %.2f us, p95 %.2f, mean %.2f, over %d car-ticks (budget %.1f on the median)" % [
		"PASS" if okc else "FAIL", ct.p50, ct.p95, ct.mean, step_n, STEP_BUDGET_US])
	if not okc:
		fails.append("CPU")
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: ", f)
	Weather.reset()
	quit(0 if fails.is_empty() else 1)
