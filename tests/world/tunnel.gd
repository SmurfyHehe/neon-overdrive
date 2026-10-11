extends SceneTree

# The tunnel under Downtown (TN1): road 0, s = 4250 to 4550 (chunks 85-90),
# with a 150 m ramp in an open trench at each end (chunks 82-84 and 91-93).
#
# Part 1, the map and the road's shape, no game:
# - RoadMap.tunnel_at() is true on chunks 85-90 of every lap and nowhere else,
#   in every act; the dip is chunks 82-93
# - exit 6 (x6a, x6b) is off the road while tunnels are live and back when
#   they are not; the other exits, both of district 6's median gaps and its
#   crossing stay
# - chunks 82-93 are pinned and straight for every road seed; the road is
#   level with the street at both ends of the dip, 6 m under it through the
#   middle of the tunnel (level there), never steeper than 4 %, and no crest
#   or sag is tighter than the road's own limits
# - the lap still closes (ends at the height it began)
# - nothing repeats bright enough to flicker (the strip's housing joints and
#   the wall grime stay under TunnelKit.FLICKER_MAX)
# - how deep inside the map says a point is, and what the echo and the radio
#   make of it
#
# Part 2, the real Game.tscn on the default road with hills, started 450 m
# before the mouth with 16 traffic cars: the shared test driver ("clean",
# 200 km/h, looks at traffic) drives down the ramp, through and out.
# - the tunnel and trench chunks are built as such (walls, no lamps, no
#   buildings and no kerb strips under cover, the cross street's deck at each
#   mouth), an ordinary chunk is not
# - the car never touches a wall or a building, and gets through
# - no traffic car was placed under cover
# - the echo comes up inside and is gone outside; the radio loses the signal
#   inside and has it back after
#
# Part 3, the game again with no traffic, started at the top of the ramp at
# 250 km/h and held flat out: the car keeps at least one wheel on the road
# every tick through the dip, and touches no wall.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/tunnel.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const TunnelKit := preload("res://scripts/world/tunnel_kit.gd")
const TunnelAudio := preload("res://scripts/audio/tunnel_audio.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")

const RATE := 120
const L := 50.0
const FIRST := 85          # first chunk under cover
const LAST := 90           # last
const RAMP := 3            # ramp chunks each end
const S0 := 4250.0
const S1 := 4550.0
const DIP := 6.0
const MAX_GRADE := 0.04
const TRAFFIC_CARS := 16
const TRAFFIC_START := 3800.0
const TRAFFIC_KMH := 200.0
const FAST_START := 4100.5
const FAST_MS := 250.0 / 3.6
## Where a pass ends: on the far ramp's last chunk, short of the crossing's
## stop line at 4713 m.
const PASS_END := 4690.0
const SETTLE_TICKS := RATE
const TIMEOUT_TICKS := RATE * 150

var logger := Harness.ErrorCounter.new()
var fails: Array[String] = []
var game: Node
var phase := "traffic"
var tick := 0
var started := false
var driver: RefCounted
var wall_hits := 0
var other_hits := 0
var hit_note := ""
var max_kmh := 0.0
var min_kmh_inside := INF
var air_ticks := 0
var fewest_wheels := 4
var deepest := 0.0
var echo_before := -1.0
var echo_inside := 0.0
var rx_inside := 1.0
var chunks_checked := {}
var wait_ticks := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL: ", msg)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_map()
	_shape()
	_safety()
	_sound_maths()
	# Its own road settings: run_tests.bat sets NEON_HILLS=0 for the older tests.
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_KICKERS", "0")
	OS.set_environment("NEON_ROAD", "0")
	OS.set_environment("NEON_TUNNEL", "")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_START_S", str(TRAFFIC_START))
	RoadMap.tunnel_live = true
	game = Harness.boot(self, TRAFFIC_CARS, 300.0, 777)

# ---------- part 1 ----------

