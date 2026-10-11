extends SceneTree

# Ghost audit (breakable world I0, 2026-10-11): which roadside things does the
# car drive straight through today?
#
# 1. Census: builds chunks across the districts and counts every recorded
#    prop per kind (posts, cones, bins, hydrants, lamps, sign posts, gantry
#    legs), and checks the record itself: each prop inside its chunk, on the
#    side it claims, in the 5 m bucket near() will look in, and a chunk built
#    twice gives the same record.
# 2. Drive: boots the game and drives the player along the kerb line on the
#    own side, aiming at the post line, for DRIVE_M metres. Every tick the
#    car's box is tested against the record (RoadsideProps.near); a prop the
#    box covered while the car kept its speed and touched no wall is a
#    pass-through. Prints them per kind.
#
# The drive is a report, not a gate: its pass count depends on what stands on
# that stretch. What fails the test: a broken record, a script error, or a
# drive that meets no prop at all (the audit would be blind).
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/world/prop_ghosts.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Props := preload("res://scripts/world/roadside_props.gd")
const Districts := preload("res://scripts/world/districts.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")

const DRIVE_M := 1500.0
const SPEED_KMH := 70.0
const TIMEOUT_TICKS := 60 * 240

var fails := 0
var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var start_s := 0.0
var ticks := 0
var half := Vector3.ZERO
var seen := {}        # "chunk:i" -> kind, props the box has covered
var through := {}     # same key, once the car is past it at speed
var pending := {}     # key -> [kind, speed when first covered, wall contacts then]
var aim_x := 0.0
var solid_hits := 0
var out := PackedInt32Array()

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	OS.add_logger(logger)
	_census()
	game = Harness.boot(self, 0, 300.0, 4242, 1e7)

func _census() -> void:
	var totals := PackedInt32Array()
	totals.resize(Props.NAMES.size())
	var per_district := {}
	var chunks := 0
	for c in range(0, 1200, 7):
		var d := Districts.name_at(c)
		per_district[d] = int(per_district.get(d, 0)) + 1
		var cfg := {"own_lanes": 3, "onc_lanes": 2, "barrier": true}
		seed(c)
		var chunk: Node3D = B.build_chunk(c, cfg, cfg)
		root.add_child(chunk)
		var rec: Dictionary = Props.of(chunk)
		if rec.is_empty():
			_fail("chunk %d has no props record" % c)
			chunk.free()
			continue
		chunks += 1
		var kind: PackedInt32Array = rec.kind
		var road: PackedVector2Array = rec.road
		var side: PackedInt32Array = rec.side
		for i in kind.size():
			totals[kind[i]] += 1
			if road[i].y > 0.01 or road[i].y < -Props.CHUNK_LEN - 0.01:
				_fail("chunk %d %s outside the chunk (z %.2f)" % [c, Props.NAMES[kind[i]], road[i].y])
			if signf(road[i].x) != float(side[i]):
				_fail("chunk %d %s on the wrong side (x %.2f, side %d)" % [c, Props.NAMES[kind[i]], road[i].x, side[i]])
			var b := clampi(int(-road[i].y / Props.BUCKET), 0, Props.N_BUCKETS - 1)
			if not (rec.buckets[b] as PackedInt32Array).has(i):
				_fail("chunk %d prop %d is not in bucket %d" % [c, i, b])
			# near() must find it with a box centred on it
			out.clear()
			var here := Transform3D(Basis(), -(rec.pos[i] as Vector3))
			Props.near(rec, here, road[i].x, road[i].y, 0.5, 0.5, 0.5, PackedByteArray(), out)
			if not out.has(i):
				_fail("chunk %d: near() misses prop %d (%s)" % [c, i, Props.NAMES[kind[i]]])
		if c % 70 == 0:
			seed(c)
			var again: Node3D = B.build_chunk(c, cfg, cfg)
			var a: Dictionary = Props.of(again)
			if str(a.kind) != str(rec.kind) or str(a.road) != str(rec.road) or str(a.slot) != str(rec.slot):
				_fail("chunk %d built twice gives two prop records" % c)
			again.free()
		chunk.free()
	print("census over %d chunks (%s):" % [chunks, str(per_district)])
	for k in Props.NAMES.size():
		print("  %-8s %5d  (%.1f per km)  %s" % [Props.NAMES[k], totals[k], float(totals[k]) / (float(chunks) * 0.05),
			["gives", "breakaway", "ghost"][Props.CLASS[k]]])
	for k in [Props.POST, Props.LAMP, Props.HYDRANT, Props.BIN]:
		if totals[k] == 0:
			_fail("census found no %s at all" % Props.NAMES[k])

func _car_half(c: Node3D) -> Vector3:
	for ch in c.get_children():
		if ch is CollisionShape3D and ch.shape is ConvexPolygonShape3D:
			var m := Vector3.ZERO
			for pt in (ch.shape as ConvexPolygonShape3D).points:
				m = m.max(pt.abs())
			return m
	return Vector3(0.9, 0.7, 2.2)

