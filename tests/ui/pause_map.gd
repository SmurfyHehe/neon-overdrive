extends SceneTree

# The pause map (satnav step 1, 2026-10-11), on the real Game.tscn on Loop 1, act 1:
# - the Map row is second, under Resume; Enter opens the page, Esc goes back to
#   the list, M on the page closes the pause
# - the car is put at 8 places round the loop (the start of districts 1, 3, 5, 7
#   and 400 m into 2, 4, 6, 8; every other one heading the other way); each time
#   the arrow is at map_point() of where(), points along the line the way the car
#   faces, and the caption names the district and the loop
# - M from the road: refused (toast signal, no pause) while a cop can see you,
#   otherwise the pause opens straight on the map; nothing on the endless road
# - map is on M and there is no mute key
# - no page node exists while driving
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/ui/pause_map.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const TIMEOUT_FRAMES := 900

var failures: Array[String] = []
var refused := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_TITLE", "0")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_FREEMODE", "0")   # story act 1 (a new save is free)
	OS.set_environment("NEON_ROAD_SEED", "31337")
	SaveStore.root = "user://test_pause_map"
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveStore.select_slot(1)
	SaveStore.clear_run()
	AudioSettings.path = "user://pause_map_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	change_scene_to_file("res://Game.tscn")
	_run.call_deferred()

