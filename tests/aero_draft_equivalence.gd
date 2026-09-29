extends SceneTree

# Before/after check for issue #24 (drafting lookup was O(n^2)).
#
# Compares AeroModel._draft_factor() (grid lookup) with a frozen copy of the
# old full-group scan in tests/fixtures/aero_draft_pre_24.gd. Every value must
# match EXACTLY -- the grid only changes which cars get looked at, not the
# maths, so there is no tolerance.
#
# 1. Player: loads the real Game.tscn and puts stand-in cars around the real
#    PlayerCar (dead ahead at 1-20 m, off to the side, behind, in other
#    lanes), checking the player's draft value old vs new at each spot.
# 2. Random layouts: 3000 layouts of 0-40 cars (clustered in lanes along the
#    road, plus fully scattered ones, random headings, some on cell edges),
#    every car checked old vs new.
# 3. Timing (reported, not asserted): 10/20/40/80 cars spread over 6 lanes,
#    one physics frame's worth of lookups, old vs new. Machine-dependent and
#    noisy; the point is old grows with cars squared, new roughly linearly.
#
# Run (a window opens briefly; headless also works for this test):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/aero_draft_equivalence.gd
# Exit code 0 = pass.

const Old := preload("res://tests/fixtures/aero_draft_pre_24.gd")
const LAYOUTS := 3000
const MAX_CARS := 40
const TIMING_FRAMES := 300

var fails := 0
var compared := 0
var nonzero := 0
var game: Node
var stubs: Array[Node3D] = []
var step := 0

func _initialize() -> void:
	seed(24)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _process(_delta: float) -> bool:
	step += 1
	if step < 5:  # let Game.tscn finish _ready and settle a few frames
		return false
	_check_player()
	_check_random_layouts()
	_report_timing()
	print("aero_draft_equivalence: %d comparisons (%d with draft > 0), %d failures" % [compared, nonzero, fails])
	print("PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
	return true

func _stub() -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.add_to_group("aero_vehicles")
	stubs.append(n)
	return n

func _clear_stubs() -> void:
	for n in stubs:
		n.remove_from_group("aero_vehicles")
		n.free()
	stubs.clear()

func _compare(v: Node3D, label: String) -> void:
	AeroModel.invalidate_draft_grid()
	var a: float = Old._draft_factor(v)
	var b: float = AeroModel._draft_factor(v)
	compared += 1
	if a > 0.0:
		nonzero += 1
	if a != b:
		fails += 1
		if fails <= 20:
			printerr("MISMATCH %s: old %.9f new %.9f at %s" % [label, a, b, v.global_position])

func _check_player() -> void:
	var p: Node3D = game.get("player")
	if p == null or not p.is_in_group("aero_vehicles"):
		printerr("player missing or not in aero_vehicles")
		fails += 1
		return
	var fwd := (-p.global_transform.basis.z).normalized()
	var right := p.global_transform.basis.x.normalized()
	# Alone: no draft, same as today.
	_compare(p, "player alone")
	var s := _stub()
	var before_nonzero := nonzero
	for i in 401:
		var ahead := -5.0 + i * 0.0625       # -5 m .. 20 m along the heading
		for side in [0.0, 1.0, 2.3, 4.6, 8.0]:  # dead ahead, offsets, one/two lanes over
			s.global_position = p.global_position + fwd * ahead + right * side
			_compare(p, "player, car at %.2f ahead %.1f side" % [ahead, side])
	if nonzero == before_nonzero:
		printerr("player check never produced a draft -- test is vacuous")
		fails += 1
	# A pack: several cars ahead in the lane at once, best one wins.
	for k in 4:
		var n := _stub()
		n.global_position = p.global_position + fwd * (4.0 + k * 3.5) + right * randf_range(-0.8, 0.8)
	_compare(p, "player in pack")
	_clear_stubs()

func _place_random(n: Node3D, scattered: bool) -> void:
	if scattered:
		n.global_position = Vector3(randf_range(-60, 60), randf_range(-1, 3), randf_range(-60, 60))
	else:
		# Lanes along the road (forward = -Z), cars bunched so drafting happens.
		var lane := randi_range(-3, 2)
		n.global_position = Vector3(lane * 2.3 + randf_range(-0.6, 0.6), randf_range(0.4, 0.8), randf_range(-120, 0))
	if randf() < 0.1:
		# Snap to a cell boundary to exercise the edges of the grid.
		n.global_position.x = roundf(n.global_position.x / 30.0) * 30.0 + randf_range(-15.01, 15.01) * float(randi() % 2)
		n.global_position.z = roundf(n.global_position.z / 30.0) * 30.0 + randf_range(-0.01, 0.01)
	var yaw := randf_range(-0.3, 0.3) if randf() < 0.8 else randf_range(-PI, PI)
	n.global_rotation = Vector3(0, yaw, 0)

func _check_random_layouts() -> void:
	seed(24)  # Game.tscn consumes randomness while loading; reseed so layouts repeat
	var p: Node3D = game.get("player")
	p.remove_from_group("aero_vehicles")  # stubs only; the player is covered above
	for layout in LAYOUTS:
		var count := randi_range(0, MAX_CARS)
		var scattered := layout % 4 == 3
		while stubs.size() < count:
			_stub()
		while stubs.size() > count:
			var n: Node3D = stubs.pop_back()
			n.remove_from_group("aero_vehicles")
			n.free()
		for n in stubs:
			_place_random(n, scattered)
		for n in stubs:
			_compare(n, "layout %d (%d cars)" % [layout, count])
	p.add_to_group("aero_vehicles")
	_clear_stubs()

func _report_timing() -> void:
	var p: Node3D = game.get("player")
	p.remove_from_group("aero_vehicles")
	for count in [10, 20, 40, 80]:
		for i in count:
			var n := _stub()
			n.global_position = Vector3((i % 6 - 3) * 2.3, 0.6, -float(i) * 15.0 + randf_range(-4, 4))
		var t0 := Time.get_ticks_usec()
		for f in TIMING_FRAMES:
			for n in stubs:
				Old._draft_factor(n)
		var t_old := float(Time.get_ticks_usec() - t0) / TIMING_FRAMES
		t0 = Time.get_ticks_usec()
		for f in TIMING_FRAMES:
			AeroModel.invalidate_draft_grid()  # one rebuild per simulated frame, like the game
			for n in stubs:
				AeroModel._draft_factor(n)
		var t_new := float(Time.get_ticks_usec() - t0) / TIMING_FRAMES
		print("timing, %d cars, per physics frame: old %.0f us, new %.0f us (%.1fx)" % [count, t_old, t_new, t_old / maxf(t_new, 0.001)])
		_clear_stubs()
	p.add_to_group("aero_vehicles")
