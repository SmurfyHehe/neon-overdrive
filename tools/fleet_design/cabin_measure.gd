extends SceneTree
# Measures each player car's body for its cabin (interior pass, 2026-10-09)
# and prints a proposed CABIN dictionary for its data file: the windshield,
# side and rear glass panes from the body mesh's "glass" surface, the skin's
# half width at the belt, cowl, floor and roof by rays from the centreline,
# then every interior anchor derived from those with the P1 coupe's own
# cabin as the calibration (its dictionary reproduces the hand-built P1
# numbers of cockpit_frame.gd). Car space, lift included (the car at rest).
#
# The seat (height over the floor, fore-aft) and the style words are the
# hand-set part per car, in SEAT below; the rest follows the body.
#
#   <godot> --headless --path . -s res://tools/fleet_design/cabin_measure.gd
#   NEON_FIT_CAR=p4_kei limits it to one car.

## Hand-set per car: cushion top over the carpet, how far behind the
## windshield header the eye sits, and the style words the builder reads.
const SEAT := {
	"p0_beater":    {"seat_h": 0.30, "eye_back": 0.34, "console": "flat",   "seats": "flat",   "cluster": "pod",    "speedo": 160.0},
	"p1_coupe":     {"seat_h": 0.21, "eye_back": 0.34, "console": "tunnel", "seats": "bucket", "cluster": "dials",  "speedo": 300.0},
	"p2_hothatch":  {"seat_h": 0.27, "eye_back": 0.36, "console": "tunnel", "seats": "bucket", "cluster": "dials",  "speedo": 240.0},
	"p3_tuner":     {"seat_h": 0.22, "eye_back": 0.36, "console": "tunnel", "seats": "bucket", "cluster": "triple", "speedo": 280.0},
	"p4_kei":       {"seat_h": 0.19, "eye_back": 0.30, "console": "tunnel", "seats": "bucket", "cluster": "dials",  "speedo": 180.0},
	"p5_muscle":    {"seat_h": 0.23, "eye_back": 0.36, "console": "tunnel", "seats": "bench",  "cluster": "strip",  "speedo": 260.0},
	"p6_crossover": {"seat_h": 0.31, "eye_back": 0.38, "console": "tunnel", "seats": "bucket", "cluster": "dials",  "speedo": 260.0},
}

var skin: Array = []   # [a, b, c, n]

func _initialize() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		if only != "" and kind != only:
			continue
		_measure(kind)
	quit(0)

