extends SceneTree
# Special vehicles, S0 shared plumbing (Roy 2026-10-10). T-S1:
#   - every input action has a unique key (the photo-mode group is modal: it
#     reuses the drive keys while photo mode is on, so only photo_mode itself,
#     the global toggle, is compared);
#   - the new keys exist, Ctrl is the one `special` key, the hydraulic keys are
#     the 7 8 9 0 / U I O P columns plus L and K, and they do nothing in other cars;
#   - m1_monster and l1_lowrider are KINDS, flagged special by their data
#     files, and absent from the sprint race list; the garage lists them only
#     once unlocked; the unlock round-trips through the save;
#   - each boots as the player's car and drives 10 s headless: finite, upright,
#     no errors; the chase camera uses the per-kind framing table;
#   - the run end hook fires on the per-kind upside-down thresholds.
#
# Run: <godot> --headless --fixed-fps 120 --path . -s res://tests/car/special_s0.gd
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const RATE := 120
const DRIVE_SECS := 10.0
const SPECIALS := ["m1_monster", "l1_lowrider"]

var logger := Harness.ErrorCounter.new()
var fails := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	_run.call_deferred()

func _run() -> void:
	_keys()
	_lists()
	_run_end()
	for k in SPECIALS:
		await _drive(k)
	OS.set_environment("NEON_CAR", "")
	print("special_s0: %d warning(s)" % logger.warnings)
	if fails == 0:
		print("PASS special_s0")
	else:
		print("FAIL special_s0: %d check(s)" % fails)
	quit(0 if fails == 0 else 1)

func _keys() -> void:
	PhotoMode.ensure_actions()
	SpecialKeys.ensure_actions()
	var by_key := {}
	for a in InputMap.get_actions():
		var name := String(a)
		if name.begins_with("ui_") or (name.begins_with("photo_") and name != "photo_mode"):
			continue
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey:
				var code: int = ev.keycode if ev.keycode != 0 else ev.physical_keycode
				by_key[code] = by_key.get(code, []) + [name]
	for code in by_key:
		var names: Array = by_key[code]
		_check(names.size() == 1, "key %s is bound to %s" % [OS.get_keycode_string(code), names])
	for action in SpecialKeys.KEYS:
		_check(InputMap.has_action(action), "action %s is not registered" % action)
	_check(SpecialKeys.KEYS.special == KEY_CTRL, "special is not Ctrl")
	var want := {"hyd_pump_left": KEY_7, "hyd_pump_front": KEY_8, "hyd_pump_back": KEY_9, "hyd_pump_right": KEY_0,
		"hyd_dump_left": KEY_U, "hyd_dump_front": KEY_I, "hyd_dump_back": KEY_O, "hyd_dump_right": KEY_P,
		"hyd_three": KEY_L, "hyd_dump_all": KEY_K}
	for a in want:
		_check(SpecialKeys.KEYS[a] == want[a], "%s is not on its column key" % a)
	# nothing in ordinary cars; hydraulics only in the lowrider; special in both
	for a in SpecialKeys.KEYS:
		_check(not SpecialKeys.applies(a, "p1_coupe"), "%s does something in the coupe" % a)
		_check(not SpecialKeys.applies(a, "p0_beater"), "%s does something in the beater" % a)
	_check(SpecialKeys.applies("special", "m1_monster") and SpecialKeys.applies("special", "l1_lowrider"), "special should work in both")
	_check(not SpecialKeys.applies("hyd_pump_left", "m1_monster"), "hydraulics work in the truck")
	_check(SpecialKeys.applies("hyd_pump_left", "l1_lowrider") and SpecialKeys.applies("hyd_dump_all", "l1_lowrider"), "hydraulics do not work in the lowrider")
	# the Controls page lists them under "Special vehicles"
	var listed := false
	for g in PauseMenu.controls_groups():
		if g[0] == "Special vehicles":
			listed = g[1].size() == SpecialKeys.LABELS.size()
	_check(listed, "the Controls page does not list the special vehicle keys")
	print("special_s0: %d keys checked" % by_key.size())

