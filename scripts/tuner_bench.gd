class_name TunerBench
extends Node3D

# The car on the bench (Tuner UI overhaul PR 1, 2026-10-08; proposal "Tuner &
# Mechanic UI overhaul", signed off by Roy). While the Tuner is open the game is
# paused with your car in the street; this swings a tuner camera to a shop angle
# for the page you are on, dims the street, puts a work light on the car and
# draws the part you are tuning in sodium over it.
#
# It reuses the live car, so there is no second 3D view (integrated graphics).
# Built as its own node so the Stage E garage can reuse the shots and outlines:
# give it a car and a page id, call open(), then show(page). Nothing here knows
# about TunerScreen.
#
# Shots are car-local (the car faces -Z, the driver's side is -X) so they work
# for any body; the outlines come from the wheel nodes and the body's size metas,
# so they fit any car built by CarSpec.build_wheels() and a builder that sets
# "half_w" / "half_l" (all of ours do).

const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")

## page id -> {dir (from the part toward the camera, car-local), look (the
## part, car-local metres), fit (half width and half height in metres, as seen
## from the camera, that must fit the car window),
## fov (degrees), part (the outline's tag)}. The distance is worked out from fit
## and the window, so the shot holds on any screen size.
const SHOTS := {
	"setup":      {"dir": Vector3(-0.62, 0.3, -0.72), "look": Vector3(0.0, 0.55, -0.1), "fit": Vector2(2.4, 0.95), "fov": 40.0, "part": ""},
	"tyres":      {"dir": Vector3(-0.72, 0.16, -0.67), "look": Vector3(-0.3, 0.36, -1.25), "fit": Vector2(1.25, 0.6), "fov": 40.0, "part": "TYRES"},
	"suspension": {"dir": Vector3(1.0, 0.1, 0.0), "look": Vector3(0.0, 0.5, 0.0), "fit": Vector2(2.5, 0.8), "fov": 40.0, "part": "SPRINGS AND BARS"},
	"gearbox":    {"dir": Vector3(-0.86, 0.12, 0.5), "look": Vector3(0.0, 0.32, -0.15), "fit": Vector2(1.4, 0.7), "fov": 40.0, "part": "GEARBOX"},
	"engine":     {"dir": Vector3(-0.42, 0.6, -0.68), "look": Vector3(0.0, 0.65, -1.35), "fit": Vector2(1.3, 0.8), "fov": 40.0, "part": "ENGINE"},
	"diff":       {"dir": Vector3(-0.5, 0.22, 0.84), "look": Vector3(0.0, 0.36, 1.25), "fit": Vector2(1.25, 0.7), "fov": 40.0, "part": "DIFFERENTIAL"},
	"brakes":     {"dir": Vector3(-0.8, 0.18, -0.57), "look": Vector3(-0.85, 0.36, -1.25), "fit": Vector2(0.8, 0.55), "fov": 40.0, "part": "BRAKES"},
	"aero":       {"dir": Vector3(0.97, 0.08, 0.22), "look": Vector3(0.0, 0.62, 0.0), "fit": Vector2(2.5, 0.8), "fov": 40.0, "part": "WINGS"},
	"assists":    {"dir": Vector3(-0.2, 0.42, -0.88), "look": Vector3(-0.2, 0.95, -0.3), "fit": Vector2(1.1, 0.7), "fov": 40.0, "part": "DASH"},
	"mechanic":   {"dir": Vector3(0.6, 0.42, -0.68), "look": Vector3(0.0, 0.5, 0.0), "fit": Vector2(2.4, 1.0), "fov": 40.0, "part": ""},
	"sound":      {"dir": Vector3(-0.42, 0.25, 0.87), "look": Vector3(0.0, 0.45, 2.1), "fit": Vector2(1.0, 0.55), "fov": 40.0, "part": "EXHAUST"},
	"advanced":   {"dir": Vector3(0.62, 0.32, 0.72), "look": Vector3(0.0, 0.55, 0.0), "fit": Vector2(2.4, 1.0), "fov": 40.0, "part": ""},
}
const BLEND_RATE := 6.0       # 1/s: ~0.5 s from one shot to the next
## How much of the street's light is left while the bench is up.
const STREET_EXPOSURE := 0.55
const WORK_LIGHT_ENERGY := 6.0

