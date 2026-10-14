extends SceneTree

# Screenshots and draw cost of the title's lamp life (menu litter M2,
# 2026-10-11; not a test, nothing is asserted). Boots Game.tscn onto the title
# (test mode: no splash, no first-launch card, settings untouched), then saves
# to user://title_litter_shots/:
#   gust_held.png   the title at rest wind with every gust and the bat held
#                   mid-run (LampLife.freeze_for_shots)
#   wind2_held.png  the same with the turbo wind at 2.0
#   live.png        nothing held, whatever the clock gives
#   steam.png       the manhole close up
#   lamp.png        the lamp head close up (moths and bat, bat held)
# and prints the draw calls of one frame with the lamp-life root hidden and
# shown. Needs the real renderer (a window opens):
#   set NEON_TEST=1 && godot --path . -s res://tools/title_litter_shots.gd

const LampLife := preload("res://scripts/world/lamp_life.gd")
const OUT := "user://title_litter_shots"

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
		print("lamp life enabled: ", LampLife.enabled)
	elif step == 1 and t > 2.5:
		step = 2
		_shot("gust_held")
		k.set_title_wind(2.0)
	elif step == 2 and t > 3.2:
		step = 3
		_shot("wind2_held")
		k.set_title_wind(0.6)
		LampLife.freeze_for_shots(-1.0)
		# let the easing finish, then a live frame
	elif step == 3 and t > 7.0:
		step = 4
		_shot("live")
		# draw calls with and without
		k.life_root.visible = false
	elif step == 4 and t > 7.5:
		step = 5
		print("draw calls, lamp life hidden: ", _draws())
		k.life_root.visible = true
	elif step == 5 and t > 8.0:
		step = 6
		print("draw calls, lamp life shown: ", _draws())
		LampLife.freeze_for_shots(0.5)
		var cam := k.camera
		var vent := k.to_global(TitleKerbside.VENT_AT)
		cam.global_position = vent + Vector3(-1.5, 1.0, 3.2)
		cam.look_at(vent + Vector3(0.0, 1.0, 0.0))
		cam.fov = 45.0
		k.set_process(false)
	elif step == 6 and t > 8.6:
		step = 7
		_shot("steam")
		var cam := k.camera
		var head := k.to_global(k._lamp_xf.origin + k._lamp_xf.basis * LampLife.HEAD)
		cam.global_position = head + Vector3(-4.0, -5.0, 8.0)
		cam.look_at(head + Vector3(0.0, -1.7, 0.5))
		cam.fov = 40.0
	elif step == 7 and t > 9.2:
		step = 8
		_shot("lamp")
		quit()
	return false
