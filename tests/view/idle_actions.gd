extends SceneTree

# Idle actions (L, 2026-10-11): one puff of the vape or one sip of the beer,
# whichever Settings > Game > Driver has picked. For every player car:
# - vape, window shut (cockpit view) and window down (chase view): L -> the left
#   hand leaves the rim, the hand shaped round the vape shows instead of the
#   mitten, it reaches the mouth and is back on the rim within 3 s; a cloud of
#   at most 10 puffs appears and is gone within 3 s of the hand being back;
#   with the window down some of it gets out past the door line;
# - sight line, every tick: no corner of the left hand or of the item it holds,
#   and no puff (top edge), is above 8 degrees below the eye within 20 degrees
#   either side of straight ahead;
# - beer: with "beer while driving" on, L works at 80 km/h; off, nothing at
#   80 km/h and it works parked;
# - cigarette (MA5), from a shut window and from a down one: the window rolls
#   down a little by itself (about 0.55) and back up after, and not at all if
#   it was down; the lighter clicks once and its flame and light are up about
#   0.4 s; three drags each with a breath out and a brighter tip; the
#   cigarette gets shorter with every drag and never longer (its length is the
#   only health bar); the butt is flicked out of the window by itself through
#   the pooled ember burst, always; three fast presses are at most two uses;
# - traffic flicks (once, driven by hand): a car 24 m ahead flicks no more than
#   once per 120 s, none from 60 m ahead or from behind;
# - None: L does nothing;
# - one hand, one job: L during a window roll or a flip-off waits and then runs
#   once; three fast presses are at most two uses; K and the window key (held,
#   or tapped) during a use wait until the hand is back; the right hand never
#   leaves the rim;
# - glove only: no arm, forearm or sleeve node;
# - no stats: the same scripted drive from a fresh boot, once with the hands on
#   the wheel and once with ten uses (five puffs, five sips), gives the same
#   speed, yaw, steering and position trace tick for tick, and the same cash, bank, heat,
#   damage and fuel at the end, exactly.
# Once: the two Settings rows change, save and load the choice.
# One car with NEON_IDLE_CAR=<kind>. Needs --fixed-fps 60 (the two drives are
# compared tick for tick). Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/view/idle_actions.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RATE := 60
const CONE_DEG := 20.0
const SIGHT_DEG := 8.0
const GRIP_TOL := 0.02
const TAP_TICKS := 3
const BACK_SECS := 3.0
const CLOUD_SECS := 3.0
const MOUTH_TOL := 0.03
const CIG_BACK_SECS := 4.6     # reach, light, three drags, lower, back to the rim
const USES := 10
const DRIVE_SECS := 27.0
const DRIVE_SPEED := 22.3      # m/s, 80 km/h
## The first boot of a process settles a hair differently from every later one
## (the speed is about 0.0001 m/s off at the first tick of the drive, before any
## use), and later boots repeat bit for bit. So one boot is thrown away first
## and the two drives are then compared exactly. Speed, yaw rate, steering input, x.
const TRACE_NAMES := ["speed", "yaw rate", "steering", "x"]

var logger := Harness.ErrorCounter.new()
var failures: Array[String] = []
var game: Node
var p: PlayerCar
var cam: ChaseCamera
var frame: CockpitFrame
var d: DriverModel
var kind := ""
# what _sample() saw since the last _watch()
var saw_idle := false
var saw_hold := ""
var mouth_gap := INF         # the nearest the hand got to the mouth pose
var most_puffs := 0
var puff_out := -INF         # the furthest out (-x) any puff got
var cone_worst := ""
var right_off := false
var hands_wrong := false
var flame_ticks := 0         # ticks the lighter's flame was up
var flame_light_ok := true
var tip_peak := 0.0          # the brightest the cigarette tip got
var cig_first := -1.0        # how much cigarette was left at the first sample of a use, and the last
var cig_last := -1.0
var cig_mono := true         # it never got longer
var cig_paper_first := -1.0  # the paper's drawn length, m
var cig_paper_last := -1.0
var win_max := 0.0           # the window's range during the watch
var win_min := 1.0
var window_hand_seen := false   # the crank or switch animated (window_direction != 0)
var traffic_checked := false # the traffic flick check runs once, on the first car

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append("%s: %s" % [kind, msg])

