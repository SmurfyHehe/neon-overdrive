extends SceneTree

# Cockpit interior (cockpit milestone, 2026-10-06), headless and silent:
# - the CockpitFrame lives on the player car and has the cabin, the SteeringWheel
#   (LED strip, LCD, paddles), the cluster needles, lamps, lever, handbrake,
#   pedals, radio label and the three CockpitMirrors
# - the wheel turns by steer_fraction x WHEEL_LOCK_RAD, the same way the car steers
# - the LED count grows with rpm from 60% of max, reaches 15 at the shift point
#   and all of them flash on the HUD's shift cue; the LCD shows rpm, km/h, gear
# - the mirror SubViewports never render in the chase view and do in the cockpit;
#   their cameras skip the interior and see the car's own body, far clip 250 m
# - the pedals follow the inputs, the lever moves to the gear on a manual shift
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/cockpit_interior.gd

const TIMEOUT_TICKS := 60 * 30

enum Step { BOOT, CHASE, COCKPIT, WHEEL, PEDALS, SHIFT, BACK, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var steer := 0.0
var throttle := 0.0
var lever_moved := false

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_interior_exhaust.json"
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = steer

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var frame: CockpitFrame = cam.frame
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(frame != null and frame.get_parent() == p, "the cockpit frame should be a child of the player car")
			for n in ["Cabin", "Backlight", "WheelMount", "WheelMount/Wheel", "WheelMount/Wheel/Leds", "WheelMount/Wheel/Lcd",
					"WheelMount/Wheel/PaddleL", "WheelMount/Wheel/PaddleR", "TachNeedle", "SpeedoNeedle", "Lamps", "Radio", "Radio/Screen", "Radio/Bezel",
					"Lever", "Lever/Knob", "Handbrake", "ThrottlePedal", "BrakePedal", "ClutchPedal", "CabinLight",
					"Mirrors", "Mirrors/RearView", "Mirrors/LeftView", "Mirrors/RightView", "Mirrors/RearGlass", "Shelf"]:
				_check(frame.get_node_or_null(n) != null, "the cockpit should have a node %s" % n)
			_check(frame.mirrors.views.size() == 3, "three mirrors")
			for v in frame.mirrors.views:
				var c: Camera3D = v.cam
				_check(c.cull_mask & CockpitFrame.INTERIOR_BIT == 0, "mirror cameras must not draw the interior")
				_check(c.cull_mask & CockpitFrame.MIRROR_ONLY_BIT != 0 and c.cull_mask & 1 != 0, "mirror cameras should see the world and the car's own body")
				_check(absf(c.far - CockpitMirrors.FAR) < 0.01, "mirror far clip should be %.0f m" % CockpitMirrors.FAR)
				_check(v.mat.uv1_scale.x < 0.0, "mirror glass should be flipped left to right")
			_check(frame.mirrors.views[0].vp.size == Vector2i(320, 96) and frame.mirrors.views[1].vp.size == Vector2i(160, 112), "mirror sizes at medium quality: %s %s" % [frame.mirrors.views[0].vp.size, frame.mirrors.views[1].vp.size])
			_check(cam.cull_mask & CockpitFrame.MIRROR_ONLY_BIT == 0, "the main camera must never draw the mirror-only layer")
			_check(cam.cull_mask & CockpitFrame.INTERIOR_BIT != 0, "the main camera draws the interior")
			_check(frame.get_node("Cabin").layers == CockpitFrame.INTERIOR_BIT, "the cabin mesh is on the interior layer")
			# LED rule, static
			_check(SteeringWheel.lit_count_for(0.3) == 0 and SteeringWheel.lit_count_for(0.59) == 0, "no LEDs below 60%% of max rpm")
			_check(SteeringWheel.lit_count_for(0.60) == 2, "the two outer LEDs light at 60%%, got %d" % SteeringWheel.lit_count_for(0.60))
			var prev := 0
			var mono := true
			for i in 101:
				var n := SteeringWheel.lit_count_for(float(i) / 100.0)
				mono = mono and n >= prev
				prev = n
			_check(mono, "the lit LED count never drops as rpm rises")
			_check(SteeringWheel.lit_count_for(Hud.SHIFT_POINT) == 15 and SteeringWheel.lit_count_for(1.0) == 15, "all 15 LEDs at the shift point")
			_check(SteeringWheel.led_base_colour(0) == Hud.RPM_GREEN and SteeringWheel.led_base_colour(14) == Hud.RPM_GREEN, "the outer LEDs are green")
			_check(SteeringWheel.led_base_colour(4) == SteeringWheel.AMBER and SteeringWheel.led_base_colour(7) == SteeringWheel.RED, "amber then red toward the middle")
			_go(Step.CHASE)
		Step.CHASE:
			if waited == 30:
				_check(not frame.cockpit and frame.visible, "the interior is drawn in the chase view too (through the glass), cockpit mode off")
				# the HUD rear strip may queue the rearview in the chase view; the door mirrors never render there
				_check(not frame.mirrors.active and not _side_rendering(frame), "door mirrors must not render in the chase view")
				_check(not frame.body_hidden_from_camera(), "the body is drawn in the chase view")
				cam.set_view(ChaseCamera.View.COCKPIT)
				steer = 0.6
				_go(Step.COCKPIT)
		Step.COCKPIT:
			if waited == 6:
				_check(frame.cockpit and frame.visible and frame.mirrors.active, "the cockpit mode starts the mirrors")
				_check(frame.mirrors.is_rendering(), "a mirror should be queued to render in the cockpit view")
				_check(frame.body_hidden_from_camera(), "the body moves to the mirror-only layer in the cockpit")
				_go(Step.WHEEL)
		Step.WHEEL:
			if waited == 60:
				var w := frame.wheel
				_check(absf(frame.steering - p.steer_fraction()) < 1e-4, "the frame reads the car's steer fraction")
				# the drawn wheel rolls to steering x lock through CockpitFrame's spring (2026-10-09)
				_check(absf(w.angle - frame.steering * CockpitFrame.WHEEL_LOCK_RAD) < deg_to_rad(1.5), "the wheel has rolled to steering x lock (%.3f vs %.3f)" % [w.angle, frame.steering * CockpitFrame.WHEEL_LOCK_RAD])
				_check(absf(w.angle) > 0.5, "the wheel should be turned well off centre (%.2f rad)" % w.angle)
				_check(signf(w.angle) == signf(frame.steering) and absf(w.rotation.z + w.angle) < 1e-4, "right steering turns the wheel clockwise (rotation.z = -angle)")
				var frac := clampf(p.motor_rpm / p.max_rpm, 0.0, 1.0)
				_check(w.lit_count == SteeringWheel.lit_count_for(frac), "live LED count follows the live rpm")
				_check(w.lcd.text.contains("rpm") and w.lcd.text.contains("km/h") and w.lcd.text.contains(str(int(p.motor_rpm))) and w.lcd.text.contains(str(Hud.kmh(p.current_speed()))) and w.lcd.text.ends_with(Hud.gear_text(p.gear)), "the LCD shows rpm, km/h and the gear, got '%s'" % w.lcd.text.replace("\n", " / "))
				# flash on the shift cue: manual, gear 1 of several, past the shift point
				p.automatic_transmission = false
				var cue := Hud.shift_cue(p, 0.95)
				_check(cue, "manual box in 1st past the shift point should cue a shift")
				w.update(0.95, cue, true, 6650.0, 40, "1")
				_check(w.lit_count == 15 and w.flashing, "all LEDs lit and flashing on the cue")
				var mid := w.led_colours[7]
				_check(mid.a > 0.99 and mid.r > 0.7 and mid.g > 0.7 and mid.b > 0.7, "a flashing LED goes silver, got %s" % mid)
				w.update(0.95, cue, false, 6650.0, 40, "1")
				_check(not w.flashing and w.led_colours[7].is_equal_approx(Color(SteeringWheel.RED, 1.0)), "between blinks the middle LED is red")
				w.update(0.5, false, false, 3500.0, 40, "1")
				_check(w.lit_count == 0 and w.led_colours[0].a < 0.01, "at 50%% every LED is off (alpha 0)")
				_check_sightline(p, frame)
				_check_wheel_pose(frame)
				_check_view(p, frame, cam)
				steer = 0.0
				throttle = 1.0
				_go(Step.PEDALS)
		Step.PEDALS:
			if waited == 30:
				var t: Node3D = frame.pedals.throttle
				var b: Node3D = frame.pedals.brake
				_check(t.rotation_degrees.x > 10.0, "the throttle pedal should be pressed (%.1f deg)" % t.rotation_degrees.x)
				_check(b.rotation_degrees.x < 1.0, "the brake pedal stays up (%.1f deg)" % b.rotation_degrees.x)
				_check(frame.tach_needle.rotation.z < deg_to_rad(135.0) - 0.05, "the tach needle moves off empty with revs")
				p.automatic_transmission = false
				var before: int = p.gear
				p.shift(1)
				_check(p.requested_gear == before + 1, "shift(1) should request the next gear")
				_go(Step.SHIFT)
		Step.SHIFT:
			lever_moved = lever_moved or frame.lever_moving
			if waited == 90:
				_check(lever_moved, "a manual shift should move the gear lever")
				_check(not frame.lever_moving and frame._lever_gear == p.gear, "the lever should settle in the new gear's slot within 1.5 s (gear %d)" % p.gear)
				_check(absf(frame.lever.rotation_degrees.x - CockpitFrame.LEVER_ROW_TILT * frame._slot_of(p.gear).y) < 0.5, "the lever tilt matches the H-gate row of gear %d" % p.gear)
				throttle = 0.0
				cam.set_view(ChaseCamera.View.CHASE)
				_go(Step.BACK)
		Step.BACK:
			if waited == 6:
				_check(not frame.cockpit and not frame.mirrors.active and not _side_rendering(frame), "back in the chase view the door mirrors stop")
				_check(not frame.body_hidden_from_camera(), "back in the chase view the body is drawn again")
				print("cockpit triangles: %d (wheel %d)" % [frame.triangle_count(), frame.wheel.triangle_count()])
				return _end("")
	return false

## Roy (2026-10-06): the cluster must not block the road. Rays from the cockpit
## eye across +-20 degrees, from the horizon down to the ground 10 m ahead of
## the bumper, may hit nothing of the interior except the wheel rim (the band
## stays clear of the A-pillars, which sit past 25 degrees).
func _check_sightline(p: PlayerCar, frame: CockpitFrame) -> void:
	var eye := ChaseCamera.COCKPIT_EYE
	var ground_z := -(P1CoupeBuilder.LENGTH / 2.0) - 10.0
	var ground_pitch := -rad_to_deg(atan2(eye.y, eye.z - ground_z))
	var to_car := p.global_transform.affine_inverse()
	var hits := {}
	var rays := 0
	var meshes: Array = frame.find_children("*", "MeshInstance3D", true, false)
	for yaw_i in 11:
		var yaw := deg_to_rad(-20.0 + 4.0 * yaw_i)
		for pitch in [0.0, -1.0, -2.0, -3.0, -4.0, ground_pitch]:
			rays += 1
			var dir := Vector3(0, 0, -1).rotated(Vector3.RIGHT, deg_to_rad(pitch)).rotated(Vector3.UP, yaw)
			for m in meshes:
				var mi := m as MeshInstance3D
				if not mi.mesh is ArrayMesh or not mi.is_visible_in_tree() or _see_through(mi):
					continue   # the driver's head and torso are hidden in the cockpit view; glass is clear
				var xf: Transform3D = to_car * mi.global_transform
				var mesh := mi.mesh as ArrayMesh
				for si in mesh.get_surface_count():
					var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
					var t := 0
					while t + 2 < verts.size():
						var hit = Geometry3D.ray_intersects_triangle(eye, dir, xf * verts[t], xf * verts[t + 1], xf * verts[t + 2])
						t += 3
						if hit == null:
							continue
						if mi.name == "WheelBody":
							var local: Vector3 = frame.wheel.global_transform.affine_inverse() * (p.global_transform * hit)
							if Vector2(local.x, local.y).length() >= 0.13:
								continue   # the rim is allowed
						var key := "%s@%.1f/%.1f" % [mi.name, rad_to_deg(yaw), pitch]
						hits[key] = hit
	print("sightline: %d rays, ground pitch %.2f deg, %d blocked" % [rays, ground_pitch, hits.size()])
	_check(hits.is_empty(), "the cluster, dash, hub or column block the road from the eye: %s" % [hits.keys().slice(0, 8)])

## Roy (2026-10-06): the wheel points at the driver and does not block the view.
## The face normal must rise toward the eye (between 15 and 35 degrees up from
## the hub), and the top of the rim, grip included, must sit at least
## CockpitFrame.WHEEL_TOP_MIN_DEG below the eye's horizontal.
func _check_wheel_pose(frame: CockpitFrame) -> void:
	var eye := ChaseCamera.COCKPIT_EYE
	var hub := CockpitFrame.WHEEL_POS
	var normal: Vector3 = frame.wheel_mount.transform.basis * Vector3(0, 0, 1)
	var normal_up := rad_to_deg(atan2(normal.y, normal.z))
	var to_eye := eye - hub
	var eye_up := rad_to_deg(atan2(to_eye.y, to_eye.z))
	var top_local := frame.wheel.rim_point(90.0) + Vector3(0, SteeringWheel.GRIP_R, 0)
	var top: Vector3 = frame.wheel_mount.transform * top_local
	var top_below := rad_to_deg(atan2(eye.y - top.y, eye.z - top.z))
	print("wheel pose: face %.1f deg up, eye %.1f deg up from the hub, rim top %.1f deg below the eye" % [normal_up, eye_up, top_below])
	_check(normal_up >= 15.0 and normal_up <= 35.0 and normal_up < eye_up, "the wheel face looks %.1f deg up; it should rise toward the driver's eye" % normal_up)
	_check(top_below >= CockpitFrame.WHEEL_TOP_MIN_DEG, "the rim top is only %.1f deg below the eye" % top_below)

static func _side_rendering(frame: CockpitFrame) -> bool:
	for i in [1, 2]:
		if frame.mirrors.views[i].vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			return true
	return false

## Roy (2026-10-06): the dash top at least CockpitFrame.DASH_TOP_MIN_DEG below
## A mesh drawn with alpha transparency (the side window pane) is glass: the
## sightline rays pass through it.
static func _see_through(mi: MeshInstance3D) -> bool:
	var m := mi.material_override
	if m == null and mi.mesh.get_surface_count() > 0:
		m = mi.mesh.surface_get_material(0)
	return m is StandardMaterial3D and (m as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA

## the eye, and at least CockpitFrame.GLASS_MIN_FRACTION of the cockpit view
## clear glass. Both measured with rays from the eye in car space:
## - the dash top: at yaws between the binnacle and the A-pillar, the first
##   pitch below the horizon (half-degree steps) at which a ray hits any part
##   of the interior; the highest of those is the dash line;
## - clear glass: a 32 x 18 grid of rays over the camera's rest FOV at 16:9;
##   a ray that hits nothing of the interior looks out through glass.
func _check_view(p: PlayerCar, frame: CockpitFrame, cam: ChaseCamera) -> void:
	var eye := ChaseCamera.COCKPIT_EYE
	var to_car := p.global_transform.affine_inverse()
	# gather every interior triangle in car space, with a bounding box per mesh
	var meshes := []
	for m in frame.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.mesh is ArrayMesh or not mi.is_visible_in_tree() or _see_through(mi):
			continue   # the door glass pane (window animation) is glass, not an obstruction
		var xf: Transform3D = to_car * mi.global_transform
		var tris: PackedVector3Array = []
		var mesh := mi.mesh as ArrayMesh
		for si in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in verts:
				tris.append(xf * v)
		if tris.is_empty():
			continue
		var lo := tris[0]
		var hi := tris[0]
		for v in tris:
			lo = lo.min(v)
			hi = hi.max(v)
		meshes.append({"name": mi.name, "tris": tris, "aabb": AABB(lo, hi - lo).grow(0.001)})
	# dash top: scan down from the horizon across the driver's view (+-20 deg,
	# +yaw is left), skipping yaws where the first thing hit is the binnacle
	# (near, in front of the driver) or an A-pillar (far out to the side)
	var dash_top := 90.0
	var dash_where := ""
	for yi in 21:
		var yaw_deg := -20.0 + 2.0 * yi
		var pitch := 0.0
		while pitch < 40.0:
			var dir := Vector3(0, 0, -1).rotated(Vector3.RIGHT, deg_to_rad(-pitch)).rotated(Vector3.UP, deg_to_rad(yaw_deg))
			var hit := _first_hit(meshes, eye, dir)
			if not hit.is_empty():
				var pt: Vector3 = hit.point
				var binnacle := absf(pt.x - CockpitFrame.SEAT_X) < 0.22 and pt.z > -0.52
				var pillar := absf(pt.x) > 0.55
				if not binnacle and not pillar and pitch < dash_top:
					dash_top = pitch
					dash_where = "%s at yaw %.0f, %s" % [hit.name, yaw_deg, pt]
				break
			pitch += 0.5
	# clear glass over the view
	var fov := cam.fov
	var results := {}
	for test_fov in [fov, 62.0]:
		var half_v := tan(deg_to_rad(test_fov) * 0.5)
		var half_h := half_v * 16.0 / 9.0
		var clear := 0
		var total := 0
		for j in 18:
			var v := (0.5 - (float(j) + 0.5) / 18.0) * 2.0 * half_v
			for i in 32:
				var u := ((float(i) + 0.5) / 32.0 - 0.5) * 2.0 * half_h
				total += 1
				if _first_hit(meshes, eye, Vector3(u, v, -1.0).normalized()).is_empty():
					clear += 1
		results[test_fov] = float(clear) / float(total)
	print("view: dash top %.1f deg below the eye (%s); clear glass %.1f%% at FOV %.0f, %.1f%% at FOV 62" % [dash_top, dash_where, results[fov] * 100.0, fov, results[62.0] * 100.0])
	_check(dash_top >= CockpitFrame.DASH_TOP_MIN_DEG, "the dash top is only %.1f deg below the eye (%s), want %.0f" % [dash_top, dash_where, CockpitFrame.DASH_TOP_MIN_DEG])
	# The share is asserted at FOV 62, the cockpit default PR #135 sets (this
	# branch's rest FOV is printed too); the eye is 0.34 m from the glass top,
	# so a wider view fills with header and pillars whatever the dash does.
	_check(results[62.0] >= CockpitFrame.GLASS_MIN_FRACTION, "only %.1f%% of the view is clear glass at FOV 62, want %.0f%%" % [results[62.0] * 100.0, CockpitFrame.GLASS_MIN_FRACTION * 100.0])

## The first mesh a ray from `from` along `dir` hits, as {name, point}; empty for none.
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

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("cockpit_interior: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
