extends SceneTree

# The garage's mod tree panel (garage step G3a): moving, buying, keystones,
# branch swaps and the king crate, through the panel and its model with a real
# wallet and the real save files (in a test folder).
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/ui/mod_tree_panel.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const GarageMods := preload("res://scripts/car/garage_mods.gd")
const TreePanel := preload("res://scripts/ui/mod_tree_panel.gd")
const PlayerTune := preload("res://scripts/car/player_tune.gd")

const ROOT := "user://test_mod_tree_panel"
const CAR := "p1_coupe"
const CASH := 777

var failures: Array[String] = []
var checks := 0
var panel: Control
var wallet: Node

func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveStore.select_slot(1)
	PlayerTune.path = ROOT.path_join("player_tune.json")
	root.size = Vector2i(1280, 720)

	_reach()
	_buy()
	_short()
	_keystone()
	_swap()
	_crate()
	await _keys_and_draw()

	print("mod_tree_panel: %d checks, %d failed" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: " + f)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures.append(msg)

## A fresh slot with this much money, and a panel on the coupe.
func _fresh(bank: int) -> void:
	if panel != null:
		root.remove_child(panel)
		panel.free()
		root.remove_child(wallet)
		wallet.free()
	SaveStore.save_wallet(CASH, bank)
	SaveStore.save_garage([])
	SaveStore.save_mod_tree({})
	_write(PlayerTune.path, {"version": 1, "values": {}})
	_write("%s_%s_branches.json" % [PlayerTune.path.get_basename(), CAR], {})
	wallet = Wallet.new()
	root.add_child(wallet)
	panel = TreePanel.new()
	root.add_child(panel)
	_check(panel.open(CAR, wallet), "the coupe has a panel")

func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _tune() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PlayerTune.path)).get("values", {})

func _must_buy(id: String) -> void:
	var r: Dictionary = panel.model.buy(id)
	_check(r.ok, "buying %s: %s" % [id, r.reason])

# ---- From Service, arrow moves reach every node on every car's tree -----------

func _reach() -> void:
	var with_tree: Array = []
	var dir := DirAccess.open("res://data/mod_trees")
	for f in dir.get_files():
		if f.ends_with(".json") and not f.begins_with("_"):
			with_tree.append(f.get_basename())
	_check(CAR in with_tree, "the coupe's tree file is there")
	print("mod_tree_panel: tree files: %s" % str(with_tree))
	for car in PlayerCars.ids():
		var m := GarageMods.new()
		var opened := m.open(car, null)
		_check(opened == (car in with_tree and not PlayerCars.is_special(car)), "%s: a panel only with a tree file and never on a special vehicle" % car)
		if not opened:
			continue
		var seen := {m.root: true}
		var open: Array = [m.root]
		while not open.is_empty():
			var at: String = open.pop_back()
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var to := m.move(at, d)
				_check(m.items.has(to), "%s: a move from %s lands on a node" % [car, at])
				if not seen.has(to):
					seen[to] = true
					open.append(to)
		for id in m.items:
			_check(seen.has(id), "%s: arrows never reach %s" % [car, id])
		print("mod_tree_panel: %s: %d nodes, all reached: %s" % [car, m.items.size(), seen.size() == m.items.size()])
		# The row along the bottom.
		var bolts := 0
		var groups := {}
		for id in m.items:
			if m.items[id].kind == "bolt":
				bolts += 1
				groups[m.items[id].group] = true
				_check(not String(id).contains("scanner"), "%s: the police scanner is not on the row" % car)
		_check(bolts == BoltOns.items().size(), "%s: every bolt-on is on the row, got %d" % [car, bolts])
		_check(groups.size() == 5, "%s: five groups on the row, got %s" % [car, str(groups.keys())])
		var down := m.move(m.root, Vector2i.DOWN)
		_check(m.items[down].kind == "bolt", "%s: down from Service drops into the Bolt-on row" % car)
		_check(m.move(down, Vector2i.UP) == m.root, "%s: up from the row's top comes back to Service" % car)
	for car in ["m1_monster", "l1_lowrider"]:
		_check(not GarageMods.has_panel(car), "%s has no tree and no Bolt-on row" % car)

# ---- Buying -----------------------------------------------------------------

