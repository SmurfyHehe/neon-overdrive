extends SceneTree

# Floating-structures scan (2026-10-09): nothing a chunk draws may hang in
# the air. Roy saw roadside structures floating in the sky in his play build.
#
# The scan runs the way the game does: a pool of chunks lives in the tree,
# and every frame some are rebuilt in place as the next chunk index
# (RoadChunkBuilder.rebuild_chunk, the recycle path), on a flat road, a curvy
# hilly one and a kicker-crest one, through every district. A chunk is
# checked a few frames after its rebuild, reading the MultiMesh buffers the
# renderer actually draws: with physics interpolation on (project setting)
# those lag the writes, which is how the first fix's in-frame scan missed
# the real bug (a rebuilt chunk kept its previous occupant's roof props,
# office water tanks 40 m over a one-floor lot).
#
# Every piece -- building, gap wall, lamp, pylon, barrier piece, reflector,
# dash, light pool, sign, billboard, roof prop -- must have its lowest point
# on a support, within TOL:
# - the road surface at that spot (ground; reaching below it, or being
#   hidden entirely under it, is fine), or
# - the top face of a building it stands on, or
# - another piece of the chunk it rests on or is threaded through (a canopy
#   on its columns, a billboard panel on its poles, the diner sign on its
#   pole), or, for wall signs only,
# - a building wall: the sign is against the building and within its height.
#
# Asserts (exit code 1 on failure): no unsupported piece, and all four
# districts were seen on every road.
#
# Needs a real window: headless drops MultiMesh instance data.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/world/floating_structures.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const RoofProps := preload("res://scripts/world/roof_props.gd")
const Districts := preload("res://scripts/world/districts.gd")

const TOL := 0.05
## A wall sign hangs off a bracket: how far from the wall it may sit.
const MOUNT := 0.25
## Chunks per road: 12 district runs of 16.
const CHUNKS := 192
const POOL := 8
## Frames between a rebuild and its check, so the drawn buffers have caught up.
const SETTLE := 4
const REBUILDS_PER_FRAME := 4
const ROADS := [
	["flat", null],
	["curvy+hilly", [7, 1.0, 1.0, 0.0]],
	["kickers", [5, 0.5, 1.0, 1.0]],
]
## Local AABB of each roof prop shape (RoofProps.mesh), before the instance scale.
const SHAPE_AABB := {
	RoofProps.SHAPE_BOX: [Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0)],
	RoofProps.SHAPE_TANK: [Vector3(-0.75, 0.0, -0.75), Vector3(1.5, 3.6, 1.5)],
	RoofProps.SHAPE_ANTENNA: [Vector3(-0.8, 0.0, -0.6), Vector3(1.6, 6.14, 1.2)],
	RoofProps.SHAPE_CANOPY: [Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0)],
	RoofProps.SHAPE_FLOOD: [Vector3(-0.25, 0.0, -0.35), Vector3(0.5, 5.15, 0.7)],
}
const GROUND_NAMES := ["RoadOwn", "RoadOnc", "EdgeLineOwn", "EdgeLineOnc", "ShoulderOwn", "ShoulderOnc", "CurbOwn", "CurbOnc", "SidewalkOwn", "SidewalkOnc"]

var fails := 0
var checked := 0
var road_i := -1
var next_index := 0
var pool: Array = []  # {root, index, built_frame, checked}
var frame := 0
var districts_seen := {}
var prev := {"own_lanes": 2, "onc_lanes": 1, "barrier": false}
var cfg := {"own_lanes": 2, "onc_lanes": 1, "barrier": false}

func _fail(msg: String) -> void:
	fails += 1
	if fails <= 300:
		print("FAIL ", msg)

func _initialize() -> void:
	seed(9)
	_next_road()

func _next_road() -> void:
	for c in pool:
		c.root.free()
	pool.clear()
	road_i += 1
	if road_i >= ROADS.size():
		RoadFrame.align = null
		print("floating_structures: %d chunks x %d roads, %d pieces, %s" % [CHUNKS, ROADS.size(), checked, "PASS" if fails == 0 else "%d failure(s)" % fails])
		quit(0 if fails == 0 else 1)
		return
	var spec: Variant = ROADS[road_i][1]
	RoadFrame.align = null if spec == null else RoadAlignment.new(int(spec[0]), float(spec[1]), float(spec[2]), float(spec[3]))
	RoadFrame.origin_index = 0
	districts_seen = {}
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
			_check_chunk(c.root, int(c.index), "%s chunk %d" % [road_name, c.index])
			c.checked = true
			districts_seen[Districts.name_at(int(c.index))] = true
		if next_index < CHUNKS and rebuilt < REBUILDS_PER_FRAME:
			# the recycle path, in the tree, like game.gd's chunk pool
			B.rebuild_chunk(c.root, next_index, prev, cfg)
			c.index = next_index
			c.built_frame = frame
			c.checked = false
			next_index += 1
			rebuilt += 1
			all_done = false
	if all_done:
		for d in ["downtown", "residential", "strip", "industrial"]:
			if not districts_seen.has(d):
				_fail("%s: district %s never came up in %d chunks" % [road_name, d, CHUNKS])
		print("%s: %d chunks, districts %s" % [road_name, CHUNKS, districts_seen.keys()])
		_next_road()
	return false

