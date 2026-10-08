extends RefCounted
class_name CarBuilder

# Simplified box-based car builder, ported from the Three.js prototype's buildCar().
# Trades the JS version's fine detailing (chrome trim, mirrors, spoiler, rounded
# panels) for a smaller, faster-to-build node tree: main body, raked hood, glass
# cabin + roof, 4 wheels+rims, head/tail lights. Enough to read as "car" and to
# recolor per-instance for traffic variety.

const KIND_CONFIGS := {
	"coupe": {"wheel_r":0.34, "axle_z":1.25, "wheel_x":0.88, "chassis_h":0.46, "hood_h":0.30,
		"main_w":1.6, "hood_w":1.5, "hood_z0":-1.7, "hood_z1":-0.25, "main_z0":-0.25, "main_z1":1.7,
		"cabin_w":1.24, "roof_w":1.12, "cabin_z0":-0.35, "cabin_z1":0.95, "glass_h":0.30, "hood_rake":0.16,
		"spoiler":true},
	"sedan": {"wheel_r":0.34, "axle_z":1.15, "wheel_x":0.86, "chassis_h":0.44, "hood_h":0.32,
		"main_w":1.58, "hood_w":1.46, "hood_z0":-1.55, "hood_z1":-0.15, "main_z0":-0.15, "main_z1":1.85,
		"cabin_w":1.26, "roof_w":1.16, "cabin_z0":-0.05, "cabin_z1":1.15, "glass_h":0.34, "hood_rake":0.08},
	"van": {"wheel_r":0.37, "axle_z":1.2, "wheel_x":0.92, "chassis_h":0.62, "hood_h":0.46,
		"main_w":1.7, "hood_w":1.58, "hood_z0":-1.3, "hood_z1":-0.55, "main_z0":-0.55, "main_z1":1.75,
		"cabin_w":1.4, "roof_w":1.32, "cabin_z0":-0.5, "cabin_z1":1.6, "glass_h":0.48, "hood_rake":0.05},
}

## Emits one flat-shaded quad (a,b,c,d given in order, CCW as seen from the
## outward-normal side) as two triangles into an open SurfaceTool. Normal is
## computed per-quad (not smoothed across neighbors) to keep the deliberate
## faceted/low-poly look everything else in this file already uses.
##
## Godot treats CLOCKWISE triangles as front faces, so the triangles are
## emitted in reverse (a,c,b / a,d,c) while the normal stays outward. Emitting
## them CCW as given culled every panel facing the camera and showed the far
## panels' insides, lit from behind -- the "bare frame, panels missing" car in
## ISSUES G1.
##
## The normal comes from the diagonals, not from (b-a)x(c-a): lofts taper to a
## zero-height section (the coupe glass) or repeat a z (the coupe body), so a
## quad can have two coincident corners and collapse into a triangle, and the
## edge-based cross product is then zero (ISSUES G2). The diagonal cross is the
## same direction for any planar quad and only vanishes when the whole quad
## does. Zero-area triangles are skipped instead of emitted.
const _QUAD_AREA_EPS := 1e-8

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var diag := (c - a).cross(d - b)
	if diag.length_squared() < _QUAD_AREA_EPS:
		return
	var normal := diag.normalized()
	for tri in [[a, c, b], [a, d, c]]:
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).length_squared() < _QUAD_AREA_EPS:
			continue
		for v in tri:
			st.set_normal(normal); st.add_vertex(v)