func _buy() -> void:
	_fresh(50000)
	var m: RefCounted = panel.model
	_check(panel.selected == "service", "the panel opens on Service")
	var cost: int = m.card("service").price
	_check(cost == ModTree.price_cred(CAR, "service") and cost > 0, "the card's price is the tree's price (%d)" % cost)
	panel.accept()
	_check(panel.ticket == "service" and wallet.bank == 50000, "Enter puts up the work order first, nothing paid yet")
	_check(m.ticket_text("service") == "Fit the service, %s?" % GarageMods.money(cost), "ticket reads '%s'" % m.ticket_text("service"))
	panel.cancel()
	_check(panel.ticket == "" and not m.owned.has("service"), "Escape tears the ticket up")
	panel.accept()
	panel.accept()
	_check(wallet.bank == 50000 - cost, "the bank went down by the card's price (%d left)" % wallet.bank)
	_check(wallet.cash == CASH, "tonight's cash is untouched")
	_check(SaveStore.load_wallet().bank == 50000 - cost, "wallet.json has the new bank")
	_check((CAR + "/service") in SaveStore.load_garage().owned_parts, "the part is in garage.json")
	_check("service" in SaveStore.load_mod_tree().cars.get(CAR, {}).get("installed", []), "the node is in mod_tree.json")
	_check(m.state("service") == GarageMods.FITTED, "Service reads fitted")
	# A few more, then the next spawn.
	for id in ["B", "tyres_1", "short_shifter", "lamps_fixed"]:
		var before: int = wallet.bank
		var p: int = m.price(id)
		_must_buy(id)
		_check(wallet.bank == before - p and p > 0, "%s took its price from the bank" % id)
	var stock := CarSpec.player_spec(CAR)
	var want: Dictionary = ModTree.build_base(stock, ModTree.fitted(CAR, ["service", "B", "tyres_1", "short_shifter", "lamps_fixed"]))
	var spawn: Dictionary = GarageMods.spawn_build(CAR)
	_check(spawn.problems.is_empty(), "the saved tree builds clean: %s" % str(spawn.problems))
	_check(var_to_str(spawn.spec) == var_to_str(want), "the next spawn's CarSpec matches the tree")
	_check(float(spawn.spec.turbo_boost_max) > 0.0 and float(spawn.spec.shift_time) < float(stock.shift_time), "and it is not the stock car")
	# The card shows real numbers.
	var card: Dictionary = m.card("B1")
	_check(not card.lines.is_empty() and card.bars.size() == 4, "B1's card has numbers and four bars")
	var labels: Array = []
	for line in card.lines:
		labels.append(line.label)
	_check("Torque" in labels, "B1's card says what it does to torque (%s)" % str(labels))
	# A second model reads the same thing back from the files.
	var again := GarageMods.new()
	again.open(CAR, wallet)
	_check(again.owned.size() == 5 and again.chain == m.chain, "a reload reads the same parts and path")
	# Nothing is bought during a chase.
	SaveStore.chase_active = true
	var bank_now: int = wallet.bank
	_check(not m.buy("air_filter").ok and wallet.bank == bank_now, "no buying while a chase is on")
	SaveStore.chase_active = false

func _short() -> void:
	_fresh(100)
	var m: RefCounted = panel.model
	var cost: int = m.price("service")
	_check(m.card("service").short == cost - 100, "the card says how much the bank is short")
	panel.accept()
	_check(panel.ticket == "" and panel.note.begins_with("Short $"), "Enter while short: no ticket, '%s'" % panel.note)
	_check(not m.buy("service").ok and wallet.bank == 100 and wallet.cash == CASH, "and nothing is taken")
	# Cash is not the bank.
	wallet.add_cash(90000)
	_check(not m.buy("service").ok and wallet.cash == CASH + 90000, "a pocket full of cash buys no mods")

# ---- Keystones need two wires --------------------------------------------------

func _keystone() -> void:
	_fresh(200000)
	var m: RefCounted = panel.model
	_check(m.state("grip") == GarageMods.LOCKED, "a keystone starts locked")
	for id in ["service", "B", "B1"]:
		_must_buy(id)
	var need: String = ModTree.node(CAR, "grip").needs[0]
	_check(m.state("grip") == GarageMods.LOCKED, "engine done, chassis step missing: still locked")
	_check(m.lock_reason("grip").contains(m.items[need].name), "Walt says which chassis step: '%s'" % m.lock_reason("grip"))
	var wires: Array = m.key_wires("grip")
	_check(wires.size() == 2 and wires[0].ok and not wires[1].ok, "the card shows the engine wire lit and the chassis wire missing")
	var bank: int = wallet.bank
	_check(not m.buy("grip").ok and wallet.bank == bank, "it cannot be bought")
	var rung := int(need.get_slice("_", 1))
	for n in range(1, rung + 1):
		_check(m.state("grip") == GarageMods.LOCKED, "still locked before %s_%d" % [need.get_slice("_", 0), n])
		_must_buy("%s_%d" % [need.get_slice("_", 0), n])
	_check(m.state("grip") == GarageMods.BUYABLE, "buying the chassis step lights the keystone")
	_check(m.key_wires("grip")[1].ok, "and the card shows both wires")
	_must_buy("grip")
	_check(m.state("grip") == GarageMods.FITTED and m.chain == ["service", "B", "B1", "grip"], "the keystone is fitted: %s" % str(m.chain))
	_check(GarageMods.spawn_build(CAR).nodes.has("grip"), "and it is on the car at the next spawn")
	# The other keystone has its own chassis wire.
	_check(m.state("slide") == GarageMods.LOCKED, "Slide waits for its own chassis step")

# ---- Branch swap --------------------------------------------------------------

