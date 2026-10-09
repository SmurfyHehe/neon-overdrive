extends SceneTree

# Gas station test (stops, first slice, 2026-10-09). Roy: "there is no way to
# fill gas now". End to end in the real game, first station moved next to the
# spawn (GasStation.first_s):
# - where the stations are: s_of / nearest / next_after;
# - the station's lot is cleared (own-side buildings there are empty lots);
# - a low tank shows "GAS x km" on the HUD fuel line, a full one does not;
# - a dry car put in the bay and stopped opens the pump menu (State.STATION);
# - with an empty bank the fill-up is refused, nothing is paid;
# - while a cop sees you (the chase flag) fill-up and tow are locked;
# - the tow (two presses) ends the night: tonight's cash goes into the bank
#   and the tank is back at the starting third;
# - the fill-up is paid from the bank at FuelTank.PRICE_PER_LITRE, fills the
#   tank, and moves the clock about 10 in-game minutes; the money is saved;
# - drive off: the game runs again and the menu does not open again while
#   the car is still in the bay.
#   <godot> --headless --path . -s res://tests/world/gas_station.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const GasStation := preload("res://scripts/world/gas_station.gd")
const PumpPanel := preload("res://scripts/ui/pump_panel.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")

const ROOT := "user://test_gas_station"
const FIRST := 120.0

var failures: Array[String] = []
var game: Node
var ticks := 0
var phase := 0
var wait := 0
var clock_before := 0.0

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.select_slot(1)
	SaveStore.chase_active = false
	GasStation.first_s = FIRST
	_static()
	game = Harness.boot(self, 0, 300.0, 5)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _static() -> void:
	_check(is_equal_approx(GasStation.s_of(0), FIRST), "first station at %.0f" % GasStation.s_of(0))
	_check(is_equal_approx(GasStation.s_of(2), FIRST + 2.0 * GasStation.SPACING), "third station misplaced")
	_check(is_equal_approx(GasStation.next_after(0.0), FIRST), "next station from the start is %.0f" % GasStation.next_after(0.0))
	_check(is_equal_approx(GasStation.next_after(FIRST + 2.0), FIRST), "a car in the bay should still be at this station")
	_check(is_equal_approx(GasStation.next_after(FIRST + 50.0), FIRST + GasStation.SPACING), "past the station, the next one is %.0f" % GasStation.next_after(FIRST + 50.0))
	_check(is_equal_approx(GasStation.nearest(FIRST + GasStation.SPACING * 0.4), FIRST), "nearest station wrong")

