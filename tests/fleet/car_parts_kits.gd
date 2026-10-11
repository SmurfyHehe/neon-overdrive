extends SceneTree

# Cars from parts, after the coupe pilot: the cars built with a kit
# (tools/car_pipeline/kits.py). One table row per car; for each:
#   slots     every required part is in the glb by name: brakes on all four
#             wheels, plates front and rear, the lamps as parts of their own
#             (head, tail, brake, reverse, blinkers), wipers, the fuel flap on
#             its hinge, handles, seals, arch liners, what is under the lids;
#             the wagon also its barn doors, rear wiper and roof rails
#   lamps     every lamp part carries its own glow material, so it can be lit
#             on its own later
#   brakes    each wheel mesh has its drum (240 mm) or disc; the hubcaps are
#             on the wheels the car should have them on, wheel nuts on the rest
#   plates    520 x 110 mm, in a dark recess
#   flap      the fuel flap swings outward on its hinge
#   gaps      the shut gap between panels is 3.5 to 4.5 mm (5 mm between the
#             wagon's barn doors, never more)
#   symmetry  every part that is not listed as one-sided in body.json is the
#             mirror image of its twin (or of itself) within 0.05 mm; at most
#             12 vertices a car may differ in normal or ao after the import
#   budget    body triangles within the ceiling (7,000), body.json agrees
#   draws     the car from parts costs no more draw calls than its one-piece
#             sheet body (NEON_PARTS_LEGACY=1), wheels and underside included
#   legacy    NEON_PARTS_LEGACY=1 still builds the sheet body
#   under     a rear-engined car's underside has no pipe under the cabin
#
# Needs the import cache (godot --headless --path . --import after a rebuild).
#   godot --headless --path . -s res://tests/fleet/car_parts_kits.gd
# NEON_PARTS_CAR=<id> checks one car only.

