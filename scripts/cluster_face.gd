class_name ClusterFace
extends Node2D

# The printed faces of a car's instrument cluster (interiors pass, 2026-10-08).
# Roy: every car has its OWN cluster, and its numbers come from that car's
# CarSpec. This draws every dial face of one cluster (bezel ring, face, ticks,
# numerals, red zone, legends) into one SubViewport texture that CockpitFrame
# puts on a single quad, so a whole cluster is one draw call; the needles stay
# 3D so they sit in front of the face with a little parallax.
#
# The layout comes from InteriorStyle (cluster.gauges): each gauge has a kind,
# a centre and radius in metres on the cluster plate, and a sweep. Scales come
# from scales_for(): the tach ends at the car's max_rpm rounded up to the next
# 1000 with the red zone from its red line, the speedo ends at the car's top
# speed in its top gear rounded up to the next 20 km/h, the boost gauge runs to
# the turbo's turbo_boost_max. The face is drawn once (UPDATE_ONCE) and again
# only when a scale changes (a tune that adds boost, say).

const PX_PER_M := 2600.0
## Needle angles: a value of 0 points at `start` degrees and 1 at start - sweep
## (clockwise as the driver sees it), 0 degrees = 3 o'clock.
const START_DEG := 225.0

var plate := Vector2(0.34, 0.13)      # metres
var gauges: Array = []                # InteriorStyle cluster.gauges
var look := {}                        # colours and font sizes (InteriorStyle cluster)
var scales := {}                      # from scales_for()
var font: Font

## What a cluster's dials read to, from the car itself.
static func scales_for(p: Vehicle) -> Dictionary:
	var max_rpm := maxf(p.max_rpm, 1000.0)
	var tach_k := int(ceil(max_rpm / 1000.0 - 0.001))
	if float(tach_k) * 1000.0 - max_rpm < 400.0:
		tach_k += 1   # a little dial past the limiter, like a real tach
	var top_ratio := 1.0
	if p.gear_ratios.size() > 0:
		top_ratio = p.gear_ratios[p.gear_ratios.size() - 1]
	var r := maxf(p.rear_tire_radius, 0.2)
	var top_ms := max_rpm / maxf(top_ratio * p.final_drive, 0.1) * TAU * r / 60.0
	var top_kmh := top_ms * 3.6
	var speedo := int(ceil((top_kmh + 15.0) / 20.0)) * 20
	return {
		"tach_max": float(tach_k) * 1000.0,
		"red_from": max_rpm * Hud.RED_FROM,
		"speedo_max": float(speedo),
		"boost_max": maxf(p.turbo_boost_max, 0.0),
	}

## Where a value 0..1 puts a needle, radians about the dial's z (Godot's z
## rotation, counter-clockwise positive).
static func needle_angle(t: float, sweep_deg: float, start_deg := START_DEG) -> float:
	return deg_to_rad(start_deg - sweep_deg * clampf(t, 0.0, 1.0) - 90.0)

func image_size() -> Vector2i:
	return Vector2i(int(plate.x * PX_PER_M), int(plate.y * PX_PER_M))

func _ready() -> void:
	if font == null:
		font = ThemeDB.fallback_font

func _px(m: Vector2) -> Vector2:
	# plate metres (origin at the plate centre, y up) to image pixels
	return Vector2((m.x + plate.x * 0.5) * PX_PER_M, (plate.y * 0.5 - m.y) * PX_PER_M)

func _col(key: String, fallback: Color) -> Color:
	return look.get(key, fallback)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(image_size())), _col("plate", Color("#10141C")))
	for g in gauges:
		if g.get("needs_boost", false) and float(scales.get("boost_max", 0.0)) <= 0.0:
			continue
		_dial(g)

func _dial(g: Dictionary) -> void:
	var c := _px(g.at)
	var r: float = g.r * PX_PER_M
	var sweep: float = g.get("sweep", 270.0)
	var start: float = g.get("start", START_DEG)
	var face := _col("face", Color("#0E1424"))
	var ink := _col("ink", Color("#FFC066"))
	var ring := _col("ring", Color("#C9CED6"))
	var red := _col("red", Color("#E5262B"))
	# chrome bezel, then the face
	draw_circle(c, r * 1.08, ring)
	draw_circle(c, r * 1.02, _col("ring_dark", Color("#2A2E36")))
	draw_circle(c, r, face)
	var kind: String = g.kind
	var major := 0
	var minor := 1
	var labels: Array = []
	var red_from := 2.0
	var legend := ""
	match kind:
		"tach":
			var k := int(float(scales.tach_max) / 1000.0)
			major = k
			minor = 2
			for i in k + 1:
				labels.append([float(i) / k, str(i)])
			red_from = float(scales.red_from) / float(scales.tach_max)
			legend = "x1000 r/min"
		"speedo":
			var mx := int(scales.speedo_max)
			var step := 20 if mx <= 200 else 40
			major = mx / step
			minor = 2
			for i in major + 1:
				labels.append([float(i) / major, str(i * step)])
			legend = "km/h"
		"boost":
			major = 4
			minor = 2
			var bm := maxf(float(scales.get("boost_max", 1.0)), 0.1)
			labels = [[0.0, "-1"], [1.0 / (bm + 1.0), "0"], [1.0, "%.1f" % bm]]
			legend = "BOOST bar"
		"water":
			major = 2
			labels = [[0.0, "C"], [1.0, "H"]]
			red_from = 0.85
		"fuel":
			major = 2
			labels = [[0.0, "E"], [1.0, "F"]]
		"oil":
			major = 2
			labels = [[0.0, "0"], [1.0, "8"]]
			legend = "OIL"
		"volt":
			major = 2
			labels = [[0.0, "8"], [1.0, "16"]]
	# red zone
	if red_from < 1.0:
		var a0 := deg_to_rad(-(start - sweep * red_from))
		var a1 := deg_to_rad(-(start - sweep))
		draw_arc(c, r * 0.86, a0, a1, 24, red, r * 0.10, true)
	# ticks
	var n := maxi(major * minor, 1)
	for i in n + 1:
		var t := float(i) / n
		var a := deg_to_rad(-(start - sweep * t))
		var is_major := i % minor == 0
		var r0 := r * (0.78 if is_major else 0.84)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * r0, c + dir * r * 0.93, ink if is_major else Color(ink, 0.7), maxf(r * (0.035 if is_major else 0.018), 1.5), true)
	# numerals
	var fs := int(clampf(r * 0.20, 12.0, 34.0))
	for pair in labels:
		var lab: String = pair[1]
		var t: float = pair[0]
		var a := deg_to_rad(-(start - sweep * t))
		var p := c + Vector2(cos(a), sin(a)) * r * 0.60
		var w := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, p + Vector2(-w * 0.5, fs * 0.36), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	if legend != "":
		var ls := int(clampf(r * 0.11, 10.0, 20.0))
		var lw := font.get_string_size(legend, HORIZONTAL_ALIGNMENT_CENTER, -1, ls).x
		draw_string(font, c + Vector2(-lw * 0.5, r * 0.42), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, Color(ink, 0.8))
	var title: String = g.get("title", "")
	if title != "":
		var ts := int(clampf(r * 0.12, 10.0, 18.0))
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, ts).x
		draw_string(font, c + Vector2(-tw * 0.5, -r * 0.25), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(ink, 0.7))
