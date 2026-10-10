extends SceneTree

# Gauges must not block each other (Roy, 2026-10-09: "make sure the gauges
# dont block each other"). For every player car, with the bolt-on AFR/PSI pod
# fitted, from the driver's eye in the cockpit view:
# - no two gauge faces overlap on screen: the tach, the speedo, the pod's AFR
#   and PSI faces and the head unit screen, each as a disc seen from the eye
#   (angular centre and radius); any pair closer than the sum of their radii
#   fails
# - nothing sits between the eye and a gauge face: rays to the centre and to
#   eight points round the face (at 0.8 of the radius) must not hit any cabin
#   mesh clearly in front of the face (more than 12 mm nearer). The wheel rim
#   is allowed over the lower quarter of the cluster dials only (they are
#   designed to be read over and through the top of the rim), so the two
#   lowest rim points of the tach and the speedo are not checked.
# Boots each car in turn (NEON_CAR), like tests/fleet/interior_fit.gd; one car
# with NEON_LAYOUT_CAR=<kind>. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/gauge_layout.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RATE := 60
const BOOST := 0.7
const IN_FRONT := 0.012

var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	Engine.physics_ticks_per_second = RATE
	OS.set_environment("NEON_TRAFFIC", "0")
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_LAYOUT_CAR")
	for k in PlayerCars.KINDS:
		if only != "" and String(k.id) != only:
			continue
		await _layout(String(k.id))
	OS.set_environment("NEON_CAR", "")
	for f in failures:
		printerr("FAIL: ", f)
	print("gauge_layout: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _layout(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	if p == null or cam == null or cam.frame == null:
		failures.append("%s: the game should boot with a cockpit frame" % kind)
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.set_view(ChaseCamera.View.COCKPIT)
	if p.turbo_boost_max <= 0.0:
		p.turbo_boost_max = BOOST
	for i in 30:
		await physics_frame
	var frame: CockpitFrame = cam.frame
	var pod: GaugePod = frame.pod
	if pod == null:
		failures.append("%s: no pod after a boost setup" % kind)
	# gauges in car space: {name, centre, radius}
	var to_car := p.global_transform.affine_inverse()
	var gauges := []
	var frame_n: Vector3 = (to_car.basis * frame.global_basis * Vector3.BACK).normalized()
	for dx in [-0.085, 0.085]:
		gauges.append({"name": "tach" if dx < 0.0 else "speedo", "centre": to_car * frame.to_global(Vector3(CockpitFrame.SEAT_X + dx, CockpitFrame.CLUSTER_Y, CockpitFrame.CLUSTER_Z)), "r": CockpitFrame.DIAL_R, "cluster": true, "normal": frame_n})
	if pod != null:
		var cs := pod.gauge_centres()
		var pod_n: Vector3 = (to_car.basis * pod.global_basis * Vector3.BACK).normalized()
		gauges.append({"name": "AFR", "centre": to_car * pod.to_global(cs[0]), "r": GaugePod.GAUGE_R, "cluster": false, "normal": pod_n})
		gauges.append({"name": "PSI", "centre": to_car * pod.to_global(cs[1]), "r": GaugePod.GAUGE_R, "cluster": false, "normal": pod_n})
	var hu_n: Vector3 = (to_car.basis * frame.head_unit.global_basis * Vector3.BACK).normalized()
	gauges.append({"name": "radio", "centre": to_car * frame.head_unit.to_global(Vector3.ZERO), "r": HeadUnit.SCREEN_H * 0.5, "cluster": false, "normal": hu_n})
	var eye: Vector3 = cam.eye
	# 1. no two faces overlap on screen
	for i in gauges.size():
		for j in range(i + 1, gauges.size()):
			var a: Dictionary = gauges[i]
			var b: Dictionary = gauges[j]
			var da: Vector3 = (a.centre - eye)
			var db: Vector3 = (b.centre - eye)
			var apart := rad_to_deg(da.angle_to(db))
			var ra := rad_to_deg(atan(a.r / da.length()))
			var rb := rad_to_deg(atan(b.r / db.length()))
			if apart < ra + rb:
				failures.append("%s: %s and %s overlap on screen (%.1f deg apart, radii %.1f + %.1f)" % [kind, a.name, b.name, apart, ra, rb])
	# 2. nothing in front of a face
	var meshes := _cabin_meshes(frame, to_car)
	for g in gauges:
		var centre: Vector3 = g.centre
		# a basis in the face's own plane (u across, v up the face)
		var n: Vector3 = g.normal
		var u := Vector3.UP.cross(n).normalized()
		var v := n.cross(u).normalized()
		var samples: Array[Vector3] = [centre]
		for k in 8:
			var a := TAU * float(k) / 8.0
			var off: Vector3 = (u * cos(a) + v * sin(a)) * (float(g.r) * 0.8)
			if g.cluster and sin(a) < -0.6:
				continue   # the lower quarter of a cluster dial sits behind the rim by design
			samples.append(centre + off)
		var blocked := 0
		var by := ""
		for s in samples:
			var dir := (s - eye).normalized()
			var hit := _first_hit(meshes, eye, dir)
			if hit.is_empty():
				continue
			var d: float = eye.distance_to(hit.point)
			if d < eye.distance_to(s) - IN_FRONT:
				blocked += 1
				by = "%s at %.2f m, %.3f in front of %s" % [hit.name, d, eye.distance_to(s) - d, s]
		if blocked > 0:
			failures.append("%s: %s is blocked at %d of %d points (%s)" % [kind, g.name, blocked, samples.size(), by])
		print("%s: %s %d/%d points clear" % [kind, g.name, samples.size() - blocked, samples.size()])
	game.queue_free()
	await process_frame
	await process_frame

## Every opaque cabin mesh in car space, with a bounding box; the driver's
## body and the glass panes are left out (the driver is hidden in the cockpit,
## glass is see-through).
func _cabin_meshes(frame: CockpitFrame, to_car: Transform3D) -> Array:
	var meshes := []
	for m in frame.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _is_driver(mi) or _see_through(mi):
			continue
		var xf: Transform3D = to_car * mi.global_transform
		var tris := PackedVector3Array()
		for vtx in mi.mesh.get_faces():
			tris.append(xf * vtx)
		if tris.is_empty():
			continue
		var lo := tris[0]
		var hi := tris[0]
		for vtx in tris:
			lo = lo.min(vtx)
			hi = hi.max(vtx)
		meshes.append({"name": _path_name(mi, frame), "tris": tris, "aabb": AABB(lo, hi - lo).grow(0.001)})
	return meshes

static func _is_driver(n: Node) -> bool:
	var q := n
	while q != null:
		if q is DriverModel:
			return true
		q = q.get_parent()
	return false

static func _see_through(mi: MeshInstance3D) -> bool:
	var mat := mi.material_override
	if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		mat = mi.mesh.surface_get_material(0)
	return mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED

static func _path_name(n: Node, top: Node) -> String:
	var parts: Array[String] = []
	var q := n
	while q != null and q != top:
		parts.push_front(q.name)
		q = q.get_parent()
	return "/".join(parts)

static func _first_hit(meshes: Array, from: Vector3, dir: Vector3) -> Dictionary:
	var best := INF
	var best_hit := {}
	for m in meshes:
		var box: AABB = m.aabb
		if not box.intersects_ray(from, dir):
			continue
		var tris: PackedVector3Array = m.tris
		var t := 0
		while t + 2 < tris.size():
			var hit = Geometry3D.ray_intersects_triangle(from, dir, tris[t], tris[t + 1], tris[t + 2])
			t += 3
			if hit != null:
				var d: float = from.distance_squared_to(hit)
				if d < best:
					best = d
					best_hit = {"name": m.name, "point": hit}
	return best_hit