func _map() -> void:
	RoadMap.tunnel_live = true
	for act in [1, 2, 3]:
		RoadMap.use(0, act)
		var n := RoadMap.period
		var wrong := 0
		var dips := 0
		for c in range(-n, 2 * n):
			var m := posmod(c, n)
			if RoadMap.tunnel_at(c) != (m >= FIRST and m <= LAST):
				wrong += 1
			var want := RoadMap.DIP_NONE
			if m >= FIRST and m <= LAST:
				want = RoadMap.DIP_TUNNEL
			elif m >= FIRST - RAMP and m <= LAST + RAMP:
				want = RoadMap.DIP_RAMP
			if RoadMap.dip_at(c) != want:
				dips += 1
		_check(wrong == 0, "act %d: tunnel_at is wrong on %d chunks of three laps" % [act, wrong])
		_check(dips == 0, "act %d: dip_at is wrong on %d chunks of three laps" % [act, dips])
		_check(RoadMap.dip_span(87 + n) == Vector2i(FIRST - RAMP + n, LAST - FIRST + 1 + 2 * RAMP), "act %d: dip_span(87 a lap on) is %s" % [act, RoadMap.dip_span(87 + n)])
		var ids := {}
		for e in RoadMap.exits():
			ids[String(e.id)] = true
		_check(not ids.has("x6a") and not ids.has("x6b"), "act %d: exit 6 is still on the road with the tunnel live" % act)
		_check(ids.has("x5a") and ids.has("x7b"), "act %d: exits 5 and 7 should be untouched" % act)
		_check(RoadMap.exits().size() == RoadMap.district_count() * 2 - 2, "act %d: %d exits for %d districts (one pair off)" % [act, RoadMap.exits().size(), RoadMap.district_count()])
		var gaps := {}
		for g in RoadMap.gaps():
			gaps[String(g.id)] = true
		_check(gaps.has("g6a") and gaps.has("g6b"), "act %d: district 6 lost a median gap" % act)
		var crossing := false
		for j in RoadMap.junctions():
			crossing = crossing or absf(j - 4725.0) < 0.5
		_check(crossing, "act %d: the crossing at 4725 m is gone" % act)
		var pins := RoadMap.pins()
		for c in range(FIRST - RAMP, LAST + RAMP + 1):
			_check(pins[c] == 1, "act %d: chunk %d is not pinned" % [act, c])
	_check(RoadMap.tunnels().size() == 1 and String(RoadMap.tunnels()[0].id) == "t1", "the road should have the one tunnel t1")
	# off: the exit is back and nothing is under cover
	RoadMap.tunnel_live = false
	RoadMap.use(0, 1)
	var back := 0
	for e in RoadMap.exits():
		if String(e.id) == "x6a" or String(e.id) == "x6b":
			back += 1
	var covered := 0
	for c in RoadMap.period:
		if RoadMap.dip_at(c) != RoadMap.DIP_NONE:
			covered += 1
	_check(back == 2, "tunnels off: exit 6 should be back (%d of 2)" % back)
	_check(covered == 0 and RoadMap.dip_vcurves().is_empty(), "tunnels off: %d chunks still dip" % covered)
	RoadMap.tunnel_live = true
	RoadMap.use(0, 1)
	print("map: tunnel on chunks %d-%d of every lap, ramps %d chunks, exit 6 off, %d exits, %d gaps, crossings %s" % [
		FIRST, LAST, RAMP, RoadMap.exits().size(), RoadMap.gaps().size(), str(RoadMap.junctions())])

