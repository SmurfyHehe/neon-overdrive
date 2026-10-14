extends SceneTree

# The garage bay (garage look step 1, 2026-10-14), on the real Game.tscn with
# NEON_GARAGE=1: the first drive goes dawn card -> garage, and then
# - the bay set exists far below the road with a copy of the player's car,
#   and its camera is the one in use;
# - the work lamp is the only light with a shadow, hanging over the car, and
#   it follows the graphics preset (off on Low);
# - every playable car (Roy's rule 2026-10-14) fits: parked in turn, nose,
#   tail and roof are in the picture and the lamp is above the car;
# - Go out frees the bay and the game camera is back.

var tick := 0
var fails := 0
var done := {}

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_GARAGE", "1")
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)

func _once(name: String, at: int) -> bool:
	if tick >= at and not done.has(name):
		done[name] = true
		return true
	return false

func _process(_delta: float) -> bool:
	var game := current_scene
	if game == null or game.get("game_state") == null:
		return false
	tick += 1
	var gs: GameState = game.game_state
	if _once("drive", 30) and gs.state == GameState.State.TITLE:
		gs.start_drive()
	if _once("dawn", 90):
		_check(gs.state == GameState.State.DAWN, "the first drive opens the dawn card, state %d" % gs.state)
		gs.dawn_continue()
	if _once("bay", 120):
		_check(gs.state == GameState.State.GARAGE, "the dawn card leads into the garage, state %d" % gs.state)
		var bay := _find_bay(game)
		_check(bay != null, "the garage bay set exists")
		if bay != null:
			_check_bay(game, bay)
		gs.leave_garage()
	if _once("out", 150):
		_check(gs.state == GameState.State.PLAYING, "Go out is back on the road, state %d" % gs.state)
		_check(_find_bay(game) == null, "the bay is freed on the way out")
		var cam := game.get_viewport().get_camera_3d()
		_check(cam != null and cam.global_position.y > -300.0, "the game camera is back")
		print("garage_bay: ", "PASS" if fails == 0 else "FAIL")
		quit(0 if fails == 0 else 1)
		return true
	return false

func _find_bay(game: Node) -> GarageBay:
	for c in game.get_children():
		if c is GarageBay:
			return c
	return null

func _check_bay(game: Node, bay: GarageBay) -> void:
	_check(bay.camera.current, "the bay camera is the one in use")
	var hud: Node = null
	for c in game.get_children():
		if c is Hud:
			hud = c
	_check(hud != null and not hud.visible, "no HUD over the bay")
	_check(bay.camera.position.z > GarageBay.DOOR_Z, "the camera stands inside the door")
	_check(bay.global_position.y < -300.0, "the bay is clear of the road")
	_check(bay.kind == PlayerCar.chassis_kind(), "the parked car is the player's car")
	_check(bay.car.find_children("*", "MeshInstance3D", true, false).size() > 4, "the parked car has a body and wheels")
	var lights := bay.find_children("*", "Light3D", true, false)
	var shadows := lights.filter(func(l): return l.shadow_enabled)
	_check(shadows.size() == 1 and shadows[0] == bay.lamp_light, "the work lamp is the one light with a shadow")
	# every preset: the lamp shadow is off on Low, on elsewhere
	var was_preset := GraphicsSettings.preset
	for p in GraphicsSettings.PRESETS + ["custom"]:
		GraphicsSettings.preset = p
		bay.apply_graphics()
		_check(bay.lamp_light.shadow_enabled == (p != "low"), "preset %s: lamp shadow %s" % [p, "off" if p == "low" else "on"])
	GraphicsSettings.preset = was_preset
	bay.apply_graphics()
	# every car: headless the window is 64x64, so give the camera the game's
	# shape before asking what is in the picture
	var was_size := root.size
	root.size = Vector2i(1152, 648)
	var was := bay.kind
	for kind in PlayerCars.ids():
		bay.set_car(kind)
		var car := bay.car
		var half_l: float = car.get_meta("half_l")
		for p: Vector3 in [Vector3(0.0, 0.5, -half_l), Vector3(0.0, 0.5, half_l), Vector3(0.0, 1.3, 0.0)]:
			_check(bay.camera.is_position_in_frustum(car.to_global(p)), "%s: the car is in the picture at %s" % [kind, p])
		var lamp := bay.lamp_light.position
		_check(lamp.y > 3.0 and absf(lamp.x - car.position.x) < 0.5 and absf(lamp.z - car.position.z) < half_l, "%s: the work lamp hangs over the car" % kind)
		_check(lamp.z > GarageBay.DOOR_Z and car.position.z - half_l > GarageBay.DOOR_Z, "%s: the car and the lamp are inside the door" % kind)
	bay.set_car(was)
	root.size = was_size
