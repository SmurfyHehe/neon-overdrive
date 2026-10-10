extends SceneTree

# Sign placement audit (2026-10-10): every shop sign, blade, gas and diner
# sign and billboard a chunk draws is checked where it stands, like the
# floating-structures scan: a pool of chunks in the tree, rebuilt in place
# (the recycle path), read from the drawn MultiMesh buffers a few frames
# after each rebuild, on a flat road and a curvy hilly one.
#
# Per sign:
# - it faces the road (a band) or the oncoming traffic (a blade, the diner
#   sign); never away from the road or backwards,
# - no part of it hangs over the road, shoulder or curb (the sidewalk is
#   fine: blades do),
# - its bottom clears a car: at least CLEAR over the road surface,
# - the letters are not squeezed: the lightbox is as long as its word needs
#   for its height (a squeezed pixel font drops columns),
# - its word, colour and style are valid, a shop sign is lit (style 0 or 1),
#   a billboard dim (style 2),
# - its height is a sign's, not a wall's or a sliver's,
# - it overlaps no other sign.
#
# Needs a real window: headless drops MultiMesh instance data.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/world/sign_audit.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Signs := preload("res://scripts/world/building_signs.gd")
const Districts := preload("res://scripts/world/districts.gd")

const CHUNKS := 128
const POOL := 8
const SETTLE := 4
const REBUILDS_PER_FRAME := 4
const CLEAR := 2.2
const ROADS := [
	["flat", null],
	["curvy+hilly", [7, 1.0, 1.0, 0.0]],
]

var fails := 0
var checked := 0
var road_i := -1
var next_index := 0
var pool: Array = []
var frame := 0
var prev := {"own_lanes": 2, "onc_lanes": 1, "barrier": false}
var cfg := {"own_lanes": 2, "onc_lanes": 1, "barrier": false}
var kinds := {}

func _fail(msg: String) -> void:
	fails += 1
	if fails <= 200:
		print("FAIL ", msg)

func _initialize() -> void:
	seed(11)
	_next_road()

func _next_road() -> void:
	for c in pool:
		c.root.free()
	pool.clear()
	road_i += 1
	if road_i >= ROADS.size():
		RoadFrame.align = null
		print("sign_audit: %d chunks x %d roads, %d signs %s, %s" % [CHUNKS, ROADS.size(), checked, kinds, "PASS" if fails == 0 else "%d failure(s)" % fails])
		quit(0 if fails == 0 else 1)
		return
	var spec: Variant = ROADS[road_i][1]
	RoadFrame.align = null if spec == null else RoadAlignment.new(int(spec[0]), float(spec[1]), float(spec[2]), float(spec[3]))
	RoadFrame.origin_index = 0
	next_index = 0
	for k in POOL:
		var chunk: Node3D = B.build_chunk(next_index, prev, cfg)
		root.add_child(chunk)
		pool.append({"root": chunk, "index": next_index, "built_frame": frame, "checked": false})
		next_index += 1

func _process(_delta: float) -> bool:
	frame += 1
	if road_i >= ROADS.size():
		return true
	var road_name: String = ROADS[road_i][0]
	var all_done := true
	var rebuilt := 0
	for c in pool:
		if not c.checked:
			if frame - c.built_frame < SETTLE:
				all_done = false
				continue
			_check_chunk(c.root, int(c.index), "%s chunk %d (%s)" % [road_name, c.index, Districts.name_at(int(c.index))])
			c.checked = true
		if next_index < CHUNKS and rebuilt < REBUILDS_PER_FRAME:
			B.rebuild_chunk(c.root, next_index, prev, cfg)
			c.index = next_index
			c.built_frame = frame
			c.checked = false
			next_index += 1
			rebuilt += 1
			all_done = false
	if all_done:
		print("%s: %d chunks" % [road_name, CHUNKS])
		_next_road()
	return false

## Road-space (x across, y up off the surface, z along) of a world point.
func _road(p: Vector3) -> Vector3:
	return RoadFrame.unroll(p)

