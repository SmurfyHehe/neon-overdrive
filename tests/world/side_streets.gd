extends SceneTree

# Side-street mouths and eyes in the headlights (world step 6, W7 + A1,
# 2026-10-10).
#
# Asserts (exit code 1 on failure):
# - every district run of 16 chunks has 1-3 mouths, none on a crossing's
#   chunks or a freeway, and the picks are the same on a second call
# - a chunk with a mouth: the slot's building is gone (mesh hidden,
#   collision off) and the road layout is otherwise identical to the same
#   chunk built with the mouths off (every other building's transform and
#   size match: the random sequence is untouched)
# - floating-support: the kit's origin sits on the pavement's outer edge at
#   the mouth (x and height against the Sidewalk strip's own vertices), the
#   lamp, sign and car stand on the street at the right offsets, and on a
#   hilly road every piece is still on the surface the road builder puts
#   there (no gap under anything)
# - the street is 30-60 m long and its kit, lamp, car and sign all lie
#   inside it, behind the building line (nothing in front of the setback)
# - a rebuilt chunk (the recycle path) lays out the same mouths
# - meshes: every triangle of the kit, prop and animal meshes has area and a
#   unit normal matching its clockwise winding (the lamp-mesh rule)
# - animals: at most 3 per chunk, each at a mouth's corner or a shop front;
#   a spot aimed at one makes its eyes shine within a second and it bolts
#   and is hidden after FLEE_TIME; a spot aimed away leaves it dark and
#   still; with the lights off it never shines
#
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/side_streets.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Districts := preload("res://scripts/world/districts.gd")
const SideStreets := preload("res://scripts/world/side_streets.gd")
const StreetAnimals := preload("res://scripts/world/street_animals.gd")
const CFG := {"own_lanes": 2, "onc_lanes": 2, "barrier": false}
const EPS := 0.01

var fails := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", msg)

func _run() -> void:
	seed(99)
	Junction.enabled = true
	RoadFrame.layout = null
	RoadFrame.align = null
	_check_picks()
	var found := _check_layout()
	_check_hills(found)
	_check_meshes()
	await _check_animals(found)
	print("side_streets: %d checks, %s" % [checks, "PASS" if fails == 0 else "%d failure(s)" % fails])
	quit(0 if fails == 0 else 1)

func _check_picks() -> void:
	var total := 0
	for run in 12:
		var n := 0
		for c in range(run * Districts.RUN, (run + 1) * Districts.RUN):
			var ms: Array = SideStreets.mouths_at(c)
			_check(ms == SideStreets.mouths_at(c), "chunk %d: mouths differ between calls" % c)
			for m in ms:
				n += 1
				_check(not Junction.touches(c), "chunk %d: mouth on a crossing's chunk" % c)
				_check(not Districts.is_freeway(c), "chunk %d: mouth on a freeway" % c)
				_check(float(m.len) >= SideStreets.LEN_MIN - EPS and float(m.len) <= SideStreets.LEN_MAX + EPS, "chunk %d: length %.1f" % [c, m.len])
		_check(n >= SideStreets.PER_RUN_MIN and n <= SideStreets.PER_RUN_MAX, "run %d has %d mouths" % [run, n])
		total += n
	print("side_streets: %d mouths in 12 runs" % total)