func _measure(kind: String) -> void:
	var vis: Node3D
	if kind == P1CoupeBuilder.KIND:
		vis = P1CoupeBuilder.build_chassis_visual()
	else:
		vis = NpcCarBuilder.chassis_visual(kind, "stock", NpcCarBuilder.sheet_paint(kind))
	var body: MeshInstance3D = vis.find_child("Body", true, false)
	var mesh: ArrayMesh = body.mesh
	var lift: Vector3 = body.position
	var glass := []
	skin = []
	for s in mesh.get_surface_count():
		if mesh.surface_get_name(s) == "flare":
			continue
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var into := glass if mesh.surface_get_name(s) == "glass" else skin
		for t in verts.size() / 3:
			var a: Vector3 = verts[t * 3] + lift
			var b: Vector3 = verts[t * 3 + 1] + lift
			var c: Vector3 = verts[t * 3 + 2] + lift
			var n := (b - a).cross(c - a)
			if n.length_squared() < 1e-12:
				continue
			into.append([a, b, c, -n.normalized()])   # a, c, b winding: the design normal is the opposite
	for t in glass:
		skin.append(t)   # the glass is part of the shell too
	var wind := _pane(glass, func(t: Array) -> bool: return t[3].z < -0.35 and t[3].y > 0.2 and absf(_cx(t)) < 0.45)
	var rear := _pane(glass, func(t: Array) -> bool: return t[3].z > 0.35 and t[3].y > 0.1 and absf(_cx(t)) < 0.45)
	var side := _pane(glass, func(t: Array) -> bool: return t[3].x < -0.6)
	var open_top := rear.size.z < 0.12 or rear.position.z < wind.end.z + 0.2
	var hand: Dictionary = SEAT[kind]
	var floor_y := _floor()
	var roof_y := _roof(side)
	var belt_y := side.position.y
	# the eye, from the header and the seat
	var carpet_y := floor_y + 0.016
	var seat_h := carpet_y + float(hand.seat_h)
	var eye_z := wind.end.z + float(hand.eye_back)
	var seat_z := eye_z + 0.06
	var seat_x := -0.36 if _half(belt_y - 0.06, seat_z) > 0.85 else -(_half(belt_y - 0.06, seat_z) * 0.42)
	var eye := Vector3(seat_x + 0.04, seat_h + 0.62, eye_z)
	var cowl_z := wind.position.z - 0.01
	var wheel := Vector3.ZERO
	var cluster := Vector2.ZERO
	var cowl_y := minf(wind.position.y - 0.086, eye.y - tan(deg_to_rad(15.0)) * (eye.z - cowl_z))
	var header := Vector2(wind.end.y + 0.005, wind.end.z + 0.01)
	var door_face := _half(belt_y - 0.06, seat_z) - 0.096
	var door_face_rear := _half(belt_y - 0.06, seat_z + 0.5) - 0.096
	var door_face_front := _half(belt_y - 0.06, cowl_z + 0.30) - 0.096
	var pillar_foot_x := _half(cowl_y, cowl_z + 0.08) - 0.045
	var pillar_top_x := _half(header.x - 0.06, header.y + 0.06) - 0.08
	var b_pillar_z := minf(seat_z + 0.10, side.end.z - 0.05)
	var rear_z := maxf(rear.position.z - 0.14, seat_z + 0.56) if not open_top else seat_z + 0.50
	wheel = Vector3(seat_x, eye.y - 0.33, eye.z - 0.48)
	cluster = Vector2(eye.y - 0.17, eye.z - 0.649)
	# a body that draws its own tub (the kei) has a floor above the underside
	# A body that draws its own tub (the kei: floor at 0.54, 0.42 m over the
	# road) is only reported: seating the driver on it put the eye over the
	# windshield header, so the cabin keeps the real floor and the tub hides
	# the seat bases from outside.
	var tub_floor := _down(Vector3(seat_x, belt_y, seat_z))
	if tub_floor > carpet_y + 0.02:
		print("   (the body draws a tub floor at %.3f; the cabin floor stays at %.3f)" % [tub_floor, carpet_y])
	var dash_face_z := wheel.z - 0.15
	print("== %s ==   body x %.2f y %.2f..%.2f z %.2f..%.2f | windshield y %.3f..%.3f z %.2f..%.2f | side y %.3f..%.3f z %.2f..%.2f | rear y %.3f z %.2f..%.2f | roof %.3f floor %.3f%s"
		% [kind, _half(belt_y - 0.06, seat_z), floor_y, roof_y, _zmin(), _zmax(), wind.position.y, wind.end.y, wind.position.z, wind.end.z,
		side.position.y, side.end.y, side.position.z, side.end.z, rear.position.y, rear.position.z, rear.end.z, roof_y, floor_y, " OPEN TOP" if open_top else ""])
	var sight := rad_to_deg(atan2(eye.y - cowl_y, eye.z - cowl_z))
	print("   eye %s: cowl %.1f deg below, roof %.2f m above%s" % [str(eye), sight, roof_y - eye.y, "" if open_top else ""])
	var lines := [
		"## The cabin, car space (the car at rest, lift included), measured from this",
		"## body by tools/fleet_design/cabin_measure.gd (2026-10-09) and hand-tuned.",
		"## CockpitFrame builds the interior from these; nothing in it is the coupe's.",
		"const CABIN := {",
		'\t"seat_x": %.3f, "seat_h": %.3f, "seat_z": %.3f,' % [seat_x, seat_h, seat_z],
		'\t"eye": Vector3(%.3f, %.3f, %.3f),' % [eye.x, eye.y, eye.z],
		'\t"floor_y": %.3f, "belt_y": %.3f,' % [carpet_y, belt_y],
		'\t"cowl": Vector2(%.3f, %.3f), "dash_face_z": %.3f,' % [cowl_y, cowl_z, dash_face_z],
		'\t"header": Vector2(%.3f, %.3f), "roof_y": %.3f, "roof_z1": %.3f, "open_top": %s,' % [header.x, header.y, (roof_y - 0.03) if not open_top else header.x, rear.position.z - 0.06 if not open_top else rear_z, "true" if open_top else "false"],
		'\t"door_x": %.3f, "door_x_rear": %.3f, "door_x_front": %.3f, "glass_x": %.3f, "glass_top": %.3f,' % [door_face, door_face_rear, door_face_front, _half(belt_y + 0.10, seat_z) - 0.05, side.end.y - 0.025],
		'\t"a_pillar": [Vector3(%.3f, %.3f, %.3f), Vector3(%.3f, %.3f, %.3f)],' % [pillar_foot_x, cowl_y, cowl_z, pillar_top_x, header.x, header.y],
		'\t"b_pillar_z": %.3f, "rear_z": %.3f,' % [b_pillar_z, rear_z],
	]
	if open_top:
		lines.append('\t"shelf": {},')
	else:
		lines.append('\t"shelf": {"y": %.3f, "z0": %.3f, "z1": %.3f, "half_w": %.3f},' % [rear.position.y - 0.13, rear_z, minf(rear.end.z + 0.23, _zmax() - 0.05), _half(rear.position.y - 0.16, rear.position.z) - 0.08])
	lines.append_array([
		'\t"wheel": Vector3(%.3f, %.3f, %.3f), "wheel_tilt_deg": -25.0,' % [wheel.x, wheel.y, wheel.z],
		'\t"cluster": Vector2(%.3f, %.3f), "cluster_style": "%s", "speedo_max_kmh": %.1f,' % [cluster.x, cluster.y, hand.cluster, hand.speedo],
		'\t"head_unit": Vector3(0.0, %.3f, %.3f),' % [cluster.x - 0.098, dash_face_z + 0.076],
		'\t"lever": Vector3(0.0, %.3f, %.3f), "handbrake": Vector3(0.0, %.3f, %.3f),' % [seat_h + 0.135, eye.z - 0.32, seat_h + 0.135, eye.z + 0.14],
		'\t"pedals": Vector3(%.3f, %.3f, %.3f),' % [seat_x + 0.10, carpet_y + 0.27, eye.z - 0.80],
		'\t"crank": Vector3(%.3f, %.3f, %.3f), "switch": Vector3(%.3f, %.3f, %.3f),' % [-(door_face - 0.004), seat_h + 0.17, eye.z - 0.48, -(door_face - 0.03), seat_h + 0.307, eye.z - 0.28],
		'\t"rear_mirror": Vector3(0.0, %.3f, %.3f),' % [header.x - 0.125, header.y - 0.10 * clampf((wind.end.z - wind.position.z) / 0.65, 0.4, 1.0)],
		'\t"door_mirror": Vector3(%.3f, %.3f, %.3f),' % [_half(belt_y - 0.07, cowl_z + 0.14) + 0.085, belt_y + 0.05, cowl_z + 0.14],
		'\t"console": "%s", "seats": "%s",' % [hand.console, hand.seats],
		"}",
	])
	print("\n".join(lines))
	vis.free()