const CEILING := 7000
const GAP_MIN := 0.0035
const GAP_MAX := 0.0045
const PAINTS := ["paint", "paint_primer", "paint_rust", "paint_bondo"]
const COMMON := [
	"body", "underbody", "hood", "trunk", "door_l", "door_r", "fender_fl", "fender_fr", "bumper_f", "bumper_r",
	"glass_windshield", "glass_backlight", "glass_door_l", "glass_door_r",
	"seal_windshield", "seal_backlight", "seal_door_l", "seal_door_r",
	"handle_l", "handle_r", "arch_liner_fl", "arch_liner_fr", "arch_liner_rl", "arch_liner_rr",
	"plate_f", "plate_r", "wiper_l", "wiper_r", "fuel_flap", "fuel_recess", "exhaust",
	"head_l", "head_r",
]
## part -> the glow material it must carry
const CARS := {
	"p0_beater": {
		"parts": ["louvres", "bumper_blade", "mirror_l", "mirror_r", "bay_spare", "bay_tank", "engine",
			"susp_fl", "susp_fr", "susp_rl", "susp_rr"],
		"lamps": {"head_l": "glow_head", "head_r": "glow_head", "turn_fl": "glow_turn", "turn_fr": "glow_turn",
			"tail_l": "glow_tail", "brake_l": "glow_brake", "turn_rl": "glow_turn",
			"reverse_l": "glow_reverse", "reverse_r": "glow_reverse"},
		"anchors": ["bay_engine", "tank", "torsion_bar_f", "swing_axle_r"],
		"engine_behind_axle": true,
		## corner -> brake radius (all drums, 240 mm)
		"brakes": {"fl": 0.12, "fr": 0.12, "rl": 0.12, "rr": 0.12},
		"no_hubcap": ["fr"],
		## [part a, part b, across, facing, along axis, at]
		"gaps": [
			["hood", "fender_fr", Vector3.RIGHT, Vector3.UP, 2, -1.225],
			["fender_fr", "door_r", Vector3.BACK, Vector3.RIGHT, 1, 0.59],
			["door_r", "body", Vector3.BACK, Vector3.RIGHT, 1, 0.60],
			["trunk", "body", Vector3.RIGHT, Vector3.UP, 2, 1.575],
		],
		"rear_engine": true,
	},
	"p7_wagon": {
		## no deck lid: the tail is two barn doors, each with its half of the rear glass
		"without": ["trunk", "glass_backlight", "seal_backlight"],
		"parts": ["barn_l", "barn_r", "glass_barn_l", "glass_barn_r", "seal_barn_l", "seal_barn_r", "handle_barn_l", "handle_barn_r",
			"wiper_rear", "roof_rails", "grille", "mirror_l", "mirror_r", "bumper_f_insert", "bumper_r_insert", "rub_strip",
			"rub_door_l", "rub_door_r", "caliper_fl", "caliper_fr", "engine", "spare", "susp_fl", "susp_fr", "susp_rl", "susp_rr"],
		"lamps": {"head_l": "glow_head", "head_r": "glow_head", "turn_fl": "glow_turn", "turn_fr": "glow_turn",
			"turn_rl": "glow_turn", "turn_rr": "glow_turn", "tail_l": "glow_tail", "tail_r": "glow_tail",
			"brake_l": "glow_brake", "brake_r": "glow_brake", "brake_c": "glow_brake",
			"reverse_l": "glow_reverse", "reverse_r": "glow_reverse"},
		"anchors": ["bay_engine", "tank", "torsion_beam_r", "spare_cradle", "strut_top_fl", "strut_top_fr"],
		"hinges": ["hinge_hood", "hinge_door_l", "hinge_door_r", "hinge_barn_l", "hinge_barn_r"],
		## small discs in front, 200 mm drums at the rear
		"brakes": {"fl": 0.118, "fr": 0.118, "rl": 0.10, "rr": 0.10},
		"no_hubcap": ["rl"],
		"gaps": [
			["hood", "fender_fr", Vector3.RIGHT, Vector3.UP, 2, -1.42],
			["fender_fr", "door_r", Vector3.BACK, Vector3.RIGHT, 1, 0.60],
			["door_r", "body", Vector3.BACK, Vector3.RIGHT, 1, 0.60],
			# between the two barn doors: 5 mm (Roy, 2026-10-11), the most the parts rule allows
			["barn_l", "barn_r", Vector3.RIGHT, Vector3.BACK, 1, 0.57, 0.0049, 0.0050],
		],
	},
	"p2_hothatch": {
		## no deck lid: the tail is one glass hatch on the roof's rear edge, its glass goes up with it
		"without": ["trunk"],
		"parts": ["hatch", "handle_hatch", "wiper_rear", "plate_lamp", "spoiler", "grille", "mirror_l", "mirror_r",
			"blister_fl", "blister_fr", "blister_rl", "blister_rr", "rub_strip_l", "rub_strip_r", "rub_door_l", "rub_door_r",
			"bumper_f_insert", "bumper_r_insert", "lamp_block_l", "lamp_block_r", "caliper_fl", "caliper_fr",
			"engine", "cargo", "susp_fl", "susp_fr", "susp_rl", "susp_rr"],
		"lamps": {"head_l": "glow_head", "head_r": "glow_head", "turn_fl": "glow_turn", "turn_fr": "glow_turn",
			"turn_rl": "glow_turn", "turn_rr": "glow_turn", "tail_l": "glow_tail", "tail_r": "glow_tail",
			"brake_l": "glow_brake", "brake_r": "glow_brake", "brake_c": "glow_brake",
			"reverse_l": "glow_reverse", "reverse_r": "glow_reverse",
			"fog_l": "glow_lens", "fog_r": "glow_lens", "plate_lamp": "glow_lens"},
		"anchors": ["bay_engine", "tank", "torsion_beam_r", "strut_top_fl", "strut_top_fr"],
		"hinges": ["hinge_hood", "hinge_door_l", "hinge_door_r", "hinge_hatch"],
		"on_hinge": {"hinge_hatch": ["hatch", "glass_backlight", "seal_backlight", "plate_r", "plate_lamp", "wiper_rear"]},
		## 262 mm discs in front, 200 mm drums at the rear; alloy wheels, a centre cap on all four
		"brakes": {"fl": 0.131, "fr": 0.131, "rl": 0.10, "rr": 0.10},
		"no_hubcap": [],
		"gaps": [
			["hood", "fender_fr", Vector3.RIGHT, Vector3.UP, 2, -1.69],
			["fender_fr", "door_r", Vector3.BACK, Vector3.RIGHT, 1, 0.60],
			["door_r", "body", Vector3.BACK, Vector3.RIGHT, 1, 0.60],
			["hatch", "body", Vector3.RIGHT, Vector3.BACK, 1, 0.58],
		],
	},
	"p4_kei": {
		## open top: the screen's glass wedge is the windscreen, front and back; the lamps are pop-ups, not head_*
		"without": ["glass_backlight", "seal_backlight", "head_l", "head_r"],
		"parts": ["popup_l", "popup_r", "hump_l", "hump_r", "intake_l", "intake_r", "intake_lip_l", "intake_lip_r",
			"seal_cockpit", "arch_lips", "grille", "mirror_l", "mirror_r", "bumper_r_insert", "caliper_fl", "caliper_fr", "bay_floor"],
		"lamps": {"popup_l": "glow_head", "popup_r": "glow_head", "turn_fl": "glow_turn", "turn_fr": "glow_turn",
			"turn_rl": "glow_turn", "turn_rr": "glow_turn", "tail_l": "glow_tail", "tail_r": "glow_tail",
			"brake_l": "glow_brake", "brake_r": "glow_brake", "brake_c": "glow_brake",
			"reverse_c": "glow_reverse", "plate_lamp": "glow_lens"},
		"anchors": ["bay_engine", "tank", "diff"],
		"hinges": ["hinge_hood", "hinge_trunk", "hinge_door_l", "hinge_door_r", "hinge_popup_l", "hinge_popup_r"],
		"on_hinge": {"hinge_popup_l": ["popup_l"], "hinge_popup_r": ["popup_r"]},
		## the short side pane is fixed to the screen frame: it must not swing with the door
		"off_hinge": {"hinge_door_l": ["glass_door_l"], "hinge_door_r": ["glass_door_r"]},
		## 230 mm discs in front, 180 mm drums at the rear; alloy wheels, a centre cap on all four
		"brakes": {"fl": 0.115, "fr": 0.115, "rl": 0.09, "rr": 0.09},
		"no_hubcap": [],
		"gaps": [
			["hood", "fender_fr", Vector3.RIGHT, Vector3.UP, 2, -1.43],
			["fender_fr", "door_r", Vector3.BACK, Vector3.RIGHT, 1, 0.47],
			["door_r", "body", Vector3.BACK, Vector3.RIGHT, 1, 0.47],
			["trunk", "body", Vector3.RIGHT, Vector3.UP, 2, 0.75],
		],
	},
}

