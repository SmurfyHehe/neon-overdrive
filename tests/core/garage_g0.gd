extends SceneTree

# Garage G0 plumbing (2026-10-11), on the real Game.tscn with NEON_GARAGE=1 and a
# throwaway save folder:
#
# Boot
# - a fresh save and each of the 3 slots boot to the dawn card, Continue opens
#   the garage, the whole way in under 3 s of wall clock
# Garage
# - Esc does nothing there; a stretch of sub-30 fps frames never opens the pause
#   screen (the same frames do pause the game on the road)
# - Service car fixes the car, free; Wash car opens the wash and Esc comes back
#   to the garage (not the road)
# - Presence says Garage in there, Driving out here
# - frame cap: the lower of the player's cap and 60, 30 after 5 s idle, any
#   input brings it back
# Go out
# - the car is parked with the engine off, the throttle does nothing, holding
#   the starter starts it
# Mid-night
# - a visit from the forecourt opens the garage, saves the run in under 16 ms;
#   refused (toast signal) while a cop sees the player
# - a 6 a.m. during a chase waits for the chase to end, then the dawn card opens
# - the Polaroid writer scales to 320x180 and lands in the slot's folder
# Old rows
# - no Service car / Wash car button on the pause screen or on Settings, and the
#   car picker is hidden unless the test build switch is on
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/core/garage_g0.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const TestBuild := preload("res://scripts/core/test_build.gd")
const Presence := preload("res://scripts/core/presence.gd")

const BOOT_BUDGET_SECS := 3.0
const TIMEOUT_FRAMES := 1800

var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_GARAGE", "1")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	SaveStore.root = "user://test_garage_g0"
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveDirector.enabled = true
	GameState.title_seen = false
	GameState.garage_seen = false
	_run.call_deferred()

