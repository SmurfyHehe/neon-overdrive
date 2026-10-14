extends SceneTree

# Police P5: the cop brain's pure rules, the danger number and the bust ring
# (no game, under a second).
#   <godot> --headless --path . -s res://tests/traffic/cop_brain_pure.gd

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	_danger()
	_bust()
	_slots()
	for f in failures:
		printerr("FAIL: " + f)
	print("cop_brain_pure: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)

func _danger() -> void:
	var line := PoliceRules.DANGER_LINE
	# up with each of the four things the spec names
	_check(PoliceRules.danger(200.0, 0, false, false) > PoliceRules.danger(120.0, 0, false, false), "danger does not rise with speed")
	_check(PoliceRules.danger(150.0, 5, false, false) > PoliceRules.danger(150.0, 0, false, false), "danger does not rise with traffic")
	_check(PoliceRules.danger(150.0, 0, true, false) > PoliceRules.danger(150.0, 0, false, false), "danger does not rise with oncoming cars on an undivided road")
	_check(PoliceRules.danger(150.0, 0, false, true) > PoliceRules.danger(150.0, 0, false, false), "danger does not rise near a junction")
	# where the line falls (balance numbers: P15 may move them)
	_check(PoliceRules.danger(50.0, 12, true, true) == 0.0, "a 50 km/h chase has a danger number")
	_check(PoliceRules.danger(120.0, 3, false, false) < line, "120 km/h past 3 cars is over the line (%.2f)" % PoliceRules.danger(120.0, 3, false, false))
	_check(PoliceRules.danger(200.0, 4, false, false) > line, "200 km/h past 4 cars is under the line (%.2f)" % PoliceRules.danger(200.0, 4, false, false))
	_check(PoliceRules.danger(250.0, 0, false, false) < line, "250 km/h on an empty divided road is over the line (%.2f)" % PoliceRules.danger(250.0, 0, false, false))
	_check(PoliceRules.danger(180.0, 2, true, true) > line, "180 km/h past 2 cars at an undivided junction is under the line (%.2f)" % PoliceRules.danger(180.0, 2, true, true))

func _bust() -> void:
	var dt := 1.0 / 60.0
	# stopped with a cop beside you: full in BUST_SECS
	var f := 0.0
	var n := 0
	while f < 1.0 and n < 1000:
		f = PoliceRules.bust_step(f, dt, 0.0, 2.0)
		n += 1
	_check(absf(n * dt - PoliceRules.BUST_SECS) < 0.05, "the ring filled in %.2f s (%.0f expected)" % [n * dt, PoliceRules.BUST_SECS])
	# never while moving at BUST_KMH or more, never with the cop out of range, never with no cop
	_check(PoliceRules.bust_step(0.0, dt, PoliceRules.BUST_KMH, 1.0) == 0.0, "the ring fills at %.0f km/h" % PoliceRules.BUST_KMH)
	_check(PoliceRules.bust_step(0.0, dt, 0.0, PoliceRules.BUST_RANGE + 0.1) == 0.0, "the ring fills with the cop out of range")
	_check(PoliceRules.bust_step(0.0, dt, 0.0, INF) == 0.0, "the ring fills with no cop")
	_check(PoliceRules.bust_step(0.3, dt, 9.0, PoliceRules.BUST_RANGE) > 0.3, "the ring does not fill at 9 km/h with a cop at the edge of range")
	# it drains when you get going, in BUST_DRAIN_SECS from full, and stops at 0
	f = 1.0
	n = 0
	while f > 0.0 and n < 1000:
		f = PoliceRules.bust_step(f, dt, 40.0, 2.0)
		n += 1
	_check(absf(n * dt - PoliceRules.BUST_DRAIN_SECS) < 0.05, "the ring drained in %.2f s (%.1f expected)" % [n * dt, PoliceRules.BUST_DRAIN_SECS])
	_check(PoliceRules.bust_step(0.0, dt, 40.0, 2.0) == 0.0, "the ring went below empty")
	_check(PoliceRules.bust_step(1.0, dt, 0.0, 2.0) == 1.0, "the ring went over full")

## Cops by heat and graphics tier (Roy 1490), the roles sent (issue #631).
func _slots() -> void:
	var want := [0, 1, 2, 3, 5, 6]
	for preset in ["low", "medium", "high", "custom"]:
		var cap := PoliceRules.near_cops(preset)
		_check(cap == int(PoliceRules.NEAR_COPS.get(preset, PoliceRules.NEAR_COPS["medium"])), "%s allows %d cops near you" % [preset, cap])
		_check(cap <= PoliceRules.MAX_COPS, "%s allows %d cops, more than %d" % [preset, cap, PoliceRules.MAX_COPS])
		for l in range(0, 6):
			_check(PoliceRules.cops_wanted(l, preset) == mini(want[l], cap), "heat %d on %s wants %d cops" % [l, preset, PoliceRules.cops_wanted(l, preset)])
	_check(PoliceRules.near_cops("low") == 3 and PoliceRules.near_cops("medium") == 4 and PoliceRules.near_cops("high") == 6, "tier caps are not 3 / 4 / 6")
	# heat 4 and 5 add cops where the tier has room, and a heavy unit on every tier
	_check(PoliceRules.cops_wanted(4, "high") > PoliceRules.cops_wanted(3, "high"), "heat 4 adds no cops on high")
	_check(PoliceRules.cops_wanted(5, "high") > PoliceRules.cops_wanted(4, "high"), "heat 5 adds no cops on high")
	var H := CopBrain.Role.HEAVY
	for slots in [3, 4, 6]:
		for l in [4, 5]:
			var r := PolicePatrol.roles_wanted(l, slots)
			_check(r.has(H), "heat %d with %d slots sends no heavy unit (%s)" % [l, slots, r])
			_check(r.count(H) <= PoliceRules.MAX_HEAVY, "heat %d with %d slots sends %d heavies" % [l, slots, r.count(H)])
			_check(r.size() == mini(slots, want[l]), "heat %d with %d slots sends %d cops" % [l, slots, r.size()])
		for l in [1, 2, 3]:
			_check(not PolicePatrol.roles_wanted(l, slots).has(H), "heat %d sends a heavy unit" % l)
	_check(PolicePatrol.roles_wanted(1, 6) == [CopBrain.Role.CHASER], "heat 1 is not one chaser")
	_check(PolicePatrol.roles_wanted(0, 6).is_empty(), "heat 0 sends cops")