var fails := 0
var checks := 0

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.set_environment("NEON_PARTS_LEGACY", "")
	OS.set_environment("NEON_CAR_PANELS", "")
	var only := OS.get_environment("NEON_PARTS_CAR")
	for id in CARS:
		if only == "" or only == id:
			_car(id, CARS[id])
	print("PASS (%d checks)" % checks if fails == 0 else "FAILURES: %d of %d checks" % [fails, checks])
	quit(1 if fails > 0 else 0)

func _car(id: String, want: Dictionary) -> void:
	_check(CarAssembler.has_car(id), "%s: assets/cars/%s/body.glb should be in the project" % [id, id])
	if not CarAssembler.has_car(id):
		return
	var meta := _load_meta(id)
	var names := CarAssembler.part_names(id)

	# ---- slots
	for p in COMMON + want.parts + want.lamps.keys():
		if p in want.get("without", []):
			_check(not names.has(p), "%s: part %s should not be on this car" % [id, p])
		else:
			_check(names.has(p), "%s: part %s missing from the glb" % [id, p])
	for a in want.anchors:
		_check(CarAssembler.anchor(id, a) != Transform3D.IDENTITY, "%s: anchor %s missing" % [id, a])
	if want.get("engine_behind_axle", false):
		var hub_z: float = CarAssembler.anchor(id, "wheel_rr").origin.z
		_check(CarAssembler.anchor(id, "bay_engine").origin.z > hub_z, "%s: the engine should be behind the rear axle" % id)
		_check(CarAssembler.part_aabb(id, "engine").position.z > hub_z, "%s: the engine part should be behind the rear axle" % id)
		_check(CarAssembler.anchor(id, "tank").origin.z < 0.0, "%s: the tank should be in the front" % id)

	# ---- lamps: each its own part with its own glow material
	for p in want.lamps:
		_check(CarAssembler.part_arrays(id, p).has(want.lamps[p]), "%s: lamp part %s should carry %s" % [id, p, want.lamps[p]])

	# ---- brakes, hubcaps, wheel nuts
	for corner in want.brakes:
		var wm := CarAssembler.wheel_mesh(id, corner)
		_check(wm != null and wm.get_surface_count() == 1, "%s: wheel %s should be one mesh with one surface" % [id, corner])
		var mats: Dictionary = CarAssembler._load(id).wheels.get(corner, {})
		var sx := -1.0 if corner.ends_with("l") else 1.0
		var r_in := 0.0     # the brake: steel on the inboard side of the tyre
		var nuts := 0       # steel proud of the outboard face
		var inboard := 0.0
		if mats.has("rubber"):
			for v in (mats["rubber"].v as PackedVector3Array):
				inboard = maxf(inboard, -v.x * sx)
		if mats.has("steel"):
			for v in (mats["steel"].v as PackedVector3Array):
				if -v.x * sx > inboard + 0.005:
					r_in = maxf(r_in, Vector2(v.y, v.z).length())
				elif v.x * sx > inboard + 0.01:
					nuts += 1
		_check(absf(r_in - float(want.brakes[corner])) < 0.004, "%s: wheel %s brake radius %.3f, want %.3f" % [id, corner, r_in, float(want.brakes[corner])])
		var capped := mats.has("chrome")
		if corner in want.no_hubcap:
			_check(not capped and nuts > 0, "%s: wheel %s should have no hubcap and show its wheel nuts" % [id, corner])
		else:
			_check(capped, "%s: wheel %s should have its hubcap" % [id, corner])

	# ---- plates: 520 x 110 in a dark recess
	for p in ["plate_f", "plate_r"]:
		var mats := CarAssembler.part_arrays(id, p)
		_check(mats.has("plate") and mats.has("rubber"), "%s: %s should be a plate in a dark recess" % [id, p])
		if mats.has("plate"):
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for v in (mats["plate"].v as PackedVector3Array):
				lo = lo.min(v)
				hi = hi.max(v)
			_check(absf(hi.x - lo.x - 0.52) < 0.005 and absf(hi.y - lo.y - 0.11) < 0.005,
				"%s: %s is %.0f x %.0f mm, want 520 x 110" % [id, p, (hi.x - lo.x) * 1000.0, (hi.y - lo.y) * 1000.0])

	# ---- the fuel flap opens outward
	var hinges := CarAssembler.hinges(id)
	_check(hinges.has("hinge_fuel_flap") and "fuel_flap" in hinges.get("hinge_fuel_flap", {}).get("parts", []),
		"%s: the fuel flap should hang on hinge_fuel_flap" % id)
	if hinges.has("hinge_fuel_flap"):
		var h: Dictionary = hinges["hinge_fuel_flap"]
		var box := CarAssembler.part_aabb(id, "fuel_flap")
		var far: Vector3 = box.get_center() - h.origin
		var turned := far.rotated(h.axis, deg_to_rad(h.open_sign * h.open_deg))
		var side := signf(h.origin.x)
		_check(turned.x * side > far.x * side + 0.03, "%s: the fuel flap should swing outward" % id)
	for hname in want.get("hinges", ["hinge_hood", "hinge_trunk", "hinge_door_l", "hinge_door_r"]):
		_check(hinges.has(hname), "%s: %s missing" % [id, hname])
	for hname in want.get("on_hinge", {}):
		for p in want.on_hinge[hname]:
			_check(p in hinges.get(hname, {}).get("parts", []), "%s: %s should hang on %s" % [id, p, hname])
	for hname in want.get("off_hinge", {}):
		for p in want.off_hinge[hname]:
			_check(not (p in hinges.get(hname, {}).get("parts", [])), "%s: %s should not hang on %s" % [id, p, hname])

	# ---- gaps
	var gap_txt := PackedStringArray()
	for g in want.gaps:
		var gap := _gap(id, g[0], g[1], g[2], g[3], g[4], g[5])
		gap_txt.append("%s/%s %.2f" % [g[0], g[1], gap * 1000.0])
		var lo: float = g[6] if g.size() > 6 else GAP_MIN
		var hi: float = g[7] if g.size() > 7 else GAP_MAX
		_check(gap >= lo - 1e-5 and gap <= hi + 1e-5, "%s: gap %s to %s is %.2f mm, want %.1f-%.1f" % [id, g[0], g[1], gap * 1000.0, lo * 1000.0, hi * 1000.0])
	if not meta.is_empty():
		_check(float(meta.shut.gap) >= GAP_MIN and float(meta.shut.gap) <= GAP_MAX, "%s: body.json gap %.4f" % [id, float(meta.shut.gap)])

	# ---- symmetry
	var one_sided: Dictionary = meta.get("symmetry", {}).get("not_mirrored", {})
	var mirrored := 0
	var shade_off := 0
	for pname in names:
		if one_sided.has(pname):
			continue
		var other := pname
		if pname.ends_with("l") and names.has(pname.left(-1) + "r"):
			continue
		if pname.ends_with("r") and names.has(pname.left(-1) + "l"):
			other = pname.left(-1) + "l"
			if one_sided.has(other):
				continue
		var miss := _mirror_misses(CarAssembler.part_arrays(id, pname), CarAssembler.part_arrays(id, other))
		_check(miss[0] == 0, "%s: %s is not the mirror image of %s (%d vertices off)" % [id, other, pname, miss[0]])
		shade_off += int(miss[1])
		mirrored += 1
	_check(shade_off <= 12, "%s: %d mirrored vertices differ in normal or ao, at most 12 allowed" % [id, shade_off])
	for pname in one_sided:
		_check(str(one_sided[pname]) != "", "%s: one-sided part %s needs its reason in body.json" % [id, pname])

	# ---- budget, materials
	var tris := CarAssembler.triangle_count(id)
	_check(tris <= CEILING, "%s: %d body triangles, ceiling %d" % [id, tris, CEILING])
	if not meta.is_empty():
		_check(tris == int(meta.tris_body), "%s: merged %d triangles, body.json says %d" % [id, tris, int(meta.tris_body)])
		for mname in meta.materials:
			_check(CarAssembler.MATERIALS.has(mname), "%s: material %s is not one the assembler knows" % [id, mname])
	var wheel_tris := 0
	for corner in want.brakes:
		wheel_tris += CarAssembler.wheel_triangle_count(id, corner)

	# ---- draw calls against the one-piece sheet body, and the legacy switch
	var draws := NpcCarBuilder.draw_call_count(id, "stock")
	var car := NpcCarBuilder.chassis_visual(id, "stock", NpcCarBuilder.sheet_paint(id))
	var body := car.get_node("Body") as MeshInstance3D
	_check(body.mesh.get_surface_count() == 4 and body.has_meta("car_id"), "%s: the body should be the assembled one, 4 surfaces" % id)
	_check(car.has_meta("body_mat") and (car.get_meta("body_mat") as ShaderMaterial).get_shader_parameter("paint") != null,
		"%s: the paint material should keep its `paint` uniform" % id)
	_check((car.get_meta("body_mat") as ShaderMaterial).shader.code.contains("uniform float dirt"), "%s: the paint shader should keep `dirt`" % id)
	var meshes := 0
	for n in car.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.visibility_range_begin <= 0.0:      # the far underside plate swaps in for the near one
			meshes += mi.mesh.get_surface_count()
	_check(meshes + 4 == draws, "%s: %d surfaces on the body node plus 4 wheels, draw_call_count says %d" % [id, meshes, draws])
	car.free()
	var wheel := NpcCarBuilder.wheel_visual(id, "stock", Vector3(-0.7, 0.3, -1.2))
	_check((wheel.get_node("Mesh") as MeshInstance3D).mesh == CarAssembler.wheel_mesh(id, "fl"), "%s: the front left wheel should be the glb's" % id)
	wheel.free()
	OS.set_environment("NEON_PARTS_LEGACY", "1")
	var old_draws := NpcCarBuilder.draw_call_count(id, "stock")
	var old_tris := NpcCarBuilder.triangle_count(id, "stock")
	var old := NpcCarBuilder.chassis_visual(id, "stock", NpcCarBuilder.sheet_paint(id))
	_check(not (old.get_node("Body") as MeshInstance3D).has_meta("car_id"), "%s: NEON_PARTS_LEGACY=1 should build the sheet body" % id)
	old.free()
	OS.set_environment("NEON_PARTS_LEGACY", "")
	_check(draws <= old_draws, "%s: %d draw calls from parts, the sheet body costs %d" % [id, draws, old_draws])

	# ---- the underside of a rear-engined car
	if want.get("rear_engine", false):
		var p := NpcCarBuilder.undercarriage_params(id, "stock")
		_check(String(p.get("engine", "")) == "rear", "%s: the underside should be built rear-engined" % id)
		var pipes := _steel_under_cabin(p)
		var front := p.duplicate()
		front["engine"] = "front"
		_check(pipes == 0 and _steel_under_cabin(front) > 0,
			"%s: no pipe or shaft should run under the cabin (%d steel vertices there, %d with the front-engine layout)" % [id, pipes, _steel_under_cabin(front)])

	print("%s: %d parts (%d mirrored within 0.05 mm, %d shading mismatches, %d one-sided), %d body triangles + %d in the wheels (sheet car: %d all in), %d draw calls (sheet car: %d), gaps mm: %s" % [
		id, names.size(), mirrored, shade_off, one_sided.size(), tris, wheel_tris, old_tris, draws, old_draws, ", ".join(gap_txt)])