func _run() -> void:
	_pure()

	# ---------- slots: fresh save, then slots 1..3 ----------
	SaveStore.select_slot(2)
	SaveStore.save_wallet(120, 4500)
	SaveStore.select_slot(3)
	SaveStore.save_wallet(0, 900)
	SaveStore.select_slot(1)
	SaveStore.clear_run()
	SaveStore.load_meta()

	var boot_secs: Array[float] = []
	for pass_n in 4:
		var slot_n := 1 if pass_n == 0 else pass_n   # pass 0 = fresh slot 1, then 1, 2, 3
		SaveStore.select_slot(slot_n)
		GameState.garage_seen = false
		var t0 := Time.get_ticks_usec()
		await _boot()
		var gs: GameState = game.game_state
		var reached := await _wait_until(func() -> bool: return gs.state == GameState.State.DAWN)
		_check(reached, "slot %d (pass %d): the dawn card never opened (state %d)" % [slot_n, pass_n, gs.state])
		if not reached:
			continue
		var card: DawnCard = _node("DawnCard")
		_check(card != null and card.visible and card.continue_button != null, "slot %d: the dawn card shows" % slot_n)
		_check(gs.garage_entry == GameState.ENTRY_BOOT and paused, "slot %d: boot entry, tree paused" % slot_n)
		gs.dawn_continue()
		await physics_frame
		var secs := (Time.get_ticks_usec() - t0) / 1000000.0
		boot_secs.append(secs)
		_check(gs.state == GameState.State.GARAGE and _node("GarageScreen").visible and not card.visible,
			"slot %d: Continue opens the garage" % slot_n)
		_check(secs < BOOT_BUDGET_SECS, "slot %d: boot into the garage took %.2f s (budget %.0f)" % [slot_n, secs, BOOT_BUDGET_SECS])
	print("boot into the garage (s): ", boot_secs)

	# ---------- the garage, on the last boot ----------
	var gs: GameState = game.game_state
	var player: PlayerCar = game.player
	var garage: GarageScreen = _node("GarageScreen")
	var flow: GarageFlow = game.garage_flow
	var pause_menu: PauseMenu = _node("PauseMenu")

	_check(Presence.activity == Presence.GARAGE, "Presence says Garage in the garage (%s)" % Presence.activity)
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")) or AudioServer.get_bus_index(&"Music") < 0,
		"the radio plays in the garage")

	# Esc does nothing in the garage.
	gs.toggle_pause()
	_check(gs.state == GameState.State.GARAGE, "Esc must not leave the garage")

	# Auto-pause: slow frames in the garage never open the pause screen...
	gs.auto_pause_on_low_fps = true
	gs._fps_watch.slow_pauses = true
	gs._fps_watch.reset()
	for i in 400:
		gs.feed_frame(0.05)   # 20 fps for 20 s
	_check(gs.state == GameState.State.GARAGE and not pause_menu.visible, "20 fps in the garage must not open the pause screen")

	# Frame cap.
	flow.idle_secs = 0.0
	await physics_frame
	await process_frame
	_check(flow.applied_cap == GarageFlow.cap_for(GraphicsSettings.fps_cap, false),
		"garage cap should be %d, is %d" % [GarageFlow.cap_for(GraphicsSettings.fps_cap, false), flow.applied_cap])
	flow.idle_secs = GarageFlow.IDLE_SECS + 0.1
	await process_frame
	_check(flow.applied_cap == GarageFlow.cap_for(GraphicsSettings.fps_cap, true) and flow.applied_cap <= GarageFlow.IDLE_CAP,
		"idle cap should drop to 30, is %d" % flow.applied_cap)
	var key := InputEventKey.new()
	key.keycode = KEY_DOWN
	key.pressed = true
	flow._input(key)
	await process_frame
	_check(flow.applied_cap == GarageFlow.cap_for(GraphicsSettings.fps_cap, false), "input should bring the cap back (%d)" % flow.applied_cap)

	# Service car: free fix-everything.
	player.health.tyre_wear[2] = 0.5
	player.health.clutch_wear = 0.5
	var bank_before: int = game.wallet.bank
	garage.service_button.pressed.emit()
	_check(player.health.tyre_wear[2] == 0.0 and player.health.clutch_wear == 0.0, "Service car should reset wear")
	_check(game.wallet.bank == bank_before, "Service car is free")

	# Wash car: the wash opens, Esc returns to the garage, not the road.
	garage.wash_button.pressed.emit()
	await physics_frame
	_check(gs.state == GameState.State.WASH and gs.in_garage() and paused, "Wash car opens the wash (state %d)" % gs.state)
	gs.toggle_pause()
	await physics_frame
	_check(gs.state == GameState.State.GARAGE and paused and garage.visible, "Esc in the wash returns to the garage (state %d)" % gs.state)

	# ---------- Go out ----------
	garage.out_button.pressed.emit()
	await physics_frame
	_check(gs.state == GameState.State.PLAYING and not paused, "Go out should return to the road")
	_check(Presence.activity == Presence.DRIVING, "Presence says Driving outside (%s)" % Presence.activity)
	_check(not player.engine_running and flow.parked_off, "the car waits outside with the engine off")
	_check(player.linear_velocity.length() < 0.5, "the parked car is stopped")
	_check(GameState.garage_seen, "garage_seen is set so Restart skips the garage")
	# Throttle does nothing while the engine is off.
	Input.action_press("accelerate")
	await _frames(30)
	Input.action_release("accelerate")
	_check(player.throttle_input == 0.0, "the throttle does nothing with the engine off (%.2f)" % player.throttle_input)
	# The starter starts it.
	Input.action_press("starter")
	await _frames(int(GarageFlow.START_HOLD * 120.0) + 20)
	Input.action_release("starter")
	_check(player.engine_running and not flow.parked_off, "holding the starter starts the engine")
	_check(not player.driver.is_valid(), "the parked-car driver is gone once it is started")

	# ---------- mid-night visit from the forecourt ----------
	# A cop sees the player: refused, with the toast signal.
	var refused := [0]
	gs.pause_refused.connect(func() -> void: refused[0] += 1)
	SaveStore.begin_chase()
	_check(not gs.open_garage(), "the garage refuses while a cop sees the player")
	_check(refused[0] == 1 and gs.state == GameState.State.PLAYING, "refusal shows the toast signal and stays on the road")
	# A 6 a.m. in the chase waits for it to end.
	gs.request_dawn(3)
	_check(gs.state == GameState.State.PLAYING and gs.dawn_pending, "dawn waits while a cop sees the player")
	SaveStore.end_chase()
	_check(await _wait_until(func() -> bool: return gs.state == GameState.State.DAWN), "the dawn card opens when the chase ends")
	_check(gs.dawn_night == 3 and gs.garage_entry == GameState.ENTRY_DAWN, "dawn card carries the night that ended")
	var card2: DawnCard = _node("DawnCard")
	_check(card2.title_label.text == "NIGHT 3 IS OVER", "card text: %s" % card2.title_label.text)
	gs.dawn_continue()
	gs.leave_garage()
	await physics_frame
	_check(gs.state == GameState.State.PLAYING, "back on the road after the dawn visit")

	# Forecourt: opens, and the entry (save + polaroid hook) is cheap.
	var saves_before: int = game.saver.saves
	var t := Time.get_ticks_usec()
	var opened := gs.open_garage()
	var entry_ms := (Time.get_ticks_usec() - t) / 1000.0
	_check(opened and gs.state == GameState.State.GARAGE and gs.garage_entry == GameState.ENTRY_FORECOURT, "forecourt visit opens the garage")
	_check(game.saver.saves == saves_before + 1, "entering the garage saves the run (%d -> %d)" % [saves_before, game.saver.saves])
	print("garage entry (save + polaroid hook): %.2f ms" % entry_ms)
	_check(entry_ms < 16.0, "garage entry took %.2f ms (budget 16)" % entry_ms)
	gs.leave_garage()
	await physics_frame

	# ---------- polaroid writer ----------
	var img := Image.create(640, 360, false, Image.FORMAT_RGB8)
	img.fill(Color("#FF8A1F"))
	t = Time.get_ticks_usec()
	var wrote := GarageFlow.write_polaroid(img, "test_car")
	var write_ms := (Time.get_ticks_usec() - t) / 1000.0
	print("polaroid write: %.2f ms" % write_ms)
	var path := GarageFlow.polaroid_path("test_car")
	_check(wrote and FileAccess.file_exists(path), "the Polaroid lands in the slot folder (%s)" % path)
	var back := Image.load_from_file(path)
	_check(back != null and back.get_size() == Vector2i(320, 180), "the Polaroid is 320x180")
	_check(not GarageFlow.write_polaroid(null, "x") and not GarageFlow.write_polaroid(Image.new(), "x"), "no image, no Polaroid")

	# ---------- the old rows are gone ----------
	var texts: Array[String] = []
	_collect_buttons(pause_menu, texts)
	_check(not texts.has("Service car") and not texts.has("Wash car"), "no Service car / Wash car on the pause screen")
	var st: SettingsScreen = pause_menu.settings
	var settings_texts: Array[String] = []
	_collect_buttons(st, settings_texts)
	for s in settings_texts:
		_check(not s.begins_with("Service car") and s != "Wash car", "Settings still has a '%s' button" % s)
	_check(not st.car_option.get_parent().visible, "the car picker is hidden outside the test build")
	TestBuild.forced = 1
	var st2 := SettingsScreen.new(gs)
	root.add_child(st2)
	await physics_frame
	_check(st2.car_option.get_parent().visible and st2.car_restart_button.visible, "the car picker shows with the test build switch on")
	TestBuild.forced = -1
	st2.queue_free()

	# Garage entry is off without the flag: nothing opens.
	gs.garage_enabled = false
	_check(not gs.open_garage(), "open_garage does nothing when the garage is off")
	gs.request_dawn(9)
	_check(not gs.dawn_pending and gs.state == GameState.State.PLAYING, "request_dawn does nothing when the garage is off")

	_finish()

