extends SceneTree

# Screenshots and draw cost of the title's street life and rats (menu street
# life M8 + rats M9, 2026-10-11; not a test, nothing is asserted). Boots
# Game.tscn onto the title (test mode: no splash, no first-launch card), holds
# the street clock at a moment a rat sits up in the lamp light, and saves:
#   docs/title-kerbside/street_life/
#     title.png            the title framing, everything at rest
#     neighbour.png        the window lit, blind up, the shape standing there
#     neighbour_close.png  the same, close
#     pigeons_rest.png     the four on the lamp arm, close
#     pigeons_lift.png     the flock 0.9 s into the lift-off, title framing
#     cat.png              on the shutter box, close
#     cat_drop.png         0.3 s into the drop
#     bags_flies.png       the bin bags and the flies, close
#     bags_wind2.png       the same in the gale (flies scattered, bags ruffled)
#     shoes.png            the sneakers on the wire, close
#     shoes_wrap.png       the gale wrapping them round the wire
#   docs/title-kerbside/rats/
#     sitting.png          a rat sitting up in the lamp light, close
#     title.png            the title framing at that moment
# then prints the draw calls of one frame with the street life, the rats and
# the roaches hidden and shown, and the mean frame time over a second each
# way, plus the time probe's reading. Needs the real renderer (a window opens):
#   set NEON_TEST=1 && godot --path . -s res://tools/title_street_shots.gd

const OUT := "res://docs/title-kerbside/street_life/"
const OUT_RATS := "res://docs/title-kerbside/rats/"
const LampLife := preload("res://scripts/world/lamp_life.gd")

var t := 0.0
var step := 0
var title: TitleScreen
var sit_at := -1.0
var sit_pos := Vector2.ZERO
var frames := 0
var frame_ms := 0.0
var next_at := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TEST", "1")
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_TRAFFIC", "0")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_RATS))
	change_scene_to_file("res://Game.tscn")

func _shot(dir: String, name: String) -> void:
	var p := ProjectSettings.globalize_path(dir + name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot: ", p)

func _draws() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))

func _life_nodes(k: TitleKerbside) -> Array:
	var out := []
	for n in ["Neighbour", "Pigeons", "Cat", "BinBags", "Flies", "Wire", "Rats"]:
		out.append(k.life_root.get_node(NodePath(n)))
	return out

## Puts the set's camera close on a point (set space), looking at it.
func _close(k: TitleKerbside, from: Vector3, at: Vector3, fov := 30.0) -> void:
	k.set_process(false)
	k.camera.position = from
	k.camera.look_at(k.to_global(at))
	k.camera.fov = fov

