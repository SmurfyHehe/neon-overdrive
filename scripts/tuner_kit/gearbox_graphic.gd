class_name GearboxGraphic
extends PageGraphic

# Gearbox page: the gearing chart (road speed across, rpm up, a line per gear,
# top speed marked), stock dashed in steel blue under yours in sodium, and the
# next notch as a faint amber top-speed marker.

var chart: GearingChart

func _ready() -> void:
	chart = GearingChart.new()
	chart.title = "GEARING"
	chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chart)

func show_setup(s: Dictionary, st: Dictionary, c := {}) -> void:
	super.show_setup(s, st, c)
	if chart == null or s.is_empty():
		return
	var est: Dictionary = c.get("est", {})
	var sest: Dictionary = c.get("stock_est", {})
	chart.set_gearing(s, st, float(c.get("wheel_r", 0.34)), float(est.get("top", 0.0)), float(sest.get("top", 0.0)))
	var pest: Dictionary = c.get("preview_est", {})
	if not pest.is_empty() and absf(float(pest.top) - float(est.get("top", 0.0))) > 0.5:
		chart.markers.append({"x": float(pest.top), "colour": Color(TunerColours.VALUE, 0.45), "label": ""})
	chart.queue_redraw()
