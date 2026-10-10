extends SceneTree

# Names you can read, shots (world step 4, 2026-10-10): boots Game.tscn at
# night and drives the (hidden) player down the road in 60 m steps. At every
# step it looks at the chunks that exist and, the first time it finds one of
# each, photographs it from where a driver would see it: the area gantry and
# the advance sign (three distances each), every kind of painted mark, the
# street blades on the signal masts and the cross street's STOP. Then the head
# unit's area banner and its radio header, on their own.
#
# Looking up what is really in the chunks (not computing where things ought
# to be) means a road layout that puts no bus lane where the plan said still
# gets a shot of the next one.
#
# Env: NAMES_SHOT_DIR (output folder, required), NEON_CLOCK (default 23:30),
# NEON_ROAD_SEED / NEON_HILLS / NEON_CURVES as in the game.
# NEON_CITY_LIGHTS is forced on (the crossing's blades and paint need it).
# Run (real window):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tools/world_names_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")
const WordAtlas := preload("res://scripts/world/word_atlas.gd")
const RoadSigns := preload("res://scripts/world/road_signs.gd")
const SETTLE := 30
const STEP_M := 60.0
const END_S := 1700.0
const LANE_X := RoadChunkBuilder.MEDIAN_GAP + 0.5 * RoadChunkBuilder.LANE_W

enum Mode { SWEEP, SHOOT, UNITS, DONE }

var game: Node
var cam: Camera3D
var frame := 0
var wait_until := 90
var mode := Mode.SWEEP
var s_cursor := 0.0
var out_dir := ""
var seen := {}
var queue: Array = []   # [label, Transform3D, look-at point]
var sheets: Array = []
var hud_hidden := false
var _unit: HeadUnit
var _unit_b: HeadUnit
var _words: Array = []