func _physics_process(_delta: float) -> bool:
	ticks += 1
	var player: Node3D = game.get("player")
	var gs: GameState = game.get("game_state")
	var w: Node = game.get("wallet")
	var clock: NightClock = game.get("night_clock")
	var panel := _find(game, "PumpPanel") as CanvasLayer
	if ticks > 4000:
		failures.append("timed out in phase %d" % phase)
		return _end()
	match phase:
		0:
			if ticks < 30:
				return false
			_check(panel != null and game.get("gas_station") != null, "no gas station or pump menu in the game")
			if panel == null:
				return _end()
			_check(_lot_cleared(), "no cleared lot at the station")
			_check(Hud.station_hint(player) == "", "full tank shows a station hint '%s'" % Hud.station_hint(player))
			player.fuel.litres = 3.0
			phase = 1
			wait = 0
			# Hands off, foot on the brake: the car sits where it is put.
			player.set("driver", func(c: Node) -> void:
				c.set("throttle_input", 0.0)
				c.set("brake_input", 1.0)
				c.set("steering_input", 0.0))
		1:
			wait += 1
			if wait < 10:
				return false
			var fuel_lbl := _find(game, "Fuel") as Label
			var hint := Hud.station_hint(player)
			_check(hint.contains("GAS"), "low tank shows no station hint ('%s')" % hint)
			_check(fuel_lbl != null and fuel_lbl.text.contains("GAS"), "HUD fuel reads '%s'" % (fuel_lbl.text if fuel_lbl != null else "<none>"))
			print("gas_station: low tank HUD reads '%s'" % (fuel_lbl.text if fuel_lbl != null else ""))
			# Dry, no bank, some cash, into the bay.
			player.fuel.litres = 0.0
			w.take_bank(w.bank)
			w.take_cash(w.cash)
			w.add_cash(300)
			var z := float(RoadFrame.origin_index) * RoadFrame.L - FIRST
			player.global_transform = RoadFrame.pose(GasStation.own_edge(FIRST) + 1.6, 0.6, z, 0.0)
			player.set("linear_velocity", Vector3.ZERO)
			player.set("angular_velocity", Vector3.ZERO)
			phase = 5
			wait = 0
		5:
			# held in the bay for a few ticks so the teleport sticks
			wait += 1
			var z2 := float(RoadFrame.origin_index) * RoadFrame.L - FIRST
			player.global_transform = RoadFrame.pose(GasStation.own_edge(FIRST) + 1.6, 0.6, z2, 0.0)
			player.set("linear_velocity", Vector3.ZERO)
			player.set("angular_velocity", Vector3.ZERO)
			if wait > 20:
				phase = 2
				wait = 0
		2:
			wait += 1
			if gs.state != GameState.State.STATION:
				if wait > 300:
					var p := GasStation.road_pos(player)
					failures.append("the pump menu did not open (car at x %.2f from the edge, s %.1f, %.2f m/s)" % [p.x - GasStation.own_edge(FIRST), p.y, (player.get("linear_velocity") as Vector3).length()])
					return _end()
				return false
			_check(panel.visible, "pump menu not shown")
			_check(get_tree_paused(), "game not paused at the pump")
			var fill_b := _find(panel, "FillUp") as Button
			var tow_b := _find(panel, "Tow") as Button
			_check(fill_b.disabled and fill_b.text.contains("can't cover"), "empty bank: fill button '%s' disabled=%s" % [fill_b.text, fill_b.disabled])
			var bank0: int = w.bank
			panel.call("fill")
			_check(w.bank == bank0 and player.fuel.litres == 0.0, "empty bank still filled or paid")
			# A cop sees you.
			SaveStore.begin_chase()
			panel.call("refresh")
			_check(fill_b.disabled and tow_b.disabled, "pump menu not locked during a chase")
			panel.call("tow")
			panel.call("tow")
			_check(w.cash == 300, "tow went through during a chase")
			SaveStore.end_chase()
			panel.call("refresh")
			_check(not tow_b.disabled, "tow still locked after the chase")
			# Ferris: first press only arms it.
			var night0 := clock.night
			panel.call("tow")
			_check(clock.night == night0 and w.cash == 300, "one press of tow already ended the night")
			panel.call("tow")
			_check(clock.night == night0 + 1, "tow did not end the night (night %d)" % clock.night)
			_check(w.cash == 0 and w.bank == 300, "tow banked wrong: cash %d bank %d" % [w.cash, w.bank])
			var third := FuelTank.CAPACITY_L * FuelTank.START_FRACTION
			_check(is_equal_approx(player.fuel.litres, third), "tow left %.1f L, expected %.1f" % [player.fuel.litres, third])
			# Fill up from the bank.
			var want := int(ceil(FuelTank.CAPACITY_L - player.fuel.litres - 0.001))
			clock_before = clock.minutes
			panel.call("fill")
			_check(w.bank == 300 - want * FuelTank.PRICE_PER_LITRE, "fill cost %d, expected %d" % [300 - w.bank, want * FuelTank.PRICE_PER_LITRE])
			_check(is_equal_approx(player.fuel.litres, FuelTank.CAPACITY_L), "tank at %.1f L after the fill" % player.fuel.litres)
			_check(int(SaveStore.load_wallet().bank) == w.bank, "the fill-up payment was not saved")
			phase = 3
			wait = 0
		3:
			wait += 1
			if wait < int((PumpPanel.FILL_SHOW_SECONDS + 0.5) * Engine.physics_ticks_per_second):
				return false
			var gone := clock.minutes - clock_before
			_check(absf(gone - PumpPanel.FILL_GAME_MINUTES) < 0.5, "the fill took %.1f in-game minutes" % gone)
			_check(not (_find(panel, "DriveOff") as Button).disabled, "drive off still disabled after the fill")
			print("gas_station: fill took %.1f in-game minutes, message '%s'" % [gone, (_find(panel, "Message") as Label).text])
			gs.close_station()
			_check(gs.state == GameState.State.PLAYING and not get_tree_paused(), "drive off did not resume the game")
			phase = 4
			wait = 0
		4:
			wait += 1
			if gs.state != GameState.State.PLAYING:
				failures.append("the pump menu opened again while the car sat in the bay")
				return _end()
			if wait > 90:
				return _end()
	return false

func get_tree_paused() -> bool:
	return paused

## Some own-side building near the first station was turned into a lot.
func _lot_cleared() -> bool:
	var chunk_i := int(FIRST / RoadFrame.L)
	for c in [chunk_i - 1, chunk_i, chunk_i + 1]:
		var root := _find(game, "Chunk_%d" % c)
		if root == null:
			continue
		for n in root.get_children():
			if String(n.name).begins_with("BuildingMesh") and n.get_meta("building_type", "") == "lot":
				return true
	return false

func _find(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var f := _find(c, name)
		if f != null:
			return f
	return null

func _end() -> bool:
	for m in failures:
		printerr("FAIL: ", m)
	print("gas_station: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
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
