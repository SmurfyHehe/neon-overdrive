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
# - graffiti (M10) is on the wall: one Graffiti MultiMesh under the set with
#   every item placed, the big piece and the shutter tags in frame, nothing
#   bright behind the car's roof line, the poster flaps, and
#   Graffiti.enabled = false leaves the node empty
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
const Graffiti := preload("res://scripts/world/graffiti.gd")
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
		_check_graffiti(set_node)

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
	_check(vxf.basis.is_equal_approx(Basis()) and hole.is_equal_approx(TitleKerbside.VENT_AT), "the manhole cover is unsquashed (round) at the forced spot")
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
	# wind: up at once, back down over 3 s
	set_node.set_title_wind(2.0)
	set_node._ease_wind(0.016)
	_check(is_equal_approx(LampLife.wind(), 2.0), "turbo wind is taken at once, got %.2f" % LampLife.wind())
	set_node.set_title_wind(TitleKerbside.WIND_REST)
	set_node._ease_wind(1.5)
	_check(LampLife.wind() > 1.2 and LampLife.wind() < 1.5, "wind is easing back after release, got %.2f" % LampLife.wind())
	set_node._ease_wind(2.0)
	_check(is_equal_approx(LampLife.wind(), TitleKerbside.WIND_REST), "wind is back at rest after 3 s, got %.2f" % LampLife.wind())
	# the switch: off leaves every node empty
	LampLife.enabled = false
	var off := TitleKerbside.new(set_node.kind)
	LampLife.enabled = true
	for n in ["LampMoths", "LampBanners", "SteamVents", "VentCovers", "WindLitter"]:
		_check(_mm_of(off.life_root, n).visible_instance_count == 0, "NEON_LAMP_LIFE=0 empties %s on the title" % n)
	off.free()

func _check_graffiti(set_node: TitleKerbside) -> void:
	var art := set_node.wall_art
	_check(art != null and art.get_parent() == set_node, "the wall art has a root under the set")
	if art == null:
		return
	var mm := _mm_of(art, "Graffiti")
	_check(mm != null, "the Graffiti MultiMesh exists under the title set")
	if mm == null:
		return
	var items: Array = set_node.graffiti_items
	_check(items.size() >= 7, "the wall has the piece, the roller, tags, the stencil and a poster (%d items)" % items.size())
	_check(mm.visible_instance_count == items.size() and mm.instance_count == items.size(), "every item is placed, %d of %d" % [mm.visible_instance_count, items.size()])
	var cam := set_node.camera
	var wall_z := -RoadChunkBuilder.CURB_W - RoadChunkBuilder.SIDEWALK_W
	var kinds := {}
	var flaps := 0
	for it in items:
		var c: Dictionary = Graffiti.cell(it.cell)
		_check(not c.is_empty(), "title cell %s exists in the atlas" % [it.cell])
		_check(Graffiti.tint_index(it.tint) >= 0, "title tint %s is on the palette" % [it.tint])
		kinds[c.get("kind", "")] = true
		var o: Vector3 = it.xf.origin
		_check(o.z > wall_z and o.z < wall_z + 0.2, "%s sits just off the wall face (z %.3f)" % [c.get("id"), o.z])
		_check(cam.is_position_in_frustum(set_node.to_global(o)), "%s is in the picture" % c.get("id"))
		if bool(it.get("flap", false)):
			flaps += 1
		# the car's silhouette: the camera sees it against wall x 0.5..7, y < 2.2.
		# Only the stencil and the tag on the shutter may be there, and they are
		# low and dull; nothing white or amber at the roof line
		if o.x > 0.5 and o.x < 7.0 and o.y < 2.6:
			_check(c.get("kind") == "stencil" or (c.get("kind") == "tag" and o.y < 2.0), "%s does not sit on the car's roof line (x %.1f y %.1f)" % [c.get("id"), o.x, o.y])
	for k in ["piece", "roller", "tag", "stencil", "poster"]:
		_check(kinds.has(k), "the wall has a %s" % k)
	_check(flaps == 1, "one poster flaps, got %d" % flaps)
	# the big piece: above the ledge, left of the car
	var piece: Dictionary = items[0]
	_check(String(Graffiti.cell(piece.cell).id).begins_with("piece_") and piece.xf.origin.y > 3.9 and piece.xf.origin.x < -1.0, "the big piece is high on the wall left of the car")
	# the stencil on the shutter has a tag over it
	var stencil_i := -1
	var over_i := -1
	for i in range(items.size()):
		var id := String(Graffiti.cell(items[i].cell).id)
		if id == "stencil_no_parking":
			stencil_i = i
		elif stencil_i >= 0 and over_i < 0 and Graffiti.cell(items[i].cell).kind == "tag":
			over_i = i
	_check(stencil_i >= 0 and over_i > stencil_i, "a tag is sprayed over the NO PARKING stencil")
	if stencil_i >= 0 and over_i > stencil_i:
		var so: Vector3 = items[stencil_i].xf.origin
		var to: Vector3 = items[over_i].xf.origin
		_check(to.z > so.z and absf(to.x - so.x) < 0.8 and absf(to.y - so.y) < 0.8, "the tag lies over the stencil, in front of it")
		_check(so.x > 0.1 and so.x < 3.7 and so.y > 0.1 and so.y < 2.8 and so.z > wall_z + TitleKerbside.SHUTTER_FACE, "the stencil is on the shutter's face")
	# the wind reaches the graffiti too (the poster flaps with the litter)
	set_node.set_title_wind(2.0)
	set_node._ease_wind(0.016)
	_check(is_equal_approx(Graffiti.wind(), 2.0), "turbo wind reaches the graffiti, got %.2f" % Graffiti.wind())
	set_node.set_title_wind(TitleKerbside.WIND_REST)
	set_node._ease_wind(4.0)
	# the switch
	Graffiti.enabled = false
	var off := TitleKerbside.new(set_node.kind)
	Graffiti.enabled = true
	_check(_mm_of(off.wall_art, "Graffiti").visible_instance_count == 0, "NEON_GRAFFITI=0 empties the wall on the title")
	off.free()

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
