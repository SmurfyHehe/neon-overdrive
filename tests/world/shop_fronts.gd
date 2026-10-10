extends SceneTree

# World step 3 (2026-10-10): shop fronts with life inside. Headless: it reads
# node meta and instance shader parameters; the room itself is drawn by the
# facade shader (tools/shopfront_shots.gd shows it).
#
# Asserts (exit code 1 on failure):
# - every shop, gas station and diner has a room behind its glass (shader
#   `room` 0..3, meta shop_front a BuildingKit.ROOMS key from its district's
#   "fronts" table, or the next district's in a run's blend chunks); a gas
#   kiosk is always a store and a diner a bar; every other building has
#   room -1 and no shop_front meta
# - the closing time matches the kind: a laundromat in [90, 210], a bar in
#   [330, 400], a store either never or in [180, 300], a vacant unit never,
#   a shuttered unit all night; gas and diner never
# - every kind turns up along 320 chunks, and stores both kinds (24-hour and
#   closing)
# - the shutter curve: all up at 8 p.m. (bar the shuttered units), bars
#   still up at 1 a.m., laundromats and bars down by 3 a.m., a 24-hour store
#   up all night, and the roll takes BuildingKit.SHUTTER_MINUTES
# - WindowLights.set_minutes feeds the clock to the facade material, and a
#   change under a tenth of a minute is not pushed
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/shop_fronts.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const CHUNKS := 320  # 20 runs

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _cfg(o: int, n: int, barrier: bool) -> Dictionary:
	return {"own_lanes": o, "onc_lanes": n, "barrier": barrier}

func _kinds_of(table: Array) -> Array:
	var out := []
	for e in table:
		out.append(String(e[0]))
	return out

