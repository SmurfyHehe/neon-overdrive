extends SceneTree
# Every player car's interior is its own (Roy, 2026-10-09: "every car must
# have its own individual interior"; 2026-10-10: check it). Reads each car's
# CABIN (CabinSpec) and its shifter (CarSpec.player_spec) and compares every
# pair of cars that have a cabin of their own:
#   - no two share a cluster layout ("cluster_style");
#   - no two share a trim set ("trim": plastics, seats, accent strip);
#   - any two differ in at least MIN_DIFFERENT of the things you see from the
#     seat: cluster, trim, seats, console, shift gate and lever, speedo scale,
#     boost pod style, glove style;
#   - every trim named has an entry in CockpitFrame.TRIMS.
# A car that still wears the coupe's cabin (no CABIN in its data file) is
# listed as a note, not failed: it has no interior of its own to compare.
# Prints the table. Exit code 1 on failure.
# Run: <godot> --headless --audio-driver Dummy --path . -s res://tests/fleet/interior_unique.gd

const MIN_DIFFERENT := 3

var fails := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	var looks := {}
	var borrowed := []
	# the coupe's cabin as the game hands it out (its rearview mirror fitted), so
	# a car that borrows it is still seen as borrowing
	var coupe := CabinSpec.for_kind(P1CoupeBuilder.KIND)
	for k in PlayerCars.KINDS:
		var id := String(k.id)
		var cab := CabinSpec.for_kind(id)
		if id != P1CoupeBuilder.KIND and cab == coupe:
			borrowed.append(id)
			continue
		var spec := CarSpec.player_spec(id)
		var shifter: Dictionary = CarSpec.fit_gate(spec.get("shifter", CarSpec.shifter("h5")), (spec.gear_ratios as Array).size())
		var trim := String(cab.get("trim", "stock"))
		_check(CockpitFrame.TRIMS.has(trim), "%s: no trim set called '%s'" % [id, trim])
		looks[id] = {
			"cluster": String(cab.cluster_style),
			"trim": trim,
			"seats": String(cab.seats),
			"console": "%s %.2f" % [String(cab.console), float(cab.get("console_w", 0.26))],
			"shifter": "%s len %.2f throw %.0f %s" % [str(shifter.gate), float(shifter.lever_len), float(shifter.row_tilt_deg), String(shifter.sequential)],
			"speedo": "%d" % int(cab.speedo_max_kmh),
			"pod": str(GaugePod.STYLES.get(id, {})),
			"gloves": str(DriverModel.GLOVE_STYLES.get(id, {})),
		}
		print("%-16s cluster %-7s trim %-8s seats %-7s console %-12s speedo %s, %d gears, lever %.2f m" % [id, looks[id].cluster, trim,
			looks[id].seats, looks[id].console, looks[id].speedo, (spec.gear_ratios as Array).size(), float(shifter.lever_len)])
	var ids := looks.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = looks[ids[i]]
			var b: Dictionary = looks[ids[j]]
			_check(a.cluster != b.cluster, "%s and %s share the cluster layout '%s'" % [ids[i], ids[j], a.cluster])
			_check(a.trim != b.trim, "%s and %s share the trim '%s'" % [ids[i], ids[j], a.trim])
			var different := 0
			for key in a:
				if a[key] != b[key]:
					different += 1
			_check(different >= MIN_DIFFERENT, "%s and %s differ in only %d things" % [ids[i], ids[j], different])
	for id in borrowed:
		print("NOTE %s has no cabin of its own yet: it wears the coupe's" % id)
	print("interior_unique: %d cars with their own cabin, %d without; %s" % [ids.size(), borrowed.size(), "PASS" if fails == 0 else "FAIL (%d)" % fails])
	quit(0 if fails == 0 else 1)
