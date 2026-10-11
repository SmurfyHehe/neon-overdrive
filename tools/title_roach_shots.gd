extends SceneTree

# Screenshots and draw cost of the title's roaches (menu roaches M7,
# 2026-10-11; not a test, nothing is asserted). Boots Game.tscn onto the title
# (test mode: no splash, no first-launch card), holds the roach clock at a
# moment the schedule says 2-3 are out, and saves to docs/title-kerbside/roaches/:
#   manhole.png     the lid ajar, close, roaches out
#   title.png       the normal title framing at the same moment
#   scare_0_5s.png  the frame 0.5 s after scare 1 (they are running for cover)
# and prints the draw calls of one frame with the roaches and the hole hidden
# and shown, and the mean frame time over a second each way. Needs the real
# renderer (a window opens):
#   set NEON_TEST=1 && godot --path . -s res://tools/title_roach_shots.gd

const OUT := "res://docs/title-kerbside/roaches/"
const LampLife := preload("res://scripts/world/lamp_life.gd")

var t := 0.0
var step := 0
var title: TitleScreen
var busy := -1.0
var frames := 0
var frame_ms := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TEST", "1")
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_TRAFFIC", "0")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://Game.tscn")

func _shot(name: String) -> void:
	var p := ProjectSettings.globalize_path(OUT + name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot: ", p)

func _draws() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))

func _roach_nodes(k: TitleKerbside) -> Array:
	return [k.life_root.get_node(^"Roaches"), k.life_root.get_node(^"VentHole")]

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
	if step >= 20:
		frames += 1
		frame_ms += delta * 1000.0
	if step == 0 and t > 2.0:
		step = 1
		# a moment with 2-3 out, from the schedule
		var tt := 0.0
		while tt < 200.0 and busy < 0.0:
			var n := k.roach_positions(tt).filter(func(r): return r.out).size()
			if n >= 2:
				busy = tt
			tt += 0.05
		print("roaches out at clock %.2f: %d" % [busy, k.roach_positions(busy).filter(func(r): return r.out).size()])
		k.freeze_roaches(true)
		k.set_roach_clock(busy)
		LampLife.freeze_for_shots(0.5)
	elif step == 1 and t > 2.6:
		step = 2
		_shot("title")
		var cam := k.camera
		var vent := k.to_global(TitleKerbside.VENT_AT)
		var near: Vector2 = k.life["roach_near"]
		cam.global_position = vent + Vector3(near.x, 0.0, near.y) * 2.2 + Vector3(0.0, 0.7, 0.0)
		cam.look_at(vent + Vector3(0.0, 0.05, 0.0))
		cam.fov = 40.0
		k.set_process(false)
	elif step == 2 and t > 3.2:
		step = 3
		_shot("manhole")
		k.set_scare(1.0)
		k.set_roach_clock(busy + 0.5)
	elif step == 3 and t > 3.8:
		step = 4
		_shot("scare_0_5s")
		# back to the title framing, live, for the cost
		k.set_process(true)
		k.camera.fov = TitleKerbside.CAM_FOV
		k._place_camera()
		k.set_scare(0.0)
		k.freeze_roaches(false)
		LampLife.freeze_for_shots(-1.0)
		for n in _roach_nodes(k):
			n.visible = false
	elif step == 4 and t > 4.5:
		step = 20
		print("draw calls, roaches hidden: ", _draws())
	elif step == 20 and t > 6.5:
		step = 21
		print("frame time, roaches hidden: %.2f ms over %d frames" % [frame_ms / frames, frames])
		frames = 0
		frame_ms = 0.0
		for n in _roach_nodes(k):
			n.visible = true
	elif step == 21 and t > 7.0:
		step = 22
		print("draw calls, roaches shown: ", _draws())
		frames = 0
		frame_ms = 0.0
	elif step == 22 and t > 9.0:
		step = 23
		print("frame time, roaches shown: %.2f ms over %d frames" % [frame_ms / frames, frames])
		quit()
	return false
