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
# - street life (M8): the neighbour, pigeons, cat, bin bags + flies and the
#   wire exist under the set; no event before 10 s and one at a time; a 4 s
#   boost wakes the neighbour (then the cooldown holds), a boost lifts the
#   pigeons and they are back one by one, a boost drops the cat and it is
#   back 45-90 s on, the bags and flies read the wind, a gale wraps the shoes
#   and they unwind; each returns to rest
# - rats (M9): three in one MultiMesh on the wall seam, one every 20-40 s,
#   never more than two, one sits up in the lamp light; scare 1 bolts the one
#   out and none start until 3 s of calm; Settings' "Roaches and rats" off
#   hides roaches, rats and flies and leaves the moths
# - graffiti (M10) is on the wall: one Graffiti MultiMesh under the set with
#   every item placed, the big piece and the shutter tags in frame, nothing
#   bright behind the car's roof line, the poster flaps, and
#   Graffiti.enabled = false leaves the node empty
# - the menu has Continue, New Game, Load, Settings, Extras, Quit; Load lists
#   one row per save slot plus Delete a save and Back; Esc comes back to the main list
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
		# two lights (relight 2026-10-14): the sodium lamp, the only one with a
		# shadow, and the dusk rim light behind the car
		var lights := set_node.find_children("*", "Light3D", true, false)
		_check(lights.size() == 2, "the lamp and the rim light light the set, got %d" % lights.size())
		var shadows := lights.filter(func(l): return l.shadow_enabled)
		_check(shadows.size() == 1 and shadows[0] == set_node.lamp_light, "the lamp is the one light with a shadow")
		_check(set_node.rim_light != null and set_node.rim_light.light_color.b > set_node.rim_light.light_color.r, "the rim light is cool, not sodium")

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
	# one row per slot, DELETE A SAVE (8000037, tests/core/save_delete.gd), BACK
	_check(title.load_list.get_child_count() == SaveStore.SLOTS + 2, "one row per save slot plus Delete a save and Back")
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
	# The speaker's name comes from the radio data, whatever it says there.
	var dj := str(TitleScreen.news_lines()[0]).get_slice(": ", 0).to_upper()
	_check(title.ticker_speaker.text.strip_edges() == dj, "the news line names the DJ, got '%s'" % title.ticker_speaker.text)

	# ---------- radio ----------
	var radio: RadioManager = game.radio
	var synth := TitleScreen._synthwave_station()
	var own := radio.player_station()
	_check(radio.station == -1 and title.theme_playing(), "the title's radio is off and the theme song plays")
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
	_check_street_life(set_node)
	_check_rats(set_node)
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
	for n in ["LampMoths", "LampBanners", "SteamVents", "VentCovers", "WindLitter", "Roaches", "Rats"]:
		_check(_mm_of(off.life_root, n).visible_instance_count == 0, "NEON_LAMP_LIFE=0 empties %s on the title" % n)
	for n in ["Neighbour", "Pigeons", "Cat", "BinBags", "Flies", "Wire"]:
		_check(not (off.life_root.get_node(NodePath(n)) as Node3D).visible, "NEON_LAMP_LIFE=0 hides %s on the title" % n)
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