func _shape() -> void:
	RoadMap.use(0, 1)
	var n := RoadMap.period
	var first := FIRST - RAMP
	var count := LAST - FIRST + 1 + 2 * RAMP
	var worst_grade := 0.0
	var worst_end := 0.0
	var worst_mid := 0.0
	var worst_close := 0.0
	var tightest_crest := INF
	var tightest_sag := INF
	var mouth_depth := 0.0
	for road_seed in [1, 37, 777, 20261010, 424242]:
		for shape in [[0.8, 0.8], [0.5, 0.5], [0.0, 0.3]]:
			var a := RoadAlignment.new(road_seed, shape[0], shape[1], 0.0, n, RoadMap.pins(), RoadMap.dip_vcurves())
			_check(a.has_hills(), "seed %d: a road with a dip has hills" % road_seed)
			worst_close = maxf(worst_close, absf(a.start_height(n) - a.start_height(0)))
			var h0 := a.start_height(first)
			var h1 := a.start_height(first + count)
			var tilt := (h1 - h0) / (float(count) * L)
			_check(absf(tilt) < 0.01, "seed %d: the street tilts %.4f across the dip" % [road_seed, tilt])
			for c in range(first, first + count):
				_check(a.curvature(c) == 0.0, "seed %d: chunk %d bends" % [road_seed, c])
				var vc := a.vcurve(c)
				if vc < 0.0:
					tightest_crest = minf(tightest_crest, -1.0 / vc)
				elif vc > 0.0:
					tightest_sag = minf(tightest_sag, 1.0 / vc)
				for k in 11:
					var s := float(k) * 5.0
					worst_grade = maxf(worst_grade, absf(a.grade_at(c, s) - tilt))
					var street := lerpf(h0, h1, (float(c - first) * L + s) / (float(count) * L))
					var depth := street - a.height_at(c, s)
					_check(depth > -0.02, "seed %d: chunk %d is %.3f m above the street %.0f m in" % [road_seed, c, -depth, s])
					if c >= FIRST + 1 and c <= LAST - 1:
						worst_mid = maxf(worst_mid, absf(depth - DIP))
					if c == FIRST and k == 0:
						mouth_depth = depth
			worst_end = maxf(worst_end, absf(a.grade_at(first, 0.0) - tilt))
			worst_end = maxf(worst_end, absf(a.grade_at(first + count, 0.0) - tilt))
	_check(worst_grade <= MAX_GRADE + 0.0005, "the dip is as steep as %.2f %% (limit %.0f %%)" % [worst_grade * 100.0, MAX_GRADE * 100.0])
	_check(worst_mid < 0.03, "the tunnel floor is up to %.3f m off %.0f m under the street" % [worst_mid, DIP])
	_check(worst_end < 0.003, "the road is not level with the street at the ends of the dip (grade off by %.4f)" % worst_end)
	_check(worst_close < 0.001, "the lap no longer ends at the height it began (%.4f m)" % worst_close)
	_check(tightest_crest >= RoadAlignment.CREST_MIN_RADIUS and tightest_sag >= RoadAlignment.SAG_MIN_RADIUS,
		"vertical radius under the road's limit: crest %.0f m, sag %.0f m" % [tightest_crest, tightest_sag])
	print("shape: steepest %.2f %%, floor within %.0f mm of %.0f m down, %.2f m down at the mouth, crest %.0f m, sag %.0f m, lap closes to %.2f mm" % [
		worst_grade * 100.0, worst_mid * 1000.0, DIP, mouth_depth, tightest_crest, tightest_sag, worst_close * 1000.0])

func _safety() -> void:
	# Brightness that repeats along the tunnel: the strip's joints, the grime.
	var joint := 1.0 - TunnelKit.JOINT_DIM
	var grime := 0.0
	for side in [1, -1]:
		var lo := INF
		var hi := 0.0
		for i in 2000:
			var g: float = TunnelKit.grime(float(i) * 0.5, side)
			lo = minf(lo, g)
			hi = maxf(hi, g)
		grime = maxf(grime, (hi - lo) / hi)
	_check(joint <= TunnelKit.FLICKER_MAX, "the strip's housing joints dim it by %.0f %%" % (joint * 100.0))
	_check(grime <= TunnelKit.FLICKER_MAX, "the wall grime changes its brightness by %.0f %%" % (grime * 100.0))
	_check(TunnelKit.JOINT_W / TunnelKit.JOINT_EVERY < 0.05, "the housing joints are not thin")
	# the slowest the grime can repeat at the fastest a car goes (400 km/h)
	var hz := 111.0 / minf(TunnelKit.GRIME_WAVES.x, TunnelKit.GRIME_WAVES.y)
	_check(hz < 2.5, "the grime repeats at %.1f Hz at 400 km/h" % hz)
	print("safety: strip joints %.0f %% dimmer and %.0f cm wide every %.0f m, grime %.1f %% peak to peak, %.1f Hz at 400 km/h" % [
		joint * 100.0, TunnelKit.JOINT_W * 100.0, TunnelKit.JOINT_EVERY, grime * 100.0, hz])

