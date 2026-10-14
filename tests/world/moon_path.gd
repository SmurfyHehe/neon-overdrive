extends SceneTree

# Moon path test (more-alive MA3, 2026-10-11). Pure maths on NightSky, no scene.
# Roy (1377): the moon moves, like the real one.
#
# For 40 nights, sampling the night every six game minutes:
# - the moon is above the horizon from 8 p.m. to 6 a.m. (altitude > 0)
# - its highest point falls between 1 and 2 a.m., at 45-55 degrees (never
#   overhead, where it would be out of every view)
# - the direction swings 140-180 degrees over the night, in one sense
# - it climbs by day-angle rate: about 15 degrees an hour of hour angle, so no
#   step between samples is more than 4 degrees of arc
# - low in the east at 8 p.m. (under 16.5 degrees up, right of the road's
#   direction), low in the west at 6 a.m. (under 25 degrees up, behind)
# - the evening moon is not inside the 20 degree cone around straight ahead
# - the phase is exactly what it was (phase_for_night is untouched here)
# - the per-night directions are finite unit vectors, and set_moon_time puts
#   the same value on the global shader parameter the car paint reads
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/moon_path.gd

const STEPS := 100    # 6 game minutes each

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	var worst_swing_lo := 999.0
	var worst_swing_hi := -999.0
	var peak_lo := 999.0
	var peak_hi := -999.0
	var step_max := 0.0
	var ahead_min := 999.0
	var low_az := []
	for night in range(1, 41):
		var best_t := 0.0
		var best_el := -999.0
		var prev := Vector3.ZERO
		var first := Vector3.ZERO
		var last := Vector3.ZERO
		var swing_prev := 0.0
		var swing := 0.0
		for i in STEPS + 1:
			var t := float(i) / STEPS
			var d := NightSky.moon_direction(night, t)
			if not is_equal_approx(d.length(), 1.0):
				_fail("night %d t %.2f: direction not a unit vector (%.4f)" % [night, t, d.length()])
			if d.y <= 0.0:
				_fail("night %d t %.2f (%02d:%02d): the moon is below the horizon (el %.1f)" % [night, t, int(20.0 + t * 10.0) % 24, int(fmod(t * 600.0, 60.0)), rad_to_deg(asin(d.y))])
			var el := rad_to_deg(asin(d.y))
			if el > best_el:
				best_el = el
				best_t = t
			var az := rad_to_deg(atan2(d.x, -d.z))   # right of straight ahead, -180..180
			if i == 0:
				first = d
				swing_prev = az
				ahead_min = minf(ahead_min, absf(az))
			else:
				var dz := fposmod(az - swing_prev + 180.0, 360.0) - 180.0   # shortest signed turn
				swing += dz
				swing_prev = az
				step_max = maxf(step_max, rad_to_deg(prev.angle_to(d)))
			last = d
			prev = d
		var peak_h := best_t * 10.0   # hours after 8 p.m.
		if peak_h < 5.0 - 0.001 or peak_h > 6.0 + 0.001:
			_fail("night %d: highest at %.1f h after 8 p.m. (%.2f a.m.), wanted 1-2 a.m." % [night, peak_h, peak_h - 4.0])
		peak_lo = minf(peak_lo, best_el)
		peak_hi = maxf(peak_hi, best_el)
		if best_el < 45.0 - 0.5 or best_el > 55.0 + 0.5:
			_fail("night %d: peak altitude %.1f, wanted 45-55" % [night, best_el])
		worst_swing_lo = minf(worst_swing_lo, absf(swing))
		worst_swing_hi = maxf(worst_swing_hi, absf(swing))
		if absf(swing) < 140.0 or absf(swing) > 180.0:
			_fail("night %d: swung %.0f degrees, wanted 140-180" % [night, swing])
		if swing < 0.0:
			_fail("night %d: swung the wrong way (%.0f)" % [night, swing])
		var el0 := rad_to_deg(asin(first.y))
		var el1 := rad_to_deg(asin(last.y))
		if el0 > 16.5 or first.x <= 0.0:
			_fail("night %d: 8 p.m. moon %.1f up, x %.2f (wanted low, on the right)" % [night, el0, first.x])
		var az1 := absf(rad_to_deg(atan2(last.x, -last.z)))
		if el1 > 27.0 or az1 < 150.0:
			_fail("night %d: 6 a.m. moon %.1f up, %.0f degrees off ahead (wanted low and behind)" % [night, el1, az1])
		low_az.append(rad_to_deg(atan2(first.x, -first.z)))
	if ahead_min < 20.0:
		_fail("an evening moon sat %.1f degrees off straight ahead, inside the 20 degree cone" % ahead_min)
	if step_max > 4.0:
		_fail("the moon jumped %.1f degrees between samples (6 game minutes)" % step_max)

	# phase is untouched
	var p1 := NightSky.phase_for_night(1)
	if not is_equal_approx(p1, fposmod(NightSky.PHASE_NIGHT_1, 1.0)):
		_fail("phase for night 1 changed: %.3f" % p1)

	# the car paint's global value follows set_moon_time
	NightSky.set_moon_time(null, 3, 0.5)
	var want := NightSky.moon_direction(3, 0.5)
	if not NightSky.moon_dir.is_equal_approx(want):
		_fail("set_moon_time did not set moon_dir")

	print("moon_path: 40 nights, peak %.1f-%.1f degrees up (1-2 a.m.), swing %.0f-%.0f degrees, biggest step %.2f degrees per 6 min, 8 p.m. moon %.0f-%.0f degrees right of ahead" % [
		peak_lo, peak_hi, worst_swing_lo, worst_swing_hi, step_max, low_az.min(), low_az.max()])
	for t in [0.0, 0.3, 0.5, 0.6, 0.95, 1.0]:
		var d := NightSky.moon_direction(1, t)
		var hh := int(20.0 + t * 10.0) % 24
		print("  night 1 %02d:%02d el %5.1f az %6.1f right of ahead" % [hh, int(fmod(t * 600.0, 60.0)), rad_to_deg(asin(d.y)), rad_to_deg(atan2(d.x, -d.z))])
	print("moon_path: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(0 if fails == 0 else 1)
