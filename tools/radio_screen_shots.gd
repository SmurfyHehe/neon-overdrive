extends SceneTree

# Saves the head unit's 512 x 320 screen to PNG: in use (ring), at rest with a
# song, and off. Needs the real renderer (no --headless):
#   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 -s res://tools/radio_screen_shots.gd
# Output folder: RADIO_SHOT_DIR (default user://).

var head: HeadUnit
var phase := 0
var frames := 0
var out_dir := ""

func _initialize() -> void:
	out_dir = OS.get_environment("RADIO_SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://")
	head = HeadUnit.new("p1_coupe")
	root.add_child(head)
	head.show_clock("11:42")
	head.show_area("Harbor Row")
	head.show_ring(3, 0, 0.0, 0.0, true)
	head.show_state(3, "01_harlow-drive_dusk", 0.7, 0.0)

func _process(_delta: float) -> bool:
	frames += 1
	if frames < 6:
		return false
	match phase:
		0:
			_save("radio_in_use.png")
			head.area_t = 0.0
			head.show_ring(3, 0, 0.0, 5.0, true)   # 5 s of quiet: at rest
			head.show_ring(3, 0, 0.0, 0.5, true)
			head.show_ring(3, 0, 0.0, 0.5, true)
		1:
			_save("radio_at_rest.png")
			head.show_state(-1, "", 0.0, 0.0)
			head.show_ring(3, 0, 0.0, 0.0, false)
		2:
			_save("radio_off.png")
			quit(0)
	phase += 1
	frames = 0
	return false

func _save(file: String) -> void:
	var img := head.viewport.get_texture().get_image()
	var path := out_dir.path_join(file)
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