func _sound_maths() -> void:
	RoadMap.use(0, 1)
	var lap := RoadMap.length()
	_check(absf(RoadMap.tunnel_depth(S0)) < 0.001 and absf(RoadMap.tunnel_depth(S1)) < 0.001, "the mouths should be 0 m inside")
	_check(absf(RoadMap.tunnel_depth(4400.0) - 150.0) < 0.001, "the middle should be 150 m inside")
	_check(absf(RoadMap.tunnel_depth(4400.0 + 3.0 * lap) - 150.0) < 0.01, "the same on a later lap")
	_check(absf(RoadMap.tunnel_depth(4200.0) + 50.0) < 0.001 and RoadMap.tunnel_depth(100.0) < 0.0, "outside should read as outside")
	_check(TunnelAudio.amount_at(-5.0) == 0.0 and TunnelAudio.amount_at(0.0) == 0.0, "no echo outside")
	_check(TunnelAudio.amount_at(TunnelAudio.WET_RAMP) == 1.0 and TunnelAudio.amount_at(150.0) == 1.0, "full echo 20 m in")
	var half := TunnelAudio.amount_at(TunnelAudio.WET_RAMP * 0.5)
	_check(half > 0.3 and half < 0.7, "the echo should be about half way up 10 m in (%.2f)" % half)
	_check(RadioManager.reception_at_depth(-1.0) == 1.0 and RadioManager.reception_at_depth(0.0) == 1.0, "clear radio at the mouth")
	_check(absf(RadioManager.reception_at_depth(20.0) - 0.5) < 0.001, "half the signal 20 m in")
	_check(RadioManager.reception_at_depth(40.0) == 0.0 and RadioManager.reception_at_depth(150.0) == 0.0, "no signal 40 m in")
	print("sound: echo full %.0f m in, radio gone %.0f m in" % [TunnelAudio.WET_RAMP, RadioManager.TUNNEL_FADE])

# ---------- parts 2 and 3 ----------

func _s_of(p: Node3D) -> float:
	return RoadMap.wrap_s(RoadFrame.s_at(RoadFrame.unroll(p.global_position).z))

func _physics_process(_delta: float) -> bool:
	if phase == "done":
		return true
	if phase == "reboot":
		wait_ticks -= 1
		if wait_ticks <= 0:
			OS.set_environment("NEON_START_S", str(FAST_START))
			game = Harness.boot(self, 0, 300.0, 777)
			phase = "fast"
			tick = 0
			started = false
		return false
	tick += 1
	if tick > TIMEOUT_TICKS:
		_fail("%s pass: timed out" % phase)
		return _next()
	var p: PlayerCar = game.get("player")
	if p == null:
		return false
	if not Harness.finite(p):
		_fail("%s pass: non-finite player state" % phase)
		return _next()
	var s := _s_of(p)
	if tick < SETTLE_TICKS:
		return false
	if not started:
		started = true
		var cam: Node = game.get("camera")
		if cam != null:
			cam.set("shake_enabled", false)
		wall_hits = 0
		other_hits = 0
		if phase == "traffic":
			_check(RoadMap.tunnel_live and RoadMap.tunnel_at(87), "the game's road has no tunnel")
			_check(absf(s - TRAFFIC_START) < 2.0, "the run did not start %.0f m round the loop (at %.1f)" % [TRAFFIC_START, s])
			var traffic: TrafficManager = game.get("traffic")
			traffic.log_spawns = true
			driver = TestDriver.start(game, "clean", {"speed": TRAFFIC_KMH, "lane": 1})
			var audio := game.get_node_or_null(^"TunnelAudio")
			_check(audio != null, "the game has no TunnelAudio node")
			_check(AudioServer.get_bus_index(&"Tunnel") == 1, "there should be a Tunnel bus next to Master")
			for bus_name in TunnelAudio.SENDS:
				_check(AudioServer.get_bus_send(AudioServer.get_bus_index(bus_name)) == &"Tunnel", "the %s bus should send to Tunnel" % bus_name)
			_check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Music")) == &"Master", "the Music bus should stay dry")
			if audio != null:
				echo_before = float(audio.get("amount"))
		else:
			_check(absf(s - FAST_START) < 2.0, "the fast run did not start at the top of the ramp (at %.1f)" % s)
			p.driver = Harness.lane_driver(RoadFrame.unroll(p.global_position).x, 1.0, FAST_MS)
			Harness.launch_player(p, FAST_MS)
		return false
	var kmh := Harness.kmh(p.current_speed())
	max_kmh = maxf(max_kmh, kmh)
	var inside := RoadMap.tunnel_depth(s)
	if inside > 0.0:
		min_kmh_inside = minf(min_kmh_inside, kmh)
	deepest = maxf(deepest, inside)
	# contacts: a wall or a building is a fail; anything else is counted
	if p.get_contact_count() > 0:
		for b in p.get_colliding_bodies():
			var bn := String((b as Node).name)
			if bn.begins_with("Boundary") or bn.begins_with("Building") or bn.begins_with("Barrier") or bn.begins_with("Kit"):
				wall_hits += 1
				if hit_note == "":
					hit_note = "%s at %.0f m, %.0f km/h" % [bn, s, kmh]
			else:
				other_hits += 1
				if hit_note == "":
					hit_note = "(%s at %.0f m)" % [bn, s]
	var grounded := 0
	for w in p.wheel_array:
		if w.is_colliding():
			grounded += 1
	if phase == "fast" and tick > SETTLE_TICKS + 20:
		fewest_wheels = mini(fewest_wheels, grounded)
		if grounded == 0:
			air_ticks += 1
	if phase == "traffic":
		_look_at_chunks()
		var audio := game.get_node_or_null(^"TunnelAudio")
		var radio: RadioManager = game.get("radio")
		if inside > 60.0 and audio != null:
			echo_inside = maxf(echo_inside, float(audio.get("amount")))
			rx_inside = minf(rx_inside, radio.reception)
	if s >= PASS_END:
		return _next()
	return false

