class_name PerformanceCard
extends VBoxContainer

# The performance card (Tuner UI overhaul PR 2), on the right of every Tuner
# page and later beside the car in the Stage E garage: a five-point radar (Top
# speed, Acceleration, Braking, Grip, Handling; stock steel-blue outline, yours
# sodium), a balance seesaw, then one row per stat with its number and the
# change against stock ("▲ +4" green when it helps, "▼ -0.3" red when it hurts,
# "stock" in steel blue). Numbers are estimates ("~") until a Test run measures
# them; any change to the car clears the measured numbers again.
#
# Takes TunerModel.estimate() dictionaries: {top, accel, brake, grip, balance}.

## [key, label, format, worst, best, higher is better]
const ROWS := [
	["top", "Top speed", "~%d km/h", 150.0, 320.0, true],
	["accel", "0-100", "~%.1f s", 10.0, 2.5, false],
	["brake", "100-0", "~%d m", 60.0, 25.0, false],
	["grip", "Grip", "~%.2f g", 0.8, 2.0, true],
	["balance", "Balance", "%s", -1.0, 1.0, true],
]
## A change smaller than this reads "stock".
const STEP := {"top": 0.5, "accel": 0.05, "brake": 0.5, "grip": 0.01}
const DELTA_FMT := {"top": "%+.0f", "accel": "%+.2f", "brake": "%+.0f", "grip": "%+.2f"}

var radar: RadarChart
var seesaw: BalanceSeesaw
var labels := {}
## "vs stock" column: signed difference from the car's factory setup.
var vs := {}
var stock := {}
## Track numbers from a Test run, for the setup they were measured on.
var measured := {}
var measured_for := 0
var note: Label
## "Next notch" line: what one more notch of the focused setting would change.
var next_label: Label

func _ready() -> void:
	add_theme_constant_override("separation", 3)
	var head := HBoxContainer.new()
	add_child(head)
	var title := UiTheme.title_label("PERFORMANCE", 26, UiTheme.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var key := Label.new()
	key.text = "VS STOCK"
	key.add_theme_font_override("font", UiTheme.font("mono"))
	key.add_theme_color_override("font_color", TunerColours.STOCK)
	head.add_child(key)
	add_child(UiTheme.floor_tape())
	radar = RadarChart.new()
	radar.custom_minimum_size = Vector2(230, 176)
	add_child(radar)
	seesaw = BalanceSeesaw.new()
	seesaw.custom_minimum_size = Vector2(230, 58)
	add_child(seesaw)
	for r in ROWS:
		var line := HBoxContainer.new()
		add_child(line)
		var l := Label.new()
		l.add_theme_color_override("font_color", TunerColours.LABEL)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		var d := Label.new()
		d.add_theme_font_override("font", UiTheme.font("mono"))
		line.add_child(d)
		vs[r[0]] = d
		labels[r[0]] = l
	note = Label.new()
	note.text = "~ = estimate"
	note.add_theme_color_override("font_color", TunerColours.DIM)
	add_child(note)
	next_label = Label.new()
	next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_label.custom_minimum_size = Vector2(220, 0)
	next_label.add_theme_font_size_override("font_size", 14)
	next_label.add_theme_color_override("font_color", TunerColours.VALUE)
	add_child(next_label)

## `before` is kept for callers that track the screen-open values; the card
## compares with `stock`.
func set_values(_before: Dictionary, now: Dictionary) -> void:
	if labels.is_empty() or now.is_empty():
		return
	var s := stock if not stock.is_empty() else now
	var any_measured := false
	for r in ROWS:
		var k: String = r[0]
		var v: float = now[k]
		var text: String
		if k == "balance":
			text = "%s  %s" % [r[1], balance_word(v)]
		elif _measured_value(k) != null:
			v = _measured_value(k)
			any_measured = true
			text = "%s  %s" % [r[1], (r[2] as String).replace("~", "") % v]
		else:
			text = "%s  %s" % [r[1], r[2] % v]
		labels[k].text = text
		_set_vs(k, float(now[k]))
	note.text = "measured on the test track" if any_measured else "~ = estimate"
	radar.set_values(radar_values(s), radar_values(now))
	seesaw.set_values(float(now.balance), float(s.balance))

## Shows what one notch on would do (faint dashes on the radar and a line of
## words), or clears it with an empty dictionary.
func set_preview(now: Dictionary, next: Dictionary, what := "") -> void:
	if radar == null:
		return
	if next.is_empty():
		radar.preview = []
		next_label.text = ""
		radar.queue_redraw()
		return
	radar.preview.assign(radar_values(next))
	radar.queue_redraw()
	next_label.text = preview_words(now, next, what)

## "Next notch on Springs rear: ▼ -0.02 g grip, more oversteer" (or no change).
static func preview_words(now: Dictionary, next: Dictionary, what := "") -> String:
	var parts := []
	var names := {"top": "top speed", "accel": "0-100", "brake": "100-0", "grip": "grip"}
	var units := {"top": " km/h", "accel": " s", "brake": " m", "grip": " g"}
	for r in ROWS:
		var k: String = r[0]
		if k == "balance":
			continue
		var d := TunerColours.delta(float(next[k]) - float(now[k]), r[5], DELTA_FMT[k], STEP[k])
		if not d.level:
			parts.append("%s%s %s" % [d.text, units[k], names[k]])
	var db := float(next.balance) - float(now.balance)
	if absf(db) > 0.02:
		parts.append("more oversteer" if db > 0.0 else "more understeer")
	var head := "Next notch" + (" on " + what if what != "" else "") + ": "
	return head + (", ".join(parts) if not parts.is_empty() else "no change the estimates can see")

static func balance_word(b: float) -> String:
	return "Understeer" if b < -0.15 else ("Oversteer" if b > 0.15 else "Neutral")

## The radar's five spokes, 0..1, from an estimate. Handling is grip with the
## balance's distance from neutral taken off: a grippy car that pushes or snaps
## handles worse than its grip says.
static func radar_values(e: Dictionary) -> Array:
	var out := []
	for r in ROWS:
		if r[0] == "balance":
			continue
		out.append(clampf(inverse_lerp(r[3], r[4], float(e[r[0]])), 0.0, 1.0))
	var grip_t: float = out[3]
	out.append(clampf(grip_t * (1.0 - 0.6 * absf(float(e.balance))), 0.0, 1.0))
	return out

func _set_vs(k: String, v: float) -> void:
	var d: Label = vs[k]
	if k == "balance" or not stock.has(k):
		d.text = ""
		return
	var higher_better := true
	for r in ROWS:
		if r[0] == k:
			higher_better = r[5]
	var res := TunerColours.delta(v - float(stock[k]), higher_better, DELTA_FMT[k], STEP[k])
	d.text = res.text
	d.add_theme_color_override("font_color", res.colour)

func _measured_value(k: String) -> Variant:
	var key: String = {"top": "top_speed_kmh", "accel": "t_0_100", "brake": "brake_dist_100", "grip": "peak_lat_g"}.get(k, "")
	return float(measured[key]) if key != "" and measured.has(key) else null
