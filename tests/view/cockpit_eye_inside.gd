extends "res://tests/view/parked_cockpit.gd"

# Camera upgrade C1 (2026-10-10): the cockpit eye never leaves the cabin.
# Through a scripted hit (full trauma + road bump, shake on), a crest and a dip
# (body pitched +/-10 deg, rolled +/-8 deg) and a full look-around (all four
# arrow keys held in turn), the eye, in car space, stays inside this car's
# cabin box from CabinSpec (|x| < door_x, floor_y < y < roof_y, header z .. rear_z).
# The eye is also checked with the head's full sway added in each direction
# (HEAD_MAX_M), since the head offset is capped but real.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/cockpit_eye_inside.gd

const POSES := [[0.0, 0.0], [0.0, 10.0], [0.0, -10.0], [8.0, 0.0], [-8.0, 0.0], [8.0, 10.0]]
const KEYS := ["look_left", "look_right", "look_up", "look_down"]
const HOLD := 40   # ticks per key, ~0.67 s: past the full turn (0.15 s tap window + 0.2 s)

var box_lo := Vector3.ZERO
var box_hi := Vector3.ZERO
var worst := 0.0       # largest distance the eye got outside the box, m (<= 0: always inside)
var frames := 0
var key_down := ""

func _init() -> void:
	name_ = "cockpit_eye_inside"

func _step(n: int) -> bool:
	if n == 0:
		var cab := CabinSpec.for_kind(PlayerCar.chassis_kind())
		var hdr: Vector2 = cab.header
		# the front of the box is the windscreen at the eye's height (the arcade
		# eye sits ahead of the header's z on every car, behind the glass)
		var cowl: Vector2 = cab.cowl
		var e0: Vector3 = cam.eye
		var tg := clampf((e0.y - cowl.x) / maxf(hdr.x - cowl.x, 0.01), 0.0, 1.0)
		box_lo = Vector3(-float(cab.door_x), float(cab.floor_y), lerpf(cowl.y, hdr.y, tg) + 0.04)
		box_hi = Vector3(float(cab.door_x), float(cab.roof_y), float(cab.rear_z))
		cam.shake_enabled = true
		# the eye, plus the head's full sway each way, must fit: static margin check
		var e: Vector3 = cam.eye
		var m := ChaseCamera.HEAD_MAX_M
		for d in [Vector3(m, 0, 0), Vector3(-m, 0, 0), Vector3(0, 0, m), Vector3(0, 0, -m)]:
			var q: Vector3 = e + d
			_check(_inside(q) >= 0.0, "the eye %s plus full head sway %s is inside the box %s..%s" % [e, d, box_lo, box_hi])
		print("cabin box %s .. %s, eye %s" % [box_lo, box_hi, e])
	cam.trauma = 1.0   # the scripted hit, held at its worst
	cam.bump = 1.0
	if n > 4:
		var eye_local := p.global_transform.affine_inverse() * cam.global_position
		worst = maxf(worst, -_inside(eye_local))
		frames += 1
	var pose_ticks := SETTLE_TICKS * 2
	var pose_total := POSES.size() * pose_ticks
	if n < pose_total:
		if n % pose_ticks == 0:
			var pz: Array = POSES[n / pose_ticks]
			pose(pz[0], pz[1])
		return false
	var m2 := n - pose_total
	if m2 % HOLD == 0:
		if key_down != "":
			Input.action_release(key_down)
			key_down = ""
		var k := m2 / HOLD
		if k >= KEYS.size():
			return _done()
		if k == 0:
			pose(0.0, 0.0)
		key_down = KEYS[k]
		Input.action_press(key_down)
	return false

## Distance inside the box (m), negative outside: the smallest margin to a face.
func _inside(q: Vector3) -> float:
	return minf(minf(minf(q.x - box_lo.x, box_hi.x - q.x), minf(q.y - box_lo.y, box_hi.y - q.y)),
		minf(q.z - box_lo.z, box_hi.z - q.z))

func _done() -> bool:
	print("eye checked over %d frames; worst excursion past the box: %.4f m" % [frames, worst])
	_check(frames > 100, "enough frames were sampled (%d)" % frames)
	_check(worst <= 0.0, "the eye never leaves the cabin (%.4f m outside)" % worst)
	return _end("")
