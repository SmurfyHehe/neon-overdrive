extends SceneTree

# Save system in the game (run structure 2026-10-09; scripts/save/). Boots
# Game.tscn on a curved, hilly road, drives far enough that the floating origin
# has moved, quits the way the pause menu does, and boots again. Checks
# - quit saves the run, and the relaunch resumes it exactly: same road seed and
#   origin index, the car at the same transform with the same velocity, spin
#   and gear, the clock and radio as they were, and road under the car
# - the resumed car is not kicked by stale positions (no speed burst, upright)
# - the autosave runs on its own while driving
# - nothing is saved during a chase, and a quit mid-chase is a bust on return:
#   the run starts fresh at the start of the road
# - restart starts a fresh run
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/save_resume.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

var game: Node
var phase := 0
var ticks := 0
var fails: Array[String] = []
var saved := {}

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_ROAD_SEED", "")
	SaveStore.root = "user://test_save_resume"
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveDirector.enabled = true
	SaveStore.select_slot(1)
	SaveStore.clear_run()
	SaveStore.load_meta()
	_boot()

func _boot() -> void:
	if game != null:
		root.remove_child(game)
		game.free()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)
	ticks = 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _drive(p: PlayerCar) -> void:
	p.driver = func(c: Vehicle) -> void:
		c.throttle_input = 1.0
		c.brake_input = 0.0
		# Hold the lane: steer back toward the road's centre line.
		var u := RoadFrame.unroll(c.global_position)
		c.steering_input = clampf((u.x - TrafficManager.lane_centre(1, false)) * 0.08, -0.3, 0.3)
		if c.current_gear < 3 and c.motor_rpm > 6000.0:
			c.current_gear += 1

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	var p: PlayerCar = game.get("player")
	var saver = game.get("saver")
	match phase:
		0:
			if ticks == 2:
				game.recenter_dist = 150.0  # move the floating origin early
				_drive(p)
				game.radio.tune_to(1)
				saver._left = 5.0  # the first autosave inside this drive
			if ticks % (Engine.physics_ticks_per_second * 2) == 0:
				print("t=%d z=%.0f origin=%d %.0f km/h gear %d" % [ticks, RoadFrame.unroll(p.global_position).z, game.origin_index, p.linear_velocity.length() * 3.6, p.current_gear])
			if ticks < Engine.physics_ticks_per_second * 14:
				return false
			if game.origin_index == 0:
				_fail("the floating origin never moved; resume is not tested across it")
			if saver.saves < 1:
				_fail("no autosave in 14 s of driving")
			# Quit the way the pause menu does (GameState.quit() emits quitting,
			# then ends the process; the test does the first half).
			game.game_state.quitting.emit()
			saved = saver.capture()
			phase = 1
			_boot()
		1:
			if ticks == 1:
				var run := SaveStore.load_run()
				if run.is_empty():
					_fail("quit did not save the run")
			if ticks < 2:
				return false
			_compare(p, saved)
			_drive(p)
			phase = 2
		2:
			if ticks < 2 + Engine.physics_ticks_per_second:
				return false
			var kmh := p.linear_velocity.length() * 3.6
			var start_kmh: float = SaveDirector.v3(saved.car.lin_vel).length() * 3.6
			# No kick from stale positions: no burst of speed, still upright.
			# (Losing speed is the bot's driving, not the resume.)
			if kmh > start_kmh + 40.0 or not p.global_position.is_finite() or p.global_basis.y.y < 0.5:
				_fail("resumed car was kicked: %.0f km/h (was %.0f), up %.2f" % [kmh, start_kmh, p.global_basis.y.y])
			# A chase starts; nothing saves; the player quits mid-chase.
			saver.save_now()
			SaveStore.begin_chase()
			var before: int = saver.saves
			for i in 3:
				saver.save_now()
			if saver.saves != before:
				_fail("the run was saved during a chase")
			game.game_state.quitting.emit()
			phase = 3
			_boot()
		3:
			if ticks < 4:
				return false
			if not game.saver.busted:
				_fail("quitting mid-chase was not a bust on return")
			if game.origin_index != 0 or p.global_position.length() > 10.0:
				_fail("a busted run should start fresh, car at %s origin %d" % [p.global_position, game.origin_index])
			if SaveStore.take_pending_bust() != 1:
				_fail("the bust is not waiting for a penalty")
			# Restart: a fresh run, not a resume.
			saver.save_now()
			game.game_state.restarting.emit()
			if not SaveStore.load_run().is_empty():
				_fail("restart did not clear the run")
			_finish()
	return false

func _compare(p: PlayerCar, s: Dictionary) -> void:
	if game.road_seed != int(s.road.seed) or game.origin_index != int(s.origin_index):
		_fail("road differs: seed %d/%d origin %d/%d" % [game.road_seed, s.road.seed, game.origin_index, s.origin_index])
	var want := SaveDirector.array_to_xform(s.car.xform)
	var got := p.global_transform
	# One physics tick has run since the restore; allow one tick of motion.
	var tick_move := SaveDirector.v3(s.car.lin_vel).length() / Engine.physics_ticks_per_second * 2.0 + 0.01
	if got.origin.distance_to(want.origin) > tick_move:
		_fail("car moved on resume: %s vs %s (%.3f m)" % [got.origin, want.origin, got.origin.distance_to(want.origin)])
	var tick_turn := SaveDirector.v3(s.car.ang_vel).length() / Engine.physics_ticks_per_second * 2.0 + 0.01
	if got.basis.z.angle_to(want.basis.z) > tick_turn:
		_fail("car heading differs by %.3f rad" % got.basis.z.angle_to(want.basis.z))
	var v_want := SaveDirector.v3(s.car.lin_vel)
	if p.linear_velocity.distance_to(v_want) > maxf(1.0, v_want.length() * 0.05):
		_fail("velocity %s, saved %s" % [p.linear_velocity, v_want])
	if p.current_gear != int(s.car.gear):
		_fail("gear %d, saved %d" % [p.current_gear, s.car.gear])
	if absf(game.night_clock.minutes - float(s.clock.minutes)) > 0.5:
		_fail("clock %.2f, saved %.2f" % [game.night_clock.minutes, s.clock.minutes])
	if game.radio.station != int(s.radio):
		_fail("radio %d, saved %d" % [game.radio.station, s.radio])
	# Road under the car: a ray straight down hits the chunk collider.
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 2.0, p.global_position + Vector3.DOWN * 5.0)
	q.exclude = [p.get_rid()]
	if space.intersect_ray(q).is_empty():
		_fail("no road under the resumed car")
	print("resume: origin %d, car %.1f m from start, %.0f km/h, gear %d" % [game.origin_index,
		want.origin.length(), v_want.length() * 3.6, p.current_gear])

func _finish() -> void:
	SaveDirector.enabled = false
	print("save_resume: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