func _roots() -> Dictionary:
	var by := {}
	for e in game.get("chunk_pool"):
		if not B.is_rebuilding(e.root):
			by[int(e.index)] = e.root
	return by

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < 60:
			p = null
			return false
		half = _car_half(p)
		var by := _roots()
		var u0 := RoadFrame.unroll(p.global_position)
		aim_x = _post_line(by, floori(RoadFrame.s_at(u0.z) / Props.CHUNK_LEN), 0.0, 14.0)
		TestDriver.place(p, aim_x, 0.0, 0.0, SPEED_KMH / 3.6, u0.y + 0.25)
		bot = TestDriver.start(game, "aim", {"speed": SPEED_KMH})
		start_s = RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)
		print("car box half size %.2f x %.2f m, driving the kerb line at x %.2f" % [half.x, half.z, aim_x])
		return false
	ticks += 1
	var u := RoadFrame.unroll(p.global_position)
	var s := RoadFrame.s_at(u.z)
	var here := floori(s / Props.CHUNK_LEN)
	var by := _roots()
	var speed := p.linear_velocity.length()
	aim_x = _post_line(by, here, -(s - float(here) * Props.CHUNK_LEN), aim_x)
	bot.aim_point = RoadFrame.roll(Vector3(aim_x, u.y, u.z - 25.0))
	var car_inv := p.global_transform.affine_inverse()
	var now := {}
	for c in [here, here + 1]:
		if not by.has(c):
			continue
		var root_c: Node3D = by[c]
		var rec: Dictionary = Props.of(root_c)
		out.clear()
		Props.near(rec, car_inv * root_c.global_transform, u.x, -(s - float(c) * Props.CHUNK_LEN), half.x, half.z, half.z, PackedByteArray(), out)
		for i in out:
			var key := "%d:%d" % [c, i]
			now[key] = true
			if not seen.has(key):
				seen[key] = int(rec.kind[i])
				pending[key] = [int(rec.kind[i]), speed, bot.wall_contacts]
	for key in pending.keys():
		if now.has(key):
			continue
		# the box has left it: a pass-through if nothing stopped the car
		var e: Array = pending[key]
		if bot.wall_contacts == int(e[2]) and speed > float(e[1]) - 1.5:
			through[key] = int(e[0])
		pending.erase(key)
	if bot.wall_contacts > solid_hits:
		# something solid on the pavement (a kit rail, a wall): step past it
		solid_hits = bot.wall_contacts
		p.damage.garage_repair(null)
		TestDriver.place(p, aim_x, 25.0, 0.0, SPEED_KMH / 3.6, u.y + 0.25)
	elif speed < 3.0 and ticks % 120 == 0:
		TestDriver.place(p, aim_x, 25.0, 0.0, SPEED_KMH / 3.6, u.y + 0.25)
	var bad := TestDriver.sanity(p)
	if bad != "":
		_fail("car state: " + bad)
		return _end(s)
	if s - start_s >= DRIVE_M or ticks > TIMEOUT_TICKS:
		return _end(s)
	return false

## The x of the nearest own-side post ahead (the kerb's inner edge), plus a
## little, so the box covers the post line, the lamp line and the hydrants.
func _post_line(by: Dictionary, here: int, car_z: float, fallback: float) -> float:
	var best := INF
	var x := fallback
	for c in [here, here + 1]:
		if not by.has(c):
			continue
		var rec: Dictionary = Props.of(by[c])
		if rec.is_empty():
			continue
		for i in rec.kind.size():
			if rec.kind[i] != Props.POST or rec.side[i] != 1:
				continue
			var ahead: float = (float(c - here) * Props.CHUNK_LEN - rec.road[i].y) + car_z
			if ahead > 8.0 and ahead < best:
				best = ahead
				x = rec.road[i].x + 0.45
	return x

func _end(s: float) -> bool:
	var seen_n := PackedInt32Array()
	var thr_n := PackedInt32Array()
	seen_n.resize(Props.NAMES.size())
	thr_n.resize(Props.NAMES.size())
	for key in seen:
		seen_n[seen[key]] += 1
	for key in through:
		thr_n[through[key]] += 1
	print("drive: %.0f m along the own-side kerb line in %d ticks, %d solid hits" % [s - start_s, ticks, solid_hits])
	print("  kind      met  passed through")
	var total := 0
	for k in Props.NAMES.size():
		print("  %-8s %4d  %4d" % [Props.NAMES[k], seen_n[k], thr_n[k]])
		total += seen_n[k]
	if total == 0:
		_fail("the drive met no prop at all")
	if s - start_s < DRIVE_M * 0.5:
		_fail("the drive covered only %.0f of %.0f m" % [s - start_s, DRIVE_M])
	if not logger.errors.is_empty():
		_fail("%d script errors, first: %s" % [logger.errors.size(), str(logger.errors[0])])
	print("prop_ghosts: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
	return true