## Builds a tapered "loft" mesh from a series of cross-sections along Z, each
## {z, w, y0, y1} (half-width w/2 either side of X=0, bottom y0, top y1, all
## in the same local space everything else in this file uses). Connecting
## sections with sloped side/top/bottom quads -- instead of stacking
## axis-aligned boxes -- is what actually produces a wedge silhouette (raked
## hood, tapering greenhouse, tapering tail).
##
## 2026-09-13 REDESIGN (Roy: "replace the sport coupe its hideous"): read back
## through car_builder.gd and found the actual root cause -- the whole body
## was BoxMesh primitives stacked together (main body box + hood box + glass
## box), which can only ever produce a slab silhouette no matter how the trim
## details on top are tuned. Real low-poly coupes (our own Supra/RX-7/Silvia
## reference research) get their read from a wedge shape: tapering nose,
## raked windshield, tapering tail -- angled surfaces, not stacked rectangles.
## This loft builder is the fix: an explicit SurfaceTool mesh with real sloped
## faces between named cross-sections, replacing the coupe's main+hood+glass
## boxes (see build_car/build_chassis_visual's coupe branch below). Verified
## headless (geometry only -- see ship notes for the actual vertex/triangle
## count sanity check; RENDERED LOOK still needs Roy's in-game judgment, same
## "headless can't judge looks" caveat as every art pass before this one).
static func _build_loft(sections: Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sections.size() - 1):
		var s0: Dictionary = sections[i]
		var s1: Dictionary = sections[i + 1]
		var hw0: float = s0.w / 2.0
		var hw1: float = s1.w / 2.0
		# left (-X, outward normal -X)
		_quad(st, Vector3(-hw0, s0.y0, s0.z), Vector3(-hw1, s1.y0, s1.z), Vector3(-hw1, s1.y1, s1.z), Vector3(-hw0, s0.y1, s0.z))
		# right (+X, outward normal +X)
		_quad(st, Vector3(hw0, s0.y0, s0.z), Vector3(hw0, s0.y1, s0.z), Vector3(hw1, s1.y1, s1.z), Vector3(hw1, s1.y0, s1.z))
		# top (+Y)
		_quad(st, Vector3(-hw0, s0.y1, s0.z), Vector3(-hw1, s1.y1, s1.z), Vector3(hw1, s1.y1, s1.z), Vector3(hw0, s0.y1, s0.z))
		# bottom (-Y)
		_quad(st, Vector3(-hw0, s0.y0, s0.z), Vector3(hw0, s0.y0, s0.z), Vector3(hw1, s1.y0, s1.z), Vector3(-hw1, s1.y0, s1.z))
	var sf: Dictionary = sections[0]
	var hwf: float = sf.w / 2.0
	_quad(st, Vector3(-hwf, sf.y0, sf.z), Vector3(-hwf, sf.y1, sf.z), Vector3(hwf, sf.y1, sf.z), Vector3(hwf, sf.y0, sf.z))
	var sr: Dictionary = sections[sections.size() - 1]
	var hwr: float = sr.w / 2.0
	_quad(st, Vector3(-hwr, sr.y0, sr.z), Vector3(hwr, sr.y0, sr.z), Vector3(hwr, sr.y1, sr.z), Vector3(-hwr, sr.y1, sr.z))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

## Coupe-only: replaces the old main+hood boxes with one tapered wedge body
## (narrow/low nose -> full-width/height cowl+doors -> tapering decklid), and
## the old flat glass box with a raked windshield/roof/backlight wedge sitting
## on top of the body's beltline. See _build_loft's header for why.
const COUPE_NOSE_W_RATIO := 0.72
const COUPE_NOSE_H_RATIO := 0.45
const COUPE_TAIL_W_RATIO := 0.8
const COUPE_TAIL_H_RATIO := 0.55

static func _build_coupe_body(cfg: Dictionary, chassis_y0: float) -> Array:
	var body_sections := [
		{"z": cfg.hood_z0, "w": float(cfg.hood_w) * COUPE_NOSE_W_RATIO, "y0": chassis_y0, "y1": chassis_y0 + cfg.hood_h * COUPE_NOSE_H_RATIO},
		{"z": cfg.hood_z0 + 0.18, "w": float(cfg.hood_w), "y0": chassis_y0, "y1": chassis_y0 + cfg.hood_h * 0.95},
		{"z": cfg.hood_z1, "w": float(cfg.main_w) * 0.97, "y0": chassis_y0, "y1": chassis_y0 + cfg.chassis_h},
		{"z": cfg.main_z0, "w": float(cfg.main_w), "y0": chassis_y0, "y1": chassis_y0 + cfg.chassis_h},
		{"z": float(cfg.main_z1) - 0.35, "w": float(cfg.main_w), "y0": chassis_y0, "y1": chassis_y0 + cfg.chassis_h},
		{"z": float(cfg.main_z1) - 0.05, "w": float(cfg.main_w) * 0.92, "y0": chassis_y0, "y1": chassis_y0 + cfg.chassis_h * 0.85},
		{"z": cfg.main_z1, "w": float(cfg.main_w) * COUPE_TAIL_W_RATIO, "y0": chassis_y0, "y1": chassis_y0 + cfg.chassis_h * COUPE_TAIL_H_RATIO},
	]
	return body_sections

## Bumpers sized to match _build_coupe_body's tapered nose/tail sections
## (COUPE_NOSE_W_RATIO/H_RATIO, COUPE_TAIL_W_RATIO/H_RATIO) instead of the
## generic _add_body_details bumpers, which assume a full-width/height box
## end and would poke out past the tapered wedge body here.
static func _add_coupe_bumpers(root: Node3D, cfg: Dictionary, chassis_y0: float) -> void:
	var trim_mat := _mat(Color(0.05, 0.05, 0.06), 0.0, 0.15, 0.7)
	var front_h: float = cfg.hood_h * COUPE_NOSE_H_RATIO
	var front_bumper := _box(Vector3(float(cfg.hood_w) * COUPE_NOSE_W_RATIO + 0.05, front_h * 0.9, 0.16), trim_mat)
	front_bumper.position = Vector3(0.0, chassis_y0 + front_h * 0.45, cfg.hood_z0 - 0.02)
	root.add_child(front_bumper)
	var rear_h: float = cfg.chassis_h * COUPE_TAIL_H_RATIO
	var rear_bumper := _box(Vector3(float(cfg.main_w) * COUPE_TAIL_W_RATIO + 0.05, rear_h * 0.9, 0.16), trim_mat)
	rear_bumper.position = Vector3(0.0, chassis_y0 + rear_h * 0.45, cfg.main_z1 + 0.02)
	root.add_child(rear_bumper)

