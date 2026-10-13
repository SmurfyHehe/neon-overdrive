extends SceneTree

# Where a traffic tick goes (2026-10-13, cloud half of the "benchmark and
# profile" ask). Headless, so CPU only: no draw calls, no GPU time.
#
# traffic_perf.gd measures the wall time of a whole tick. This splits that tick
# into its parts by taking over the processing of the TrafficManager and of
# every TrafficCar: their own _physics_process is switched off and called from
# here, in the order the engine would (manager first, then the cars), each call
# timed with Time.get_ticks_usec(). What is left of the tick (the physics server
# step: raycasts, body integration; the player and the rest of the game) is the
# tick wall time minus those parts.
#
# It only times calls the game already makes. Nothing about the game changes
# except WHO calls them, so car physics is not touched.
#
# Also times the manager's index helpers on their own (_build_index,
# _refresh_index, _deal_ai_phases are safe to call extra times: they only
# rebuild derived tables) and counts what a tick touches: cars, cars in the
# full sim, cars on rails, nodes in the traffic subtree.
#
# Run (Linux, no GDExtension, so the GDScript GEVP fallback runs the cars):
#   godot --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/traffic/traffic_manager_profile.gd
# CARS=<n> picks the traffic count (default 16, the Medium default).

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 120
const WARMUP_TICKS := RATE * 3
const MEASURE_TICKS := RATE * 10
const PLAYER_LANE := 3
const TRAFFIC_OWN_LANES: Array[int] = [0, 1]
const MAX_SPEED := 55.0
const HELPER_EVERY := 10

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var tick := 0
var last_usec := 0
var n_cars := 16
var ready_ := false

var wall := PackedFloat32Array()
var mgr_all := PackedFloat32Array()
var mgr_move := PackedFloat32Array()  # manager ticks that recycled or woke a car
var others_ms := PackedFloat32Array()
var game_ms := PackedFloat32Array()
var player_ms := PackedFloat32Array()
var cars_sim := PackedFloat32Array()  # sum over cars in the full sim
var cars_rail := PackedFloat32Array()  # sum over cars on rails
var h_build := PackedFloat32Array()
var h_refresh := PackedFloat32Array()
var h_deal := PackedFloat32Array()
## script path -> [total ms, calls] over the measured ticks, for every other
## scripted node (taken over like the manager: switched off, called from here).
var script_ms := {}
var others: Array[Node] = []
var sim_count := 0
var rail_count := 0
var shown_count := 0

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	var env := OS.get_environment("CARS")
	if env.is_valid_int():
		n_cars = int(env)
	game = Harness.boot(self, 0, 150.0, 777)

func _setup() -> void:
	traffic = game.get("traffic")
	traffic.own_lanes_used = TRAFFIC_OWN_LANES
	var p: PlayerCar = game.get("player")
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, MAX_SPEED)
	Harness.move_player_to_lane(p, Harness.lane_x(PLAYER_LANE))
	traffic.set_car_count(n_cars)
	ready_ = true

func _timed(c: Callable) -> float:
	var t := Time.get_ticks_usec()
	c.call()
	return float(Time.get_ticks_usec() - t) / 1000.0

