extends SceneTree

# Cabin clearance (W1, 2026-10-11): every steering wheel shape on every
# drivable car, at rest and at full lock both ways, against the cabin parts
# around it. Headless and silent; the game boots once per car (NEON_CAR) and
# the wheel is rebuilt per shape without reloading the scene.
#
# Per car x shape:
#  1. Rim clearance. The rim centreline every 5 degrees, the spokes along
#     their length, the hub and pad, and the race wheel's paddles, each as a
#     sphere of its own radius, against the nearest triangle of the dash, the
#     cluster, the head unit, the door card, the lever (moved through every
#     gear), the handbrake, the pedals, and the driver's thighs and shins (the
#     knees). At least MIN_CLEAR (2 cm). The column and the hands are skipped
#     (they touch by design).
#  2. Dials readable: 40 rays from the eye to points on the tach needle's
#     sweep (the gear digit sits in the tach face); at most 25% may hit the
#     wheel first, wheel at rest.
#  3. Sight line: the rim top (grip included) at least
#     CockpitFrame.WHEEL_TOP_MIN_DEG below the eye.
#  4. Hands: at rest each hand is within 3 cm of rim_point(0) / rim_point(180);
#     at full lock (the hands slide, so rim_point(0) is not where they are)
#     within 3 cm of the rim's centreline.
#  5. Bobble and trinket at their largest tilt / swing stay 2 cm from the
#     wheel, the rear-view mirror, the windscreen glass and the A-pillars.
#  6. Cost: a plain wheel is at most 2 meshes and 1,400 triangles.
# Plus per car the largest radius (0.5 cm steps, a round three-spoke) and the
# largest dish (1 cm steps, the deep dish) that pass 1-3, printed so the
# WheelStyles.FIT table can be checked against them.
#
# NEON_CLEARANCE_CAR=<kind> runs one car. Exit code 1 on any failure.
# Run: <godot> --headless --audio-driver Dummy --path . -s res://tests/view/cabin_clearance.gd
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const WheelStyles := preload("res://scripts/view/wheel_styles.gd")

const RATE := 60
const MIN_CLEAR := 0.02
## A cabin part (dash, bezel, lever) only has to stay un-touched: the rim top
## sits about 1 cm under the binnacle hood by the cabin's own numbers.
const CABIN_CONTACT := 0.003
const DIAL_MAX := 0.25
const HAND_TOL := 0.03
const NEAR := 0.40          # a triangle further than this from the hub is never a wheel neighbour
const PLAIN_MAX_MESHES := 2
const PLAIN_MAX_TRIS := 1400
const DIAL_RAYS_ANGLES := 10
const DIAL_RAYS_RADII := [0.3, 0.55, 0.8, 1.0]

## "kind/shape" -> why this pair is exempt (a cabin problem found by this
## test, not to be fixed in the wheel step). Empty unless a stock car fails.
const EXEMPT := {}

## Cabin nodes that are not obstacles (by first path component).
const SKIP := ["WheelMount", "Mirrors", "WindowGlass", "Bobble", "Trinket", "Driver", "Lever", "Backlight", "Shelf"]
const LEG_PARTS := ["Driver/ThighL", "Driver/ThighR", "Driver/ShinL", "Driver/ShinR"]

# ---------- triangle soup ----------

class Soup:
	var v := PackedVector3Array()
	var names := PackedStringArray()
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()

	func add_tri(a: Vector3, b: Vector3, c: Vector3, label: String) -> void:
		v.append(a)
		v.append(b)
		v.append(c)
		names.append(label)
		lo.append(Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z))))
		hi.append(Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z))))

	func size() -> int:
		return names.size()

	## [distance, label] of the nearest triangle closer than `limit`, or [limit, ""].
	func nearest(p: Vector3, limit: float) -> Array:
		var best := limit
		var who := ""
		for i in names.size():
			var l := lo[i]
			var h := hi[i]
			if p.x < l.x - best or p.x > h.x + best or p.y < l.y - best or p.y > h.y + best or p.z < l.z - best or p.z > h.z + best:
				continue
			var q := closest_on_tri(p, v[i * 3], v[i * 3 + 1], v[i * 3 + 2])
			var d := p.distance_to(q)
			if d < best:
				best = d
				who = names[i]
		return [best, who]

	## Closest point of triangle abc to p (Ericson, Real-Time Collision Detection).
	static func closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		var ab := b - a
		var ac := c - a
		var ap := p - a
		var d1 := ab.dot(ap)
		var d2 := ac.dot(ap)
		if d1 <= 0.0 and d2 <= 0.0:
			return a
		var bp := p - b
		var d3 := ab.dot(bp)
		var d4 := ac.dot(bp)
		if d3 >= 0.0 and d4 <= d3:
			return b
		var vc := d1 * d4 - d3 * d2
		if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
			return a + ab * (d1 / (d1 - d3))
		var cp := p - c
		var d5 := ab.dot(cp)
		var d6 := ac.dot(cp)
		if d6 >= 0.0 and d5 <= d6:
			return c
		var vb := d5 * d2 - d1 * d6
		if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
			return a + ac * (d2 / (d2 - d6))
		var va := d3 * d6 - d5 * d4
		if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
			return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
		var denom := 1.0 / (va + vb + vc)
		return a + ab * (vb * denom) + ac * (vc * denom)