## Reads back what the builder recorded on the chunks around the car.
func _look_at_chunks() -> void:
	for entry in game.get("chunk_pool"):
		var root: Node3D = entry.root
		var m := RoadMap.lap_chunk(int(entry.index))
		# A recycled chunk has its new index before its staged rebuild starts.
		if chunks_checked.has(m) or RoadChunkBuilder.is_rebuilding(root) or int(root.get_meta("chunk_index", -1)) != int(entry.index):
			continue
		if m < FIRST - RAMP - 1 or m > LAST + RAMP + 1:
			continue
		chunks_checked[m] = true
		var rec: Dictionary = root.get_meta(&"tunnel", {})
		var holder := root.get_node_or_null(^"Tunnel") as Node3D
		var lamps := (root.get_node(^"Lamps") as MultiMeshInstance3D).multimesh.visible_instance_count
		var kerb := (root.get_node(^"CurbOwn") as MeshInstance3D).visible
		var buildings := 0
		for i in RoadChunkBuilder._building_slots() * 2:
			if (root.get_node(NodePath("BuildingMesh%d" % i)) as MeshInstance3D).visible:
				buildings += 1
		if m >= FIRST and m <= LAST:
			_check(int(rec.get("kind", 0)) == RoadMap.DIP_TUNNEL and holder != null and holder.visible, "chunk %d is not built as a tunnel" % m)
			_check(int(rec.get("walls", 0)) == 20 and int(rec.get("surfaces", 0)) == 3, "chunk %d: %s wall rows, %s surfaces" % [m, rec.get("walls"), rec.get("surfaces")])
			_check(lamps == 0, "chunk %d: %d street lamps in the tunnel" % [m, lamps])
			_check(buildings == 0, "chunk %d: %d buildings over the tunnel" % [m, buildings])
			_check(not kerb, "chunk %d: the kerb is drawn in the tunnel" % m)
			_check(int(rec.get("blocks", 0)) == (1 if m == FIRST or m == LAST else 0), "chunk %d: %s mouth blocks" % [m, rec.get("blocks")])
			var bounds := RoadChunkBuilder.bounds(root)
			_check(bounds.x < 16.5 and bounds.y < 16.5, "chunk %d: the walls are %s from the centre line, not at the road's edge" % [m, bounds])
			for lv in rec.get("strip_levels", PackedFloat32Array()):
				_check(lv >= 1.0 - TunnelKit.FLICKER_MAX, "chunk %d: a strip piece at %.2f of full" % [m, lv])
		elif m >= FIRST - RAMP and m <= LAST + RAMP:
			_check(int(rec.get("kind", 0)) == RoadMap.DIP_RAMP and holder != null and holder.visible, "chunk %d is not built as a trench" % m)
			_check(not kerb, "chunk %d: the kerb is drawn in the trench" % m)
			var has_deck: bool = rec.get("deck", Vector2.ZERO) != Vector2.ZERO
			_check(has_deck == (m == FIRST - 1 or m == LAST + 1), "chunk %d: cross-street deck %s" % [m, has_deck])
			var d: Array = rec.get("depth", [0.0, 0.0])
			if m == FIRST - 1:
				_check(absf(float(d[1]) - 5.0) < 0.1, "chunk %d ends %.2f m under the street at the mouth (5 m)" % [m, float(d[1])])
			if m == FIRST - RAMP:
				_check(absf(float(d[0])) < 0.05, "chunk %d starts %.2f m under the street" % [m, float(d[0])])
		else:
			_check(holder == null or not holder.visible, "chunk %d, outside the dip, shows tunnel pieces" % m)
			_check(kerb, "chunk %d, outside the dip, has no kerb" % m)

