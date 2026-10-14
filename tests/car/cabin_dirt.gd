extends SceneTree

# Cabin dirt levels, beer cans and receipts (MA6, Y1 + Roy 1370). Looks only.
#
# State (CabinDirt, no game): Clean -> Lived-in -> Messy -> Filthy. One level
# per 3 nights of driving; one level sooner for every 4 beers; the two add up.
# Walt's clean resets all of it (level, counters, cans, receipts). Saved per
# car, and one car's mess is not another's. 7 beers leave 6 cans; up to 5
# receipts, one per fuel stop.
#
# Cans (CanSim, no game): under a scripted 0.8 g stop they slide forward and
# every centre stays inside the footwell box on every tick; under a launch they
# slide back; a parked or cruising car puts them to sleep (no work done). The
# cost of six cans awake is printed (the ask was about 0.02 ms).
#
# In the real game (one car, the cockpit view): the cabin gets a CabinClutter;
# each level shows what it should (receipts at Lived-in, dust and stain at
# Messy, smear and bag at Filthy, the smear outside the centre 20 degrees of
# the driver's eye); 7 beers on L leave 6 cans on the floor; a clean empties
# them; a real hard stop from 80 km/h moves the cans forward and keeps them
# inside; clinks never ring more than 2 at once; the night, fuel and Clean the
# car hooks are wired.
#
# One car with NEON_DIRT_CAR=<kind>. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tests/car/cabin_dirt.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RATE := 60
const KIND := "p1_coupe"
const OTHER := "p2_hothatch"
const CFG := "user://cabin_dirt_test.cfg"
const SMEAR_CONE_DEG := 20.0
const BRAKE_G := 0.8
const EPS := 0.0005

