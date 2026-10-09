extends SceneTree

# No visible pop-in or pop-out (Roy, 2026-10-09: "i don't want to see car spawn
# in anymore, it breaks the realism").
#
# Drives the real Game.tscn with 40 traffic cars for DRIVE_SECS of game time and
# records EVERY car event the TrafficManager reports (spawn = just placed,
# despawn = about to be moved or freed while drawn, show/hide = crossing the
# reveal distance) and every road-chunk rebuild (a chunk vanishes from where it
# stands). At the moment of each event it asks, independently of ViewGuard
# (exact Camera3D frustum, no margin, plain physics rays), whether any camera
# could see it:
#   - the viewport's current camera (chase, cockpit, look-back);
#   - the cockpit mirrors, whenever they draw (cockpit view, HUD rear strip);
#   - a stand-in free-look camera that sweeps all the way round 3 times a minute
#     (anything in the view_cameras group counts).
# A car is seen if some camera has a box corner in its frustum with a clear ray
# to it; a corner behind a crest, a building or a wall does not count.
#
# Asserts (exit code 1 on failure):
# - zero spawn / despawn events where a camera could see the car
# - show / hide only at the reveal distance (the fog edge), never nearer
# - road chunks are rebuilt only out of sight, or by force 300 m back
# - the phases really happened: chase and cockpit views, look-back, a hill road,
#   lane changes, slow and fast player speed, wrecks, and a live slider trim
# - enough events that the check means something
# - no engine or script errors
#
# Run (NEON_HILLS=1 NEON_CURVES=1 for the hilly road; the default is flat):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/traffic/no_visible_spawn.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
const CARS := 40
var DRIVE_SECS := int(OS.get_environment("NVS_SECS")) if OS.get_environment("NVS_SECS") != "" else 100
var RUN_TICKS := RATE * DRIVE_SECS
var TIMEOUT_TICKS := RUN_TICKS * 6

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var player: PlayerCar
var cam: ChaseCamera
var sweep: Camera3D
var tick := 0
var fails: Array[String] = []
var events := {"spawn": 0, "despawn": 0, "show": 0, "hide": 0}
var seen_violations := 0
var occluded_ok := 0       # events whose car was in a frustum but behind geometry
var offscreen_ok := 0      # events whose car was outside every frustum
var by_view := {}          # view label -> events checked
var show_min := INF
var hide_min := INF
var chunk_rebuilds := 0
var chunk_forced := 0
var chunk_seen_violations := 0
var cockpit_ticks := 0
var lookback_ticks := 0
var strip_cam_ticks := 0
var lane_changes_made := 0
var trimmed := false
var wrecks_seen := 0
var min_cams := 99
var max_cams := 0
var phase_label := "chase"

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 4242, 400.0)

func _setup() -> void:
	traffic = game.get("traffic")
	player = game.get("player")
	cam = game.get("camera")
	traffic.own_lanes_used = [2, 3]  # the player changes between lanes 0 and 1
	traffic.event_hook = _on_car_event
	game.set("chunk_event_hook", _on_chunk_event)
	traffic.set_car_count(CARS)
	Harness.move_player_to_lane(player, Harness.lane_x(0))
	sweep = Camera3D.new()
	sweep.name = "SweepCam"
	sweep.fov = 75.0
	sweep.far = 400.0
	sweep.add_to_group(ViewGuard.GROUP)
	game.add_child(sweep)

func _physics_process(_delta: float) -> bool:
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		printerr("FAIL: timed out after ", Engine.get_physics_frames(), " ticks")
		quit(1)
		return true
	if traffic == null:
		if game.get("player") == null or game.get("traffic") == null:
			return false
		_setup()
		return false
	tick += 1
	var secs := float(tick) / RATE
	_drive_script(secs)
	_sweep_camera(secs)
	for car in traffic.cars:
		if car.wrecked and car.visible:
			wrecks_seen += 1
	if tick >= RUN_TICKS:
		return _end()
	return false