var fails := 0
var failed_pairs: Array[String] = []
var game: Node
var logger := Harness.ErrorCounter.new()
var only := OS.get_environment("NEON_CLEARANCE_CAR")
var lock := CockpitFrame.WHEEL_LOCK_RAD
var table: Array[String] = []
## Today's race wheel on the car being tested: {clear, dial, top}.
var base := {"clear": 9.0, "dial": 0.0, "top": 90.0}
## Problems found in the cabin or the driver with the stock wheel (not failures).
var found: Array[String] = []

## No pick may be closer than the 2 cm, or than today's wheel is on this car.
func _need_clear() -> float:
	return MIN_CLEAR

func _max_dial() -> float:
	return maxf(DIAL_MAX, float(base.dial) + 0.001)

func _min_top() -> float:
	return minf(CockpitFrame.WHEEL_TOP_MIN_DEG, float(base.top) - 0.05)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_run.call_deferred()

## The picks save per car, reload, and an unknown id reads as unpicked; the
## override string sets them for the car being driven.
func _saves() -> void:
	var cfg := "user://cabin_clearance_test.cfg"
	AudioSettings.path = cfg
	DirAccess.remove_absolute(cfg)
	CabinMods.wheel_shapes.clear()
	CabinMods.wheel_grips.clear()
	CabinMods.wheel_stitches.clear()
	CabinMods.set_wheel_shape("p1_coupe", "deepdish")
	CabinMods.set_wheel_grip("p1_coupe", "tan_leather")
	CabinMods.set_wheel_stitch("p1_coupe", "amber")
	CabinMods.set_wheel_shape("p4_kei", "wood")
	_check(CabinMods.save_settings(), "the picks should save")
	CabinMods.wheel_shapes.clear()
	CabinMods.wheel_grips.clear()
	CabinMods.wheel_stitches.clear()
	CabinMods.load_settings()
	_check(CabinMods.wheel_shape_for("p1_coupe") == "deepdish" and CabinMods.wheel_grip_for("p1_coupe") == "tan_leather" and CabinMods.wheel_stitch_for("p1_coupe") == "amber", "the coupe's picks should reload")
	_check(CabinMods.wheel_shape_for("p4_kei") == "wood" and CabinMods.wheel_grip_for("p4_kei") == "", "the kei's picks are its own")
	_check(CabinMods.wheel_shape_for("p2_hothatch") == "" and CabinMods.wheel_signature("p2_hothatch") == "||", "a car with no picks is unpicked")
	CabinMods.set_wheel_shape("p1_coupe", "no_such_wheel")
	_check(CabinMods.wheel_shape_for("p1_coupe") == "", "an unknown shape reads as unpicked")
	OS.set_environment("NEON_CAR", "p3_tuner")
	CabinMods.apply_override("wheel=banjo4;grip=wood;stitch=none")
	_check(CabinMods.wheel_picks("p3_tuner") == {"shape": "banjo4", "grip": "wood", "stitch": "none"}, "the override sets the driven car's picks, got %s" % [CabinMods.wheel_picks("p3_tuner")])
	OS.set_environment("NEON_CAR", "")
	# every table entry builds, plain wheels have no screen, the race wheel does
	for kind in ["p1_coupe", "p4_kei", "p0_beater"]:
		for id in WheelStyles.SHAPE_IDS:
			var w := SteeringWheel.new()
			WheelStyles.apply(w, kind, {"shape": id})
			root.add_child(w)
			_check(w.has_screen() == (id == WheelStyles.RACE), "%s/%s: only the race wheel has the screen" % [kind, id])
			_check((id == WheelStyles.RACE) == (w.lcd_text() != ""), "%s/%s: lcd_text is empty on a plain wheel" % [kind, id])
			_check(is_equal_approx(w.radius() * 200.0, WheelStyles.diameter_cm(kind, id)), "%s/%s: the rim is the car's size, %.1f cm" % [kind, id, w.radius() * 200.0])
			w.update(0.8, false, false, 100, 3, 0.016)   # a plain wheel must take update() quietly
			root.remove_child(w)
			w.free()
	DirAccess.remove_absolute(cfg)

