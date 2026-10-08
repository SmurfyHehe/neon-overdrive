class_name DynoGraphic
extends PageGraphic

# Engine page: a dyno sheet, power (kW) and torque (Nm) against rpm. Stock as
# steel-blue dashes, yours in sodium (power) and amber (torque); boost on a
# needle gauge beside it, with the stock boost as its steel-blue tick.

const BOOST_MAX := 1.5

var plot: CurvePlot
var gauge: RotaryDial

func _ready() -> void:
	plot = CurvePlot.new()
	plot.title = "DYNO   power kW / torque Nm"
	plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plot)
	gauge = RotaryDial.new()
	gauge.title = "BOOST"
	gauge.needle = true
	gauge.red_from = 0.85
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gauge)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if plot == null:
		return
	var gw := minf(110.0, size.x * 0.32)
	plot.position = Vector2.ZERO
	plot.size = Vector2(size.x - gw - 4.0, size.y)
	gauge.custom_minimum_size = Vector2(gw, gw)
	gauge.position = Vector2(size.x - gw, (size.y - gw) * 0.4)
	gauge.size = Vector2(gw, gw)

func show_setup(s: Dictionary, st: Dictionary, c := {}) -> void:
	super.show_setup(s, st, c)
	if plot == null or s.is_empty():
		return
	plot.clear()
	var top_rpm := maxf(f("max_rpm"), f("max_rpm", st))
	var sc := curves(st)
	var mc := curves(s)
	var peak := 0.0
	for p in sc.power + mc.power + sc.torque + mc.torque:
		peak = maxf(peak, p.y)
	plot.x_min = 0.0
	plot.x_max = ceilf(top_rpm / 1000.0) * 1000.0
	plot.x_step = 2000.0
	plot.y_min = 0.0
	plot.y_max = ceilf(peak * 1.1 / 100.0) * 100.0
	plot.y_step = 100.0 if plot.y_max <= 500.0 else 200.0
	plot.x_unit = "rpm"
	plot.add_series(sc.torque, TunerColours.STOCK, 1.5, true)
	plot.add_series(sc.power, TunerColours.STOCK, 1.5, true)
	plot.add_series(mc.torque, TunerColours.VALUE, 2.0)
	plot.add_series(mc.power, TunerColours.YOURS, 2.5)
	plot.queue_redraw()
	gauge.set_values(f("turbo_boost_max") / BOOST_MAX, f("turbo_boost_max", st) / BOOST_MAX,
		"%.1f bar" % f("turbo_boost_max") if f("turbo_boost_max") > 0.0 else "none")

## {torque, power}: (rpm, Nm) and (rpm, kW) from 1000 rpm to the redline, with
## boost on the same model as TunerModel.estimate().
static func curves(s: Dictionary) -> Dictionary:
	var shape: Dictionary = s.torque_shape
	var curve := CarSpec.build_torque_curve(shape.low_end, shape.peak_pos, shape.plateau, shape.falloff)
	var max_rpm: float = s.max_rpm
	var boost_k := 1.0 + float(s.get("turbo_gain", 0.45)) * float(s.get("turbo_boost_max", 0.0)) * 0.6
	var tq := PackedVector2Array()
	var pw := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var rpm := lerpf(1000.0, max_rpm, float(i) / n)
		var nm := curve.sample_baked(clampf(rpm / max_rpm, 0.0, 1.0)) * float(s.max_torque) * boost_k
		tq.append(Vector2(rpm, nm))
		pw.append(Vector2(rpm, nm * rpm * TAU / 60.0 / 1000.0))
	return {"torque": tq, "power": pw}
