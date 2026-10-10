extends SceneTree

# Boost stages test (C1, 2026-10-09), headless and silent:
# - a naturally aspirated car: multiplier exactly 1.0, no ForcedInduction object
# - "single" is the old GEVP turbo bit for bit (compared with a copy of the old code)
# - twin spools earlier, tops out a little lower; Roots is instant, never blows off;
#   sequential hands over once on a pull; twincharger fills the bottom, then
#   drops the blower out
# - sweep: every kind at every boost on TuneTrack (accel, brake, corner): no run
#   fails or goes non-finite, boost always makes the car quicker, and a car with
#   a boost kind but no boost drives exactly like the plain car
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/forced_induction.gd

const DT := 1.0 / 60.0
const BOOSTS := [0.5, 3.0]  # Tuner range is 0-1.5, Advanced goes to 3.0; 1.0 gets the full runs

var failures: Array[String] = []
var _made: Array[Vehicle] = []

func _initialize() -> void:
	_units()
	_sweep()

func _car(kind: String, boost_max := 1.0) -> Vehicle:
	var v := Vehicle.new()
	_made.append(v)
	v.max_rpm = 7000.0
	v.idle_rpm = 1000.0
	v.turbo_boost_max = boost_max
	if kind != "":
		ForcedInduction.set_kind(v, kind)
	return v

## Holds rpm and throttle for `secs`; returns the last multiplier.
func _hold(v: Vehicle, rpm: float, thr: float, secs: float) -> float:
	var m := 1.0
	for i in int(round(secs / DT)):
		v.motor_rpm = rpm
		v.throttle_amount = thr
		m = ForcedInduction.step(v, DT)
	return m

func _units() -> void:
	# naturally aspirated
	var na := _car("")
	na.turbo_boost_max = 0.0
	var m := _hold(na, 5000.0, 1.0, 1.0)
	_check(m == 1.0 and na.boost == 0.0, "NA: multiplier %.4f, boost %.3f" % [m, na.boost])
	_check(ForcedInduction.of(na) == null, "NA: should not get a ForcedInduction object")

	# single == the old GEVP code, every tick of a pull, lift, re-pull and shift-like drop
	var a := _car("")
	var ref := {"boost": 0.0, "prev": 0.0, "bo": 0}
	var worst := 0.0
	for i in 600:
		var rpm := 1500.0 + 9.0 * i if i < 500 else 3000.0
		var thr := 1.0 if (i < 200 or (i > 260 and i < 400) or i > 420) else (0.1 if i % 2 == 0 else 0.0)
		a.motor_rpm = rpm
		a.throttle_amount = thr
		var got := ForcedInduction.step(a, DT)
		var want := _old_turbo(ref, a, DT)
		worst = maxf(worst, absf(got - want) + absf(a.boost - ref.boost))
	_check(worst == 0.0, "single should match the old GEVP turbo exactly, worst diff %.9f" % worst)
	_check(a.blow_off_count == ref.bo and ref.bo > 0, "single blow-offs %d, old code %d" % [a.blow_off_count, ref.bo])

	# twin vs single: earlier, smoother, a little less on top
	var s := _car("single")
	var t := _car("twin")
	_hold(s, 3500.0, 1.0, 0.5)
	_hold(t, 3500.0, 1.0, 0.5)
	print("3500 rpm after 0.5 s: single %.3f bar, twin %.3f bar" % [s.boost, t.boost])
	_check(t.boost > s.boost * 1.3, "twin should spool earlier (%.3f vs single %.3f)" % [t.boost, s.boost])
	var ms := _hold(s, 7000.0, 1.0, 5.0)
	var mt := _hold(t, 7000.0, 1.0, 5.0)
	print("full boost multiplier: single %.3f, twin %.3f" % [ms, mt])
	_check(mt < ms and mt > ms - 0.06, "twin should have slightly less top power (%.3f vs %.3f)" % [mt, ms])

	# Roots: no lag, strong low down, no blow-off, a little parasitic loss on top
	var r := _car("roots")
	_hold(r, 2000.0, 1.0, 0.2)
	_check(r.boost > 0.55, "roots should make boost at once at 2000 rpm, has %.3f" % r.boost)
	var bo := r.blow_off_count
	_hold(r, 6000.0, 1.0, 1.0)
	_hold(r, 6000.0, 0.0, 0.5)
	_check(r.blow_off_count == bo, "roots should never blow off")
	var mr := _hold(r, 7000.0, 1.0, 1.0)
	_check(mr < ms, "roots should have less top end than a single turbo (%.3f vs %.3f)" % [mr, ms])
	_check(ForcedInduction.of(r).blower_whine > 0.9, "roots whine should follow crank speed")

	# sequential: small turbo first, one handover on a pull
	var q := _car("sequential")
	var fq := ForcedInduction.of(q, true)
	var s2 := _car("single")
	var low_q := 0.0
	var low_s := 0.0
	for i in 360:
		var rpm := 1500.0 + 15.0 * i
		q.motor_rpm = rpm
		q.throttle_amount = 1.0
		ForcedInduction.step(q, DT)
		s2.motor_rpm = rpm
		s2.throttle_amount = 1.0
		ForcedInduction.step(s2, DT)
		if i == 120:
			low_q = q.boost
			low_s = s2.boost
	_hold(q, 7000.0, 1.0, 3.0)
	print("sequential at 3300 rpm %.3f bar (single %.3f), handovers %d, stage %d, full %.3f" % [low_q, low_s, fq.handover_count, fq.seq_stage, q.boost])
	_check(low_q > low_s, "sequential should have more low-down boost than a single")
	_check(fq.handover_count == 1 and fq.seq_stage == 2, "one handover on a pull, got %d (stage %d)" % [fq.handover_count, fq.seq_stage])
	_check(q.boost > 0.9, "sequential should reach full boost on top, %.3f" % q.boost)

	# twincharger: blower at the bottom, turbo on top
	var c := _car("twincharger")
	var fc := ForcedInduction.of(c, true)
	_hold(c, 1800.0, 1.0, 0.3)
	_check(c.boost > 0.4 and fc.sc_engaged, "twincharger should boost at 1800 rpm on the blower (%.3f)" % c.boost)
	_hold(c, 6500.0, 1.0, 4.0)
	_check(not fc.sc_engaged and c.boost > 0.8, "twincharger on top: blower out, turbo boost %.3f" % c.boost)
	_check(c.boost <= c.turbo_boost_max + 1e-6, "twincharger boost over max")

	# readable data and the spec route
	for k in ForcedInduction.KIND_NAMES:
		var v := _car(k)
		_hold(v, 5000.0, 1.0, 1.0)
		var snap := ForcedInduction.of(v).snapshot()
		_check(snap.kind == k and snap.stages.size() == ForcedInduction.STAGE_DEFS[k].size(), "%s: snapshot %s" % [k, snap])
		_check(snap.boost_frac >= 0.0 and snap.boost_frac <= 1.0, "%s: boost_frac %.3f" % [k, snap.boost_frac])
	var spec_car := _car("")
	CarSpec.apply(spec_car, {"boost_kind": "nonsense", "turbo_boost_max": 0.7})
	_hold(spec_car, 4000.0, 1.0, 0.1)
	_check(ForcedInduction.of(spec_car).kind == "single", "an unknown boost_kind should fall back to single")
	CarSpec.apply(spec_car, {"boost_kind": "roots"})
	_hold(spec_car, 4000.0, 1.0, 0.1)
	_check(ForcedInduction.of(spec_car).kind == "roots", "changing boost_kind should take effect")

