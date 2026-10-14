extends SceneTree

# The heat-5 helicopter (police spec P12, issue #631) in the real game, with
# the clean bot driving at 110 km/h through 8 traffic cars:
#   - heat 5 puts one helicopter up, out of view, and it gets over the player
#     (within ARRIVE_SECS);
#   - over open road it sees the player on nearly every look;
#   - a roof over the player (a tunnel, a bridge deck) hides the player from
#     it;
#   - "cooling needs broken sight": with no cop seeing the player and heat
#     about to drop, heat 5 holds while the helicopter has the player, and
#     drops once the roof hides the player;
#   - under heat 5 it leaves and is gone, and never flew faster than its top
#     speed; it is not one of the driving-cop slots.
# Prints its cost a tick. Needs --fixed-fps 60 (about 1.5 min):
#   <godot> --headless --fixed-fps 60 --path . -s res://tests/traffic/police_helicopter.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const ARRIVE_SECS := 30.0
const OPEN_SEES := 0.9          # share of looks over open road that see the player
const ROOF_BLIND := 0.9         # share of looks under the roof that do not
const GONE_SECS := 60.0

var failures: Array[String] = []
var game: Node
var p: PlayerCar
var police: PolicePatrol
var heat: PoliceHeat
var traffic: TrafficManager
var bot: RefCounted
var phase := 0
var t := 0.0
var game_t := 0.0
var heli: PoliceHelicopter
var spawn_seen := false
var arrive_t := -1.0
var fastest := 0.0
var open_looks := 0
var open_sees := 0
var roof_looks := 0
var roof_sees := 0
var last_looks := 0
var roof: StaticBody3D
var held_level := -1
var dropped_level := -1
var saved_cops: Array[Node3D] = []
var pushed := false
var most_units := 0
var gone_t := -1.0
var cost_us := 0
var cost_runs := 0

func _check(ok: bool, msg: String) -> void:
	if not ok and not failures.has(msg):
		failures.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	OS.set_environment("NEON_POLICE", "1")
	OS.set_environment("NEON_NEAR_MISS_LOG", "")
	game = Harness.boot(self, 8, 300.0, 3, 300.0)

