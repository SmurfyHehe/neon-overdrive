extends SceneTree

# Stage B1 design-sheet checks, run in Godot on the exact proxy shapes the
# sheets show (docs/design/fleet/proxies.json) plus fleet.json:
#   fleet     7 player (P0 beater starter added 2026-10-09, #274), 3 traffic, 3 police cars
#   budget    triangles per build within the class budget (player 10k,
#             police 6k, traffic 4k); draw calls per car <= 7 (B1 plan)
#   stickers  exactly 4 slots per build (door, hood, windshield sun strip, rear). Every placement sits on the body (a
#             ray along -normal meets it within 3 cm). No part hovers over it
#             (a wing, spoiler or rack more than 8 cm above); a flush part
#             like a hood scoop is fine, the sticker wraps over it. From every
#             orbit camera (24 yaw x 4 pitch, the 360 garage view) at least
#             one slot faces the camera and is unblocked. The sun strip is
#             what covers the 3 ground-level views of the nose (yaw 165-195,
#             pitch 2), where only the front fascia faces the camera. The
#             rear slot sits on the upright tail panel or tailgate (normal
#             no more than 0.2 up) and must be seen from the chase cam; its
#             readable size there (area x facing) is reported.
#   exhaust   every build and every exhaust option has at least one tip (gas
#             only). Rear tips sit behind the rear axle, side exits between
#             the axles. The tip geometry is there (a ray back into the tip
#             meets it) and 0.6 m in front of it is clear for B4's flames.
#   classes   traffic arch gaps are bigger than every player car's; every
#             police build carries a police tell (light bar, push bar,
#             spotlight or antennas)
#   palette   no magenta or cyan in any colour (same bands as B1's
#             palette_check.py: hue 165-200 or 285-335, saturation > 0.25,
#             value > 0.2). Police blue #2E4FD8 is approved (Roy, 2026-10-05).
# Writes design_check.json to user://fleet_audit/ (so a test run never dirties
# the repo); -- --out=res://docs/design/fleet/audit refreshes the committed
# snapshot.
#
# Run (headless is fine):
#   godot --headless --path . -s res://tests/fleet_design_check.gd

const Proxies := preload("res://tests/fleet_proxies.gd")
const FLEET_JSON := "res://docs/design/fleet/fleet.json"
const OUT_DIR := "user://fleet_audit"
const BUDGET := {"player": 10000, "cop": 6000, "npc": 4000}
const MAX_DRAW_CALLS := 7
const ORBIT_R := 9.5
const ORBIT_TARGET := Vector3(0, 0.6, 0)
const PITCHES := [2.0, 15.0, 35.0, 60.0]
const YAW_STEP := 15.0
const CHASE_EYE := Vector3(0, 1.85, 5.2)       # stage A chase cam, relative to the car
const CHASE_AIM := Vector3(0, 0.95, -12.0)
const CHASE_VFOV := 58.0
const CHASE_ASPECT := 16.0 / 9.0
const POLICE_TELLS := ["lightbar", "pushbar", "spotlight", "antennas"]
const HOVER := 0.08            # a part this far above a slot hides it

var fails := 0
var report := {"cars": {}, "fails": []}

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	report.fails.append(msg)
	fails += 1