var car: Vehicle
## The camera that was current before open(), made current again on close().
var prev_camera: Camera3D
var cam: Camera3D
var work_light: SpotLight3D
var fill_light: OmniLight3D
var overlay: CanvasLayer
var outline: PartOutline
var page := "setup"
var is_open := false
## The part of the screen the car is framed in, in pixels; the screen sets it
## to the gap between its panels. Empty = the whole viewport.
var frame_rect := Rect2()

var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _fov := 42.0
var _hidden: Array[CanvasItem] = []
var _hidden_layers: Array[CanvasLayer] = []

func _init(target: Vehicle) -> void:
	car = target

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.name = "TunerCamera"
	cam.near = 0.05
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	# Work light: a warm lamp up and in front of the car, as over a bench. The
	# fill keeps the far side from going black. Both are off until open().
	work_light = SpotLight3D.new()
	work_light.name = "WorkLight"
	work_light.light_color = Color(1.0, 0.9, 0.76)
	work_light.light_energy = WORK_LIGHT_ENERGY
	work_light.spot_range = 14.0
	work_light.spot_angle = 38.0
	work_light.shadow_enabled = false
	work_light.visible = false
	add_child(work_light)
	fill_light = OmniLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_color = Color(0.62, 0.7, 0.86)  # cool bounce off the night
	fill_light.light_energy = 1.2
	fill_light.omni_range = 9.0
	fill_light.shadow_enabled = false
	fill_light.visible = false
	add_child(fill_light)
	overlay = CanvasLayer.new()
	overlay.layer = 9  # over the HUD, under the Tuner (10)
	overlay.visible = false
	add_child(overlay)
	outline = PartOutline.new(self)
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(outline)

## Takes over the view: tuner camera current, street dimmed, work light on, the
## HUD layers hidden. `hide_layers` are CanvasLayers to hide while open.
func open(hide_layers: Array = []) -> void:
	if is_open:
		return
	is_open = true
	prev_camera = get_viewport().get_camera_3d()
	if prev_camera == cam:
		prev_camera = null
	var env: Environment = null
	if prev_camera != null and prev_camera.environment != null:
		env = prev_camera.environment
	elif get_world_3d() != null:
		env = get_world_3d().environment
	if env != null:
		# The camera's own copy: the street's environment is left alone.
		var dim: Environment = env.duplicate()
		dim.tonemap_exposure = env.tonemap_exposure * STREET_EXPOSURE
		cam.environment = dim
	if prev_camera != null:
		cam.cull_mask = prev_camera.cull_mask
	_hidden_layers = []
	for l in hide_layers:
		if l is CanvasLayer and l.visible:
			l.visible = false
			_hidden_layers.append(l)
	snap()
	cam.current = true
	work_light.visible = true
	fill_light.visible = true
	overlay.visible = true

## Gives the view back to the camera that had it.
func close() -> void:
	if not is_open:
		return
	is_open = false
	work_light.visible = false
	fill_light.visible = false
	overlay.visible = false
	cam.current = false
	if prev_camera != null and is_instance_valid(prev_camera):
		prev_camera.current = true
	for l in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true
	_hidden_layers = []

## Swings to a page's shot (blends there over ~0.5 s) and outlines its part.
func show_page(id: String) -> void:
	page = id if SHOTS.has(id) else "setup"
	outline.build(page)

## Jumps straight to the current page's shot (tests, screenshots).
func snap() -> void:
	var s: Dictionary = SHOTS[page]
	_eye = shot_eye(page)
	_look = s.look
	_fov = s.fov
	_place(1.0)