func _run() -> void:
	var game := await _wait_game()
	if game == null:
		return _finish("Game.tscn never became ready")
	var gs: GameState = game.game_state
	var menu: PauseMenu = _node(game, "PauseMenu")
	await _wait_until(func() -> bool: return gs.state == GameState.State.PLAYING)
	_check(gs.state == GameState.State.PLAYING, "the run should be PLAYING")
	_check(RoadMap.road_id == 0 and RoadMap.act == 1, "should be on Loop 1, act 1 (road %d, act %d)" % [RoadMap.road_id, RoadMap.act])
	gs.pause_refused.connect(func() -> void: refused += 1)

	# ---------- keys ----------
	_check(InputMap.has_action(&"map") and _keycode(&"map") == KEY_M, "map should be bound to M")
	_check(not InputMap.has_action(&"mute"), "there is no mute key (sliders in Settings > Sound)")

	# ---------- nothing while driving ----------
	_check(menu.map_view == null and menu.find_child("MapView", true, false) == null, "no map page exists while driving")

	# ---------- the list ----------
	gs.pause()
	await _frames(2)
	var rows: Array[String] = []
	for b in menu.main_page.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			rows.append((b as Button).text)
	_check(rows.size() > 1 and rows[0] == "Resume" and rows[1] == "Map", "the Map row is second, under Resume; got %s" % [rows])
	_check(menu.map_view == null, "the page is not built until it opens")
	menu.map_button.pressed.emit()
	await _frames(2)
	_check(menu.map_view != null and not menu.main_page.visible, "Map opens the page")
	await _tap(KEY_ESCAPE)
	await _frames(6)
	_check(gs.state == GameState.State.PAUSED and menu.map_view == null and menu.main_page.visible, "Esc on the page goes back to the pause list")
	menu.map_button.pressed.emit()
	await _frames(2)
	await _tap(KEY_M)
	await _frames(4)
	_check(gs.state == GameState.State.PLAYING and menu.map_view == null, "M on the page closes the pause")

	# ---------- the car on the loop, 8 places ----------
	var player: PlayerCar = game.player
	var places := []
	for n in [0, 1, 2, 3, 4, 5, 6, 7]:
		# Even districts (1st, 3rd, ...) at their start, odd ones 400 m in.
		var s := RoadMap.district_start(n) + (1.0 if n % 2 == 0 else 400.0)
		places.append({"n": n, "s": s, "dir": 1 if n % 2 == 0 else -1})
	# Half of them heading the other way, spread over both kinds.
	places[0].dir = -1
	places[2].dir = 1
	places[5].dir = 1
	places[7].dir = -1
	for pl in places:
		var s: float = pl.s
		var dir: int = pl.dir
		var z := float(RoadFrame.origin_index) * 50.0 - s
		var t := RoadFrame.pose(0.0 + TrafficManager.lane_centre(1, dir < 0), RoadFrame.unroll(player.global_position).y, z, 0.0 if dir > 0 else PI)
		game.saver.restore_car(player, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
		game.call("_update_chunk_pool", z)
		game.call("flush_rebuilds")
		await _frames(2)
		var at := RoadMap.where(RoadFrame.unroll(player.global_position).z, -player.global_transform.basis.z)
		var label := "district %d (s %.0f, dir %d)" % [pl.n + 1, s, dir]
		_check(absf(float(at.s) - s) < 5.0 and int(at.dir) == dir, "%s: the test put the car at s %.1f dir %d" % [label, at.s, at.dir])
		gs.pause()
		await _frames(2)
		menu.map_button.pressed.emit()
		await _frames(2)
		var view := menu.map_view
		if view == null:
			_check(false, "%s: the page did not open" % label)
			gs.resume()
			await _frames(2)
			continue
		var want := RoadMap.map_point(0, float(at.s))
		_check(view.arrow_point().distance_to(want) < 1e-5, "%s: arrow at %s, want %s" % [label, view.arrow_point(), want])
		var along := RoadMap.map_point(0, float(at.s) + 30.0) - want   # the line the way s counts
		_check(view.arrow_heading().dot(along) * float(at.dir) > 0.0, "%s: the arrow points the wrong way (heading %s, line %s)" % [label, view.arrow_heading(), along])
		print("%s: arrow %s heading %s caption '%s'" % [label, view.arrow_point().snappedf(0.001), view.arrow_heading().snappedf(0.01), view.caption()])
		var name_want := "%s · Loop 1" % RoadMap.district_info(pl.n).name
		_check(view.caption() == name_want, "%s: caption '%s', want '%s'" % [label, view.caption(), name_want])
		view.close_requested.emit()
		await _frames(3)
		_check(gs.state == GameState.State.PLAYING and menu.map_view == null, "%s: closing the page resumes" % label)

	# ---------- M from the road ----------
	SaveStore.chase_active = true
	var before := refused
	await _tap(KEY_M)
	await _frames(6)
	_check(gs.state == GameState.State.PLAYING and refused == before + 1, "M while a cop can see you is refused (state %d, refusals %d -> %d)" % [gs.state, before, refused])
	SaveStore.chase_active = false
	await _tap(KEY_M)
	await _frames(6)
	_check(gs.state == GameState.State.PAUSED and menu.map_view != null and not menu.main_page.visible, "M opens the pause straight onto the map")
	await _tap(KEY_M)
	await _frames(6)
	_check(gs.state == GameState.State.PLAYING and menu.map_view == null, "M on the map closes the pause")

	# ---------- the endless road has no map ----------
	var was := RoadMap.road_id
	RoadMap.road_id = RoadMap.ENDLESS
	await _tap(KEY_M)
	await _frames(6)
	_check(gs.state == GameState.State.PLAYING and menu.map_view == null, "M does nothing on the endless road")
	RoadMap.road_id = was

	_finish("")

func _keycode(action: StringName) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return KeyBindings.code_of(e as InputEventKey)
	return 0

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_until(cond: Callable) -> bool:
	for i in TIMEOUT_FRAMES:
		if cond.call():
			return true
		await physics_frame
	return false

func _wait_game() -> Node:
	for i in TIMEOUT_FRAMES:
		var game := current_scene
		if game != null and is_instance_valid(game) and game.get("game_state") != null \
				and game.get("player") != null and _node(game, "PauseMenu") != null:
			return game
		await physics_frame
	return null

func _node(game: Node, cls: String) -> Node:
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null

func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		if pressed:
			await _frames(3)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _finish(abort: String) -> void:
	if abort != "":
		failures.append(abort)
	DirAccess.remove_absolute(AudioSettings.path)
	SaveStore.chase_active = false
	for f in failures:
		printerr("FAIL: ", f)
	print("pause_map: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