func _initialize() -> void:
	var D := B.Districts
	var K := B.BuildingKit
	seed(4242)
	var kinds := {}
	var store_24h := 0
	var store_closing := 0
	var n_fronts := 0
	var n_plain := 0
	for idx in CHUNKS:
		var cfg := _cfg(1 + idx % 4, 1 + (idx / 4) % 2, idx % 3 == 0)
		var fresh := B.build_chunk(idx, _cfg(2, 2, false), cfg)
		var run := D.run_of(idx)
		var allowed := _kinds_of(D.spec(D.name_of_run(run)).get("fronts", D.DEFAULTS.fronts))
		allowed.append_array(_kinds_of(D.spec(D.name_of_run(run + 1)).get("fronts", D.DEFAULTS.fronts)))
		for i in B._building_slots() * 2:
			var mi: MeshInstance3D = fresh.get_node(NodePath("BuildingMesh%d" % i))
			var type: String = mi.get_meta("building_type", "")
			if type == "lot" or not mi.visible:
				continue
			var room = mi.get_instance_shader_parameter("room")
			var close = mi.get_instance_shader_parameter("close_at")
			var kind: String = mi.get_meta("shop_front", "")
			var where := "chunk %d building %d (%s)" % [idx, i, type]
			if type != "shop" and type != "gas" and type != "diner":
				n_plain += 1
				if room == null or int(room) != -1 or kind != "":
					_fail("%s: a %s has a shop front (room %s, kind '%s')" % [where, type, str(room), kind])
				continue
			n_fronts += 1
			if room == null or close == null:
				_fail("%s: no room / close_at parameter" % where)
				continue
			if not K.ROOMS.has(kind):
				_fail("%s: shop_front '%s' is not a BuildingKit room" % [where, kind])
				continue
			if int(room) != int(K.ROOMS[kind].id):
				_fail("%s: room %d does not match kind %s" % [where, int(room), kind])
			if type == "gas" and kind != "store":
				_fail("%s: a gas kiosk is a %s, not a store" % [where, kind])
			elif type == "diner" and kind != "bar":
				_fail("%s: a diner is a %s, not a bar" % [where, kind])
			elif type == "shop" and not allowed.has(kind):
				_fail("%s: %s is not in the district's fronts table %s" % [where, kind, str(allowed)])
			kinds[kind] = kinds.get(kind, 0) + 1
			var c := float(close)
			var spec: Dictionary = K.ROOMS[kind]
			if type != "shop":
				if c != K.NEVER:
					_fail("%s: a 24-hour %s closes at %.0f" % [where, type, c])
			elif spec.close is Array:
				var lo := float(spec.close[0])
				var hi := float(spec.close[1])
				if c == K.NEVER:
					if float(spec.close_chance) >= 1.0:
						_fail("%s: a %s never closes" % [where, kind])
					if kind == "store":
						store_24h += 1
				elif c < lo - 1e-4 or c > hi + 1e-4:
					_fail("%s: %s closes at %.0f, outside [%.0f, %.0f]" % [where, kind, c, lo, hi])
				elif kind == "store":
					store_closing += 1
			elif int(spec.close) == -2:
				if c != K.ALWAYS:
					_fail("%s: a shuttered unit has close_at %.0f" % [where, c])
			elif c != K.NEVER:
				_fail("%s: a %s has close_at %.0f" % [where, kind, c])
			# the shutter curve for this building
			var s0 := K.shutter_at(c, 0.0)
			var s300 := K.shutter_at(c, 300.0)
			var s420 := K.shutter_at(c, 420.0)
			if kind == "shuttered":
				if s0 < 1.0:
					_fail("%s: a shuttered unit is open at 8 p.m." % where)
			elif s0 > 0.0:
				_fail("%s: %s is shut at 8 p.m. (close_at %.0f)" % [where, kind, c])
			if kind == "bar" and type == "shop" and s300 > 0.0:
				_fail("%s: a bar is shutting at 1 a.m. (close_at %.0f)" % [where, c])
			if (kind == "bar" or kind == "laundromat") and type == "shop" and s420 < 1.0:
				_fail("%s: a %s is still open at 3 a.m. (close_at %.0f)" % [where, kind, c])
			if c == K.NEVER and K.shutter_at(c, 599.0) > 0.0:
				_fail("%s: a 24-hour front shut before dawn" % where)
			if c > 0.0 and c < K.NEVER:
				var mid := K.shutter_at(c, c + K.SHUTTER_MINUTES * 0.5)
				if absf(mid - 0.5) > 1e-4 or K.shutter_at(c, c + K.SHUTTER_MINUTES) < 1.0:
					_fail("%s: the shutter roll is not %.0f minutes" % [where, K.SHUTTER_MINUTES])
		fresh.free()
	for k in K.ROOMS:
		if not kinds.has(k):
			_fail("no %s anywhere along %d chunks" % [k, CHUNKS])
	if store_24h == 0 or store_closing == 0:
		_fail("stores: %d 24-hour, %d closing; both kinds are expected" % [store_24h, store_closing])
	# the clock reaches the material
	var mat := K.material()
	WindowLights.set_minutes(100.0)
	if absf(K.minutes() - 100.0) > 1e-6 or absf(float(mat.get_shader_parameter("minutes")) - 100.0) > 1e-6:
		_fail("set_minutes(100) left the facade clock at %.2f / %s" % [K.minutes(), str(mat.get_shader_parameter("minutes"))])
	WindowLights.set_minutes(100.05)
	if absf(float(mat.get_shader_parameter("minutes")) - 100.0) > 1e-6:
		_fail("a 0.05-minute change was pushed to the material")
	WindowLights.set_minutes(101.0)
	if absf(float(mat.get_shader_parameter("minutes")) - 101.0) > 1e-6:
		_fail("a 1-minute change was not pushed to the material")
	print("shop fronts: %d fronts, %d plain buildings, kinds %s, stores 24h/closing %d/%d" % [n_fronts, n_plain, str(kinds), store_24h, store_closing])
	if fails > 0:
		print("shop_fronts: %d FAILED" % fails)
		quit(1)
	else:
		print("shop_fronts: PASS")
		quit(0)