func _next() -> bool:
	var p: PlayerCar = game.get("player")
	if phase == "traffic":
		var traffic: TrafficManager = game.get("traffic")
		var under := 0
		for slot in traffic.spawn_log:
			if RoadMap.tunnel_at(floori(RoadFrame.s_at(float(slot.z)) / L)):
				under += 1
		var audio := game.get_node_or_null(^"TunnelAudio")
		var radio: RadioManager = game.get("radio")
		var echo_after := float(audio.get("amount")) if audio != null else -1.0
		print("traffic pass: reached %.0f m, top %.0f km/h, slowest inside %.0f km/h, %d traffic cars on the road, %d placed (%d under cover), wall contacts %d, other contacts %d %s" % [
			_s_of(p) if p != null else -1.0, max_kmh, min_kmh_inside, traffic.active_count(), traffic.spawn_count, under, wall_hits, other_hits, hit_note])
		print("  echo: %.2f before, %.2f inside, %.2f after; radio: %.2f inside, %.2f after; chunks looked at: %s" % [
			echo_before, echo_inside, echo_after, rx_inside, radio.reception, str(chunks_checked.keys())])
		_check(p != null and _s_of(p) >= PASS_END, "the traffic pass did not get through the tunnel")
		_check(deepest > 140.0, "the car was never in the middle of the tunnel (deepest %.0f m)" % deepest)
		_check(traffic.active_count() > 0, "no traffic was on the road")
		_check(wall_hits == 0, "the car touched a wall %d times: %s" % [wall_hits, hit_note])
		_check(under == 0, "%d traffic cars were placed under cover" % under)
		_check(echo_before == 0.0, "echo before the tunnel (%.2f)" % echo_before)
		_check(echo_inside > 0.95, "no full echo inside (%.2f)" % echo_inside)
		_check(echo_after < 0.05, "the echo is still on after the tunnel (%.2f)" % echo_after)
		_check(rx_inside < 0.1, "the radio kept its signal inside (%.2f)" % rx_inside)
		_check(radio.reception > 0.9, "the radio did not come back (%.2f)" % radio.reception)
		for m in range(FIRST - RAMP - 1, LAST + RAMP + 1):
			_check(chunks_checked.has(m), "chunk %d was never looked at" % m)
		if driver != null and p != null:
			driver.call("detach", p)
		game.queue_free()
		phase = "reboot"
		wait_ticks = 10
		max_kmh = 0.0
		min_kmh_inside = INF
		deepest = 0.0
		hit_note = ""
		return false
	print("fast pass: reached %.0f m, top %.0f km/h, slowest inside %.0f km/h, fewest wheels on the road %d, ticks in the air %d, wall contacts %d, other contacts %d %s" % [
		_s_of(p) if p != null else -1.0, max_kmh, min_kmh_inside, fewest_wheels, air_ticks, wall_hits, other_hits, hit_note])
	_check(p != null and _s_of(p) >= PASS_END, "the fast pass did not get through the tunnel")
	_check(max_kmh > 240.0, "the fast pass only reached %.0f km/h" % max_kmh)
	_check(air_ticks == 0, "the car left the ground for %d ticks at 250 km/h" % air_ticks)
	# The belly brushing the road in the sag inside the mouth is the car's own
	# ground clearance at this speed (0.4 g extra on a 1250 m sag; the open
	# road's sags go down to 400 m) and is printed, not failed.
	_check(wall_hits == 0, "the fast pass touched a wall: %s" % hit_note)
	return _end()

func _end() -> bool:
	phase = "done"
	for e in logger.errors:
		_fail("engine error: " + e)
	if fails.is_empty():
		print("tunnel: PASS")
	else:
		print("tunnel: FAIL (%d)" % fails.size())
		for f in fails:
			print("  - ", f)
	quit(0 if fails.is_empty() else 1)
	return true
