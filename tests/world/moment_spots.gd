extends SceneTree

# Moment spots test (M0 + power cut + speed trap, 2026-10-10), headless:
# - the deck, pure: spots are fixed for a road seed and stand clear of the
#   district blend and of each other; every cycle of spots gets each card
#   once; the deal is the same for a seed and night, and changes with the
#   night and with the seed
# - the rules, with a stand-in car on a straight road: the power cut starts
#   once, as the car comes within CUT_AT of the block; the trap clocks a lit
#   car over the limit, lets a slow one go, lets a dark car go in the far
#   lanes and clocks it in the lane beside the cop
# - the cost of one look
# - the real game (NEON_MOMENTS=1, a road seed picked so run 0 holds a power
#   cut and then a trap): the car is held at 100 km/h; the block goes dark
#   (lamp heads, pools, signs, windows) and its neighbour does not; a new
#   night lights it again; the patrol car stands on the sidewalk and clocks
#   the car; at the end every live chunk's dark state matches tonight's deal.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/world/moment_spots.gd

const TIMEOUT_TICKS := 3600
const SPEED := 100.0 / 3.6

class FakeCar extends Node3D:
	var speed := 0.0
	var headlights_on := true
	func current_speed() -> float:
		return speed

enum Step { BOOT, TO_CUT, DARK, RELIT, TO_TRAP, DONE, EXIT }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var moments: MomentSpots
var seed_used := 0
var cut_chunk := 0
var trap_chunk := 0
var cuts: Array[int] = []
var clocks: Array[float] = []
var clock_cop: Node3D
var lines: Array[String] = []

func _initialize() -> void:
	_deck_tests()
	_rule_tests()
	_cost()
	# A road whose first run holds a power cut, then a trap, on night 1.
	for sd in range(1, 5000):
		if MomentSpots.moment_at(sd, 1, 0, 0) == "power_cut" and MomentSpots.moment_at(sd, 1, 0, 1) == "speed_trap":
			seed_used = sd
			break
	_check(seed_used > 0, "a seed with a power cut and a trap in run 0")
	cut_chunk = MomentSpots.spot_chunk(seed_used, 0, 0)
	trap_chunk = MomentSpots.spot_chunk(seed_used, 0, 1)
	OS.set_environment("NEON_MOMENTS", "1")
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_ROAD_SEED", str(seed_used))
	NightClock.path = "user://test_moment_spots_clock.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	change_scene_to_file("res://Game.tscn")

# ---------- the deck ----------

func _deck_tests() -> void:
	var cards := MomentSpots.deck_cards()
	for sd in [1, 77, 123456]:
		for run in range(0, 40):
			var last := -100
			for i in range(MomentSpots.SPOTS_PER_RUN):
				var c := MomentSpots.spot_chunk(sd, run, i)
				var off := c - run * 16
				_check(off >= 1 and off + MomentSpots.BLOCK_CHUNKS - 1 < 16 - 2, "spot clear of the blend (run %d, offset %d)" % [run, off])
				_check(c - last >= 2, "spots are not neighbours")
				_check(c == MomentSpots.spot_chunk(sd, run, i), "spot is fixed")
				last = c
		# Every cycle of spots holds the whole deck.
		for night in [1, 2, 9]:
			var counts := {}
			for g in range(cards.size() * 6):
				var card := MomentSpots.card_at(sd, night, floori(float(g) / MomentSpots.SPOTS_PER_RUN), g % MomentSpots.SPOTS_PER_RUN)
				counts[card] = int(counts.get(card, 0)) + 1
				_check(card == MomentSpots.card_at(sd, night, floori(float(g) / MomentSpots.SPOTS_PER_RUN), g % MomentSpots.SPOTS_PER_RUN), "the deal is repeatable")
			for card in MomentSpots.DECK:
				_check(counts.get(card, 0) == int(MomentSpots.DECK[card]) * 6, "%s dealt %d times in 6 cycles, seed %d night %d" % [card, counts.get(card, 0), sd, night])
	_check(_deal(1, 1) != _deal(1, 2), "the deal changes with the night")
	_check(_deal(1, 1) != _deal(2, 1), "the deal changes with the road seed")
	_check(_deal(5, 3) == _deal(5, 3), "same seed and night, same deal")
	# Negative runs (behind the start) deal too.
	_check(MomentSpots.DECK.has(MomentSpots.card_at(1, 1, -3, 1)), "a run behind the start has a card")

func _deal(sd: int, night: int) -> Array:
	var out := []
	for run in range(0, 24):
		for i in range(MomentSpots.SPOTS_PER_RUN):
			out.append(MomentSpots.card_at(sd, night, run, i))
	return out

# ---------- the rules ----------

## A MomentSpots outside the game, on the default straight road, with the
## first spot of run 0 holding `card`.
func _stand_in(card: String, car: FakeCar) -> MomentSpots:
	var m := MomentSpots.new()
	for sd in range(1, 5000):
		if MomentSpots.moment_at(sd, 1, 0, 0) == card and MomentSpots.moment_at(sd, 1, 0, 1) == "quiet":
			m.road_seed = sd
			break
	m.player = car
	return m

