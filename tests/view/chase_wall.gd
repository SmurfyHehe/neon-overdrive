extends "res://tests/view/parked_cockpit.gd"

# Chase camera wall check (camera proposal step 1, #634, #557): the chase
# camera is never inside the world or behind it.
# - Tunnel, Up held: driving in through the mouth with the camera lifted, it
#   stays under the roof (TunnelKit.CLEAR_H less ChaseCamera.WALL_GAP) and its
#   height never jumps at the mouth.
# - Clear road: nothing in the way, so the wall check changes nothing
#   (wall_f stays exactly 1), and the check's cost per frame is measured.
# - Crash: a wall 1 m off the nose, then reverse, then B: on every drawn frame
#   the camera is outside the wall and the line from the roof to it is clear.
# - Guardrail: a 0.8 m rail 2.5 m to the left, Left held for the 100 degree
#   orbit: the camera stays on the car's side of the rail, the line under it is
#   clear, and after release it eases back out (no frame further than
#   OUT_STEP_MAX), back to the full distance.
# Frame-clock test (one sample per drawn frame): run with --fixed-fps 60.
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/view/chase_wall.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const TunnelKit := preload("res://scripts/world/tunnel_kit.gd")

const START_S := 4170.0      # 80 m before the tunnel's mouth (tests/world/tunnel.gd: road 0, s 4250-4550)
const STOP_S := 4330.0       # brake from here: the car stops under the roof
const CRUISE := 22.0         # m/s
const FRAMES := 90           # drawn frames per held case (1.5 s at 60 fps)
## The camera's height may change this much in one drawn frame near the mouth:
## the roof cap comes down WALL_MOUTH_SLOPE m per metre in front of it, 0.18 m
## a frame at CRUISE, plus the rig's own follow on the ramp. Measured after the
## Up lift has settled (its own ease is 0.3 m a frame at first).
const MOUTH_STEP_MAX := 0.25
## Easing back out at WALL_OUT_RATE 4/s over ~5 m is ~0.35 m a frame at 60 fps.
const OUT_STEP_MAX := 0.4
## The check's own cost, one call (two rays) on the cloud's 2.8 GHz Xeon.
const COST_MAX_US := 20.0

enum S { DRIVE, STOP, CLEAR, CRASH_REV, CRASH_B, RAIL, RAIL_OUT, DONE }
var s := S.DRIVE
var s_frame := 0
var frame_n := 0
var last_frame := -1
var in_tunnel_frames := 0
var max_over_roof := -INF
var max_mouth_step := 0.0
var last_y := INF
var bad := 0
var bad_at := ""
var step_at := ""
var max_out_step := 0.0
var last_dist := -1.0
var wall: StaticBody3D
var rail: StaticBody3D

func _init() -> void:
	name_ = "chase_wall"
	park = false

func _initialize() -> void:
	OS.set_environment("NEON_START_S", str(START_S))
	super._initialize()

func _drive(c: PlayerCar) -> void:
	c.steering_input = 0.0
	c.handbrake_input = 0.0
	if s == S.DRIVE:
		var err := CRUISE - c.current_speed()
		c.throttle_input = clampf(err * 0.3, 0.0, 1.0)
		c.brake_input = clampf(-err * 0.3, 0.0, 1.0)
	else:
		c.throttle_input = 0.0
		c.brake_input = 1.0

func _go(next: S) -> void:
	s = next
	s_frame = frame_n

## A box on the wall layer, `size` in the car's frame, centred at `at` (car space).
func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	CarSpec.make_wall(b)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	b.add_child(col)
	current_scene.add_child(b)
	b.global_transform = p.global_transform * Transform3D(Basis.IDENTITY, at)
	return b

func _roof() -> Vector3:
	return p.get_global_transform_interpolated() * Vector3(cam._centre_local.x, cam._roof_local + ChaseCamera.WALL_ROOF_UP, cam._centre_local.z)

