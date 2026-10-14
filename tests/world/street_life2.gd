extends SceneTree

# Street life step 2 test (2026-10-14): parked cars at the kerb
# (scripts/world/parked_cars.gd, laid out by roadside_kit.gd), security
# floodlights (flood_lights.gd), bin night (roadside_kit.gd), dead sign
# letters (building_signs.gd) and lawn sprinklers (sprinklers.gd).
#
# Asserts (exit code 1 on failure):
# - parked cars: every district has a table row; a narrow shoulder parks
#   none; the mode shares match the table; the shader reads the instance's
#   custom data and TIME; on built chunks every car sits inside the chunk,
#   on its own side, under the cap, overlapping no cone, jersey piece or
#   other car on that side, with one enabled collision box each and the
#   KitCars node visible only when a car is there; NEON off parks none
# - floodlights: every district plans per its table row (none without
#   one), under the cap, off the road; the state machine goes off -> rise
#   -> hold while the car is near, -> fall -> off after it leaves; shaders
#   read the custom data
# - bin night: on, the bin-night districts hold more bins than off, the
#   others the same; the weekday rule picks one night a week
# - dead letters: deterministic, never on a billboard, letter index inside
#   the word, share near DEAD_SHARE, the custom-data encoding round-trips
#   for every style x letter x buzz; off, no letter dies
# - sprinklers: the window is the dead hours, every district plans per its
#   table (none in a tunnel), under the cap, off the road, the shader reads
#   the clock uniform set from the night clock
#
# Loops over every district kind, every car mode, every sign style and
# six built chunks of every district (the "everything" rule). Runs headless: facts come from
# the chunks' meta records, not MultiMesh getters.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/street_life2.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Kit := preload("res://scripts/world/roadside_kit.gd")
const Cars := preload("res://scripts/world/parked_cars.gd")
const Floods := preload("res://scripts/world/flood_lights.gd")
const Sprinklers := preload("res://scripts/world/sprinklers.gd")
const Signs := preload("res://scripts/world/building_signs.gd")
const Districts := preload("res://scripts/world/districts.gd")
const SeasonCalendar := preload("res://scripts/world/season_calendar.gd")

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	_check_cars()
	_check_floods()
	_check_signs()
	_check_sprinklers()
	_check_chunks()
	_check_bin_night()