func _initialize() -> void:
	OS.set_environment("NEON_COCKPIT", "0")
	OS.set_environment("NEON_TEST", "1")
	OS.set_environment("NEON_CITY_LIGHTS", "1")
	if OS.get_environment("NEON_CLOCK") == "":
		OS.set_environment("NEON_CLOCK", "23:30")
	out_dir = OS.get_environment("NAMES_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_words = PlaceNames.atlas_words()
	game = Harness.boot(self, 0, 300.0, 7)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = 1500.0
	root.add_child(cam)

func _process(_delta: float) -> bool:
	frame += 1
	var player: PlayerCar = game.get("player")
	match mode:
		Mode.SWEEP:
			if frame < wait_until:
				_park(player)
				return false
			if s_cursor > 0.0:
				_scan()
			if not queue.is_empty():
				mode = Mode.SHOOT
				wait_until = frame + SETTLE
				return false
			if s_cursor >= END_S:
				mode = Mode.UNITS
				_head_unit_shots()
				wait_until = frame + 25
				return false
			s_cursor += STEP_M
			_park(player)
			wait_until = frame + 25
		Mode.SHOOT:
			_park(player)
			var shot: Array = queue[0]
			cam.global_transform = shot[1]
			cam.current = true
			if frame < wait_until:
				return false
			if not hud_hidden:
				_hide_hud(root)
				hud_hidden = true
				return false
			var img := root.get_viewport().get_texture().get_image()
			var name := "%02d_%s" % [sheets.size(), shot[0]]
			img.save_png(out_dir.path_join(name + ".png"))
			sheets.append([name, img])
			print("shot ", name)
			queue.remove_at(0)
			wait_until = frame + SETTLE
			if queue.is_empty():
				mode = Mode.SWEEP
				wait_until = frame + 10
		Mode.UNITS:
			if frame >= wait_until:
				_unit.viewport.get_texture().get_image().save_png(out_dir.path_join("head_unit_radio.png"))
				_unit_b.viewport.get_texture().get_image().save_png(out_dir.path_join("head_unit_area.png"))
				print("head unit shots saved")
				_sheet()
				quit(0)
				return true
	return false

func _park(player: PlayerCar) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.freeze = true
	player.visible = false
	player.global_transform = RoadFrame.pose(LANE_X, 0.6, _z(), 0.0)
	player.reset_physics_interpolation()
	if mode == Mode.SWEEP:
		var t := RoadFrame.pose(LANE_X, 1.4, _z(), 0.0)
		cam.global_transform = t
		cam.current = true

## Looks through every chunk that exists for something not photographed yet.
func _scan() -> void:
	for chunk in game.get_children():
		if not chunk.has_node("RoadPaint"):
			continue
		var ci: int = chunk.get_meta("chunk_index")
		var paint := chunk.get_node("RoadPaint") as MultiMeshInstance3D
		_marks(paint, "")
		var signs := chunk.get_node("NameSigns") as MultiMeshInstance3D
		var kind := RoadChunkBuilder.name_sign_kind(ci)
		if kind != "" and signs.multimesh.visible_instance_count > 0 and not seen.has("sign_%d" % ci):
			seen["sign_%d" % ci] = true
			for k in signs.multimesh.visible_instance_count:
				var cd := signs.multimesh.get_instance_custom_data(k)
				if int(round(cd.a)) != RoadSigns.PANEL:
					continue
				var xf := signs.global_transform * signs.multimesh.get_instance_transform(k)
				var n := -xf.basis.x.normalized()
				var r := xf.basis.z.normalized()
				var dists := [70.0, 28.0, 12.0] if kind == "gantry" else [60.0, 22.0]
				var lateral := 6.0 if kind == "gantry" else 8.5
				for d in dists:
					var at: Vector3 = xf.origin + n * float(d) - r * lateral
					at.y = xf.origin.y - (4.7 if kind == "gantry" else 2.8)
					queue.append(["%s_chunk%d_%03dm" % [kind, ci, int(d)], Transform3D(Basis(), at).looking_at(xf.origin, Vector3.UP), xf.origin])
	var j: Variant = game.get("junction")
	if j is Node3D and not seen.has("junction"):
		var jn := j as Node3D
		if jn.has_node("StreetNames") and jn.get_node("StreetNames").multimesh.visible_instance_count > 0:
			var near := absf(Junction.centre_z() - _z()) < 140.0
			if near:
				seen["junction"] = true
				var sm := (jn.get_node("StreetNames") as MultiMeshInstance3D)
				var xf0 := sm.global_transform * sm.multimesh.get_instance_transform(0)
				var n0 := -xf0.basis.x.normalized()
				var at0 := xf0.origin + n0 * 16.0
				at0.y = xf0.origin.y - 4.7
				queue.append(["street_blade_main_masts", Transform3D(Basis(), at0).looking_at(xf0.origin, Vector3.UP), xf0.origin])
				var xf2 := sm.global_transform * sm.multimesh.get_instance_transform(2)
				var n2 := -xf2.basis.x.normalized()
				var at2 := xf2.origin + n2 * 14.0
				at2.y = xf2.origin.y - 2.2
				queue.append(["street_blade_cross_masts", Transform3D(Basis(), at2).looking_at(xf2.origin, Vector3.UP), xf2.origin])
				var stops := (jn.get_node("StopPaint") as MultiMeshInstance3D)
				_marks(stops, "cross_")


func _marks(mmi: MultiMeshInstance3D, prefix: String) -> void:
	var mm := mmi.multimesh
	for k in mm.visible_instance_count:
		var cd := mm.get_instance_custom_data(k)
		var layer := int(round(cd.r))
		var word: String = _words[layer] if layer >= 0 and layer < _words.size() else "?"
		var kind := prefix + word.replace("#", "arrow_").replace(" ", "_")
		if seen.has(kind):
			continue
		seen[kind] = true
		var xf := mmi.global_transform * mm.get_instance_transform(k)
		var back := xf.basis.z.normalized()   # toward the driver: text reads away from them
		for d in [20.0, 9.0]:
			var at: Vector3 = xf.origin + back * float(d)
			at.y = xf.origin.y + 1.4
			queue.append(["paint_%s_%dm" % [kind, int(d)], Transform3D(Basis(), at).looking_at(xf.origin, Vector3.UP), xf.origin])

func _head_unit_shots() -> void:
	# two head units, on their own, in a SubViewport each: the banner and the radio
	_unit = HeadUnit.new("p1_coupe")
	_unit_b = HeadUnit.new("p1_coupe")
	root.add_child(_unit)
	root.add_child(_unit_b)
	_unit.show_state(0, "", 0.5, 0.0)
	_unit_b.show_state(0, "", 0.5, 0.0)
	_unit.show_clock("11:30")
	_unit_b.show_clock("11:30")
	_unit_b.show_area(PlaceNames.area_name("residential"))

func _sheet() -> void:
	if sheets.is_empty():
		return
	var w: int = sheets[0][1].get_width() / 3
	var h: int = sheets[0][1].get_height() / 3
	var cols := 3
	var rows := ceili(float(sheets.size()) / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in sheets.size():
		var im: Image = sheets[i][1]
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out_dir.path_join("sheet.png"))
	print("sheet: ", sheets.size(), " shots")

## No HUD over the shots: every CanvasLayer in the tree goes dark.
func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_hud(c)

## Road-space z for road metre s_cursor: the floating origin moves by whole
## chunks as the player goes (RoadFrame.s_at is its inverse).
func _z() -> float:
	return float(RoadFrame.origin_index) * RoadChunkBuilder.CHUNK_LEN - s_cursor
