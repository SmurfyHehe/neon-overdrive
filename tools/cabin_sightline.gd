extends SceneTree

# Sight line of one car's own cabin (Roy: nothing in the cabin above 8 degrees
# below eye level within 20 degrees either side of straight ahead, except the
# wheel rim and the A-pillars). tests/view/cockpit_interior.gd measures the coupe with the
# coupe's eye; this boots NEON_CAR and uses that car's CABIN eye.
#
#   set NEON_CAR=p2_hothatch
#   <godot> --headless --audio-driver Dummy --path . -s res://tools/cabin_sightline.gd
#
# Prints, per yaw, the highest thing in the way (degrees below the eye, the
# mesh, the point in car space), then the worst of them. Exit code 1 when
# anything but the rim is above RULE_DEG.

const RULE_DEG := 8.0
const TIMEOUT_TICKS := 60 * 30

var tick := 0

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null or game.camera.frame == null:
		if tick > TIMEOUT_TICKS:
			printerr("cabin_sightline: the game never became ready")
			quit(1)
			return true
		return false
	if tick < 30:
		return false
	var p: PlayerCar = game.player
	var frame: CockpitFrame = game.camera.frame
	var kind := PlayerCar.chassis_kind()
	var eye: Vector3 = CabinSpec.for_kind(kind).eye
	var to_car := p.global_transform.affine_inverse()
	var tris := []   # [name, a, b, c, is_wheel]
	for m in frame.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.mesh is ArrayMesh or not mi.is_visible_in_tree() or _see_through(mi):
			continue
		var xf: Transform3D = to_car * mi.global_transform
		var mesh := mi.mesh as ArrayMesh
		for si in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var idx = mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				var ii: PackedInt32Array = idx
				for t in range(0, ii.size() - 2, 3):
					tris.append([String(mi.name), xf * verts[ii[t]], xf * verts[ii[t + 1]], xf * verts[ii[t + 2]]])
			else:
				for t in range(0, verts.size() - 2, 3):
					tris.append([String(mi.name), xf * verts[t], xf * verts[t + 1], xf * verts[t + 2]])
	# the A-pillars stand at the edge of the band on a narrow car; they are the
	# body, not the dash (cockpit_interior.gd uses 0.55 for the coupe)
	var pillar_x := minf(0.55, float((CabinSpec.for_kind(kind).a_pillar[1] as Vector3).x) - 0.05)
	var worst := 90.0
	var worst_txt := ""
	for yi in 21:
		var yaw_deg := -20.0 + 2.0 * yi
		var pitch := 0.0
		var found := ""
		var on_pillar := false
		while pitch < 30.0 and found == "":
			var dir := Vector3(0, 0, -1).rotated(Vector3.RIGHT, deg_to_rad(-pitch)).rotated(Vector3.UP, deg_to_rad(yaw_deg))
			var best := INF
			for tr in tris:
				var hit = Geometry3D.ray_intersects_triangle(eye, dir, tr[1], tr[2], tr[3])
				if hit == null:
					continue
				if tr[0] == "WheelBody":
					var local: Vector3 = frame.wheel.global_transform.affine_inverse() * (p.global_transform * hit)
					if Vector2(local.x, local.y).length() >= 0.13:
						continue   # the rim is allowed
				var d := eye.distance_to(hit)
				if d < best:
					best = d
					found = "%s at %s" % [tr[0], hit]
					on_pillar = absf(hit.x) > pillar_x
			if found == "":
				pitch += 0.5
		print("  yaw %+5.0f: %4.1f deg below the eye  %s%s" % [yaw_deg, pitch, found, "  (A-pillar, not counted)" if on_pillar else ""])
		if pitch < worst and not on_pillar:
			worst = pitch
			worst_txt = "yaw %+.0f, %s" % [yaw_deg, found]
	print("cabin_sightline %s: eye %s, highest thing in the way %.1f deg below the eye (%s), rule %.0f: %s" % [
		kind, eye, worst, worst_txt, RULE_DEG, "PASS" if worst >= RULE_DEG else "FAIL"])
	quit(0 if worst >= RULE_DEG else 1)
	return true

static func _see_through(mi: MeshInstance3D) -> bool:
	var m := mi.material_override
	if m == null and mi.mesh.get_surface_count() > 0:
		m = mi.mesh.surface_get_material(0)
	return m is StandardMaterial3D and (m as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
