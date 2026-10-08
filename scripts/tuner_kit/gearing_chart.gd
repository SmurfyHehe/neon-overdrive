class_name GearingChart
extends CurvePlot

# The gearing chart (Tuner UI overhaul PR 2; Forza and GT7 show one, Tokyo
# Xtreme Racer players ask for it): road speed across, engine rpm up, one line
# per gear from where the previous gear shifts up to the redline, the top speed
# marked. Stock gearing as steel-blue dashes under yours in sodium.

## Builds the chart from two CarSpec dictionaries (gear_ratios, final_drive,
## max_rpm) and a wheel radius in metres. top_kmh / stock_top_kmh, when > 0,
## put a marker at the estimated top speed.
func set_gearing(spec: Dictionary, stock: Dictionary, wheel_r: float, top_kmh := 0.0, stock_top_kmh := 0.0) -> void:
	clear()
	var redline: float = spec.get("max_rpm", 7000.0)
	x_min = 0.0
	y_min = 0.0
	y_max = ceilf(maxf(redline, float(stock.get("max_rpm", redline))) / 1000.0) * 1000.0
	y_step = 2000.0
	x_unit = "km/h"
	y_unit = "rpm"
	var stock_lines := gear_lines(stock, wheel_r)
	var lines := gear_lines(spec, wheel_r)
	var far := 0.0
	for g in stock_lines + lines:
		far = maxf(far, g[g.size() - 1].x)
	x_max = ceilf(maxf(far, maxf(top_kmh, stock_top_kmh)) / 50.0) * 50.0
	x_step = 100.0 if x_max > 250.0 else 50.0
	for g in stock_lines:
		add_series(g, TunerColours.STOCK, 1.5, true)
	for g in lines:
		add_series(g, TunerColours.YOURS, 2.0)
	if stock_top_kmh > 0.0:
		markers.append({"x": stock_top_kmh, "colour": TunerColours.STOCK, "label": ""})
	if top_kmh > 0.0:
		markers.append({"x": top_kmh, "colour": TunerColours.VALUE, "label": "top %d" % roundi(top_kmh)})
	queue_redraw()

## One polyline per gear: (km/h, rpm) from the speed the previous gear reaches
## at the redline (where you shift into this one) to this gear's redline.
static func gear_lines(spec: Dictionary, wheel_r: float) -> Array:
	var out := []
	var gears: Array = spec.get("gear_ratios", [])
	var fd: float = spec.get("final_drive", 4.0)
	var redline: float = spec.get("max_rpm", 7000.0)
	var prev_kmh := 0.0
	for g in gears:
		var k := kmh_at(redline, float(g), fd, wheel_r)
		var start_rpm := redline * prev_kmh / k if k > 0.0 else 0.0
		out.append(PackedVector2Array([Vector2(prev_kmh, start_rpm), Vector2(k, redline)]))
		prev_kmh = k
	return out

static func kmh_at(rpm: float, ratio: float, fd: float, wheel_r: float) -> float:
	return rpm / (ratio * fd) * TAU / 60.0 * wheel_r * 3.6
