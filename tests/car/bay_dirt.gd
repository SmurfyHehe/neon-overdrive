extends SceneTree

# Engine bay dirt (engine bays 2e, Roy 1509): the bay has its own grime level
# that builds at half the body's rate, is drawn on the Bay mesh while the hood
# is up, goes with the car in the save, and comes off on the wash's second
# page, after the body.
#
# In the game (Harness.boot, the coupe):
#   - 60% of a night's driving leaves the body at 0.6 and the bay at 0.3
#   - Y with the car stopped: the Bay mesh exists and carries grime 0.3; a
#     changed level reaches it; the "dirt" effect off draws 0 there too
#   - the night save's car_live carries bay_dirt; a .cfg path saves it as well
#   - wash: a clean body and a dirty bay opens on the bay page; sweeping it
#     leaves the bay at 0 and the screen closes itself; a dirty body first,
#     then CLEAN goes on to the bay page instead of closing; Esc there keeps
#     the bay's remaining grime and the body's 0
#
# Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/car/bay_dirt.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")

var logger := Harness.ErrorCounter.new()
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	root.size = Vector2i(1280, 720)
	OS.set_environment("NEON_FX", "")   # the dirt flag must be allowed on
	CarDirt.path = CarDirt.path.get_base_dir().path_join("test_bay_dirt.cfg")
	var f := FileAccess.open(CarDirt.path, FileAccess.WRITE)
	f.store_string("")
	f = null
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## Waits t seconds of physics ticks (headless draws frames faster than it ticks).
func _secs(t: float) -> void:
	var until := Engine.get_physics_frames() + int(ceil(t * float(Engine.physics_ticks_per_second)))
	while Engine.get_physics_frames() < until:
		await process_frame

func _tap(action: String) -> void:
	Input.action_press(action)
	await _secs(0.05)
	Input.action_release(action)
	await _secs(0.05)

## Sweeps the sponge over the whole grid until the model says done.
func _sweep(screen: WashScreen) -> void:
	var m := screen.model
	var row := 0.0
	var right := true
	var strokes := 0
	while not m.done and strokes < 100000:
		m.sponge = Vector2(0.0 if right else WashScreen.Model.COLS, row)
		var dir := Vector2.RIGHT if right else Vector2.LEFT
		for i in 200:
			screen.scrub(dir, 0.05)
			strokes += 1
			if m.done:
				break
		row += WashScreen.Model.SPONGE_R
		right = not right
		if row > WashScreen.Model.ROWS + 1.0:
			row = 0.0
			if strokes > 20000:
				break

func _find(game: Node, type) -> Node:
	for c in game.get_children():
		if is_instance_of(c, type):
			return c
	return null