## Where the camera sits for a page, car-local: back along the shot's direction
## until its fit radius fills the car window (the smaller of its two sides).
func shot_eye(id: String) -> Vector3:
	var s: Dictionary = SHOTS[id]
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var win := frame_rect.size if frame_rect.has_area() else vp
	var tan_v := tan(deg_to_rad(float(s.fov)) * 0.5)
	var tan_h := tan_v * vp.x / maxf(vp.y, 1.0)
	# the window's share of each half-angle, with a little air round the part
	var tv := tan_v * win.y / maxf(vp.y, 1.0) * 0.9
	var th := tan_h * win.x / maxf(vp.x, 1.0) * 0.9
	var fit: Vector2 = s.fit
	var dist := maxf(fit.x / maxf(th, 0.05), fit.y / maxf(tv, 0.05))
	return Vector3(s.look) + Vector3(s.dir).normalized() * dist

func _process(delta: float) -> void:
	if not is_open:
		return
	_place(1.0 - exp(-BLEND_RATE * delta))
	outline.queue_redraw()

func _place(k: float) -> void:
	var s: Dictionary = SHOTS[page]
	_eye = _eye.lerp(shot_eye(page), k)
	_look = _look.lerp(s.look, k)
	_fov = lerpf(_fov, s.fov, k)
	var basis := _car_basis()
	var origin := car.global_position
	var eye := origin + basis * _eye
	var look := origin + basis * _look
	cam.fov = _fov
	cam.global_position = eye
	if not eye.is_equal_approx(look):
		cam.look_at(look, basis.y)
	_frame_offsets(eye.distance_to(look))
	# The work light hangs over the car's front quarter on the camera's side,
	# so whatever the shot, the side you see is lit.
	var side := signf(_eye.x) if absf(_eye.x) > 0.1 else -1.0
	work_light.global_position = origin + basis * Vector3(side * 1.6, 3.4, _eye.z * 0.35)
	work_light.look_at(origin + basis * Vector3(0.0, 0.4, _look.z), basis.y)
	fill_light.global_position = origin + basis * Vector3(-side * 2.4, 1.6, -_eye.z * 0.3)