## Drives the stand-in car from 300 m before the start of the road to `to_s`
## m at `kmh`, in lane x, looking every 0.1 s.
func _drive(m: MomentSpots, car: FakeCar, kmh: float, x: float, to_s: float) -> void:
	car.speed = kmh / 3.6
	var s := -300.0
	while s < to_s:
		car.position = Vector3(x, 0.0, -s)
		m.look(car.position)
		s += car.speed * MomentSpots.CHECK_EVERY

func _rule_tests() -> void:
	RoadFrame.origin_index = 0
	RoadFrame.align = null
	var car := FakeCar.new()

	# power cut
	var m := _stand_in("power_cut", car)
	var block_s := float(MomentSpots.spot_chunk(m.road_seed, 0, 0)) * 50.0
	var started: Array[float] = []
	var said: Array[String] = []
	m.power_cut_started.connect(func(_c: int) -> void: started.append(-car.position.z))
	m.announce = func(t: String) -> bool:
		said.append(t)
		return true
	_drive(m, car, 100.0, 5.0, block_s + 300.0)
	_check(started.size() == 1, "the power cut starts once (%d)" % started.size())
	if started.size() == 1:
		var ahead := block_s - started[0]
		_check(ahead <= MomentSpots.CUT_AT and ahead > MomentSpots.CUT_AT - 6.0, "it starts %d m before the block" % int(ahead))
	_check(said == [MomentSpots.CUT_LINE], "Dave says it once")
	m.free()

	# speed trap: [kmh, lane x, headlights, clocked?]
	var near_lane := MomentSpots.trap_x() - 4.4
	for c in [[100.0, 2.0, true, true], [60.0, 2.0, true, false], [100.0, 2.0, false, false],
			[100.0, 5.2, false, false], [100.0, near_lane, false, true], [69.0, near_lane, false, false]]:
		m = _stand_in("speed_trap", car)
		var cop_s := float(MomentSpots.spot_chunk(m.road_seed, 0, 0)) * 50.0 + MomentSpots.TRAP_Z
		var got: Array = []
		var slips: Array = []
		m.clocked.connect(func(kmh: float, _cop: Node3D) -> void: got.append([kmh, cop_s + car.position.z]))
		m.slipped.connect(func(dark: bool) -> void: slips.append(dark))
		car.headlights_on = c[2]
		_drive(m, car, c[0], c[1], cop_s + 200.0)
		var what := "%d km/h, x %.1f, lights %s" % [int(c[0]), c[1], "on" if c[2] else "off"]
		if c[3]:
			_check(got.size() == 1 and slips.is_empty(), "clocked once: " + what)
			if got.size() == 1:
				_check(absf(got[0][0] - c[0]) < 0.5, "the reading is the car's speed: " + what)
				var reach: float = MomentSpots.SEE_LIT if c[2] else MomentSpots.SEE_DARK
				_check(got[0][1] <= reach and got[0][1] > -MomentSpots.PAST, "clocked within reach (%d m ahead): %s" % [int(got[0][1]), what])
		else:
			_check(got.is_empty(), "not clocked: " + what)
			_check(slips == [not c[2]], "slipped past once, dark %s: %s" % [not c[2], what])
		m.free()
	car.free()

func _cost() -> void:
	var car := FakeCar.new()
	var m := _stand_in("speed_trap", car)
	car.speed = 10.0
	var t0 := Time.get_ticks_usec()
	for n in range(2000):
		car.position.z = -float(n)
		m.look(car.position)
	var us := float(Time.get_ticks_usec() - t0) / 2000.0
	print("moment_spots: one look = %.1f us (ten a second in the game)" % us)
	_check(us < 200.0, "one look is cheap (%.1f us)" % us)
	m.free()
	car.free()