func _run() -> void:
	OS.set_environment("NEON_CAR", "p1_coupe")
	var game := Harness.boot(self, 0, 150.0, 7, 1.0e6)
	await _frames(60)
	var p: PlayerCar = game.get("player")
	var fx: Variant = game.get("fx")
	var gs: GameState = game.get("game_state")
	var screen := _find(game, WashScreen) as WashScreen
	_check(p != null and fx != null and fx.get("dirt") is CarDirt and gs != null and screen != null, "the game did not boot with a player, FxPack.dirt, a game state and a WashScreen")
	if p == null or fx == null or not (fx.get("dirt") is CarDirt) or gs == null or screen == null:
		return _end()
	var dirt: CarDirt = fx.dirt
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 1.0
		c.steering_input = 0.0
	await _secs(1.5)

	# ---- half the body's rate
	_check(dirt.bay_level < 0.001, "a fresh file should start with a clean bay: %s" % dirt.bay_level)
	dirt.add_distance(CarDirt.FULL_NIGHT_METRES * 0.6, false)
	_check(is_equal_approx(dirt.level, 0.6), "body after 60%% of a night: %s" % dirt.level)
	_check(absf(dirt.bay_level - 0.3) < 0.002, "bay after 60%% of a night should be half the body's, 0.3: %s" % dirt.bay_level)
	dirt.add_distance(CarDirt.FULL_NIGHT_METRES * 0.1, true)
	_check(absf(dirt.bay_level - 0.5) < 0.002, "off road counts %sx in the bay too: %s" % [CarDirt.OFF_ROAD_RATE, dirt.bay_level])
	dirt.set_bay_level(0.3)

	# ---- the Bay mesh gets the grime when the hood opens
	var lids := CarLids.of(p)
	var detail := CarDetail.of(p)
	_check(lids != null and detail != null and lids.can_open(), "the stopped coupe has no CarLids/CarDetail or cannot open a lid")
	if lids == null or detail == null:
		return _end()
	_check(detail.node_of("bay") == null, "the Bay mesh should not exist before a lid was ever up")
	await _tap(CarLids.ACTION)
	_check(lids.is_open("hinge_hood"), "Y did not open the hood")
	await _frames(3)
	var bay := detail.node_of("bay") as MeshInstance3D
	_check(bay != null and bay.visible, "no visible Bay mesh with the hood up")
	if bay != null:
		_check(absf(float(bay.get_instance_shader_parameter("grime")) - 0.3) < 0.003, "the Bay mesh should carry grime 0.3 as soon as it is built: %s" % str(bay.get_instance_shader_parameter("grime")))
		dirt.set_bay_level(0.8)
		_check(absf(float(bay.get_instance_shader_parameter("grime")) - 0.8) < 0.003, "a changed bay level should reach the mesh: %s" % str(bay.get_instance_shader_parameter("grime")))
		fx.set_effect("dirt", false)
		_check(float(bay.get_instance_shader_parameter("grime")) == 0.0, "dirt off should draw 0 in the bay: %s" % str(bay.get_instance_shader_parameter("grime")))
		_check(absf(dirt.bay_level - 0.8) < 0.003, "dirt off should keep the bay level: %s" % dirt.bay_level)
		fx.set_effect("dirt", true)
		_check(absf(float(bay.get_instance_shader_parameter("grime")) - 0.8) < 0.003, "dirt on again should draw the bay level: %s" % str(bay.get_instance_shader_parameter("grime")))
		var trim := bay.get_surface_override_material(CarAssembler.surface_index(bay.mesh, "trim")) as ShaderMaterial
		_check(trim != null and trim.shader != null and trim.shader.code.contains("instance uniform float grime"), "the bay's trim surface should wear the shader with the grime uniform")
	lids.shut_all()
	await _secs(CarLids.SHUT_TIME + 0.5)

	# ---- saved with the car
	dirt.set_level(0.4)
	dirt.set_bay_level(0.25)
	var live: Dictionary = game.saver.car_live()
	_check(live.get("car") == "p1_coupe" and absf(float(live.get("bay_dirt", -1.0)) - 0.25) < 0.001, "the night's car_live should carry bay_dirt 0.25: %s" % str(live))
	_check(SaveCore.LIVE_KEYS.has("bay_dirt"), "bay_dirt is not one of SaveCore.LIVE_KEYS, so it would not survive a night")
	_check(dirt.save_state(), "save_state to the .cfg failed")
	var cfg := ConfigFile.new()
	_check(cfg.load(CarDirt.path) == OK and absf(float(cfg.get_value("dirt", "bay", -1.0)) - 0.25) < 0.001, "the .cfg should carry the bay level")
	dirt.set_bay_level(0.0)
	dirt.load_state()
	_check(absf(dirt.bay_level - 0.25) < 0.001, "load_state should bring the bay level back: %s" % dirt.bay_level)

	# ---- the wash: a clean body and a dirty bay opens on the bay page
	dirt.set_level(0.0)
	dirt.set_bay_level(0.5)
	gs.pause()
	gs.open_wash()
	_check(gs.state == GameState.State.WASH and screen.active and screen.model != null, "open_wash did not open the wash")
	if screen.model == null:
		return _end()
	_check(screen.page() == WashScreen.PAGE_BAY, "a clean body with a dirty bay should open on the bay page, got %s" % screen.page())
	_check(absf(screen.model.start - 0.5 * 0.85) < 0.08, "bay grime should come from the bay level: %s" % screen.model.start)
	_sweep(screen)
	_check(screen.model.done, "sweeping the bay should finish it (left %s)" % screen.model.remaining())
	_check(dirt.bay_level == 0.0, "a finished bay wash should leave the bay clean: %s" % dirt.bay_level)
	var closed := false
	for i in 200:
		await process_frame
		if gs.state != GameState.State.WASH:
			closed = true
			break
	_check(closed, "the wash should close itself after the bay is CLEAN")
	_check(not screen.active, "WashScreen should be inactive after closing")

	# ---- body first, then on to the bay, Esc keeps what is left
	dirt.set_level(0.4)
	dirt.set_bay_level(0.3)
	gs.pause()
	gs.open_wash()
	_check(screen.active and screen.page() == WashScreen.PAGE_BODY, "a dirty body should open on the body page, got %s" % screen.page())
	_sweep(screen)
	_check(screen.model.done and dirt.level == 0.0, "sweeping the body should finish it (left %s)" % screen.model.remaining())
	var on_bay := false
	for i in 200:
		await process_frame
		if gs.state != GameState.State.WASH:
			break
		if screen.page() == WashScreen.PAGE_BAY and not screen.model.done:
			on_bay = true
			break
	_check(on_bay and gs.state == GameState.State.WASH, "after CLEAN on the body the wash should go on to the bay page, not close (page %s, state %d)" % [screen.page(), gs.state])
	if on_bay:
		screen.model.sponge = Vector2(WashScreen.Model.COLS / 2.0, WashScreen.Model.ROWS / 2.0)
		screen.scrub(Vector2.RIGHT, 0.3)
		var left := screen.model.remaining()
		_check(left > 0.0 and left < screen.model.start, "one stroke should take some bay grime off, not all: %s of %s" % [left, screen.model.start])
		gs.close_wash()
		_check(not screen.active and absf(dirt.bay_level - left) < 0.001, "Esc on the bay page should keep what is left there: %s vs %s" % [dirt.bay_level, left])
		_check(dirt.level == 0.0, "Esc on the bay page should keep the body clean: %s" % dirt.level)
	OS.set_environment("NEON_CAR", "")
	game.queue_free()
	await _frames(2)
	_end()

func _end() -> void:
	print("bay_dirt: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