# ---------- pure bits ----------
func _pure() -> void:
	_check(GarageFlow.cap_for(0, false) == 60, "no player cap -> 60")
	_check(GarageFlow.cap_for(144, false) == 60, "144 cap -> 60")
	_check(GarageFlow.cap_for(45, false) == 45, "45 cap stays 45")
	_check(GarageFlow.cap_for(0, true) == 30 and GarageFlow.cap_for(144, true) == 30, "idle -> 30")
	_check(GarageFlow.cap_for(24, true) == 24, "an idle 24 cap stays 24 (lower of the two)")

# ---------- helpers ----------
func _boot() -> void:
	if game != null and is_instance_valid(game):
		root.remove_child(game)
		game.free()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await physics_frame

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_until(cond: Callable) -> bool:
	for i in TIMEOUT_FRAMES:
		if cond.call():
			return true
		await physics_frame
	return false

func _node(cls: String) -> Node:
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null

func _collect_buttons(n: Node, out: Array[String]) -> void:
	if n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_collect_buttons(c, out)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)

func _finish() -> void:
	Input.action_release("accelerate")
	Input.action_release("starter")
	if game != null and is_instance_valid(game):
		root.remove_child(game)
		game.free()
	if failures.is_empty():
		print("garage_g0: all checks passed")
		quit(0)
	else:
		print("garage_g0: %d check(s) failed" % failures.size())
		quit(1)
