class_name SetupGraphic
extends PageGraphic

# Setup page (Tuner UI overhaul PR 4): the Grip to Drift dial as a big rotary
# knob, stock as its steel-blue tick, and beside it a top-down car showing what
# the character means. Toward Grip it sits straight with planted arrows; toward
# Drift it slides sideways with a smoke trail behind, the slide angle growing
# with the dial. ctx.character is the dial notch (TunerModel.character).

var dial: RotaryDial

func _ready() -> void:
	dial = RotaryDial.new()
	dial.title = "GRIP TO DRIFT"
	dial.lo_word = "Grip"
	dial.hi_word = "Drift"
	dial.ticks = TunerModel.CHARACTER_NOTCHES
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dial)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if dial == null:
		return
	var d := minf(size.y, size.x * 0.55)
	dial.position = Vector2(0.0, (size.y - d) * 0.5)
	dial.size = Vector2(d, d)

func show_setup(s: Dictionary, st: Dictionary, c := {}) -> void:
	super.show_setup(s, st, c)
	if dial == null:
		return
	var n: int = c.get("character", TunerModel.CHARACTER_STOCK)
	# a loaded sheet or the Street preset is not a dial position: name it instead
	var label: String = c.get("label", "")
	var on_dial := label == "" or label.begins_with("Stock") or label.begins_with("Grip") or label.begins_with("Drift")
	dial.set_values(float(n) / (TunerModel.CHARACTER_NOTCHES - 1), 0.5, TunerModel.character_word(n) if on_dial else label)

func _draw() -> void:
	var n: int = ctx.get("character", TunerModel.CHARACTER_STOCK)
	var t := float(n - TunerModel.CHARACTER_STOCK) / float(TunerModel.CHARACTER_STOCK)  # -1 grip .. +1 drift
	var left := minf(size.y, size.x * 0.55)
	var c := Vector2(left + (size.x - left) * 0.5, size.y * 0.5)
	var slide := deg_to_rad(38.0) * maxf(t, 0.0)
	# smoke trail: puffs behind the rear axle, sweeping out with the slide
	if t > 0.05:
		for i in 7:
			var k := float(i + 1) / 7.0
			var p := c + Vector2(0.0, 22.0 + 16.0 * i).rotated(slide * 0.5) + Vector2(-slide * 30.0 * k, 0.0)
			draw_circle(p, 5.0 + 4.0 * k, Color(TunerColours.LABEL, 0.35 * (1.0 - k) * t + 0.05))
	# the car, nose up, yawed by the slide angle
	var body := car_pts(Vector2.ZERO, 30.0, 58.0)
	var pts := PackedVector2Array()
	for p in body:
		pts.append(c + p.rotated(slide))
	draw_colored_polygon(pts, TunerColours.YOURS)
	draw_line(c + Vector2(-9, -16).rotated(slide), c + Vector2(9, -16).rotated(slide), TunerColours.PANEL, 3.0)
	# the way it is travelling, and grip arrows pressing it down toward Grip
	arrow(c + Vector2(0, -40), c + Vector2(0, -66), Color(TunerColours.DIM, 0.9), 2.0)
	if t < -0.05:
		for side in [-1.0, 1.0]:
			arrow(c + Vector2(side * 30.0, -10.0 - 22.0 * -t), c + Vector2(side * 30.0, -6.0), TunerColours.VALUE, 2.5)
	var words := "Planted: hooks up and holds the line" if t < -0.05 else ("Loose: steps out and holds a slide" if t > 0.05 else "As it left the factory")
	centred(words, Vector2(c.x, size.y - 4.0), 12, TunerColours.LABEL)
	if t > 0.05:
		mono("%d° slide" % roundi(rad_to_deg(slide)), c + Vector2(26, -30), 12, TunerColours.VALUE)