func _initialize() -> void:
	Engine.physics_ticks_per_second = RATE
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_environment("NEON_IDLE_CAR")
	OS.set_environment("NEON_IDLE", "")
	var warm := true
	for k in PlayerCars.ids():
		if only != "" and String(k) != only:
			continue
		if warm:
			warm = false
			kind = String(k)
			if await _boot(kind):
				await _unboot()
		await _car(String(k))
	OS.set_environment("NEON_CAR", "")
	_release_keys()
	kind = "settings"
	await _settings_rows()
	kind = "all"
	_check(logger.errors.is_empty(), "%d engine error(s): %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in failures:
		printerr("FAIL: ", f)
	print("idle_actions: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _release_keys() -> void:
	for a in ["idle_action", "flip_off", "window"]:
		Input.action_release(a)

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame
		_sample()

func _secs(s: float) -> void:
	await _ticks(int(round(s * RATE)))

func _watch() -> void:
	saw_idle = false
	saw_hold = ""
	mouth_gap = INF
	most_puffs = 0
	puff_out = -INF
	cone_worst = ""
	right_off = false
	hands_wrong = false
	flame_ticks = 0
	flame_light_ok = true
	tip_peak = 0.0
	cig_first = -1.0
	cig_last = -1.0
	cig_mono = true
	cig_paper_first = -1.0
	cig_paper_last = -1.0
	win_max = 0.0
	win_min = 1.0
	window_hand_seen = false

func _in_view(c: Vector3, what: String) -> void:
	var rel: Vector3 = c - (frame.cab.eye as Vector3)
	if rel.z >= 0.0 or cone_worst != "":
		return
	var az := rad_to_deg(atan2(-rel.x, -rel.z))
	var el := rad_to_deg(atan2(rel.y, Vector2(rel.x, rel.z).length()))
	if absf(az) < CONE_DEG and el > -SIGHT_DEG:
		cone_worst = "%s %.1f deg left, %.1f deg up (%s)" % [what, az, el, DriverModel.LeftAct.keys()[d.left_act]]

func _corners(node: MeshInstance3D, what: String) -> void:
	var bb := node.mesh.get_aabb()
	for i in 8:
		_in_view(node.transform * bb.get_endpoint(i), what)

## One look at the left hand, the item and the cloud, in car space.
func _sample() -> void:
	var shown := 0
	var hand: MeshInstance3D = d.hands[-1]
	if hand.visible:
		shown += 1
	if d.finger_hand.visible:
		shown += 1
		hand = d.finger_hand
	for item in d.hold_hands:
		var h: MeshInstance3D = d.hold_hands[item]
		if h.visible:
			shown += 1
			hand = h
			saw_hold = String(item)
			var held_node: MeshInstance3D = d.props.vape
			if item == IdleActions.BEER:
				held_node = d.props.can
			elif item == IdleActions.CIGARETTE:
				held_node = d.props.cig
			_corners(held_node, "the " + String(item))
			for ch in held_node.get_children():   # the cigarette's paper and tip hang off it
				if ch is MeshInstance3D and ch.visible:
					var bb := (ch as MeshInstance3D).mesh.get_aabb()
					for i in 8:
						_in_view(held_node.transform * (ch as Node3D).transform * bb.get_endpoint(i), "the " + String(item))
			mouth_gap = minf(mouth_gap, h.position.distance_to((frame.cab.eye as Vector3) + DriverModel.IDLE_MOUTH[item]))
	hands_wrong = hands_wrong or shown != 1
	saw_idle = saw_idle or d.is_idling()
	if d.props.flame_up():
		flame_ticks += 1
		flame_light_ok = flame_light_ok and d.props.flame_light.visible and d.props.lighter.visible
	elif d.props.flame_light.visible or d.props.lighter.visible:
		flame_light_ok = false   # the flame's light must go out with the flame
	tip_peak = maxf(tip_peak, d.props.tip_energy())
	win_max = maxf(win_max, frame.window)
	win_min = minf(win_min, frame.window)
	window_hand_seen = window_hand_seen or frame.window_direction != 0
	if saw_hold == IdleActions.CIGARETTE and d.hold_hands[IdleActions.CIGARETTE].visible:
		var left: float = d.props.burn_left()
		var len: float = d.props.paper.scale.y
		if cig_first < 0.0:
			cig_first = left
			cig_paper_first = len
		if cig_last >= 0.0 and left > cig_last + 0.0001:
			cig_mono = false
		cig_last = left
		cig_paper_last = len
	_corners(hand, "the left hand")
	var puffs := d.props.puffs()
	most_puffs = maxi(most_puffs, puffs.size())
	for puff in puffs:
		var c: Vector3 = puff[0]
		puff_out = maxf(puff_out, -c.x)
		_in_view(c + Vector3(0.0, float(puff[1]), 0.0), "a puff")
	if d.is_busy() or d.hand_position(1).distance_to(d.grip_position(1)) > GRIP_TOL:
		right_off = true

func _set_window(v: float) -> void:
	cam.perspective.window = v
	await _ticks(3)
	_check(is_equal_approx(frame.window, v) and frame.window_direction == 0, "the test could not put the window at %.1f" % v)

func _tap(action: String = "idle_action") -> void:
	Input.action_press(action)
	await _ticks(TAP_TICKS)
	Input.action_release(action)

func _on_rim(what: String) -> void:
	_check(d.left_act == DriverModel.LeftAct.GRIP, "%s: the left hand is not back (%s)" % [what, DriverModel.LeftAct.keys()[d.left_act]])
	_check(d.hand_position(-1).distance_to(d.grip_position(-1)) < GRIP_TOL, "%s: the left hand is %.3f m off the rim" % [what, d.hand_position(-1).distance_to(d.grip_position(-1))])
	_check((d.hands[-1] as Node3D).visible, "%s: the mitten is not back" % what)

func _always(what: String) -> void:
	_check(cone_worst == "", "%s: in the road view: %s" % [what, cone_worst])
	_check(not right_off, "%s: the right hand left the rim" % what)
	_check(not hands_wrong, "%s: the left hand showed as two meshes, or none" % what)

## Foot on the brake, hands on the wheel (an automatic creeps with the brake off).
func _stopped(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 1.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _park() -> void:
	p.driver = _stopped
	Harness.launch_player(p, 0.0)
	await _wait_for(func() -> bool: return p.linear_velocity.length() * 3.6 < 1.0, 6.0)
	await _secs(0.5)

func _boot(k: String) -> bool:
	OS.set_environment("NEON_CAR", k)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	p = game.get("player")
	cam = game.get("camera")
	if p == null or cam == null or cam.frame == null or cam.frame.driver == null:
		failures.append("%s: the game should boot with a cockpit frame and a driver" % k)
		await _unboot()
		return false
	frame = cam.frame
	d = frame.driver
	IdleActions.set_item(IdleActions.VAPE)
	IdleActions.set_beer_while_moving(true)
	cam.set_view(ChaseCamera.View.COCKPIT)
	return true

func _unboot() -> void:
	_release_keys()
	game.queue_free()
	await process_frame
	await process_frame

func _car(k: String) -> void:
	kind = k
	# the same drive twice from a fresh boot: hands on the wheel, then ten uses
	if not await _boot(k):
		return
	var plain := await _drive(false)
	await _unboot()
	if not await _boot(k):
		return
	var used := await _drive(true)
	_same_drive(plain, used)
	IdleActions.set_item(IdleActions.VAPE)
	await _park()

	_check(InputMap.has_action("idle_action"), "idle_action should be bound")
	for n in d.find_children("*", "", true, false):
		var low := String(n.name).to_lower()
		_check(not ("arm" in low or "sleeve" in low), "the driver has a %s node" % n.name)
	_check(d.props.cloud.multimesh.instance_count <= 10, "the cloud has %d puffs, want at most 10" % d.props.cloud.multimesh.instance_count)
	_watch()
	await _ticks(2)
	_always("at rest")
	_check(d.props.vape.visible and not d.props.can.visible, "with Vape picked only the vape should be in the car")

	await _vape_case(false)
	cam.set_view(ChaseCamera.View.CHASE)
	await _vape_case(true)
	cam.set_view(ChaseCamera.View.COCKPIT)
	await _beer_cases()
	await _cigarette_cases()
	if not traffic_checked:
		traffic_checked = true
		_traffic_flicks()
	await _none_case()
	await _wait_cases()
	print("idle_actions: %s ok so far: %d failure(s)" % [k, failures.size()])
	await _unboot()

func _vape_case(open: bool) -> void:
	var what := "vape, window %s" % ("down" if open else "shut")
	IdleActions.set_item(IdleActions.VAPE)
	await _set_window(1.0 if open else 0.0)
	var uses := d.idle_uses
	_watch()
	await _tap()
	await _ticks(int(BACK_SECS * RATE) - TAP_TICKS)
	_check(saw_idle and saw_hold == IdleActions.VAPE, "%s: L did not bring the vape up" % what)
	_check(mouth_gap < MOUTH_TOL, "%s: the hand got no nearer than %.3f m to the mouth" % [what, mouth_gap])
	_check(d.idle_uses - uses == 1, "%s: %d uses for one press" % [what, d.idle_uses - uses])
	_on_rim(what)
	_check(most_puffs > 0, "%s: no cloud" % what)
	await _secs(CLOUD_SECS)
	_check(d.props.puff_count() == 0, "%s: %d puffs still there %.0f s after the hand was back" % [what, d.props.puff_count(), CLOUD_SECS])
	_check(most_puffs <= 10, "%s: %d puffs at once" % [what, most_puffs])
	if open:
		_check(puff_out > d.door_line(), "%s: the cloud never got out of the window (%.2f out, the door line is %.2f)" % [what, puff_out, d.door_line()])
	elif d.has_door_glass():
		_check(puff_out < d.door_line(), "%s: the cloud went through the glass" % what)
	_always(what)

## One press; true if a use started within half a second.
func _press_starts() -> bool:
	_watch()
	await _tap()
	await _secs(0.5)
	return saw_idle

func _beer_cases() -> void:
	IdleActions.set_item(IdleActions.BEER)
	await _set_window(0.0)
	_check(d.props.can.visible and not d.props.vape.visible, "with Beer picked only the can should be in the car")
	# switched on, at 80 km/h
	IdleActions.set_beer_while_moving(true)
	Harness.launch_player(p, DRIVE_SPEED)
	await _ticks(5)
	var uses := d.idle_uses
	_check(p.linear_velocity.length() * 3.6 > 60.0 and p.engine_running, "the test could not get the car to 80 km/h with the engine running (%.0f km/h)" % (p.linear_velocity.length() * 3.6))
	_check(await _press_starts(), "beer while driving on, 80 km/h: L did nothing")
	await _secs(BACK_SECS - 0.5)
	_check(saw_hold == IdleActions.BEER and mouth_gap < MOUTH_TOL, "beer at 80 km/h: the can did not reach the mouth (%.3f m)" % mouth_gap)
	_check(d.idle_uses - uses == 1, "beer at 80 km/h: %d uses for one press" % (d.idle_uses - uses))
	_check(most_puffs == 0, "the beer made a cloud")
	_on_rim("beer at 80 km/h")
	_always("beer at 80 km/h")
	# switched off, at 80 km/h: nothing
	IdleActions.set_beer_while_moving(false)
	Harness.launch_player(p, DRIVE_SPEED)
	await _ticks(5)
	_check(p.linear_velocity.length() * 3.6 > 60.0 and p.engine_running, "the test could not hold 80 km/h for the switched-off case")
	uses = d.idle_uses
	_check(not await _press_starts(), "beer while driving off, 80 km/h: L still worked")
	await _secs(1.0)
	_check(d.idle_uses == uses and not d.idle_waiting(), "beer while driving off, 80 km/h: a use happened or is waiting")
	# switched off, parked: works
	await _park()
	_check(p.linear_velocity.length() * 3.6 < IdleActions.PARKED_KMH, "the test could not park the car (%.1f km/h)" % (p.linear_velocity.length() * 3.6))
	_check(await _press_starts(), "beer while driving off, parked: L did nothing")
	await _secs(BACK_SECS - 0.5)
	_check(d.idle_uses - uses == 1, "beer parked: %d uses for one press" % (d.idle_uses - uses))
	_on_rim("beer parked")
	_always("beer parked")
	IdleActions.set_beer_while_moving(true)

## The cigarette (MA5): the same states as the vape, from a shut window and an
## open one. The window rolls down a little by itself for the light (and back
## up after, if it opened it); lighter first (a click, a flame for about 0.4 s
## and the one extra light, the tip catching); three drags with a breath out
## after each and the tip brighter on each, the cigarette itself shorter with
## every drag (its length is the only "health bar"); then the butt is flicked
## out of the window by itself as an ember behind the car.
func _cigarette_cases() -> void:
	for start_open in [false, true]:
		var what := "cigarette, window starts %s" % ("down" if start_open else "shut")
		IdleActions.set_item(IdleActions.CIGARETTE)
		cam.set_view(ChaseCamera.View.CHASE if start_open else ChaseCamera.View.COCKPIT)
		await _set_window(1.0 if start_open else 0.0)
		var pr: IdleProps = d.props
		_check(pr.cig.visible and not pr.vape.visible and not pr.can.visible, "with Cigarette picked only the cigarette should be in the car")
		var ember: EmberFlick = EmberFlick.current
		_check(ember != null and is_instance_valid(ember), "%s: no EmberFlick in the game" % what)
		var uses := d.idle_uses
		var clicks := pr.lighter_clicks
		var exhales := pr.exhales
		var flicked := pr.butts_flicked
		var player_flicks := ember.player_flicks if ember != null else 0
		_check(is_equal_approx(pr.burn_left(), 1.0), "%s: a fresh cigarette is not whole (%.2f)" % [what, pr.burn_left()])
		_watch()
		await _tap()
		await _secs(CIG_BACK_SECS - float(TAP_TICKS) / RATE)
		_check(saw_idle and saw_hold == IdleActions.CIGARETTE, "%s: L did not bring the cigarette up" % what)
		_check(mouth_gap < MOUTH_TOL, "%s: the hand got no nearer than %.3f m to the mouth" % [what, mouth_gap])
		_check(d.idle_uses - uses == 1, "%s: %d uses for one press" % [what, d.idle_uses - uses])
		_on_rim(what)
		_check(pr.lighter_clicks - clicks == 1, "%s: %d lighter clicks, want 1" % [what, pr.lighter_clicks - clicks])
		var flame_s := float(flame_ticks) / RATE
		_check(flame_s > 0.3 and flame_s < 0.5, "%s: the flame was up %.2f s, want about 0.4" % [what, flame_s])
		_check(flame_light_ok and not pr.flame_light.visible and not pr.lighter.visible, "%s: the flame's light did not go out with the flame" % what)
		_check(pr.exhales - exhales == DriverModel.CIG_DRAGS, "%s: %d breaths, want %d drags" % [what, pr.exhales - exhales, DriverModel.CIG_DRAGS])
		_check(tip_peak >= IdleProps.TIP_DRAG * 0.9, "%s: the tip peaked at %.1f, want about %.1f on a drag" % [what, tip_peak, IdleProps.TIP_DRAG])
		_check(pr.tip_energy() == IdleProps.TIP_UNLIT and not pr.is_lit(), "%s: the tip is still glowing at the end" % what)
		_check(most_puffs > 0 and most_puffs <= IdleProps.MAX_PUFFS, "%s: %d puffs at once" % [what, most_puffs])
		# it shortens with every drag, never grows back, and is a butt at the end
		_check(cig_first > 0.99 and cig_last <= IdleProps.BURN_END + 0.02, "%s: the cigarette went from %.2f to %.2f of its length" % [what, cig_first, cig_last])
		_check(cig_mono, "%s: the cigarette got longer during the use" % what)
		_check(cig_paper_last < cig_paper_first * 0.4, "%s: the paper is %.4f m of %.4f m, want under 40%%" % [what, cig_paper_last, cig_paper_first])
		# the window: a little by itself from shut, none of the crank or switch, untouched if already down
		_check(not window_hand_seen, "%s: the window's crank or switch animated (the hand was busy)" % what)
		if not d.has_door_glass():
			# no pane to roll (the open kei, DriverModel.has_door_glass): the arm goes over the door
			_check(win_max - win_min < 0.01, "%s: a car with no door glass moved its window (%.2f..%.2f)" % [what, win_min, win_max])
		elif start_open:
			_check(is_equal_approx(frame.window, 1.0) and win_min > 0.99, "%s: the window moved from fully down (%.2f)" % [what, win_min])
		else:
			_check(win_max >= 0.5 and win_max <= 0.7, "%s: the window rolled to %.2f, want a little past half" % [what, win_max])
			_check(await _wait_for(func() -> bool: return frame.window < 0.01, 3.0), "%s: the window did not roll back up (%.2f)" % [what, frame.window])
		# the smoke and the butt went out of the window
		_check(puff_out > d.door_line(), "%s: the smoke never got out of the window (%.2f out, the door line is %.2f)" % [what, puff_out, d.door_line()])
		_check(pr.butts_flicked - flicked == 1, "%s: the butt was not flicked out" % what)
		if ember != null:
			_check(ember.player_flicks - player_flicks == 1, "%s: the ember effect did not play (%d flicks)" % [what, ember.player_flicks - player_flicks])
			var side := p.to_local(ember.last_origin)
			_check(side.x < -d.door_line(), "%s: the ember left from %.2f m, inside the door line %.2f" % [what, side.x, d.door_line()])
			_check(ember.last_ground < ember.last_origin.y, "%s: the road slab is not under the flick" % what)
		await _secs(CLOUD_SECS)
		_check(pr.puff_count() == 0, "%s: %d puffs still there %.0f s after the hand was back" % [what, pr.puff_count(), CLOUD_SECS])
		_always(what)
	cam.set_view(ChaseCamera.View.COCKPIT)
	await _set_window(0.0)
	# the rules the vape and the beer follow: a press during a use queues one more, no more
	var uses := d.idle_uses
	for i in 3:
		await _tap()
		await _ticks(6)
	await _secs(CIG_BACK_SECS * 2.0 + 1.0)
	_check(d.idle_uses - uses == 2, "three fast cigarette presses made %d uses, want 2" % (d.idle_uses - uses))
	_on_rim("three fast cigarette presses")
	await _secs(CLOUD_SECS)
	IdleActions.set_item(IdleActions.VAPE)

## T9: a car ahead flicks one now and then. Driven by hand with a big step
## (no waiting 120 s): a car 24 m ahead, then one 60 m ahead and one behind.
func _traffic_flicks() -> void:
	var cars: Array = game.traffic.cars
	if cars.is_empty():   # the harness boots with no traffic: add one
		game.traffic.add_rival("n1_commuter", p.global_position.x, p.global_position.z - 24.0, 0.0, Color(0.5, 0.5, 0.55))
		cars = game.traffic.cars
	_check(not cars.is_empty(), "the test needs a traffic car")
	if cars.is_empty():
		return
	var game_ember: EmberFlick = EmberFlick.current
	var e := EmberFlick.new()
	e.player = p
	e.traffic = game.traffic
	e.set_physics_process(false)   # only the manual steps below drive it
	root.add_child(e)
	var car: Node3D = cars[0]
	var fwd := -p.global_transform.basis.z
	var t0 := Time.get_ticks_usec()
	var steps := 0
	# a car 24 m ahead, 2000 s in 0.05 s steps
	car.global_position = p.global_position + fwd * 24.0
	for i in 40000:
		e._physics_process(0.05)
		steps += 1
	var per_step_us := float(Time.get_ticks_usec() - t0) / steps
	_check(e.traffic_flicks >= 5 and e.traffic_flicks <= 14, "2000 s with a car ahead made %d flicks, want about 6 to 13" % e.traffic_flicks)
	_check(e.traffic_flicks >= 1 and e.flick_log[0] >= EmberFlick.FIRST_MIN - 0.1 and e.flick_log[0] <= EmberFlick.FIRST_MAX + 2.1, "the first flick came at %s s" % (str(e.flick_log[0]) if not e.flick_log.is_empty() else "never"))
	var worst_gap := INF
	for i in range(1, e.flick_log.size()):
		worst_gap = minf(worst_gap, e.flick_log[i] - e.flick_log[i - 1])
	_check(worst_gap >= 120.0, "two traffic flicks %.0f s apart, want 120 s or more" % worst_gap)
	_check(e.last_origin.distance_to(car.global_position) < 3.0, "the ember left %.1f m from the car" % e.last_origin.distance_to(car.global_position))
	_check(e.flicks == e.traffic_flicks, "flick counters disagree: %d vs %d" % [e.flicks, e.traffic_flicks])
	# a car too far ahead, and one behind: nothing, however long we wait
	var before := e.traffic_flicks
	car.global_position = p.global_position + fwd * 60.0
	for i in 12000:
		e._physics_process(0.05)
	_check(e.traffic_flicks == before, "a car 60 m ahead flicked")
	car.global_position = p.global_position - fwd * 24.0
	for i in 12000:
		e._physics_process(0.05)
	_check(e.traffic_flicks == before, "a car behind the player flicked")
	print("idle_actions: traffic flicks %d in 2000 s (first at %.0f s, closest pair %.0f s apart), %.1f us per step" % [before, e.flick_log[0] if not e.flick_log.is_empty() else -1.0, worst_gap, per_step_us])
	e.free()
	EmberFlick.current = game_ember

func _none_case() -> void:
	IdleActions.set_item(IdleActions.NONE)
	await _ticks(2)
	_check(not d.props.can.visible and not d.props.vape.visible, "with None picked nothing should be in the car")
	var uses := d.idle_uses
	_check(not await _press_starts(), "None: L did something")
	await _secs(1.0)
	_check(d.idle_uses == uses and not d.idle_waiting(), "None: a use happened or is waiting")
	_on_rim("None")
	IdleActions.set_item(IdleActions.VAPE)

## Ticks until `until` is true, at most `secs`; false if it never was.
func _wait_for(until: Callable, secs: float) -> bool:
	var n := 0
	while not until.call() and n < int(secs * RATE):
		await _ticks(1)
		n += 1
	return until.call()

func _wait_cases() -> void:
	IdleActions.set_item(IdleActions.VAPE)
	# L while the window is rolling: nothing until the window stops, then once
	await _set_window(0.0)
	var uses := d.idle_uses
	_watch()
	Input.action_press("window")
	await _ticks(6)
	await _tap()
	await _ticks(20)
	_check(not saw_idle, "L during a window roll did not wait")
	Input.action_release("window")
	_check(await _wait_for(d.is_idling, 4.0), "the waiting L never happened once the window stopped")
	_check(frame.window_direction == 0, "the use started while the window was still moving")
	await _secs(BACK_SECS)
	_check(d.idle_uses - uses == 1, "L during a window roll: %d uses" % (d.idle_uses - uses))
	_on_rim("L after a window roll")
	_always("L during a window roll")
	# L while the finger is out: waits, then once
	await _set_window(0.0)
	uses = d.idle_uses
	_watch()
	await _tap("flip_off")
	await _secs(0.3)
	_check(d.is_gesturing(), "the flip-off should be under way")
	await _tap()
	var together := false
	var guard := 0
	while d.is_gesturing() and guard < RATE * 4:
		await _ticks(1)
		guard += 1
		together = together or d.is_idling()
	_check(not together and not d.is_gesturing(), "L during a flip-off did not wait for it (%s, %d ticks, hand %s)" % ["the use began with the finger out" if together else "the finger stayed out", guard, DriverModel.LeftAct.keys()[d.left_act]])
	_check(await _wait_for(d.is_idling, 2.0), "the waiting L never happened after the flip-off")
	await _secs(BACK_SECS)
	_check(d.idle_uses - uses == 1, "L during a flip-off: %d uses" % (d.idle_uses - uses))
	_on_rim("L after a flip-off")
	_always("L during a flip-off")
	# three fast presses: at most two uses
	uses = d.idle_uses
	_watch()
	for i in 3:
		await _tap()
		await _ticks(6)
	await _secs(BACK_SECS * 2.0 + 1.0)
	_check(d.idle_uses - uses == 2, "three fast presses made %d uses, want 2" % (d.idle_uses - uses))
	_on_rim("three fast presses")
	_always("three fast presses")
	# K during a use: the finger waits for the hand to be back
	_watch()
	await _tap()
	await _secs(0.5)
	_check(d.is_idling(), "the use should be under way")
	await _tap("flip_off")
	together = false
	guard = 0
	while d.is_idling() and guard < RATE * 4:
		await _ticks(1)
		guard += 1
		together = together or d.is_gesturing()
	_check(not together, "K during a use did not wait")
	_check(await _wait_for(d.is_gesturing, 2.0), "the waiting K never happened after the use")
	await _secs(2.5)
	_on_rim("K after a use")
	_always("K during a use")
	# the window key held during a use: the window stays put until the hand is back
	await _set_window(0.0)
	_watch()
	await _tap()
	await _secs(0.5)
	Input.action_press("window")
	var moved := false
	guard = 0
	while d.is_idling() and guard < RATE * 4:
		await _ticks(1)
		guard += 1
		moved = moved or frame.window > 0.0 or frame.window_direction != 0
	_check(not moved, "the window moved during a use")
	await _secs(0.5)
	_check(frame.window > 0.0, "the held window key did nothing after the use")
	Input.action_release("window")
	await _secs(0.6)
	_always("the window key during a use")
	# a window tap during a use: kept, and the window rolls up once the hand is back
	await _set_window(1.0)
	_watch()
	await _tap()
	await _secs(0.5)
	await _tap("window")
	moved = false
	guard = 0
	while d.is_idling() and guard < RATE * 4:
		await _ticks(1)
		guard += 1
		moved = moved or frame.window < 1.0 or frame.window_direction != 0
	_check(not moved, "a window tap moved the window during a use")
	await _secs(1.0)
	_check(frame.window < 1.0, "the window tap made during a use was lost")
	await _wait_for(func() -> bool: return frame.window_direction == 0, 6.0)
	await _secs(0.6)
	_on_rim("after the window tap")
	_always("a window tap during a use")
	await _secs(CLOUD_SECS)

func _stats() -> Dictionary:
	var s := {}
	var wallet: Variant = game.get("wallet")
	if wallet != null:
		s["cash"] = wallet.get("cash")
		s["bank"] = wallet.get("bank")
	var heat: Variant = game.get("police_heat")
	if heat != null:
		s["heat"] = heat.get("heat")
		s["level"] = heat.get("level")
		s["seen"] = heat.get("seen")
	var damage: Variant = p.get("damage")
	if damage != null:
		s["parts"] = str(damage.get("parts"))
		s["lamps"] = str(damage.get("lamps"))
		s["hits"] = damage.get("hits")
	var tank: Variant = p.get("fuel")
	if tank != null:
		s["fuel"] = tank.get("litres")
	return s

## The scripted drive: launched at 80 km/h, the lane driver holding the lane
## and the speed for DRIVE_SECS. With `use` on, ten presses on the way (five
## with the vape, five with the beer). Returns the trace and the end stats.
func _drive(use: bool) -> Dictionary:
	p.driver = Harness.lane_driver(p.global_position.x, 0.5, DRIVE_SPEED)
	Harness.launch_player(p, DRIVE_SPEED)
	var trace := PackedFloat32Array()
	var uses := d.idle_uses
	var every := int(DRIVE_SECS * RATE / USES) - 6
	_watch()
	for i in int(DRIVE_SECS * RATE):
		if use and i % every == 12 and i / every < USES:
			IdleActions.set_item(IdleActions.VAPE if i / every < USES / 2 else IdleActions.BEER)
			Input.action_press("idle_action")
		elif i % every == 12 + TAP_TICKS:
			Input.action_release("idle_action")
		await physics_frame
		_sample()
		trace.append(p.linear_velocity.length())
		trace.append(p.angular_velocity.y)
		trace.append(p.steering_input)
		trace.append(p.global_position.x)
	if use:
		_check(d.idle_uses - uses == USES, "the drive made %d uses, want %d" % [d.idle_uses - uses, USES])
		_always("ten uses on the move")
	return {"trace": trace, "stats": _stats()}

func _same_drive(plain: Dictionary, used: Dictionary) -> void:
	var a: PackedFloat32Array = plain.trace
	var b: PackedFloat32Array = used.trace
	var worst := [0.0, 0.0, 0.0, 0.0]
	for i in mini(a.size(), b.size()):
		worst[i % 4] = maxf(worst[i % 4], absf(a[i] - b[i]))
	_check(a.size() == b.size(), "the two drives are not the same length")
	for c in 4:
		_check(worst[c] == 0.0, "ten uses changed the drive: %s differs by up to %.6f" % [TRACE_NAMES[c], worst[c]])
	var sa: Dictionary = plain.stats
	var sb: Dictionary = used.stats
	_check(not sa.is_empty(), "no stats to compare (wallet, heat, damage and fuel are all missing)")
	_check(str(sa) == str(sb), "ten uses changed the stats: %s -> %s" % [sa, sb])
	print("idle_actions: %s drive, %d ticks: worst difference speed %.5f m/s, yaw %.5f rad/s, steering %.5f, x %.5f m; heat %s / %s, fuel %s / %s" % [
		kind, a.size() / 4, worst[0], worst[1], worst[2], worst[3], sa.get("heat"), sb.get("heat"), sa.get("fuel"), sb.get("fuel")])

## Settings > Game > Driver: the two rows set, save and load the choice.
func _settings_rows() -> void:
	AudioSettings.path = "user://idle_actions_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	IdleActions.load_settings()
	_check(IdleActions.item == IdleActions.VAPE and IdleActions.beer_while_moving, "the defaults should be Vape and On")
	var screen := SettingsScreen.new()
	root.add_child(screen)
	await process_frame
	screen.open("Game")
	var names := []
	for i in screen.idle_item_option.item_count:
		names.append(screen.idle_item_option.get_item_text(i))
	_check(names == ["Vape", "Beer", "Cigarette", "None"], "the In the car row offers %s" % [names])
	_check(screen.idle_item_option.selected == 0 and screen.beer_moving_option.selected == 1, "the rows should show Vape and On")
	screen.idle_item_option.select(2)
	screen.idle_item_option.item_selected.emit(2)
	_check(IdleActions.item == IdleActions.CIGARETTE, "Cigarette was not picked from the row")
	screen.idle_item_option.select(3)
	screen.idle_item_option.item_selected.emit(3)
	screen.beer_moving_option.select(0)
	screen.beer_moving_option.item_selected.emit(0)
	_check(IdleActions.item == IdleActions.NONE and not IdleActions.beer_while_moving, "the rows did not change the setting")
	IdleActions.set_item(IdleActions.VAPE)
	IdleActions.set_beer_while_moving(true)
	IdleActions.load_settings()
	_check(IdleActions.item == IdleActions.NONE and not IdleActions.beer_while_moving, "the choice was not saved")
	screen.idle_item_option.select(1)
	screen.idle_item_option.item_selected.emit(1)
	IdleActions.load_settings()
	_check(IdleActions.item == IdleActions.BEER, "Beer was not saved")
	screen.queue_free()
	DirAccess.remove_absolute(AudioSettings.path)
	IdleActions.set_item(IdleActions.VAPE)
	IdleActions.set_beer_while_moving(true)
	await process_frame
