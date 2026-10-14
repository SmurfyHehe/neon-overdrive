extends SceneTree

# Wrong way and the illegal turn in PoliceHeat, with a mocked cop that always
# notices (a bare Node3D 40 m off, looking at a lit car). No game.
# - turned round at a gap (seen: +1 heat, the illegal turn), then driving
#   legally up the -x side: no WRONG_SIDE on the legal side;
# - turned round at a city crossing (no gap there): no heat at all;
# - on +x heading up the road: nothing after 1 s, WRONG_SIDE after 2 s;
# - backing up the shoulder under 20 km/h: never; backing up the lanes: yes;
# - a spin never fires it.
#   <godot> --headless --path . -s res://tests/traffic/police_wrong_way.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const WRONG := PoliceRules.Offence.WRONG_SIDE
const GAP := PoliceRules.Offence.MEDIAN_GAP

var failures: Array[String] = []
var heat: PoliceHeat
var player: RigidBody3D
var cop: Node3D
var seen: Array[int] = []       # offences seen, in order
var t := 0
var done := false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	player = RigidBody3D.new()
	player.gravity_scale = 0.0
	var c := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2, 1.4, 4)
	c.shape = b
	player.add_child(c)
	var lamp := Node3D.new()
	lamp.name = "Headlights"
	player.add_child(lamp)
	root.add_child(player)
	cop = Node3D.new()
	root.add_child(cop)
	heat = PoliceHeat.new()
	heat.player = player
	heat.set_physics_process(false)   # stepped by hand below
	root.add_child(heat)
	heat.register_cop(cop)
	heat.offence_seen.connect(func(kind: int, _cop: Node3D) -> void: seen.append(kind))

## The car at road x, z; nose along `nose_z` (-1 down the road, +1 up it);
## moving at `kmh` along `travel_z`. The cop stands 40 m down the road from
## it, looking at it.
func _put(x: float, z: float, nose_z: float, travel_z: float, kmh: float) -> void:
	player.global_position = Vector3(x, 0, z)
	player.rotation = Vector3(0, PI if nose_z > 0.0 else 0.0, 0)
	player.linear_velocity = Vector3(0, 0, travel_z * kmh / 3.6)
	player.angular_velocity = Vector3.ZERO
	cop.rotation = Vector3(0, PI, 0)
	cop.global_position = Vector3(x, 0, z - 40.0)

func _run(seconds: float) -> void:
	for i in int(seconds * 60.0):
		heat._physics_process(1.0 / 60.0)

func _fresh() -> void:
	heat.reset()
	heat.area_override = "city"
	seen.clear()