# the flood state machine reads global positions, so it runs on the first
# frame, once the nodes are inside the tree
func _process(_delta: float) -> bool:
	_check_flood_steps()
	print("street_life2: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(0 if fails == 0 else 1)
	return true

func _check_cars() -> void:
	for district in Districts.SPECS.keys():
		if not Cars.BY_DISTRICT.has(district):
			_fail("parked cars: no table row for %s" % district)
		if Cars.expected(district, Cars.MIN_SHOULDER - 0.1) != 0.0:
			_fail("%s parks on a shoulder narrower than %.1f m" % [district, Cars.MIN_SHOULDER])
		if Cars.expected(district, 3.0) != float(Cars.BY_DISTRICT.get(district, 0.0)):
			_fail("%s expected cars differ from the table" % district)
	var got := {Cars.MODE_PLAIN: 0, Cars.MODE_ALARM: 0, Cars.MODE_DOME: 0, Cars.MODE_HAZARD: 0}
	for r in 100:
		got[Cars.mode_of(r)] += 1
	if got[Cars.MODE_ALARM] != Cars.SHARE_ALARM or got[Cars.MODE_DOME] != Cars.SHARE_DOME or got[Cars.MODE_HAZARD] != Cars.SHARE_HAZARD:
		_fail("mode shares %s differ from the table" % [got])
	for mode in got.keys():
		for tint in Cars.TINTS.size():
			var c := Cars.custom(tint, mode, 0.25)
			if int(c.r) != tint or int(c.g) != mode or not is_equal_approx(c.b, 0.25):
				_fail("custom data for tint %d mode %d does not round-trip" % [tint, mode])
	var code: String = Cars.material().shader.code
	if not code.contains("INSTANCE_CUSTOM") or not code.contains("TIME"):
		_fail("parked car shader does not read custom data and TIME")
	if Cars.material() != Cars.material() or Cars.mesh() != Cars.mesh():
		_fail("parked car mesh or material is not cached")
	if Cars.mesh().get_surface_count() < 1:
		_fail("parked car mesh is empty")
	Cars.enabled = false
	if Cars.expected("old_town", 3.0) != 0.0:
		_fail("parked cars off still parks")
	Cars.enabled = true
	print("cars: %d districts, modes %s, shader reads custom + TIME" % [Districts.SPECS.size(), got])

func _check_floods() -> void:
	var fake := [{"empty": false, "type": "warehouse", "side": 1, "z": -20.0, "d": 14.0, "front_x_abs": 16.0, "h": 9.0},
		{"empty": false, "type": "garage", "side": -1, "z": -40.0, "d": 10.0, "front_x_abs": 15.0, "h": 6.0},
		{"empty": false, "type": "hangar", "side": 1, "z": -8.0, "d": 20.0, "front_x_abs": 18.0, "h": 11.0},
		{"empty": false, "type": "parking", "side": -1, "z": -30.0, "d": 12.0, "front_x_abs": 14.0, "h": 4.0}]
	var walks := [9.0, 9.0, 9.0, 9.0]
	for district in Districts.SPECS.keys():
		var n := 0
		for c in 200:
			var list := Floods.plan(c, district, fake, walks)
			if list.size() > Floods.CAP:
				_fail("%s chunk %d: %d floods over the cap" % [district, c, list.size()])
			for f in list:
				if absf(float(f.x)) < 9.0:
					_fail("%s: flood head x %.1f is on the road" % [district, f.x])
			n += list.size()
		if Floods.BY_DISTRICT.has(district) == (n == 0):
			_fail("%s: %d floods over 200 chunks, table row %s" % [district, n, Floods.BY_DISTRICT.has(district)])
	for m in [Floods.head_material(), Floods.pool_material()]:
		if not (m as ShaderMaterial).shader.code.contains("INSTANCE_CUSTOM"):
			_fail("flood shader does not read the custom data")
	print("floods: %d districts planned, shaders read custom data" % Districts.SPECS.size())

func _check_flood_steps() -> void:
	var walks := [9.0, 9.0, 9.0, 9.0]
	# the state machine on a chunk root with one planned light
	var chunk := Node3D.new()
	root.add_child(chunk)
	for n in Floods.new_nodes():
		chunk.add_child(n)
	var one := [{"empty": false, "type": "warehouse", "side": 1, "z": -20.0, "d": 14.0, "front_x_abs": 16.0, "h": 9.0}]
	var ci := 0
	while Floods.plan(ci, "industrial", one, walks).is_empty():
		ci += 1
	Floods.update(chunk, ci, "industrial", one, walks)
	var floods: Array = chunk.get_meta("floods")
	if floods.size() != 1:
		_fail("one planned flood, %d in the meta" % floods.size())
	var player := Node3D.new()
	root.add_child(player)
	player.global_position = Vector3(1000.0, 0.0, 0.0)
	Floods.step([{"root": chunk, "index": ci}], player, 0.1)
	if int(floods[0].state) != Floods.STATE_OFF:
		_fail("flood woke with the car %d m away" % 1000)
	player.global_position = (floods[0].pos as Vector3) + Vector3(5.0, 0.0, 0.0)
	Floods.step([chunk], player, 0.01)
	if int(floods[0].state) != Floods.STATE_RISE:
		_fail("flood did not rise with the car beside it (state %d)" % floods[0].state)
	Floods.step([chunk], player, Floods.RISE_S + 0.01)
	if int(floods[0].state) != Floods.STATE_HOLD:
		_fail("flood did not reach hold after %.2f s (state %d)" % [Floods.RISE_S, floods[0].state])
	Floods.step([chunk], player, Floods.HOLD_S * 2.0)
	if int(floods[0].state) != Floods.STATE_HOLD:
		_fail("flood fell while the car stayed (state %d)" % floods[0].state)
	player.global_position = (floods[0].pos as Vector3) + Vector3(Floods.TRIGGER_M + 20.0, 0.0, 0.0)
	Floods.step([chunk], player, Floods.HOLD_S + 0.01)
	if int(floods[0].state) != Floods.STATE_FALL:
		_fail("flood did not fall %.0f s after the car left (state %d)" % [Floods.HOLD_S, floods[0].state])
	Floods.step([chunk], player, Floods.FALL_S + 0.01)
	if int(floods[0].state) != Floods.STATE_OFF:
		_fail("flood did not go off after the fall (state %d)" % floods[0].state)
	chunk.free()
	player.free()
	print("flood steps: off/rise/hold/fall/off")

func _check_signs() -> void:
	var words := ["LOANS", "MOTEL", "DINER", "BAR", "TYRES", "PAWN", "GAS", "24 HOURS", "LIQUOR", "HOTEL"]
	var n := 0
	var dead := 0
	var buzz := 0
	for style in 3:
		for w in words:
			for k in 60:
				var front := Vector3(12.0 + float(k) * 0.7, 5.0, -float(k) * 3.1)
				var a := Signs.dead_letter(w, style, front)
				if a != Signs.dead_letter(w, style, front):
					_fail("dead letter differs between calls for %s" % w)
				if style == 2 and int(a[0]) != -1:
					_fail("a billboard (%s) lost a letter" % w)
				if int(a[0]) >= w.length():
					_fail("%s: dead letter %d past the word" % [w, a[0]])
				if int(a[0]) >= 0 and w[int(a[0])] == " ":
					_fail("%s: the dead letter is the space" % w)
				if style < 2:
					n += 1
					if int(a[0]) >= 0:
						dead += 1
						if bool(a[1]):
							buzz += 1
				# the encoding carries style, letter and buzz back out
				var enc := Signs.encode_style(style, a)
				if Signs.style_of(enc) != style or Signs.dead_of(enc) != int(a[0]) or Signs.buzzing_of(enc) != bool(a[1]):
					_fail("%s style %d: custom data %d does not round-trip %s" % [w, style, enc, a])
	var share := float(dead) / float(n)
	if absf(share - Signs.DEAD_SHARE / 100.0) > 0.03:
		_fail("dead letter share %.3f, table says %.2f" % [share, Signs.DEAD_SHARE / 100.0])
	if buzz == 0 or buzz == dead:
		_fail("%d of %d dead letters buzz: want some, not all" % [buzz, dead])
	for style in 3:
		for li in range(-1, 8):
			for b in [false, true]:
				var enc := Signs.encode_style(style, [li, b])
				if Signs.style_of(enc) != style or Signs.dead_of(enc) != li or Signs.buzzing_of(enc) != b:
					_fail("encoding style %d letter %d buzz %s does not round-trip" % [style, li, b])
	if not Signs.material().shader.code.contains("TIME"):
		_fail("sign shader has no buzz (no TIME)")
	Signs.dead_letters = false
	if int(Signs.dead_letter("LOANS", 0, Vector3(12.0, 5.0, -3.0))[0]) != -1 and dead > 0:
		pass
	for w in words:
		for k in 30:
			if int(Signs.dead_letter(w, 0, Vector3(12.0, 5.0, -float(k)))[0]) != -1:
				_fail("dead letters off still kills a letter in %s" % w)
	Signs.dead_letters = true
	print("signs: %d lit signs, %.1f%% with a dead letter (%d buzzing), 3 styles encode" % [n, share * 100.0, buzz])

func _check_sprinklers() -> void:
	if Sprinklers.active(0.0) or Sprinklers.active(599.0) or not Sprinklers.active((Sprinklers.WINDOW.x + Sprinklers.WINDOW.y) / 2.0):
		_fail("sprinkler window %s is not the dead hours" % Sprinklers.WINDOW)
	var walks := [9.0, 9.0, 9.0, 9.0]
	for district in Districts.SPECS.keys():
		var n := 0
		for c in 200:
			var list := Sprinklers.plan(c, district, walks)
			if list.size() > Sprinklers.CAP:
				_fail("%s chunk %d: %d sprinklers over the cap" % [district, c, list.size()])
			for s in list:
				if absf(float(s.x)) < 9.0 or float(s.z) > 0.0 or float(s.z) < -B.CHUNK_LEN:
					_fail("%s: sprinkler at (%.1f, %.1f) on the road or outside the chunk" % [district, s.x, s.z])
			n += list.size()
			if not Sprinklers.plan(c, district, walks, true).is_empty():
				_fail("%s chunk %d: sprinklers in a tunnel" % [district, c])
		if Sprinklers.BY_DISTRICT.has(district) == (n == 0):
			_fail("%s: %d sprinklers over 200 chunks, table row %s" % [district, n, Sprinklers.BY_DISTRICT.has(district)])
	var m := Sprinklers.material()
	if not m.shader.code.contains("clock") or not m.shader.code.contains("INSTANCE_CUSTOM"):
		_fail("sprinkler shader does not read the clock and the custom data")
	Sprinklers.set_clock(500.0)
	if not is_equal_approx(float(m.get_shader_parameter("clock")), 500.0):
		_fail("set_clock did not reach the shader")
	print("sprinklers: window %s, %d districts planned, clock uniform" % [Sprinklers.WINDOW, Districts.SPECS.size()])

func _overlaps(a: Dictionary, b: Dictionary) -> bool:
	var ah := float(a.len) / 2.0
	var bh := float(b.len) / 2.0
	return float(a.z) + ah > float(b.z) - bh and float(a.z) - ah < float(b.z) + bh

func _check_chunks() -> void:
	Kit.force = {"workzone": 0.5}
	var cfg := {"own_lanes": 3, "onc_lanes": 2, "barrier": true}
	var cars := 0
	var modes := {}
	var floods := 0
	var sprinklers := 0
	var districts := {}
	# six chunks of every district kind (the first six found along the road)
	var picks := []
	var scan := 2
	while scan < 600:
		var d := Districts.name_at(scan)
		if int(districts.get(d, 0)) < 6:
			districts[d] = int(districts.get(d, 0)) + 1
			picks.append(scan)
		scan += 1
	for d in Districts.SPECS.keys():
		if not districts.has(d):
			_fail("district %s not found in 600 chunks" % d)
	for ci in picks:
		var chunk: Node3D = B.build_chunk(ci, cfg, cfg)
		root.add_child(chunk)
		var kit: Array = chunk.get_meta("kit")
		var per_side := {1: [], -1: []}
		var n_cars := 0
		for r in kit:
			per_side[int(r.side)].append(r)
			if String(r.kind) != Kit.CAR:
				continue
			n_cars += 1
			modes[int(r.mode)] = int(modes.get(int(r.mode), 0)) + 1
			var half := Cars.SIZE.z / 2.0
			if float(r.z) + half > 0.0 or float(r.z) - half < -B.CHUNK_LEN:
				_fail("chunk %d: car z %.1f outside the chunk" % [ci, r.z])
			if float(r.x) < 3.0:
				_fail("chunk %d: car x %.1f is in the lane" % [ci, r.x])
			if int(r.tint) < 0 or int(r.tint) >= Cars.TINTS.size():
				_fail("chunk %d: car tint %d out of the table" % [ci, r.tint])
		if n_cars > Cars.CAP:
			_fail("chunk %d: %d cars over the cap" % [ci, n_cars])
		cars += n_cars
		for side in [1, -1]:
			var list: Array = per_side[side]
			for i in list.size():
				var a: Dictionary = list[i]
				if String(a.kind) != Kit.CAR:
					continue
				for j in list.size():
					if i == j:
						continue
					var b: Dictionary = list[j]
					if String(b.kind) in [Kit.CAR, Kit.CONE, Kit.JERSEY] and _overlaps(a, b):
						_fail("chunk %d side %d: car at z %.1f overlaps %s at z %.1f" % [ci, side, a.z, b.kind, b.z])
		var mmi := chunk.get_node(^"KitCars") as MultiMeshInstance3D
		if mmi.visible != (n_cars > 0) or mmi.multimesh.visible_instance_count != n_cars:
			_fail("chunk %d: KitCars shows %d of %d cars, visible=%s" % [ci, mmi.multimesh.visible_instance_count, n_cars, mmi.visible])
		if not mmi.multimesh.use_custom_data:
			_fail("chunk %d: KitCars carries no custom data" % ci)
		var body := chunk.get_node(^"KitColCars") as StaticBody3D
		var on := 0
		for col in body.get_children():
			if not (col as CollisionShape3D).disabled:
				on += 1
		if on != n_cars:
			_fail("chunk %d: %d car collision boxes for %d cars" % [ci, on, n_cars])
		# floodlights and sprinklers: inside the chunk, off the road
		var fl: Array = chunk.get_meta("floods")
		floods += fl.size()
		for f in fl:
			var p: Vector3 = f.pos
			if absf(p.x) < 5.0 or p.z > 1.0 or p.z < -B.CHUNK_LEN - 1.0:
				_fail("chunk %d: flood head at %s on the road or outside" % [ci, p])
			if int(f.state) != Floods.STATE_OFF:
				_fail("chunk %d: flood built already on" % ci)
		var sp: Array = chunk.get_meta("sprinklers")
		sprinklers += sp.size()
		for s in sp:
			if absf(float(s.x)) < 5.0:
				_fail("chunk %d: sprinkler x %.1f on the road" % [ci, s.x])
		# a pooled chunk rebuilt as this one parks the same cars (the kit's
		# RNG is chunk-seeded) unless its buildings' kerb drops moved them
		var again: Node3D = B.build_chunk(ci + 500, cfg, cfg)
		root.add_child(again)
		B.rebuild_chunk(again, ci, cfg, cfg)
		var n_again := 0
		for r in again.get_meta("kit"):
			if String(r.kind) == Kit.CAR:
				n_again += 1
		if absi(n_again - n_cars) > 2:
			_fail("chunk %d: rebuilt %d cars, fresh %d" % [ci, n_again, n_cars])
		again.free()
		chunk.free()
	Kit.force = {}
	if cars == 0:
		_fail("no parked car in %d chunks" % picks.size())
	if floods == 0:
		_fail("no floodlight in %d chunks" % picks.size())
	if sprinklers == 0:
		_fail("no sprinkler in %d chunks" % picks.size())
	for mode in [Cars.MODE_PLAIN, Cars.MODE_ALARM, Cars.MODE_DOME, Cars.MODE_HAZARD]:
		if not modes.has(mode):
			_fail("no parked car in mode %d over %d chunks" % [mode, picks.size()])
	print("chunks: %d built over %d districts, %d parked cars (modes %s), %d floodlights, %d sprinklers" % [picks.size(), districts.size(), cars, modes, floods, sprinklers])

func _bins(ci: int, cfg: Dictionary) -> int:
	var chunk: Node3D = B.build_chunk(ci, cfg, cfg)
	root.add_child(chunk)
	var n := 0
	for r in chunk.get_meta("kit"):
		if String(r.kind) == Kit.BIN:
			n += 1
	chunk.free()
	return n

func _check_bin_night() -> void:
	var cfg := {"own_lanes": 2, "onc_lanes": 2, "barrier": false}
	var seen := {}
	var more := 0
	var ci := 2
	while seen.size() < Districts.SPECS.size() and ci < 400:
		var district := Districts.name_at(ci)
		ci += 1
		if seen.has(district):
			continue
		seen[district] = true
		Kit.bin_night = false
		var off := 0
		Kit.bin_night = true
		var on := 0
		for k in 6:
			Kit.bin_night = false
			off += _bins(ci + k, cfg)
			Kit.bin_night = true
			on += _bins(ci + k, cfg)
		Kit.bin_night = false
		if district in Kit.BIN_NIGHT_DISTRICTS:
			if on <= off:
				_fail("%s: bin night %d bins, off %d" % [district, on, off])
			more += on - off
		elif on != off:
			_fail("%s: bin night changed the bins (%d vs %d) outside the bin-night districts" % [district, on, off])
	if seen.size() < Districts.SPECS.size():
		_fail("only %d of %d districts found in 400 chunks" % [seen.size(), Districts.SPECS.size()])
	var nights := 0
	for n in range(1, 29):
		if SeasonCalendar.weekday(n) == Kit.BIN_WEEKDAY:
			nights += 1
	if nights != 4:
		_fail("%d bin nights in 28, want 4" % nights)
	print("bin night: %d districts, %d extra bins on the bin-night kerbs, one night a week" % [seen.size(), more])
