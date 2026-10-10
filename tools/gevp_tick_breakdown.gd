class_name GevpTickBreakdown
extends SceneTree

# Where one full-sim traffic car's 120 Hz tick goes, piece by piece, and what
# the C++ tyre maths (GevpTyreNative, native/gevp_tyre) changes (2026-10-10).
# Measurement only. Companion to tools/traffic_profile.gd, same options.
#
# It boots the real game in benchmark mode, lets traffic settle, then at the
# end of the run calls the pieces of every full-sim TrafficCar directly and
# times them (these extra calls disturb the cars, which is why they come last):
#
#   car      the whole _physics_process, the lane controller, aero, and each
#            Vehicle.process_* step
#   wheel    process_forces whole, and its parts: the raycast, the suspension
#            maths, the tyre maths (process_tires)
#   tyre     process_tires alone in a tight loop on two scratch wheels holding
#            a live wheel's state: the GDScript one and (if the library is
#            loaded) the C++ one, in the same process, alternating blocks
#   equal    the same random and live states through both; the largest
#            difference in force and slip
#
# Run:
#   <godot> --headless --fixed-fps 60 --path . --audio-driver Dummy -s res://tools/gevp_tick_breakdown.gd -- --benchmark --secs=12 --traffic=40 --detail=300
# With NEON_NATIVE_TYRES=1 in the environment the cars themselves run the C++
# tyre maths, so "car" and "wheel" show the per-car effect.
# Release build: an export template ignores -s and --path. Copy the release
# template .exe into the project folder, put this in override.cfg next to
# project.godot and run the .exe from there with the options after "--":
#   [application]
#   run/main_loop_type="GevpTickBreakdown"
#
# Output: one line "TICK_JSON {...}" on stdout, also appended to --out=<file>.

const PASSES := 15
const TYRE_CALLS := 20000   # per block
const TYRE_BLOCKS := 9
const EQUAL_SAMPLES := 100000
const STEPS := ["process_drag", "process_braking", "process_steering", "process_throttle", "process_motor",
	"process_clutch", "process_transmission", "process_drive", "process_forces", "process_stability", "process_hill_hold"]
const WITH_DELTA := ["process_braking", "process_steering", "process_throttle", "process_motor", "process_clutch", "process_drive", "process_forces"]
# What process_tires reads from the wheel.
const TYRE_STATE := ["local_velocity", "spin", "tire_radius", "wheel_moment", "applied_torque", "mass_over_wheel",
	"current_tire_stiffness", "contact_patch", "pressure_stiffness_mult", "spring_force", "current_cof", "grip_mult",
	"pressure_grip_mult", "tire_width", "braking_grip_multiplier", "current_longitudinal_grip_ratio",
	"current_lateral_grip_assist", "camber_active", "camber_long_mult", "static_camber", "static_camber_stock",
	"camber_side", "current_rolling_resistance", "pressure_roll_mult", "vehicle"]

var game: Node
var game_t := 0.0
var done := false

func _initialize() -> void:
	# As the project's main loop type (release build) the game scene is already up.
	for c in root.get_children():
		if c.scene_file_path == "res://Game.tscn":
			game = c
	if game == null:
		game = (load("res://Game.tscn") as PackedScene).instantiate()
		root.add_child(game)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	game_t += root.get_process_delta_time()
	if not done and game_t >= Benchmark.run_secs():
		done = true
		_finish()

func _cars() -> Array[TrafficCar]:
	var out: Array[TrafficCar] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is TrafficCar and n.get("detailed") and n.is_physics_processing():
			out.append(n)
	return out

func _wheels(v: Vehicle) -> Array[Wheel]:
	return [v.front_left_wheel, v.front_right_wheel, v.rear_left_wheel, v.rear_right_wheel]

func _median(a: Array) -> float:
	a.sort()
	return a[a.size() / 2]

