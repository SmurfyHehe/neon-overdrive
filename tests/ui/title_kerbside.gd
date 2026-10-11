extends SceneTree

# The Kerbside title screen (2026-10-10), on the real Game.tscn with
# NEON_TITLE=1, NEON_SPLASH=1 and NEON_WELCOME=1:
#
# - the splash runs first with the menu hidden; a key skips it
# - the first-launch card shows once, OK closes it and it is remembered
# - the Kerbside set exists with a copy of the player's car, and its camera is
#   the one in use
# - lamp life stands on the title (menu litter M2): the nodes are under the set,
#   two litter sets blow a gust phase apart, one round manhole with its steam
#   is inside the camera frustum between the camera and the car, the lamp has
#   moths and a bat in frame, wind eases back down over 3 s, and
#   LampLife.enabled = false leaves every node empty
# - roaches (menu roaches M7): ten in one MultiMesh, the lid ajar off the
#   hole, first out ~6 s in, never more than 3, none on the car, scare 1
#   clears them inside a second and holds them in for 3 s of calm
# - the menu has Continue, New Game, Load, Settings, Extras, Quit; Load lists
#   one row per save slot plus Back; Esc comes back to the main list
# - the news line has text; the Early Access tag is on the title
# - the radio is on the synthwave station but the save keeps the player's own
# - Continue (the drive button) starts the drive: the set is freed, the radio
#   is back on the player's station, the game camera is back
# - every brand icon size is in the .ico
# Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/ui/title_kerbside.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const LampLife := preload("res://scripts/world/lamp_life.gd")
const TIMEOUT_FRAMES := 900
const ICO := "res://assets/brand/logo_B4_combined.ico"

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_SPLASH", "1")
	OS.set_environment("NEON_WELCOME", "1")
	GameState.title_seen = false
	TitleScreen.splash_done = false
	AudioSettings.path = "user://title_kerbside_test.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("title", "welcome_seen", false)
	cfg.save(AudioSettings.path)
	change_scene_to_file("res://Game.tscn")
	_run.call_deferred()