var logger := Harness.ErrorCounter.new()
var failures: Array[String] = []
var game: Node
var p: PlayerCar
var cam: ChaseCamera
var frame: CockpitFrame

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	Engine.physics_ticks_per_second = RATE
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	CabinDirt.path = CFG
	CabinDirt.wipe()
	_levels()
	_persistence()
	_sim()
	var kind := OS.get_environment("NEON_DIRT_CAR")
	if kind == "":
		kind = KIND
	await _game(kind)
	CabinDirt.wipe()
	_check(logger.errors.is_empty(), "%d engine error(s): %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in failures:
		printerr("FAIL: ", f)
	print("cabin_dirt: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

# ---------- state ----------

func _levels() -> void:
	CabinDirt.wipe()
	_check(CabinDirt.level(KIND) == CabinDirt.CLEAN, "a fresh car is not Clean")
	# nights: every third one is a level
	for n in 2:
		CabinDirt.night_ended(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.CLEAN, "2 nights made the car dirty")
	CabinDirt.night_ended(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.LIVED_IN, "3 nights did not make it Lived-in (level %d)" % CabinDirt.level(KIND))
	for n in 3:
		CabinDirt.night_ended(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.MESSY, "6 nights did not make it Messy")
	for n in 3:
		CabinDirt.night_ended(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.FILTHY, "9 nights did not make it Filthy")
	for n in 6:
		CabinDirt.night_ended(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.FILTHY, "the level went past Filthy")
	# beers: every fourth is a level, and the cans are counted from the first
	CabinDirt.wipe()
	for n in 3:
		CabinDirt.beer_drunk(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.CLEAN and CabinDirt.cans(KIND) == 3, "3 beers: level %d, %d cans" % [CabinDirt.level(KIND), CabinDirt.cans(KIND)])
	CabinDirt.beer_drunk(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.LIVED_IN, "4 beers did not make it Lived-in")
	for n in 4:
		CabinDirt.beer_drunk(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.MESSY, "8 beers did not make it Messy")
	_check(CabinDirt.cans(KIND) == CabinDirt.MAX_CANS, "8 beers left %d cans, want %d" % [CabinDirt.cans(KIND), CabinDirt.MAX_CANS])
	# the two add up: a level sooner
	CabinDirt.wipe()
	CabinDirt.night_ended(KIND)
	CabinDirt.night_ended(KIND)
	for n in 4:
		CabinDirt.beer_drunk(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.LIVED_IN, "2 nights + 4 beers: level %d, want 1" % CabinDirt.level(KIND))
	CabinDirt.night_ended(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.MESSY, "the third night did not add its level on top of the beers (level %d)" % CabinDirt.level(KIND))
	# receipts: one per fuel stop, five at most
	CabinDirt.wipe()
	for n in 7:
		CabinDirt.fuel_stop(KIND)
	_check(CabinDirt.receipts(KIND) == CabinDirt.MAX_RECEIPTS, "7 fuel stops left %d receipts, want 5" % CabinDirt.receipts(KIND))
	# Walt
	CabinDirt.beer_drunk(KIND)
	CabinDirt.night_ended(KIND)
	CabinDirt.clean(KIND)
	_check(CabinDirt.level(KIND) == CabinDirt.CLEAN and CabinDirt.cans(KIND) == 0 and CabinDirt.receipts(KIND) == 0 \
		and CabinDirt.nights(KIND) == 0 and CabinDirt.beers(KIND) == 0, "Walt's clean did not reset everything")

func _persistence() -> void:
	CabinDirt.wipe()
	for n in 6:
		CabinDirt.night_ended(KIND)
	for n in 3:
		CabinDirt.beer_drunk(KIND)
	CabinDirt.fuel_stop(KIND)
	CabinDirt.fuel_stop(KIND)
	CabinDirt.reload_from_disk()
	_check(CabinDirt.level(KIND) == CabinDirt.MESSY and CabinDirt.cans(KIND) == 3 and CabinDirt.receipts(KIND) == 2 \
		and CabinDirt.beers(KIND) == 3, "the state did not survive a reload: level %d, %d cans, %d receipts" % [CabinDirt.level(KIND), CabinDirt.cans(KIND), CabinDirt.receipts(KIND)])
	_check(CabinDirt.level(OTHER) == CabinDirt.CLEAN and CabinDirt.cans(OTHER) == 0, "one car's mess showed up in another")
	CabinDirt.clean(OTHER)
	_check(CabinDirt.level(KIND) == CabinDirt.MESSY, "cleaning one car cleaned another")
	CabinDirt.wipe()

# ---------- the cans ----------

func _box_ok(s: CanSim) -> bool:
	for i in s.count:
		if s.px[i] < s.x0 - EPS or s.px[i] > s.x1 + EPS or s.pz[i] < s.z0 - EPS or s.pz[i] > s.z1 + EPS:
			return false
	return true

func _mean_z(s: CanSim) -> float:
	var t := 0.0
	for i in s.count:
		t += s.pz[i]
	return t / maxf(float(s.count), 1.0)

func _sim() -> void:
	var s := CanSim.new()
	s.configure(0.18, 0.63, -0.55, 0.0)   # about the coupe's passenger footwell
	var clinks := [0, 0.0]
	s.on_contact = func(strength: float) -> void:
		clinks[0] += 1
		clinks[1] = maxf(clinks[1], strength)
	# six cans toward the back of the floor, as if just dropped there
	for i in 6:
		s.add(0.25 + 0.07 * float(i), s.z1 - 0.02 * float(i % 2))
	s.asleep = true
	for i in 6:
		s.vx[i] = 0.0
		s.vz[i] = 0.0
	_check(s.count == 6, "the sim holds %d cans, want 6" % s.count)
	var z0 := _mean_z(s)
	# a parked car does no work
	var before := s.steps
	for t in 120:
		s.step(1.0 / RATE, 0.0, 0.0, 0.0)
	_check(s.steps == before and s.asleep, "a parked car did work (%d steps) or woke the cans" % (s.steps - before))
	# 0.8 g stop: the car's acceleration is +z (it slows down moving -z)
	var inside := true
	for t in int(1.5 * RATE):
		s.step(1.0 / RATE, 0.0, BRAKE_G * 9.81, 0.0)
		inside = inside and _box_ok(s)
	_check(inside, "a can left the footwell box during the 0.8 g stop")
	var z1 := _mean_z(s)
	_check(z1 < z0 - 0.15, "under a 0.8 g stop the cans moved %.3f m, want forward (toward -z) by 0.15 m or more" % (z0 - z1))
	_check(clinks[0] > 0, "the cans never clinked in the stop")
	# the stop ends: they settle and fall asleep
	for t in int(4.0 * RATE):
		s.step(1.0 / RATE, 0.0, 0.0, 0.0)
	_check(s.asleep, "the cans never settled after the stop")
	var settled := s.steps
	for t in 60:
		s.step(1.0 / RATE, 0.0, 0.0, 0.0)
	_check(s.steps == settled, "settled cans still did work")
	# a launch slides them back
	var back0 := _mean_z(s)
	inside = true
	for t in int(1.5 * RATE):
		s.step(1.0 / RATE, 0.0, -BRAKE_G * 9.81, 0.0)
		inside = inside and _box_ok(s)
	_check(inside, "a can left the footwell box during the launch")
	_check(_mean_z(s) > back0 + 0.15, "under a launch the cans moved %.3f m, want back" % (_mean_z(s) - back0))
	# a hard corner slides them across
	for t in int(1.0 * RATE):
		s.step(1.0 / RATE, 0.8 * 9.81, 0.0, 0.0)
		inside = inside and _box_ok(s)
	_check(inside, "a can left the footwell box in the corner")
	# rough road rattles them awake
	for t in int(4.0 * RATE):
		s.step(1.0 / RATE, 0.0, 0.0, 0.0)
	var quiet := s.steps
	for t in int(2.0 * RATE):
		s.step(1.0 / RATE, 0.0, 0.0, 0.8)
		inside = inside and _box_ok(s)
	_check(s.steps > quiet, "rough road did not wake the cans")
	_check(inside, "a can left the footwell box on the rough road")
	# cost: six cans, awake, a stop then a launch back and forth
	var t0 := Time.get_ticks_usec()
	var n := 0
	for rep in 20:
		for t in 30:
			s.step(1.0 / RATE, 0.0, BRAKE_G * 9.81, 0.0)
			n += 1
		for t in 30:
			s.step(1.0 / RATE, 0.0, -BRAKE_G * 9.81, 0.0)
			n += 1
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	print("cabin_dirt: six cans awake cost %.1f us per tick (ask: about 20)" % us)
	_check(us < 100.0, "six cans cost %.0f us a tick, over the 100 us ceiling" % us)
	# seven drops keep six
	var r := CanSim.new()
	r.configure(0.18, 0.63, -0.55, 0.0)
	for i in 7:
		r.add(0.4, -0.2)
	_check(r.count == CanSim.MAX_CANS, "7 cans on the floor of a %d-can sim" % r.count)

# ---------- the real cabin ----------

func _boot(k: String) -> bool:
	OS.set_environment("NEON_CAR", k)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	for i in RATE:
		await physics_frame
	p = game.get("player")
	cam = game.get("camera")
	if p == null or cam == null or cam.frame == null:
		failures.append("%s: the game should boot with a cockpit frame" % k)
		return false
	frame = cam.frame
	cam.set_view(ChaseCamera.View.COCKPIT)
	return true

func _stopped(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 1.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame

func _visible_count(nodes: Array) -> int:
	var c := 0
	for n in nodes:
		if (n as Node3D).visible:
			c += 1
	return c

func _game(k: String) -> void:
	if not await _boot(k):
		return
	var kind := PlayerCar.chassis_kind()
	CabinDirt.wipe()
	var cl := frame.clutter
	_check(cl != null, "%s: the cockpit has no CabinClutter" % kind)
	if cl == null:
		return
	cl._refresh()
	_check(_visible_count(cl.receipt_nodes) == 0 and not cl.dust.visible and not cl.stain.visible \
		and not cl.smear.visible and not cl.bag.visible and _visible_count(cl.can_nodes) == 0, "%s: a Clean car shows clutter" % kind)
	# each level adds to the one before
	for n in 2:
		CabinDirt.fuel_stop(kind)
	for lvl in [1, 2, 3]:
		for n in CabinDirt.NIGHTS_PER_LEVEL:
			CabinDirt.night_ended(kind)
		cl._refresh()
		var rec := _visible_count(cl.receipt_nodes)
		_check(CabinDirt.level(kind) == lvl, "%s: level %d, want %d" % [kind, CabinDirt.level(kind), lvl])
		_check(rec == 2, "%s: level %d shows %d receipts, want 2" % [kind, lvl, rec])
		_check(cl.dust.visible == (lvl >= 2) and cl.stain.visible == (lvl >= 2), "%s: level %d dust/stain wrong" % [kind, lvl])
		_check(cl.smear.visible == (lvl >= 3) and cl.bag.visible == (lvl >= 3), "%s: level %d smear/bag wrong" % [kind, lvl])
	_smear_cone(cl)
	# a Clean-level car holds receipts without showing them
	CabinDirt.wipe()
	CabinDirt.fuel_stop(kind)
	cl._refresh()
	_check(_visible_count(cl.receipt_nodes) == 0, "%s: receipts show on a Clean car" % kind)
	# seven beers on L: six cans on the floor
	CabinDirt.wipe()
	cl._refresh()
	for n in 7:
		cl.beer_finished()
	_check(CabinDirt.cans(kind) == 6 and cl.sim.count == 6 and _visible_count(cl.can_nodes) == 6, "%s: 7 beers left %d / %d / %d cans (saved / sim / drawn), want 6" % [kind, CabinDirt.cans(kind), cl.sim.count, _visible_count(cl.can_nodes)])
	_check(CabinDirt.level(kind) == CabinDirt.LIVED_IN, "%s: 7 beers made level %d, want Lived-in" % [kind, CabinDirt.level(kind)])
	var on_floor := true
	for i in 6:
		var c := cl.can_nodes[i].position as Vector3
		on_floor = on_floor and c.x > 0.1 and c.x < float(frame.cab.door_x) and absf(c.y - (cl.floor_top + IdleProps.CAN_R)) < 0.001
	_check(on_floor, "%s: a can is not on the passenger footwell floor" % kind)
	# the drivers' beer on the key reaches the clutter: a real use on the key
	CabinDirt.wipe()
	cl._refresh()
	IdleActions.set_item(IdleActions.BEER)
	IdleActions.set_beer_while_moving(true)
	var uses := frame.driver.idle_uses
	frame.driver.request_idle()
	for i in int(5.0 * RATE):
		await physics_frame
	_check(frame.driver.idle_uses - uses == 1 and CabinDirt.cans(kind) == 1 and cl.sim.count == 1, "%s: a beer drunk on L did not drop its can (uses %d, cans %d)" % [kind, frame.driver.idle_uses - uses, CabinDirt.cans(kind)])
	IdleActions.set_item(IdleActions.VAPE)
	# clinks: ten at once make two sounds
	var played := cl.clinks_played
	var dropped := cl.clinks_dropped
	for i in 10:
		cl.play_clink(1.0)
	_check(cl.clinks_played - played == 2 and cl.clinks_dropped - dropped == 8, "%s: ten clinks in one tick: %d played, %d dropped, want 2 and 8" % [kind, cl.clinks_played - played, cl.clinks_dropped - dropped])
	_check(cl.clinks_ringing() <= 2 and cl.max_simultaneous <= 2, "%s: %d clinks ringing at once" % [kind, cl.max_simultaneous])
	# a real hard stop from 80 km/h: the cans go forward and stay in the footwell
	CabinDirt.wipe()
	cl._refresh()
	for n in 6:
		CabinDirt.beer_drunk(kind)
	cl._refresh()   # six cans scattered
	cl.sim.configure(cl.sim.x0 - CanSim.R, cl.sim.x1 + CanSim.R, cl.sim.z0 - CanSim.R, cl.sim.z1 + CanSim.R)
	for i in 6:
		cl.sim.pz[i] = cl.sim.z1   # all at the back of the floor
	var start := _mean_z(cl.sim)
	cl.sim.wake()
	cl._place_cans()
	var ring_before := cl.clinks_played
	p.driver = _stopped
	Harness.launch_player(p, 22.3)
	var inside := true
	var worst_ringing := 0
	var stopped_at := -1
	for i in int(8.0 * RATE):
		await physics_frame
		inside = inside and _box_ok(cl.sim)
		worst_ringing = maxi(worst_ringing, cl.clinks_ringing())
		if stopped_at < 0 and p.linear_velocity.length() < 0.5:
			stopped_at = i
	_check(stopped_at > 0, "%s: the car never stopped from 80 km/h" % kind)
	_check(inside, "%s: a can left the footwell box in the real stop" % kind)
	_check(_mean_z(cl.sim) < start - 0.15, "%s: in a real stop the cans moved %.3f m forward, want 0.15 m or more" % [kind, start - _mean_z(cl.sim)])
	_check(worst_ringing <= 2 and cl.max_simultaneous <= 2, "%s: %d clinks rang at once in the stop" % [kind, maxi(worst_ringing, cl.max_simultaneous)])
	print("cabin_dirt: %s real stop from 80 km/h: %.2f m forward, %d clinks played, %d dropped, at most %d at once" % [kind, start - _mean_z(cl.sim), cl.clinks_played - ring_before, cl.clinks_dropped, cl.max_simultaneous])
	# Walt's clean through the Garage page row empties it all
	var screen := SettingsScreen.new()
	root.add_child(screen)
	await process_frame
	screen.open("Game")
	_check(screen.clean_button != null, "%s: no Clean the car row on the Game page" % kind)
	CabinDirt.night_ended(kind)
	if screen.clean_button != null:
		screen.clean_button.pressed.emit()
	await _ticks(3)
	_check(CabinDirt.level(kind) == CabinDirt.CLEAN and CabinDirt.cans(kind) == 0 and CabinDirt.receipts(kind) == 0, "%s: the Clean the car row did not reset the car" % kind)
	_check(_visible_count(cl.can_nodes) == 0 and cl.sim.count == 0, "%s: the cans are still drawn after the clean" % kind)
	screen.queue_free()
	# the night and fuel-stop hooks in game.gd
	var nc: Variant = game.get("night_clock")
	if nc != null:
		for n in CabinDirt.NIGHTS_PER_LEVEL:
			nc.night_ended.emit(1)
		_check(CabinDirt.level(kind) == CabinDirt.LIVED_IN, "%s: three night_ended signals did not raise the level" % kind)
	var pumps := game.get_children().filter(func(n: Node) -> bool:
		return n.get_script() != null and String(n.get_script().resource_path).ends_with("pump_panel.gd"))
	_check(not pumps.is_empty(), "%s: no PumpPanel in the game" % kind)
	if not pumps.is_empty():
		var before := CabinDirt.receipts(kind)
		pumps[0].filled.emit(10.0)
		_check(CabinDirt.receipts(kind) == before + 1, "%s: a fuel stop did not add a receipt" % kind)
	CabinDirt.wipe()
	game.queue_free()
	await process_frame
	await process_frame

## No vertex of the smear is inside the centre SMEAR_CONE_DEG either side of
## straight ahead from the driver's eye.
func _smear_cone(cl: CabinClutter) -> void:
	var eye: Vector3 = frame.cab.eye
	var arrays := cl.smear.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(verts.size() > 0, "the smear has no geometry")
	var worst := 999.0
	for v in verts:
		var rel := v - eye
		if rel.z >= 0.0:
			continue
		worst = minf(worst, absf(rad_to_deg(atan2(rel.x, -rel.z))))
	_check(worst >= SMEAR_CONE_DEG - 0.5, "the smear comes within %.1f degrees of straight ahead, want %.0f or more" % [worst, SMEAR_CONE_DEG])
