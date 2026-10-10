class_name BoltOnWorth
extends RefCounted

# Worth sweep for the bolt-on row (mod tree step B1, 2026-10-10): fits each
# item on the Bug after Service, runs the hidden test track (TuneTrack) with
# the scripted driver, and scores it.
#
#   worth = Pace (0-5) + Control (0-3) + Street (-3..3) + flair (0-1), capped at 10
#
# Pace    seconds saved on a 90 s reference loop; 1 point = 0.5 s. The loop is
#         two standing 400 m runs, six 50 m-radius bends taken at the car's
#         peak lateral g, and a fixed traffic gap no part changes (set so the
#         Bug after Service lands on exactly 90 s). Braking is NOT in Pace (it
#         is in Control), so a brake part is not paid twice.
# Control 1 point = 10% fewer mistakes OR 2 m less in 100-0, summed. Mistakes
#         come from the corner run's slide-onset speed: a bot that enters bends
#         at a fixed spread of speeds slides when it enters above the car's own
#         onset speed, so a car that holds on to higher speed makes fewer.
# Street  money and time saved per act-1 night, 1 point = 5% of a night's
#         earnings, from an ASSUMED night ledger in the data file (Stage C
#         payouts are not measured yet). Items the sim cannot see (lamps, tow,
#         heat, wear, fuel) are priced only here; treat them as placeholders.
# flair   authored sound/info value, 0-1; not measurable headless.
#
# Everything except Street and flair comes off the real PlayerCar sim, so the
# scores move when the cars change. Use from a SceneTree script:
#   var rows: Array = await BoltOnWorth.sweep(track, "p0_beater")
#   print(BoltOnWorth.table(rows))

const PACE_MAX := 5.0
const CONTROL_MAX := 3.0
const STREET_MAX := 3.0
const WORTH_MAX := 10.0
const PACE_PT_S := 0.5
## Average driver: shifts a little early. The shift light moves this to the optimum.
const AVERAGE_DRIVER := {"shift_frac": 0.90, "throttle_max": 1.0, "throttle_ramp": 0.5, "brake_max": 0.90}
## Upshift points the shift light's driver can pick from (fraction of redline).
const SHIFT_CANDIDATES := [0.80, 0.85, 0.90, 0.95, 0.97]
## Steering of the bend run. The track's usual 0.3 never reaches the Bug's grip
## limit (it is power-limited and never slides in 30 s), so lateral g and slide
## onset would be noise; 0.7 makes the bend grip-limited, with slide onset
## (12 deg) at about 19 m/s on the Bug.
const BEND_STEER := 0.7
## Past this slide angle the bend run is a spin.
const SPIN_DEG := 45.0

## The test car after Service: the starting point every item is measured from.
static func base_spec(car_id: String) -> Dictionary:
	return BoltOns.apply_deltas(CarSpec.player_spec(car_id), BoltOns.service_deltas())

## Runs the sweep (all items, or the listed ids) and returns one row per item,
## preceded by nothing: the baseline is rows' "base" key on every row.
static func sweep(track: TuneTrack, car_id := "p0_beater", only: Array = []) -> Array:
	var base := base_spec(car_id)
	track.corner_steer = BEND_STEER
	track.driver_profile = TuneTrack.DEFAULT_PROFILE
	var m0: Dictionary = (await track.evaluate([base]))[0]
	var m0_avg: Dictionary = {}  # only run if an item needs the average driver
	var loop: Dictionary = data_loop(m0)
	var rows: Array = []
	for it in BoltOns.items():
		if not only.is_empty() and not (it.id in only) and not (it.get("step_of", "") in only):
			continue
		var has_deltas: bool = not it.get("deltas", {}).is_empty()
		var driver: Dictionary = it.get("driver", {})
		var ref := m0
		var m := m0
		if not driver.is_empty() or has_deltas:
			var profile: Dictionary = TuneTrack.DEFAULT_PROFILE
			if not driver.is_empty():
				profile = AVERAGE_DRIVER.duplicate()
				if m0_avg.is_empty():
					track.driver_profile = profile
					m0_avg = (await track.evaluate([base]))[0]
				ref = m0_avg
				m = ref
			var spec := BoltOns.apply_deltas(base, it.get("deltas", {}))
			if not driver.is_empty():
				profile = profile.duplicate()
				profile.merge(driver, true)
				if profile.shift_frac is String:  # "best": the lamp shows the car's own best upshift point
					profile["shift_frac"] = await _best_shift_frac(track, spec, AVERAGE_DRIVER)
			track.driver_profile = profile
			m = (await track.evaluate([spec]))[0]
		var r := score(it, m, ref, m0, loop)
		if not driver.is_empty():
			r["driver_note"] = "shift at %.2f of redline (average driver: %.2f)" % [float(track.driver_profile.shift_frac), float(AVERAGE_DRIVER.shift_frac)]
		rows.append(r)
	track.corner_steer = TuneTrack.CORNER_STEER
	track.driver_profile = TuneTrack.DEFAULT_PROFILE
	return rows

