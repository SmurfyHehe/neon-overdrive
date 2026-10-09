class_name ViewGuard

# "Could anyone see this?" for the things that must never pop in or out: traffic
# cars placed or recycled (TrafficManager), road chunks rebuilt behind the
# player (Game). Roy, 2026-10-09: seeing a car spawn breaks the realism.
#
# A thing is seen if some live camera can see any part of its box:
#   - the viewport's current camera (chase, cockpit, look-back, glance, photo);
#   - every Camera3D in the group GROUP: the cockpit mirrors while they render
#     (CockpitMirrors), and anything else that draws the world (a future
#     free-look rig joins the group and is covered with no change here).
# and nothing solid is in the way: a ray from the camera to each of the box's
# corners that hits the world (hill crest, building, wall) hides that corner.
#
# Conservative on purpose: the frustum test is widened by MARGIN_DEG, so a
# camera that turns between the physics tick and the draw still has not seen
# the event; only "unseen" is ever claimed on evidence, "seen" is the default.

## Cameras that draw the world besides the viewport's current one.
const GROUP := "view_cameras"
## World geometry for the line-of-sight rays: layer 1 (road, ground, buildings,
## walls). Cars are on their own layer and do not block.
const WORLD_MASK := 1
## The frustum is widened by this much on every side.
const MARGIN_DEG := 8.0
## Half-size of a car's box (x across, y up, z along), metres, and its
## height of the box's centre above the road.
const CAR_HALF := Vector3(1.0, 0.75, 2.4)
const CAR_LIFT := 0.9

## The box's corners and top-centre in world space, for a car whose chassis
## sits at road-space `u` (x across, y above the road, z along).
static func car_points(u: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				pts.append(RoadFrame.roll(Vector3(u.x + sx * CAR_HALF.x, u.y + CAR_LIFT + sy * CAR_HALF.y, u.z + sz * CAR_HALF.z)))
	pts.append(RoadFrame.roll(Vector3(u.x, u.y + CAR_LIFT + CAR_HALF.y, u.z)))
	return pts

## Every camera that is drawing the world right now.
static func live_cameras(tree: SceneTree) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	var main := tree.root.get_viewport().get_camera_3d()
	if main != null:
		out.append(main)
	for n in tree.get_nodes_in_group(GROUP):
		var c := n as Camera3D
		if c != null and c.is_inside_tree() and c != main:
			out.append(c)
	return out

## What in_cone needs of a camera, computed once per query: [inverse transform,
## tan(half fov) across and up (widened by MARGIN_DEG), near, far].
static func cone_of(cam: Camera3D) -> Array:
	var size := cam.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var half_fov := deg_to_rad(cam.fov) * 0.5
	var tan_v: float
	var tan_h: float
	if cam.keep_aspect == Camera3D.KEEP_HEIGHT:
		tan_v = tan(half_fov)
		tan_h = tan_v * aspect
	else:
		tan_h = tan(half_fov)
		tan_v = tan_h / aspect
	var m := deg_to_rad(MARGIN_DEG)
	tan_h = tan(minf(atan(tan_h) + m, PI * 0.49))
	tan_v = tan(minf(atan(tan_v) + m, PI * 0.49))
	return [cam.global_transform.affine_inverse(), tan_h, tan_v, cam.near, cam.far]

## Whether `p` is inside a camera's view (cone_of), near plane to far plane,
## widened by MARGIN_DEG (the far plane is not widened: that is a distance, not
## a turn).
static func in_cone(cone: Array, p: Vector3) -> bool:
	var l: Vector3 = (cone[0] as Transform3D) * p
	var d := -l.z
	if d <= cone[3] or d > cone[4]:
		return false
	return absf(l.x) <= d * cone[1] and absf(l.y) <= d * cone[2]

## Whether the world blocks the sight line from `from` to `to`.
static func blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return not space.intersect_ray(q).is_empty()

## True if any live camera can see any part of a car at road-space `u`.
## `space` is the physics space for the occlusion rays (null = skip them, which
## only makes the answer more cautious).
static var prof_usec := 0
static var prof_calls := 0
static func car_seen(tree: SceneTree, space: PhysicsDirectSpaceState3D, u: Vector3) -> bool:
	var t0 := Time.get_ticks_usec()
	var r := _car_seen(tree, space, u)
	prof_usec += Time.get_ticks_usec() - t0
	prof_calls += 1
	return r

static func _car_seen(tree: SceneTree, space: PhysicsDirectSpaceState3D, u: Vector3) -> bool:
	var cams := live_cameras(tree)
	if cams.is_empty():
		return true
	var pts := car_points(u)
	for cam in cams:
		var cone := cone_of(cam)
		var eye := cam.global_position
		for p in pts:
			if not in_cone(cone, p):
				continue
			if space == null or not blocked(space, eye, p):
				return true
	return false

## A road chunk's footprint in its own frame (x across, y up, z along = -z):
## sampled densely enough that no camera cone, mirrors included, slips between
## the points, and tall enough for the buildings.
const CHUNK_X := [-40.0, -22.0, -8.0, 0.0, 8.0, 22.0, 40.0]
const CHUNK_Y := [-2.0, 6.0, 18.0, 40.0]

## True if any live camera can see any part of a road chunk (its road, kerbs
## and buildings). Frustum only, no rays: a chunk is big and a crest rarely
## hides all of it.
static func chunk_seen(tree: SceneTree, root: Node3D) -> bool:
	var cams := live_cameras(tree)
	if cams.is_empty():
		return true
	var xf := root.global_transform
	var steps := int(RoadChunkBuilder.CHUNK_LEN / 6.0) + 1
	for cam in cams:
		if cam.global_position.distance_to(xf.origin) < 1.0:
			return true
		var cone := cone_of(cam)
		for iz in steps + 1:
			var z := -RoadChunkBuilder.CHUNK_LEN * float(iz) / float(steps)
			for x in CHUNK_X:
				for y in CHUNK_Y:
					if in_cone(cone, xf * Vector3(x, y, z)):
						return true
	return false
