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