func _physics_process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if not ready_:
		if game.get("player") == null:
			return false
		_setup()
		last_usec = now
		return false
	tick += 1
	var measuring := tick > WARMUP_TICKS
	if measuring:
		wall.append(float(now - last_usec) / 1000.0)
	last_usec = now
	if OS.get_environment("NOTAKE") == "1":
		if tick >= WARMUP_TICKS + MEASURE_TICKS:
			print("wall only: mean %.3f" % _mean(wall))
			quit(0)
		return false
	# Take over the manager and the cars.
	traffic.set_physics_process(false)
	var d := 1.0 / RATE
	var moves_before: int = traffic.recycle_count + traffic.unbench_count
	var m := _timed(func() -> void: traffic._physics_process(d))
	var moved: bool = traffic.recycle_count + traffic.unbench_count != moves_before
	var pl: PlayerCar = game.get("player")
	pl.set_physics_process(false)
	game.set_physics_process(false)
	var g_ms := _timed(func() -> void: game._physics_process(d))
	var p_ms := _timed(func() -> void: pl._physics_process(d))
	var sim_ms := 0.0
	var rail_ms := 0.0
	var ns := 0
	var nr := 0
	var nshown := 0
	for car in traffic.cars:
		car.set_physics_process(false)
		var det: bool = car.detailed
		var ms := _timed(func() -> void: car._physics_process(d))
		if det:
			sim_ms += ms
			ns += 1
		else:
			rail_ms += ms
			nr += 1
		if car.visible:
			nshown += 1
	if tick % 60 == 1:
		_collect_others()
	var other_ms := 0.0
	for n in others:
		if not is_instance_valid(n):
			continue
		var ms := 0.0
		var key: String = n.get_script().resource_path
		if n.has_method("_physics_process") and n.is_physics_processing():
			n.set_physics_process(false)
			var t := Time.get_ticks_usec()
			n._physics_process(d)
			ms += float(Time.get_ticks_usec() - t) / 1000.0
			key += " (physics)"
		if n.has_method("_process") and n.is_processing():
			n.set_process(false)
			var t2 := Time.get_ticks_usec()
			n._process(d)
			ms += float(Time.get_ticks_usec() - t2) / 1000.0
			key += " (process)"
		other_ms += ms
		if measuring:
			var e: Array = script_ms.get(key, [0.0, 0])
			e[0] += ms
			e[1] += 1
			script_ms[key] = e
	if measuring:
		mgr_all.append(m)
		if moved:
			mgr_move.append(m)
		others_ms.append(other_ms)
		game_ms.append(g_ms)
		player_ms.append(p_ms)
		cars_sim.append(sim_ms)
		cars_rail.append(rail_ms)
		sim_count += ns
		rail_count += nr
		shown_count += nshown
		# The full pass is the one that ends in _life_step; telling the two kinds apart
		# by cost is enough: the light tick is under a third of the full one.
		if tick % HELPER_EVERY == 0:
			h_build.append(_timed(traffic._build_index))
			h_refresh.append(_timed(traffic._refresh_index))
			h_deal.append(_timed(traffic._deal_ai_phases))
	if tick >= WARMUP_TICKS + MEASURE_TICKS:
		return _end()
	return false