func _lists() -> void:
	for k in SPECIALS:
		_check(PlayerCars.is_player_kind(k), "%s is not a player kind" % k)
		_check(PlayerCars.is_special(k), "%s is not special" % k)
		_check(not k in PlayerCars.sprint_ids(), "%s is in the sprint race list" % k)
	_check(not PlayerCars.is_special("p1_coupe"), "the coupe is special")
	_check(PlayerCars.sprint_ids().size() == PlayerCars.ids().size() - SPECIALS.size(), "sprint list size")
	_check(not "m1_monster" in PlayerCars.garage_ids({}), "a locked special is in the garage")
	var g := PlayerCars.garage_ids({"l1_lowrider": true})
	_check("l1_lowrider" in g and not "m1_monster" in g, "garage_ids ignores the unlock map: %s" % [g])
	for k in SPECIALS:
		_check(PlayerCars.CABIN_OFFSET.has(k), "%s has no CABIN_OFFSET entry" % k)
	# save round trip (test saves folder, see TestMode)
	SaveStore.save_special({})
	var unlocked: Dictionary = SaveStore.load_special().unlocked
	_check(unlocked.is_empty(), "the save starts empty: %s" % [unlocked])
	SaveStore.save_special({"m1_monster": true, "l1_lowrider": false})
	unlocked = SaveStore.load_special().unlocked
	_check(unlocked.has("m1_monster") and not unlocked.has("l1_lowrider"), "special.json round trip: %s" % [unlocked])
	SaveStore.save_special({})
	# GameState: --test-mode unlocks every special
	var gs := GameState.new()
	_check(GameState.TestMode.active(), "test mode is not active")
	_check(gs.is_special_unlocked("m1_monster") and gs.is_special_unlocked("l1_lowrider"), "test mode does not unlock every special")
	_check(gs.garage_cars().size() == PlayerCars.ids().size(), "test mode garage does not list every car")
	gs.free()

func _run_end() -> void:
	var cases := {"m1_monster": 2.0, "l1_lowrider": 1.0}
	for k in cases:
		var secs: float = cases[k]
		var r := SpecialRunEnd.new(null, k)
		var fired := [0]
		r.run_ended.connect(func(_w: String) -> void: fired[0] += 1)
		for i in int((secs - 0.2) * RATE):
			r.step(1.0 / RATE, 0.1)
		_check(fired[0] == 0, "%s ended the run 0.2 s early" % k)
		r.step(0.1, 0.9)  # the car rights itself: the clock resets
		for i in int((secs - 0.2) * RATE):
			r.step(1.0 / RATE, 0.1)
		_check(fired[0] == 0, "%s did not reset the upside-down clock" % k)
		for i in int(0.4 * RATE):
			r.step(1.0 / RATE, 0.1)
		_check(fired[0] == 1, "%s fired %d times after %.1f s upside down" % [k, fired[0], secs])
		for i in RATE:
			r.step(1.0 / RATE, 0.1)
		_check(fired[0] == 1, "%s fired again" % k)
		# a tilt just above 0.3 never counts
		var r2 := SpecialRunEnd.new(null, k)
		for i in int(secs * 3.0 * RATE):
			r2.step(1.0 / RATE, 0.35)
		_check(not r2.fired, "%s ended the run at basis.y.y 0.35" % k)
	_check(not SpecialRunEnd.has_limit("p1_coupe"), "the coupe has a flip limit")

func _drive(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	_check(PlayerCar.chassis_kind() == kind, "NEON_CAR=%s picked %s" % [kind, PlayerCar.chassis_kind()])
	var errors_before := logger.errors.size()
	var game: Node = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE * 2:
		await physics_frame
	var p: PlayerCar = game.get("player")
	_check(p != null, "%s: the game has no player" % kind)
	if p == null:
		return
	var cam: ChaseCamera = game.get("camera")
	var fr: Array = ChaseCamera.FRAMING[kind]
	_check(cam != null and absf(cam.base_dist - float(fr[0])) < 0.001 and absf(cam.base_height - float(fr[1])) < 0.001
		and absf(cam.look_ahead - float(fr[2])) < 0.001 and absf(cam.look_height - float(fr[3])) < 0.001,
		"%s: the chase camera does not use its framing" % kind)
	var lane := RoadFrame.unroll(p.global_position).x
	var z0 := RoadFrame.unroll(p.global_position).z
	p.driver = Harness.lane_driver(lane, 1.0, 80.0 / 3.6)
	var t := 0.0
	while t < DRIVE_SECS:
		await physics_frame
		t += 1.0 / RATE
	p.driver = Callable()
	var travel := z0 - RoadFrame.unroll(p.global_position).z
	print("special_s0: %s drove %.0f m in %.0f s, %.0f km/h" % [kind, travel, DRIVE_SECS, Harness.kmh(p.current_speed())])
	_check(travel > 20.0, "%s moved %.1f m in %.0f s" % [kind, travel, DRIVE_SECS])
	_check(Harness.finite(p), "%s has non-finite state" % kind)
	_check(p.global_transform.basis.y.y > 0.95, "%s is not upright after the drive" % kind)
	_check(logger.errors.size() == errors_before, "%s: %d error(s): %s" % [kind, logger.errors.size() - errors_before, logger.errors.slice(errors_before)])
	game.queue_free()
	await physics_frame
	await physics_frame