## Vertices of the underside where a front-engined car's exhaust runs: under
## the cabin (within half a metre of the middle of the car), 0.26 to 0.34 m
## off the centre line, more than 4 cm below the floor.
func _steel_under_cabin(p: Dictionary) -> int:
	var mesh := Undercarriage.build_mesh(p, Undercarriage.ROLE_PLAYER)
	var n := 0
	for si in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for k in v.size():
			if absf(v[k].z) < 0.5 and absf(v[k].x) > 0.26 and absf(v[k].x) < 0.34 and v[k].y < float(p.floor_y) - 0.04:
				n += 1
	return n

func _load_meta(id: String) -> Dictionary:
	var f := FileAccess.open("res://assets/cars/%s/body.json" % id, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

## The shut gap between two parts across `across`, measured between their
## outer skin edges (painted vertices with shut = 1 whose normal is along
## `facing`) in a 6 cm window at `at` along car axis `along` (0 x, 1 y, 2 z).
func _gap(car_id: String, part_a: String, part_b: String, across: Vector3, facing: Vector3, along: int, at: float) -> float:
	var a := _edge_extent(car_id, part_a, across, facing, along, at, true, -INF)
	var b := _edge_extent(car_id, part_b, across, facing, along, at, false, a - 0.02)
	return b - a

func _edge_extent(car_id: String, part: String, across: Vector3, facing: Vector3, along: int, at: float, want_max: bool, beyond: float) -> float:
	var best := -INF if want_max else INF
	var mats: Dictionary = CarAssembler.part_arrays(car_id, part)
	for mname in PAINTS:
		if not mats.has(mname):
			continue
		var m: Dictionary = mats[mname]
		var v: PackedVector3Array = m.v
		var n: PackedVector3Array = m.n
		var ao: PackedByteArray = m.ao
		for k in v.size():
			if ao[k * 4 + 1] < 250 or n[k].dot(facing) < 0.7 or absf(v[k][along] - at) > 0.03:
				continue
			var d := v[k].dot(across)
			if want_max:
				best = maxf(best, d)
			elif d > beyond:
				best = minf(best, d)
	return best

## Part A against part B as its mirror image -> [off, shade]: `off` counts the
## vertices of A with no vertex of B at the mirrored position within 0.05 mm
## (plus any difference in triangle count); `shade` those that have one, but
## none with the mirrored normal and the same ao and shut (Godot's importer
## welds a handful of vertices differently on the two sides).
func _mirror_misses(a: Dictionary, b: Dictionary) -> Array:
	var off := 0
	var shade := 0
	for mname in a:
		if not b.has(mname):
			off += (a[mname].v as PackedVector3Array).size()
			continue
		var av: PackedVector3Array = a[mname].v
		var an: PackedVector3Array = a[mname].n
		var aa: PackedByteArray = a[mname].ao
		var bv: PackedVector3Array = b[mname].v
		var bn: PackedVector3Array = b[mname].n
		var ba: PackedByteArray = b[mname].ao
		off += absi((a[mname].i as PackedInt32Array).size() - (b[mname].i as PackedInt32Array).size())
		var at := {}
		for k in bv.size():
			var key := Vector3i(roundi(bv[k].x * 10000.0), roundi(bv[k].y * 10000.0), roundi(bv[k].z * 10000.0))
			if not at.has(key):
				at[key] = []
			at[key].append(k)
		for k in av.size():
			var want := Vector3(-av[k].x, av[k].y, av[k].z)
			var nm := Vector3(-an[k].x, an[k].y, an[k].z)
			var cell := Vector3i(roundi(want.x * 10000.0), roundi(want.y * 10000.0), roundi(want.z * 10000.0))
			var there := false
			var same := false
			for dx in [0, -1, 1]:
				for dy in [0, -1, 1]:
					for dz in [0, -1, 1]:
						for j in at.get(cell + Vector3i(dx, dy, dz), []):
							if want.distance_to(bv[j]) < 5e-5:
								there = true
								if nm.distance_to(bn[j]) < 0.02 and absi(aa[k * 4] - ba[j * 4]) <= 1 and absi(aa[k * 4 + 1] - ba[j * 4 + 1]) <= 1:
									same = true
			if not there:
				if off == 0:
					print("  no mirror partner: %s vertex %s" % [mname, av[k]])
				off += 1
			elif not same:
				shade += 1
	return [off, shade]
