extends RefCounted

# One flat-out top-speed run (2026-10-13): a sim-only PlayerCar of `id`
# built from `spec` on its own long, flat ground (a kilometre up, clear of any
# game world), full throttle, shifting at 97% of redline like TuneTrack's
# driver, until the speed stops rising (under FLAT_GAIN km/h gained in
# FLAT_WINDOW s, after 15 s) or `secs` runs out. Engine heat, fuel and damage
# are off (sim_only), as on TuneTrack. Used by tools/top_speed_sweep.gd and
# tests/car/max_tune_speed.gd.
#
# Returns {top (km/h), gear, rpm (where the top was reached), t100, t200 (s,
# -1 if never), t (s driven), why ("drag, top gear", "limiter (top gear)",
# "drag, gear N", "flipped", "time")}.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RUN_SECS := 150.0
const SETTLE := 1.0
const FLAT_WINDOW := 10.0   # s the speed must stop rising for
const FLAT_GAIN := 0.5      # km/h gained in that window = flat
const ROAD_Y := 1000.0
const LANE_X := -400.0

static func run(tree: SceneTree, id: String, spec: Dictionary, secs := RUN_SECS) -> Dictionary:
	var ground := StaticBody3D.new()
	ground.add_to_group("Road")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 2.0, 16000.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(LANE_X, ROAD_Y - 1.0, -7900.0)
	tree.root.add_child(ground)
	var car := PlayerCar.new()
	car.sim_only = true
	car.chassis = id
	car.spec = CarSpec.clone_spec(spec)
	car.spec["automatic_transmission"] = false
	car.position = Vector3(LANE_X, ROAD_Y + 0.3, 0.0)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var st := {"t": -SETTLE, "top": 0.0, "gear": 0, "rpm": 0.0, "t100": -1.0, "t200": -1.0,
		"hist": [], "done": false, "why": "time"}
	car.driver = func(c: PlayerCar) -> void:
		st.t += dt
		c.steering_input = 0.0
		c.handbrake_input = 0.0
		if st.done or st.t < 0.0:
			c.throttle_input = 0.0
			c.brake_input = 1.0
			return
		c.brake_input = 0.0
		c.throttle_input = 1.0
		if c.current_gear >= 1 and c.current_gear < c.gear_ratios.size() and not c.is_shifting \
				and c.motor_rpm >= c.max_rpm * 0.97:
			c.manual_shift(1)
		var kmh := c.current_speed() * 3.6
		if kmh > st.top:
			st.top = kmh
			st.gear = c.current_gear
			st.rpm = c.motor_rpm
		if st.t100 < 0.0 and kmh >= 100.0:
			st.t100 = st.t
		if st.t200 < 0.0 and kmh >= 200.0:
			st.t200 = st.t
		if c.global_transform.basis.y.y < 0.3:
			st.done = true
			st.why = "flipped"
			return
		# Flat: under FLAT_GAIN km/h gained over the last FLAT_WINDOW s.
		var hist: Array = st.hist
		hist.append(kmh)
		var n := int(FLAT_WINDOW / dt)
		if hist.size() > n:
			hist.pop_front()
			if st.t > 15.0 and kmh - float(hist[0]) < FLAT_GAIN:
				st.done = true
				var top_gear: bool = c.current_gear == c.gear_ratios.size()
				# GEVP's limiter cuts at 1.1 x max_rpm (gevp_vehicle.gd).
				st.why = "limiter (top gear)" if top_gear and c.motor_rpm > c.max_rpm * 1.06 \
					else ("drag, top gear" if top_gear else "drag, gear %d" % c.current_gear)
		if st.t >= secs:
			st.done = true
	tree.root.add_child(car)
	while not st.done:
		await tree.physics_frame
	car.queue_free()
	ground.queue_free()
	await tree.physics_frame
	return st
