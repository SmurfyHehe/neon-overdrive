extends SceneTree

# Wheel screen (2026-10-11): the seven-segment gear and speed on the steering
# wheel's LED MultiMesh. Headless, no scene needed:
# - the segment pattern of every gear char (r, n, 1-6) and of speeds 0, 9, 99, 245
# - no leading zeros: blank digits stay unlit; all slots keep the faint 8% segments
# - the gear shows the instant it changes; speed changes at most 5 times in a
#   second of rising speed; max 999
# - no Label3D under the wheel, no rpm number, and no more draw calls than before
# - the window fits: top corners inside the LED plate's inner edge (0.118), bottom
#   clear of the centre pad (0.0425), every segment inside the window
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --audio-driver Dummy -s res://tests/view/wheel_screen.gd

const GEAR := {"r": "eg", "n": "ceg", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg"}
const DIGIT := {"0": "abcdef", "2": "abdeg", "4": "bcfg", "5": "acdfg", "9": "abcdfg"}
const DRAWS_BEFORE := 5   # body, LED MultiMesh, LCD label, two paddles

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var w := SteeringWheel.new()
	root.add_child(w)
	await process_frame   # _ready builds the wheel
	_patterns(w)
	_speeds(w)
	_rates(w)
	_structure(w)
	_geometry(w)
	print("wheel_screen: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

## The lit segments of digit `d` (0 = gear, 1-3 = speed) as letters, a..g.
func _lit(w: SteeringWheel, d: int) -> String:
	var out := ""
	for s in 7:
		var c: Color = w.seg_colours[d * 7 + s]
		if SevenSeg.is_lit(c):
			out += "abcdefg"[s]
	return out

## Every segment renders as amber #FFC066: full when lit, 8% when not.
func _all_faint_or_lit(w: SteeringWheel) -> bool:
	var amber := SteeringWheel.AMBER
	for c: Color in w.seg_colours:
		var r := SevenSeg.rendered(c)
		var share := r.r / amber.r
		var hue_ok := absf(r.g / amber.g - share) < 0.01 and absf(r.b / amber.b - share) < 0.01
		var want := 1.0 if SevenSeg.is_lit(c) else SevenSeg.UNLIT_SHARE
		if not (hue_ok and absf(share - want) < 0.01):
			return false
	return true

func _show(w: SteeringWheel, kmh: int, gear: int) -> void:
	w.update(0.3, false, false, kmh, gear, 0.25)   # a long enough frame to pass the speed rate limit

func _patterns(w: SteeringWheel) -> void:
	_show(w, 0, -1)
	_check(_lit(w, 0) == GEAR["r"] and w.lcd_text().begins_with("r "), "reverse should light e,g and read r, got '%s' '%s'" % [_lit(w, 0), w.lcd_text()])
	_show(w, 0, 0)
	_check(_lit(w, 0) == GEAR["n"] and w.lcd_text().begins_with("n "), "neutral should light c,e,g and read n, got '%s'" % _lit(w, 0))
	for g in range(1, 7):
		_show(w, 0, g)
		_check(_lit(w, 0) == GEAR[str(g)] and w.lcd_text().begins_with("%d " % g), "gear %d pattern, got '%s' (want %s)" % [g, _lit(w, 0), GEAR[str(g)]])
	_check(_all_faint_or_lit(w), "every segment renders amber: full when lit, 8%% when not")

func _speeds(w: SteeringWheel) -> void:
	_show(w, 0, 1)
	_check(w.lcd_text() == "1   0", "speed 0 reads '  0', got '%s'" % w.lcd_text())
	_check(_lit(w, 1) == "" and _lit(w, 2) == "" and _lit(w, 3) == DIGIT["0"], "speed 0: only the ones digit lights a 0, got '%s' '%s' '%s'" % [_lit(w, 1), _lit(w, 2), _lit(w, 3)])
	_show(w, 9, 1)
	_check(w.lcd_text() == "1   9" and _lit(w, 1) == "" and _lit(w, 2) == "" and _lit(w, 3) == DIGIT["9"], "speed 9 reads '  9' (no leading zeros), got '%s'" % w.lcd_text())
	_show(w, 99, 2)
	_check(w.lcd_text() == "2  99" and _lit(w, 1) == "" and _lit(w, 2) == DIGIT["9"] and _lit(w, 3) == DIGIT["9"], "speed 99 reads ' 99', got '%s'" % w.lcd_text())
	_show(w, 245, 4)
	_check(w.lcd_text() == "4 245" and _lit(w, 1) == DIGIT["2"] and _lit(w, 2) == DIGIT["4"] and _lit(w, 3) == DIGIT["5"], "speed 245 reads '245', got '%s'" % w.lcd_text())
	_show(w, 1500, 4)
	_check(w.lcd_text() == "4 999", "speed caps at 999, got '%s'" % w.lcd_text())
	_check(_all_faint_or_lit(w), "unlit segments stay at 8%% amber, every slot")
	_show(w, 0, 0)

## Gear is instant; speed changes at most 5 times in a second of rising speed.
func _rates(w: SteeringWheel) -> void:
	_show(w, 50, 3)
	w.update(0.3, false, false, 50, 4, 0.001)
	_check(w.lcd_text().begins_with("4 "), "the gear shows the moment it changes, got '%s'" % w.lcd_text())
	var changes := 0
	var last := w.lcd_text().substr(2)
	for i in 60:
		var kmh := 50 + int(float(i + 1) * 1.5)   # rising about 90 km/h per second
		w.update(0.3, false, false, kmh, 4, 1.0 / 60.0)
		var now := w.lcd_text().substr(2)
		if now != last:
			changes += 1
			last = now
	_check(changes <= 5 and changes >= 3, "speed digits changed %d times in one second, want 3..5" % changes)

func _structure(w: SteeringWheel) -> void:
	_check(w.find_children("*", "Label3D", true, false).is_empty(), "no Label3D under the wheel")
	var draws := 0
	for n in w.find_children("*", "VisualInstance3D", true, false):
		if n is MeshInstance3D or n is MultiMeshInstance3D or n is Label3D:
			draws += 1
	_check(draws <= DRAWS_BEFORE, "wheel draw calls %d, was %d" % [draws, DRAWS_BEFORE])
	var mm: MultiMesh = w.leds.multimesh
	_check(mm.instance_count == 15 + 4 + 28, "LED MultiMesh holds 15 LEDs, 4 buttons and 28 segments, got %d" % mm.instance_count)
	_check(not w.lcd_text().contains("rpm"), "no rpm on the screen")

func _geometry(w: SteeringWheel) -> void:
	var half_w := SteeringWheel.WIN_W * 0.5
	var half_h := SteeringWheel.WIN_H * 0.5
	var top_corner := Vector2(half_w, SteeringWheel.WIN_Y + half_h).length()
	_check(top_corner <= 0.118, "window top corners at radius %.4f must stay inside the LED plate edge 0.118" % top_corner)
	_check(SteeringWheel.WIN_Y - half_h >= 0.0425 + 0.004, "window bottom %.4f must clear the centre pad top 0.0425" % (SteeringWheel.WIN_Y - half_h))
	_check(is_equal_approx(SteeringWheel.WIN_W, 0.100) and is_equal_approx(SteeringWheel.WIN_H, 0.056), "window is 100 x 56 mm")
	var gx0 := 1.0e9
	var gx1 := -1.0e9
	var sx0 := 1.0e9
	var sx1 := -1.0e9
	var gy0 := 1.0e9
	var gy1 := -1.0e9
	var sy0 := 1.0e9
	var sy1 := -1.0e9
	for i in 28:
		var r: Rect2 = w.seg_rects[i]
		var lo := r.position
		var hi := r.end
		_check(lo.x >= -half_w + 0.003 and hi.x <= half_w - 0.003 and lo.y >= SteeringWheel.WIN_Y - half_h + 0.003 and hi.y <= SteeringWheel.WIN_Y + half_h - 0.003, "segment %d (%.3f..%.3f, %.3f..%.3f) must sit inside the window with a margin" % [i, lo.x, hi.x, lo.y, hi.y])
		if i < 7:
			gx0 = minf(gx0, lo.x); gx1 = maxf(gx1, hi.x); gy0 = minf(gy0, lo.y); gy1 = maxf(gy1, hi.y)
		else:
			sx0 = minf(sx0, lo.x); sx1 = maxf(sx1, hi.x); sy0 = minf(sy0, lo.y); sy1 = maxf(sy1, hi.y)
	_check(absf((gy1 - gy0) - 0.040) < 0.0005, "gear digit is 40 mm tall, got %.1f mm" % ((gy1 - gy0) * 1000.0))
	_check(absf((gx1 - gx0) - 0.033) < 0.001, "gear digit is about 33 mm wide, got %.1f mm" % ((gx1 - gx0) * 1000.0))
	_check(absf((sy1 - sy0) - 0.018) < 0.0005, "speed digits are 18 mm tall, got %.1f mm" % ((sy1 - sy0) * 1000.0))
	_check(absf((sx1 - sx0) - 0.044) < 0.001, "three speed digits are about 44 mm wide, got %.1f mm" % ((sx1 - sx0) * 1000.0))
	_check(gx1 < sx0, "the gear digit sits left of the speed digits")