## Why the camera of the last drawn frame is in the world, "" when it is not.
func _blocked() -> String:
	var space := p.get_world_3d().direct_space_state
	var pt := PhysicsPointQueryParameters3D.new()
	pt.position = cam.global_position
	pt.collision_mask = ChaseCamera.WALL_MASK
	if not space.intersect_point(pt, 1).is_empty():
		return "inside a wall"
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(_roof(), cam.global_position, ChaseCamera.WALL_MASK))
	if not hit.is_empty():
		return "a wall between the roof and the camera at %s" % hit.position
	return ""

func _count_bad(what: String) -> void:
	var why := _blocked()
	if why != "":
		bad += 1
		if bad_at == "":
			bad_at = "%s frame %d: %s (camera in car frame %s)" % [what, frame_n - s_frame, why, p.global_transform.affine_inverse() * cam.global_position]

func _rel() -> Vector3:
	return p.global_transform.affine_inverse() * cam.global_position

## Mean microseconds of one _wall_check call in the camera's current state.
func _cost() -> float:
	var u := RoadFrame.unroll(p.get_global_transform_interpolated().origin)
	var a_rs := RoadFrame.unroll(cam.anchor)
	var keep_f := cam.wall_f
	var keep_anchor := cam.anchor
	var n := 2000
	var t0 := Time.get_ticks_usec()
	for i in n:
		cam.anchor = keep_anchor
		cam._wall_check(1.0 / 60.0, u, a_rs)
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	cam.wall_f = keep_f
	cam.anchor = keep_anchor
	return us

## Once per drawn frame, before the camera's own _process: the camera as the
## last frame drew it.
func _process(_delta: float) -> bool:
	if cam == null or boot_tick < 0 or not is_instance_valid(p):
		return false
	var fr := Engine.get_process_frames()
	if fr == last_frame:
		return false
	last_frame = fr
	frame_n += 1
	match s:
		S.DRIVE, S.STOP:
			var c := RoadFrame.unroll(cam.global_position)
			var depth := RoadMap.tunnel_depth(RoadFrame.s_at(c.z))
			if depth > 0.0:
				in_tunnel_frames += 1
				max_over_roof = maxf(max_over_roof, c.y - TunnelKit.CLEAR_H)
			if last_y < INF and frame_n - s_frame > 60 and absf(c.y - last_y) > max_mouth_step:
				max_mouth_step = absf(c.y - last_y)
				step_at = "%s frame %d, %.1f m from the mouth, camera %.2f m up" % [S.keys()[s], frame_n - s_frame, depth, c.y]
			last_y = c.y
		S.CRASH_REV:
			if frame_n - s_frame > 2:
				_count_bad("reverse")
		S.CRASH_B:
			if frame_n - s_frame > 0:
				_count_bad("B")
		S.RAIL:
			if frame_n - s_frame > 2:
				_count_bad("orbit")
				var rel := _rel()
				if rel.x < -2.5 + 0.15:
					bad += 1
					if bad_at == "":
						bad_at = "orbit frame %d: the camera is past the rail (car frame %s)" % [frame_n - s_frame, rel]
		S.RAIL_OUT:
			var d := cam.global_position.distance_to(_roof())
			if last_dist >= 0.0:
				max_out_step = maxf(max_out_step, d - last_dist)
			last_dist = d
	return false

