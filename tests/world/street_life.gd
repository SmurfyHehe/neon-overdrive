extends SceneTree

# Street life step 1 test (2026-10-14): dead, buzzing and swapped lamps
# (scripts/world/lamp_wear.gd), work-zone flashers (roadside_kit.gd) and
# wall vents (scripts/world/wall_vents.gd).
#
# Asserts (exit code 1 on failure):
# - lamp wear is a pure function of chunk, side and slot: same inputs, same
#   answer; a lamp is never both dead and buzzing; no swap where the
#   district's lamps are already white; the global random sequence is not
#   touched (the road layout depends on it)
# - over many lamps the shares land near the district table
# - the head and pool materials are one ShaderMaterial per light colour, the
#   head above the glow threshold, both reading the instance's custom data
# - built chunks: the "Lamps" and "LampPools" MultiMeshes carry custom data,
#   the chunk's "lamp_wear" meta matches the rolls for its lamps, a chunk
#   with a work zone has one flasher per jersey piece (none otherwise), and
#   a chunk's wall vents sit off the road, under the cap; a rebuilt chunk's
#   lamp wear and flashers match a fresh one's; NEON_LAMP_WEAR=0 leaves every
#   lamp plain
#
# Runs headless (meta records, not MultiMesh getters, carry the facts).
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/street_life.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const W := preload("res://scripts/world/lamp_wear.gd")
const V := preload("res://scripts/world/wall_vents.gd")
const Kit := preload("res://scripts/world/roadside_kit.gd")
const Districts := preload("res://scripts/world/districts.gd")

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	_check_roll()
	_check_shares()
	_check_materials()
	_check_chunks()
	_check_off()
	print("street_life: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(0 if fails == 0 else 1)

func _check_roll() -> void:
	seed(77)
	var before := randi()
	seed(77)
	for c in 40:
		for side in [1, -1]:
			for slot in 4:
				var a := W.roll(c, side, slot, "old_town", "amber")
				var b := W.roll(c, side, slot, "old_town", "amber")
				if a != b:
					_fail("roll(%d, %d, %d) differs between calls: %s vs %s" % [c, side, slot, a, b])
				if a.r > 0.5 and a.g > 0.5:
					_fail("lamp %d/%d/%d is dead and buzzing at once" % [c, side, slot])
				if a.r > 0.5 and a.a > 0.5:
					_fail("lamp %d/%d/%d is dead and swapped at once" % [c, side, slot])
				if a.b < 0.0 or a.b > 1.0:
					_fail("phase %.2f out of 0..1" % a.b)
				var w := W.roll(c, side, slot, "lofts", "white")
				if w.a > 0.5:
					_fail("a white district swapped a lamp to white")
	var after := randi()
	if before != after:
		_fail("lamp wear touched the global random sequence")
	print("roll: deterministic, never dead+buzz, no swap on white, RNG untouched")

func _check_shares() -> void:
	for district in W.WEAR:
		var spec: Dictionary = W.WEAR[district]
		var n := 0
		var got := {"dead": 0, "buzz": 0, "swap": 0}
		for c in 500:
			for side in [1, -1]:
				for slot in 4:
					var r := W.roll(c, side, slot, district, "sodium")
					n += 1
					if r.r > 0.5:
						got.dead += 1
					elif r.g > 0.5:
						got.buzz += 1
					if r.a > 0.5:
						got.swap += 1
		for key in ["dead", "buzz", "swap"]:
			var want := float(spec[key]) / 100.0
			var have := float(got[key]) / float(n)
			# swap is rolled only on the lamps that are not dead
			if key == "swap":
				want *= 1.0 - float(spec.dead) / 100.0
			if absf(have - want) > maxf(0.012, want * 0.35):
				_fail("%s %s share %.3f, table says %.3f" % [district, key, have, want])
	print("shares: %d districts near their table" % W.WEAR.size())

func _check_materials() -> void:
	for light in Districts.LIGHTS:
		var head := W.head_mat(light)
		var pool := B._get_pool_mat(light)
		if head != W.head_mat(light) or pool != B._get_pool_mat(light):
			_fail("%s: materials are not cached" % light)
		if float(head.get_shader_parameter("energy")) < 1.0:
			_fail("%s head under the glow threshold" % light)
		for m in [head, pool]:
			if not (m as ShaderMaterial).shader.code.contains("INSTANCE_CUSTOM"):
				_fail("%s material does not read the instance's wear" % light)
		if B._get_lamp_mesh("cobra", light).surface_get_material(1) != head:
			_fail("%s lamp mesh head is not lamp wear's material" % light)
	if not Kit.flasher_material().shader.code.contains("TIME"):
		_fail("flasher shader does not blink with time")
	print("materials: %d lights, head and pool shaders cached" % Districts.LIGHTS.size())

func _chunk_rolls(chunk: Node3D) -> Dictionary:
	# what the builder should have rolled for this chunk's street lamps
	var ci := int(chunk.get_meta("chunk_index"))
	var st: Dictionary = Districts.street_at(ci)
	var district := Districts.name_at(ci)
	var every := int(st.every)
	var out := {"dead": 0, "buzz": 0, "swap": 0}
	if every == 0:
		return out
	var n := 0
	for i in B._lamp_slots():
		for side in [1, -1]:
			if every == 2 and (i == 0) != (side == 1):
				continue
			if every == 4 and (i != 0 or (side == 1) != (posmod(ci, 2) == 0)):
				continue
			var w := W.roll(ci, side, i, district, st.light)
			n += 1
			if w.r > 0.5:
				out.dead += 1
			elif w.g > 0.5:
				out.buzz += 1
			if w.a > 0.5:
				out.swap += 1
	out["n"] = n
	return out

func _check_chunks() -> void:
	Kit.force = {"workzone": 1.0}
	var cfg := {"own_lanes": 3, "onc_lanes": 2, "barrier": true}
	var flashers := 0
	var jerseys := 0
	var vents := 0
	var worn := 0
	var chunks := 0
	for ci in range(2, 60):
		var chunk: Node3D = B.build_chunk(ci, cfg, cfg)
		root.add_child(chunk)
		chunks += 1
		var lamps: MultiMesh = (chunk.get_node(^"Lamps") as MultiMeshInstance3D).multimesh
		var pools: MultiMesh = (chunk.get_node(^"LampPools") as MultiMeshInstance3D).multimesh
		if not lamps.use_custom_data or not pools.use_custom_data:
			_fail("chunk %d: lamps or pools carry no custom data" % ci)
		var wear: Dictionary = chunk.get_meta("lamp_wear")
		var want := _chunk_rolls(chunk)
		# the builder skips a lamp at a crossing, a ramp or a gas station, so
		# the chunk can hold fewer than the full set; never more
		for key in ["dead", "buzz", "swap"]:
			if int(wear[key]) > int(want[key]):
				_fail("chunk %d: %d %s lamps, the rolls allow %d" % [ci, wear[key], key, want[key]])
		worn += int(wear.dead) + int(wear.buzz) + int(wear.swap)
		# flashers: one per jersey piece
		var kit: Array = chunk.get_meta("kit")
		var nj := 0
		for r in kit:
			if String(r.kind) == Kit.JERSEY:
				nj += 1
		jerseys += nj
		var nf := int(chunk.get_meta("kit_flashers"))
		flashers += nf
		if nf != mini(nj, Kit.FLASHER_CAP):
			_fail("chunk %d: %d jersey pieces, %d flashers" % [ci, nj, nf])
		var fl := chunk.get_node(^"KitFlashers") as MultiMeshInstance3D
		if fl.visible != (nf > 0):
			_fail("chunk %d: flasher node visible=%s with %d flashers" % [ci, fl.visible, nf])
		# wall vents: in front of a fitting building's front wall
		var vl: Array = chunk.get_meta("wall_vents")
		vents += vl.size()
		if vl.size() > V.VENT_CAP:
			_fail("chunk %d: %d vents over the cap" % [ci, vl.size()])
		var infos: Array = chunk.get_meta("buildings") if chunk.has_meta("buildings") else []
		for v in vl:
			if absf(float(v.z)) > B.CHUNK_LEN:
				_fail("chunk %d: vent z %.1f outside the chunk" % [ci, v.z])
			if absf(float(v.x)) < 5.0:
				_fail("chunk %d: vent x %.1f is on the road" % [ci, v.x])
		# a pooled chunk rebuilt as this one matches it
		var again: Node3D = B.build_chunk(ci + 500, cfg, cfg)
		root.add_child(again)
		B.rebuild_chunk(again, ci, cfg, cfg)
		if again.get_meta("lamp_wear") != wear:
			_fail("chunk %d: rebuilt lamp wear %s != fresh %s" % [ci, again.get_meta("lamp_wear"), wear])
		if int(again.get_meta("kit_flashers")) != nf:
			_fail("chunk %d: rebuilt flashers %d != fresh %d" % [ci, again.get_meta("kit_flashers"), nf])
		# (vents follow the buildings, which are not a pure function of the
		# chunk index, so they are not compared)
		again.free()
		chunk.free()
	Kit.force = {}
	if worn == 0:
		_fail("no worn lamp in %d chunks" % chunks)
	if flashers == 0 or jerseys == 0:
		_fail("no work zone with flashers in %d chunks (forced on)" % chunks)
	if vents == 0:
		_fail("no wall vent in %d chunks" % chunks)
	print("chunks: %d built, %d worn lamps, %d flashers on %d jersey pieces, %d wall vents" % [chunks, worn, flashers, jerseys, vents])

func _check_off() -> void:
	W.enabled = false
	for c in 30:
		for side in [1, -1]:
			for slot in 4:
				if W.roll(c, side, slot, "docks", "sodium") != Color(0.0, 0.0, 0.0, 0.0):
					_fail("lamp wear off still wears lamp %d/%d/%d" % [c, side, slot])
	W.enabled = true
	print("off: every lamp plain")
