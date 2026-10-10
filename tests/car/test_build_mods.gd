extends SceneTree

# Test build: every car fully modded (2026-10-10, Roy: "all the modifications
# equipped on all cars based off their mod tree"). No game boot: for every
# player car it builds the sandbox's fit (ModTree.everything_fit) and prints
# what went on and what the numbers became.
#
# Asserts (exit code 1 on failure):
# - nothing asked for was left off (build().problems is empty)
# - a car with a tree file gets a finished path (Service to a capstone) and
#   its side nodes; every car gets every Workshop item and every part's top rung
# - the built spec is usable: finite, positive mass, torque, redline, gears
# - the stock spec it was built from is untouched
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/test_build_mods.gd

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var ladder: Array = ModTree.shared().get("ladder", {}).get("parts", [])
	var items := ModTree.all_bolt_ons()
	print("test_build_mods: %d Workshop items, %d parts with a ladder" % [items.size(), ladder.size()])
	for id: String in PlayerCars.ids():
		var stock := CarSpec.player_spec(id)
		var before := stock.duplicate(true)
		TuneParams.set_gear_count((stock.gear_ratios as Array).size())  # as PlayerCar does before it builds
		var b := ModTree.build(stock, ModTree.everything_fit(id))
		var s: Dictionary = b.spec
		var tree := ModTree.has_tree(id)
		var rungs: Array[String] = []
		for part in ladder:
			rungs.append("%s: %s" % [part.id, part.rungs[int(b.rungs.get(part.id, 0))]])
		print("\n%s (%s)" % [id, "own tree" if tree else "no tree file yet: Workshop and parts only"])
		print("  tree nodes   %s" % (", ".join(PackedStringArray(b.nodes)) if not b.nodes.is_empty() else "none"))
		print("  Workshop     %d of %d" % [b.bolt_ons.size(), items.size()])
		print("  parts        %s; tyre compound %s" % ["; ".join(PackedStringArray(rungs)), b.get("compound", "")])
		print("  torque       %.0f -> %.0f Nm   mass %.0f -> %.0f kg   redline %.0f -> %.0f   gears %d -> %d   tier %s -> %s" % [
			float(stock.max_torque), float(s.max_torque), float(stock.vehicle_mass), float(s.vehicle_mass),
			float(stock.max_rpm), float(s.max_rpm), (stock.gear_ratios as Array).size(), (s.gear_ratios as Array).size(),
			ModTree.tier_of(stock), ModTree.tier_of(s)])
		print("  boost        %s -> %s   sound hooks %s" % [str(stock.get("boost_kind", "none")), str(s.get("boost_kind", "none")), str(b.sound)])
		print("  not fitted   %s" % ("; ".join(PackedStringArray(b.problems)) if not b.problems.is_empty() else "nothing"))
		_check(b.problems.is_empty(), "%s: %s" % [id, "; ".join(PackedStringArray(b.problems))])
		_check(b.bolt_ons.size() == items.size(), "%s: %d of %d Workshop items" % [id, b.bolt_ons.size(), items.size()])
		for part in ladder:
			_check(int(b.rungs.get(part.id, 0)) == part.rungs.size() - 1, "%s: %s is not on its top rung" % [id, part.id])
		if tree:
			var t := ModTree.tree(id)
			_check(b.nodes.size() >= ModTree.LEVEL_NAMES.size() - 1, "%s: no finished path (%s)" % [id, str(b.nodes)])
			for side in t.side:
				var req := String(t.nodes[side].get("requires", ""))
				if req == "" or req in t.showcase:
					_check(side in b.nodes, "%s: side node %s not fitted" % [id, side])
		_check(is_finite(float(s.max_torque)) and float(s.max_torque) > 0.0 and float(s.vehicle_mass) > 300.0
			and float(s.max_rpm) > float(s.idle_rpm) and (s.gear_ratios as Array).size() >= 3, "%s: the built spec is not usable" % id)
		_check(stock == before, "%s: the stock spec was changed" % id)
	for f in failures:
		printerr("FAIL: ", f)
	print("\ntest_build_mods: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