static func _add_coupe_glass(root: Node3D, cfg: Dictionary, glass_mat: Material, roof_mat: Material, chassis_y0: float) -> void:
	var base_y: float = chassis_y0 + cfg.chassis_h
	var cabin_len: float = cfg.cabin_z1 - cfg.cabin_z0
	var windshield_len: float = cabin_len * 0.38
	var backlight_len: float = cabin_len * 0.3
	var z_g1: float = cfg.cabin_z0
	var z_g2: float = float(cfg.cabin_z0) + windshield_len
	var z_g3: float = float(cfg.cabin_z1) - backlight_len
	var z_g4: float = cfg.cabin_z1
	var roof_y: float = base_y + cfg.glass_h

	var glass_sections := [
		{"z": z_g1, "w": float(cfg.cabin_w), "y0": base_y, "y1": base_y},
		{"z": z_g2, "w": float(cfg.roof_w), "y0": base_y, "y1": roof_y},
		{"z": z_g3, "w": float(cfg.roof_w), "y0": base_y, "y1": roof_y},
		{"z": z_g4, "w": float(cfg.cabin_w), "y0": base_y, "y1": base_y},
	]
	root.add_child(_build_loft(glass_sections, glass_mat))

	var roof := _box(Vector3(cfg.roof_w, 0.06, z_g3 - z_g2 + 0.1), roof_mat)
	roof.position = Vector3(0.0, roof_y + 0.03, (z_g2 + z_g3) / 2.0)
	root.add_child(roof)