func _run() -> void:
	var game := await _wait_game()
	if game == null:
		return _finish("Game.tscn never became ready")
	var gs: GameState = game.game_state
	var title: TitleScreen = _node(game, "TitleScreen")
	await _frames(3)
	_check(gs.state == GameState.State.TITLE and title.visible, "boots onto the title")

	# ---------- splash ----------
	_check(title.splash_running() and title.splash.visible, "the splash runs first")
	_check(not title.panel.visible, "the menu is hidden behind the splash")
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 60:
		if not title.splash_running():
			break
		await process_frame
	await _frames(2)
	_check(not title.splash_running() and not title.splash.visible, "a key skips the splash")
	_check(gs.state == GameState.State.TITLE, "skipping the splash stays on the title")
	_check(title.panel.visible, "the menu shows after the splash")

	# ---------- first-launch card ----------
	_check(title.welcome.visible, "the Early Access card shows on the first launch")
	title.welcome_button.pressed.emit()
	await _frames(2)
	_check(not title.welcome.visible and title.main_list.visible, "OK closes the card onto the menu")
	_check(not TitleScreen.welcome_due(), "the card is remembered as seen")

	# ---------- the set ----------
	var set_node := title.kerbside
	_check(set_node != null and set_node.is_inside_tree(), "the Kerbside set is built")
	if set_node != null:
		_check(set_node.camera.current, "the Kerbside camera is the one in use")
		_check(set_node.kind == PlayerCar.chassis_kind(), "the parked car is the player's car")
		_check(set_node.car.find_children("*", "MeshInstance3D", true, false).size() > 4, "the parked car has a body and wheels")
		_check(set_node.global_position.y < -300.0, "the set is clear of the road")
		var lights := set_node.find_children("*", "Light3D", true, false)
		_check(lights.size() == 1, "one lamp lights the set, got %d" % lights.size())

	# ---------- lamp life ----------
	if set_node != null:
		_check_lamp_life(set_node)

	# ---------- menu ----------
	var rows: Array[String] = []
	for b in title.main_list.get_children():
		rows.append((b as Button).text)
	_check(rows == ["CONTINUE", "NEW GAME", "LOAD", "SETTINGS", "EXTRAS", "QUIT"], "main rows, got %s" % [rows])
	title.load_button.pressed.emit()
	await _frames(2)
	_check(title.load_list.visible and not title.main_list.visible, "Load opens the save list")
	_check(title.load_list.get_child_count() == SaveStore.SLOTS + 1, "one row per save slot plus Back")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	for i in 60:   # input lands on a drawn frame, which can lag physics frames
		if title.main_list.visible:
			break
		await process_frame
	_check(title.main_list.visible and gs.state == GameState.State.TITLE, "Esc comes back to the main list")
	_check(title.ticker_label.text.length() > 40, "the news line has text")
	_check(title.slide.find_child("EarlyAccessTag", true, false) != null, "the Early Access tag is on the title")
	_check(not TitleScreen.news_lines().is_empty(), "there are news lines")
	_check(title.ticker_speaker.text.strip_edges() == "DALE", "the news line is Dale's, got '%s'" % title.ticker_speaker.text)
	_check(not ("Dave" in title.ticker_label.text), "no Dave on the news line")

	# ---------- radio ----------
	var radio: RadioManager = game.radio
	var synth := TitleScreen._synthwave_station()
	var own := radio.player_station()
	_check(radio.station == synth, "the title plays the synthwave station")
	radio.give_back()
	radio.tune_to(1)
	radio.borrow(synth)
	_check(radio.player_station() == 1 and radio.station == synth, "a borrowed radio still reports the player's station")
	radio.give_back()
	radio.tune_to(own)
	radio.borrow(synth)

	# ---------- drive ----------
	title.drive_button.pressed.emit()
	await _frames(4)
	_check(gs.state == GameState.State.PLAYING and not title.visible, "Continue starts the drive")
	_check(title.kerbside == null and (not is_instance_valid(set_node) or set_node.is_queued_for_deletion()),
		"the set is freed for the drive")
	_check(radio.station == own, "the radio is back on the player's station, got %d want %d" % [radio.station, own])
	var cam := game.get_viewport().get_camera_3d()
	_check(cam != null and cam.global_position.y > -300.0, "the game camera is back")

	# ---------- brand files ----------
	_check(str(ProjectSettings.get_setting("application/config/windows_native_icon", "")).ends_with(".ico"),
		"the window uses the multi-size .ico")
	_check(_ico_sizes(ICO) == [16, 20, 24, 32, 40, 48, 64, 128, 256], "the .ico holds every size, got %s" % [_ico_sizes(ICO)])
	_finish("")

func _mm_of(life: Node, node_name: String) -> MultiMesh:
	var n := life.get_node_or_null(NodePath(node_name)) as MultiMeshInstance3D
	return n.multimesh if n != null else null