# ---------- the game ----------

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick > TIMEOUT_TICKS and step != Step.EXIT:
		_check(false, "timed out in step %s" % Step.keys()[step])
		_finish()
		return false
	match step:
		Step.BOOT:
			game = current_scene
			if game == null or game.get("player") == null:
				return false
			moments = game.moments
			_check(moments != null, "NEON_MOMENTS=1 builds the moment spots")
			if moments == null:
				_finish()
				return false
			_check(moments.road_seed == seed_used and moments.tonight == 1, "seed %d, night %d" % [moments.road_seed, moments.tonight])
			moments.power_cut_started.connect(func(c: int) -> void: cuts.append(c))
			moments.clocked.connect(func(kmh: float, cop: Node3D) -> void:
				clocks.append(kmh)
				clock_cop = cop)
			moments.announce = func(t: String) -> bool:
				lines.append(t)
				return true
			_check(not _is_dark(_root(cut_chunk)), "the block is lit before the car arrives")
			_go(Step.TO_CUT)
		Step.TO_CUT:
			_hold_speed()
			if not cuts.is_empty() and tick - step_start > 0 and moments._flicker_spot.is_empty():
				_check(cuts == [cut_chunk], "the cut is the dealt block")
				_go(Step.DARK)
		Step.DARK:
			for c in range(cut_chunk, cut_chunk + MomentSpots.BLOCK_CHUNKS):
				var root := _root(c)
				_check(root != null, "block chunk %d is live" % c)
				if root != null:
					_check(_is_dark(root), "chunk %d is dark: lamps, pools, signs, windows" % c)
			var side := _root(cut_chunk + MomentSpots.BLOCK_CHUNKS)
			_check(side != null and not _is_dark(side) and (side.get_node(^"LampPools") as Node3D).visible, "the next chunk is still lit")
			_check(lines.has(MomentSpots.CUT_LINE), "Dave's line went out")
			# 6 a.m.: the next night's deal has no cut here (or has not fired it).
			game.night_clock.set_time(null, 2)
			moments.new_night()
			_go(Step.RELIT)
		Step.RELIT:
			var root := _root(cut_chunk)
			if root != null:
				_check(not _is_dark(root), "a new night lights the block again")
				_check(_lit_windows(root) > 0, "its windows are back")
			game.night_clock.set_time(null, 1)
			moments.new_night()
			_go(Step.TO_TRAP)
		Step.TO_TRAP:
			_hold_speed()
			var root := _root(trap_chunk)
			if root != null and clocks.is_empty() and root.get_node_or_null(^"TrapCop") != null and not has_meta("cop_checked"):
				set_meta("cop_checked", true)
				var cop := root.get_node(^"TrapCop") as Node3D
				var at := RoadFrame.unroll(cop.global_position)
				_check(absf(at.x - MomentSpots.trap_x()) < 0.05, "the patrol car is on the sidewalk (x %.2f)" % at.x)
				_check(absf(RoadFrame.s_at(at.z) - (trap_chunk * 50.0 + MomentSpots.TRAP_Z)) < 0.05, "at its spot along the road")
				_check(cop is StaticBody3D and cop.get_node_or_null(^"NpcBody") != null and cop.get_child_count() == 6, "body, four wheels and a box")
				_check(cop.get_script() == null, "the patrol car has no script")
			if not clocks.is_empty():
				_check(has_meta("cop_checked"), "the patrol car was there before it clocked")
				_check(clocks[0] > MomentSpots.SPEED_LIMIT_KMH, "clocked at %d km/h" % int(clocks[0]))
				_check(clock_cop != null and clock_cop.get_parent() == _root(trap_chunk), "the clocking cop is the one at the spot")
				_check(lines.has(MomentSpots.CLOCKED_LINE), "Dave's trap line went out")
				_go(Step.DONE)
		Step.DONE:
			_hold_speed()
			if tick - step_start < 240:
				return false
			_check(clocks.size() == 1, "the trap clocks once (%d)" % clocks.size())
			_check(MomentSpots.FLICKER.size() % 2 == 1, "the flicker ends dark")
			var cops := 0
			for c in game.chunk_pool:
				var s := moments.spot_at(c.index)
				var want: bool = s.get("card", "") == "power_cut" and s.fired
				_check(_is_dark(c.root) == want, "chunk %d dark state matches the deal" % c.index)
				var has_cop: bool = c.root.get_node_or_null(^"TrapCop") != null
				_check(has_cop == (s.get("card", "") == "speed_trap"), "chunk %d patrol car matches the deal" % c.index)
				cops += 1 if has_cop else 0
			_check(cops <= 2, "at most two patrol cars live")
			_finish()
	return false

func _go(s: Step) -> void:
	step = s
	step_start = tick

## Keeps the car at 100 km/h down its lane without driving it.
func _hold_speed() -> void:
	var p: RigidBody3D = game.player
	p.linear_velocity = Vector3(0.0, p.linear_velocity.y, -SPEED)
	p.angular_velocity = Vector3.ZERO

func _root(chunk: int) -> Node3D:
	for c in game.chunk_pool:
		if c.index == chunk:
			return c.root
	return null

func _lit_windows(root: Node3D) -> int:
	var n := 0
	for child in root.get_children():
		if child is MeshInstance3D and child.name.begins_with("BuildingMesh") and child.visible:
			if float((child as MeshInstance3D).get_instance_shader_parameter("lit_density")) > 0.0:
				n += 1
	return n

## Dark as a whole: the dark lamp mesh, no pools, no signs, no lit window.
## Half dark fails the test.
func _is_dark(root: Node3D) -> bool:
	if root == null:
		return false
	var lamps_dark: bool = (root.get_node(^"Lamps") as MultiMeshInstance3D).multimesh.mesh == RoadChunkBuilder.lamp_mesh(true)
	var pools_off: bool = not (root.get_node(^"LampPools") as Node3D).visible
	var signs := root.get_node_or_null(^"Signs") as Node3D
	var signs_off: bool = signs == null or not signs.visible
	var windows_off := _lit_windows(root) == 0
	if lamps_dark != pools_off or (lamps_dark and not (signs_off and windows_off)):
		_check(false, "%s is half dark (lamps %s, pools off %s, signs off %s, windows off %s)" % [root.name, lamps_dark, pools_off, signs_off, windows_off])
	return lamps_dark

func _finish() -> void:
	step = Step.EXIT
	for f in failures:
		printerr("FAIL: " + f)
	print("moment_spots: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
