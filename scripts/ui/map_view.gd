extends Control

# The pause map (satnav step 1, 2026-10-11). A schematic of the loop on a dusk
# plate with a faint printed-map grid, and the player's car on it. Built by the
# pause menu when the Map page opens and freed when it closes, so nothing of it
# exists, or runs, while driving.
#
# It only draws road_map.gd's drawn line: the open districts as a thick amber
# line, the districts not open yet as a faint outline with no names, and the
# seam that bridges them until act 3. Never on it: cops, traffic, racers,
# heat. Exits, stops, a route and race markers are later steps.
#
# No class_name on purpose: the pause menu preloads it.

const RoadMap := preload("res://scripts/world/road_map.gd")

const L := 50.0

signal back_requested    # Esc: back to the pause list
signal close_requested   # M: close the pause, as Resume does

## The car's place when the page opened: {road, s, dir} (RoadMap.where).
var place := {}

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "MapView"

## Takes the car's place and draws it. Called once, on open.
func show_place(at: Dictionary) -> void:
	place = at
	queue_redraw()

# ---------- what the page says (read by the tests) ----------

## The car's point on the drawn map (0-1 square).
func arrow_point() -> Vector2:
	return RoadMap.map_point(int(place.get("road", RoadMap.road_id)), float(place.get("s", 0.0)))

## Unit vector the arrow points along, on the map.
func arrow_heading() -> Vector2:
	return RoadMap.map_heading(int(place.get("road", RoadMap.road_id)), RoadMap.wrap_s(float(place.get("s", 0.0))), int(place.get("dir", 1)))

## Index of the district the car is in.
func district_index() -> int:
	return RoadMap.district_of(floori(RoadMap.wrap_s(float(place.get("s", 0.0))) / L))

## "District 3 · Loop 1"
func caption() -> String:
	var n := district_index()
	if n < 0:
		return ""
	var road_name := String(RoadMap.ROADS[RoadMap.road_id].name)
	return "%s · %s" % [RoadMap.district_info(n).name, road_name]

# ---------- keys ----------

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
	elif event.is_action_pressed(&"map"):
		get_viewport().set_input_as_handled()
		close_requested.emit()

# ---------- drawing ----------

## The square the 0-1 map is drawn in, leaving room for the title and caption.
func plot_rect() -> Rect2:
	var k := _k()
	var top := 110.0 * k
	var bottom := 84.0 * k
	var side := maxf(minf(size.x - 160.0 * k, size.y - top - bottom), 100.0)
	return Rect2(Vector2((size.x - side) * 0.5, top), Vector2(side, side))

func _k() -> float:
	return clampf(size.y / 720.0, 1.0, 3.0)

func _pt(p: Vector2, r: Rect2) -> Vector2:
	return r.position + p * r.size

func _screen_line(from_s: float, to_s: float, r: Rect2) -> PackedVector2Array:
	var pts := RoadMap.map_span(RoadMap.road_id, from_s, to_s, 100.0)
	for i in pts.size():
		pts[i] = _pt(pts[i], r)
	return pts

func _draw() -> void:
	if RoadMap.period <= 0:
		return
	var k := _k()
	var r := plot_rect()
	var road := RoadMap.road_id
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.DUSK)

	# The printed-map grid, a faint square every twelfth of the plot, edge to edge.
	var cell := r.size.x / 12.0
	var grid := Color(UiTheme.NAVY, 0.75)
	var x := r.position.x - ceilf(r.position.x / cell) * cell
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid, 1.0)
		x += cell
	var y := r.position.y - ceilf(r.position.y / cell) * cell
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)
		y += cell
	draw_rect(r.grow(10.0 * k), UiTheme.NAVY, false, 2.0)

	var full := RoadMap.map_full_length(road)
	var open_end := minf(RoadMap.length(), full)

	# Districts not open yet: a faint outline, no names.
	var locked := RoadMap.map_locked_span(road)
	if locked.y > locked.x:
		_stroke(_screen_line(locked.x, locked.y, r), Color(UiTheme.DIM, 0.4), 3.0 * k)
	# The seam: where the open line would meet its start.
	var seam := RoadMap.map_seam(road)
	if seam.size() == 2:
		draw_line(_pt(seam[0], r), _pt(seam[1], r), Color(UiTheme.DIM, 0.45), 1.5 * k, true)
	# The open loop you are on.
	_stroke(_screen_line(0.0, open_end, r), UiTheme.AMBER, 7.0 * k)

	# District ticks and names.
	var centre := r.get_center()
	var road_font := UiTheme.font("road")
	for n in RoadMap.district_count():
		var info := RoadMap.district_info(n)
		var s := RoadMap.district_start(n)
		var p := _pt(RoadMap.map_point(road, s), r)
		var out := (p - centre).normalized()
		var tick_dir := RoadMap.map_heading(road, s, 1).orthogonal()
		var half := 9.0 * k
		draw_line(p - tick_dir * half, p + tick_dir * half, UiTheme.SILVER, 2.0 * k, true)
		var city: bool = String(info.area) == "city"
		var fs := int(round((16.0 if city else 14.0) * k))
		var col: Color = UiTheme.SILVER if city else Color(UiTheme.SILVER, 0.75)
		var text := String(info.name)
		var w := road_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := p + out * (16.0 * k)
		var base := Vector2(at.x if out.x >= 0.0 else at.x - w, at.y + fs * 0.35)
		draw_string(road_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if city:   # a little bolder: the same string drawn again, a pixel over
			draw_string(road_font, base + Vector2(1.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# City crossings.
	for c in RoadMap.junctions():
		var jp := _pt(RoadMap.map_point(road, float(c)), r)
		draw_circle(jp, 5.0 * k, UiTheme.DUSK)
		draw_circle(jp, 3.5 * k, UiTheme.SILVER)

	# The car.
	if not place.is_empty():
		_draw_arrow(_pt(arrow_point(), r), arrow_heading(), 13.0 * k)

	# Title and caption.
	draw_string(UiTheme.font("display"), Vector2(72.0 * k, 90.0 * k), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(56.0 * k)), UiTheme.SODIUM)
	var cap := caption()
	if cap != "":
		var nf := UiTheme.font("numbers")
		var fsz := int(round(22.0 * k))
		var cw := nf.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		draw_string(nf, Vector2((size.x - cw) * 0.5, size.y - 40.0 * k), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, UiTheme.AMBER)

func _draw_arrow(p: Vector2, dir: Vector2, s: float) -> void:
	var side := dir.orthogonal()
	var tri := PackedVector2Array([p + dir * s, p - dir * s * 0.7 + side * s * 0.65, p - dir * s * 0.35, p - dir * s * 0.7 - side * s * 0.65])
	draw_colored_polygon(tri, UiTheme.SODIUM)
	var ring := tri.duplicate()
	ring.append(tri[0])
	draw_polyline(ring, UiTheme.DUSK, 2.0, true)

## A thick line with round joins and ends.
func _stroke(pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, col, width, true)
	for p in pts:
		draw_circle(p, width * 0.5, col)
