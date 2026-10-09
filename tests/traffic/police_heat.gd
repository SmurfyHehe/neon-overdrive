extends SceneTree

# Police heat, F0 (scripts/traffic/police_heat.gd, scripts/ui/heat_icons.gd).
# No game, its own little world:
# - can_see: lit far ahead yes, dark far ahead no, dark close yes, behind
#   only within mirror range, beside only up close;
# - cop_can_see_player: a wall between them blocks it, gone = seen;
# - heat: seen over the limit = level 1 at once and rising; under the limit
#   holds; unseen cools only after COOL_DELAY; a bad cop never raises it;
# - icons: a distinct icon for each of levels 1-5, none at 0; the HUD icon
#   follows the level;
# - night one: one warning when a patrol comes near, one jab when spotted;
#   night two says nothing.
#   <godot> --headless --path . -s res://tests/traffic/police_heat.gd

var failures: Array[String] = []
var heat: PoliceHeat
var icons: HeatIcons
var player: RigidBody3D
var cop: Node3D
var wall: StaticBody3D
var lines: Array[String] = []
var step := 0
var t := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	_geometry()
	_icon_names()
	player = RigidBody3D.new()
	player.gravity_scale = 0.0
	player.add_child(_box())
	root.add_child(player)
	cop = Node3D.new()
	root.add_child(cop)
	heat = PoliceHeat.new()
	heat.player = player
	heat.set_physics_process(false)   # stepped by hand below
	root.add_child(heat)
	heat.line_said.connect(func(s: String) -> void: lines.append(s))
	icons = HeatIcons.new(heat)
	root.add_child(icons)

func _box() -> CollisionShape3D:
	var c := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2, 1.4, 4)
	c.shape = b
	return c

## Cop at the origin facing -Z (forward), player `at`.
func _geometry() -> void:
	var xf := Transform3D.IDENTITY
	var cases := [
		[Vector3(0, 0, -100), true, true, "lit, 100 m ahead"],
		[Vector3(0, 0, -100), false, false, "dark, 100 m ahead"],
		[Vector3(0, 0, -15), false, true, "dark, 15 m ahead"],
		[Vector3(0, 0, -150), true, false, "lit, 150 m ahead (past SEE_RANGE_LIT)"],
		[Vector3(0, 0, 100), true, false, "lit, 100 m behind"],
		[Vector3(0, 0, 40), true, true, "lit, 40 m behind (mirrors)"],
		[Vector3(10, 0, 0), false, true, "dark, 10 m beside"],
		[Vector3(30, 0, 0), true, false, "lit, 30 m straight out to the side"],
		[Vector3(30, 0, -40), true, true, "lit, 50 m ahead-right (inside the cone)"],
	]
	for c in cases:
		_check(PoliceHeat.can_see(xf, c[0], c[1]) == c[2], "can_see %s should be %s" % [c[3], c[2]])

func _icon_names() -> void:
	_check(PoliceHeat.icon_for(0) == "", "level 0 has an icon")
	var seen := {}
	for l in range(1, PoliceHeat.MAX_LEVEL + 1):
		var k := PoliceHeat.icon_for(l)
		_check(k != "" and not seen.has(k), "level %d icon '%s' is empty or repeats" % [l, k])
		seen[k] = true
	_check(PoliceHeat.MAX_LEVEL == 5 and seen.size() == 5, "expected 5 levels with 5 icons")

func _place(cop_z: float, lights: bool, kmh: float) -> void:
	cop.global_position = Vector3(0, 0, cop_z)
	player.global_position = Vector3.ZERO
	player.linear_velocity = Vector3(0, 0, -kmh / 3.6)
	player.set_meta("lights", lights)
	var lamp := player.get_node_or_null("Headlights") as Node3D
	if lamp == null:
		lamp = Node3D.new()
		lamp.name = "Headlights"
		player.add_child(lamp)
	lamp.visible = lights

## Seconds of heat ticks (and looks) at 60 Hz.
func _run(seconds: float) -> void:
	for i in int(seconds * 60.0):
		heat._physics_process(1.0 / 60.0)

