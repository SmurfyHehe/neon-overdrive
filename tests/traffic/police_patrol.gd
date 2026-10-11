extends SceneTree

# The stand-in patrol car and heat in the real game (police F1).
# - a patrol car spawns on its own, out past the reveal distance and not in
#   view: a C1 patrol body with the cop undercarriage role and full parts,
#   driving its lane at traffic speed;
# - lit and speeding past it head on (130 km/h, over lane 0's flow and the line):
#   seen, a warning first (the dim icon, the loudspeaker line on the
#   caption), then level 1 and night one's jab once the 5 s are up;
# - a crash that is the player's fault with a car ahead, seen by the cop:
#   heat 1 at once, no warning; the same crash with the car behind: nothing;
# - the same pass with the headlights off (H): not seen at 35 m;
# - H is a real action with a key, and on the Controls page;
# - a patrol left far behind is dropped, and another one comes.
#   <godot> --headless --path . -s res://tests/traffic/police_patrol.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const MAX_WAIT := 60 * 20

var failures: Array[String] = []
var game: Node
var player: PlayerCar
var police: PolicePatrol
var heat: PoliceHeat
var step := 0
var t := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	OS.set_environment("NEON_POLICE", "1")
	game = Harness.boot(self, 0, 300.0, 11)

func _pz() -> float:
	return RoadFrame.unroll(player.global_position).z

## Patrol oncoming in lane 0, `ahead` m in front, player lit or dark at 36 m/s (130 km/h: over lane 0's flow of 115 plus the margin, so an offence).
func _pass_setup(ahead: float, lights: bool) -> void:
	heat.reset()
	player.set_headlights(lights)
	Harness.launch_player(player, 36.0)
	player.driver = Harness.lane_driver(Harness.lane_x(0), 1.0, 36.0)
	var c := police.car
	c.place(TrafficManager.lane_centre(0, true), 1.0, _pz() - ahead, c.rest_y, 15.0)