## Street life (M8): one node per part; the events are driven through the
## set's own scheduler (_run_street) with the clock set by hand, and read
## back through the GDScript mirrors of the shaders.
func _check_street_life(set_node: TitleKerbside) -> void:
	var life := set_node.life_root
	for n in ["Neighbour", "Pigeons", "Cat", "BinBags", "Flies", "Wire"]:
		var node := life.get_node_or_null(NodePath(n)) as Node3D
		_check(node != null and node.visible, "street life node %s exists under the set" % n)
	var pigeons := _mm_of(life, "Pigeons")
	_check(pigeons != null and pigeons.instance_count == TitleStreetLife.PIGEON_COUNT, "four pigeons in one MultiMesh")
	var was_frozen := set_node.roach_frozen
	set_node.freeze_roaches(false)
	# nothing in the first 10 s, however hard the turbo is held
	set_node.set_roach_clock(5.0)
	set_node.set_scare(0.95)
	set_node._run_street(4.5)
	_check(not set_node.event_free(5.0), "no event in the first 10 s")
	_check(set_node.neighbour_wake_t < 0.0 and set_node.pigeon_lift_t < 0.0 and set_node.cat_leave_t < 0.0,
		"a held turbo at 5 s wakes nothing")
	# the neighbour: 4 s over 0.85 wakes the window; the blind goes up and the
	# shape stands there; it is dark again after WAKE_LEN
	set_node.set_roach_clock(12.0)
	set_node._run_street(0.1)
	_check(is_equal_approx(set_node.neighbour_wake_t, 12.0), "4 s of hard boost wakes the neighbour at 12 s, got %.1f" % set_node.neighbour_wake_t)
	_check(is_equal_approx(float(TitleStreetLife.uniform("neighbour", "wake_t")), 12.0), "the wake_t uniform is written")
	var mid := TitleStreetLife.neighbour_at(1.2)
	_check(mid.light > 0.95 and mid.blind > 0.95 and mid.head, "1.2 s in the light is on, the blind up, the shape there")
	var done := TitleStreetLife.neighbour_at(TitleStreetLife.WAKE_LEN + 0.2)
	_check(done.light == 0.0 and done.blind == 0.0 and not done.head, "after %.1f s the window is dark and the blind down" % TitleStreetLife.WAKE_LEN)
	# one event at a time: the pigeons wait while the window is busy
	set_node.set_roach_clock(13.0)
	set_node.set_scare(0.7)
	set_node._run_street(0.1)
	_check(set_node.pigeon_lift_t < 0.0, "the pigeons do not lift while the neighbour's window is busy")
	# ... and lift once it is free; back one by one, 20-40 s on
	set_node.set_roach_clock(20.0)
	set_node._run_street(0.1)
	_check(is_equal_approx(set_node.pigeon_lift_t, 20.0), "a 0.7 boost lifts the pigeons at 20 s, got %.1f" % set_node.pigeon_lift_t)
	_check(is_equal_approx(float(TitleStreetLife.uniform("pigeon", "lift_t")), 20.0), "the lift_t uniform is written")
	_check(TitleStreetLife.pigeon_state(0, 21.0, 20.0, set_node.pigeon_ret[0]) == "out", "a second in the first pigeon is in the air")
	_check(not set_node.pigeons_settled(21.0), "the flock is not settled in the air")
	var rets: Array[float] = set_node.pigeon_ret
	_check(rets.size() == TitleStreetLife.PIGEON_COUNT, "every pigeon has a return clock")
	var one_by_one := true
	var in_range := true
	for i in rets.size():
		if i > 0 and rets[i] - rets[i - 1] < 2.9:
			one_by_one = false
		if rets[i] < 20.0 + TitleStreetLife.LIFT_FLY + TitleStreetLife.RETURN_MIN or rets[i] > 20.0 + 1.0 + TitleStreetLife.LIFT_FLY + TitleStreetLife.RETURN_MAX + 15.0:
			in_range = false
	_check(one_by_one, "the pigeons come back one by one, got %s" % [rets])
	_check(in_range, "the pigeons come back 20-40 s on, got %s" % [rets])
	var last_back: float = rets[rets.size() - 1] + TitleStreetLife.RETURN_FLY + 0.1
	_check(set_node.pigeons_settled(last_back), "after the last return the flock is at rest")
	_check(TitleStreetLife.pigeon_state(0, rets[0] + 1.0, 20.0, rets[0]) == "back", "a pigeon on its way back reads as back")
	# the cat: it waits out the pigeons' lift-off, then a 0.8 boost drops it
	set_node.set_roach_clock(21.0)
	set_node.set_scare(0.8)
	set_node._run_street(0.1)
	_check(set_node.cat_leave_t < 0.0, "the cat sits tight while the pigeons' lift-off is the event")
	set_node.set_roach_clock(30.0)
	set_node._run_street(0.1)
	_check(is_equal_approx(set_node.cat_leave_t, 30.0), "a 0.8 boost drops the cat at 30 s, got %.1f" % set_node.cat_leave_t)
	_check(TitleStreetLife.cat_state(30.2, 30.0, set_node.cat_back_t) == "drop", "0.2 s in the cat is dropping")
	_check(TitleStreetLife.cat_state(31.5, 30.0, set_node.cat_back_t) == "run", "1.5 s in the cat is running off")
	var gone_at := 30.0 + TitleStreetLife.CAT_DROP + TitleStreetLife.CAT_RUN
	_check(TitleStreetLife.cat_state(gone_at + 1.0, 30.0, set_node.cat_back_t) == "gone", "then it is out of frame")
	_check(set_node.cat_back_t >= gone_at + TitleStreetLife.CAT_BACK_MIN and set_node.cat_back_t <= gone_at + TitleStreetLife.CAT_BACK_MAX,
		"the cat is back 45-90 s later, got %.1f s" % (set_node.cat_back_t - gone_at))
	var home_at: float = set_node.cat_back_t + TitleStreetLife.CAT_RUN_IN + TitleStreetLife.CAT_JUMP
	_check(TitleStreetLife.cat_state(home_at - 0.1, 30.0, set_node.cat_back_t) == "jump", "it jumps back up onto the box")
	_check(TitleStreetLife.cat_state(home_at + 0.1, 30.0, set_node.cat_back_t) == "sit", "and sits again")
	# the neighbour's cooldown: two big blow-offs inside 60 s of the wake do nothing
	set_node.set_roach_clock(40.0)
	set_node.set_scare(0.0)
	set_node.blow_off(0.9)
	set_node.set_roach_clock(41.0)
	set_node.blow_off(0.9)
	set_node._run_street(0.1)
	_check(is_equal_approx(set_node.neighbour_wake_t, 12.0), "the neighbour does not wake again inside the 60 s cooldown")
	set_node.set_roach_clock(home_at + 0.5)
	set_node._run_street(0.1)
	_check(set_node.cat_leave_t < 0.0 and float(TitleStreetLife.uniform("cat", "leave_t")) < 0.0, "once home the cat's event clears")
	# ... and after the cooldown a second big blow-off within 20 s wakes it
	set_node.set_roach_clock(home_at + 1.0)
	set_node.blow_off(0.9)
	set_node.set_roach_clock(home_at + 2.0)
	set_node.blow_off(0.9)
	set_node._run_street(0.1)
	_check(is_equal_approx(set_node.neighbour_wake_t, home_at + 2.0), "two big blow-offs in 20 s wake the neighbour, got %.1f" % set_node.neighbour_wake_t)
	# the bags and the flies read the wind uniform; the shoes wrap at a gale
	set_node.set_title_wind(2.0)
	set_node._ease_wind(0.016)
	_check(is_equal_approx(float(TitleStreetLife.uniform("bags", "wind")), 2.0), "the bin bags read the gale")
	_check(is_equal_approx(float(TitleStreetLife.uniform("flies", "wind")), 2.0), "the flies read the gale")
	var gale_at := home_at + 10.0
	set_node.set_roach_clock(gale_at)
	set_node._run_street(0.016)
	_check(is_equal_approx(set_node.shoes_wrap_t, gale_at), "a gale wraps the shoes round the wire, got %.1f" % set_node.shoes_wrap_t)
	_check(TitleStreetLife.wrap_at(TitleStreetLife.WRAP_UP) > 0.99, "they are wound up after %.1f s" % TitleStreetLife.WRAP_UP)
	_check(TitleStreetLife.wrap_at(TitleStreetLife.WRAP_LEN + 0.1) == 0.0, "and hang free again after %.1f s" % TitleStreetLife.WRAP_LEN)
	set_node.set_title_wind(TitleKerbside.WIND_REST)
	set_node._ease_wind(5.0)
	_check(is_equal_approx(float(TitleStreetLife.uniform("flies", "wind")), TitleKerbside.WIND_REST), "the flies gather again at the default breeze")
	set_node.set_scare(0.0)
	set_node.freeze_roaches(was_frozen)