func _finish() -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	var cars := _cars()
	var out := {
		"when": Time.get_datetime_string_from_system(false, true),
		"build": "debug" if OS.is_debug_build() else "release",
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"physics_hz": Engine.physics_ticks_per_second,
		"native_available": NativeTyres.available(),
		"native_cars": NativeTyres.active(),
		"cars_full_sim": cars.size(),
		"opts": " ".join(OS.get_cmdline_user_args()),
	}
	if cars.is_empty():
		out["error"] = "no full-sim traffic cars"
		_emit(out)
		return

	# The clock itself: two reads back to back, so it can be taken off each piece.
	var t := Time.get_ticks_usec()
	for i in 100000:
		Time.get_ticks_usec()
	var clock_us := (Time.get_ticks_usec() - t) / 100000.0
	out["clock_read_us"] = snappedf(clock_us, 0.001)

	# --- car and wheel pieces, per pass: total us over all cars ---------------
	var runs := {}
	for pass_i in PASSES:
		var tot := {}
		for v in cars:
			if not is_instance_valid(v):
				continue
			var t0 := Time.get_ticks_usec()
			v._physics_process(dt)
			var t1 := Time.get_ticks_usec()
			v.call("_drive", dt)
			var t2 := Time.get_ticks_usec()
			AeroModel.apply(v)
			var t3 := Time.get_ticks_usec()
			_add(tot, "car whole _physics_process", t1 - t0)
			_add(tot, "car lane controller (_drive)", t2 - t1)
			_add(tot, "car aero (AeroModel.apply)", t3 - t2)
			for s in STEPS:
				t0 = Time.get_ticks_usec()
				if s in WITH_DELTA:
					v.call(s, dt)
				else:
					v.call(s)
				_add(tot, "car " + s, Time.get_ticks_usec() - t0)
			for w in _wheels(v):
				t0 = Time.get_ticks_usec()
				w.process_forces(0.0, false, dt)
				t1 = Time.get_ticks_usec()
				w.force_raycast_update()
				t2 = Time.get_ticks_usec()
				w.process_suspension(0.0, dt)
				t3 = Time.get_ticks_usec()
				w.process_tires(false, dt)
				var t4 := Time.get_ticks_usec()
				_add(tot, "wheel whole process_forces", t1 - t0)
				_add(tot, "wheel raycast", t2 - t1)
				_add(tot, "wheel suspension maths", t3 - t2)
				_add(tot, "wheel tyre maths (process_tires)", t4 - t3)
		for key in tot:
			if not runs.has(key):
				runs[key] = []
			runs[key].append(tot[key])
	var pieces := {}
	for key in runs:
		var a: Array = runs[key]
		a.sort()
		var per := float(cars.size()) * (4.0 if String(key).begins_with("wheel") else 1.0)
		# us for one call on one car (or one wheel), clock read taken off.
		pieces[key] = {"us": snappedf(maxf(_median(a) / per - clock_us, 0.0), 0.01), "us_best": snappedf(maxf(float(a[0]) / per - clock_us, 0.0), 0.01)}
	out["pieces"] = pieces

	# --- tyre maths alone: GDScript against C++, same process -----------------
	var live: Wheel = cars[0].rear_left_wheel
	var gd := Wheel.new()
	_copy_state(live, gd)
	var nat: Wheel = null
	if NativeTyres.available():
		nat = (load(NativeTyres.WHEEL_SCRIPT) as GDScript).new()
		_copy_state(live, nat)
	var empty: Array = []
	var gd_us: Array = []
	var nat_us: Array = []
	for b in TYRE_BLOCKS:
		t = Time.get_ticks_usec()
		for i in TYRE_CALLS:
			pass
		empty.append(Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		for i in TYRE_CALLS:
			gd.process_tires(false, dt)
		gd_us.append(Time.get_ticks_usec() - t)
		if nat != null:
			t = Time.get_ticks_usec()
			for i in TYRE_CALLS:
				nat.process_tires(false, dt)
			nat_us.append(Time.get_ticks_usec() - t)
	var loop_us := _median(empty) / TYRE_CALLS
	var tyre := {"calls_per_block": TYRE_CALLS, "blocks": TYRE_BLOCKS, "empty_loop_us": snappedf(loop_us, 0.0001),
		"gdscript_us_per_call": snappedf(_median(gd_us) / TYRE_CALLS - loop_us, 0.001),
		"gdscript_us_per_call_best": snappedf(float(gd_us[0]) / TYRE_CALLS - loop_us, 0.001)}
	if nat != null:
		tyre["native_us_per_call"] = snappedf(_median(nat_us) / TYRE_CALLS - loop_us, 0.001)
		tyre["native_us_per_call_best"] = snappedf(float(nat_us[0]) / TYRE_CALLS - loop_us, 0.001)
	out["tyre"] = tyre

	# --- same answers? ---------------------------------------------------------
	if nat != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261010
		var max_force := 0.0
		var max_slip := 0.0
		var flag_mismatch := 0
		var not_identical := 0
		var worst := {}
		var states: Array = []
		for v in cars:
			for w in _wheels(v):
				states.append(w)
		for i in EQUAL_SAMPLES + states.size():
			var braking := false
			if i < states.size():
				_copy_state(states[i], gd)
				_copy_state(states[i], nat)
			else:
				var lv := Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-70.0, 20.0))
				if i % 50 == 0:
					lv = Vector3.ZERO
				var spin := -lv.z / live.tire_radius * rng.randf_range(0.0, 2.0) if i % 7 != 0 else 0.0
				braking = rng.randf() < 0.3
				var torque := rng.randf_range(0.0, 3000.0) if i % 3 != 0 else 0.0
				var load := rng.randf_range(0.0, 12000.0) if i % 11 != 0 else 0.0
				for x: Wheel in [gd, nat]:
					x.local_velocity = lv
					x.spin = spin
					x.applied_torque = torque
					x.spring_force = load
					x.grip_mult = 0.4 + 0.8 * float(i % 5) / 4.0
			gd.process_tires(braking, dt)
			nat.process_tires(braking, dt)
			var df := maxf(absf(gd.force_vector.x - nat.force_vector.x), absf(gd.force_vector.y - nat.force_vector.y))
			var ds := maxf(absf(gd.slip_vector.x - nat.slip_vector.x), absf(gd.slip_vector.y - nat.slip_vector.y))
			if is_nan(df) != false or is_nan(ds) != false:
				# NaN on both sides counts as the same answer.
				if str(gd.force_vector) != str(nat.force_vector) or str(gd.slip_vector) != str(nat.slip_vector):
					not_identical += 1
				continue
			if df > 0.0 or ds > 0.0 or gd.spin_velocity_diff != nat.spin_velocity_diff:
				not_identical += 1
			if gd.limit_spin != nat.limit_spin:
				flag_mismatch += 1
			if df > max_force:
				max_force = df
				worst = {"gd": str(gd.force_vector), "native": str(nat.force_vector), "lv": str(gd.local_velocity), "spin": gd.spin}
			max_slip = maxf(max_slip, ds)
		out["equal"] = {"samples": EQUAL_SAMPLES + states.size(), "live_states": states.size(), "not_identical": not_identical,
			"limit_spin_mismatch": flag_mismatch, "max_force_diff_n": max_force, "max_slip_diff": max_slip, "worst": worst}
	gd.free()
	if nat != null:
		nat.free()
	_emit(out)

func _add(tot: Dictionary, key: String, us: int) -> void:
	tot[key] = tot.get(key, 0) + us

func _copy_state(from: Wheel, to: Wheel) -> void:
	for p in TYRE_STATE:
		to.set(p, from.get(p))

func _emit(out: Dictionary) -> void:
	var line := JSON.stringify(out)
	print("TICK_JSON ", line)
	var path := Benchmark.opt("out")
	if path != "":
		var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
	quit(0)
