extends SceneTree

# Sidewalk collision taper test (issue #35).
#
# The "Dirt" collision under each sidewalk used to be one box at the chunk's
# average width, up to 1.15 m off the drawn sidewalk at the ends of a
# lane-count-change chunk. This builds chunks that widen and narrow on both
# sides, then casts rays straight down just inside and just outside the drawn
# sidewalk edges at several points along the chunk: inside must hit a Dirt
# body, outside must hit nothing (no road slab is added here). The same is
# checked after recycling the chunk root, since the shape is reused.
#
# Run (headless is fine -- no MultiMesh data is read):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/sidewalk_collision_taper.gd
# Exit code 0 = pass.

const B := preload("res://scripts/world/road_chunk_builder.gd")
const MARGIN := 0.1  # metres inside/outside the drawn edge
const CASES := [
	[{"own_lanes": 2, "onc_lanes": 1, "barrier": false}, {"own_lanes": 4, "onc_lanes": 2, "barrier": false}],
	[{"own_lanes": 4, "onc_lanes": 2, "barrier": false}, {"own_lanes": 2, "onc_lanes": 1, "barrier": true}],
	[{"own_lanes": 3, "onc_lanes": 2, "barrier": false}, {"own_lanes": 3, "onc_lanes": 2, "barrier": false}],
]

var fails := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var chunk: Node3D = B.build_chunk(0, CASES[0][0], CASES[0][1])
	holder.add_child(chunk)
	for c in CASES:
		B.rebuild_chunk(chunk, 0, c[0], c[1])
		await physics_frame
		await physics_frame
		_check(chunk, c[0], c[1])
	print("sidewalk_collision_taper: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)

func _check(chunk: Node3D, prev_cfg: Dictionary, cfg: Dictionary) -> void:
	var space := chunk.get_world_3d().direct_space_state
	for side in [1, -1]:
		var key := "own_lanes" if side == 1 else "onc_lanes"
		var inner0: float = B._lane_w(prev_cfg[key]) + B.SHOULDER_W + B.CURB_W
		var inner1: float = B._lane_w(cfg[key]) + B.SHOULDER_W + B.CURB_W
		for t in [0.02, 0.25, 0.5, 0.75, 0.98]:
			var z: float = -t * B.CHUNK_LEN
			var inner: float = lerp(inner0, inner1, t)
			var outer: float = inner + B.SIDEWALK_W
			for probe in [
				[inner - MARGIN, false, "before sidewalk"],
				[inner + MARGIN, true, "sidewalk inner edge"],
				[outer - MARGIN, true, "sidewalk outer edge"],
				[outer + MARGIN, false, "past sidewalk"],
			]:
				var x: float = probe[0] * side
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, 5.0, z), Vector3(x, -1.0, z))
				var hit := space.intersect_ray(q)
				var is_dirt: bool = not hit.is_empty() and (hit.collider as Node).is_in_group("Dirt")
				checks += 1
				if is_dirt != probe[1]:
					fails += 1
					printerr("FAIL %s->%s side %d t=%.2f %s at x=%.2f: dirt=%s" % [prev_cfg[key], cfg[key], side, t, probe[2], x, is_dirt])