func _step(_n: int) -> bool:
	var t := frame_n - s_frame
	match s:
		S.DRIVE:
			if t == 0:
				cam.set_view(ChaseCamera.View.CHASE)
				# the monster truck's framing (5 m up): with Up held it is far above the roof
				cam.base_height = ChaseCamera.FRAMING["m1_monster"][1]
				Input.action_press("look_up")
			var car_s := RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)
			if car_s >= STOP_S:
				_go(S.STOP)
			elif t > 60 * 30:
				return _end("the car never reached the tunnel (at s %.1f)" % car_s)
		S.STOP:
			if absf(p.current_speed()) < 0.3 and t > 20:
				Input.action_release("look_up")
				cam.base_height = ChaseCamera.HEIGHT
				print("tunnel, Up held: %d frames under the roof, highest %.2f m from the roof (allowed %.2f), largest height step %.3f m (%s)" % [in_tunnel_frames, max_over_roof, -ChaseCamera.WALL_GAP, max_mouth_step, step_at])
				_check(RoadMap.tunnel_depth(RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)) > 20.0, "the car stopped under the roof")
				_check(in_tunnel_frames > 60, "the camera was under the roof (%d frames)" % in_tunnel_frames)
				_check(max_over_roof <= -ChaseCamera.WALL_GAP + 0.01, "tunnel: the camera rose to %.2f m from the roof" % max_over_roof)
				_check(max_mouth_step <= MOUTH_STEP_MAX, "tunnel: the camera's height jumped %.3f m in one frame" % max_mouth_step)
				p.freeze = true
				park_origin = p.global_transform.origin
				park_basis = p.global_transform.basis
				_go(S.CLEAR)
		S.CLEAR:
			if t > 0 and t < 40:
				_check(cam.wall_f == 1.0 and not cam.wall_hit, "clear road: the wall check moved the camera (wall_f %.4f)" % cam.wall_f)
			if t == 40:
				var us := _cost()
				print("wall check cost, nothing in the way: %.2f us a frame" % us)
				_check(us <= COST_MAX_US, "wall check cost %.2f us (max %.0f)" % [us, COST_MAX_US])
				# a wall 1 m off the nose: 0.6 m thick, across the whole road
				wall = _box(Vector3(0.0, 2.0, -(2.4 + 1.0 + 0.3)), Vector3(16.0, 6.0, 0.6))
				p.current_gear = -1
				_go(S.CRASH_REV)
		S.CRASH_REV:
			p.current_gear = -1
			if t == FRAMES:
				print("crash, reverse: %d bad frames; camera in car frame %s, wall_f %.2f" % [bad, _rel(), cam.wall_f])
				_check(_rel().z < -1.0, "reverse: the rig swung to the front (%s)" % _rel())
				_check(cam.wall_hit, "reverse: the wall was seen")
				var us := _cost()
				print("wall check cost, wall in the way: %.2f us a frame" % us)
				_check(us <= COST_MAX_US, "wall check cost with a hit %.2f us (max %.0f)" % [us, COST_MAX_US])
				p.current_gear = 1
				Input.action_press("look_back")
				_go(S.CRASH_B)
		S.CRASH_B:
			if t == FRAMES:
				print("crash, B: %d bad frames so far; camera in car frame %s" % [bad, _rel()])
				_check(_rel().z < -1.0, "B: the rig is in front (%s)" % _rel())
				Input.action_release("look_back")
				wall.queue_free()
				_go(S.RAIL)
		S.RAIL:
			if t == 60 and rail == null:
				# the rig is back behind the car: a 0.8 m rail 2.5 m to its left
				rail = _box(Vector3(-2.5, 0.0, 0.0), Vector3(0.3, 0.8, 30.0))
				var r := RoadFrame.unroll(rail.global_position)
				rail.global_position = RoadFrame.roll(Vector3(r.x, 0.4, r.z))   # standing on the road
				s_frame = frame_n
				Input.action_press("look_left")
			elif t == FRAMES and rail != null:
				print("guardrail, Left held: %d bad frames so far; orbit %.1f, camera in car frame %s, wall_f %.2f" % [bad, cam.orbit_yaw, _rel(), cam.wall_f])
				_check(cam.orbit_yaw > 90.0, "the orbit swung left (%.1f)" % cam.orbit_yaw)
				_check(cam.wall_hit, "orbit: the rail was seen")
				Input.action_release("look_left")
				_go(S.RAIL_OUT)
		S.RAIL_OUT:
			if t == 120:
				print("guardrail, released: largest step out %.3f m a frame (max %.2f), wall_f %.4f" % [max_out_step, OUT_STEP_MAX, cam.wall_f])
				_check(max_out_step <= OUT_STEP_MAX, "after release the camera stepped out %.3f m in one frame" % max_out_step)
				_check(cam.wall_f == 1.0, "after release the camera is back at the full distance (wall_f %.4f)" % cam.wall_f)
				_check(bad == 0, "%d frames with the camera in or behind a wall; first: %s" % [bad, bad_at])
				rail.queue_free()
				return _end("")
	return false