func _physics_process(_delta: float) -> bool:
	t += 1
	if t < 3 or done:
		return false
	done = true
	_scenarios()
	RoadMap.use(RoadMap.ENDLESS)
	for f in failures:
		printerr("FAIL: " + f)
	print("police_wrong_way: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return false

## Drives across the centre line at road z: with the flow on +x, across, then
## back up the road on -x for `after` seconds.
func _turn_round(z: float, after: float) -> void:
	_put(2.0, z, -1.0, -1.0, 50.0)
	_run(1.0)
	player.global_position.x = 0.2
	player.rotation = Vector3(0, PI * 0.5, 0)
	player.linear_velocity = Vector3(-20.0 / 3.6, 0, 0)
	_run(0.3)
	player.global_position.x = -0.6
	_run(0.3)
	_put(-2.0, z, 1.0, 1.0, 50.0)
	_run(after)

func _scenarios() -> void:
	var lane := RoadChunkBuilder.lane_offset(1)
	var shoulder := RoadChunkBuilder.MEDIAN_GAP + RoadChunkBuilder.MAX_OWN_LANES * RoadChunkBuilder.LANE_W + RoadChunkBuilder.SHOULDER_W * 0.5

	# 1. The legal side. Seen the whole time.
	_fresh()
	_put(-lane, 0.0, 1.0, 1.0, 50.0)
	_run(6.0)
	_check(heat.seen, "the mocked cop does not see the car")
	_check(seen.is_empty() and heat.level == PoliceHeat.NONE and not heat.warning_active, "driving up the -x side with its traffic: offences %s level %d" % [seen, heat.level])
	print("  legal on -x, 6 s seen: offences %s, level %d" % [seen, heat.level])

	# 2. Turned round at a gap in the barrier while seen: the illegal turn is
	# +1 heat, and the legal driving after it adds nothing.
	var road := -1
	for id in RoadMap.ROADS:
		RoadMap.use(id, RoadMap.MAX_ACT)
		if not RoadMap.gaps().is_empty():
			road = id
			break
	if road < 0:
		failures.append("no road with a gap in it to test on")
	else:
		var s_gap := float(RoadMap.gaps()[0].s)
		var z_gap := 0.0
		for zi in range(0, -20000, -5):
			if absf(RoadFrame.s_at(float(zi)) - s_gap) < 5.0:
				z_gap = float(zi)
				break
		_check(RoadMap.gap_in(floori(RoadFrame.s_at(z_gap) / RoadChunkBuilder.CHUNK_LEN)), "did not find the gap at s %.0f" % s_gap)
		_fresh()
		_turn_round(z_gap, 6.0)
		_check(seen == [GAP], "turned round at a gap, then legal on -x: offences %s, expected only the illegal turn" % [seen])
		_check(heat.level == PoliceHeat.ONE_CAR, "the illegal turn seen: level %d, expected 1" % heat.level)
		_check(not heat.warning_active, "a warning is running on the legal side")
		print("  U-turn at the gap (s %.0f) then 6 s legal on -x: offences %s (9 = MEDIAN_GAP), level %d" % [s_gap, seen, heat.level])
		# 3. The same turn where there is no gap (a city crossing): nothing.
		var z_plain := z_gap
		for k in range(1, 40):
			z_plain = z_gap - float(k) * RoadChunkBuilder.CHUNK_LEN
			if not RoadMap.gap_in(floori(RoadFrame.s_at(z_plain) / RoadChunkBuilder.CHUNK_LEN)):
				break
		_fresh()
		_turn_round(z_plain, 6.0)
		_check(seen.is_empty() and heat.level == PoliceHeat.NONE and not heat.warning_active, "U-turn away from a gap: offences %s level %d" % [seen, heat.level])
		print("  U-turn where there is no gap, then 6 s legal on -x: offences %s, level %d" % [seen, heat.level])
	RoadMap.use(RoadMap.ENDLESS)

	# 4. On +x heading up the road, nose first: WRONG_SIDE after 2 s.
	_fresh()
	_put(lane, 0.0, 1.0, 1.0, 60.0)
	_run(1.0)
	_check(seen.is_empty() and not heat.warning_active, "1 s up the +x side already counted: %s" % [seen])
	_run(1.5)
	_check(seen == [WRONG] and heat.warning_active and heat.warning_kind == WRONG, "2.5 s up the +x side: offences %s warning %s" % [seen, heat.warning_active])
	print("  +x heading up the road, 2.5 s: offences %s (2 = WRONG_SIDE), warning %s" % [seen, heat.warning_active])
	# ...and turning back to go with the flow clears the warning.
	_put(lane, 0.0, -1.0, -1.0, 50.0)
	_run(0.5)
	_check(not heat.warning_active and heat.level == PoliceHeat.NONE, "back with the flow did not clear it")

	# 5. Backing up the shoulder at 18 km/h (a missed exit), 10 s: never.
	_fresh()
	_put(shoulder, 0.0, -1.0, 1.0, 18.0)
	_run(10.0)
	_check(seen.is_empty() and heat.level == PoliceHeat.NONE and not heat.warning_active, "backing up the shoulder at 18 km/h: offences %s" % [seen])
	print("  backing up the shoulder at 18 km/h, 10 s: offences %s" % [seen])
	# ...the same on the lanes counts after 2 s, and so does 25 km/h on the shoulder.
	_fresh()
	_put(lane, 0.0, -1.0, 1.0, 18.0)
	_run(1.0)
	_check(seen.is_empty(), "1 s backing up the lanes already counted")
	_run(1.5)
	_check(seen == [WRONG], "backing up the lanes at 18 km/h for 2.5 s: offences %s" % [seen])
	print("  backing up the lanes at 18 km/h, 2.5 s: offences %s" % [seen])
	_fresh()
	_put(shoulder, 0.0, -1.0, 1.0, 25.0)
	_run(2.5)
	_check(seen == [WRONG], "backing up the shoulder at 25 km/h for 2.5 s: offences %s" % [seen])

	# 6. A spin never fires it: 5 s moving up the +x side while turning at
	# 4 rad/s (the nose goes round with it), then 5 s sliding sideways.
	_fresh()
	_put(lane, 0.0, -1.0, 1.0, 50.0)
	player.angular_velocity = Vector3(0, 4.0, 0)
	for i in 300:
		player.rotation = Vector3(0, 4.0 * float(i) / 60.0, 0)
		heat._physics_process(1.0 / 60.0)
	_check(seen.is_empty() and not heat.warning_active, "a spin counted: %s" % [seen])
	_fresh()
	_put(lane, 0.0, -1.0, 1.0, 50.0)
	player.rotation = Vector3(0, PI * 0.5, 0)
	_run(5.0)
	_check(seen.is_empty() and not heat.warning_active, "a sideways slide counted: %s" % [seen])
	print("  spinning / sliding up the +x side, 5 s each: offences %s" % [seen])