## The upshift point (of SHIFT_CANDIDATES) with the quickest standing 400 m.
static func _best_shift_frac(track: TuneTrack, spec: Dictionary, profile: Dictionary) -> float:
	var best := float(profile.shift_frac)
	var best_t := INF
	for frac in SHIFT_CANDIDATES:
		var p: Dictionary = profile.duplicate()
		p["shift_frac"] = frac
		track.driver_profile = p
		var m: Dictionary = (await track.evaluate([spec], [TuneTrack.Kind.ACCEL]))[0]
		var t := float(m.get("t_400", INF))
		if t < best_t - 0.0001:
			best_t = t
			best = frac
	return best

## The reference loop's fixed gap, from the baseline run.
static func data_loop(m0: Dictionary) -> Dictionary:
	var cfg: Dictionary = BoltOns.data().get("loop", {})
	var variable := _loop_variable_s(m0, cfg)
	return {"cfg": cfg, "gap_s": float(cfg.get("reference_s", 90.0)) - variable}

static func _bend_time(lat_g: float, radius: float) -> float:
	var v := sqrt(maxf(lat_g, 0.05) * 9.81 * radius)
	return (PI / 2.0 * radius) / v

static func _loop_variable_s(m: Dictionary, cfg: Dictionary) -> float:
	var r := float(cfg.get("bend_radius_m", 50.0))
	return float(cfg.get("accel_runs", 2)) * float(m.get("t_400", NAN)) \
		+ float(cfg.get("bends", 6)) * _bend_time(float(m.get("peak_lat_g", NAN)), r)

## Scores one item. `m` = its metrics, `ref` = the metrics of the same driver
## without it, `m0` = the Bug after Service on the stock driver (calibration).
static func score(it: Dictionary, m: Dictionary, ref: Dictionary, m0: Dictionary, loop: Dictionary) -> Dictionary:
	var ctl: Dictionary = BoltOns.data().get("control_model", {})
	var row := {"id": it.id, "label": it.get("label", it.id), "kind": it.get("kind", ""), "est": float(it.get("est_worth", 0.0)),
		"flair": float(it.get("flair", 0.0)), "giftable": bool(it.get("giftable", not String(it.get("kind", "")).begins_with("sound"))),
		"ok": bool(m.get("ok", false)) and bool(ref.get("ok", false)), "problems": m.get("problems", [])}
	# Pace
	var cfg: Dictionary = loop.cfg
	var loop_ref := float(loop.gap_s) + _loop_variable_s(ref, cfg)
	var loop_m := float(loop.gap_s) + _loop_variable_s(m, cfg)
	row["pace_s"] = loop_ref - loop_m
	# A bend that ends in a spin reads spin, not grip (speed x yaw rate): no
	# lap-time credit, and it is shown. Same rule as tools/balance_sweep.gd.
	row["spins"] = float(m.get("max_slip_deg", 0.0)) > SPIN_DEG and not float(ref.get("max_slip_deg", 0.0)) > SPIN_DEG
	if row.spins:
		row["pace_s"] = 0.0
	row["pace"] = clampf(float(row.pace_s) / PACE_PT_S, 0.0, PACE_MAX)
	# Control
	var brake_m: float = float(ref.get("brake_dist_100", NAN)) - float(m.get("brake_dist_100", NAN))
	var v0 := float(ref.get("v_slide_ms", NAN))
	var v1 := float(m.get("v_slide_ms", NAN))
	var mistakes_pct := 0.0
	var measured := true
	if is_finite(v0) and is_finite(v1):
		var mu := float(ctl.get("mean_fraction", 0.9)) * v0
		var sigma := float(ctl.get("sigma_fraction", 0.1)) * v0
		var rate0 := _mistake_rate(v0, mu, sigma)
		var rate1 := _mistake_rate(v1, mu, sigma)
		mistakes_pct = (rate0 - rate1) / maxf(rate0, 0.0001) * 100.0
	elif it.get("id", "") == "drift_handbrake":
		measured = false  # no handbrake in the test bot
	row["mistakes_pct"] = mistakes_pct
	row["brake_m"] = brake_m if is_finite(brake_m) else 0.0
	row["control_measured"] = measured
	var control := mistakes_pct / float(ctl.get("mistake_pt_pct", 10.0)) + float(row.brake_m) / float(ctl.get("brake_pt_m", 2.0))
	row["control"] = clampf(control, 0.0, CONTROL_MAX)
	# Street
	var st := street_nights(it.get("effects", {}), m0)
	row["street_pct"] = st * 100.0
	row["street"] = clampf(st / float(BoltOns.data().street_model.point_nights), -STREET_MAX, STREET_MAX)
	row["worth"] = minf(float(row.pace) + float(row.control) + float(row.street) + float(row.flair), WORTH_MAX)
	return row

