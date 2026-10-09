extends Node3D
class_name CarPanels

# Opening panels (car-parts plan 2026-10-09, build list item 4): the hood,
# the doors and the trunk lid (hatch, or the pickup's tailgate) open on the
# player's car wherever it is stopped: the garage, a gas station, photo
# mode, or just parked on the street. They close by themselves when the car
# drives off. Nothing pops open in a crash.
#
# The sheet bodies are one triangle soup with a material per triangle and no
# panel names, so the panels are cut out of the body mesh at build time by
# region: the hood is the up-facing paint between the front axle and the
# windshield base, a door is the side between the wheel arches, the lid is
# the up-facing paint behind the rear glass (a hatch takes the glass with it,
# a tailgate is the rear face). Every car gets the same cut from its own
# wheel positions and glass, so it works for all fifteen sheet cars without
# a data change; per-kind overrides (door count, lid kind) sit in KINDS.
#
# Draw calls: none while the panels are closed. The car keeps drawing its
# one merged Body; this node (hidden) holds the split copy: the Shell (body
# minus panels), one mesh per panel under a hinge, and the engine bay. The
# moment a panel starts to open the Body hides and the split copy shows, so
# the cost (about +6 draw calls, plus one each for the bay and the trunk
# tub) is paid only while something is open, which only happens stopped.
# The engine bay is drawn only while the hood is open, as decided.
#
# Panels are single-sided like the body, so each gets an inner skin: the
# same triangles flipped, in cabin black, so an open door read from behind
# is a dark door and not a hole.
#
# Keys (Controls page lists them; no on-screen hints): H hood, J doors,
# K trunk. Each toggles. Ignored while moving or while a menu is up.

const KEYS := {"open_hood": KEY_H, "open_doors": KEY_J, "open_trunk": KEY_K}
const NODE_NAME := "Panels"

## Per-kind cut settings. doors: 2 or 4 (per side 1 or 2). trunk: "auto"
## (lid or hatch from the rear glass), "lid", "hatch", "tailgate", "none".
const KINDS := {
	"p0_beater": {"doors": 4}, "p1_coupe": {"doors": 2}, "p2_hothatch": {"doors": 2},
	"p3_tuner": {"doors": 4}, "p4_kei": {"doors": 2}, "p5_muscle": {"doors": 2},
	"p6_crossover": {"doors": 4}, "n1_commuter": {"doors": 4}, "n2_cityhatch": {"doors": 4},
	"n3_pickup": {"doors": 2, "trunk": "tailgate"}, "c1_patrol": {"doors": 4},
	"c2_patrolsuv": {"doors": 4}, "c3_interceptor": {"doors": 4},
}
const DEFAULT_KIND := {"doors": 4, "trunk": "auto"}

## Open angles (degrees) and the speed of the swing.
const HOOD_ANGLE := 48.0
const DOOR_ANGLE := 58.0
const LID_ANGLE := 55.0
const HATCH_ANGLE := 68.0
const TAILGATE_ANGLE := 88.0
const SWING_RATE := 2.2          # fraction of the swing per second
## Stopped below this (m/s); driving off above DRIVE_OFF closes everything.
const STOPPED_SPEED := 0.6
const DRIVE_OFF_SPEED := 1.5
## A lid shorter than this behind the rear glass makes the car a hatchback.
const HATCH_MAX_LID := 0.55

const INNER := Color("#15181E")      # cabin black, the inner skins
const COL_TRAY := Color("#101216")
const COL_BLOCK := Color("#2A2D33")
const COL_COVER := Color("#3A3E46")
const COL_PLENUM := Color("#4A4E57")
const COL_BATTERY := Color("#15171C")
const COL_TERMINAL := Color("#C9CED6")
const COL_RADIATOR := Color("#1C1F26")
const COL_TOWER := Color("#22252C")
const COL_HOSE := Color("#0E1014")