## Shifts the lens so the look point lands in the middle of frame_rect instead
## of the middle of the screen.
func _frame_offsets(dist: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var frame_px := frame_rect.get_center()
	if not frame_rect.has_area() or vp.y <= 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		return
	var half_h := dist * tan(deg_to_rad(cam.fov) * 0.5)
	var half_w := half_h * vp.x / vp.y
	var ndc := (frame_px - vp * 0.5) / (vp * 0.5)   # -1..1, y down
	cam.h_offset = -ndc.x * half_w
	cam.v_offset = ndc.y * half_h

## The car's heading with the body roll and pitch taken out, so shots stay level.
func _car_basis() -> Basis:
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	return Basis.looking_at(fwd.normalized(), Vector3.UP)

## Where a car-local point is on screen.
func project(local: Vector3) -> Vector2:
	return cam.unproject_position(car.global_position + _car_basis() * local)

func behind_camera(local: Vector3) -> bool:
	return cam.is_position_behind(car.global_position + _car_basis() * local)

## The four wheel centres in car-local space (level basis), FL, FR, RL, RR.
func wheel_centres() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var inv := _car_basis().inverse()
	for w in [car.front_left_wheel, car.front_right_wheel, car.rear_left_wheel, car.rear_right_wheel]:
		var n: Node3D = w.wheel_node if w != null and w.wheel_node != null else w
		out.append(inv * (n.global_position - car.global_position) if n != null else Vector3.ZERO)
	return out

## The part being tuned, drawn over the car in sodium: lines worked out in car
## space and projected every frame, so they stay on the part as the camera moves.
class PartOutline extends Control:
	var bench: TunerBench
	## Polylines in car-local space, and where the part's tag goes.
	var lines: Array[PackedVector3Array] = []
	var tag := ""
	var tag_at := Vector3.ZERO

	func _init(b: TunerBench) -> void:
		bench = b

	func build(id: String) -> void:
		lines = []
		tag = String(SHOTS.get(id, {}).get("part", ""))
		var wc := bench.wheel_centres()
		var r: float = float(bench.car.get("front_tire_radius")) if bench.car.get("front_tire_radius") != null else 0.34
		var visual: Node3D = bench.car.get("chassis_visual")
		var hw: float = visual.get_meta("half_w", 0.9) if visual != null else 0.9
		var hl: float = visual.get_meta("half_l", 2.2) if visual != null else 2.2
		match id:
			"tyres":
				for i in 4:
					lines.append(_circle(wc[i], r + 0.04))
					if i < 2:
						lines.append(_circle(wc[i], r * 0.7))
				tag_at = wc[0] + Vector3(0.0, r + 0.2, 0.0)
			"brakes":
				for i in 4:
					lines.append(_circle(wc[i], r * 0.62))
					lines.append(_circle(wc[i], r * 0.3))
				tag_at = wc[0] + Vector3(0.0, r + 0.2, 0.0)
			"suspension":
				for i in 4:
					lines.append(_coil(wc[i] + Vector3(signf(-wc[i].x) * 0.18, 0.0, 0.0), 0.5))
				lines.append(PackedVector3Array([wc[0] + Vector3(0, 0.25, 0), wc[1] + Vector3(0, 0.25, 0)]))
				lines.append(PackedVector3Array([wc[2] + Vector3(0, 0.25, 0), wc[3] + Vector3(0, 0.25, 0)]))
				tag_at = wc[0] + Vector3(0.0, 0.85, 0.0)
			"gearbox":
				lines.append_array(_box(Vector3(0.0, 0.32, -0.35), Vector3(0.2, 0.13, 0.42)))
				lines.append(PackedVector3Array([Vector3(0.0, 0.3, 0.07), Vector3(0.0, 0.3, (wc[2].z + wc[3].z) * 0.5)]))
				tag_at = Vector3(0.0, 0.62, -0.35)
			"engine":
				lines.append_array(_box(Vector3(0.0, 0.62, (wc[0].z + wc[1].z) * 0.5 - 0.05), Vector3(hw * 0.62, 0.24, 0.45)))
				tag_at = Vector3(0.0, 1.05, (wc[0].z + wc[1].z) * 0.5)
			"diff":
				var rz := (wc[2].z + wc[3].z) * 0.5
				var ry := (wc[2].y + wc[3].y) * 0.5
				lines.append_array(_box(Vector3(0.0, ry, rz), Vector3(0.18, 0.13, 0.15)))
				lines.append(PackedVector3Array([wc[2], wc[3]]))
				lines.append(_circle(wc[2], r * 0.45))
				lines.append(_circle(wc[3], r * 0.45))
				tag_at = Vector3(0.0, ry + 0.4, rz)
			"aero":
				var deck := Vector3(0.0, 1.0, hl - 0.25)
				lines.append(_rect_xz(deck, hw * 0.85, 0.18))
				lines.append(_rect_xz(Vector3(0.0, 0.16, -hl + 0.12), hw * 0.9, 0.12))
				tag_at = deck + Vector3(0.0, 0.35, 0.0)
			"assists":
				lines.append(_rect_xy(Vector3(-0.1, 0.98, -0.35), hw * 0.75, 0.1))
				tag_at = Vector3(0.0, 1.35, -0.35)
			"sound":
				var tips: Array = visual.get_meta("exhaust_tips", []) if visual != null else []
				for t in tips:
					lines.append(_circle_z(t.pos, float(t.r) + 0.05))
				tag_at = (Vector3(tips[0].pos) if not tips.is_empty() else Vector3(0.0, 0.4, hl)) + Vector3(0.0, 0.35, 0.0)
			_:
				# Whole car: corner brackets round the body.
				lines.append_array(_brackets(Vector3(0.0, 0.62, 0.0), Vector3(hw + 0.08, 0.62, hl + 0.08)))
				tag = ""
		queue_redraw()

	func _draw() -> void:
		if bench == null or not bench.is_open:
			return
		for l in lines:
			var pts := PackedVector2Array()
			for p in l:
				if bench.behind_camera(p):
					pts = PackedVector2Array()
					break
				pts.append(bench.project(p))
			if pts.size() >= 2:
				# a dark edge first, so the line reads on the sodium paint too
				draw_polyline(pts, Color(UiTheme.DUSK, 0.8), 6.0, true)
				draw_polyline(pts, SODIUM, 2.5, true)
		if tag != "" and not bench.behind_camera(tag_at):
			var at := bench.project(tag_at)
			var f := UiTheme.font("strong")
			var w := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			if bench.frame_rect.has_area():  # keep the tag inside the car window
				var r := bench.frame_rect.grow(-8.0)
				at.x = clampf(at.x, r.position.x + w * 0.5 + 6.0, r.end.x - w * 0.5 - 6.0)
				at.y = clampf(at.y, r.position.y + 20.0, r.end.y - 8.0)
			draw_rect(Rect2(at + Vector2(-w * 0.5 - 6.0, -18.0), Vector2(w + 12.0, 22.0)), Color(UiTheme.DUSK, 0.85))
			draw_rect(Rect2(at + Vector2(-w * 0.5 - 6.0, 4.0), Vector2(w + 12.0, 2.0)), SODIUM)
			draw_string(f, at + Vector2(-w * 0.5, 0.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, AMBER)

	# Shapes, all car-local.
	static func _circle(c: Vector3, r: float, n := 28) -> PackedVector3Array:  # in the wheel's plane (YZ)
		var out := PackedVector3Array()
		for i in n + 1:
			var a := TAU * i / n
			out.append(c + Vector3(0.0, sin(a) * r, cos(a) * r))
		return out

	static func _circle_z(c: Vector3, r: float, n := 20) -> PackedVector3Array:  # facing back (XY)
		var out := PackedVector3Array()
		for i in n + 1:
			var a := TAU * i / n
			out.append(c + Vector3(cos(a) * r, sin(a) * r, 0.0))
		return out

	static func _coil(base: Vector3, height: float, turns := 5, r := 0.08) -> PackedVector3Array:
		var out := PackedVector3Array()
		var n := turns * 12
		for i in n + 1:
			var a := TAU * turns * i / n
			out.append(base + Vector3(cos(a) * r, height * i / n, sin(a) * r))
		return out

	static func _rect_xz(c: Vector3, hx: float, hz: float) -> PackedVector3Array:
		return PackedVector3Array([c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz), c + Vector3(hx, 0, hz), c + Vector3(-hx, 0, hz), c + Vector3(-hx, 0, -hz)])

	static func _rect_xy(c: Vector3, hx: float, hy: float) -> PackedVector3Array:
		return PackedVector3Array([c + Vector3(-hx, -hy, 0), c + Vector3(hx, -hy, 0), c + Vector3(hx, hy, 0), c + Vector3(-hx, hy, 0), c + Vector3(-hx, -hy, 0)])

	static func _box(c: Vector3, h: Vector3) -> Array[PackedVector3Array]:
		var out: Array[PackedVector3Array] = []
		out.append(_rect_xz(c - Vector3(0, h.y, 0), h.x, h.z))
		out.append(_rect_xz(c + Vector3(0, h.y, 0), h.x, h.z))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(PackedVector3Array([c + Vector3(sx * h.x, -h.y, sz * h.z), c + Vector3(sx * h.x, h.y, sz * h.z)]))
		return out

	## Corner brackets on the box's 8 corners, a quarter of each edge long.
	static func _brackets(c: Vector3, h: Vector3) -> Array[PackedVector3Array]:
		var out: Array[PackedVector3Array] = []
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := c + Vector3(sx * h.x, sy * h.y, sz * h.z)
					out.append(PackedVector3Array([p - Vector3(sx * 0.3, 0, 0), p, p - Vector3(0, 0, sz * 0.3)]))
					out.append(PackedVector3Array([p, p - Vector3(0, sy * 0.25, 0)]))
		return out
