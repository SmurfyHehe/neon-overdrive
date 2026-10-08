class_name RotaryDial
extends Control

# A big rotary knob, or a needle gauge (needle = true), drawn in Godot (Tuner UI
# overhaul PR 2). Value and stock are 0..1 along a 240 degree sweep from
# lo_word (bottom left) to hi_word (bottom right). Stock is a steel-blue tick,
# yours the sodium pointer. Used for the Grip to Drift dial, the boost gauge and
# the diff lock ring; standalone so the Stage E garage can place it too
# (scenes/tuner_kit/rotary_dial.tscn).

const SWEEP := deg_to_rad(240.0)

@export_range(0.0, 1.0) var value := 0.5:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
@export_range(0.0, 1.0) var stock := 0.5:
	set(v):
		stock = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var title := ""
@export var lo_word := ""
@export var hi_word := ""
## Big centre readout, e.g. "0.8 bar"; empty = none.
@export var readout := ""
@export var needle := false
@export var ticks := 11
## Optional band of the sweep in a warning colour, 0..1 (e.g. red line).
@export var red_from := 2.0

func _init() -> void:
	custom_minimum_size = Vector2(150, 150)

func set_values(v: float, s: float, text := "") -> void:
	value = v
	stock = s
	readout = text
	queue_redraw()

func _angle(t: float) -> float:
	# 0 at bottom-left (210 deg from +x, measured clockwise on screen), 1 at bottom-right
	return deg_to_rad(150.0) + SWEEP * t

func _draw() -> void:
	var title_h := 20.0 if title != "" else 0.0
	var words_h := 18.0 if lo_word != "" or hi_word != "" else 0.0
	var box := Vector2(size.x, size.y - title_h - words_h)
	var r := minf(box.x, box.y) * 0.5 - 6.0
	if r <= 8.0:
		return
	var c := Vector2(size.x * 0.5, title_h + box.y * 0.5 + r * 0.12)
	var font := UiTheme.font("strong")
	var mono := UiTheme.font("mono")
	if title != "":
		_text(font, title, Vector2(size.x * 0.5, 15.0), 15, TunerColours.LABEL)
	# track
	draw_arc(c, r, _angle(0.0), _angle(1.0), 48, TunerColours.PLOT, 8.0, true)
	if red_from < 1.0:
		draw_arc(c, r, _angle(red_from), _angle(1.0), 16, Color(TunerColours.WORSE, 0.7), 8.0, true)
	if not needle:
		draw_arc(c, r, _angle(0.0), _angle(value), 48, TunerColours.YOURS, 8.0, true)
	for i in ticks:
		var a := _angle(float(i) / maxf(ticks - 1, 1))
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - 14.0), c + d * (r - 8.0), TunerColours.DIM, 2.0, true)
	# stock: a steel-blue tick across the track
	var sa := Vector2(cos(_angle(stock)), sin(_angle(stock)))
	draw_line(c + sa * (r - 10.0), c + sa * (r + 9.0), TunerColours.STOCK, 3.0, true)
	var va := Vector2(cos(_angle(value)), sin(_angle(value)))
	if needle:
		draw_line(c, c + va * (r - 4.0), TunerColours.YOURS, 3.0, true)
		draw_circle(c, 6.0, TunerColours.YOURS)
	else:
		# the knob: a plate with a pointer
		draw_circle(c, r * 0.62, TunerColours.PANEL)
		draw_arc(c, r * 0.62, 0.0, TAU, 40, TunerColours.PLOT, 3.0, true)
		draw_line(c + va * r * 0.2, c + va * r * 0.58, TunerColours.YOURS, 5.0, true)
	if readout != "":
		_text(mono, readout, c + Vector2(0.0, r * (0.62 if needle else 0.95) + (0.0 if needle else -2.0)), 15, TunerColours.VALUE)
	if lo_word != "":
		_text(font, lo_word, Vector2(c.x - r * 0.62, size.y - 3.0), 14, TunerColours.DIM)
	if hi_word != "":
		_text(font, hi_word, Vector2(c.x + r * 0.62, size.y - 3.0), 14, TunerColours.DIM)

func _text(f: Font, t: String, centre_base: Vector2, sz: int, col: Color) -> void:
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(f, Vector2(centre_base.x - w * 0.5, centre_base.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
