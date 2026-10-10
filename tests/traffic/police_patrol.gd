extends SceneTree

# The stand-in patrol car and heat in the real game (police F1).
# - a patrol car spawns on its own, out past the reveal distance and not in
#   view: a C1 patrol body with the cop undercarriage role and full parts,
#   driving its lane at traffic speed;
# - lit and speeding past it head on: spotted, level 1, the one-car icon,
#   night one's jab on the caption (no talk station tuned);
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

## Patrol oncoming in lane 0, `ahead` m in front, player lit or dark at 30 m/s.
func _pass_setup(ahead: float, lights: bool) -> void:
	heat.reset()
	player.set_headlights(lights)
	Harness.launch_player(player, 30.0)
	player.driver = Harness.lane_driver(Harness.lane_x(0), 1.0, 30.0)
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
			if t < 48:
				return false
			var d := police.car.global_position.distance_to(player.global_position)
			_check(police.car.detailed and police.car.visible, "patrol %.0f m away is not in the full sim and drawn" % d)
			_check(heat.seen and heat.level >= PoliceHeat.ONE_CAR, "lit car not seen at %.0f m (level %d)" % [d, heat.level])
			var icons: HeatIcons = game.get("heat_icons")
			_check(icons.icon.visible and icons.icon.kind == "car", "icon %s / %s at level %d" % [icons.icon.visible, icons.icon.kind, heat.level])
			_check(icons.caption.visible and icons.caption.text == PoliceHeat.MOCK_LINE, "night one jab not on the caption: '%s'" % icons.caption.text)
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
