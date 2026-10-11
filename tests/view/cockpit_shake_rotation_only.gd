extends "res://tests/view/parked_cockpit.gd"

# Camera upgrade C1 (2026-10-10): in the cockpit the shake is rotation only.
# Position shake (it was up to 12 cm on a big hit) could push the eye into the
# roof, a pillar or the glass. The car is parked, the camera shaken at full
# trauma and a full road bump every frame: the eye must sit exactly where the
# head puts it (car transform x (eye + head_offset)), 0 cm off, while the view
# still rotates as before (a visible shake, within the old rotation envelope).
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/cockpit_shake_rotation_only.gd

const FRAMES := 90

var max_off := 0.0
var max_rot := 0.0
var samples := 0

func _init() -> void:
	name_ = "cockpit_shake_rotation_only"

func _step(n: int) -> bool:
	if n == 0:
		cam.shake_enabled = true
		return false
	cam.trauma = 1.0    # the biggest hit, kept at the maximum
	cam.bump = 1.0      # and a full road bump
	if n < 10:
		return false    # let a couple of frames draw with the shake on
	var head_pos := p.global_transform * (cam.eye + cam.head_offset)
	max_off = maxf(max_off, cam.global_position.distance_to(head_pos))
	var unshaken := cam._levelled(p.global_basis)
	max_rot = maxf(max_rot, rad_to_deg(unshaken.get_rotation_quaternion().angle_to(cam.global_basis.get_rotation_quaternion())))
	samples += 1
	if n < FRAMES:
		return false
	print("shaken %d frames at full trauma: eye off the head position by %.6f m, view rotated up to %.2f deg" % [samples, max_off, max_rot])
	_check(samples > 40, "the check sampled enough frames (%d)" % samples)
	_check(max_off < 0.0001, "cockpit shake moves the eye 0 cm (%.6f m)" % max_off)
	_check(max_rot > 0.3, "the view still shakes in rotation (%.2f deg)" % max_rot)
	_check(max_rot < 4.0, "and within the old envelope (%.2f deg)" % max_rot)
	return _end("")
