extends SceneTree

# Screenshots and draw cost of the title wall's graffiti (M10, 2026-10-11;
# not a test, nothing is asserted). Boots Game.tscn onto the title (test
# mode: no splash, no first-launch card, settings untouched), then saves to
# user://title_graffiti_shots/:
#   before.png   the title with the wall art hidden (litter gust held)
#   after.png    the same frame with it shown
#   wall.png     the wall close up, from the sidewalk
#   shutter.png  the shutter with its stencil and the tag over it
# and prints the draw calls of one frame with the wall art hidden and shown,
# and the atlas's size in video memory. Needs the real renderer (a window
# opens):
#   set NEON_TEST=1 && godot --path . -s res://tools/title_graffiti_shots.gd

const LampLife := preload("res://scripts/world/lamp_life.gd")
const Graffiti := preload("res://scripts/world/graffiti.gd")
const OUT := "user://title_graffiti_shots"

var t := 0.0
var step := 0
var title: TitleScreen

func _initialize() -> void:
	OS.set_environment("NEON_TEST", "1")
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_TRAFFIC", "0")
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://Game.tscn")

func _shot(name: String) -> void:
	var p := OUT.path_join(name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot: ", ProjectSettings.globalize_path(p))

func _draws() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))

func _process(delta: float) -> bool:
	var game := current_scene
	if game == null or game.get("game_state") == null:
		return false
	if title == null:
		for c in game.get_children():
			if c is TitleScreen:
				title = c
		return false
	var k := title.kerbside
	if k == null or not title.visible:
		return false
	t += delta
	if step == 0 and t > 2.0:
		step = 1
		LampLife.freeze_for_shots(0.5)
		k.wall_art.visible = false
		print("graffiti enabled: ", Graffiti.enabled, ", items: ", k.graffiti_items.size())
	elif step == 1 and t > 2.6:
		step = 2
		_shot("before")
		print("draw calls, wall art hidden: ", _draws())
		k.wall_art.visible = true
	elif step == 2 and t > 3.2:
		step = 3
		_shot("after")
		print("draw calls, wall art shown: ", _draws())
		var tex := load(Graffiti.ATLAS_PATH) as Texture2D
		var img := tex.get_image()
		print("atlas: %d x %d, format %d, %d mipmaps, %.2f MB in VRAM" % [tex.get_width(), tex.get_height(), img.get_format(), img.get_mipmap_count(), float(img.get_data().size()) / 1048576.0])
		# the wall close up, from the sidewalk a little left of the lamp
		var cam := k.camera
		var wall_z := -RoadChunkBuilder.CURB_W - RoadChunkBuilder.SIDEWALK_W
		cam.global_position = k.to_global(Vector3(-5.5, 1.6, wall_z + 9.0))
		cam.look_at(k.to_global(Vector3(-3.6, 3.0, wall_z)))
		cam.fov = 55.0
		k.set_process(false)
	elif step == 3 and t > 3.8:
		step = 4
		_shot("wall")
		var cam := k.camera
		var wall_z := -RoadChunkBuilder.CURB_W - RoadChunkBuilder.SIDEWALK_W
		cam.global_position = k.to_global(Vector3(0.6, 1.5, wall_z + 4.2))
		cam.look_at(k.to_global(Vector3(1.9, 1.7, wall_z)))
		cam.fov = 45.0
	elif step == 4 and t > 4.4:
		step = 5
		_shot("shutter")
		quit()
	return false