func _swap() -> void:
	# Carries on from _keystone: service, B, B1, grip fitted.
	var m: RefCounted = panel.model
	_write(PlayerTune.path, {"version": 1, "values": {"front_arb_ratio": 0.33}})
	_must_buy("A")
	_check(m.chain == ["service", "A"] and m.state("B") == GarageMods.OWNED and m.state("B1") == GarageMods.OWNED,
		"buying the other side fits it; the old branch is owned, swapped out: %s" % str(m.chain))
	_check(_tune().is_empty(), "the new branch starts on its own (empty) tune")
	_write(PlayerTune.path, {"version": 1, "values": {"front_arb_ratio": 0.55}})
	var bank: int = wallet.bank
	var swaps: Array = []
	panel.swapped.connect(func(id: String) -> void: swaps.append(id))
	panel.selected = "B"
	panel.accept()
	_check(panel.ticket == "" and swaps == ["B"], "Enter on an owned node in the other branch swaps, no ticket")
	_check(wallet.bank == bank and wallet.cash == CASH, "no money taken")
	_check(m.chain == ["service", "B", "B1", "grip"], "the fitted node moved, with what was under it: %s" % str(m.chain))
	_check(m.state("A") == GarageMods.OWNED and m.state("B") == GarageMods.FITTED, "A is owned and swapped out now")
	_check(is_equal_approx(float(_tune().get("front_arb_ratio", 0.0)), 0.33), "the old branch's tune is back: %s" % str(_tune()))
	var saved: Array = SaveStore.load_mod_tree().cars[CAR].installed
	_check("B" in saved and "B1" in saved and not "A" in saved, "mod_tree.json has the swapped path: %s" % str(saved))
	_check((CAR + "/A") in SaveStore.load_garage().owned_parts, "A is still in garage.json")
	_check(GarageMods.spawn_build(CAR).nodes.slice(0, 4) == ["service", "B", "B1", "grip"], "the next spawn is the B car")
	_check(m.swap_to("A") and is_equal_approx(float(_tune().get("front_arb_ratio", 0.0)), 0.55), "and A's tune returns on the way back")
	_check(wallet.bank == bank, "still no money taken")
	# A side node that only fits one branch.
	_must_buy("trumpets")
	_check(m.state("trumpets") == GarageMods.FITTED, "trumpets fit the NA branch")
	m.swap_to("B")
	_check(m.state("trumpets") == GarageMods.OWNED and not "trumpets" in m.installed, "and come off with it")

# ---- King crate ----------------------------------------------------------------

func _crate() -> void:
	_fresh(50000)
	var m: RefCounted = panel.model
	_check(not panel.open_king_crate(), "no crate, nothing to open")
	_must_buy("service")
	_must_buy("B")
	wallet.take_bank(wallet.bank)
	m.king_crates = 1
	_check(panel.open_king_crate() and m.crate_open, "the crate opens")
	_check(m.price("B1") == 0 and m.price("grip") == 0 and m.price("tyres_1") > 0 and m.price("A") > 0, "deep steps and keystones are $0, nothing else")
	_check(m.state("A1") == GarageMods.LOCKED, "a crate does not skip the wires")
	panel.selected = "tyres_1"
	panel.accept()
	_check(panel.ticket == "" and m.crate_open, "the crate is not spent on a chassis step")
	panel.selected = "B1"
	panel.accept()
	_check(panel.ticket == "B1" and m.ticket_text("B1").ends_with("$0?"), "same ticket, at $0: '%s'" % m.ticket_text("B1"))
	panel.accept()
	_check(m.state("B1") == GarageMods.FITTED and wallet.bank == 0 and wallet.cash == CASH, "one step fitted at $0")
	_check(m.king_crates == 0 and not m.crate_open and m.price("B2") > 0, "the crate is used up")
	_check("B1" in SaveStore.load_mod_tree().cars[CAR].installed, "and it is saved like any other part")
	# A crate can wait: Escape closes it unspent.
	m.king_crates = 1
	panel.open_king_crate()
	panel.cancel()
	_check(m.king_crates == 1 and not m.crate_open, "Escape keeps the crate for another night")

# ---- Keys and a drawn frame ------------------------------------------------------

func _keys_and_draw() -> void:
	panel.selected = panel.model.root
	for step in [["ui_right", "tyres_1"], ["ui_up", "tyres_2"], ["ui_down", "tyres_1"], ["ui_left", "service"]]:
		var ev := InputEventAction.new()
		ev.action = step[0]
		ev.pressed = true
		Input.parse_input_event(ev)
		await process_frame
		await process_frame
		_check(panel.selected == step[1], "%s moves along the wire to %s, got %s" % [step[0], step[1], panel.selected])
	# Every node drawn selected once (script errors in _draw would show here).
	for id in panel.model.items:
		panel.selected = id
		panel.queue_redraw()
		await process_frame
	panel.ticket = "B2"
	await process_frame
	panel.ticket = ""