func _run() -> void:
	_saves()
	OS.set_environment("NEON_CABIN_MODS", "")
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		if PlayerCars.is_special(kind) or (only != "" and only != kind):
			continue
		await _car(kind)
	OS.set_environment("NEON_CAR", "")
	print("")
	print("kind / shape                       min cm  closest part               dials   rim r   dish")
	for line in table:
		print(line)
	print("")
	print("FOUND with today's wheel (cabin or driver, not changed in this step):")
	for line in found:
		print("  " + line)
	if logger.errors.size() > 0:
		print("FAIL %d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += logger.errors.size()
	print("cabin_clearance: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------- one car ----------

func _car(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	_check(p != null and cam != null and cam.frame != null, "%s: the game should boot with a cockpit frame" % kind)
	if p == null or cam == null or cam.frame == null:
		game.queue_free()
		await process_frame
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	for i in RATE:
		await physics_frame
	var frame: CockpitFrame = cam.frame
	var w: SteeringWheel = frame.wheel
	var driver: DriverModel = frame.driver
	# This test drives the frame itself: nothing else may move the wheel or the hands.
	frame.set_process(false)
	driver.set_process(false)
	for dict in [CabinMods.wheel_shapes, CabinMods.wheel_grips, CabinMods.wheel_stitches]:
		(dict as Dictionary).clear()
	_pick(frame, kind, "")
	_settle(driver, w, 0.0, 30)
	var cab: Dictionary = frame.cab
	var eye: Vector3 = cab.eye
	var statics := _static_soup(frame, driver)
	print("%s: %d cabin triangles near the wheel, eye %s, hub %s" % [kind, statics.size(), eye, frame.wheel_mount.position])
	var objects := _bobble_and_trinket(frame)
	for shape in WheelStyles.SHAPE_IDS:
		_pick(frame, kind, shape)
		_settle(driver, w, 0.0, 30)
		_shape(kind, shape, frame, driver, w, statics, eye, objects)
	_pick(frame, kind, "")
	if OS.get_environment("NEON_CLEARANCE_SCAN") != "0":
		_scan(kind, frame, w, statics, eye)
	game.queue_free()
	await process_frame
	await process_frame

## Picks a shape for the car (grip and stitch cleared) and rebuilds the wheel.
func _pick(frame: CockpitFrame, kind: String, shape: String) -> void:
	CabinMods.set_wheel_shape(kind, shape)
	CabinMods.set_wheel_grip(kind, "")
	CabinMods.set_wheel_stitch(kind, "")
	frame._refresh_wheel()

## Turns the wheel to `angle` and lets the hands settle on it.
func _settle(driver: DriverModel, w: SteeringWheel, angle: float, steps: int) -> void:
	w.set_angle(angle)
	for i in steps:
		driver._process(1.0 / float(RATE))

# ---------- the cabin ----------

## Every cabin triangle within NEAR of the hub, in the frame's space: the
## static meshes, the legs, and the lever through every gear.
func _static_soup(frame: CockpitFrame, driver: DriverModel) -> Soup:
	var soup := Soup.new()
	var inv := frame.global_transform.affine_inverse()
	var hub: Vector3 = frame.wheel_mount.position
	var cab: Dictionary = frame.cab
	for mi in frame.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var path := String(frame.get_path_to(m))
		var top := path.get_slice("/", 0)
		if SKIP.has(top) and not LEG_PARTS.has(path):
			continue
		_add_mesh(soup, m, inv, hub, _label(path, cab, m, inv))
	# the lever, through every gear (and the neutral gate between)
	var gears: int = frame.player.gear_ratios.size()
	for g in range(-1, gears + 1):
		frame._apply_lever(frame._slot_of(g))
		for mi in frame.lever.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh != null and m.is_visible_in_tree():
				_add_mesh(soup, m, inv, hub, "gear lever")
	frame._apply_lever(frame._slot_of(frame.player.gear))
	return soup

func _add_mesh(soup: Soup, mi: MeshInstance3D, inv: Transform3D, hub: Vector3, label: String) -> void:
	var xf := inv * mi.global_transform
	var f := mi.mesh.get_faces()
	var i := 0
	while i + 2 < f.size():
		var a := xf * f[i]
		var b := xf * f[i + 1]
		var c := xf * f[i + 2]
		i += 3
		if (a - hub).length() > NEAR + 0.3 and (b - hub).length() > NEAR + 0.3 and (c - hub).length() > NEAR + 0.3:
			continue
		soup.add_tri(a, b, c, label)

## A part name a person can read: the node's, or for the one big "Cabin" mesh
## where the triangle is (dash, door card, seat, console).
func _label(path: String, cab: Dictionary, mi: MeshInstance3D, inv: Transform3D) -> String:
	match path:
		"Driver/ThighL", "Driver/ThighR":
			return "thigh"
		"Driver/ShinL", "Driver/ShinR":
			return "knee/shin"
		"Cabin":
			return "cabin"
	return path.get_file().to_lower()

## Splits "cabin" triangles into dash / door card / console by where they are.
func _cabin_part(c: Vector3, cab: Dictionary) -> String:
	if absf(c.x) >= float(cab.door_x) - 0.03:
		return "door card"
	if c.y < float(cab.floor_y) + 0.35:
		return "footwell/console"
	return "dash"

# ---------- one shape ----------

func _shape(kind: String, shape: String, frame: CockpitFrame, driver: DriverModel, w: SteeringWheel, statics: Soup, eye: Vector3, objects: Dictionary) -> void:
	var pair := "%s/%s" % [kind, shape]
	var exempt: String = EXEMPT.get(pair, "")
	var problems: Array[String] = []
	# 1. rim clearance, at rest and at both locks
	var worst := _rim_clearance(frame, w, statics, [0.0, lock, -lock])
	var dial := _dial_cover(frame, w, eye)
	var top_below := _top_below_eye(frame, w, eye)
	if shape == WheelStyles.RACE:
		# Today's wheel is the baseline: whatever it does to this car is a
		# found problem in the cabin or the driver, not something a pick may
		# be blamed for, and no pick may make it worse.
		base = {"clear": float(worst.clear), "dial": dial, "top": top_below}
		if worst.clear < MIN_CLEAR:
			found.append("%s: today's race wheel is %.1f cm from the %s at %.0f deg of lock (sample %s from the hub)" % [kind, float(worst.raw) * 100.0, worst.part, rad_to_deg(worst.angle), worst.at])
		if dial > DIAL_MAX:
			found.append("%s: today's race wheel covers %.0f%% of the tach sweep from the eye" % [kind, dial * 100.0])
		if top_below < CockpitFrame.WHEEL_TOP_MIN_DEG:
			found.append("%s: today's race wheel top is %.1f deg below the eye" % [kind, top_below])
	else:
		if worst.clear < _need_clear():
			problems.append("clearance %.1f cm to %s at %.0f deg of lock (needs 2.0 from the legs, 0.3 from the cabin), sample %s" % [float(worst.raw) * 100.0, worst.part, rad_to_deg(worst.angle), worst.at])
		if dial > _max_dial():
			problems.append("dial cover %.0f%% (limit %.0f%%)" % [dial * 100.0, _max_dial() * 100.0])
		if top_below < _min_top():
			problems.append("rim top only %.1f deg below the eye (needs %.1f)" % [top_below, _min_top()])
	# 4. hands
	_settle(driver, w, 0.0, 90)
	for side in [1, -1]:
		var grip: Vector3 = frame.wheel_mount.transform * w.transform * w.rim_point(0.0 if side > 0 else 180.0)
		var d := driver.hand_position(side).distance_to(grip)
		if d > HAND_TOL:
			problems.append("rest: hand %d is %.1f cm from the grip point" % [side, d * 100.0])
	for a in [lock, -lock]:
		_settle(driver, w, a, 150)
		for side in [1, -1]:
			var d := _hand_to_rim(frame, w, driver.hand_position(side))
			if d > HAND_TOL:
				problems.append("lock %+.0f: hand %d is %.1f cm off the rim" % [rad_to_deg(a), side, d * 100.0])
	_settle(driver, w, 0.0, 90)
	# 5. bobble and trinket
	var obj := _objects_clearance(frame, w, objects, eye)
	if obj.clear < MIN_CLEAR:
		if obj.part == "wheel":
			problems.append("%s %.1f cm from the wheel" % [obj.what, obj.clear * 100.0])
		elif shape == WheelStyles.RACE:
			found.append("%s: %s swings to %.1f cm from the %s (no wheel involved)" % [kind, obj.what, obj.clear * 100.0, obj.part])
	# 6. cost
	var meshes := 0
	for n in w.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).get_parent() == w:
			meshes += 1
	var tris := w.triangle_count()
	if not w.has_screen():
		if meshes > PLAIN_MAX_MESHES:
			problems.append("%d meshes on a plain wheel" % meshes)
		if tris > PLAIN_MAX_TRIS:
			problems.append("%d triangles on a plain wheel" % tris)
	var part := String(worst.part)
	table.append("%-34s %6.1f  %-24s %4.0f%%  %5.1f  %5.1f   %d tris%s" % [pair, float(worst.raw) * 100.0, part, dial * 100.0,
		w.radius() * 100.0, w.dish() * 100.0, tris, ("  EXEMPT: " + exempt) if exempt != "" and not problems.is_empty() else ""])
	if exempt == "":
		for pr in problems:
			_check(false, "%s: %s" % [pair, pr])

## Minimum of (distance - sphere radius) over the wheel's sample spheres at
## each angle: {clear, part, angle}.
func _rim_clearance(frame: CockpitFrame, w: SteeringWheel, soup: Soup, angles: Array) -> Dictionary:
	var samples := _samples(w)
	var worst := {"clear": 9.0, "raw": 9.0, "part": "", "angle": 0.0}
	for a in angles:
		w.set_angle(float(a))
		var xf: Transform3D = frame.wheel_mount.transform * w.transform
		for s in samples:
			var r := float(s[1])
			var p: Vector3 = xf * (s[0] as Vector3)
			var res := soup.nearest(p, float(worst.clear) + r + (MIN_CLEAR - CABIN_CONTACT))
			var raw := float(res[0]) - r
			# the driver's legs keep 2 cm; a cabin part only has to not be touched
			var legs: bool = res[1] == "thigh" or res[1] == "knee/shin"
			var c := raw - (MIN_CLEAR if legs else CABIN_CONTACT) + MIN_CLEAR
			if c < float(worst.clear):
				worst.clear = c
				worst["raw"] = raw
				worst.part = String(res[1])
				if worst.part == "cabin":
					worst.part = _cabin_part(p, frame.cab)
				worst.angle = float(a)
				worst["at"] = String(s[2]) + " " + str(p - frame.wheel_mount.position)
	w.set_angle(0.0)
	return worst

## [local point, radius] spheres covering the rim, spokes, hub and pad, and
## the paddles when the wheel has them.
func _samples(w: SteeringWheel) -> Array:
	var st: Dictionary = w._st
	var out := []
	var grip_r := float(st.grip_r)
	var thin_r := float(st.thin_r)
	var dish := float(st.dish)
	for deg in range(0, 360, 5):
		out.append([w.rim_point(float(deg)), grip_r if SteeringWheel._is_grip(float(deg)) else thin_r, "rim %d" % deg])
	# Spokes are thin in z: sample their four long edges as points, not a
	# fat sphere (a sphere would reach 1 cm further toward the dash than the bar).
	var kind := String(st.spoke_kind)
	var half_w := 0.017
	var half_t := 0.006
	if kind == "thin":
		half_w = 0.007
		half_t = 0.005
	for deg in st.spokes:
		var tip := w.rim_point(float(deg))
		var hub := Vector3(0.0, 0.0, -dish)
		var dir := (tip - hub).normalized()
		var side := Vector3.BACK.cross(dir).normalized()
		for i in range(1, 7):
			var at := hub.lerp(tip, float(i) / 7.0)
			if kind == "round":
				out.append([at, 0.009, "spoke %d" % int(deg)])
				continue
			for sw in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					out.append([at + side * (half_w * sw) + Vector3.BACK * (half_t * sz), 0.0, "spoke %d at %d/7" % [int(deg), i]])
	if String(st.pad) == "race":
		# the pad box (0.115 x 0.085, z -0.003..0.027) and the hub ring behind it (r 0.055, z -0.03)
		for sx in [-0.0575, 0.0575]:
			for sy in [-0.0425, 0.0425]:
				for z in [-0.003, 0.027]:
					out.append([Vector3(sx, sy, z), 0.0, "pad corner"])
		for k in 12:
			var a := TAU * float(k) / 12.0
			out.append([Vector3(cos(a) * 0.055, sin(a) * 0.055, -0.03), 0.0, "hub ring"])
	else:
		# the hub boss (r 0.042, back at -dish - 0.03) and the pad or button
		for k in 12:
			var a := TAU * float(k) / 12.0
			out.append([Vector3(cos(a) * 0.042, sin(a) * 0.042, -dish - 0.03), 0.0, "boss"])
		out.append([Vector3(0.0, 0.0, -dish - 0.03), 0.0, "boss"])
		for sx in [-0.035, 0.035]:
			for sy in [-0.03, 0.03]:
				out.append([Vector3(sx, sy, -dish - 0.004), 0.0, "pad"])
	if w.has_screen():
		# the paddles: 0.095 x 0.036 x 0.005 at z -0.028, x 0.075..0.17
		for sx in [-1.0, 1.0]:
			for x in [0.075, 0.1225, 0.17]:
				for y in [-0.023, -0.005, 0.013]:
					out.append([Vector3(sx * x, y, -0.0305), 0.0, "paddle"])
	return out

## Share of 40 rays from the eye to the tach needle's sweep that the wheel
## blocks first, wheel at rest.
func _dial_cover(frame: CockpitFrame, w: SteeringWheel, eye: Vector3) -> float:
	w.set_angle(0.0)
	var inv := frame.global_transform.affine_inverse()
	var tris := PackedVector3Array()
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := inv * m.global_transform
		for v in m.mesh.get_faces():
			tris.append(xf * v)
	var cab: Dictionary = frame.cab
	var centre: Vector3 = frame.tach_needle.position
	var r: float = float(frame.dial_radii()[0]) - 0.006
	var sweep := frame.dial_sweep
	var rays := 0
	var blocked := 0
	for i in DIAL_RAYS_ANGLES:
		var th := deg_to_rad(sweep * 0.5 - sweep * float(i) / float(DIAL_RAYS_ANGLES - 1))
		var dir := Vector3(-sin(th), cos(th), 0.0)
		for f in DIAL_RAYS_RADII:
			var target := centre + dir * (r * float(f))
			var to := target - eye
			var dist := to.length()
			var d := to / dist
			rays += 1
			var j := 0
			while j + 2 < tris.size():
				var hit: Variant = Geometry3D.ray_intersects_triangle(eye, d, tris[j], tris[j + 1], tris[j + 2])
				j += 3
				if hit != null and eye.distance_to(hit as Vector3) < dist - 0.005:
					blocked += 1
					break
	return float(blocked) / float(maxi(rays, 1))

## How far the rim top (grip included) sits below the eye's horizontal, degrees.
func _top_below_eye(frame: CockpitFrame, w: SteeringWheel, eye: Vector3) -> float:
	w.set_angle(0.0)
	var top_local := w.rim_point(90.0) + Vector3(0.0, w.grip_radius(), 0.0)
	var top: Vector3 = frame.wheel_mount.transform * top_local
	return rad_to_deg(atan2(eye.y - top.y, eye.z - top.z))

## Distance from a car-space point to the rim's centreline (min over 5-degree samples).
func _hand_to_rim(frame: CockpitFrame, w: SteeringWheel, hand: Vector3) -> float:
	var xf: Transform3D = frame.wheel_mount.transform * w.transform
	var best := 9.0
	for deg in range(0, 360, 5):
		best = minf(best, hand.distance_to(xf * w.rim_point(float(deg))))
	return best

# ---------- bobble and trinket ----------

## The worst-tilt vertices of every bobble figure and trinket design in frame
## space, those near the wheel kept apart, plus each one's clearance to the
## mirror, the windscreen and the A-pillars: {near: [points, labels], fixed:
## {clear, what, part}}.
func _bobble_and_trinket(frame: CockpitFrame) -> Dictionary:
	var inv := frame.global_transform.affine_inverse()
	var hub: Vector3 = frame.wheel_mount.position
	var cab: Dictionary = frame.cab
	var near_pts := PackedVector3Array()
	var near_lbl := PackedStringArray()
	var fixed := {"clear": 9.0, "what": "", "part": ""}
	var all_pts := PackedVector3Array()
	var all_lbl := PackedStringArray()
	# bobble figures, the neck-pivot lean the shader applies (see BobbleHead.BOB_SHADER)
	frame.bobble.set_active(true)
	var t: float = frame.bobble.tilt_max
	var d := t * 0.7071   # the lean is capped by length (BobbleHead.step), so the diagonals are t/sqrt2
	var combos := [Vector2(t, 0), Vector2(-t, 0), Vector2(0, t), Vector2(0, -t), Vector2(d, d), Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d)]
	for id in BobbleFigures.IDS:
		if id == BobbleFigures.NONE:
			continue
		frame.bobble.set_figure(id)
		var mi := frame.bobble.mesh_instance()
		if mi == null:
			continue
		var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var xf := inv * mi.global_transform
		for bob in combos:
			for i in verts.size():
				var uv := uvs[i]
				var q := verts[i] - Vector3(0.0, uv.y, 0.0)
				var s: float = (bob as Vector2).x * uv.x
				var f: float = (bob as Vector2).y * uv.x
				q = Vector3(q.x * cos(s) + q.y * sin(s), -q.x * sin(s) + q.y * cos(s), q.z)
				q = Vector3(q.x, q.y * cos(f) - q.z * sin(f), q.z * cos(f) + q.y * sin(f))
				all_pts.append(xf * (q + Vector3(0.0, uv.y, 0.0)))
				all_lbl.append("bobble " + id)
	frame.bobble.set_active(false)
	# trinket designs at the largest swing
	var tr: DashTrinket = frame.trinket
	var sw := DashTrinket.SWING_MAX
	var swings := [Vector2(sw, 0), Vector2(-sw, 0), Vector2(0, sw), Vector2(0, -sw), Vector2(sw, sw), Vector2(-sw, -sw), Vector2(sw, -sw), Vector2(-sw, sw)]
	for id in DashTrinket.IDS:
		if id == DashTrinket.NONE:
			continue
		tr.set_design(id)
		var charm := tr.get_node_or_null("Pivot/Charm") as MeshInstance3D
		if charm == null:
			continue
		for sv in swings:
			tr.phi = (sv as Vector2).x
			tr.psi = (sv as Vector2).y
			tr._apply_pose()
			var xf := inv * charm.global_transform
			var faces := charm.mesh.get_faces()
			for fi in range(36, faces.size()):   # the first 12 triangles are the cord, which hangs from the mirror by design
				all_pts.append(xf * faces[fi])
				all_lbl.append("trinket " + id)
	tr.phi = 0.0
	tr.psi = 0.0
	tr._apply_pose()
	tr.set_design(CabinMods.trinket)
	# fixed parts: rear-view mirror, windscreen glass, A-pillars
	var rear_pos: Vector3 = cab.rear_mirror
	var rb := Basis(Vector3.UP, deg_to_rad(CockpitMirrors.REAR_YAW)) * Basis(Vector3.RIGHT, deg_to_rad(CockpitMirrors.REAR_PITCH))
	var box_c := rear_pos + rb * Vector3(0, 0, -0.013)
	var box_h := Vector3(0.215, 0.072, 0.022) * 0.5
	var cowl: Vector2 = cab.cowl
	var header: Vector2 = cab.header
	var p0 := Vector2(cowl.y, cowl.x + 0.086 - 0.008)    # (z, y) of the glass line's lower end
	var p1 := Vector2(header.y, header.x - 0.008)
	var gdir := (p1 - p0).normalized()
	var foot: Vector3 = cab.a_pillar[0]
	var topp: Vector3 = cab.a_pillar[1]
	# The tilts and swings share most vertices (and a mesh repeats a vertex
	# per face): measure each distinct point once. The first label is kept,
	# which is the one the strict "<" below would report anyway.
	var seen := {}
	var uniq_pts := PackedVector3Array()
	var uniq_lbl := PackedStringArray()
	for i in all_pts.size():
		if seen.has(all_pts[i]):
			continue
		seen[all_pts[i]] = true
		uniq_pts.append(all_pts[i])
		uniq_lbl.append(all_lbl[i])
	all_pts = uniq_pts
	all_lbl = uniq_lbl
	for i in all_pts.size():
		var p := all_pts[i]
		var lbl := all_lbl[i]
		if p.distance_to(hub) <= NEAR + 0.05:
			near_pts.append(p)
			near_lbl.append(lbl)
		# mirror housing (oriented box)
		var q := rb.inverse() * (p - box_c)
		var o := Vector3(maxf(absf(q.x) - box_h.x, 0.0), maxf(absf(q.y) - box_h.y, 0.0), maxf(absf(q.z) - box_h.z, 0.0))
		_fix(fixed, o.length(), lbl, "rear-view mirror")
		# windscreen: positive below the glass line, only along the glass
		if p.z >= cowl.y - 0.05 and p.z <= header.y:
			var wv := Vector2(p.z, p.y) - p0
			var below := -(gdir.x * wv.y - gdir.y * wv.x)
			_fix(fixed, below, lbl, "windscreen")
		# A-pillars (capsules, 7.5 cm across)
		for side in [-1.0, 1.0]:
			var a := Vector3(side * (foot.x - 0.04), foot.y, foot.z + 0.02)
			var b := Vector3(side * (topp.x - 0.13), topp.y - 0.09, topp.z + 0.03)
			var cp := Geometry3D.get_closest_point_to_segment(p, a, b)
			_fix(fixed, p.distance_to(cp) - 0.0375, lbl, "A-pillar")
	return {"near_pts": near_pts, "near_lbl": near_lbl, "fixed": fixed}

static func _fix(fixed: Dictionary, clear: float, lbl: String, part: String) -> void:
	if clear < float(fixed.clear):
		fixed.clear = clear
		fixed.what = lbl
		fixed.part = part

## The worst of the fixed-part clearance and the near-wheel distances for this shape.
func _objects_clearance(frame: CockpitFrame, w: SteeringWheel, objects: Dictionary, eye: Vector3) -> Dictionary:
	var res := {"clear": float((objects.fixed as Dictionary).clear), "what": (objects.fixed as Dictionary).what, "part": (objects.fixed as Dictionary).part}
	w.set_angle(0.0)
	var inv := frame.global_transform.affine_inverse()
	var soup := Soup.new()
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := inv * m.global_transform
		var f := m.mesh.get_faces()
		var i := 0
		while i + 2 < f.size():
			soup.add_tri(xf * f[i], xf * f[i + 1], xf * f[i + 2], "wheel")
			i += 3
	var pts: PackedVector3Array = objects.near_pts
	var lbls: PackedStringArray = objects.near_lbl
	# The wheel's bounding box: a point at least `res.clear` outside it is at
	# least that far from every wheel triangle, so it cannot set a new minimum.
	var box_lo := Vector3(INF, INF, INF)
	var box_hi := Vector3(-INF, -INF, -INF)
	for k in soup.size():
		box_lo = box_lo.min(soup.lo[k])
		box_hi = box_hi.max(soup.hi[k])
	for i in pts.size():
		var p := pts[i]
		if p.distance_to(p.clamp(box_lo, box_hi)) >= float(res.clear):
			continue
		var r := soup.nearest(p, float(res.clear) + 0.0)
		if float(r[0]) < float(res.clear):
			res.clear = float(r[0])
			res.what = lbls[i]
			res.part = "wheel"
	return res

# ---------- fit limits ----------

## The largest rim radius (0.5 cm steps, round three-spoke, no dish) and the
## largest dish (1 cm steps, deep dish at its medium size) that pass checks 1-3.
func _scan(kind: String, frame: CockpitFrame, w: SteeringWheel, statics: Soup, eye: Vector3) -> void:
	var fit := WheelStyles.fit_for(kind)
	if OS.get_environment("NEON_CLEARANCE_GRID") == "1":
		# design aid: round three-spoke, clearance by radius and flat-bottom share
		for fy in [-1.0, -0.9, -0.8, -0.7]:
			var row := ""
			for rr in [0.150, 0.160, 0.170, 0.175, 0.180, 0.190]:
				WheelStyles.apply(w, kind, {"shape": "sport3"})
				var st := WheelStyles.style_for(kind, "sport3", rr, 0.0)
				st["flat_y"] = fy
				w.style = st
				w.rebuild()
				var c := _rim_clearance(frame, w, statics, [0.0, lock, -lock])
				row += "  r%.1f %+.1f %s" % [rr * 100.0, float(c.clear) * 100.0, String(c.part).left(6)]
			print("%s flat %.2f:%s" % [kind, fy, row])
	var best_r := 0.0
	var least_r := 0.0
	var r := 0.150
	while r <= 0.2301:
		if _passes(kind, "sport3", r, 0.0, frame, w, statics, eye):
			best_r = r   # the largest size that passes (the knees clear a bigger rim better, the sight line a smaller one)
			if least_r == 0.0:
				least_r = r
		r += 0.005
	var r_med := clampf((float(fit.factory) - 1.0) * 0.005, least_r, maxf(best_r, least_r))
	var best_d := -1.0
	var d := 0.0
	while d <= 0.1201:
		if not _passes(kind, "deepdish", r_med, d, frame, w, statics, eye):
			break
		best_d = d
		d += 0.01
	var want_r := float(fit.hi) * 0.005
	var want_d := float(fit.dish) * 0.01
	var want_lo := float(fit.lo) * 0.005
	print("%s FIT scan: radius %.1f..%.1f cm passes (table %.1f..%.1f cm), largest dish %.0f cm at r %.1f cm (table asks %.0f cm)%s" % [
		kind, least_r * 100.0, best_r * 100.0, want_lo * 100.0, want_r * 100.0, best_d * 100.0, r_med * 100.0, want_d * 100.0,
		"  <-- CLAMP" if (want_r > best_r + 1e-6 or want_lo < least_r - 1e-6 or want_d > best_d + 1e-6) else ""])
	_check(want_r <= best_r + 1e-6 and want_lo >= least_r - 1e-6 and want_d <= best_d + 1e-6, "%s: the FIT table asks for more than passes" % kind)
	# put the car's own pick back
	WheelStyles.apply(w, kind, CabinMods.wheel_picks(kind))
	w.rebuild()

func _passes(kind: String, shape: String, r: float, d: float, frame: CockpitFrame, w: SteeringWheel, statics: Soup, eye: Vector3) -> bool:
	WheelStyles.apply(w, kind, {"shape": shape})
	w.style = WheelStyles.style_for(kind, shape, r, d)
	w.rebuild()
	if float(_rim_clearance(frame, w, statics, [0.0, lock, -lock]).clear) < _need_clear():
		return false
	if _top_below_eye(frame, w, eye) < _min_top():
		return false
	return _dial_cover(frame, w, eye) <= _max_dial()