var vehicle: RigidBody3D
var kind := ""
var body: MeshInstance3D
var shell: MeshInstance3D
## panel name -> {hinge: Node3D, axis: Vector3 (unit, local), angle: float (rad), open: float 0..1, target: float}
var panels := {}
var engine_bay: MeshInstance3D
var trunk_tub: MeshInstance3D
var trunk_kind := "none"
var _game_state: Node
var _state_looked := false
var _showing_split := false
var _inner_mat: Material
static var _bay_mat: StandardMaterial3D

# ---------- setup ----------

static func ensure_actions() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.keycode = KEYS[action]
		InputMap.action_add_event(action, ev)

## Cuts the panels out of `root`'s "Body" mesh and hangs them under `root`.
## `root` is a chassis visual with metas "kind" and "under_params" (the
## Undercarriage.params its builder used). Call before CarFx.attach, which
## moves every mesh present to the car's render layer. Returns null when the
## body cannot be cut (no Body mesh, no params).
static func attach(root: Node3D, v: RigidBody3D) -> CarPanels:
	var body_mi := root.get_node_or_null("Body") as MeshInstance3D
	if body_mi == null or not (body_mi.mesh is ArrayMesh) or not root.has_meta("under_params"):
		return null
	var cp := CarPanels.new()
	cp.name = NODE_NAME
	cp.vehicle = v
	cp.kind = String(root.get_meta("kind", ""))
	cp.body = body_mi
	cp.position = body_mi.position
	cp.visible = false
	cp.process_mode = Node.PROCESS_MODE_ALWAYS
	cp._build(body_mi, root.get_meta("under_params"))
	root.add_child(cp)
	return cp

func _ready() -> void:
	ensure_actions()

