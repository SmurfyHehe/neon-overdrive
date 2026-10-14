extends "res://tests/view/parked_cockpit.gd"

# Mirrors you can read (2026-10-14), headless and silent. The car in NEON_CAR
# (the selected one otherwise), parked in the cockpit view, straight ahead at
# the default FOV:
# - the rearview glass is wholly on screen, hanging between 5 and 19.5 degrees
#   above the eye, its outer edge no more than 45.5 to the side (CabinSpec.fit_rear_mirror);
#   at build 4 it was off the top of the screen on the pickup and off the right
#   edge on the drift coupe
# - the rearview glass still hangs behind the windscreen and above the eye line
# - the left door mirror is at least 40% on screen (the right one sits 55-63
#   degrees to the right in every car and is reached with a look round)
# - the mirror cameras: rear 14 degrees vertical (~45 wide), door 22 (~31
#   wide); every tier keeps the base render size, only high doubles it
# Exit code 1 on failure. Run (once per car):
#   NEON_CAR=p17_work_pickup Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/mirror_readable.gd

const UP_MIN := 5.0
const UP_MAX := CabinSpec.REAR_MIRROR_MAX_UP_DEG + 1.5   # the eye measured here carries the head's rest offset
const EDGE_MAX := 45.5   # the screen edge is 46.9 deg out at FOV 62 on 16:9
const LEFT_MIN_ON_SCREEN := 0.4   # the kei's and beater's sit 46 deg left, half over the edge

func _init() -> void:
	name_ = "mirror_readable"

func _step(n: int) -> bool:
	if n < SETTLE_TICKS * 2:
		return false
	var kind := PlayerCar.chassis_kind()
	var cab := CabinSpec.for_kind(kind)
	var mirrors: CockpitMirrors = cam.frame.mirrors
	_check(mirrors != null and mirrors.views.size() == 3, "three mirrors")
	var fov := float(cam.fov)
	# rearview
	var rear: Dictionary = mirrors.views[0]
	var r := _measure(rear.quad, fov)
	print("%s: rear mirror %.1f deg right, %.1f deg up, %.0f%% on screen, glass %.1f x %.1f deg" % [kind, -r.yaw, r.pitch, r.on_screen * 100.0, r.ang_w, r.ang_h])
	_check(r.on_screen > 0.99, "%s: the rearview glass is wholly on screen (%.0f%%, rect %s)" % [kind, r.on_screen * 100.0, r.rect])
	_check(r.pitch >= UP_MIN and r.pitch <= UP_MAX, "%s: the rearview hangs %.1f deg above the eye (want %.0f..%.1f)" % [kind, r.pitch, UP_MIN, UP_MAX])
	_check(absf(r.yaw) + r.ang_w * 0.5 <= EDGE_MAX, "%s: the rearview's outer edge is %.1f deg to the side (max %.1f)" % [kind, absf(r.yaw) + r.ang_w * 0.5, EDGE_MAX])
	# behind the windscreen, above the eye line
	var m: Vector3 = cab.rear_mirror
	var cowl: Vector2 = cab.cowl
	var header: Vector2 = cab.header
	var slope := (header.x - cowl.x) / maxf(header.y - cowl.y, 0.1)
	var screen_y := header.x + (m.z - header.y) * slope
	_check(m.y < screen_y, "%s: the glass (y %.3f) hangs under the windscreen (y %.3f at z %.2f)" % [kind, m.y, screen_y, m.z])
	_check(m.y >= float(cab.eye.y) + 0.05 - 0.001, "%s: the glass stays above the eye line" % kind)
	_check(m.z >= header.y - 0.6, "%s: the glass is near the windscreen top (z %.2f, header z %.2f)" % [kind, m.z, header.y])
	# left door mirror
	var l := _measure(mirrors.views[1].quad, fov)
	print("%s: left mirror %.1f deg left, %.1f deg, %.0f%% on screen" % [kind, l.yaw, l.pitch, l.on_screen * 100.0])
	_check(l.on_screen >= LEFT_MIN_ON_SCREEN, "%s: the left door mirror is at least half on screen (%.0f%%)" % [kind, l.on_screen * 100.0])
	# the cameras and the tiers
	_check(absf(rear.cam.fov - 14.0) < 0.01, "rear mirror camera 14 deg vertical (%.1f)" % rear.cam.fov)
	_check(absf(mirrors.views[1].cam.fov - 22.0) < 0.01, "door mirror camera 22 deg vertical (%.1f)" % mirrors.views[1].cam.fov)
	var q := FxSettings.mirror_quality
	FxSettings.set_mirror_quality(0)
	_check(FxSettings.mirror_scale() == 1.0 and FxSettings.mirror_period() == 3, "low quality keeps the render size and redraws every third frame")
	FxSettings.set_mirror_quality(1)
	_check(FxSettings.mirror_scale() == 1.0 and FxSettings.mirror_period() == 2, "medium quality: base size, every other frame")
	FxSettings.set_mirror_quality(2)
	_check(FxSettings.mirror_scale() == 2.0 and FxSettings.mirror_period() == 1, "high quality: double size, every frame")
	FxSettings.set_mirror_quality(q)
	return _end("")

## Angles of a glass quad from the camera (yaw + = left, pitch + = up, degrees),
## its angular size, and how much of its projected rectangle is on a 16:9 screen.
func _measure(glass: MeshInstance3D, fov: float) -> Dictionary:
	var inv := cam.global_transform.affine_inverse()
	var half: Vector2 = (glass.mesh as QuadMesh).size * 0.5
	var gx := glass.global_transform
	var c: Vector3 = inv * gx.origin
	var dist := c.length()
	var aspect := 16.0 / 9.0
	var t := tan(deg_to_rad(fov * 0.5))
	var x0 := INF; var x1 := -INF; var y0 := INF; var y1 := -INF
	for p2 in [Vector3(half.x, half.y, 0.0), Vector3(-half.x, half.y, 0.0), Vector3(half.x, -half.y, 0.0), Vector3(-half.x, -half.y, 0.0)]:
		var q: Vector3 = inv * (gx * p2)
		var sx := 99.0; var sy := 99.0
		if q.z < -0.01:
			sx = 0.5 + (q.x / -q.z) / (2.0 * t * aspect)
			sy = 0.5 - (q.y / -q.z) / (2.0 * t)
		x0 = minf(x0, sx); x1 = maxf(x1, sx); y0 = minf(y0, sy); y1 = maxf(y1, sy)
	var w := x1 - x0; var h := y1 - y0
	var vis := maxf(0.0, minf(x1, 1.0) - maxf(x0, 0.0)) * maxf(0.0, minf(y1, 1.0) - maxf(y0, 0.0))
	return {"yaw": rad_to_deg(atan2(-c.x, -c.z)), "pitch": rad_to_deg(atan2(c.y, sqrt(c.x * c.x + c.z * c.z))),
		"ang_w": 2.0 * rad_to_deg(atan(half.x / dist)), "ang_h": 2.0 * rad_to_deg(atan(half.y / dist)),
		"on_screen": 0.0 if w <= 0.0 or h <= 0.0 else vis / (w * h), "rect": [snappedf(x0, 0.01), snappedf(y0, 0.01), snappedf(x1, 0.01), snappedf(y1, 0.01)]}