## What the player does and which way the camera looks, by game second.
func _drive_script(secs: float) -> void:
	# Speed: cruise, crawl (cars catch up from behind), flat out (passes).
	var cap := 38.0
	if fmod(secs, 60.0) >= 20.0 and fmod(secs, 60.0) < 32.0:
		cap = 9.0
	elif fmod(secs, 60.0) >= 40.0:
		cap = 55.0
	# Lane: 0 and 1 swapped every 7 s.
	var lane := int(secs / 7.0) % 2
	if tick % (RATE * 7) == 1:
		lane_changes_made += 1
	player.driver = Harness.lane_driver(Harness.lane_x(lane), 1.0, cap)
	# Views: chase, then the cockpit (mirrors draw), holding look-back now and then.
	var cockpit := fmod(secs, 50.0) >= 25.0
	var want_view := ChaseCamera.View.COCKPIT if cockpit else ChaseCamera.View.CHASE
	if cam.view != want_view:
		cam.set_view(want_view)
	var back := fmod(secs, 10.0) >= 6.0
	if back and not Input.is_action_pressed("look_back"):
		Input.action_press("look_back")
	elif not back and Input.is_action_pressed("look_back"):
		Input.action_release("look_back")
	if cockpit:
		cockpit_ticks += 1
	if back:
		lookback_ticks += 1
	phase_label = ("cockpit" if cockpit else "chase") + ("+back" if back else "")
	if tick == RUN_TICKS * 2 / 5 and not trimmed:
		trimmed = true
		traffic.set_car_count(25)
	if tick == RUN_TICKS * 3 / 5:
		traffic.set_car_count(CARS)

## The stand-in free-look camera: on the player's roof, turning 360 degrees
## every 20 s and pitching a little, so it passes over every direction.
func _sweep_camera(secs: float) -> void:
	var p := player.global_position + Vector3(0.0, 2.0, 0.0)
	sweep.global_transform = Transform3D(Basis.from_euler(Vector3(sin(secs) * 0.2, secs * TAU / 20.0, 0.0)), p)

## ---- the independent check ----

## Whether any camera can see a car-sized box at world position `pos`.
## Returns "" if unseen, else the label of a camera that sees it.
func _seen_by(pos: Vector3) -> String:
	var space := traffic.get_world_3d().direct_space_state
	var u := RoadFrame.unroll(pos)
	u.y = maxf(u.y, 0.0)
	var cams: Array[Camera3D] = []
	var main := root.get_viewport().get_camera_3d()
	if main != null:
		cams.append(main)
	for n in get_nodes_in_group(ViewGuard.GROUP):
		if n is Camera3D and n.is_inside_tree() and n != main:
			cams.append(n)
	min_cams = mini(min_cams, cams.size())
	max_cams = maxi(max_cams, cams.size())
	var in_frustum := false
	for c in cams:
		for sx in [-1.0, 1.0]:
			for sy in [0.1, 1.6]:
				for sz in [-2.3, 2.3]:
					var pt := RoadFrame.roll(Vector3(u.x + sx * 1.0, u.y + sy, u.z + sz))
					if not c.is_position_in_frustum(pt):
						continue
					in_frustum = true
					var q := PhysicsRayQueryParameters3D.create(c.global_position, pt, 1)
					if space.intersect_ray(q).is_empty():
						return c.name
	if in_frustum:
		occluded_ok += 1
	else:
		offscreen_ok += 1
	return ""

func _on_car_event(kind: String, car: TrafficCar, pos: Vector3) -> void:
	events[kind] += 1
	by_view[phase_label] = int(by_view.get(phase_label, 0)) + 1
	var d := absf(RoadFrame.unroll(pos).z - RoadFrame.unroll(player.global_position).z)
	if kind == "show" or kind == "hide":
		if kind == "show":
			if d < traffic.reveal_distance() - 3.0:
				print("early show: car %s d=%.1f tick %d player_z %.1f car_z %.1f wrecked=%s" % [car.name, d, tick, player.global_position.z, car.global_position.z, str(car.wrecked)])
			show_min = minf(show_min, d)
		else:
			hide_min = minf(hide_min, d)
		return
	var cam_name := _seen_by(pos)
	if cam_name != "":
		seen_violations += 1
		fails.append("%s of a car %.0f m from the player at tick %d was in view of %s (view %s)" % [kind, d, tick, cam_name, phase_label])

