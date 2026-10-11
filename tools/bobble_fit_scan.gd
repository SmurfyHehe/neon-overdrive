extends SceneTree

# Scans a car's bobble head fit (interiors B1, 2026-10-11): for the kinds in
# BOBBLE_KINDS (default "p0_beater,p4_kei"), every along / scale / lean-cap
# combination's worst glass-line clearance over every figure in the catalogue
# at the eight largest leans, so the gentlest fit that keeps CLEAR_M can be
# put in CabinSpots. (Found 2026-10-11: the lean cap hardly matters, the
# margin is the standing height, so along and scale are the levers.) Headless:
#   <godot> --headless --audio-driver Dummy --path . -s res://tools/bobble_fit_scan.gd

const CLEAR_M := 0.010
const ALONGS := [0.05, 0.2, 0.4, 0.62, 0.8]
const SCALES := [1.0, 0.9, 0.8, 0.7, 0.6]
const TILTS := [0.55, 0.40, 0.30, 0.25, 0.20, 0.15]

func _initialize() -> void:
	var kinds := OS.get_environment("BOBBLE_KINDS")
	if kinds == "":
		kinds = "p0_beater,p4_kei"
	var meshes := {}
	var b := BobbleHead.new(null, "p1_coupe")
	root.add_child(b)
	for id in BobbleFigures.IDS:
		if id == BobbleFigures.NONE:
			continue
		b.set_figure(id)
		meshes[id] = b.mesh_instance().mesh
	b.free()
	for kind in kinds.split(","):
		var cab := CabinSpec.for_kind(kind)
		var cowl: Vector2 = cab.cowl
		var header: Vector2 = cab.header
		var p0 := Vector2(cowl.y, cowl.x + 0.086 - 0.008)
		var p1 := Vector2(header.y, header.x - 0.008)
		var gdir := (p1 - p0).normalized()
		print("== %s (today: along %.2f, scale %.2f)" % [kind, CabinSpots.bobble_fit(kind).get("along", CabinSpots.DASH_PASS_ALONG), CabinSpots.dash_pass_scale(kind)])
		for along in ALONGS:
			var spot := _spot(cab, float(along))
			var line := "along %.2f:" % float(along)
			for sc in SCALES:
				for t in TILTS:
					var worst := INF
					var who := ""
					var d := float(t) * 0.7071
					var combos := [Vector2(t, 0), Vector2(-t, 0), Vector2(0, t), Vector2(0, -t), Vector2(d, d), Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2.ZERO]
					for id in meshes:
						var arr := (meshes[id] as ArrayMesh).surface_get_arrays(0)
						var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
						var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
						var uv2s: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
						for bob in combos:
							for i in verts.size():
								var p := spot + BobbleHead.bobbed_vertex(verts, uvs, uv2s, i, bob) * float(sc)
								if p.z >= cowl.y - 0.05 and p.z <= header.y:
									var wv := Vector2(p.z, p.y) - p0
									var below := -(gdir.x * wv.y - gdir.y * wv.x)
									if below < worst:
										worst = below
										who = id
					line += "  s%.1f/t%.2f %+.1f" % [float(sc), float(t), worst * 100.0]
					if worst >= CLEAR_M:
						line += "*"
				line += "\n           "
			print(line)
	quit(0)

## CabinSpots.dash_pass with the along overridden.
static func _spot(cab: Dictionary, along: float) -> Vector3:
	var cowl: Vector2 = cab.cowl
	var face_z := float(cab.dash_face_z)
	var cluster: Vector2 = cab.cluster
	var eye: Vector3 = cab.eye
	var z := lerpf(cowl.y, face_z, along)
	var y := lerpf(cowl.x, cluster.x, along)
	var x := eye.x + tan(deg_to_rad(CabinSpots.DASH_PASS_DEG)) * (eye.z - z)
	var door_x := float(cab.door_x)
	var pillar_foot: Vector3 = cab.a_pillar[0]
	var dash_half := minf(float(cab.get("door_x_front", door_x)) + 0.04, pillar_foot.x - 0.03)
	x = minf(x, minf(dash_half - 0.06, door_x - 0.25))
	return Vector3(x, y, z)
