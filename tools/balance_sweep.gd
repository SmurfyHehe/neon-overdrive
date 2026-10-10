extends SceneTree

# Balance sweep (stage G slice 1, 2026-10-09): every car on the hidden test
# track (TuneTrack), across setup presets, driver skill and assists, printed as
# tables so the car ladder can be read in one go. One headless command:
#
#   tools\balance_sweep.bat              the whole grid (about 15 min)
#   tools\balance_sweep.bat quick        Stock, pro driver, assists on (about 40 s)
#
# or directly:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tools/balance_sweep.gd
#
# Environment (all optional, comma lists): SWEEP_CARS, SWEEP_PRESETS,
# SWEEP_SKILLS, SWEEP_ASSISTS, SWEEP_OUT (a CSV path), SWEEP_QUICK=1.
#
# What is measured, and what is derived:
#   0-100, top speed, 100-0 and peak lateral g come straight off the track.
#   Standing 400 m is new (TuneTrack.m.t_400).
#   "Lap" is a SYNTHETIC test lap, not a real circuit (none exists yet):
#     standing 400 m + two 100-0 stops + four 90-degree corners of 50 m radius
#     taken at the car's peak lateral g. It only ranks cars against each other.
#   Heat is the game's PowertrainHealth model replayed offline from the runs'
#     telemetry (the track keeps health off so measurements stay clean):
#     "ENG light" is seconds of flat-out driving until the engine warning
#     (100 C); when the 35 s run is not enough the model is continued at the
#     run's last speed and load (marked ~). "BRK light" is how many
#     back-to-back launch-to-100-and-stop cycles until the brake warning (300 C).
#   Driver skill is the track's scripted driver with weaker limits
#   (TuneTrack.driver_profile), NOT a game AI: there is no rival AI yet.
#   Assists off = traction control 0, stability 0, ABS threshold at its max.
#   A corner run that slides past SPIN_DEG is a spin: its peak g (and so its
#   lap) is shown as "-", since the track's g number is speed x yaw rate.

const DT := 1.0 / 60.0
const CORNER_RADIUS := 50.0
const ENGINE_EXTRAPOLATE_S := 600.0
const MAX_STOPS := 30
## Past this slide angle the corner run is a spin, and TuneTrack's lateral g
## (speed x yaw rate) reads the spin, not grip: the g is dropped from the tables.
const SPIN_DEG := 45.0

const SKILLS := {
	"novice": {"shift_frac": 0.80, "throttle_max": 0.85, "throttle_ramp": 1.5, "brake_max": 0.70},
	"average": {"shift_frac": 0.90, "throttle_max": 1.0, "throttle_ramp": 0.5, "brake_max": 0.90},
	"pro": TuneTrack.DEFAULT_PROFILE,
}
const CAR_ORDER := ["coupe_worn", "n2_cityhatch", "n1_commuter", "n3_pickup", "traffic", "coupe"]
const CAR_LABELS := {
	"coupe_worn": "P1 coupe, as found (starter)",
	"n2_cityhatch": "N2 city hatch (traffic)",
	"n1_commuter": "N1 commuter (traffic)",
	"n3_pickup": "N3 pickup (traffic)",
	"traffic": "generic traffic (traffic_default)",
	"coupe": "P1 coupe, stock",
}

var rows: Array = []

func _initialize() -> void:
	_run()

static func _spec_for(car: String) -> Dictionary:
	match car:
		"coupe": return CarSpec.coupe_default()
		"coupe_worn": return CarSpec.coupe_worn()
		"traffic": return CarSpec.traffic_default()
	if PlayerCars.is_player_kind(car):
		return CarSpec.player_spec(car)  # SWEEP_CARS=p0_beater,p2_hothatch,... (not in the default grid)
	return CarSpec.npc_spec(car)

static func _list(env: String, fallback: Array) -> Array:
	var raw := OS.get_environment(env).strip_edges()
	if raw == "":
		return fallback
	var out: Array = []
	for part in raw.split(","):
		var p: String = part.strip_edges()
		if p != "":
			out.append(p)
	return out