## The first skin face under a point (the floor the body draws there), or -INF.
func _down(from: Vector3) -> float:
	var best := -INF
	for t in skin:
		var hit = Geometry3D.segment_intersects_triangle(from, from + Vector3(0, -2, 0), t[0], t[1], t[2])
		if hit != null:
			best = maxf(best, (hit as Vector3).y)
	return best

static func _cx(t: Array) -> float:
	return (t[0].x + t[1].x + t[2].x) / 3.0

## The skin's half width at (y, z): the nearest side face hit by a ray from
## the centreline outward, both sides averaged (the bodies are symmetric).
func _half(y: float, z: float) -> float:
	var best := 0.0
	for side in [-1.0, 1.0]:
		var from := Vector3(0.0, y, z)
		var to := Vector3(side * 2.0, y, z)
		var d := INF
		for t in skin:
			var hit = Geometry3D.segment_intersects_triangle(from, to, t[0], t[1], t[2])
			if hit != null:
				d = minf(d, absf((hit as Vector3).x))
		if d < INF:
			best = maxf(best, d) if best > 0.0 else d
	return best

func _floor() -> float:
	var y := INF
	for t in skin:
		if t[3].y < -0.7:
			for i in 3:
				if absf(t[i].x) < 0.5 and absf(t[i].z) < 0.6:
					y = minf(y, t[i].y)
	return y

func _roof(side: AABB) -> float:
	var y := -INF
	for t in skin:
		if t[3].y > 0.8:
			for i in 3:
				if t[i].z > side.position.z and t[i].z < side.end.z + 0.3 and absf(t[i].x) < 0.3:
					y = maxf(y, t[i].y)
	return y

func _zmin() -> float:
	var z := INF
	for t in skin:
		for i in 3:
			z = minf(z, t[i].z)
	return z

func _zmax() -> float:
	var z := -INF
	for t in skin:
		for i in 3:
			z = maxf(z, t[i].z)
	return z

static func _pane(tris: Array, keep: Callable) -> AABB:
	var out := AABB()
	var first := true
	for t in tris:
		if not keep.call(t):
			continue
		for i in 3:
			if first:
				out = AABB(t[i], Vector3.ZERO)
				first = false
			else:
				out = out.expand(t[i])
	return out
