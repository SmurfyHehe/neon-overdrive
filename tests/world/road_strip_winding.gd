extends SceneTree

# Winding test for the road's tapered strips (ISSUES B5, #23): every triangle
# of every strip must have non-zero area and be wound CLOCKWISE seen from
# above (Godot's front face), and no strip material may be two-sided. The
# strips used to wind counter-clockwise on the player's side and clockwise on
# the mirrored oncoming side; CULL_DISABLED on the asphalt hid that, while the
# player-side curb and edge line (single-sided) simply never rendered.
#
# Replaces tests/chunk_builder_equivalence.gd, which guarded the 01a84cb
# refactor and was retired here by design.
#
# Run (headless is fine, no MultiMesh involved):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/road_strip_winding.gd

const AREA_EPS := 1e-6
const STRIPS := [
	"RoadOwn", "RoadOnc", "EdgeLineOwn", "EdgeLineOnc", "ShoulderOwn",
	"ShoulderOnc", "CurbOwn", "CurbOnc", "SidewalkOwn", "SidewalkOnc",
]

func _initialize() -> void:
	var fails := 0
	var cases := 0
	# Every (previous config -> config) pair the game can roll, so tapering
	# strips (start width != end width) are covered on both sides.
	for po in [2, 3, 4]:
		for pn in [1, 2]:
			for o in [2, 3, 4]:
				for n in [1, 2]:
					var prev := {"own_lanes": po, "onc_lanes": pn, "barrier": false}
					var cfg := {"own_lanes": o, "onc_lanes": n, "barrier": false}
					var chunk: Node3D = RoadChunkBuilder.build_chunk(cases, prev, cfg)
					for strip_name in STRIPS:
						fails += _check_strip(chunk.get_node(NodePath(strip_name)), "%s %s -> %s" % [strip_name, prev, cfg])
					chunk.free()
					cases += 1
	print("cases: %d, strips each: %d" % [cases, STRIPS.size()])
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _check_strip(mi: MeshInstance3D, label: String) -> int:
	var fails := 0
	var mat := mi.material_override as BaseMaterial3D
	if mat != null and mat.cull_mode != BaseMaterial3D.CULL_BACK:
		print("FAIL %s: material cull_mode is %d, expected CULL_BACK" % [label, mat.cull_mode])
		fails += 1
	var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for t in verts.size() / 3:
		var a := verts[t * 3]
		var b := verts[t * 3 + 1]
		var c := verts[t * 3 + 2]
		# Outward normal of a clockwise (Godot front-facing) triangle.
		var face := (c - a).cross(b - a)
		if face.length() < AREA_EPS:
			print("FAIL %s tri %d: zero area" % [label, t])
			fails += 1
		elif face.normalized().y < 0.99:
			print("FAIL %s tri %d: front face %s does not point up" % [label, t, face.normalized()])
			fails += 1
	return fails
