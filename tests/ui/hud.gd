extends SceneTree

# HUD v1 and the pause menu's Controls page (headless, silent):
# - the HUD shows speed in km/h (not "units/s"), the gear, A/M, and an RPM bar
#   that goes green -> amber -> red; ENGINE OFF shows when the starter is needed
# - everything sits inside the window and is anchored to it, not placed at fixed
#   pixels from the top-left
# - the Controls page lists every InputMap action, grouped, with the real keys
#   (so it can't drift from the bindings), and Resume brings back the main page
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/ui/hud.gd

const TIMEOUT_TICKS := 60 * 30
const WARM_TICKS := 40

var tick := 0
var small_phase := false
var failures: Array[String] = []

const WINDOW_SIZES := [Vector2i(1152, 648), Vector2i(800, 480)]  # the default window, then a small one

var size_index := 0
var size_set_tick := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	_set_window(WINDOW_SIZES[0])
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick < WARM_TICKS:
		return false
	var p: PlayerCar = game.player
	if small_phase:
		if tick - size_set_tick < 5:
			return false
		_check_layout(game, _find(game, Hud))
		return _end("")
	var hud: Hud = _find(game, Hud)
	var menu: PauseMenu = _find(game, PauseMenu)
	if hud == null or menu == null:
		return _end("Game has no Hud or PauseMenu")

	# --- pure helpers
	_check(Hud.gear_text(-1) == "R" and Hud.gear_text(0) == "N" and Hud.gear_text(3) == "3", "gear_text should give R / N / number")
	_check(Hud.kmh(27.78) == 100, "27.78 m/s should read 100 km/h, got %d" % Hud.kmh(27.78))
	_check(Hud.rpm_colour(0.3) == Hud.RPM_GREEN and Hud.rpm_colour(0.7) == Hud.AMBER and Hud.rpm_colour(0.95) == Hud.RED, "the RPM bar should go green, amber, red")

	# --- live readout
	hud._refresh()
	_check(hud.lbl_speed.text == str(Hud.kmh(p.current_speed())), "speed label '%s' does not match the car (%d km/h)" % [hud.lbl_speed.text, Hud.kmh(p.current_speed())])
	_check(hud.lbl_unit.text == "km/h", "the unit should be km/h")
	_check(hud.lbl_gear.text == Hud.gear_text(p.gear), "gear label '%s' does not match gear %d" % [hud.lbl_gear.text, p.gear])
	_check(hud.lbl_mode.text == PlayerCar.TRANSMISSION_LETTERS[p.transmission_mode()], "the A/S/M label should follow the gearbox")
	p.automatic_transmission = false
	hud._refresh()
	_check(hud.lbl_mode.text == ("M" if p.realistic_clutch else "S"), "a manual gearbox should show S, or M with the clutch pedal")
	_check(hud.rpm_bar.frac >= 0.0 and hud.rpm_bar.frac <= 1.0, "the RPM bar fraction should be 0..1")
	# shift cue: manual, first gear, rpm at the limit
	p.current_gear = 1
	p.motor_rpm = p.max_rpm * 0.97
	hud._refresh()
	_check(hud.rpm_bar.cue, "the shift cue should light near redline in manual")
	p.automatic_transmission = true
	hud._refresh()
	_check(not hud.rpm_bar.cue, "no shift cue in automatic")
	p.current_gear = 0
	p.motor_rpm = p.idle_rpm
	p.realistic_clutch = true
	p.engine_running = false
	hud._refresh()
	_check(hud.lbl_status.text.begins_with("ENGINE OFF"), "ENGINE OFF should show when the engine is stopped (clutch model on)")
	p.engine_running = true
	p.realistic_clutch = false
	hud._refresh()
	_check(hud.lbl_status.text == "", "the status line should clear when the engine runs")

	_check_layout(game, hud)

	# --- Controls page
	var groups := SettingsScreen.controls_groups()
	var names: Array = []
	for g in groups:
		for e in g[1]:
			names.append(e[0])
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_"):
			_check(names.has(String(a)), "action '%s' is missing from the Controls page" % a)
	var titles: Array = groups.map(func(g): return g[0])
	for t in ["Drive", "Gears & Engine", "Camera", "Audio & Radio", "Menus"]:
		_check(titles.has(t), "Controls page has no '%s' group" % t)
	_check(SettingsScreen.keyboard_text("accelerate").contains("W"), "accelerate should list W, got '%s'" % SettingsScreen.keyboard_text("accelerate"))
	_check(SettingsScreen.keyboard_text("pause").contains("Escape"), "pause should list Escape, got '%s'" % SettingsScreen.keyboard_text("pause"))
	_check(SettingsScreen.gamepad_text("accelerate") == "RT", "accelerate should list RT on the pad, got '%s'" % SettingsScreen.gamepad_text("accelerate"))
	var gs: GameState = game.game_state
	gs.pause()
	_check(menu.visible and menu.main_page.visible and not menu.settings.visible, "pausing should open the main page")
	menu.show_settings("Controls")
	_check(menu.settings.visible and menu.settings.current_page == 3, "Settings should open on the Controls page")
	var rows := 0
	for n in menu.settings.controls_scroll.find_children("*", "Label", true, false):
		rows += 1
	_check(rows >= names.size() * 2, "the Controls page should hold a row per action (%d labels for %d actions)" % [rows, names.size()])
	gs.resume()
	gs.pause()
	_check(menu.main_page.visible and not menu.settings.visible, "reopening the pause menu should start on the main page")
	gs.resume()

	# --- the same layout in a smaller window
	_set_window(WINDOW_SIZES[1])
	size_set_tick = tick
	small_phase = true
	return false

func _check_layout(game: Node, hud: Hud) -> void:
	var win := game.get_viewport().get_visible_rect()
	for l in [hud.lbl_speed, hud.lbl_gear, hud.rpm_bar, hud.lbl_info, hud.lbl_hint]:
		var r: Rect2 = l.get_global_rect()
		_check(win.encloses(r) or r.size == Vector2.ZERO, "%s at %s is outside the %s window" % [l.name, r, win.size])
	_check(hud.lbl_hint.text == "Esc: pause · controls", "the hint should be short, got '%s'" % hud.lbl_hint.text)
	_check(hud.lbl_hint.get_global_rect().size.x < win.size.x * 0.3, "the controls hint should be a short line")
	_check(hud.lbl_speed.get_global_rect().position.x > win.size.x * 0.5, "speed should sit on the right of the window")


## A headless window is 64x64, so size the layout through the content scale instead.
func _set_window(sz: Vector2i) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = sz

func _find(n: Node, type: Variant) -> Node:
	for c in n.get_children():
		if is_instance_of(c, type):
			return c
	return null

func _end(reason: String) -> bool:
	if reason != "":
		failures.append(reason)
	for m in failures:
		printerr("FAIL: ", m)
	print("hud: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