## Normal CDF upper tail (logistic approximation, error < 0.01).
static func _mistake_rate(v_slide: float, mu: float, sigma: float) -> float:
	var z := (v_slide - mu) / sigma
	return 1.0 - 1.0 / (1.0 + exp(-1.702 * z))

## Nights of earnings saved (negative = costs) per act-1 night by an item's
## non-sim effects, from the assumed ledger in the data file.
static func street_nights(fx: Dictionary, m0: Dictionary) -> float:
	var s: Dictionary = BoltOns.data().get("street_model", {})
	var night_len := float(s.get("night_length_s", 1200.0))
	var tows := float(s.get("tows_per_night", 0.0))
	var tow_cost := float(s.get("tow_cost", 0.0))
	var tow_time := float(s.get("tow_time_s", 0.0)) / night_len
	var saved := 0.0
	# Fuel: more range, fewer tows from running dry.
	if fx.has("fuel_range_mul"):
		var cut := clampf((float(fx.fuel_range_mul) - 1.0) / float(s.get("dry_margin", 0.3)), 0.0, 1.0)
		saved += tows * float(s.get("dry_tow_share", 0.5)) * cut * (tow_cost + tow_time)
	# Tow strap: every tow costs and takes less.
	if fx.has("tow_cost_mul") or fx.has("tow_time_mul"):
		saved += tows * (tow_cost * (1.0 - float(fx.get("tow_cost_mul", 1.0))) + tow_time * (1.0 - float(fx.get("tow_time_mul", 1.0))))
	# Oil cooler.
	if fx.has("engine_wear_mul"):
		saved += float(s.get("engine_wear_cost", 0.0)) * (1.0 - float(fx.engine_wear_mul))
	# Noise: heat gain from noise, so cop stops.
	if fx.has("noise_heat_mul"):
		saved += float(s.get("cop_stops_per_night", 0.0)) * float(s.get("cop_stop_cost", 0.0)) \
			* float(s.get("noise_share_of_heat", 0.0)) * (1.0 - float(fx.noise_heat_mul))
	# Seeing: the repair bill's sight-limited share shrinks as the beam outruns
	# the distance needed to stop (reaction + braking from the car's own 100-0).
	var repairs := float(s.get("repairs_per_night", 0.0))
	if fx.has("headlight_range_mul"):
		var v := float(s.get("cruise_speed_ms", 25.0))
		var brake_d := float(m0.get("brake_dist_100", 45.0))
		var decel := pow(100.0 / 3.6, 2.0) / (2.0 * maxf(brake_d, 5.0))
		var needed := v * float(s.get("reaction_s", 1.0)) + v * v / (2.0 * decel)
		var beam0 := float(s.get("headlight_range_m", 55.0))
		var share0 := clampf(needed / beam0, 0.0, 1.0)
		var share1 := clampf(needed / (beam0 * float(fx.headlight_range_mul)), 0.0, 1.0)
		saved += repairs * float(s.get("sight_share", 0.0)) * (share0 - share1)
	# Fog lamps and the blind-spot lamp: a slice of the side-impact bill.
	if fx.has("side_vis_gain"):
		saved += repairs * float(s.get("side_share", 0.0)) * float(fx.side_vis_gain)
	return saved

## Markdown table of a sweep.
static func table(rows: Array) -> String:
	var lines: Array[String] = []
	lines.append("| Item | Kind | Est | Pace s | Pace | Mist % | 100-0 m | Control | Street % night | Street | Flair | **Worth** | vs est |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		lines.append("| %s | %s | %s | %s | %s | %s | %s | %s%s | %s | %s | %s | **%s** | %s%s |" % [
			r.label, r.kind, _f(r.est, 1), _f(r.pace_s, 2), _f(r.pace, 1), _f(r.mistakes_pct, 1), _f(r.brake_m, 1),
			_f(r.control, 1), "" if r.control_measured else " (n/m)", _f(r.street_pct, 1), _f(r.street, 1), _f(r.flair, 1),
			_f(r.worth, 1), _f(float(r.worth) - float(r.est), 1), ("" if r.ok else " PROBLEM") + (" SPINS" if r.spins else "")])
	return "\n".join(PackedStringArray(lines))

static func _f(v: float, places: int) -> String:
	if not is_finite(v):
		return "-"
	return ("%." + str(places) + "f") % v