func _run() -> void:
	var quick := OS.get_environment("SWEEP_QUICK") == "1"
	var cars := _list("SWEEP_CARS", CAR_ORDER)
	var presets := _list("SWEEP_PRESETS", ["Stock"] if quick else TunerModel.PRESETS)
	var skills := _list("SWEEP_SKILLS", ["pro"] if quick else ["novice", "average", "pro"])
	var assists := _list("SWEEP_ASSISTS", ["on"] if quick else ["on", "off"])
	var track := TuneTrack.new()
	track.record_heat = true
	root.add_child(track)
	await process_frame
	var total := cars.size() * presets.size() * skills.size() * assists.size()
	var n := 0
	var t0 := Time.get_ticks_msec()
	print("balance sweep: %d cars x %d presets x %d skills x %d assists = %d runs" % [cars.size(), presets.size(), skills.size(), assists.size(), total])
	for car in cars:
		var stock := _spec_for(car)
		for preset in presets:
			var m := TunerModel.new(null, CarSpec.clone_spec(stock), stock)
			if preset != "Stock":
				m.apply_preset(preset)
			for assist in assists:
				var spec := CarSpec.clone_spec(m.spec)
				if assist == "off":
					TuneParams.set_value(spec, "traction_control_max_slip", 0.0)
					TuneParams.set_value(spec, "stability_yaw_strength", 0.0)
					var abs_off: float = TuneParams.find("front_abs_spin_difference_threshold").max
					TuneParams.set_value(spec, "front_abs_spin_difference_threshold", abs_off)
					TuneParams.set_value(spec, "rear_abs_spin_difference_threshold", abs_off)
				for skill in skills:
					n += 1
					track.driver_profile = SKILLS[skill]
					var res: Array = await track.evaluate([spec])
					var r := _row(car, preset, skill, assist, res[0])
					rows.append(r)
					printerr("  [%d/%d] %s %s %s %s: %s" % [n, total, car, preset, skill, assist, _one_line(r)])
	print("sweep took %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_print_tables(cars, presets, skills, assists)
	var out := OS.get_environment("SWEEP_OUT")
	if out != "":
		_write_csv(out)
	quit(0)

# ---------- derived numbers ----------

func _row(car: String, preset: String, skill: String, assist: String, m: Dictionary) -> Dictionary:
	var r := {"car": car, "preset": preset, "skill": skill, "assist": assist,
		"ok": m.ok, "problems": ", ".join(PackedStringArray(m.get("problems", []))),
		"t_0_100": m.get("t_0_100", NAN), "top": m.get("top_speed_kmh", NAN), "t_400": m.get("t_400", NAN),
		"brake_m": m.get("brake_dist_100", NAN), "brake_s": m.get("brake_time", NAN),
		"lat_g": m.get("peak_lat_g", NAN), "slip": m.get("max_slip_deg", NAN)}
	r.spun = is_finite(r.slip) and r.slip > SPIN_DEG
	if r.spun:
		r.lat_g = NAN
	r.lap = _lap(r)
	var eng := _engine_onset(m.get("heat_accel", []))
	r.eng_warn_s = eng.warn
	r.eng_derate_s = eng.derate
	r.eng_extrapolated = eng.extrapolated
	r.eng_peak_c = eng.peak
	var brk := _brake_stops(m.get("heat_brake", []))
	r.brk_stops_warn = brk.warn
	r.brk_stops_fade = brk.fade
	r.brk_peak_1 = brk.peak_1
	return r

## Standing 400 m + two 100-0 stops + four 90-degree corners of CORNER_RADIUS at peak g.
static func _lap(r: Dictionary) -> float:
	if not (is_finite(r.t_400) and is_finite(r.brake_s) and is_finite(r.lat_g)) or r.lat_g <= 0.05:
		return NAN
	var v_corner: float = sqrt(r.lat_g * 9.81 * CORNER_RADIUS)
	var corner_t: float = (PI / 2.0 * CORNER_RADIUS) / v_corner
	return r.t_400 + 2.0 * r.brake_s + 4.0 * corner_t

## Replays the accel run through the engine heat model: seconds of flat-out
## driving until the ENG light and until derate. Continues at the last tick's
## speed and load when the run is too short (extrapolated = true).
static func _engine_onset(log: Array) -> Dictionary:
	var out := {"warn": NAN, "derate": NAN, "extrapolated": false, "peak": NAN}
	if log.is_empty():
		return out
	var h := PowertrainHealth.new()
	var t := 0.0
	var peak: float = h.engine_temp
	var i := 0
	var last: Array = log[log.size() - 1]
	while t < ENGINE_EXTRAPOLATE_S:
		var row: Array = log[i] if i < log.size() else last
		if i >= log.size():
			out.extrapolated = true
		h.step_values(DT, row[1], row[2], row[0], 0.0)
		t += DT
		i += 1
		peak = maxf(peak, h.engine_temp)
		if not is_finite(out.warn) and h.engine_temp >= PowertrainHealth.WARN_C:
			out.warn = t
		if h.engine_temp >= PowertrainHealth.DERATE_C:
			out.derate = t
			break
		# Settled below the light: no point going on.
		if i > log.size() + 60 and absf(h.engine_temp - peak) < 0.01 and h.engine_temp < PowertrainHealth.WARN_C:
			break
	out.peak = peak
	return out

## Repeats the brake run's cycle (launch to 100, full stop) until the BRK light
## and until fade. Returns the cycle count, or MAX_STOPS + 1 if never.
static func _brake_stops(log: Array) -> Dictionary:
	var out := {"warn": NAN, "fade": NAN, "peak_1": NAN}
	if log.is_empty():
		return out
	var h := PowertrainHealth.new()
	for stop in range(1, MAX_STOPS + 1):
		var peak := 0.0
		for row in log:
			h.step_values(DT, row[1], row[2], row[0], row[3])
			peak = maxf(peak, h.brake_temp)
		if stop == 1:
			out.peak_1 = peak
		if not is_finite(out.warn) and peak >= PowertrainHealth.WARN_BRAKE_C:
			out.warn = stop
		if peak >= PowertrainHealth.FADE_START_C:
			out.fade = stop
			break
	if not is_finite(out.warn):
		out.warn = MAX_STOPS + 1
	if not is_finite(out.fade):
		out.fade = MAX_STOPS + 1
	return out

# ---------- output ----------

static func _f(v: float, places := 1) -> String:
	if not is_finite(v):
		return "-"
	return ("%." + str(places) + "f") % v

static func _stops(v: float) -> String:
	if not is_finite(v):
		return "-"
	return ">%d" % MAX_STOPS if v > MAX_STOPS else str(int(v))

static func _eng(r: Dictionary) -> String:
	if not is_finite(r.eng_warn_s):
		return "never (peak %s C)" % _f(r.eng_peak_c, 0)
	return ("~" if r.eng_extrapolated else "") + _f(r.eng_warn_s, 0) + " s"

func _one_line(r: Dictionary) -> String:
	return "0-100 %s s, top %s, lap %s, 100-0 %s m, %s g, eng %s, brk %s stops%s" % [
		_f(r.t_0_100, 2), _f(r.top), _f(r.lap), _f(r.brake_m), _f(r.lat_g, 2), _eng(r), _stops(r.brk_stops_warn),
		"" if r.ok else " PROBLEM: " + r.problems]

func _find(car: String, preset: String, skill: String, assist: String) -> Dictionary:
	for r in rows:
		if r.car == car and r.preset == preset and r.skill == skill and r.assist == assist:
			return r
	return {}

func _print_tables(cars: Array, presets: Array, skills: Array, assists: Array) -> void:
	var base_skill: String = "pro" if skills.has("pro") else skills[skills.size() - 1]
	var base_assist: String = "on" if assists.has("on") else assists[0]
	print("")
	print("## Car ladder (Stock, %s driver, assists %s)" % [base_skill, base_assist])
	print("")
	print("| Car | 0-100 s | 400 m s | Top km/h | Lap s | 100-0 m | Peak g | ENG light after | BRK light after | ok |")
	print("|---|---|---|---|---|---|---|---|---|---|")
	for car in cars:
		var r := _find(car, "Stock", base_skill, base_assist)
		if r.is_empty():
			continue
		print("| %s | %s | %s | %s | %s | %s | %s | %s | %s stops | %s |" % [CAR_LABELS.get(car, car), _f(r.t_0_100, 2), _f(r.t_400, 2), _f(r.top), _f(r.lap), _f(r.brake_m), _f(r.lat_g, 2), _eng(r), _stops(r.brk_stops_warn), "yes" if r.ok else r.problems])
	if presets.size() > 1:
		print("")
		print("## Presets (%s driver, assists %s): 0-100 s / top km/h / lap s / peak g / max slip deg" % [base_skill, base_assist])
		print("")
		print("| Car | " + " | ".join(PackedStringArray(presets)) + " |")
		print("|---|" + "---|".repeat(presets.size()))
		for car in cars:
			var cells: Array = []
			for preset in presets:
				var r := _find(car, preset, base_skill, base_assist)
				cells.append("-" if r.is_empty() else "%s / %s / %s / %s / %s%s" % [_f(r.t_0_100, 2), _f(r.top, 0), _f(r.lap), _f(r.lat_g, 2), _f(r.slip, 0), "" if r.ok else " !"])
			print("| %s | %s |" % [CAR_LABELS.get(car, car), " | ".join(PackedStringArray(cells))])
	if skills.size() > 1 or assists.size() > 1:
		print("")
		print("## Driver skill x assists (Stock): 0-100 s / lap s / 100-0 m / max slip deg")
		print("")
		var heads: Array = []
		for skill in skills:
			for assist in assists:
				heads.append("%s, assists %s" % [skill, assist])
		print("| Car | " + " | ".join(PackedStringArray(heads)) + " |")
		print("|---|" + "---|".repeat(heads.size()))
		for car in cars:
			var cells: Array = []
			for skill in skills:
				for assist in assists:
					var r := _find(car, "Stock", skill, assist)
					cells.append("-" if r.is_empty() else "%s / %s / %s / %s%s" % [_f(r.t_0_100, 2), _f(r.lap), _f(r.brake_m), _f(r.slip, 0), "" if r.ok else " !"])
			print("| %s | %s |" % [CAR_LABELS.get(car, car), " | ".join(PackedStringArray(cells))])
	print("")
	print("## Heat (Stock, %s driver, assists %s)" % [base_skill, base_assist])
	print("")
	print("| Car | ENG light after flat out | ENG derate after | Brake temp after one 100-0 | BRK light after | Brake fade after |")
	print("|---|---|---|---|---|---|")
	for car in cars:
		var r := _find(car, "Stock", base_skill, base_assist)
		if r.is_empty():
			continue
		var derate: String = "never" if not is_finite(r.eng_derate_s) else ("~" if r.eng_extrapolated else "") + _f(r.eng_derate_s, 0) + " s"
		print("| %s | %s | %s | %s C | %s stops | %s stops |" % [CAR_LABELS.get(car, car), _eng(r), derate, _f(r.brk_peak_1, 0), _stops(r.brk_stops_warn), _stops(r.brk_stops_fade)])
	var problems := 0
	for r in rows:
		if not r.ok:
			problems += 1
	print("")
	print("%d runs, %d with problems" % [rows.size(), problems])

func _write_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("could not write ", path)
		return
	var keys := ["car", "preset", "skill", "assist", "ok", "t_0_100", "t_400", "top", "lap", "brake_m", "brake_s", "lat_g", "slip", "spun", "eng_warn_s", "eng_derate_s", "eng_extrapolated", "eng_peak_c", "brk_peak_1", "brk_stops_warn", "brk_stops_fade", "problems"]
	f.store_line(",".join(PackedStringArray(keys)))
	for r in rows:
		var cells: Array = []
		for k in keys:
			var v = r[k]
			cells.append(("%.4f" % v) if v is float else str(v))
		f.store_line(",".join(PackedStringArray(cells)))
	f.close()
	print("wrote ", path)
