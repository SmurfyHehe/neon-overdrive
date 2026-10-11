extends SceneTree

# Gas stations on both sides of Loop 1 (2026-10-11). In the real game on the
# loop, the car is put into each bay in turn and held still:
# - the own-side station at 2,225 m opens the pump menu;
# - the oncoming-side station at 1,825 m opens it too, and a car in the same
#   spot mirrored on the other side (the wrong side of the road) does not;
# - the lots are cleared on their own sides (a building of that side near the
#   station is an empty lot).
#   <godot> --headless --path . -s res://tests/world/gas_station_sides.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const GasStation := preload("res://scripts/world/gas_station.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const ROOT := "user://test_gas_station_sides"
const OWN_S := 2225.0
const ONC_S := 1825.0

var failures: Array[String] = []
var game: Node
var ticks := 0
var phase := 0
var wait := 0

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.select_slot(1)
	SaveStore.chase_active = false
	game = Harness.boot(self, 0, 300.0, 5)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

## Puts the car in road space at (x, s), still, facing yaw, every tick.
func _hold(player: Node3D, x: float, s: float, yaw: float) -> void:
	var z := float(RoadFrame.origin_index) * RoadFrame.L - s
	player.global_transform = RoadFrame.pose(x, 0.6, z, yaw)
	player.set("linear_velocity", Vector3.ZERO)
	player.set("angular_velocity", Vector3.ZERO)

func _physics_process(_delta: float) -> bool:
	ticks += 1
	var player: Node3D = game.get("player")
	var gs: GameState = game.get("game_state")
	if ticks > 3000:
		failures.append("timed out in phase %d" % phase)
		return _end()
	if ticks < 30:
		return false
	match phase:
		0:
			_check(game.get("gas_station_onc") != null, "no oncoming-side station node")
			_check(GasStation.RoadMap.period > 0, "the game is not on a loop")
			_check(is_equal_approx(GasStation.nearest(OWN_S, 1), OWN_S) and is_equal_approx(GasStation.nearest(ONC_S, -1), ONC_S), "the loop's stations are not at 2225 / 1825")
			phase = 1
			wait = 0
		1, 3, 5:
			# 1: own side bay (opens); 3: oncoming bay (opens); 5: the own-side
			# spot mirrored onto the oncoming side at 2225 (must not open)
			var s := OWN_S if phase == 1 else (ONC_S if phase == 3 else OWN_S)
			var x := GasStation.own_edge(s, 1) + 1.6
			if phase == 3:
				x = -(GasStation.own_edge(s, -1) + 1.6)
			elif phase == 5:
				x = -(GasStation.own_edge(s, -1) + 1.6)
			_hold(player, x, s, 0.0 if phase != 3 else PI)
			wait += 1
			if phase == 5:
				if gs.state == GameState.State.STATION:
					failures.append("the pump menu opened with the car on the oncoming side at %.0f, where there is no station" % s)
					return _end()
				if wait > 90:
					return _end()
			elif gs.state == GameState.State.STATION:
				# the road round the car is built by now: its lot is cleared on its own side
				_check(_lot_cleared(s, 1 if phase == 1 else -1), "no cleared lot on side %d at %.0f" % [1 if phase == 1 else -1, s])
				gs.close_station()
				phase += 1
				wait = 0
				# drive off: out of both bays so the next one arms
				_hold(player, GasStation.own_edge(s, 1) + 8.0, s + 120.0, 0.0)
			elif wait > 300:
				failures.append("the pump menu did not open in phase %d (car at %s)" % [phase, str(GasStation.road_pos(player))])
				return _end()
		2, 4:
			wait += 1
			_hold(player, GasStation.own_edge(1000.0, 1) + 3.0, 1000.0, 0.0)
			if wait > 40:
				phase += 1
				wait = 0
	return false

## Some building on `side` near `s` was turned into a lot.
func _lot_cleared(s: float, side: int) -> bool:
	var chunk_i := int(s / RoadFrame.L)
	for c in game.get("chunk_pool"):
		if absi(int(c.index) - chunk_i) > 1:
			continue
		for n in c.root.get_children():
			if String(n.name).begins_with("BuildingMesh") and n.get_meta("building_type", "") == "lot":
				var i := int(String(n.name).trim_prefix("BuildingMesh"))
				var body := c.root.get_node_or_null(NodePath("BuildingBody%d" % i)) as Node3D
				if body != null and (body.position.x > 0.0) == (side == 1):
					return true
	return false

func _end() -> bool:
	for m in failures:
		printerr("FAIL: ", m)
	print("gas_station_sides: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	DirAccess.remove_absolute(path)