## Rats (M9): three in one MultiMesh, their runs mirrored in GDScript
## (TitleRats.positions is the shader's top level).
func _check_rats(set_node: TitleKerbside) -> void:
	var mm := _mm_of(set_node.life_root, "Rats")
	_check(mm != null and mm.instance_count == TitleRats.COUNT and mm.visible_instance_count == TitleRats.COUNT,
		"the Rats MultiMesh has %d instances" % TitleRats.COUNT)
	_check(set_node.rat_sched.size() == TitleRats.COUNT, "every rat has a schedule")
	# over five minutes from a fresh origin: entries 1.5-45 s apart, never
	# more than two out, one sits up in the lamp light at the wall seam
	var was_frozen := set_node.roach_frozen
	set_node.freeze_roaches(true)
	var origin := set_node.rat_origin
	var scare_t := set_node.rat_scare_t
	var entries := []
	var most := 0
	var sat_in_light := false
	var off_seam := false
	var was_out := [false, false, false]
	var t := origin
	while t < origin + 300.0:
		var rows := TitleRats.positions(set_node.rat_sched, t, origin, -1.0)
		var n := 0
		for i in rows.size():
			var r: Dictionary = rows[i]
			if r.out:
				n += 1
				if not was_out[i]:
					entries.append(t)
				var p: Vector2 = r.pos
				if absf(p.y - TitleRats.SEAM_Z) > TitleRats.INTO_WALL + 0.01:
					off_seam = true
				if r.sit > 0.5 and p.x >= TitleRats.STOP_X0 - 0.01 and p.x <= TitleRats.STOP_X1 + 0.01:
					sat_in_light = true
			was_out[i] = r.out
		most = maxi(most, n)
		t += 0.1
	_check(entries.size() >= 8 and entries.size() <= 18, "about one rat every 20-40 s: %d in 5 min" % entries.size())
	var gaps_ok := entries.size() >= 2
	var pair := false
	for i in range(1, entries.size()):
		var g: float = entries[i] - entries[i - 1]
		if g < 1.0 or g > 46.0:
			gaps_ok = false
		if g < 8.0:
			pair = true
	_check(gaps_ok, "rats come 1-46 s apart, got %s" % [entries])
	_check(pair, "sometimes two come in a row")
	_check(most <= 2, "never more than two rats out, most %d" % most)
	_check(sat_in_light, "a rat sits up in the lamp light")
	_check(not off_seam, "every rat stays on the wall seam")
	# scare 1 with a rat out: it bolts on and none start until 3 s of calm
	var busy := -1.0
	t = origin
	while t < origin + 300.0 and busy < 0.0:
		var rows := TitleRats.positions(set_node.rat_sched, t, origin, -1.0)
		for r in rows:
			if r.out and r.pos.x < TitleRats.STOP_X0 - 2.0:
				busy = t
		t += 0.1
	_check(busy >= 0.0, "a moment with a rat running in exists")
	set_node.set_roach_clock(busy)
	set_node.set_scare(1.0)
	_check(set_node.rat_scare_t >= 0.0, "scare 1 starts the bolt")
	var before: Vector2 = TitleRats.positions(set_node.rat_sched, busy, origin, -1.0).filter(func(r): return r.out)[0].pos
	var calm_after: Vector2 = TitleRats.positions(set_node.rat_sched, busy + 1.0, origin, -1.0).filter(func(r): return r.out)[0].pos
	var bolted := set_node.rat_positions(busy + 1.0).filter(func(r): return r.out)
	_check(bolted.size() <= 1, "no new rat starts while scared, %d out" % bolted.size())
	if not bolted.is_empty():
		var bp: Vector2 = bolted[0].pos
		_check(bp.x - before.x > (calm_after.x - before.x) * 1.5, "the bolting rat runs on at twice its speed")
	_check(set_node.rat_positions(busy + 40.0).filter(func(r): return r.out).is_empty(), "40 s into a scare nothing is out")
	set_node.set_roach_clock(busy + 40.0)
	set_node.set_scare(0.0)
	_check(set_node.rat_scare_t >= 0.0, "the scare does not end the moment the value drops")
	set_node.set_roach_clock(busy + 40.0 + TitleRats.CALM_SECS + 0.1)
	set_node.set_scare(0.0)
	_check(set_node.rat_scare_t < 0.0 and set_node.rat_origin > busy, "after 3 s of calm the cycles start over")
	_check(set_node.rat_positions(set_node.rat_origin + 0.5).filter(func(r): return r.out).is_empty(), "nothing starts straight after the calm-down")
	_check(is_equal_approx(float(TitleRats.get_mat().get_shader_parameter("origin")), set_node.rat_origin), "the rats' origin uniform follows the set")
	_check(float(TitleRats.get_mat().get_shader_parameter("scare_t")) < 0.0, "the rats' scare_t uniform is cleared")
	# the setting: off hides the roaches, the rats and the flies, not the moths
	var life := set_node.life_root
	GameSettings.set_critters(false)
	set_node._process(0.016)
	for n in ["Roaches", "Rats", "Flies"]:
		_check(not (life.get_node(NodePath(n)) as Node3D).visible, "Roaches and rats off hides %s" % n)
	for n in ["LampMoths", "Pigeons", "Cat"]:
		_check((life.get_node(NodePath(n)) as Node3D).visible, "Roaches and rats off leaves %s" % n)
	GameSettings.set_critters(true)
	set_node._process(0.016)
	_check((life.get_node(^"Rats") as Node3D).visible and (life.get_node(^"Roaches") as Node3D).visible, "Roaches and rats on shows them again")
	set_node.rat_scare_t = scare_t
	set_node.freeze_roaches(was_frozen)
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