## The region cut, from the body mesh and the wheel numbers. Mesh space: the
## ground at rest is y = 0, the nose is -z.
func _build(src: MeshInstance3D, p: Dictionary) -> void:
	var mesh := src.mesh as ArrayMesh
	var cfg: Dictionary = KINDS.get(kind, DEFAULT_KIND)
	var doors_per_side: int = 2 if int(cfg.get("doors", 4)) >= 4 else 1
	trunk_kind = String(cfg.get("trunk", "auto"))
	var r: float = p.wheel_r
	var hw: float = p.half_w
	var axle: float = p.axle_z
	var box := mesh.get_aabb()
	var top := box.end.y

	# Surfaces by name; anything not body/glass/glow is copied to the shell untouched.
	var surfs := {}
	var extra := []
	for i in mesh.get_surface_count():
		var sname := mesh.surface_get_name(i)
		var entry := {"arrays": mesh.surface_get_arrays(i), "mat": mesh.surface_get_material(i),
			"override": src.get_surface_override_material(i), "name": sname}
		if sname in ["body", "glass", "glow"]:
			surfs[sname] = entry
		else:
			extra.append(entry)

	# Glass landmarks: the windshield base and the rear glass top and bottom.
	var z_cowl := -axle + r + 0.6     # fallback when a car has no front glass
	var z_rg_top := axle - r
	var z_rg_bot := axle - r + 0.3
	var has_rear_glass := false
	var z_cab_end := -INF             # where the side glass ends (no rear glass: the lid starts here)
	if surfs.has("glass"):
		var gv: PackedVector3Array = surfs.glass.arrays[Mesh.ARRAY_VERTEX]
		var gn: PackedVector3Array = surfs.glass.arrays[Mesh.ARRAY_NORMAL]
		var front_min := INF
		var rear_min := INF
		var rear_max := -INF
		for t in gv.size() / 3:
			var c := (gv[t * 3] + gv[t * 3 + 1] + gv[t * 3 + 2]) / 3.0
			var n := gn[t * 3]
			if c.z < 0.0 and n.z < -0.3:
				for k in 3:
					front_min = minf(front_min, gv[t * 3 + k].z)
			elif c.z > 0.0 and n.z > 0.3:
				for k in 3:
					rear_min = minf(rear_min, gv[t * 3 + k].z)
					rear_max = maxf(rear_max, gv[t * 3 + k].z)
			elif absf(n.x) > 0.5:
				for k in 3:
					z_cab_end = maxf(z_cab_end, gv[t * 3 + k].z)
		if front_min < INF:
			z_cowl = front_min
		if rear_max > -INF:
			has_rear_glass = true
			z_rg_top = rear_min
			z_rg_bot = rear_max
	if trunk_kind == "auto":
		if not has_rear_glass:
			# No rear glass (the kei): a lid over the deck behind the cabin.
			trunk_kind = "lid" if z_cab_end > -INF else "none"
			z_rg_bot = z_cab_end
		elif box.end.z - z_rg_bot < HATCH_MAX_LID:
			trunk_kind = "hatch"
		else:
			trunk_kind = "lid"

	# Door z range: between the arches, split in two for four-door cars.
	var door_z0 := -axle + r + 0.12
	var door_z1 := axle - r - 0.12
	var door_zm := (door_z0 + door_z1) * 0.5
	var y_belt := 1.6 * r   # above the arch tops, where hoods and lids live

	# Sort every body / glass / glow triangle into a panel or the shell.
	var parts := {"shell": {}}
	for sname in surfs:
		var e: Dictionary = surfs[sname]
		var vs: PackedVector3Array = e.arrays[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = e.arrays[Mesh.ARRAY_NORMAL]
		var cs: PackedColorArray = e.arrays[Mesh.ARRAY_COLOR]
		for t in vs.size() / 3:
			var a := vs[t * 3]
			var b := vs[t * 3 + 1]
			var c := vs[t * 3 + 2]
			var n := ns[t * 3]
			var part := "shell"
			if sname != "glow":
				part = _classify(sname, [a, b, c], n, hw, r, axle, top, box, z_cowl, z_rg_top, z_rg_bot,
					door_z0, door_z1, door_zm, doors_per_side, y_belt)
			_push_tri(parts, part, sname, [a, b, c], [ns[t * 3], ns[t * 3 + 1], ns[t * 3 + 2]], [cs[t * 3], cs[t * 3 + 1], cs[t * 3 + 2]])

	# The shell: the leftovers, plus the untouched surfaces (tail flares).
	shell = MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = _mesh_from(parts.shell, surfs, false)
	for e in extra:
		var arrays: Array = e.arrays
		(shell.mesh as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx: int = (shell.mesh as ArrayMesh).get_surface_count() - 1
		(shell.mesh as ArrayMesh).surface_set_name(idx, e.name)
		(shell.mesh as ArrayMesh).surface_set_material(idx, e.mat)
	_copy_look(src, shell, surfs, extra)
	shell.extra_cull_margin = src.extra_cull_margin
	add_child(shell)

	# The panels, each under a hinge at its own edge.
	var hood_box := _bounds(parts.get("hood", {}))
	if hood_box.size.z > 0.2:
		var hinge := Vector3(0.0, _edge_top(parts.hood, hood_box.end.z, 0.12), hood_box.end.z)
		_add_panel("hood", parts.hood, surfs, src, hinge, Vector3.RIGHT, deg_to_rad(HOOD_ANGLE))
	for side: float in [-1.0, 1.0]:
		for d in doors_per_side:
			var pname := "door_%s%s" % ["f" if d == 0 else "r", "l" if side < 0.0 else "r"]
			var pb := _bounds(parts.get(pname, {}))
			if pb.size.z < 0.3:
				continue
			var hinge := Vector3(side * _edge_side(parts[pname], pb.position.z, 0.15), (pb.position.y + pb.end.y) * 0.5, pb.position.z)
			_add_panel(pname, parts[pname], surfs, src, hinge, Vector3.UP, side * deg_to_rad(DOOR_ANGLE))
	var tb := _bounds(parts.get("trunk", {}))
	if tb.size.z > 0.15 or tb.size.y > 0.15:
		match trunk_kind:
			"lid":
				var hinge := Vector3(0.0, _edge_top(parts.trunk, tb.position.z, 0.12), tb.position.z)
				_add_panel("trunk", parts.trunk, surfs, src, hinge, Vector3.RIGHT, -deg_to_rad(LID_ANGLE))
			"hatch":
				var hinge := Vector3(0.0, _edge_top(parts.trunk, tb.position.z, 0.12), tb.position.z)
				_add_panel("trunk", parts.trunk, surfs, src, hinge, Vector3.RIGHT, -deg_to_rad(HATCH_ANGLE))
			"tailgate":
				var hinge := Vector3(0.0, tb.position.y, _edge_bottom_z(parts.trunk, tb.position.y, 0.1))
				_add_panel("trunk", parts.trunk, surfs, src, hinge, Vector3.RIGHT, deg_to_rad(TAILGATE_ANGLE))

	# Under the hood and the lid.
	if panels.has("hood"):
		engine_bay = MeshInstance3D.new()
		engine_bay.name = "EngineBay"
		engine_bay.mesh = build_engine_bay(hood_box, hw, r)
		engine_bay.material_override = _get_bay_material()
		engine_bay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		engine_bay.visible = false
		add_child(engine_bay)
	if panels.has("trunk") and trunk_kind != "tailgate":
		trunk_tub = MeshInstance3D.new()
		trunk_tub.name = "TrunkTub"
		trunk_tub.mesh = build_trunk_tub(tb, hw, r, box)
		trunk_tub.material_override = _get_bay_material()
		trunk_tub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		trunk_tub.visible = false
		add_child(trunk_tub)

## Which panel a triangle belongs to ("shell" for none). A triangle joins a
## panel only when all three corners are inside the panel's region, so the
## cut follows the loft's rings and the edges come out straight instead of
## sawtoothed; the facing test uses the triangle's normal.
func _classify(sname: String, v: Array, n: Vector3, hw: float, r: float, axle: float, top: float,
		box: AABB, z_cowl: float, z_rg_top: float, z_rg_bot: float,
		door_z0: float, door_z1: float, door_zm: float, doors_per_side: int, y_belt: float) -> String:
	var z0 := INF
	var z1 := -INF
	var y0 := INF
	var y1 := -INF
	var ax0 := INF
	var ax1 := 0.0
	for p in v:
		z0 = minf(z0, p.z)
		z1 = maxf(z1, p.z)
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
		ax0 = minf(ax0, absf(p.x))
		ax1 = maxf(ax1, absf(p.x))
	var cz := (z0 + z1) * 0.5
	var cx: float = (v[0].x + v[1].x + v[2].x) / 3.0
	# Doors: the sides between the arches, sills and roof left alone.
	var z_end := door_z1
	if sname == "glass" and doors_per_side == 1:
		z_end = minf(door_z1, door_zm + 0.25)   # the quarter window stays on a two-door
	if absf(n.x) > (0.5 if sname == "glass" else 0.6) and ax0 > 0.55 * hw 			and z0 > door_z0 and z1 < z_end and y0 > r and y1 < top - 0.02:
		var front := doors_per_side == 1 or cz < door_zm
		return "door_%s%s" % ["f" if front else "r", "l" if cx < 0.0 else "r"]
	if sname == "body":
		# Hood: the up-facing paint from the front axle to the windshield.
		if n.y > 0.55 and ax1 < 0.72 * hw and y0 > y_belt 				and z0 > -axle - 0.3 and z1 < z_cowl - 0.02:
			return "hood"
		match trunk_kind:
			"lid":
				if n.y > 0.5 and ax1 < 0.72 * hw and y0 > y_belt 						and z0 > z_rg_bot + 0.02 and z1 < box.end.z - 0.22:
					return "trunk"
			"hatch":
				if (n.y > 0.4 or n.z > 0.4) and ax1 < 0.8 * hw and y0 > y_belt 						and z0 > z_rg_top + 0.03:
					return "trunk"
			"tailgate":
				if n.z > 0.5 and cz > box.end.z - 0.3 and y0 > 1.3 * r and y1 < top - 0.05:
					return "trunk"
	elif sname == "glass" and trunk_kind == "hatch" and cz > 0.0 and n.z > 0.3:
		return "trunk"
	return "shell"

static func _push_tri(parts: Dictionary, part: String, sname: String, v: Array, n: Array, c: Array) -> void:
	if not parts.has(part):
		parts[part] = {}
	var surf: Dictionary = parts[part]
	if not surf.has(sname):
		surf[sname] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
	var g: Array = surf[sname]
	for k in 3:
		g[0].append(v[k])
		g[1].append(n[k])
		g[2].append(c[k])

## One ArrayMesh from a part's surfaces, in the body's surface order and
## materials. With `inner`, each body triangle also gets a flipped twin in
## cabin black (alpha 1: not paint) so the panel reads from both sides.
static func _mesh_from(part: Dictionary, surfs: Dictionary, inner: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for sname in ["body", "glass", "glow"]:
		if not part.has(sname):
			continue
		var g: Array = part[sname]
		var vs: PackedVector3Array = g[0]
		var ns: PackedVector3Array = g[1]
		var cs: PackedColorArray = g[2]
		if inner and sname == "body":
			vs = vs.duplicate()
			ns = ns.duplicate()
			cs = cs.duplicate()
			var count: int = g[0].size()
			var dark := INNER.srgb_to_linear()
			dark.a = 1.0
			for t in count / 3:
				var a: Vector3 = g[0][t * 3]
				var b: Vector3 = g[0][t * 3 + 1]
				var c: Vector3 = g[0][t * 3 + 2]
				var n: Vector3 = -g[1][t * 3]
				for p in [a, c, b]:
					vs.append(p)
					ns.append(n)
					cs.append(dark)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vs
		arrays[Mesh.ARRAY_NORMAL] = ns
		arrays[Mesh.ARRAY_COLOR] = cs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_name(idx, sname)
		mesh.surface_set_material(idx, surfs[sname].mat)
	return mesh

## The body's per-node look: surface overrides (the P1's paint) by surface
## name, and the instance paint uniform (the sheet cars).
static func _copy_look(src: MeshInstance3D, dst: MeshInstance3D, surfs: Dictionary, extra: Array) -> void:
	var dm := dst.mesh as ArrayMesh
	for i in dm.get_surface_count():
		var sname := dm.surface_get_name(i)
		var ov: Material = null
		if surfs.has(sname):
			ov = surfs[sname].override
		else:
			for e in extra:
				if e.name == sname:
					ov = e.override
		if ov != null:
			dst.set_surface_override_material(i, ov)
	var paint = src.get_instance_shader_parameter("paint")
	if paint is Color:
		dst.set_instance_shader_parameter("paint", paint)
	dst.cast_shadow = src.cast_shadow
	dst.layers = src.layers

func _add_panel(pname: String, part: Dictionary, surfs: Dictionary, src: MeshInstance3D, hinge: Vector3, axis: Vector3, angle: float) -> void:
	var pivot := Node3D.new()
	pivot.name = "Hinge_" + pname
	pivot.position = hinge
	var mi := MeshInstance3D.new()
	mi.name = pname
	mi.position = -hinge
	mi.mesh = _mesh_from(part, surfs, true)
	_copy_look(src, mi, surfs, [])
	pivot.add_child(mi)
	add_child(pivot)
	panels[pname] = {"hinge": pivot, "axis": axis, "angle": angle, "open": 0.0, "target": 0.0}

static func _bounds(part: Dictionary) -> AABB:
	var box := AABB()
	var first := true
	for sname in part:
		for v in part[sname][0]:
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	return box

## Highest y among a part's vertices within `band` of z.
static func _edge_top(part: Dictionary, z: float, band: float) -> float:
	var y := -INF
	for sname in part:
		for v in part[sname][0]:
			if absf(v.z - z) <= band:
				y = maxf(y, v.y)
	return y if y > -INF else 0.0

## Widest |x| among a part's vertices within `band` of z (a door's front edge).
static func _edge_side(part: Dictionary, z: float, band: float) -> float:
	var x := 0.0
	for sname in part:
		for v in part[sname][0]:
			if absf(v.z - z) <= band:
				x = maxf(x, absf(v.x))
	return x

## Mean z among a part's vertices within `band` of y (a tailgate's bottom edge).
static func _edge_bottom_z(part: Dictionary, y: float, band: float) -> float:
	var sum := 0.0
	var n := 0
	for sname in part:
		for v in part[sname][0]:
			if absf(v.y - y) <= band:
				sum += v.z
				n += 1
	return sum / float(n) if n > 0 else 0.0

# ---------- the engine bay and the trunk tub ----------

static func _get_bay_material() -> StandardMaterial3D:
	if _bay_mat == null:
		_bay_mat = StandardMaterial3D.new()
		_bay_mat.vertex_color_use_as_albedo = true
		_bay_mat.roughness = 0.85
		_bay_mat.metallic = 0.15
	return _bay_mat

## Block, cam cover, intake plenum, radiator, battery, strut towers and a
## tray, fitted inside the hood's footprint (so nothing pokes out of the
## hole or through the hood). Flat boxes, about 120 triangles.
static func build_engine_bay(hood: AABB, hw: float, r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x1 := minf(0.62 * hw, maxf(hood.end.x, -hood.position.x) + 0.04)
	var x0 := -x1
	var z0 := hood.position.z + 0.04
	var z1 := hood.end.z - 0.04
	var hood_y := hood.position.y            # the hood's lowest point: nothing pokes through
	var tray_y := maxf(hood_y - 0.52, 0.22)
	var top_y := hood_y - 0.06
	var zc := (z0 + z1) * 0.5
	var len := z1 - z0
	# Tray and inner wings.
	_box(st, Vector3(x0, tray_y, z0), Vector3(x1, tray_y + 0.04, z1), COL_TRAY)
	_box(st, Vector3(x0, tray_y, z0), Vector3(x0 + 0.03, top_y, z1), COL_TRAY)
	_box(st, Vector3(x1 - 0.03, tray_y, z0), Vector3(x1, top_y, z1), COL_TRAY)
	# Radiator at the front, bulkhead at the back.
	_box(st, Vector3(x0 + 0.08, tray_y + 0.04, z0), Vector3(x1 - 0.08, top_y, z0 + 0.05), COL_RADIATOR)
	_box(st, Vector3(x0, tray_y + 0.04, z1 - 0.03), Vector3(x1, top_y, z1), COL_TRAY)
	# Engine block, cam cover, intake plenum: the middle of what is left.
	var bw := minf(0.62, (x1 - x0) * 0.5)
	var bl := clampf(len * 0.5, 0.2, 0.62)
	var bz0 := zc - bl * 0.5
	var bz1 := zc + bl * 0.5
	_box(st, Vector3(-bw / 2.0, tray_y + 0.04, bz0), Vector3(bw / 2.0, top_y - 0.12, bz1), COL_BLOCK)
	_box(st, Vector3(-bw / 2.0 + 0.04, top_y - 0.12, bz0 + 0.03), Vector3(bw / 2.0 - 0.04, top_y - 0.03, bz1 - 0.03), COL_COVER)
	_box(st, Vector3(maxf(-bw / 2.0 - 0.12, x0 + 0.04), top_y - 0.18, bz0 + 0.05), Vector3(-bw / 2.0, top_y - 0.09, bz1 - 0.08), COL_PLENUM)
	# Air box with its intake hose on the right, battery with two terminals on the left.
	var ab0 := z0 + 0.08
	var ab1 := minf(z0 + 0.3, bz0 - 0.02)
	if ab1 - ab0 > 0.08:
		_box(st, Vector3(x1 - 0.3, tray_y + 0.06, ab0), Vector3(x1 - 0.06, top_y - 0.1, ab1), COL_BATTERY)
		_box(st, Vector3(x1 - 0.26, top_y - 0.18, ab1), Vector3(x1 - 0.1, top_y - 0.1, bz0), COL_HOSE)
	var bt0 := maxf(z1 - 0.34, bz1 + 0.02)
	var bt1 := z1 - 0.08
	if bt1 - bt0 > 0.08:
		_box(st, Vector3(x0 + 0.06, tray_y + 0.06, bt0), Vector3(x0 + 0.28, tray_y + 0.26, bt1), COL_BATTERY)
		_box(st, Vector3(x0 + 0.09, tray_y + 0.26, bt0 + 0.03), Vector3(x0 + 0.13, tray_y + 0.3, bt0 + 0.07), COL_TERMINAL)
		_box(st, Vector3(x0 + 0.21, tray_y + 0.26, bt0 + 0.03), Vector3(x0 + 0.25, tray_y + 0.3, bt0 + 0.07), COL_TERMINAL)
	# Strut towers at the back corners.
	for side: float in [-1.0, 1.0]:
		var cx: float = side * (x1 - 0.14)
		_box(st, Vector3(cx - 0.08, tray_y + 0.04, z1 - 0.3), Vector3(cx + 0.08, top_y - 0.04, z1 - 0.1), COL_TOWER)
	return st.commit()

## A dark tub under the trunk lid or hatch, with a spare-wheel bump.
static func build_trunk_tub(lid: AABB, hw: float, r: float, body: AABB) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -0.66 * hw
	var x1 := 0.66 * hw
	var z0 := lid.position.z + 0.04
	var z1 := minf(lid.end.z + 0.1, body.end.z - 0.15)
	var floor_y := maxf(lid.position.y - 0.45, 1.2 * r)
	_box(st, Vector3(x0, floor_y, z0), Vector3(x1, floor_y + 0.03, z1), COL_TRAY)
	_box(st, Vector3(x0, floor_y, z0), Vector3(x0 + 0.03, lid.position.y - 0.02, z1), COL_TRAY)
	_box(st, Vector3(x1 - 0.03, floor_y, z0), Vector3(x1, lid.position.y - 0.02, z1), COL_TRAY)
	_box(st, Vector3(x0, floor_y, z0), Vector3(x1, lid.position.y - 0.02, z0 + 0.03), COL_TRAY)
	_box(st, Vector3(x0, floor_y, z1 - 0.03), Vector3(x1, lid.position.y - 0.02, z1), COL_TRAY)
	var cz := (z0 + z1) * 0.5
	_box(st, Vector3(-0.3, floor_y + 0.03, cz - 0.3), Vector3(0.3, floor_y + 0.1, cz + 0.3), COL_BLOCK)
	return st.commit()

static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, col: Color) -> void:
	var c := col.srgb_to_linear()
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	# Each face: four corners, counter-clockwise seen from outside, then
	# written clockwise for Godot's front faces.
	var faces := [
		[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)],
		[0, 4, 7, 3, Vector3(-1, 0, 0)], [1, 2, 6, 5, Vector3(1, 0, 0)],
		[3, 7, 6, 2, Vector3(0, 1, 0)], [0, 1, 5, 4, Vector3(0, -1, 0)],
	]
	for f in faces:
		st.set_normal(f[4])
		st.set_color(c)
		for idx in [f[0], f[2], f[1], f[0], f[3], f[2]]:
			st.add_vertex(p[idx])

# ---------- runtime ----------

## Speed of the car along the road (m/s).
func car_speed() -> float:
	return vehicle.linear_velocity.length() if vehicle != null else 0.0

func is_stopped() -> bool:
	return car_speed() < STOPPED_SPEED

func is_open(pname: String) -> bool:
	return panels.has(pname) and float(panels[pname].target) > 0.5

func any_open() -> bool:
	for pname in panels:
		if float(panels[pname].target) > 0.5 or float(panels[pname].open) > 0.001:
			return true
	return false

## Open or close one panel ("hood", "trunk", or a door name). Doors as a
## set: set_doors(). Only while stopped, unless `force`.
func set_open(pname: String, open: bool, force := false) -> void:
	if not panels.has(pname):
		return
	if open and not force and not is_stopped():
		return
	panels[pname].target = 1.0 if open else 0.0

func set_doors(open: bool, force := false) -> void:
	for pname in panels:
		if String(pname).begins_with("door"):
			set_open(pname, open, force)

func doors_open() -> bool:
	for pname in panels:
		if String(pname).begins_with("door") and float(panels[pname].target) > 0.5:
			return true
	return false

func toggle_hood() -> void:
	set_open("hood", not is_open("hood"))

func toggle_doors() -> void:
	set_doors(not doors_open())

func toggle_trunk() -> void:
	set_open("trunk", not is_open("trunk"))

func close_all() -> void:
	for pname in panels:
		panels[pname].target = 0.0

## The game state, found once (for the photo-mode check).
func _photo_mode() -> bool:
	if not _state_looked:
		_state_looked = true
		var found := get_tree().root.find_children("*", "GameState", true, false)
		if found.size() > 0:
			_game_state = found[0]
	if _game_state == null:
		return false
	return int(_game_state.get("state")) == GameState.State.PHOTO

## Keys count while playing, or in photo mode (paused); never under a menu.
func _takes_input() -> bool:
	if get_tree().paused:
		return _photo_mode()
	return true

func _process(delta: float) -> void:
	if _takes_input():
		if Input.is_action_just_pressed("open_hood"):
			toggle_hood()
		if Input.is_action_just_pressed("open_doors"):
			toggle_doors()
		if Input.is_action_just_pressed("open_trunk"):
			toggle_trunk()
	if not get_tree().paused and car_speed() > DRIVE_OFF_SPEED:
		close_all()
	step(delta)

## One frame of the swing; split out so tests can drive it.
func step(delta: float) -> void:
	var moving := false
	for pname in panels:
		var pd: Dictionary = panels[pname]
		var open: float = pd.open
		var target: float = pd.target
		if open != target:
			open = move_toward(open, target, SWING_RATE * delta)
			pd.open = open
			var hinge: Node3D = pd.hinge
			# Ease out: the panel slows as it reaches its stop.
			var k := 1.0 - (1.0 - open) * (1.0 - open)
			hinge.transform.basis = Basis(pd.axis, float(pd.angle) * k)
		if open > 0.0:
			moving = true
	var want_split := moving or any_open()
	if want_split != _showing_split:
		_showing_split = want_split
		visible = want_split
		if body != null:
			body.visible = not want_split
	if engine_bay != null:
		engine_bay.visible = want_split and panels.has("hood") and float(panels.hood.open) > 0.0
	if trunk_tub != null:
		trunk_tub.visible = want_split and panels.has("trunk") and float(panels.trunk.open) > 0.0

## Triangles in the split copy (shell, panels with their inner skins, bay, tub).
func triangle_count() -> int:
	var n := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh as ArrayMesh
		if m == null:
			continue
		for i in m.get_surface_count():
			n += m.surface_get_array_len(i) / 3
	return n

## Draw calls while something is open: the shell's surfaces, each panel's
## surfaces, the bay when the hood is open and the tub when the trunk is.
func open_draw_calls() -> int:
	var n: int = (shell.mesh as ArrayMesh).get_surface_count()
	for pname in panels:
		var mi := (panels[pname].hinge as Node3D).get_child(0) as MeshInstance3D
		n += (mi.mesh as ArrayMesh).get_surface_count()
	if engine_bay != null and engine_bay.visible:
		n += 1
	if trunk_tub != null and trunk_tub.visible:
		n += 1
	return n
