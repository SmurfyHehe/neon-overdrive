extends SceneTree

# Mods show in the engine bay (engine bays B4; Roy 2026-10-14: "the engine
# bay should change based off the performance/mods").
#
# No game, the coupe: bay.glb carries mod variants (CarAssembler.bay_variants)
# for every engine branch template and the bay bolt-ons; the stock bay draws
# no mod part; a small turbo brings its snail, pipes and intercooler and takes
# the airbox and washer bottle away; a big single on top of it replaces the
# snail and keeps the pipes; the twin pair likewise; the NA branch swaps the
# airbox for a cone, the screamer swaps the cone for trumpets; FittedMods.keys
# turns the garage's node ids into those templates, bolt-ons as they are;
# FittedMods.combos matches the python checker's sets.
#
# In the game: with "service, small turbo, strut bar" fitted in the save, Y
# opens the hood and the Bay node under the body is the bay with those keys
# (its triangle count), the hood sheet lists SMALL TURBO and FRONT STRUT BAR;
# after the garage drops the bay (drop_part) with a stock save it is the
# stock bay again.
#
# Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/car/bay_mods.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const ID := "p1_coupe"

var logger := Harness.ErrorCounter.new()
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	root.size = Vector2i(1280, 720)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _secs(t: float) -> void:
	var until := Engine.get_physics_frames() + int(ceil(t * float(Engine.physics_ticks_per_second)))
	while Engine.get_physics_frames() < until:
		await process_frame

## A short press timed on the physics clock (as tests/car/hood_panel.gd taps):
## CarLids reads a press held past HOLD_S as the other lid, and on a slow
## runner two drawn frames can take longer than that.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _secs(0.05)
	Input.action_release(action)
	await _secs(0.05)

func _tris(names: PackedStringArray) -> int:
	var n := 0
	for p in names:
		for m: Dictionary in CarAssembler.part_arrays(ID, p).values():
			n += (m.i as PackedInt32Array).size() / 3
	return n

func _bay_tris(keys: Array) -> int:
	var b := CarAssembler.build_bay(ID, null, keys)
	var t := CarAssembler._mesh_tris(b.mesh)
	b.free()
	return t

func _static() -> void:
	var v := CarAssembler.bay_variants(ID)
	for k in ["turbo_small", "turbo_big_single", "turbo_twin", "na_breathe", "na_screamer", "na_stroker",
			"cold_air_intake", "underdrive_pulley", "light_battery", "oil_cooler", "strut_bar_front"]:
		_check(v.has(k), "the coupe's bay has no variant for %s" % k)
	# every engine branch template of the tree has a look in the bay
	for nid in ModTree.tree(ID).get("nodes", {}):
		var t := String(ModTree.node(ID, nid).get("template", ""))
		if t.begins_with("turbo_") or t.begins_with("na_"):
			_check(v.has(t), "engine node %s (%s) changes nothing in the bay" % [nid, t])
	var stock := CarAssembler.bay_active_names(ID)
	for p in stock:
		_check(not p.begins_with("bay_mod_"), "stock bay draws the mod part %s" % p)
	_check(stock.has("bay_airbox") and stock.has("bay_washer") and stock.has("bay_battery"), "stock bay keeps its airbox, washer bottle and battery")
	var ts := CarAssembler.bay_active_names(ID, ["turbo_small"])
	_check(ts.has("bay_mod_ts_turbo") and ts.has("bay_mod_ts_intercooler") and ts.has("bay_mod_ts_pipe_l"), "small turbo: snail, intercooler and pipes on")
	_check(not ts.has("bay_airbox") and not ts.has("bay_washer"), "small turbo: airbox and washer bottle off")
	var tb := CarAssembler.bay_active_names(ID, ["turbo_small", "turbo_big_single"])
	_check(tb.has("bay_mod_tb_turbo") and not tb.has("bay_mod_ts_turbo") and tb.has("bay_mod_ts_pipe_r"), "big single replaces the small snail and keeps the pipes")
	var tt := CarAssembler.bay_active_names(ID, ["turbo_small", "turbo_twin"])
	_check(tt.has("bay_mod_tt_turbos") and not tt.has("bay_mod_ts_turbo"), "the twin pair replaces the small snail")
	var na := CarAssembler.bay_active_names(ID, ["na_breathe", "cold_air_intake"])
	_check(na.has("bay_mod_na_cone") and not na.has("bay_airbox") and not na.has("bay_mod_cai"), "stay NA: a cone instead of the airbox, and instead of the cold-air intake")
	var sc := CarAssembler.bay_active_names(ID, ["na_breathe", "na_screamer"])
	_check(sc.has("bay_mod_itb") and not sc.has("bay_mod_na_cone"), "screamer: trumpets instead of the cone")
	_check(_bay_tris(["turbo_small"]) == _tris(ts) and _bay_tris(["turbo_small"]) != _bay_tris([]), "the built bay follows the fitted keys")
	# the garage's ids become the keys the bay is built by
	var keys := FittedMods.keys(ID, ["service", "B", "B1", "strut_bar_front", "short_shifter"])
	_check(keys == ["service", "turbo_small", "turbo_big_single", "strut_bar_front", "short_shifter"], "keys from ids: %s" % [keys])
	# the cover's finish by tier (Roy 1570): one plate per tier T2..T5, one at a time
	for t in ["T2", "T3", "T4", "T5"]:
		_check(v.has("tier_" + t), "no cover finish for tier %s" % t)
	var spec := CarSpec.player_spec(ID)
	var tk := FittedMods.keys(ID, ["service"], spec)
	_check(tk[0] == "tier_" + ModTree.tier_of(spec) and tk.size() == 2, "keys with the spec lead with the car's tier: %s" % [tk])
	var t3 := CarAssembler.bay_active_names(ID, ["na_breathe", "na_stroker", "tier_T3"])
	_check(t3.has("bay_mod_tier3_cover") and t3.has("bay_mod_stroker_strip") and t3.has("bay_mod_stroker_damper") and not t3.has("bay_mod_tier2_cover"), "T3: the polished lid with the stroker's strip, no T2 crown")
	var combos := FittedMods.combos(ID, v)
	for c: Array in combos:
		var n_tier := 0
		for k in c:
			if String(k).begins_with("tier_"):
				n_tier += 1
		_check(n_tier <= 1, "a set wears one tier at most: %s" % [c])
	_check(combos.size() >= 40 and combos[0].is_empty(), "%d fitted sets (8 x 5 tiers), stock first" % combos.size())
	var has_b1 := false
	for c: Array in combos:
		if c.has("turbo_big_single"):
			has_b1 = true
			_check(c.has("turbo_small") and c.has("strut_bar_front") and not c.has("na_breathe"), "B1's set: on top of B, with the bolt-ons, never with the NA branch: %s" % [c])
	_check(has_b1, "no fitted set with the big single")
	print("bay_mods: %d variants, stock %d tris, small turbo %d, big single %d, twins %d, screamer %d" % [
		v.size(), _bay_tris([]), _bay_tris(["turbo_small"]), _bay_tris(["turbo_small", "turbo_big_single"]),
		_bay_tris(["turbo_small", "turbo_twin"]), _bay_tris(["na_breathe", "na_screamer"])])