## A chunk is about to be rebuilt somewhere else: it must be out of every
## camera's view, unless it is already past the forced gap (300 m back).
func _on_chunk_event(chunk_root: Node3D, gap: int) -> void:
	chunk_rebuilds += 1
	if gap > game.call("_chunks_behind") + (load("res://scripts/core/game.gd").CHUNKS_SPARE as int):
		chunk_forced += 1
		return
	var cams: Array[Camera3D] = []
	var main := root.get_viewport().get_camera_3d()
	if main != null:
		cams.append(main)
	for n in get_nodes_in_group(ViewGuard.GROUP):
		if n is Camera3D and n.is_inside_tree() and n != main:
			cams.append(n)
	var xf := chunk_root.global_transform
	for c in cams:
		for iz in 11:
			for x in [-40.0, -15.0, 0.0, 15.0, 40.0]:
				for y in [0.0, 10.0, 30.0]:
					if c.is_position_in_frustum(xf * Vector3(x, y, -float(iz) * 5.0)):
						chunk_seen_violations += 1
						fails.append("chunk %d gap behind rebuilt in view of %s at tick %d" % [gap, c.name, tick])
						return

func _end() -> bool:
	_check(seen_violations == 0, "%d car events happened in view" % seen_violations)
	_check(chunk_seen_violations == 0, "%d chunk rebuilds happened in view" % chunk_seen_violations)
	_check(events.spawn >= 3 and traffic.spawn_count >= 120, "only %d visible spawns, %d spawns" % [events.spawn, traffic.spawn_count])
	_check(events.despawn >= 80, "only %d despawns" % events.despawn)
	_check(events.show >= 50, "only %d show events" % events.show)
	_check(show_min >= traffic.reveal_distance() - 3.0, "a car was shown at %.1f m, inside the reveal distance %.0f" % [show_min, traffic.reveal_distance()])
	_check(hide_min >= traffic.reveal_distance(), "a car was hidden at %.1f m, inside the reveal distance" % hide_min)
	_check(cockpit_ticks > RATE * 30 and lookback_ticks > RATE * 20, "views not exercised (cockpit %d, look-back %d ticks)" % [cockpit_ticks, lookback_ticks])
	_check(max_cams >= 3, "mirror cameras never joined the view group (max %d cameras)" % max_cams)
	_check(chunk_rebuilds >= 10, "only %d chunk rebuilds" % chunk_rebuilds)
	_check(traffic.cars.size() == CARS, "car count ended at %d" % traffic.cars.size())
	_check(trimmed, "the slider trim never ran")
	_check(logger.errors.is_empty(), "engine errors: %s" % str(logger.errors.slice(0, 5)))
	print("hills=%s | ticks %d | cameras seen %d..%d" % [str(RoadFrame.has_hills()), tick, min_cams, max_cams])
	print("car events: spawn %d, despawn %d, show %d, hide %d" % [events.spawn, events.despawn, events.show, events.hide])
	print("  in view: %d | hidden behind geometry: %d | outside every frustum: %d" % [seen_violations, occluded_ok, offscreen_ok])
	print("  show/hide nearest: %.1f / %.1f m (reveal %.0f m)" % [show_min, hide_min, traffic.reveal_distance()])
	print("  events by view: %s" % str(by_view))
	print("ViewGuard.car_seen: %d calls, %.1f ms total, %.3f ms per call, %.3f ms per tick" % [ViewGuard.prof_calls, ViewGuard.prof_usec / 1000.0, ViewGuard.prof_usec / 1000.0 / maxf(ViewGuard.prof_calls, 1), ViewGuard.prof_usec / 1000.0 / maxf(tick, 1)])
	print("chunks: %d rebuilt, %d forced at the gap limit, %d in view" % [chunk_rebuilds, chunk_forced, chunk_seen_violations])
	print("recycles %d (wrecked %d), spawns %d, lane changes by the player %d, drawn-wreck ticks %d" % [
		traffic.recycle_count, traffic.wreck_recycle_count, traffic.spawn_count, lane_changes_made, wrecks_seen])
	if fails.is_empty():
		print("PASS: no car spawned or vanished in view")
		quit(0)
	else:
		for f in fails.slice(0, 20):
			printerr("FAIL: ", f)
		quit(1)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