static func _box(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	return mi

## Thin box oriented and stretched to span exactly between two local points --
## used by build_skeleton_visual() to draw a "rod" between two hardpoints.
static func _rod(a: Vector3, b: Vector3, m: Material, thickness: float = 0.04) -> MeshInstance3D:
	var diff := b - a
	var length: float = diff.length()
	var rod := _box(Vector3(thickness, thickness, max(length, 0.001)), m)
	rod.position = (a + b) / 2.0
	if length > 0.0001:
		var dir := diff.normalized()
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
		rod.look_at_from_position(rod.position, rod.position + dir, up)
	return rod

## rim: fakes the light-catch a real bevel would give a hard 90-degree edge --
## researched 2026-09-13 (blenderartists.org "Bevelling Low-Poly": "the bevel
## is primarily there just to catch light... virtually nothing is at a 90
## degree angle in the real world") after Roy said the car still looked
## amateurish post-detailing. Godot's BoxMesh has zero bevel and Godot 4 has
## no cheap runtime-bevel primitive, so instead of adding geometry we fake the
## same optical effect the forum describes: StandardMaterial3D's built-in rim
## lighting brightens surfaces at grazing viewing angles, same visual cue a
## real chamfered edge gives under a moving light/camera.
static func _mat(color: Color, emission_energy: float = 0.0, metallic: float = 0.3, rough: float = 0.5, rim: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.35
	return m

## Glossy paint (polish pass, 2026-10-08): a clear coat over the body colour,
## so traffic paint carries a sharp second highlight and mirrors the sky's
## city reflections (NightSky city) like the player's car.
static func _gloss(m: StandardMaterial3D) -> StandardMaterial3D:
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.1
	return m

## Shared body detailing (2026-09-13 art pass, Roy: "the player model car and
## surroundings are horrendous, they don't even make me feel like im in
## beam.ng") -- used by BOTH build_car (traffic, with wheels attached) and
## build_chassis_visual (player, wheels are separate physics nodes). Adds the
## things the old flat box body was missing: a two-tone rocker/sill panel so
## the body reads as having actual PANELS instead of one slab, front+rear
## bumpers in a contrasting matte trim, side mirrors, a split
## windshield+backlight instead of one glass box wrapping the whole cabin, and
## (coupe only) a rear spoiler -- all still boxes (deliberately low-poly per
## the "faceted geo" style direction), just enough of them in the right places
## to stop reading as a single stretched cube.
static func _add_body_details(root: Node3D, cfg: Dictionary, body_mat: Material, chassis_y0: float, skip_bumpers: bool = false) -> void:
	var trim_mat := _mat(Color(0.05, 0.05, 0.06), 0.0, 0.15, 0.7)
	var mirror_mat := body_mat

	# Rocker/sill panel -- a slightly darker, slightly narrower strip along the
	# bottom of the main body, the single cheapest trick for making a slab read
	# as "body panel over a chassis" instead of a solid block of color.
	var main_len: float = cfg.main_z1 - cfg.main_z0
	var main_zc: float = (cfg.main_z0 + cfg.main_z1) / 2.0
	var sill := _box(Vector3(float(cfg.main_w) + 0.03, 0.09, main_len - 0.1), trim_mat)
	sill.position = Vector3(0.0, chassis_y0 + 0.05, main_zc)
	root.add_child(sill)

	# Front + rear bumpers -- contrasting trim caps at each end of the body,
	# reads as an actual bumper instead of the body just stopping. Coupe skips
	# these (its nose/tail already taper in _build_coupe_body, so a bumper
	# sized off the full hood_w/main_w would stick out past the tapered body
	# edge there) -- see _add_coupe_bumpers for its tapered-matching version.
	if not skip_bumpers:
		var front_bumper := _box(Vector3(float(cfg.hood_w) + 0.05, cfg.chassis_h * 0.55, 0.16), trim_mat)
		front_bumper.position = Vector3(0.0, chassis_y0 + cfg.chassis_h * 0.3, cfg.hood_z0 - 0.02)
		root.add_child(front_bumper)
		var rear_bumper := _box(Vector3(float(cfg.main_w) + 0.05, cfg.chassis_h * 0.55, 0.16), trim_mat)
		rear_bumper.position = Vector3(0.0, chassis_y0 + cfg.chassis_h * 0.3, cfg.main_z1 + 0.02)
		root.add_child(rear_bumper)

	# Side mirrors -- small stalk+housing pair just ahead of the cabin.
	for x in [-1.0, 1.0]:
		var mirror := _box(Vector3(0.1, 0.09, 0.16), mirror_mat)
		mirror.position = Vector3(x * (float(cfg.cabin_w) / 2.0 + 0.08), chassis_y0 + cfg.chassis_h + 0.18, cfg.cabin_z0 - 0.05)
		root.add_child(mirror)

	# Fender flares (2026-09-13 art pass, per Polycount's car-modeling thread:
	# wheels need to visually tuck under a fender, not float beside a slab).
	# Real bug found while researching this: wheel_x (0.88) is already WIDER
	# than main_w/2 (0.8) -- wheels were poking out past the body edge with
	# nothing bridging the gap, reading as broken rather than wide-stance.
	# These flares span from the body edge out past wheel_x and arch down
	# over the top of each wheel, visually integrating them into the
	# silhouette instead of leaving them as separate floating cylinders.
	var flare_mat := body_mat
	var flare_half_w: float = (float(cfg.wheel_x) + cfg.wheel_r * 0.55) - (float(cfg.main_w) / 2.0)
	if flare_half_w > 0.0:
		var flare_w: float = float(cfg.main_w) + flare_half_w * 2.0
		var flare_depth: float = cfg.wheel_r * 1.3
		var flare_h: float = cfg.wheel_r * 0.5
		for wz in [-float(cfg.axle_z), float(cfg.axle_z)]:
			var flare := _box(Vector3(flare_w, flare_h, flare_depth), flare_mat)
			flare.position = Vector3(0.0, chassis_y0 + cfg.chassis_h - flare_h * 0.3, wz)
			root.add_child(flare)

	if cfg.has("spoiler") and cfg.spoiler:
		var wing_mat := trim_mat
		var stand_h := 0.22
		for x in [-0.55, 0.55]:
			var stand := _box(Vector3(0.05, stand_h, 0.05), wing_mat)
			stand.position = Vector3(x, chassis_y0 + cfg.chassis_h + stand_h * 0.5, cfg.main_z1 - 0.18)
			root.add_child(stand)
		var wing := _box(Vector3(float(cfg.main_w) * 0.85, 0.05, 0.28), wing_mat)
		wing.position = Vector3(0.0, chassis_y0 + cfg.chassis_h + stand_h, cfg.main_z1 - 0.18)
		root.add_child(wing)

## Windshield (raked, matches hood_rake) + separate backlight (rear glass) --
## replaces the single flat glass box that used to span the whole cabin roof
## with two panes meeting at the roofline, which is what actually reads as
## "cabin" instead of "glass slab".
static func _add_glass(root: Node3D, cfg: Dictionary, glass_mat: Material, roof_mat: Material, chassis_y0: float) -> void:
	var cabin_len: float = cfg.cabin_z1 - cfg.cabin_z0
	var cabin_pivot := Node3D.new()
	cabin_pivot.position = Vector3(0.0, chassis_y0 + cfg.chassis_h, cfg.cabin_z0)
	root.add_child(cabin_pivot)

	var windshield_len: float = cabin_len * 0.38
	var windshield_pivot := Node3D.new()
	windshield_pivot.position = Vector3(0.0, 0.0, 0.0)
	windshield_pivot.rotation.x = cfg.hood_rake * 1.6
	cabin_pivot.add_child(windshield_pivot)
	var windshield := _box(Vector3(cfg.cabin_w, cfg.glass_h, windshield_len), glass_mat)
	windshield.position = Vector3(0.0, cfg.glass_h / 2.0, windshield_len / 2.0)
	windshield_pivot.add_child(windshield)

	var backlight_len: float = cabin_len * 0.3
	var backlight_pivot := Node3D.new()
	backlight_pivot.position = Vector3(0.0, 0.0, cabin_len - backlight_len)
	backlight_pivot.rotation.x = -cfg.hood_rake * 1.2
	cabin_pivot.add_child(backlight_pivot)
	var backlight := _box(Vector3(cfg.cabin_w, cfg.glass_h * 0.85, backlight_len), glass_mat)
	backlight.position = Vector3(0.0, cfg.glass_h * 0.85 / 2.0, backlight_len / 2.0)
	backlight_pivot.add_child(backlight)

	# Side glass fills the gap between windshield and backlight so the roof
	# doesn't look like it's floating on two disconnected panes.
	var side_len: float = cabin_len - windshield_len - backlight_len
	if side_len > 0.05:
		var side_glass := _box(Vector3(cfg.cabin_w, cfg.glass_h, side_len), glass_mat)
		side_glass.position = Vector3(0.0, cfg.glass_h / 2.0, windshield_len + side_len / 2.0)
		cabin_pivot.add_child(side_glass)

	var roof := _box(Vector3(cfg.roof_w, 0.06, cabin_len - 0.1), roof_mat)
	roof.position = Vector3(0.0, cfg.glass_h + 0.03, cabin_len / 2.0)
	cabin_pivot.add_child(roof)

## 5-spoke alloy-look wheel: a hub cap plus thin spoke bars radiating out to
## the rim edge, instead of a flat gray disc -- the single biggest wheel
## upgrade available without a real mesh import, since flat cylinder rims are
## what made the wheels read as "plain gray drum" before.
static func _build_alloy_wheel(radius: float, rim_mat: Material, hub_mat: Material) -> Node3D:
	var root := Node3D.new()
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = radius * 0.22
	hub_mesh.bottom_radius = radius * 0.22
	hub_mesh.height = 0.33
	hub.mesh = hub_mesh
	hub.material_override = hub_mat
	hub.rotation.z = PI / 2.0
	root.add_child(hub)
	for i in range(5):
		var ang := (TAU / 5.0) * i
		var spoke := _box(Vector3(0.34, radius * 0.16, radius * 0.62), rim_mat)
		spoke.position = Vector3(0.0, sin(ang) * radius * 0.45, cos(ang) * radius * 0.45)
		spoke.rotation.x = ang
		root.add_child(spoke)
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = radius * 0.62
	ring_mesh.bottom_radius = radius * 0.62
	ring_mesh.height = 0.06
	ring.mesh = ring_mesh
	ring.material_override = rim_mat
	ring.rotation.z = PI / 2.0
	root.add_child(ring)
	return root

static func build_car(kind: String, color: Color) -> Node3D:
	var cfg: Dictionary = KIND_CONFIGS.get(kind, KIND_CONFIGS["coupe"])
	var root := Node3D.new()
	root.set_meta("kind", kind)

	var body_mat := _gloss(_mat(color, 0.0, 0.6, 0.28, 0.4))
	var glass_mat := _mat(Color(0.05, 0.1, 0.13), 0.0, 0.85, 0.12)
	var roof_mat := _mat(Color(0.07, 0.07, 0.08), 0.0, 0.3, 0.5)
	var wheel_mat := _mat(Color(0.08, 0.08, 0.1), 0.0, 0.2, 0.75)
	var rim_mat := _mat(Color(0.81, 0.83, 0.86), 0.0, 0.9, 0.22)
	var hub_mat := _mat(Color(0.15, 0.15, 0.16), 0.0, 0.4, 0.5)
	var light_mat := _mat(Color(1.0, 0.97, 0.87), 1.4)
	var tail_mat := _mat(Color(1.0, 0.23, 0.23), 1.2)

	var chassis_y0 := 0.08
	if kind == "coupe":
		root.add_child(_build_loft(_build_coupe_body(cfg, chassis_y0), body_mat))
		_add_coupe_glass(root, cfg, glass_mat, roof_mat, chassis_y0)
		_add_body_details(root, cfg, body_mat, chassis_y0, true)
		_add_coupe_bumpers(root, cfg, chassis_y0)
	else:
		var main_len: float = cfg.main_z1 - cfg.main_z0
		var main_zc: float = (cfg.main_z0 + cfg.main_z1) / 2.0
		var main := _box(Vector3(cfg.main_w, cfg.chassis_h, main_len), body_mat)
		main.position = Vector3(0.0, chassis_y0 + cfg.chassis_h / 2.0, main_zc)
		root.add_child(main)

		var hood_len: float = cfg.hood_z1 - cfg.hood_z0
		var hood_pivot := Node3D.new()
		hood_pivot.position = Vector3(0.0, chassis_y0 + cfg.chassis_h, cfg.hood_z1)
		hood_pivot.rotation.x = cfg.hood_rake
		root.add_child(hood_pivot)
		var hood := _box(Vector3(cfg.hood_w, cfg.hood_h, hood_len), body_mat)
		hood.position = Vector3(0.0, -cfg.hood_h / 2.0, -hood_len / 2.0)
		hood_pivot.add_child(hood)

		_add_glass(root, cfg, glass_mat, roof_mat, chassis_y0)
		_add_body_details(root, cfg, body_mat, chassis_y0)

	var wheel_positions := [
		Vector3(cfg.wheel_x, cfg.wheel_r, -cfg.axle_z),
		Vector3(-cfg.wheel_x, cfg.wheel_r, -cfg.axle_z),
		Vector3(cfg.wheel_x, cfg.wheel_r, cfg.axle_z),
		Vector3(-cfg.wheel_x, cfg.wheel_r, cfg.axle_z),
	]
	for wp in wheel_positions:
		var tire := MeshInstance3D.new()
		var tire_mesh := CylinderMesh.new()
		tire_mesh.top_radius = cfg.wheel_r
		tire_mesh.bottom_radius = cfg.wheel_r
		tire_mesh.height = 0.3
		tire.mesh = tire_mesh
		tire.material_override = wheel_mat
		tire.rotation.z = PI / 2.0
		tire.position = wp
		root.add_child(tire)

		var rim := _build_alloy_wheel(cfg.wheel_r, rim_mat, hub_mat)
		rim.position = wp
		root.add_child(rim)

	for x in [-0.45, 0.45]:
		var hl := _box(Vector3(0.2, 0.13, 0.06), light_mat)
		hl.position = Vector3(x, chassis_y0 + cfg.hood_h * 0.5 + 0.08, cfg.hood_z0 + 0.02)
		root.add_child(hl)
		var tl := _box(Vector3(0.2, 0.13, 0.06), tail_mat)
		tl.position = Vector3(x, chassis_y0 + 0.17, cfg.main_z1 - 0.02)
		root.add_child(tl)

	root.set_meta("body_mat", body_mat)
	root.set_meta("half_w", float(cfg.main_w) / 2.0)
	root.set_meta("half_l", (float(cfg.main_z1) - float(cfg.hood_z0)) / 2.0)
	return root

static func recolor(car: Node3D, color: Color) -> void:
	var m: StandardMaterial3D = car.get_meta("body_mat")
	if m:
		m.albedo_color = color

## Body/hood/cabin/lights ONLY, no wheels -- for attaching to a VehicleBody3D
## where the wheels are separate VehicleWheel3D physics nodes (see
## build_wheel_visual). Added for milestone 2's real-physics player car so
## suspension motion is genuine, not faked -- see ROADMAP.md/memory decision
## on why wheels can't just be static children of the chassis anymore.
static func build_chassis_visual(kind: String, color: Color) -> Node3D:
	var cfg: Dictionary = KIND_CONFIGS.get(kind, KIND_CONFIGS["coupe"])
	var root := Node3D.new()
	root.set_meta("kind", kind)

	var body_mat := _gloss(_mat(color, 0.0, 0.6, 0.28, 0.4))
	var glass_mat := _mat(Color(0.05, 0.1, 0.13), 0.0, 0.85, 0.12)
	var roof_mat := _mat(Color(0.07, 0.07, 0.08), 0.0, 0.3, 0.5)
	var light_mat := _mat(Color(1.0, 0.97, 0.87), 1.4)
	var tail_mat := _mat(Color(1.0, 0.23, 0.23), 1.2)

	var chassis_y0 := 0.08
	if kind == "coupe":
		root.add_child(_build_loft(_build_coupe_body(cfg, chassis_y0), body_mat))
		_add_coupe_glass(root, cfg, glass_mat, roof_mat, chassis_y0)
		_add_body_details(root, cfg, body_mat, chassis_y0, true)
		_add_coupe_bumpers(root, cfg, chassis_y0)
	else:
		var main_len: float = cfg.main_z1 - cfg.main_z0
		var main_zc: float = (cfg.main_z0 + cfg.main_z1) / 2.0
		var main := _box(Vector3(cfg.main_w, cfg.chassis_h, main_len), body_mat)
		main.position = Vector3(0.0, chassis_y0 + cfg.chassis_h / 2.0, main_zc)
		root.add_child(main)

		var hood_len: float = cfg.hood_z1 - cfg.hood_z0
		var hood_pivot := Node3D.new()
		hood_pivot.position = Vector3(0.0, chassis_y0 + cfg.chassis_h, cfg.hood_z1)
		hood_pivot.rotation.x = cfg.hood_rake
		root.add_child(hood_pivot)
		var hood := _box(Vector3(cfg.hood_w, cfg.hood_h, hood_len), body_mat)
		hood.position = Vector3(0.0, -cfg.hood_h / 2.0, -hood_len / 2.0)
		hood_pivot.add_child(hood)

		_add_glass(root, cfg, glass_mat, roof_mat, chassis_y0)
		_add_body_details(root, cfg, body_mat, chassis_y0)

	for x in [-0.45, 0.45]:
		var hl := _box(Vector3(0.2, 0.13, 0.06), light_mat)
		hl.position = Vector3(x, chassis_y0 + cfg.hood_h * 0.5 + 0.08, cfg.hood_z0 + 0.02)
		root.add_child(hl)
		var tl := _box(Vector3(0.2, 0.13, 0.06), tail_mat)
		tl.position = Vector3(x, chassis_y0 + 0.17, cfg.main_z1 - 0.02)
		root.add_child(tl)

	root.set_meta("body_mat", body_mat)
	root.set_meta("half_w", float(cfg.main_w) / 2.0)
	root.set_meta("half_l", (float(cfg.main_z1) - float(cfg.hood_z0)) / 2.0)
	return root

## Skeleton test rig (2026-09-13) -- no body panels at all, just thin rods at
## the real hardpoints (axle centerlines, side rails, a CoM stub, a nose
## pointer) so suspension travel, wheel motion, and weight-transfer tilt are
## fully visible during physics testing instead of hidden behind opaque
## panels. Uses the SAME wheel_x/axle_z as build_chassis_visual's KIND_CONFIGS
## (and player.gd's own CFG, which is kept numerically identical on purpose)
## so the frame lines up exactly with the real wheel positions. Swap back to
## build_chassis_visual once real car art lands (a later milestone per
## ROADMAP.md) -- this is explicitly a testing aid, not the final look.
static func build_skeleton_visual(kind: String, color: Color) -> Node3D:
	var cfg: Dictionary = KIND_CONFIGS.get(kind, KIND_CONFIGS["coupe"])
	var root := Node3D.new()
	root.set_meta("kind", kind)

	var rod_mat := _mat(color, 0.8, 0.1, 0.6)  # emissive so the frame reads clearly against the road

	var wheel_x: float = cfg.wheel_x
	var axle_z: float = cfg.axle_z
	var mount_y: float = 0.3 + cfg.wheel_r  # matches player.gd's WHEEL_MOUNT_Y (WHEEL_REST_LENGTH=0.3 + wheel_r)

	# Front and rear axle crossbars (left wheel hardpoint to right wheel hardpoint).
	root.add_child(_rod(Vector3(-wheel_x, mount_y, -axle_z), Vector3(wheel_x, mount_y, -axle_z), rod_mat))
	root.add_child(_rod(Vector3(-wheel_x, mount_y, axle_z), Vector3(wheel_x, mount_y, axle_z), rod_mat))
	# Side rails (front-left to rear-left, front-right to rear-right) -- reads as a ladder frame.
	root.add_child(_rod(Vector3(-wheel_x, mount_y, -axle_z), Vector3(-wheel_x, mount_y, axle_z), rod_mat))
	root.add_child(_rod(Vector3(wheel_x, mount_y, -axle_z), Vector3(wheel_x, mount_y, axle_z), rod_mat))
	# Center spine, so the frame doesn't look like two disconnected axles.
	root.add_child(_rod(Vector3(0.0, mount_y, -axle_z), Vector3(0.0, mount_y, axle_z), rod_mat))
	# Nose pointer -- a short forward stub so front/back is unambiguous at a glance
	# (forward = -Z, see player.gd's current_speed() convention).
	root.add_child(_rod(Vector3(0.0, mount_y, -axle_z), Vector3(0.0, mount_y, -axle_z - 0.5), rod_mat))
	# CoM marker -- a short vertical stub near the tuned center_of_mass offset
	# from player.gd, so the actual physics balance point is visible, not just the frame.
	root.add_child(_rod(Vector3(0.0, mount_y - 0.5, 0.15), Vector3(0.0, mount_y + 0.2, 0.15), rod_mat))

	root.set_meta("body_mat", rod_mat)
	root.set_meta("half_w", wheel_x)
	root.set_meta("half_l", axle_z + 0.5)
	return root

## Tire+rim visual only, at local origin -- parent this under a VehicleWheel3D
## and it inherits that wheel's real suspension travel and spin for free.
static func build_wheel_visual(kind: String) -> Node3D:
	var cfg: Dictionary = KIND_CONFIGS.get(kind, KIND_CONFIGS["coupe"])
	var root := Node3D.new()
	var wheel_mat := _mat(Color(0.08, 0.08, 0.1), 0.0, 0.2, 0.75)
	var rim_mat := _mat(Color(0.81, 0.83, 0.86), 0.0, 0.9, 0.22)
	var hub_mat := _mat(Color(0.15, 0.15, 0.16), 0.0, 0.4, 0.5)

	var tire := MeshInstance3D.new()
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = cfg.wheel_r
	tire_mesh.bottom_radius = cfg.wheel_r
	tire_mesh.height = 0.3
	tire.mesh = tire_mesh
	tire.material_override = wheel_mat
	tire.rotation.z = PI / 2.0
	root.add_child(tire)

	root.add_child(_build_alloy_wheel(cfg.wheel_r, rim_mat, hub_mat))

	return root

# ---------- shared, merged visuals for traffic (traffic milestone 4) ----------
# build_chassis_visual() and build_wheel_visual() make a fresh node tree with
# fresh meshes and materials every call: about 17 MeshInstance3D for a coupe
# body and 8 per wheel, so ~49 draw calls per traffic car, and 40 cars meant
# 40 copies of identical resources. The shared versions build that same tree
# once per (kind, colour) (wheels: per kind), bake it into ONE ArrayMesh with
# one surface per distinct material, and hand every car a single
# MeshInstance3D pointing at the cached mesh. Same vertices, normals and
# materials, so it looks the same; it is one draw call per material instead
# of one per box. Measured 2026-10-06 (windowed, all cars in view): see the
# traffic milestone 4 PR for the numbers.
# recolor() does not work on these (the material is shared by every car of
# that colour); traffic never recolours.

static var _chassis_cache := {}  # "kind|rrggbbaa" -> ArrayMesh
static var _wheel_cache := {}    # kind -> ArrayMesh

static func shared_chassis_visual(kind: String, color: Color) -> Node3D:
	var cfg: Dictionary = KIND_CONFIGS.get(kind, KIND_CONFIGS["coupe"])
	var key := "%s|%s" % [kind, color.to_html()]
	var mesh: ArrayMesh = _chassis_cache.get(key)
	if mesh == null:
		var src := build_chassis_visual(kind, color)
		mesh = merge_meshes(src)
		src.free()
		_chassis_cache[key] = mesh
	var root := Node3D.new()
	root.set_meta("kind", kind)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	root.add_child(mi)
	root.set_meta("half_w", float(cfg.main_w) / 2.0)
	root.set_meta("half_l", (float(cfg.main_z1) - float(cfg.hood_z0)) / 2.0)
	return root

static func shared_wheel_visual(kind: String) -> Node3D:
	var mesh: ArrayMesh = _wheel_cache.get(kind)
	if mesh == null:
		var src := build_wheel_visual(kind)
		mesh = merge_meshes(src)
		src.free()
		_wheel_cache[kind] = mesh
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Wheel"
	mi.mesh = mesh
	root.add_child(mi)
	return root

## Bakes every MeshInstance3D under `root` (not in the tree; transforms are
## taken relative to root) into one ArrayMesh, one surface per distinct
## material. Materials that are equal by value (CarBuilder makes a fresh trim
## material for every bumper) share a surface.
static func merge_meshes(root: Node3D) -> ArrayMesh:
	var tools := {}
	var mats := {}
	var order: Array[String] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != root:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(s)
			var key := _material_key(mat)
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
				mats[key] = mat
				order.append(key)
			# De-indexed first: SurfaceTool.append_from keeps a source's index
			# list, and once one indexed box is in, the plain (non-indexed)
			# loft triangles appended before it are dropped at commit.
			var flat := SurfaceTool.new()
			flat.create_from(mi.mesh, s)
			flat.deindex()
			(tools[key] as SurfaceTool).append_from(flat.commit(), 0, xf)
	var out := ArrayMesh.new()
	for key in order:
		out = (tools[key] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mats[key])
	return out

static func _material_key(m: Material) -> String:
	var sm := m as StandardMaterial3D
	if sm == null:
		return str(m.get_instance_id()) if m != null else "none"
	return "%s|%.3f|%.3f|%s|%.3f|%s|%.3f" % [sm.albedo_color.to_html(), sm.metallic, sm.roughness,
		sm.emission_enabled, sm.emission_energy_multiplier, sm.rim_enabled, sm.rim]