func _physics_process(_delta: float) -> bool:
	t += 1
	match step:
		0:
			if t < 5:
				return false
			player = game.get("player")
			police = game.get("police")
			heat = game.get("police_heat")
			_check(police != null and heat != null, "no police / heat in the game with NEON_POLICE=1")
			if police == null or heat == null:
				return _finish()
			(game.get("night_clock") as NightClock).night = 1
			Harness.move_player_to_lane(player, Harness.lane_x(0))
			_check(InputMap.has_action("headlights") and not InputMap.action_get_events("headlights").is_empty(), "no key for headlights")
			_check(SettingsScreen.GROUPS.any(func(g: Array) -> bool: return g[1].any(func(a: Array) -> bool: return a[0] == "headlights")), "headlights missing from the Controls page")
			step = 1
			t = 0
		1:
			if police.car == null:
				if t > MAX_WAIT:
					_check(false, "no patrol car after %d s" % (MAX_WAIT / 60))
					return _finish()
				return false
			var c := police.car
			var d := absf(RoadFrame.unroll(c.global_position).z - _pz())
			_check(c.kind == "c1_patrol" and c.role == Undercarriage.ROLE_COP and c.spec.get("parts") == "full",
				"patrol is %s / role %s / parts %s" % [c.kind, c.role, c.spec.get("parts")])
			var traffic: TrafficManager = game.get("traffic")
			_check(d > traffic.reveal_distance(), "patrol spawned %.0f m away, inside the reveal distance %.0f" % [d, traffic.reveal_distance()])
			_check(heat.cops.has(c), "patrol not registered with heat")
			step = 2
			t = 0
		2:
			if t < 180:
				return false
			var c := police.car
			_check(not c.detailed, "patrol far from the player runs the full sim")
			_check(c.current_speed() > 5.0, "patrol not driving: %.1f m/s after 3 s" % c.current_speed())
			_check(absf(RoadFrame.unroll(c.global_position).x - c.lane_x) < 1.0, "patrol off its lane by %.2f m" % absf(RoadFrame.unroll(c.global_position).x - c.lane_x))
			_pass_setup(90.0, false)
			step = 3
			t = 0
		3:
			# Dark: closing at ~45 m/s from 90 m, at 0.8 s about 55 m apart.
			if t < 48:
				return false
			var d := police.car.global_position.distance_to(player.global_position)
			var lamp := player.get_node_or_null("Headlights") as Node3D
			_check(lamp != null and not lamp.visible, "headlights off but the lamp is lit")
			_check(not heat.seen and heat.level == PoliceHeat.NONE, "dark car seen at %.0f m (level %d)" % [d, heat.level])
			_pass_setup(90.0, true)
			step = 4
			t = 0
		4:
			# 1 s of judgement, then the warning: dim icon, no heat yet.
			if not heat.warning_active and t < 600:
				return false
			var d := police.car.global_position.distance_to(player.global_position)
			_check(police.car.detailed and police.car.visible, "patrol %.0f m away is not in the full sim and drawn" % d)
			_check(heat.warning_active and heat.level == PoliceHeat.NONE, "lit speeding car: warning %s, level %d" % [heat.warning_active, heat.level])
			var icons: HeatIcons = game.get("heat_icons")
			_check(icons.icon.visible and icons.icon.kind == "car" and icons.icon.modulate.a < 1.0, "dim icon %s / %s / %.2f" % [icons.icon.visible, icons.icon.kind, icons.icon.modulate.a])
			_check(icons.caption.visible and PoliceRules.WARN_LINES.values().has(icons.caption.text), "loudspeaker line not on the caption: '%s'" % icons.caption.text)
			step = 41
			t = 0
		41:
			# Ignored for 5 s: heat 1 and night one's jab.
			if t < 700:
				return false
			var icons: HeatIcons = game.get("heat_icons")
			_check(heat.level >= PoliceHeat.ONE_CAR and not heat.warning_active, "warning ignored: level %d" % heat.level)
			_check(icons.icon.visible and icons.icon.kind == "car" and icons.icon.modulate.a == 1.0, "icon %s / %s at level %d" % [icons.icon.visible, icons.icon.kind, heat.level])
			_check(icons.caption.visible and icons.caption.text == PoliceHeat.MOCK_LINE, "night one jab not on the caption: '%s'" % icons.caption.text)
			# Crash: the same pass again, with a car 20 m ahead in the player's lane.
			_pass_setup(90.0, true)
			step = 42
			t = 0
		42:
			if t < 48:
				return false
			var other := PatrolCar.make()   # any traffic car that is not a registered cop
			other.name = "Crashee"
			other.traffic = game.get("traffic")
			other.target_speed = 10.0
			game.add_child(other)
			other.place(Harness.lane_x(0), -1.0, _pz() - 20.0, other.rest_y, 10.0)
			_check(heat.level == PoliceHeat.NONE and not heat.warning_active, "setup: level %d warning %s" % [heat.level, heat.warning_active])
			heat.on_contact(other, 40.0)
			_check(heat.level == PoliceHeat.ONE_CAR and not heat.warning_active, "at-fault crash seen by a cop: level %d warning %s" % [heat.level, heat.warning_active])
			heat.reset()
			other.place(Harness.lane_x(0), -1.0, _pz() + 20.0, other.rest_y, 40.0)
			heat.on_contact(other, 40.0)
			_check(heat.level == PoliceHeat.NONE, "a crash with a car coming from behind is not the player's fault (level %d)" % heat.level)
			other.queue_free()
			# Leave it far behind: dropped, and a fresh one is coming.
			var c := police.car
			c.place(c.lane_x, c.direction, _pz() + 900.0, c.rest_y, 0.0)
			step = 5
			t = 0
		5:
			if t < 10:
				return false
			_check(police.car == null, "patrol 900 m behind not dropped")
			police._wait = 0.0
			step = 6
			t = 0
		6:
			if police.car != null:
				_check(police.spawn_count >= 2, "spawn count %d" % police.spawn_count)
				return _finish()
			if t > MAX_WAIT:
				_check(false, "no second patrol")
				return _finish()
	return false

func _finish() -> bool:
	for f in failures:
		printerr("FAIL: " + f)
	print("police_patrol: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
