extends SceneTree

# Ending a run, end to end, as the game itself is wired (game.gd), with the
# game as the current scene so the restart is the real one:
# - NEON_WRECK=1 turns the game's own wreck sensor on in a test;
# - the car drives into a wall at 80 km/h: the first wreck of the save, free;
# - the crash screen runs to the morning card, S is held, and the scene reloads;
# - the new run is a plain drive again: next night, playing, sound back, no
#   black screen, the money banked, the free wreck used up;
# - a second 80 km/h wall hit is a paid wreck: half of tonight's cash goes,
#   the scene reloads on the same night.
#   <godot> --headless --fixed-fps 120 --path . -s res://tests/core/run_end_restart.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const RunEnd := preload("res://scripts/core/run_end.gd")
const WreckRules := preload("res://scripts/car/wreck_rules.gd")

const ROOT := "user://test_run_end_restart"

enum Step { BOOT, FIRST, REBOOT, SECOND, REBOOT_2, DONE }

var failures: Array[String] = []
var step := Step.BOOT
var tick := 0
var t := 0
var game_id := 0
var night := 0
var started: Array = []

func _initialize() -> void:
	for name in ["NEON_CURVES", "NEON_HILLS", "NEON_TRAFFIC"]:
		OS.set_environment(name, "0")
	OS.set_environment("NEON_WRECK", "1")
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveStore.select_slot(1)
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
		d.remove(sub)

static func _coast(c: Vehicle) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.steering_input = 0.0
	c.handbrake_input = 0.0

## A wall 14 m ahead, and the car sent at it at 80 km/h. The wall belongs to
## the game, so the restart takes it away.
func _crash(game: Node, p: PlayerCar, cash: int) -> void:
	game.wallet.take_cash(game.wallet.cash)
	game.wallet.add_cash(cash)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 4.0, 1.0)
	col.shape = box
	body.add_child(col)
	CarSpec.make_wall(body)
	game.add_child(body)
	body.global_transform = Transform3D(p.global_transform.basis, p.global_position - p.global_transform.basis.z * 14.5)
	TrafficCar.set_moving(p, 80.0 / 3.6)
	p.reset_physics_interpolation()
	p.driver = _coast
	started.clear()
	game.run_end.wreck_started.connect(func(o: int, loss: int, free: bool) -> void: started.append([o, loss, free]))
	game_id = game.get_instance_id()
	night = game.night_clock.night
	t = 0

## The new scene, once it is up and has run a second.
func _fresh_game() -> Node:
	var game := current_scene
	if game == null or game.get_instance_id() == game_id or game.get("player") == null or game.get("run_end") == null:
		t = 0
		return null
	return game if t >= Engine.physics_ticks_per_second else null

func _check_fresh(game: Node, label: String) -> void:
	_check(game.game_state.state == GameState.State.PLAYING, label + ": the new run is playing")
	_check(game.run_end.phase == RunEnd.Phase.DRIVING and not game.run_end.screen.is_black(), label + ": no crash screen on the new run")
	_check(game.run_end.sensor.enabled, label + ": the new run can wreck again")
	for bus in [&"Engine", &"Tires", &"Music", &"World"]:
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(bus)), "%s: the %s sound is back" % [label, bus])
	_check(not paused and Engine.time_scale == 1.0, label + ": not paused, normal speed")

func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	var hz := Engine.physics_ticks_per_second
	if tick > hz * 240:
		return _end("timed out in %s" % Step.keys()[step])
	var game := current_scene
	match step:
		Step.BOOT:
			if game != null and game.get("player") != null and game.get("run_end") != null and t >= hz * 2:
				_check(game.run_end.sensor.enabled, "NEON_WRECK=1 turns the wreck sensor on in a test")
				_crash(game, game.player, 500)
				step = Step.FIRST
			elif game == null or game.get("player") == null:
				t = 0
		Step.FIRST:
			if game != null and game.get_instance_id() == game_id and game.run_end.phase == RunEnd.Phase.MORNING:
				Input.action_press(&"brake")  # hold S
			if game == null or game.get_instance_id() != game_id:
				Input.action_release(&"brake")
				print("first wreck: %s, then the scene reloaded after %.1f s" % [started, float(t) / hz])
				_check(started == [[WreckRules.Outcome.WRECK, 0, true]], "the first wreck is a free one")
				t = 0
				step = Step.REBOOT
		Step.REBOOT:
			game = _fresh_game()
			if game != null:
				print("new run: night %d (was %d), cash %d, bank %d" % [game.night_clock.night, night, game.wallet.cash, game.wallet.bank])
				_check_fresh(game, "after the first wreck")
				_check(game.night_clock.night == night + 1, "the first wreck moved on to the next night")
				_check(game.wallet.cash == 0 and game.wallet.bank == 500, "tonight's cash was banked whole")
				_check(SaveStore.first_wreck_used(), "the free wreck is used up")
				_crash(game, game.player, 500)
				step = Step.SECOND
		Step.SECOND:
			if game == null or game.get_instance_id() != game_id:
				print("second wreck: %s, then the scene reloaded after %.1f s" % [started, float(t) / hz])
				_check(started == [[WreckRules.Outcome.WRECK, 250, false]], "the second wreck costs half")
				t = 0
				step = Step.REBOOT_2
		Step.REBOOT_2:
			game = _fresh_game()
			if game != null:
				print("new run: night %d (was %d), cash %d, bank %d" % [game.night_clock.night, night, game.wallet.cash, game.wallet.bank])
				_check_fresh(game, "after the second wreck")
				_check(game.night_clock.night == night, "a plain wreck keeps the same night")
				_check(game.wallet.cash == 250 and game.wallet.bank == 500, "half of tonight's cash is left, the bank untouched")
				return _end("")
	return false

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	print("run_end_restart: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
