class_name ExhaustGraphic
extends PageGraphic

# Sound page: the exhaust tip with a flame that grows with the Flame setting,
# pop sparks that multiply with Pops and crackle, sound rings for Loudness, and
# the tag "Sound and looks only". Reads spec.exhaust (ExhaustTune.KEYS).

func _draw() -> void:
	if spec.is_empty():
		return
	var ex: Dictionary = spec.get("exhaust", {})
	var w := size.x
	var h := size.y
	var tip := Vector2(w * 0.3, h * 0.48)
	text("EXHAUST", Vector2(6, 14))
	# tag
	var tag := "SOUND AND LOOKS ONLY"
	var tw := UiTheme.font("strong").get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_rect(Rect2(w - tw - 18.0, 2.0, tw + 12.0, 20.0), TunerColours.PLOT)
	text(tag, Vector2(w - tw - 12.0, 17.0), 13, TunerColours.STOCK)
	# pipe
	draw_rect(Rect2(tip.x - 90, tip.y - 14, 90, 28), TunerColours.PLOT)
	draw_rect(Rect2(tip.x - 90, tip.y - 14, 90, 28), TunerColours.LABEL, false, 2.0)
	draw_arc(tip, 14.0, -PI * 0.5, PI * 0.5, 12, TunerColours.LABEL, 2.0)
	# flame
	var flame := float(ex.get("flame", 0.0))
	if flame > 0.02:
		var l := 20.0 + 90.0 * flame
		var pts := PackedVector2Array([tip + Vector2(4, -11), tip + Vector2(l * 0.55, -16 * flame - 6), tip + Vector2(l, 0),
			tip + Vector2(l * 0.55, 16 * flame + 6), tip + Vector2(4, 11)])
		draw_colored_polygon(pts, Color(TunerColours.YOURS, 0.85))
		var core := PackedVector2Array([tip + Vector2(4, -6), tip + Vector2(l * 0.6, 0), tip + Vector2(4, 6)])
		draw_colored_polygon(core, TunerColours.VALUE)
	# pops: sparks, more with the setting
	var pops := float(ex.get("pops", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in roundi(pops * 14.0):
		var p := tip + Vector2(rng.randf_range(20, 130), rng.randf_range(-40, 40))
		draw_circle(p, rng.randf_range(1.5, 3.0), TunerColours.VALUE)
	# loudness: rings
	var loud := float(ex.get("loudness", 0.0))
	for i in roundi(1.0 + loud * 3.0):
		draw_arc(tip + Vector2(40, 0), 36.0 + 18.0 * i, -0.5, 0.5, 10, Color(TunerColours.LABEL, 0.5 - 0.1 * i), 2.0)
	var rows := [["Loudness", "loudness"], ["Pops", "pops"], ["Flame", "flame"], ["Rasp", "raspiness"]]
	for i in rows.size():
		var y := h - 52.0 + (i / 2) * 22.0
		var x := 6.0 + (i % 2) * w * 0.5
		text(rows[i][0], Vector2(x, y), 13, TunerColours.DIM)
		mono("%d%%" % roundi(100.0 * float(ex.get(rows[i][1], 0.0))), Vector2(x + 72, y))