func _in_game() -> void:
	# the save: the coupe owns and has fitted a service, the small turbo and a strut bar
	_check(SaveStore.save_garage(["p1_coupe/service", "p1_coupe/B", "p1_coupe/strut_bar_front"]), "save_garage")
	_check(SaveStore.save_mod_tree({ID: {"installed": ["service", "B", "strut_bar_front"]}}), "save_mod_tree")
	var ids := FittedMods.ids(null, ID)
	_check(ids == ["service", "B", "strut_bar_front"], "the fitted ids from the save: %s" % [ids])
	OS.set_environment("NEON_CAR", ID)
	var game := Harness.boot(self, 0, 150.0, 7, 1.0e6)
	await _frames(60)
	var p: PlayerCar = game.get("player")
	_check(p != null, "no player")
	if p == null:
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 1.0
		c.steering_input = 0.0
	await _secs(1.5)
	var lids := CarLids.of(p)
	_check(lids != null and lids.can_open(), "the stopped coupe cannot open a lid")
	await _tap(CarLids.ACTION)
	await _frames(4)
	_check(lids != null and lids.is_open("hinge_hood"), "Y should open the hood")
	var detail := CarDetail.of(p)
	var bay := detail.node_of("bay") as MeshInstance3D
	_check(bay != null, "no Bay node with the hood up")
	if bay != null:
		var want := _bay_tris(["tier_" + ModTree.tier_of(p.spec), "turbo_small", "strut_bar_front"])
		_check(CarAssembler._mesh_tris(bay.mesh) == want and want != _bay_tris([]), "the bay in game should be the small-turbo bay with a strut bar (%d vs %d)" % [CarAssembler._mesh_tris(bay.mesh), want])
	var panel := HoodPanel.of(game)
	if panel != null:
		var mods: Array = panel.readout().get("mods", [])
		_check(mods.has("SMALL TURBO") and mods.has("FRONT STRUT BAR"), "the hood sheet lists the fitted mods: %s" % [mods])
	# the garage takes the turbo off: the bay is built again, stock
	_check(SaveStore.save_mod_tree({ID: {"installed": ["service"]}}), "save_mod_tree stock")
	call_group(CarDetail.GROUP, "drop_part", "bay")
	await _frames(2)
	var bay2 := detail.node_of("bay") as MeshInstance3D
	_check(bay2 != null and bay2 != bay and CarAssembler._mesh_tris(bay2.mesh) == _bay_tris(["tier_" + ModTree.tier_of(p.spec)]), "after the refit the bay should be stock again (at the car's tier)")

func _run() -> void:
	_static()
	await _in_game()
	_check(logger.errors.is_empty(), "errors were logged: %s" % [logger.errors])
	print("bay_mods: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