func _check_chunk(chunk: Node3D, idx: int, label: String) -> void:
	var mmi := chunk.get_node_or_null(^"Signs") as MultiMeshInstance3D
	if mmi == null:
		return
	var mm := mmi.multimesh
	var signs_used: int = chunk.get_meta("signs_used", 0)
	var W := chunk.transform * mmi.transform
	var road_half := float(cfg.own_lanes) * B.LANE_W + B.MEDIAN_GAP + B.SHOULDER_W + B.CURB_W
	var onc_half := float(cfg.onc_lanes) * B.LANE_W + B.MEDIAN_GAP + B.SHOULDER_W + B.CURB_W
	var boxes := []  # [i, world AABB]
	var words := Signs.words()
	for i in mm.visible_instance_count:
		var xf: Transform3D = W * mm.get_instance_transform(i)
		var cd := mm.get_instance_custom_data(i)
		var sc := xf.basis.get_scale()
		var depth := sc.x
		var height := sc.y
		var length := sc.z
		var row := int(cd.r)
		var px := int(cd.g)
		var color := int(cd.b)
		var style := int(cd.a)
		var billboard := i >= signs_used
		var kind := "billboard" if billboard else "sign"
		var word: String = words[row] if row >= 0 and row < words.size() else "?"
		var tag := "%s: %s %d %s" % [label, kind, i, word]
		checked += 1
		kinds[kind] = kinds.get(kind, 0) + 1
		# word, colour, style
		if row < 0 or row >= words.size():
			_fail("%s: word row %d is not a word" % [tag, row])
		elif Signs.word_px(word) != px:
			_fail("%s: word width %d px, custom data says %d" % [tag, Signs.word_px(word), px])
		if color < 0 or color >= Signs.COLORS.size():
			_fail("%s: colour %d is not in the palette" % [tag, color])
		if billboard and style != 2:
			_fail("%s: billboard style %d, expected 2 (dim floodlit)" % [tag, style])
		if not billboard and style != 0 and style != 1:
			_fail("%s: style %d, expected 0 or 1 (lit)" % [tag, style])
		# size and squeeze
		if height < 0.3 or height > 2.05:
			_fail("%s: height %.2f m" % [tag, height])
		var want_len := height * float(px + 4) / float(Signs.ROW_PX)
		if absf(length - want_len) > 0.02 * want_len + 0.005:
			_fail("%s: %.2f m long for %.2f m tall, the word needs %.2f (squeezed or stretched letters)" % [tag, length, height, want_len])
		if absf(depth - 0.18) > 0.01:
			_fail("%s: depth %.2f m" % [tag, depth])
		# where it is, in road space
		var corners := []
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var box := AABB(xf.origin, Vector3.ZERO)
		for k in 8:
			var c := Vector3(-0.5 if k & 1 else 0.5, -0.5 if k & 2 else 0.5, -0.5 if k & 4 else 0.5)
			var wp: Vector3 = xf * c
			box = box.expand(wp)
			var rp := _road(wp)
			corners.append(rp)
			lo = lo.min(rp)
			hi = hi.max(rp)
		boxes.append([i, box.grow(-0.02), tag])
		var centre := _road(xf.origin)
		var side := 1.0 if centre.x > 0.0 else -1.0
		var inner := minf(absf(lo.x), absf(hi.x))
		if lo.x < 0.0 and hi.x > 0.0:
			inner = 0.0
		var edge := road_half if side > 0.0 else onc_half
		if inner < edge - 0.05:
			_fail("%s: reaches %.2f m from the centre line, the curb is at %.2f (over the road)" % [tag, inner, edge])
		if lo.y < CLEAR and not billboard:
			_fail("%s: bottom %.2f m over the road, under %.1f (a car would hit it)" % [tag, lo.y, CLEAR])
		# facing: the lit front is local -x
		var n: Vector3 = -xf.basis.x.normalized()
		var rb := RoadFrame.basis_at(centre.z)
		var nl: Vector3 = rb.transposed() * n
		var to_road := nl.x * -side
		var to_traffic := nl.z  # +z is toward drivers coming down the road
		if to_road < 0.6 and to_traffic < 0.8:
			_fail("%s: faces (%.2f across toward the road, %.2f toward the traffic): away from the road or backwards" % [tag, to_road, to_traffic])
	# overlaps
	for a in boxes.size():
		for b in range(a + 1, boxes.size()):
			if boxes[a][1].intersects(boxes[b][1]):
				_fail("%s overlaps %s" % [boxes[a][2], boxes[b][2].get_slice(": ", 1)])