func _check_lamp_life(set_node: TitleKerbside) -> void:
	var life := set_node.life_root
	_check(life != null and life.get_parent() == set_node, "lamp life has a root under the set")
	if life == null:
		return
	for n in ["LampMoths", "LampBanners", "SteamVents", "VentCovers", "WindLitter"]:
		_check(_mm_of(life, n) != null, "lamp life node %s exists under the title set" % n)
	if not LampLife.enabled:
		return
	var cam := set_node.camera
	var d: Dictionary = set_node.life
	# two litter sets, a gust phase apart (counts are real, the data is the
	# set's own record: the headless renderer does not hand MultiMesh data back)
	var litter := _mm_of(life, "WindLitter")
	_check(litter.instance_count == 2 and litter.visible_instance_count == 2, "two litter sets, got %d" % litter.visible_instance_count)
	var lc: Array = d.get("litter_custom", [])
	_check(lc.size() == 2 and absf(lc[0].a - lc[1].a) > 0.3, "the litter sets are phased apart, got %s" % [lc])
	var lxf: Transform3D = d.get("litter_xf", Transform3D.IDENTITY)
	var lane := lxf.origin + Vector3(0.0, 0.5, TitleKerbside.LITTER_Z)
	_check(cam.is_position_in_frustum(set_node.to_global(lane)), "the litter lane is in the picture")
	_check(lane.z > set_node.car.position.z and lane.z < cam.position.z, "the litter lane is between the camera and the car")
	# one round manhole, in frame, between the camera and the car
	var steam := _mm_of(life, "SteamVents")
	var cover := _mm_of(life, "VentCovers")
	_check(steam.visible_instance_count == 1 and cover.visible_instance_count == 1, "one vent with its cover")
	_check(d.get("vent_round", false), "the vent is a round manhole, not a drain")
	var vxf: Transform3D = d.get("vent_xf", Transform3D.IDENTITY)
	var hole := vxf.origin
	_check(vxf.basis.is_equal_approx(Basis()) and hole.is_equal_approx(TitleKerbside.VENT_AT), "the manhole is round at the forced spot")
	# the lid sits ajar: shifted off the hole, away from the camera
	var cxf: Transform3D = d.get("cover_xf", Transform3D.IDENTITY)
	var shift := cxf.origin - TitleKerbside.VENT_AT
	_check(absf(shift.length() - TitleRoaches.LID_SHIFT) < 0.01, "the lid is %.0f cm off the hole" % (TitleRoaches.LID_SHIFT * 100.0))
	_check(shift.dot(cam.position - TitleKerbside.VENT_AT) < 0.0, "the lid slid away from the camera, so the crescent faces it")
	_check(life.get_node_or_null(^"VentHole") != null, "the hole's black disc is under the lid")
	_check(cam.is_position_in_frustum(set_node.to_global(hole)), "the manhole is inside the camera frustum")
	_check(cam.is_position_in_frustum(set_node.to_global(hole + Vector3(0.0, 1.5, 0.0))), "the steam above it is in frame")
	_check(hole.z > set_node.car.position.z and hole.z < cam.position.z, "the manhole is on the road between the camera and the car")
	# moths and the bat at the lamp head, in frame
	var moths := _mm_of(life, "LampMoths")
	_check(moths.visible_instance_count == 1, "the lamp has a moth swarm")
	var mc: Color = d.get("moth_custom", Color(0, 0, 0, 0))
	_check(mc.a > 0.5, "the lamp always has its bat")
	_check(mc.g < 0.1, "the bat flies about every 15 s")
	var mxf: Transform3D = d.get("moth_xf", Transform3D.IDENTITY)
	var head := set_node.to_global(mxf.origin + mxf.basis * LampLife.HEAD)
	_check(cam.is_position_in_frustum(head), "the lamp head with its moths is in frame")
	_check(_mm_of(life, "LampBanners").visible_instance_count == 0, "no banner on the title lamp")
	_check_roaches(set_node)
	# wind: up at once, back down over 3 s
	set_node.set_title_wind(2.0)
	set_node._ease_wind(0.016)
	_check(is_equal_approx(LampLife.wind(), 2.0), "turbo wind is taken at once, got %.2f" % LampLife.wind())
	set_node.set_title_wind(TitleKerbside.WIND_REST)
	set_node._ease_wind(1.5)
	_check(LampLife.wind() > 1.2 and LampLife.wind() < 1.5, "wind is easing back after release, got %.2f" % LampLife.wind())
	set_node._ease_wind(2.0)
	_check(is_equal_approx(LampLife.wind(), TitleKerbside.WIND_REST), "wind is back at rest after 3 s, got %.2f" % LampLife.wind())
	# the same wind number drives the moths and the bat (shader uniform)
	var swarm := life.get_node_or_null(^"LampMoths") as MultiMeshInstance3D
	var swarm_mat := swarm.material_override as ShaderMaterial if swarm != null else null
	set_node.set_title_wind(2.0)
	set_node._ease_wind(0.016)
	_check(swarm_mat != null and is_equal_approx(float(swarm_mat.get_shader_parameter("wind")), 2.0),
			"the moths and bat read the turbo wind (uniform %s)" % [swarm_mat.get_shader_parameter("wind") if swarm_mat != null else "-"])
	set_node.set_title_wind(TitleKerbside.WIND_REST)
	set_node._ease_wind(4.0)
	_check(swarm_mat != null and is_equal_approx(float(swarm_mat.get_shader_parameter("wind")), TitleKerbside.WIND_REST),
			"the moths and bat are back at the default breeze")
	# the switch: off leaves every node empty
	LampLife.enabled = false
	var off := TitleKerbside.new(set_node.kind)
	LampLife.enabled = true
	for n in ["LampMoths", "LampBanners", "SteamVents", "VentCovers", "WindLitter", "Roaches"]:
		_check(_mm_of(off.life_root, n).visible_instance_count == 0, "NEON_LAMP_LIFE=0 empties %s on the title" % n)
	off.free()