func _physics_process(delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < 60:
			p = null
			return false
		police = game.get("police")
		heat = game.get("police_heat")
		traffic = game.get("traffic")
		_check(police != null, "no police in the game with NEON_POLICE=1")
		if police == null:
			return _finish()
		(game.get("night_clock") as NightClock).night = 2
		p.set_headlights(true)
		bot = TestDriver.start(game, "clean", {"speed": 110.0, "seed": 3, "lane": 1})
		Harness.launch_player(p, 110.0 / 3.6)
		return false
	t += delta
	game_t += delta
	most_units = maxi(most_units, police.units.size())
	if police.heli != null:
		if heli != police.heli:
			heli = police.heli
			spawn_seen = traffic.in_view(heli.global_position)
			_check(not spawn_seen, "the helicopter was put up in view")
		fastest = maxf(fastest, heli.vel.length())
		if OS.get_environment("HELI_DEBUG") != "" and Engine.get_physics_frames() % 120 == 0:
			print("  t=%.0f phase %d heli %s spot %s player %s d=%.0f v=%.0f sees %s" % [game_t, heli.phase, RoadFrame.unroll(heli.global_position), RoadFrame.unroll(heli._spot()), RoadFrame.unroll(p.global_position), heli.global_position.distance_to(heli._spot()), heli.vel.length(), heli.sees])
	if roof != null:
		roof.global_position = p.global_position + Vector3.UP * 7.0
	match phase:
		0:
			# heat 5 until it is over the player
			heat._raise_to(5.0)
			if heli != null and heli.arrived:
				arrive_t = t
				phase = 1
				t = 0.0
				last_looks = heli.looks
			elif t > ARRIVE_SECS:
				_check(false, "the helicopter was not over the player %.0f s after heat 5 (sent %d)" % [ARRIVE_SECS, police.helis_sent])
				return _finish()
		1:
			# open road: it sees
			heat._raise_to(5.0)
			_count(false)
			if t > 10.0:
				_add_roof()
				phase = 2
				t = 0.0
		2:
			# under a roof: it does not
			heat._raise_to(5.0)
			if t > 0.6:
				_count(true)
			else:
				last_looks = heli.looks
			if t > 6.0:
				roof.queue_free()
				roof = null
				phase = 3
				t = 0.0
		3:
			# cooling: nobody on the road sees the player, the heat is a moment
			# from dropping; the helicopter alone holds it at 5
			if t < 0.05:
				saved_cops = heat.cops.duplicate()
				heat.cops.clear()
			heat.seen = false
			if t > 1.0 and not pushed:
				pushed = true   # once: the unseen clock half a second from the drop
				heat._unseen_t = maxf(heat._unseen_t, PoliceRules.drop_after(5, false) - 0.5)
			if t >= 4.0 and held_level < 0:
				held_level = heat.level
				cost_us = heli.step_us
				cost_runs = heli.step_runs
				_add_roof()
			if t >= 7.0:
				dropped_level = heat.level
				for c in saved_cops:
					heat.register_cop(c)
				roof.queue_free()
				roof = null
				heat._clear_heat()
				heat._raise_to(4.0)
				phase = 4
				t = 0.0
		4:
			# heat 4: it goes home
			heat._raise_to(4.0)
			if police.heli == null:
				gone_t = t
				_check(not heat.helicopter_sees, "the helicopter is gone and the heat still says it sees the player")
				return _finish()
			if t > GONE_SECS:
				_check(false, "the helicopter was still up %.0f s after the heat dropped to 4" % GONE_SECS)
				return _finish()
	if game_t > 200.0:
		_check(false, "ran out of time in phase %d" % phase)
		return _finish()
	return false

func _count(under_roof: bool) -> void:
	if heli.looks == last_looks:
		return
	last_looks = heli.looks
	if under_roof:
		roof_looks += 1
		if heli.sees:
			roof_sees += 1
	else:
		open_looks += 1
		if heli.sees:
			open_sees += 1

func _add_roof() -> void:
	roof = StaticBody3D.new()
	roof.name = "TestRoof"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	roof.add_child(shape)
	game.add_child(roof)
	roof.global_position = p.global_position + Vector3.UP * 7.0

func _finish() -> bool:
	var per_tick := float(cost_us) / maxf(float(cost_runs), 1.0)
	print("police_helicopter: sent %d, over the player %.1f s after heat 5; fastest %.0f km/h (top %.0f); open road sees %d / %d looks, under the roof %d / %d" % [
		police.helis_sent if police != null else 0, arrive_t, fastest * 3.6, PoliceHelicopter.TOP_SPEED * 3.6, open_sees, open_looks, roof_sees, roof_looks])
	print("police_helicopter: heat held at %d while it saw the player, %d once it could not; gone %.1f s after heat 4; driving cops at most %d (slots %d); cost %.1f us a tick (%d ticks)" % [
		held_level, dropped_level, gone_t, most_units, PoliceRules.near_cops(), per_tick, cost_runs])
	if bot != null:
		print("police_helicopter: bot " + String(bot.call("summary")))
	_check(police == null or police.helis_sent == 1, "%d helicopters were sent for one heat-5 spell" % (police.helis_sent if police != null else 0))
	_check(fastest <= PoliceHelicopter.TOP_SPEED + 1.0, "the helicopter flew at %.0f km/h (top %.0f)" % [fastest * 3.6, PoliceHelicopter.TOP_SPEED * 3.6])
	_check(open_looks > 0 and float(open_sees) / open_looks >= OPEN_SEES, "over open road it saw the player on %d of %d looks" % [open_sees, open_looks])
	_check(roof_looks > 0 and float(roof_looks - roof_sees) / roof_looks >= ROOF_BLIND, "under a roof it still saw the player on %d of %d looks" % [roof_sees, roof_looks])
	_check(held_level == PoliceHeat.HELICOPTER, "with only the helicopter seeing the player, heat went to %d (should hold at 5)" % held_level)
	_check(dropped_level == PoliceHeat.HEAVY, "with the helicopter blind and the time up, heat was %d (should drop to 4)" % dropped_level)
	_check(most_units <= PoliceRules.near_cops(), "%d driving cops (the helicopter is not one of the slots)" % most_units)
	print("police_helicopter: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