func _physics_process(_delta: float) -> bool:
	t += 1
	if t < 3:
		return false   # let the physics world register the bodies
	match step:
		0:
			# Cop 60 m ahead, facing the player (rotated 180), lit, 120 km/h.
			cop.rotation = Vector3(0, PI, 0)
			heat.register_cop(cop)
			_place(-60.0, true, 120.0)
			_check(heat.cop_can_see_player(cop), "a lit car 60 m in front of a cop is not seen")
			_place(-60.0, false, 120.0)
			_check(not heat.cop_can_see_player(cop), "a dark car 60 m away is seen")
			_place(-60.0, true, 120.0)
			# A wall halfway.
			wall = StaticBody3D.new()
			var c := _box()
			(c.shape as BoxShape3D).size = Vector3(20, 6, 1)
			wall.add_child(c)
			root.add_child(wall)
			wall.global_position = Vector3(0, 1, -30)
			step = 1
			t = 0
		1:
			_check(not heat.cop_can_see_player(cop), "seen through a wall")
			wall.queue_free()
			step = 2
			t = 0
		2:
			_check(heat.cop_can_see_player(cop), "not seen once the wall is gone")
			# Night one (no clock = night one): the warning on approach, the jab when spotted.
			_run(0.2)
			_check(heat.level == PoliceHeat.ONE_CAR, "seen at 120 km/h: level %d, expected 1 at once" % heat.level)
			_check(lines.size() == 2 and lines[0] == PoliceHeat.WARNING_LINE and lines[1] == PoliceHeat.MOCK_LINE,
				"night one lines: %s" % [lines])
			_check(icons.icon.visible and icons.icon.kind == "car", "HUD icon after level 1: %s %s" % [icons.icon.visible, icons.icon.kind])
			_run(12.0)
			_check(heat.level >= PoliceHeat.TWO_CARS, "12 s seen at 120 km/h: still level %d" % heat.level)
			_check(icons.icon.kind == PoliceHeat.icon_for(heat.level), "icon %s for level %d" % [icons.icon.kind, heat.level])
			var held := heat.heat
			_place(-60.0, true, 50.0)
			_run(5.0)
			_check(is_equal_approx(heat.heat, held), "seen under the limit changed heat %.2f -> %.2f" % [held, heat.heat])
			# Lights off: unseen (after the next look, CHECK_EVERY); holds for COOL_DELAY, then cools.
			_place(-60.0, false, 120.0)
			_run(PoliceHeat.COOL_DELAY - 1.0)
			_check(not heat.seen and absf(heat.heat - held) < 0.05, "lights off: seen %s, heat %.2f (was %.2f)" % [heat.seen, heat.heat, held])
			_run(60.0)
			_check(heat.heat < held - 2.0, "unseen 60 s past the delay: heat only %.2f from %.2f" % [heat.heat, held])
			_check(lines.size() == 2, "lines repeated: %d" % lines.size())
			# All the way down: no icon.
			_run(120.0)
			_check(heat.level == PoliceHeat.NONE and not icons.icon.visible, "cooled to level %d, icon %s" % [heat.level, icons.icon.visible])
			# A bad cop sees you and nothing happens.
			heat.unregister_cop(cop)
			heat.register_cop(cop, true)
			_place(-60.0, true, 150.0)
			_run(5.0)
			_check(heat.level == PoliceHeat.NONE and not heat.seen, "a bad cop raised heat to %d" % heat.level)
			# Night two: no warning, no jab.
			heat.unregister_cop(cop)
			heat.register_cop(cop)
			heat.reset()
			lines.clear()
			var clock := NightClock.new()
			clock.night = 2
			heat.night_clock = clock
			_run(1.0)
			_check(heat.level == PoliceHeat.ONE_CAR and lines.is_empty(), "night two: level %d, lines %s" % [heat.level, lines])
			clock.free()
			heat.night_clock = null
			step = 3
		3:
			for f in failures:
				printerr("FAIL: " + f)
			print("police_heat: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
			quit(0 if failures.is_empty() else 1)
	return false