## Roaches (M7): ten in one MultiMesh, their runs mirrored in GDScript
## (TitleRoaches.positions is the shader's top level) so the test can ask
## where each one is at any clock.
func _check_roaches(set_node: TitleKerbside) -> void:
	var mm := _mm_of(set_node.life_root, "Roaches")
	_check(mm != null and mm.instance_count == TitleRoaches.COUNT and mm.visible_instance_count == TitleRoaches.COUNT,
		"the Roaches MultiMesh has %d instances" % TitleRoaches.COUNT)
	_check(set_node.roach_sched.size() == TitleRoaches.COUNT, "every roach has a schedule")
	_check(set_node.roach_running, "the roach clock runs once the menu is up")
	# at scare 0: one out within 10 s, never more than 3, and never on the car
	var first_out := -1.0
	var most := 0
	var on_car := false
	var half_l: float = set_node.car.get_meta("half_l")
	var half_w: float = set_node.car.get_meta("half_w")
	var t := 0.0
	while t < 120.0:
		var n := 0
		for r in set_node.roach_positions(t):
			if r.out:
				n += 1
				var p: Vector2 = r.pos
				if absf(p.x) < half_l and absf(p.y - set_node.car.position.z) < half_w:
					on_car = true
		if n > 0 and first_out < 0.0:
			first_out = t
		most = maxi(most, n)
		t += 0.05
	_check(first_out >= 0.0 and first_out <= 10.0, "at scare 0 a roach is out within 10 s, first at %.1f" % first_out)
	_check(first_out >= 5.0, "the first roach waits about 6 s, got %.1f" % first_out)
	_check(most >= 2 and most <= 3, "never more than 3 out at once (and at least 2 some time), most %d" % most)
	_check(not on_car, "no roach on the car body")
	# scare 1 at a moment with roaches out: a second later none is outside the gap
	var busy := -1.0
	t = 0.0
	while t < 120.0 and busy < 0.0:
		if set_node.roach_positions(t).filter(func(r): return r.out).size() >= 2:
			busy = t
		t += 0.05
	_check(busy >= 0.0, "a moment with 2+ roaches out exists")
	var was_frozen := set_node.roach_frozen
	set_node.freeze_roaches(true)
	set_node.set_roach_clock(busy)
	set_node.set_scare(1.0)
	_check(set_node.roach_scare_t >= 0.0, "scare 1 starts the flight")
	var out_after := 0
	for r in set_node.roach_positions(busy + 1.0):
		if r.out:
			out_after += 1
	_check(out_after == 0, "1 s after scare 1 no roach is outside the gap, %d still out" % out_after)
	# and none come out again until the scare has been low for 3 s
	set_node.set_roach_clock(busy + 1.0)
	set_node.set_scare(0.0)
	_check(set_node.roach_scare_t >= 0.0, "the scare does not end the moment the value drops")
	set_node.set_roach_clock(busy + 1.0 + TitleRoaches.CALM_SECS + 0.1)
	set_node.set_scare(0.0)
	_check(set_node.roach_scare_t < 0.0 and set_node.roach_origin > busy, "after 3 s calm the runs start over")
	_check(set_node.roach_positions(set_node.roach_origin + 0.5).filter(func(r): return r.out).is_empty(),
		"nothing is out straight after the calm-down")
	# the shader's own uniforms were written
	var m := TitleRoaches.get_mat()
	_check(is_equal_approx(float(m.get_shader_parameter("origin")), set_node.roach_origin), "the origin uniform follows the set")
	_check(float(m.get_shader_parameter("scare_t")) < 0.0, "the scare_t uniform is cleared")
	set_node.freeze_roaches(was_frozen)

## The picture sizes inside a Windows .ico, smallest first.
func _ico_sizes(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	f.get_16()
	f.get_16()
	var n := f.get_16()
	var out := []
	for i in n:
		var w := f.get_8()
		out.append(256 if w == 0 else w)
		f.seek(f.get_position() + 15)
	out.sort()
	return out

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_game() -> Node:
	for i in TIMEOUT_FRAMES:
		var game := current_scene
		if game != null and is_instance_valid(game) and game.get("game_state") != null \
				and _node(game, "PauseMenu") != null and _node(game, "TitleScreen") != null:
			return game
		await physics_frame
	return null

func _node(game: Node, cls: String) -> Node:
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _finish(abort: String) -> void:
	if abort != "":
		failures.append(abort)
	for f in failures:
		printerr("FAIL: ", f)
	print("title_kerbside: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
