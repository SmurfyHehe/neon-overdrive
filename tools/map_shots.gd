extends SceneTree

# Screenshots of the pause Map page for PR reviews (not a test; nothing is
# asserted). Draws MapView into an off-screen viewport at each size, so sizes
# bigger than the screen work. Needs the real renderer (a window opens):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tools/map_shots.gd -- <out dir>
# Writes map_act<1-3>_<w>x<h>.png into <out dir> (default user://map_shots).

const RoadMap := preload("res://scripts/world/road_map.gd")
const MapView := preload("res://scripts/ui/map_view.gd")

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
# Where the car is in each act: [s, dir].
const CARS := {1: [1700.0, 1], 2: [7500.0, -1], 3: [10900.0, 1]}

var jobs: Array = []
var out_dir := "user://map_shots"
var vp: SubViewport
var view: Control
var frame := 0
var job := -1

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	for a in [1, 2, 3]:
		for sz in SIZES:
			jobs.append([a, sz])

func _process(_delta: float) -> bool:
	frame += 1
	if vp != null and frame >= 4:   # let it draw, then grab
		var a: int = jobs[job][0]
		var sz: Vector2i = jobs[job][1]
		var p := out_dir.path_join("map_act%d_%dx%d.png" % [a, sz.x, sz.y])
		vp.get_texture().get_image().save_png(p)
		print("shot: ", ProjectSettings.globalize_path(p))
		vp.queue_free()
		vp = null
	if vp == null:
		job += 1
		if job >= jobs.size():
			quit()
			return false
		var a: int = jobs[job][0]
		var sz: Vector2i = jobs[job][1]
		RoadMap.use(0, a)
		vp = SubViewport.new()
		vp.size = sz
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		view = MapView.new()
		vp.add_child(view)
		var car: Array = CARS[a]
		view.show_place({"road": 0, "s": car[0], "dir": car[1]})
		frame = 0
	return false