## Height of the road surface under world point p (no camber, so the same
## across the road); 0 on a flat road.
func _surface_y(p: Vector3) -> float:
	var u := RoadFrame.unroll(p)
	return RoadFrame.roll(Vector3(0.0, 0.0, u.z)).y

## World AABB of a local box (origin `lo`, size `size`) under transform xf.
func _world_box(xf: Transform3D, lo: Vector3, size: Vector3) -> AABB:
	var out := AABB(xf * lo, Vector3.ZERO)
	for i in 8:
		var corner := lo + Vector3(size.x if i & 1 else 0.0, size.y if i & 2 else 0.0, size.z if i & 4 else 0.0)
		out = out.expand(xf * corner)
	return out

func _check_chunk(chunk: Node3D, idx: int, label: String) -> void:
	var W := chunk.transform
	var buildings := []  # [world xf of the unit box, world AABB, type]
	var pieces := []     # [name, instance, world AABB]
	for c in chunk.get_children():
		if c is MeshInstance3D:
			if c.name in GROUND_NAMES or not c.visible:
				continue
			var xf: Transform3D = W * c.transform
			var box := _world_box(xf, Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
			buildings.append([xf, box, String(c.get_meta("building_type", "?"))])
			pieces.append([String(c.name), 0, box])
		elif c is MultiMeshInstance3D and c.visible:
			_collect(W, c, pieces)
			for g in c.get_children():
				if g is MultiMeshInstance3D and g.visible:
					_collect(W, g, pieces)
	var signs_used: int = chunk.get_meta("signs_used", 0)
	for p in pieces:
		var name: String = p[0]
		var i: int = p[1]
		var box: AABB = p[2]
		checked += 1
		var foot := Vector3(box.position.x + box.size.x / 2.0, box.position.y, box.position.z + box.size.z / 2.0)
		# 1. on (or into) the ground, or hidden under it (the gas station sinks
		# the edge posts it clears 50 m down, #324: not floating)
		var sy := _surface_y(foot)
		if box.position.y <= sy + TOL:
			continue
		var ok := false
		# 2. on a building's top face, inside its footprint
		for b in buildings:
			var top: float = b[1].end.y
			if absf(box.position.y - top) > TOL:
				continue
			var q: Vector3 = (b[0].affine_inverse() * foot).abs()
			if q.x <= 0.5 + TOL / b[0].basis.get_scale().x and q.z <= 0.5 + TOL / b[0].basis.get_scale().z:
				ok = true
				break
		# 3. on, or threaded on, another piece (not a building, not itself)
		if not ok:
			var margin := MOUNT if name == "Signs" else TOL
			for o in pieces:
				if o == p or o[0].begins_with("BuildingMesh"):
					continue
				var ob: AABB = o[2]
				# the other piece reaches up to (or through) this one's bottom
				var inside := ob.end.y >= box.position.y - TOL and ob.position.y <= box.end.y + TOL
				var overlap := ob.end.x >= box.position.x - margin and ob.position.x <= box.end.x + margin \
						and ob.end.z >= box.position.z - margin and ob.position.z <= box.end.z + margin
				if inside and overlap:
					ok = true
					break
		# 4. a wall sign: against a building and within its height
		if not ok and name == "Signs" and i < signs_used:
			for b in buildings:
				var bb: AABB = b[1]
				var near := bb.end.x >= box.position.x - MOUNT and bb.position.x <= box.end.x + MOUNT \
						and bb.end.z >= box.position.z - MOUNT and bb.position.z <= box.end.z + MOUNT
				if near and box.position.y >= bb.position.y - TOL and box.end.y <= bb.end.y + TOL:
					ok = true
					break
		if not ok:
			var near := ""
			for b in buildings:
				var bb: AABB = b[1]
				if bb.grow(3.0).intersects(box):
					near += " [%s top %.2f]" % [b[2], bb.end.y]
			_fail("%s: %s %d bottom %.2f at (%.1f, %.1f) over nothing (ground %.2f):%s" % [label, name, i, box.position.y, foot.x, foot.z, sy, near])

func _collect(W: Transform3D, mmi: MultiMeshInstance3D, pieces: Array) -> void:
	var mm := mmi.multimesh
	var parent_xf := W
	if mmi.get_parent() is MultiMeshInstance3D:
		parent_xf = W * (mmi.get_parent() as Node3D).transform
	var mesh_box: AABB = mm.mesh.get_aabb()
	for i in mm.visible_instance_count:
		var lo := mesh_box.position
		var size := mesh_box.size
		if mmi.name == "RoofProps":
			var shape := int(mm.get_instance_custom_data(i).r)
			lo = SHAPE_AABB[shape][0]
			size = SHAPE_AABB[shape][1]
		var box := _world_box(parent_xf * mmi.transform * mm.get_instance_transform(i), lo, size)
		pieces.append([String(mmi.name), i, box])