func _initialize() -> void:
	var data := Proxies.load_data()
	var fleet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FLEET_JSON))
	if data.is_empty() or fleet.is_empty():
		_fail("could not load proxies.json or fleet.json")
		quit(1)
		return
	var fleet_by_id := {}
	for c in fleet.cars:
		fleet_by_id[c.id] = c

	# ---- fleet
	var roles := {"player": 0, "npc": 0, "cop": 0}
	for car in data.cars:
		roles[car.role] += 1
	print("fleet: %d player, %d traffic, %d police" % [roles.player, roles.npc, roles.cop])
	if roles.player != 7 or roles.npc != 3 or roles.cop != 3:
		_fail("fleet is %s, want 7 player / 3 traffic / 3 police" % roles)

	# ---- per car
	var orbit := _orbit_cameras()
	var max_player_gap := 0.0
	var min_npc_gap := 1.0
	for car in data.cars:
		var f: Dictionary = fleet_by_id[car.id]
		var entry := {"builds": {}}
		report.cars[car.id] = entry
		var gap: float = f.wheel.arch_gap
		# The P0 beater's sagging arches are its look (worn T0 starter, #274),
		# so it does not set the fitted-player bound traffic must clear.
		if car.role == "player" and car.id != "p0_beater":
			max_player_gap = maxf(max_player_gap, gap)
		elif car.role == "npc":
			min_npc_gap = minf(min_npc_gap, gap)
		for b in car.builds:
			var r: Dictionary = await _check_build(data, car, b, f, orbit)
			entry.builds[b.name] = r
		await _check_exhaust_options(data, car, f, entry)
		var line := "%-15s" % car.id
		for bn in entry.builds:
			var r: Dictionary = entry.builds[bn]
			line += "  %s %d tris/%d dc, slots seen %d/%d" % [bn, r.tris, r.draw_calls, r.orbit_views_with_slot, orbit.size()]
		print(line)

	# ---- classes
	var tells := {}
	for car in data.cars:
		if car.role != "cop":
			continue
		for b in car.builds:
			var found := []
			for t in POLICE_TELLS:
				if t in b.part_types:
					found.append(t)
			tells["%s/%s" % [car.id, b.name]] = found
			if found.is_empty():
				_fail("%s/%s carries no police tell (light bar, push bar, spotlight or antennas)" % [car.id, b.name])
	report["police_tells"] = tells
	print("police tells: %s" % tells)
	report["arch_gap"] = {"max_player": max_player_gap, "min_traffic": min_npc_gap}
	if min_npc_gap <= max_player_gap:
		_fail("traffic arch gap %.3f is not bigger than the player cars' %.3f" % [min_npc_gap, max_player_gap])
	print("arch gaps: player max %.3f m < traffic min %.3f m" % [max_player_gap, min_npc_gap])

	# ---- palette
	var colours := _all_colours(data, fleet)
	var flagged := []
	for name in colours:
		var c := Color(colours[name])
		var h := c.h * 360.0
		if c.s > 0.25 and c.v > 0.2 and ((h >= 165.0 and h <= 200.0) or (h >= 285.0 and h <= 335.0)):
			flagged.append("%s %s hue %d" % [name, colours[name], roundi(h)])
	report["palette"] = {"checked": colours.size(), "flagged": flagged}
	print("palette: %d colours, magenta/cyan flagged: %s" % [colours.size(), flagged if not flagged.is_empty() else "none"])
	if not flagged.is_empty():
		_fail("magenta/cyan colours: %s" % [flagged])

	var out_dir := OUT_DIR
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var out := FileAccess.open(out_dir.path_join("design_check.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify(report, " ", false))
	out.close()
	print("wrote ", ProjectSettings.globalize_path(out_dir.path_join("design_check.json")))
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ one build
func _check_build(data: Dictionary, car: Dictionary, b: Dictionary, f: Dictionary, orbit: Array) -> Dictionary:
	var tag := "%s/%s" % [car.id, b.name]
	var r := {}
	# budget: count what Godot actually built
	var node := Proxies.build_car(data, car, b.name, "full")
	var tris := 0
	var dc := 0
	for child in node.get_children():
		var mesh: ArrayMesh = (child as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_array_len(s) / 3
			dc += 1
	node.free()
	r["tris"] = tris
	r["draw_calls"] = dc
	r["budget"] = BUDGET[car.role]
	if tris != int(b.tris_total):
		_fail("%s: Godot mesh has %d triangles, proxies.json says %d" % [tag, tris, b.tris_total])
	if tris > BUDGET[car.role]:
		_fail("%s: %d triangles over the %s budget %d" % [tag, tris, car.role, BUDGET[car.role]])
	if dc > MAX_DRAW_CALLS:
		_fail("%s: %d draw calls, plan is <= %d" % [tag, dc, MAX_DRAW_CALLS])

	# collision copy of the build for the ray checks
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(Proxies.build_faces(b))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state

	# sticker slots
	if b.slots.size() != 4:
		_fail("%s: %d sticker slots, want 4" % [tag, b.slots.size()])
	var placements := []
	var slot_report := {}
	for s in b.slots:
		var want := 2 if s.mirror else 1
		var got := 0
		for p in s.placements:
			if p != null:
				got += 1
		if got != want:
			_fail("%s: slot %s has %d placements, want %d" % [tag, s.id, got, want])
		var worst_gap := 0.0
		for p in s.placements:
			if p == null:
				continue
			var c := Vector3(p.center[0], p.center[1], p.center[2])
			var n := Vector3(p.normal[0], p.normal[1], p.normal[2])
			placements.append([s.id, c, n])
			if s.id == "rear" and n.y > 0.2:
				_fail("%s: rear slot faces %.2f up, it must sit on the upright tail panel" % [tag, n.y])
			# on the body: from 0.5 m out, the first thing hit along -n is the
			# body right under the slot (slots float 12 mm up; allow 3 cm)
			var hit := _ray(space, c + n * 0.5, c - n * 0.2)
			if hit.is_empty():
				_fail("%s: slot %s at %s is not over the body" % [tag, s.id, c])
				continue
			var d: float = (hit.position as Vector3).distance_to(c)
			var above: float = (hit.position - c).dot(n)
			if above > HOVER:
				_fail("%s: slot %s is hidden under a part %.2f m above it" % [tag, s.id, above])
			elif above > 0.03:
				pass  # a flush part (scoop, vent) on the panel: the sticker wraps over it
			else:
				worst_gap = maxf(worst_gap, d)
				if d > 0.03:
					_fail("%s: slot %s sits %.3f m off the body" % [tag, s.id, d])
		slot_report[s.id] = {"placements": got, "max_gap_m": snappedf(worst_gap, 0.001),
			"area_m2": snappedf(float(s.placements[0].area) if s.placements[0] != null else 0.0, 0.001)}
	r["slots"] = slot_report

	# visibility from the 360 orbit and the chase cam
	var seen := 0
	var blind := []
	var per_slot := {}
	for cam in orbit:
		var any := false
		for pl in placements:
			if _visible(space, cam.eye, pl[1], pl[2]):
				any = true
				per_slot[pl[0]] = int(per_slot.get(pl[0], 0)) + 1
		if any:
			seen += 1
		else:
			blind.append("yaw %d pitch %d" % [cam.yaw, cam.pitch])
	r["orbit_views_with_slot"] = seen
	r["orbit_views"] = orbit.size()
	r["orbit_blind_views"] = blind
	r["slot_view_counts"] = per_slot
	if not blind.is_empty():
		_fail("%s: no sticker slot visible from %d orbit views: %s" % [tag, blind.size(), blind])
	# chase cam: which slots it sees, and how big the rear one reads there
	var chase := []
	var rear_read := 0.0
	for s in b.slots:
		for p in s.placements:
			if p == null:
				continue
			var c := Vector3(p.center[0], p.center[1], p.center[2])
			var n := Vector3(p.normal[0], p.normal[1], p.normal[2])
			if _visible(space, CHASE_EYE, c, n) and _in_chase_frame(c):
				chase.append(s.id)
				if s.id == "rear":
					rear_read = float(p.area) * n.dot((CHASE_EYE - c).normalized())
	r["chase_cam_slots"] = chase
	r["chase_rear_readable_m2"] = snappedf(rear_read, 0.001)
	if not ("rear" in chase):
		_fail("%s: the rear sticker slot is not visible from the chase cam" % tag)

	# exhaust tips of this build: present, placed, clear
	r["tips"] = _check_tips(space, tag, b.tips, f)
	body.queue_free()
	await physics_frame
	return r

func _check_exhaust_options(data: Dictionary, car: Dictionary, f: Dictionary, entry: Dictionary) -> void:
	# fleet.json lists the tips for every exhaust option on the stock body
	var b := Proxies.find_build(car, "stock")
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(Proxies.build_faces(b))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var opts := {}
	for opt in f.exhaust_tips:
		var tips: Array = f.exhaust_tips[opt]
		if tips.is_empty():
			_fail("%s exhaust option %s has no tips" % [car.id, opt])
		# a non-stock option's tips are not in the stock body's geometry, so
		# only the stock option can check the tip is really there
		opts[opt] = _check_tips(space, "%s exhaust:%s" % [car.id, opt], tips, f, opt == "stock")
	entry["exhaust_options"] = opts
	body.queue_free()
	await physics_frame

func _check_tips(space: PhysicsDirectSpaceState3D, tag: String, tips: Array, f: Dictionary, check_attached := true) -> Dictionary:
	var rear_axle_z: float = f.dims.wheelbase / 2.0
	var out := {"count": tips.size(), "clear_tips": 0}
	if tips.is_empty():
		_fail("%s: no exhaust tips (every car is gas)" % tag)
	for t in tips:
		var p := Vector3(t.pos[0], t.pos[1], t.pos[2])
		var dir := Vector3(t.dir[0], t.dir[1], t.dir[2]).normalized()
		if dir.z > 0.5 and p.z < rear_axle_z:
			_fail("%s: rear tip at z %.2f is ahead of the rear axle (%.2f)" % [tag, p.z, rear_axle_z])
		if absf(dir.x) > 0.5 and absf(p.z) > rear_axle_z:
			_fail("%s: side tip at z %.2f is outside the wheelbase" % [tag, p.z])
		if check_attached:
			var back := _ray(space, p + dir * 0.3, p - dir * 0.1)
			if back.is_empty() or (back.position as Vector3).distance_to(p) > 0.06:
				_fail("%s: no tip geometry at %s" % [tag, p])
		var ahead := _ray(space, p + dir * 0.02, p + dir * 0.62)
		if ahead.is_empty():
			out["clear_tips"] += 1
		else:
			_fail("%s: tip at %s is blocked %.2f m out (flames need 0.6 m)" % [tag, p, (ahead.position as Vector3).distance_to(p)])
	return out

# ------------------------------------------------------------------ helpers
func _orbit_cameras() -> Array:
	var cams := []
	for pitch in PITCHES:
		var yaw := 0.0
		while yaw < 360.0 - 0.01:
			var a := deg_to_rad(yaw)
			var e := deg_to_rad(pitch)
			var eye := ORBIT_TARGET + ORBIT_R * Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a))
			cams.append({"eye": eye, "yaw": int(yaw), "pitch": int(pitch)})
			yaw += YAW_STEP
	return cams

func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.hit_back_faces = true
	return space.intersect_ray(q)

# A slot placement is visible when it faces the camera (within 78 degrees)
# and the first thing on the line of sight is the slot itself.
func _visible(space: PhysicsDirectSpaceState3D, eye: Vector3, c: Vector3, n: Vector3) -> bool:
	var to_cam := (eye - c).normalized()
	if n.dot(to_cam) < 0.2:
		return false
	var hit := _ray(space, eye, c + n * 0.03)
	return hit.is_empty() or (hit.position as Vector3).distance_to(c) < 0.08

func _in_chase_frame(p: Vector3) -> bool:
	var fwd := (CHASE_AIM - CHASE_EYE).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd)
	var d := p - CHASE_EYE
	var z := d.dot(fwd)
	if z <= 0.1:
		return false
	var ty := tan(deg_to_rad(CHASE_VFOV) / 2.0)
	return absf(d.dot(up) / z) <= ty and absf(d.dot(right) / z) <= ty * CHASE_ASPECT

func _all_colours(data: Dictionary, fleet: Dictionary) -> Dictionary:
	var seen := {}
	for k in data.mats:
		if data.mats[k] != null:
			seen["material " + k] = data.mats[k]
	for car in fleet.cars:
		var p: Dictionary = car.paint
		if p.has("hero"):
			seen["%s hero" % car.id] = p.hero[1]
			for a in p.alts:
				seen["%s %s" % [car.id, a[0]]] = a[1]
			for k in ["trim", "rim"]:
				if p.has(k):
					seen["%s %s" % [car.id, k]] = p[k]
		if p.has("livery"):
			for k in p.livery:
				seen["%s livery %s" % [car.id, k]] = p.livery[k]
	for t in fleet.traffic_paints:
		seen["traffic " + t.name] = t.hex
	for k in fleet.palette:
		seen["palette " + k] = fleet.palette[k]
	return seen