func _mean(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(1.0, a.size())

func _row(name: String, a: PackedFloat32Array, per_tick := true) -> void:
	var s := Harness.stats(a)
	print("  %-34s mean %6.3f  p50 %6.3f  p95 %6.3f  max %7.3f ms%s" % [name, s.mean, s.p50, s.p95, s.max, " per tick" if per_tick else " per call"])

func _end() -> bool:
	var n := float(wall.size())
	print("traffic_manager_profile: %d traffic cars, %d Hz, %d measured ticks, CPU %s" % [n_cars, RATE, wall.size(), OS.get_processor_name()])
	print("  GDExtension neon_sim loaded: %s (false = GDScript GEVP fallback runs the cars)" % str(ClassDB.class_exists(&"CarSim") or ClassDB.class_exists(&"GevpTyreNative")))
	print("  cars per tick: %.1f in the full sim, %.1f on rails, %.1f drawn" % [sim_count / n, rail_count / n, shown_count / n])
	print("  nodes under the traffic manager: %d" % _count_nodes(traffic))
	_census()
	# Split mgr ticks into full pass / light pass by the median: full passes cost
	# several times more than light ones.
	var s := Harness.stats(mgr_all)
	var full := PackedFloat32Array()
	var light := PackedFloat32Array()
	for v in mgr_all:
		if v > s.p50 * 2.0 and v > 0.05:
			full.append(v)
		else:
			light.append(v)
	_row("tick wall (everything)", wall)
	_row("traffic manager (all ticks)", mgr_all)
	_row("  full bookkeeping ticks", full)
	_row("  light ticks", light)
	_row("  ticks that moved a car (recycle)", mgr_move)
	_row("player car script", player_ms)
	_row("game.gd _physics_process", game_ms)
	_row("cars in the full sim (sum)", cars_sim)
	_row("cars on rails (sum)", cars_rail)
	_row("_build_index() alone", h_build, false)
	_row("_refresh_index() alone", h_refresh, false)
	_row("_deal_ai_phases() alone", h_deal, false)
	_row("all other scripted physics nodes", others_ms)
	var ranked := []
	for k in script_ms:
		ranked.append([k, script_ms[k][0] / n, script_ms[k][1] / n])
	ranked.sort_custom(func(a, b) -> bool: return a[1] > b[1])
	print("  top scripted physics nodes, mean ms per tick (calls per tick in brackets):")
	for i in mini(12, ranked.size()):
		print("    %7.3f  [%5.1f]  %s" % [ranked[i][1], ranked[i][2], ranked[i][0]])
	var mw := _mean(wall)
	var parts := _mean(mgr_all) + _mean(cars_sim) + _mean(cars_rail) + _mean(player_ms) + _mean(game_ms) + _mean(others_ms)
	print("  share of the tick: manager %.1f%%  player %.1f%%  game %.1f%%  sim cars %.1f%%  rail cars %.1f%%  rest (physics server step, other nodes) %.1f%%" % [
		100.0 * _mean(mgr_all) / mw, 100.0 * _mean(player_ms) / mw, 100.0 * _mean(game_ms) / mw, 100.0 * _mean(cars_sim) / mw, 100.0 * _mean(cars_rail) / mw, 100.0 * (mw - parts) / mw])
	print("  full ticks %d of %d" % [full.size(), mgr_all.size()])
	for e in logger.errors:
		printerr("FAIL: logged error: ", e)
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	OS.remove_logger(logger)
	quit(0 if logger.errors.is_empty() else 1)
	return true

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c

## What the renderer would be handed, counted from the scene tree (headless
## draws nothing, so these are proxies for draw calls, not draw calls): visible
## mesh surfaces, MultiMesh instances and their instance counts, lights.
func _census() -> void:
	var c := {"nodes": 0, "mesh_inst": 0, "mesh_surf": 0, "mm_inst": 0, "mm_instances": 0, "lights": 0, "bodies": 0}
	var traffic_c := {"mesh_inst": 0, "mesh_surf": 0}
	_walk(get_root(), c, traffic_c, false)
	print("  scene census (proxy for draw calls; headless draws none): %d nodes, %d visible MeshInstance3D (%d surfaces), %d MultiMeshInstance3D (%d instances), %d lights, %d physics bodies" % [
		c.nodes, c.mesh_inst, c.mesh_surf, c.mm_inst, c.mm_instances, c.lights, c.bodies])
	var drawn := 0
	for car in traffic.cars:
		if car.visible:
			drawn += 1
	print("  traffic cars: %d visible MeshInstance3D / %d surfaces over %d cars (%.1f / %.1f per car; every one a separate draw call on the Mobile renderer)" % [
		traffic_c.mesh_inst, traffic_c.mesh_surf, traffic.cars.size(),
		float(traffic_c.mesh_inst) / maxf(1.0, traffic.cars.size()), float(traffic_c.mesh_surf) / maxf(1.0, traffic.cars.size())])

func _walk(n: Node, c: Dictionary, t: Dictionary, in_traffic: bool) -> void:
	c.nodes += 1
	var now_in := in_traffic or n == traffic
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null:
			c.mesh_inst += 1
			c.mesh_surf += mi.mesh.get_surface_count()
			if now_in:
				t.mesh_inst += 1
				t.mesh_surf += mi.mesh.get_surface_count()
	elif n is MultiMeshInstance3D:
		var mm := n as MultiMeshInstance3D
		if mm.is_visible_in_tree() and mm.multimesh != null:
			c.mm_inst += 1
			c.mm_instances += mm.multimesh.visible_instance_count if mm.multimesh.visible_instance_count >= 0 else mm.multimesh.instance_count
	elif n is Light3D and (n as Light3D).is_visible_in_tree():
		c.lights += 1
	elif n is CollisionObject3D:
		c.bodies += 1
	for ch in n.get_children():
		_walk(ch, c, t, now_in)

## Every other scripted node that runs _physics_process (not the manager, the
## cars, the player or game.gd, which are timed above), physics or idle process. Found by walking the tree.
func _collect_others() -> void:
	others.clear()
	_find_others(get_root())

func _find_others(n: Node) -> void:
	if n is TrafficCar or n == game.get("player"):
		return  # timed above; their wheels run inside the car's own step
	if n != traffic and n != game and n != game.get("player") and not (n is TrafficCar) and n.get_script() != null and n != self and ((n.has_method("_physics_process") and n.is_physics_processing()) or (n.has_method("_process") and n.is_processing())):
		others.append(n)
	for ch in n.get_children():
		_find_others(ch)