## Finds a chunk with a mouth, builds it with and without the switch, and
## checks the layout and the floating-support rules. Returns that chunk index.
func _check_layout() -> int:
	var found := -1
	for c in range(1, 200):
		if not SideStreets.mouths_at(c).is_empty() and not Junction.touches(c - 1) and not Junction.touches(c + 1):
			found = c
			break
	_check(found > 0, "no chunk with a mouth in the first 200")
	if found < 0:
		return -1
	var mouths: Array = SideStreets.mouths_at(found)
	seed(7)
	var on: Node3D = B.build_chunk(found, CFG, CFG)
	root.add_child(on)
	SideStreets.enabled = false
	seed(7)
	var off: Node3D = B.build_chunk(found, CFG, CFG)
	root.add_child(off)
	SideStreets.enabled = true
	_check(off.get_meta("side_streets").is_empty(), "switch off: still laid out %d mouths" % off.get_meta("side_streets").size())
	for i in B._building_slots() * 2:
		var mi_on: MeshInstance3D = on.get_node(NodePath("BuildingMesh%d" % i))
		var mi_off: MeshInstance3D = off.get_node(NodePath("BuildingMesh%d" % i))
		var col_on: CollisionShape3D = on.get_node(NodePath("BuildingBody%d/Shape" % i))
		var side := 1 if i % 2 == 0 else -1
		var m: Dictionary = SideStreets.mouth_for(mouths, side, i / 2)
		if m.is_empty():
			_check(mi_on.transform.is_equal_approx(mi_off.transform) and mi_on.visible == mi_off.visible, "chunk %d building %d differs with the mouths on" % [found, i])
		else:
			_check(not mi_on.visible and col_on.disabled, "chunk %d building %d: not cleared for the mouth" % [found, i])
			_check(String(mi_on.get_meta("building_type")) == "mouth", "chunk %d building %d: type %s" % [found, i, mi_on.get_meta("building_type")])
	var placed: Array = on.get_meta("side_streets")
	_check(placed.size() == mouths.size(), "chunk %d: %d mouths picked, %d placed" % [found, mouths.size(), placed.size()])
	for p in placed:
		_check_placement(on, p, found, false)
	# the recycle path lays out the same
	var re: Node3D = B.build_chunk(found + 1, CFG, CFG)
	root.add_child(re)
	B.rebuild_chunk(re, found, CFG, CFG)
	var placed2: Array = re.get_meta("side_streets")
	_check(placed2.size() == placed.size(), "rebuilt chunk %d: %d mouths" % [found, placed2.size()])
	for i in mini(placed.size(), placed2.size()):
		_check((placed[i].kit as Transform3D).is_equal_approx(placed2[i].kit), "rebuilt chunk %d: kit %d moved" % [found, i])
	off.free()
	re.free()
	on.free()
	return found

