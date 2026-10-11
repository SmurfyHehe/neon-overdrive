extends SceneTree

# Each player car's own gearbox (transmissions step 2): every car in
# PlayerCars.KINDS on the hidden test track (TuneTrack), flat out for 35 s with
# the track's own shifting.
#   - the box is the car's own: at most TuneParams.MAX_GEARS gears, each one
#     shorter than the one before; the muscle sedan has its sheet's four, the
#     crossover drives the rear wheels only
#   - shifting: the run goes up through every gear and reaches top gear
#     (the kei's fifth is an overdrive: it tops out in fourth)
#   - speed: 0-100 km/h under the car's ceiling, top speed inside the car's band
#     (the numbers measured on 2026-10-09, with room either side)
#   - the rear-drive crossover holds the corner run without spinning
# Headless, silent, about two minutes. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/gearbox_per_car.gd

## Forward gears each car carries.
const GEARS := {
	"p0_beater": 5, "p1_coupe": 5, "p2_hothatch": 5, "p3_tuner": 5,
	"p4_kei": 5, "p5_muscle": 4, "p6_crossover": 5,
	"p7_wagon": 4, "p17_work_pickup": 5,
	# the specials drive the coupe's spec until their own (S0 stand-ins)
	"m1_monster": 5, "l1_lowrider": 5,
}
## [0-100 km/h ceiling s, top speed floor km/h, top speed ceiling km/h].
## The hot hatch, tuner sedan and crossover were re-measured on 2026-10-11 after
## they lost their factory turbo (28a5e92, the 40-minute night): 185.8, 221.8
## and 220.7 km/h. The wagon and pickup were measured the same day.
const SPEED := {
	"p0_beater": [13.5, 140.0, 168.0],
	"p1_coupe": [6.4, 235.0, 250.0],
	"p2_hothatch": [9.5, 175.0, 205.0],
	"p3_tuner": [7.5, 210.0, 245.0],
	"p4_kei": [12.5, 170.0, 200.0],
	"p5_muscle": [5.8, 257.0, 300.0],
	"p6_crossover": [7.3, 208.0, 242.0],
	"p7_wagon": [12.0, 158.0, 185.0],
	"p17_work_pickup": [7.3, 212.0, 245.0],
	"m1_monster": [6.4, 235.0, 250.0],
	"l1_lowrider": [6.4, 235.0, 250.0],
}
## Cars whose top gear is an overdrive: flat out they stop pulling one gear
## below it, so the run never revs out into top (the kei tops out in fourth).
const OVERDRIVE := ["p4_kei"]
## Past this slide angle the corner run is a spin (tools/balance_sweep.gd).
const SPIN_DEG := 45.0

var fails: Array[String] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	var track := TuneTrack.new()
	root.add_child(track)
	await process_frame
	for k in PlayerCars.KINDS:
		var id: String = k.id
		var spec := CarSpec.player_spec(id)
		var box: Array = spec.gear_ratios
		# A car added to PlayerCars without its row here is a failure, not a
		# script error that leaves the test hanging.
		_check(GEARS.has(id) and SPEED.has(id), "%s has no row in GEARS / SPEED: measure it and add one" % id)
		_check(box.size() == GEARS.get(id, -1), "%s has %d gears, wanted %d" % [id, box.size(), GEARS.get(id, -1)])
		_check(box.size() <= TuneParams.MAX_GEARS, "%s has more than %d gears" % [id, TuneParams.MAX_GEARS])
		for i in range(1, box.size()):
			_check(box[i] < box[i - 1], "%s gear %d (%.2f) is not shorter than gear %d (%.2f)" % [id, i + 1, box[i], i, box[i - 1]])
		var kinds: Array = TuneTrack.ALL_KINDS if id == "p6_crossover" else [TuneTrack.Kind.ACCEL]
		var m: Dictionary = (await track.evaluate([spec], kinds))[0]
		_check(m.ok, "%s: %s" % [id, str(m.problems)])
		var t100: float = m.get("t_0_100", INF)
		var top: float = m.get("top_speed_kmh", 0.0)
		var top_gear: int = m.get("top_gear", 0)
		print("%s: %d gears %s, 0-100 %.2f s, top %.1f km/h, reached gear %d" % [id, box.size(), str(box), t100, top, top_gear])
		var need := box.size() - (1 if id in OVERDRIVE else 0)
		_check(top_gear >= need, "%s only reached gear %d of %d" % [id, top_gear, box.size()])
		if SPEED.has(id):
			var want: Array = SPEED[id]
			_check(t100 <= want[0], "%s 0-100 %.2f s, ceiling %.1f" % [id, t100, want[0]])
			_check(top >= want[1] and top <= want[2], "%s top speed %.1f outside %.0f-%.0f" % [id, top, want[1], want[2]])
		if id == "p6_crossover":
			_check(is_zero_approx(float(spec.front_torque_split)), "the crossover should drive the rear wheels only")
			var slip: float = m.get("max_slip_deg", 0.0)
			print("%s: corner %.2f g, max slip %.1f deg" % [id, m.get("peak_lat_g", 0.0), slip])
			_check(slip <= SPIN_DEG, "the rear-drive crossover spun in the corner run (%.0f deg)" % slip)
	for f in fails:
		printerr("FAIL: ", f)
	print("gearbox_per_car: ", "PASS" if fails.is_empty() else "FAIL")
	quit(0 if fails.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