## A copy of the turbo block gevp_vehicle.gd process_motor() had before C1.
func _old_turbo(st: Dictionary, v: Vehicle, delta: float) -> float:
	var flow := v.throttle_amount * clampf((v.motor_rpm - v.turbo_rpm_thresh) / maxf(v.max_rpm - v.turbo_rpm_thresh, 1.0), 0.0, 1.0)
	var target := v.turbo_boost_max * flow
	var tau := v.turbo_tau_up if target > st.boost else v.turbo_tau_down
	st.boost += (target - st.boost) * (1.0 - exp(-delta / maxf(tau, 0.01)))
	if st.prev > 0.5 and v.throttle_amount < 0.2 and st.boost > 0.3 * v.turbo_boost_max:
		st.bo += 1
	var m: float = 1.0 + v.turbo_gain * st.boost / v.turbo_boost_max
	st.prev = v.throttle_amount
	return m

func _sweep() -> void:
	var track := TuneTrack.new()
	root.add_child(track)
	await process_frame
	var specs: Array = []
	var names: Array[String] = []
	specs.append(CarSpec.coupe_default())
	names.append("NA")
	var na_kind := CarSpec.coupe_default()
	na_kind["boost_kind"] = "twin"  # a kind but no boost: must drive exactly like NA
	specs.append(na_kind)
	names.append("NA+kind")
	for k in ForcedInduction.KIND_NAMES:
		var s := CarSpec.coupe_default()
		s["boost_kind"] = k
		s["turbo_boost_max"] = 1.0
		specs.append(s)
		names.append("%s 1.0" % k)
	# accel, brake and corner for the above; the other boost levels accel only (time)
	var res: Array = await track.evaluate(specs)
	var accel_specs: Array = []
	for k in ForcedInduction.KIND_NAMES:
		for b in BOOSTS:
			var s := CarSpec.coupe_default()
			s["boost_kind"] = k
			s["turbo_boost_max"] = b
			accel_specs.append(s)
			names.append("%s %.1f" % [k, b])
	res.append_array(await track.evaluate(accel_specs, [TuneTrack.Kind.ACCEL]))
	var na: Dictionary = res[0]
	for i in res.size():
		var m: Dictionary = res[i]
		print("%-16s ok=%s 0-100 %.2f s  top %.1f km/h  brake %.1f m  lat %.2f g" % [names[i], m.ok, m.get("t_0_100", -1.0), m.get("top_speed_kmh", -1.0), m.get("brake_dist_100", -1.0), m.get("peak_lat_g", -1.0)])
		_check(m.ok, "%s: %s" % [names[i], m.problems])
		if i >= 2:
			_check(m.get("t_0_100", 99.0) < na.t_0_100, "%s should beat NA 0-100 (%.2f vs %.2f)" % [names[i], m.get("t_0_100", 99.0), na.t_0_100])
	for key in ["t_0_100", "top_speed_kmh", "brake_dist_100", "peak_lat_g", "max_slip_deg"]:
		_check(res[1].get(key) == na.get(key), "NA+kind %s %s differs from NA %s" % [key, res[1].get(key), na.get(key)])
	_end()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end() -> void:
	for v in _made:
		v.free()
	for f in failures:
		printerr("FAIL: ", f)
	print("forced_induction: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