## One mouth's pieces against the chunk's own strips and the street's frame.
func _check_placement(chunk: Node3D, p: Dictionary, c: int, hilly: bool) -> void:
	var side := int(p.side)
	var z := float(p.z)
	var kit: Transform3D = p.kit
	var length := float(p.len)
	var tag := "chunk %d side %d z %.1f%s" % [c, side, z, " (hills)" if hilly else ""]
	# where the road builder puts the pavement's outer edge at this z (the
	# chunk was built last, so its centreline frames are the cached ones)
	var cfg_w: float = B._lane_w(CFG.own_lanes if side == 1 else CFG.onc_lanes)
	var t: float = -z / B.CHUNK_LEN
	var edge: float = cfg_w + lerpf(Districts.shoulder_at(c - 1), Districts.shoulder_at(c), t) + B.CURB_W + lerpf(Districts.walk_at(c - 1), Districts.walk_at(c), t)
	var want: Vector3 = B._xf(edge * float(side), 0.0, z).origin
	_check(kit.origin.distance_to(want) < 0.03, "%s: kit starts at %s, the pavement's edge is at %s" % [tag, kit.origin, want])
	if not hilly:
		# and against the Sidewalk strip's own vertices: the nearest row (the
		# dropped kerb puts rows at the drop's edges, up to MOUTH_HALF + ramp away)
		var suffix := "Own" if side == 1 else "Onc"
		var verts: PackedVector3Array = ((chunk.get_node(NodePath("Sidewalk" + suffix)) as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var best := Vector3.ZERO
		var best_dz := 1e9
		for v in verts:
			var dz := absf(v.z - kit.origin.z)
			if dz < best_dz - 1e-4 or (dz < best_dz + 1e-4 and absf(v.x) > absf(best.x)):
				best_dz = dz
				best = v
		_check(best_dz < SideStreets.MOUTH_HALF + B.DROP_RAMP + 0.1, "%s: no pavement row near the mouth (nearest %.2f m)" % [tag, best_dz])
		_check(absf(absf(kit.origin.x) - absf(best.x)) < 0.05, "%s: kit starts at |x| %.2f, pavement edge at %.2f" % [tag, absf(kit.origin.x), absf(best.x)])
		_check(absf(kit.origin.y - best.y) < B.KERB_H + 0.03, "%s: kit at y %.3f, pavement edge at %.3f" % [tag, kit.origin.y, best.y])
	# length and direction: the far end is `length` further from the road
	var far := kit * Vector3(0.0, 0.0, -1.0)
	_check(absf(far.distance_to(kit.origin) - length) < EPS, "%s: kit is %.2f m long, wanted %.2f" % [tag, far.distance_to(kit.origin), length])
	_check(signf(far.x - kit.origin.x) == signf(float(side)), "%s: the street runs toward the road" % tag)
	_check(length >= SideStreets.LEN_MIN - EPS and length <= SideStreets.LEN_MAX + EPS, "%s: length %.1f" % [tag, length])
	# uprights: on the surface (no gap under them) and inside the street
	var kit_inv := kit.affine_inverse()
	for key in ["lamp", "sign", "car"]:
		var xf: Transform3D = p[key]
		var local := kit_inv * xf.origin  # in the kit's frame: x across, -z along (0..-1 is the street)
		_check(local.z < 0.0 and local.z > -1.0, "%s: %s at %.2f of the length" % [tag, key, -local.z])
		_check(absf(local.x) < SideStreets.MOUTH_HALF, "%s: %s %.2f m off the street's centre" % [tag, key, local.x])
		var want_y := SideStreets.KERB_H if key != "car" else 0.0
		# the surface under it: the kit's plane carried along; with hills the
		# plane is the road's pitch carried sideways, so compare in the kit frame
		_check(absf(local.y - want_y) < 0.03, "%s: %s stands %.3f above the kit's plane, wanted %.2f" % [tag, key, local.y, want_y])
		_check(xf.basis.y.dot(Vector3.UP) > 0.999, "%s: %s is not upright" % [tag, key])
	# behind the building line: every piece's x is past the pavement edge
	for key in ["lamp", "sign", "car"]:
		_check(absf((p[key] as Transform3D).origin.x) > absf(kit.origin.x) + 0.5, "%s: %s in front of the pavement" % [tag, key])

## The same checks on a hilly, curved road (RoadAlignment with hills), on
## the steepest chunk with a mouth in the first 300.
func _check_hills(found: int) -> void:
	RoadFrame.align = RoadAlignment.new(2026, 1.0, 1.0)
	var best := -1
	var best_g := 0.0
	for c in range(1, 300):
		if SideStreets.mouths_at(c).is_empty() or Junction.touches(c - 1) or Junction.touches(c + 1):
			continue
		var g := absf(RoadFrame.start_grade(c))
		if g > best_g:
			best_g = g
			best = c
	if best < 0:
		best = found
	print("side_streets: hills check on chunk %d, grade %.1f%%" % [best, best_g * 100.0])
	_check(RoadFrame.has_hills(), "the alignment has no hills")
	var chunk: Node3D = B.build_chunk(best, CFG, CFG)
	root.add_child(chunk)
	for p in chunk.get_meta("side_streets"):
		_check_placement(chunk, p, best, true)
	chunk.free()
	RoadFrame.align = null

func _check_meshes() -> void:
	for pair in [["kit", SideStreets.kit_mesh()], ["props", SideStreets.prop_mesh()], ["animal", StreetAnimals.mesh()]]:
		var mesh: ArrayMesh = pair[1]
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n_tris := (idx.size() if idx.size() > 0 else verts.size()) / 3
			var bad := 0
			for t in n_tris:
				var i := [t * 3, t * 3 + 1, t * 3 + 2]
				if idx.size() > 0:
					i = [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
				var a: Vector3 = verts[i[0]]
				var b: Vector3 = verts[i[1]]
				var cc: Vector3 = verts[i[2]]
				var face := (cc - a).cross(b - a)
				if face.length() < 1e-7:
					bad += 1
					continue
				for k in 3:
					var nrm: Vector3 = normals[i[k]]
					if absf(nrm.length() - 1.0) > 1e-3 or nrm.dot(face.normalized()) < 0.99:
						bad += 1
						break
			_check(bad == 0, "%s mesh surface %d: %d of %d triangles have no area or a normal against their winding" % [pair[0], s, bad, n_tris])
			print("side_streets: %s mesh, %d triangles" % [pair[0], n_tris])

## A fake player: a Node3D with a "Headlights" spot, like CarFx attaches.
func _player(headlights_on: bool) -> Node3D:
	var p := Node3D.new()
	var spot := SpotLight3D.new()
	spot.name = "Headlights"
	spot.spot_angle = 30.0
	spot.light_energy = 2.0
	p.add_child(spot)
	p.set_meta("headlights_on", headlights_on)
	root.add_child(p)
	return p

func _check_animals(found: int) -> void:
	# a chunk with at least one animal, built in the tree so global transforms work
	var chunk: Node3D = null
	var c_used := -1
	for c in range(1, 400):
		var ch: Node3D = B.build_chunk(c, CFG, CFG)
		if (ch.get_meta("animals") as Array).size() > 0:
			chunk = ch
			c_used = c
			break
		ch.free()
	_check(chunk != null, "no chunk with an animal in the first 400")
	if chunk == null:
		return
	root.add_child(chunk)
	var list: Array = chunk.get_meta("animals")
	_check(list.size() <= StreetAnimals.CAPACITY, "chunk %d: %d animals" % [c_used, list.size()])
	var mouths: Array = SideStreets.mouths_at(c_used)
	for a in list:
		var pos: Vector3 = a.pos
		var ok := false
		for m in mouths:
			if absf(absf(pos.z - float(m.z)) - (SideStreets.MOUTH_HALF + 0.5)) < 0.05 and signf(pos.x) == signf(float(m.side)):
				ok = true
		for i in B._building_slots() * 2:
			var mi: MeshInstance3D = chunk.get_node(NodePath("BuildingMesh%d" % i))
			if mi.visible and String(mi.get_meta("building_type")) in ["shop", "diner", "garage"]:
				var sz: Vector3 = mi.transform.basis.get_scale()
				var front := absf(mi.transform.origin.x) - sz.x / 2.0
				if absf(absf(pos.x) - (front - 0.4)) < 0.05 and absf(pos.z - mi.transform.origin.z) < sz.z / 2.0:
					ok = true
		_check(ok, "chunk %d: an animal at %s is at no mouth corner or shop front" % [c_used, pos])
		_check(float(a.shine) == 0.0 and int(a.state) == 0, "chunk %d: an animal starts lit or moving" % c_used)
	print("side_streets: chunk %d has %d animal(s)" % [c_used, list.size()])
	# aim a spot at the first one from 25 m up the road: shine, then it bolts
	var a0: Dictionary = list[0]
	var start_pos: Vector3 = a0.pos
	var target: Vector3 = chunk.global_transform * start_pos
	var p := _player(true)
	p.global_position = target + Vector3(0.0, 0.0, 25.0)
	p.look_at(target + Vector3(0.0, 0.6, 0.0), Vector3.UP)  # -Z at the animal
	(p.get_node(^"Headlights") as SpotLight3D).position = Vector3(0.0, 0.6, 0.0)
	var lit_at := -1.0
	var t := 0.0
	while t < 1.0 and lit_at < 0.0:
		StreetAnimals.step([chunk], p, 1.0 / 60.0)
		t += 1.0 / 60.0
		if float(a0.shine) > 0.6:
			lit_at = t
	_check(lit_at >= 0.0, "aimed at it for 1 s: shine only %.2f" % float(a0.shine))
	while t < 1.0 + StreetAnimals.HOLD + StreetAnimals.FLEE_TIME + 0.5:
		StreetAnimals.step([chunk], p, 1.0 / 60.0)
		t += 1.0 / 60.0
	_check(int(a0.state) == 2, "after the hold and flee time its state is %d, not gone" % int(a0.state))
	var moved := (a0.pos as Vector3).distance_to(start_pos)
	_check(moved > 1.0, "it fled only %.2f m" % moved)
	_check(absf((a0.pos as Vector3).y - start_pos.y) < 0.05, "it fled %.2f m up or down" % ((a0.pos as Vector3).y - start_pos.y))
	_check(StreetAnimals._xf(a0).basis.get_scale().length() < 1e-6, "gone but still drawn at scale %s" % StreetAnimals._xf(a0).basis.get_scale())
	# the chunk rebuilt (new draws, so maybe another animal): the player 25 m
	# up the road from it, beam pointing away; it stays dark and put
	B.rebuild_chunk(chunk, c_used, CFG, CFG)
	list = chunk.get_meta("animals")
	var a1: Dictionary = list[0]
	target = chunk.global_transform * (a1.pos as Vector3)
	p.global_position = target + Vector3(0.0, 0.0, 25.0)
	p.look_at(target + Vector3(0.0, 0.6, 60.0), Vector3.UP)
	for k in 120:
		StreetAnimals.step([chunk], p, 1.0 / 60.0)
	_check(float(a1.shine) < 0.05 and int(a1.state) == 0, "aimed away: shine %.2f state %d" % [float(a1.shine), int(a1.state)])
	# lights off (the spot hidden, as PlayerCar does), aimed at it: nothing
	p.free()
	var dark := _player(false)
	dark.global_position = target + Vector3(0.0, 0.0, 25.0)
	dark.look_at(target + Vector3(0.0, 0.6, 0.0), Vector3.UP)
	(dark.get_node(^"Headlights") as SpotLight3D).visible = false
	for k in 120:
		StreetAnimals.step([chunk], dark, 1.0 / 60.0)
	_check(float(a1.shine) < 0.05 and int(a1.state) == 0, "lights off: shine %.2f state %d" % [float(a1.shine), int(a1.state)])
	dark.free()
	chunk.free()
	await process_frame
