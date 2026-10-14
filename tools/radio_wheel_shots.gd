extends SceneTree

# Radio look pass (R5, 2026-10-11): screenshots of the head unit's carousel
# for judging the card art and the text sizes by eye, with the real renderer.
# Marks, in order: off (boot), on (ring in use, just switched on), mid_slide
# (0.11 s into a slide), settled (the slide done, side cards up), rest (4 s
# later: song and artist under the card), card_<id> (each other card,
# settled), off_again, wheel (the eye pitched
# down at the wheel; the wheel screen is on its own branch). Each mark saves
# <mark>_eye.png (the cockpit camera, what the player sees at the window's
# resolution) and <mark>_screen.png (the head unit's own 512x320 texture).
# The tree is paused for each grab so the ring holds still. Writes to
# user://radio_wheel_shots/<WxH>/.
#
#   <godot> --path . --resolution 1280x720 -s res://tools/radio_wheel_shots.gd
#   <godot> --path . --resolution 1920x1080 -s res://tools/radio_wheel_shots.gd

var game: Node
var dir := ""

func _initialize() -> void:
	AudioSettings.path = "user://radio_wheel_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game   # CockpitFrame finds the radio and the clock through current_scene
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	var radio: RadioManager = game.get("radio")
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	var hu: HeadUnit = frame.head_unit
	for i in 60:
		await physics_frame
	var size := root.get_viewport().get_visible_rect().size
	dir = ProjectSettings.globalize_path("user://radio_wheel_shots/%dx%d" % [int(size.x), int(size.y)])
	DirAccess.make_dir_recursive_absolute(dir)
	print("radio starts %s, card %d" % ["off" if radio.station < 0 else "on", radio.card])
	await _shoot(hu, "off")
	radio.next_station()   # off: on at the card, no slide
	for i in 20:
		await physics_frame
	await _shoot(hu, "on")
	radio.next_station()   # one slide
	for i in 7:            # 0.11 s at 60 Hz
		await physics_frame
	print("mid_slide: ring at %.2f of %d" % [hu.ring_pos, hu.ring_target])
	await _shoot(hu, "mid_slide")
	for i in 30:
		await physics_frame
	await _shoot(hu, "settled")
	var waited := 0
	while hu.rest < 0.99 and waited < 1200:   # the rest state comes 4 s after the slide
		await physics_frame
		waited += 1
	print("rest: rest %.2f, playing '%s'" % [hu.rest, radio.now_playing])
	await _shoot(hu, "rest")
	# every other card, settled, for the art sheet
	for i in RadioStations.station_count() - 1:
		radio.next_station()
		for j in 30:
			await physics_frame
		await _shoot(hu, "card_%s" % RadioStations.STATIONS[radio.card].id)
	radio.toggle_power()
	for i in 20:
		await physics_frame
	await _shoot(hu, "off_again")
	# the wheel: the same eye pitched down so the whole rim shows
	var shot := Camera3D.new()
	shot.fov = cam.fov
	shot.near = 0.03
	root.add_child(shot)
	shot.global_transform = cam.global_transform * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-22.0)), Vector3.ZERO)
	shot.make_current()
	await _shoot(hu, "wheel")
	print("wrote ", dir)
	quit(0)

func _shoot(hu: HeadUnit, mark: String) -> void:
	paused = true   # at once, so a mid-slide grab is where the ring was
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_eye.png" % [dir, mark])
	hu.viewport.get_texture().get_image().save_png("%s/%s_screen.png" % [dir, mark])
	paused = false
	print("%s: station %d, card %d, ring %.2f, rest %.2f" % [mark, hu.station, hu.card_station, hu.ring_pos, hu.rest])