func _wide(k: TitleKerbside) -> void:
	k.camera.fov = TitleKerbside.CAM_FOV
	k._place_camera()

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
	if t < next_at:
		return false
	match step:
		0:
			if t < 2.0:
				return false
			# a moment a rat sits up in the light, from the schedule
			var tt := 12.0
			while tt < 400.0 and sit_at < 0.0:
				for r in k.rat_positions(tt):
					if r.out and r.sit > 0.5:
						sit_at = tt + 0.3
						sit_pos = r.pos
				tt += 0.05
			print("rat sitting at clock %.2f, x %.2f" % [sit_at, sit_pos.x])
			k.freeze_roaches(true)
			k.set_roach_clock(sit_at)
			LampLife.freeze_for_shots(0.5)
			print("time probe known: %s" % k.probe_known())
		1:
			_shot(OUT, "title")
			_shot(OUT_RATS, "title")
			var rat := Vector3(sit_pos.x, TitleRats.WALK_Y + 0.08, sit_pos.y)
			_close(k, rat + Vector3(-0.9, 0.35, 1.4), rat, 22.0)
		2:
			_shot(OUT_RATS, "sitting")
			_close(k, TitleStreetLife.WINDOW_AT + Vector3(-1.5, -0.6, 5.0), TitleStreetLife.WINDOW_AT, 28.0)
		3:
			k.wake_neighbour()
			k.set_roach_clock(sit_at + 1.5)
			# the roaches and rats move on 1.5 s too; the shot is about the window
		4:
			_shot(OUT, "neighbour_close")
			k.set_process(true)
			_wide(k)
		5:
			_shot(OUT, "neighbour")
			TitleStreetLife.set_uniform("neighbour", "wake_t", -1.0)
			var arm := Vector3(TitleStreetLife.PERCH_X, TitleStreetLife.PERCH_Y, 0.0)
			_close(k, arm + Vector3(-1.2, -0.6, 3.6), arm + Vector3(0.0, 0.05, 0.0), 24.0)
		6:
			_shot(OUT, "pigeons_rest")
			k.set_process(true)
			_wide(k)
			k.lift_pigeons()
			k.set_roach_clock(sit_at + 1.5 + 0.9)
		7:
			_shot(OUT, "pigeons_lift")
			TitleStreetLife.set_uniform("pigeon", "lift_t", -1.0)
			_close(k, TitleStreetLife.CAT_SIT + Vector3(-1.6, -0.3, 3.0), TitleStreetLife.CAT_SIT + Vector3(0.0, 0.15, 0.0), 22.0)
		8:
			_shot(OUT, "cat")
			k.leave_cat()
			k.set_roach_clock(sit_at + 2.4 + 0.3)
		9:
			_shot(OUT, "cat_drop")
			TitleStreetLife.set_uniform("cat", "leave_t", -1.0)
			TitleStreetLife.set_uniform("cat", "back_t", -1.0)
			var bags := Vector3(5.0, 0.45, -2.15)
			_close(k, bags + Vector3(-1.8, 0.9, 3.4), bags, 26.0)
		10:
			_shot(OUT, "bags_flies")
			k.set_title_wind(2.0)
			k._ease_wind(0.016)
			k.set_roach_clock(sit_at + 2.7 + 0.6)
		11:
			_shot(OUT, "bags_wind2")
			k.set_title_wind(TitleKerbside.WIND_REST)
			k._ease_wind(5.0)
			var hang := TitleStreetLife.wire_point(TitleStreetLife.WIRE_SHOES)
			var shoes := hang + Vector3(0.0, -0.35, 0.0)
			_close(k, shoes + Vector3(-0.3, -0.9, 3.2), shoes, 24.0)
		12:
			_shot(OUT, "shoes")
			k.set_title_wind(2.0)
			k._ease_wind(0.016)
			k.wrap_shoes()
			k.set_roach_clock(sit_at + 3.3 + 0.8)
		13:
			_shot(OUT, "shoes_wrap")
			# back to the title framing, live, for the cost
			TitleStreetLife.set_uniform("wire", "wrap_t", -1.0)
			k.set_title_wind(TitleKerbside.WIND_REST)
			k._ease_wind(5.0)
			k.set_process(true)
			_wide(k)
			k.freeze_roaches(false)
			LampLife.freeze_for_shots(-1.0)
			for n in _life_nodes(k):
				n.visible = false
			k.life_root.get_node(^"Roaches").visible = false
			step = 19
		20:
			print("draw calls, street life + rats + roaches hidden: ", _draws())
			frames = 0
			frame_ms = 0.0
			next_at = t + 2.0
			step = 21
			return false
		21:
			print("frame time, hidden: %.2f ms over %d frames" % [frame_ms / maxf(1.0, frames), frames])
			for n in _life_nodes(k):
				n.visible = true
			k.life_root.get_node(^"Roaches").visible = true
			next_at = t + 0.5
			step = 22
			return false
		22:
			print("draw calls, shown: ", _draws())
			frames = 0
			frame_ms = 0.0
			next_at = t + 2.0
			step = 23
			return false
		23:
			print("frame time, shown: %.2f ms over %d frames" % [frame_ms / maxf(1.0, frames), frames])
			print("time probe known: %s, shader time now %.2f" % [k.probe_known(), k.shader_time(k.street_clock())])
			quit()
			return false
	step += 1
	next_at = t + 0.6
	return false
