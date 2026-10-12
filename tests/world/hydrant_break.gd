extends SceneTree

# Breakable world I3 + MA7a (2026-10-11): burst hydrants, scripts/world/hydrant_water.gd
# with the breaker (scripts/world/prop_break.gd).
#
#  hit      a hydrant stood in the lane is hit at 50 km/h with the right
#           corner: 8-12 km/h lost, the nose turns 1-3 degrees toward it, the
#           car takes one fixed hit, and the hydrant sprays.
#  column   driving through the standing jet: 1-2 km/h of drag once, the
#           water sheet is up, the wipers are sent fast.
#  patch    20 s later the wet patch has run 30 m down the gutter: wheels on
#           it sit at shallow-water grip (0.90 of the weather's), wheels off
#           it at the weather's; the tyres then leave tracks for about 100 m.
#  lift     parked with a front wheel on the jet: the car bobs up by more
#           than nothing and at most ~5 cm, stays upright, and 2 s in the
#           water takes a step off the dirt.
#  cap      a third burst hydrant turns the first into a plain wet patch.
#  dry      the jet sinks over its last 5 game minutes and stops 15-25 game
#           minutes after the hit; the patch is gone 45 game minutes later
#           and the grip is back.
#  memory   a real kerb hydrant from the chunk's record is knocked off; the
#           chunk is laid afresh (as when you leave and come back) and the
#           hydrant is still off, with its stump and its water. The next
#           night it is whole again with a cone beside it.
#  hissers  about one hydrant in four, by its place.
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --path . -s res://tests/world/hydrant_break.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const Props := preload("res://scripts/world/roadside_props.gd")
const PropBreak := preload("res://scripts/world/prop_break.gd")
const Water := preload("res://scripts/world/hydrant_water.gd")
const WetGrip := preload("res://scripts/car/wet_grip.gd")
const Weather := preload("res://scripts/world/weather.gd")
const Puddles := preload("res://scripts/world/puddles.gd")
const Districts := preload("res://scripts/world/districts.gd")

const RATE := 120
const LANE := 1

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var breaker: Node3D
var water: Node3D
var fails: Array[String] = []
var half := Vector3.ZERO
var phase := "boot"
var t := 0
var hold_brake := false
var throttle := 0.0

var v_hist := PackedFloat32Array([0.0, 0.0, 0.0])
var yaw_before := 0.0
var yaw0 := 0.0
var swing := 0.0
var hits0 := 0
var dmg0 := 0
var hyd_s := 0.0          # the lane hydrant: along the road, across it
var hyd_x := 0.0
var drag0 := 0
var v_in := 0.0
var tracks0 := 0
var tracks_at_100 := -1
var patch_s0 := 0.0
var base_y := 0.0
var base_n := 0
var peak_y := -INF
var dirt0 := 0.0
var dirt_steps0 := 0
var dry_t0 := 0.0
var saw_trickle := false
var mem_chunk := -1
var mem_index := -1
var cost_sum := 0.0
var cost_n := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _initialize() -> void:
	OS.add_logger(logger)
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_POLICE", "0")
	Districts.force = "downtown"   # hydrants on most chunks
	Engine.physics_ticks_per_second = RATE
	_hissers()
	game = Harness.boot(self, 0, 300.0, 4242, 1e7)

func _hissers() -> void:
	var n := 0
	for k in 400:
		if posmod(hash("%d:3:1:%d" % [k, -k * 37]), Water.HISSER_IN) == 0:
			n += 1
	print("hissers: %d of 400 places" % n)
	if n < 60 or n > 140:
		_fail("hissers: %d of 400, want about one in four" % n)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 1.0 if hold_brake else 0.0
	c.handbrake_input = 1.0 if hold_brake else 0.0
	c.steering_input = 0.0

func _yaw() -> float:
	var f := RoadFrame.dir_to_road(RoadFrame.unroll(p.global_position).z, -p.global_transform.basis.z)
	return atan2(-f.x, -f.z)

func _s() -> float:
	return RoadFrame.s_at(RoadFrame.unroll(p.global_position).z)

func _place(speed_kmh: float, x: float, ahead := 0.0) -> void:
	p.damage.garage_repair(null)
	TestDriver.place(p, x, ahead, 0.0, speed_kmh / 3.6)
	p.damage.forget_motion()

## Stands a hydrant in the lane `ahead` metres on, at x, and makes it a gusher.
func _stand(x: float, ahead: float) -> Array:
	var ref: Array = breaker.add_test_prop(Props.HYDRANT, x, p.global_position, ahead)
	if ref.is_empty():
		_fail("%s: no chunk to stand the hydrant on" % phase)
	return ref

func _gusher() -> void:
	if not water.wet.is_empty():
		water.wet[water.wet.size() - 1].hisser = false

func _root_of(chunk: int) -> Node3D:
	for e in game.get("chunk_pool"):
		if int(e.index) == chunk:
			return e.root
	return null

func _go(next: String) -> void:
	phase = next
	t = 0

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		breaker = game.get("breaker")
		if breaker == null or breaker.get("water") == null:
			_fail("the game has no breaker with water")
			return _end()
		water = breaker.water
		half = breaker._half_of(p)
		p.driver = _drive
		_start_hit()
		return false
	t += 1
	v_hist[0] = v_hist[1]
	v_hist[1] = v_hist[2]
	v_hist[2] = p.linear_velocity.length() * 3.6
	cost_sum += breaker.cost_usec
	cost_n += 1
	var bad := TestDriver.sanity(p)
	if bad != "":
		_fail("car state in %s: %s" % [phase, bad])
		return _end()
	match phase:
		"hit":
			if breaker.hits > hits0:
				var loss := (v_hist[1] - v_hist[2]) - (v_hist[0] - v_hist[1])
				print("hit: %.1f km/h in, %.2f km/h lost" % [v_hist[1], loss])
				if loss < 8.0 or loss > 12.0:
					_fail("hit: lost %.2f km/h, want 8-12" % loss)
				if p.damage.hits - dmg0 != 1:
					_fail("hit: the car took %d damage hits, want 1" % (p.damage.hits - dmg0))
				if water.spraying() != 1:
					_fail("hit: %d hydrants spraying, want 1" % water.spraying())
				_gusher()
				yaw0 = yaw_before
				swing = 0.0
				_go("hit_after")
			elif t > RATE * 5:
				_fail("hit: the car never reached the hydrant")
				return _end()
			yaw_before = _yaw()
		"hit_after":
			var d := rad_to_deg(wrapf(_yaw() - yaw0, -PI, PI))
			if absf(d) > absf(swing):
				swing = d
			if t >= int(RATE * 1.5):
				print("hit: nose swung %+.2f deg (right corner, so negative)" % swing)
				if swing > -1.0 or swing < -3.0:
					_fail("hit: nose swung %.2f deg, want 1-3 toward the hydrant" % swing)
				_start_column()
		"column":
			if water.drag_passes > drag0 and v_in == 0.0:
				v_in = v_hist[1]
				var loss := (v_hist[1] - v_hist[2]) - (v_hist[0] - v_hist[1])
				print("column: %.2f km/h of drag, sheet %.2f" % [loss, water.sheet])
				if loss < 1.0 or loss > 2.0:
					_fail("column: %.2f km/h of drag, want 1-2" % loss)
				if water.sheet < 0.99:
					_fail("column: the water sheet is not up")
				var wipers := p.get_node_or_null(^"CarWipers")
				if wipers != null and float(wipers.get("burst")) <= 0.0:
					_fail("column: the wipers were not sent fast")
			if t > RATE * 4:
				if v_in == 0.0:
					_fail("column: the car never met the jet")
				_go("grow")
		"grow":
			# let the patch run its full length (GROW_SECS from the hit)
			if float(water.wet[0].age) > Water.GROW_SECS + 1.0:
				_start_patch()
		"patch":
			var u := RoadFrame.unroll(p.global_position)
			var on: bool = water.on_patch(water.wet[0], u.x, RoadFrame.s_at(u.z))
			if t == RATE:
				var want: float = WetGrip.wheel_target(Weather.rain_grip(), 1.0, Puddles.Depth.SHALLOW, 10.0)
				print("patch: on it %s, grip %s, want %.3f" % [str(on), str(p.wet.mult), want])
				if not on:
					_fail("patch: the car is not on the patch 1 s in")
				for i in 4:
					if absf(p.wet.mult[i] - want) > 0.006:
						_fail("patch: wheel %d grip %.3f, want %.3f" % [i, p.wet.mult[i], want])
						break
			# off the far end, then the 100 m of tracks, then a little more
			if t > RATE * 25 or _s() - patch_s0 > Water.GROW_M + Water.TRACK_M + 40.0:
				throttle = 0.0
				var laid: int = water.tracks_laid - tracks0
				print("tracks: %d laid after the patch, grip back to %s" % [laid, str(p.wet.mult)])
				if laid < 20:
					_fail("tracks: only %d laid" % laid)
				if laid > 2 * int(Water.TRACK_M / Water.TRACK_STEP) + 8:
					_fail("tracks: %d laid, more than 100 m of them" % laid)
				if absf(p.wet.mult[0] - maxf(Weather.rain_grip(), WetGrip.MIN_GRIP)) > 0.006:
					_fail("patch: grip %.3f off the patch, want the weather's" % p.wet.mult[0])
				_start_lift()
		"lift_base":
			if t > RATE:
				base_y += p.global_position.y
				base_n += 1
			if t >= int(RATE * 1.5):
				base_y /= float(base_n)
				water.lift_enabled = true
				dirt_steps0 = water.dirt_steps
				_go("lift")
		"lift":
			peak_y = maxf(peak_y, p.global_position.y)
			if t >= RATE * 3:
				var rise := peak_y - base_y
				print("lift: the car rose %.1f mm on the jet (%d ticks of push), upright %.3f" % [rise * 1000.0, water.lift_ticks, p.global_transform.basis.y.y])
				if water.lift_ticks == 0:
					_fail("lift: the jet never pushed the wheel")
				if rise < 0.002 or rise > 0.06:
					_fail("lift: rose %.1f mm, want 2-60" % (rise * 1000.0))
				if p.global_transform.basis.y.y < 0.98:
					_fail("lift: the car is tipping")
				if water.dirt_steps != dirt_steps0 + 1:
					_fail("lift: %d dirt steps after 3 s in the water, want 1" % (water.dirt_steps - dirt_steps0))
				var fx = game.get("fx")
				if fx != null and fx.get("dirt") != null and absf(float(fx.dirt.level) - (dirt0 - Water.DIRT_STEP)) > 0.02:
					_fail("lift: dirt %.2f, want %.2f" % [fx.dirt.level, dirt0 - Water.DIRT_STEP])
				hold_brake = false
				_start_cap()
		"cap":
			if t == 2:
				var spraying: int = water.spraying()
				print("cap: %d entries, %d spraying, the first %s" % [water.wet.size(), spraying, "sprays" if water.wet[0].spraying else "is a patch"])
				if spraying != Water.MAX_SPRAYS:
					_fail("cap: %d spraying, want %d" % [spraying, Water.MAX_SPRAYS])
				if water.wet.size() != 3 or water.wet[0].spraying:
					_fail("cap: the oldest did not fall back to a patch")
				dry_t0 = water.now()
				_go("dry")
		"dry":
			# a game minute every 6 ticks
			if t % 6 == 0:
				game.get("night_clock").add_minutes(1.0)
			var e: Dictionary = water.wet[water.wet.size() - 1]
			if e.spraying and float(e.power) < 0.9 and water.now() - float(e.start) > 14.0:
				saw_trickle = true
			if not e.spraying:
				var mins: float = water.now() - float(e.start)
				print("dry: the jet stopped %.1f game minutes after the hit" % mins)
				if mins < 15.0 or mins > 25.5:
					_fail("dry: stopped after %.1f game minutes, want 15-25" % mins)
				if not saw_trickle:
					_fail("dry: the jet never sank to a trickle first")
				_go("dry_patch")
			elif t > RATE * 30:
				_fail("dry: the jet never stopped")
				return _end()
		"dry_patch":
			if t % 6 == 0:
				game.get("night_clock").add_minutes(1.0)
			if water.wet.is_empty():
				print("dry: every patch gone %.1f game minutes after the third hydrant burst" % (water.now() - dry_t0))
				_start_memory()
			elif t > RATE * 30:
				_fail("dry: %d patches never dried" % water.wet.size())
				return _end()
		"memory":
			if breaker.is_broken(mem_chunk, Props.of(_root_of(mem_chunk)), mem_index):
				_judge_memory()
				return _end()
			elif t > RATE * 4:
				_fail("memory: the real hydrant was never hit")
				return _end()
	return false

# ---------- phases ----------

func _start_hit() -> void:
	hyd_x = Harness.lane_x(LANE)
	_place(50.0, hyd_x - 0.8 * half.x)   # the right corner meets it
	var ref := _stand(hyd_x, 50.0 / 3.6 * 0.8 + 6.0)
	if ref.is_empty():
		return
	hyd_s = _s() + 50.0 / 3.6 * 0.8 + 6.0
	hits0 = breaker.hits
	dmg0 = p.damage.hits
	_go("hit")

func _start_column() -> void:
	# back before the standing jet, in line with it
	_place(60.0, hyd_x, -(_s() - hyd_s) - 14.0)
	drag0 = water.drag_passes
	v_in = 0.0
	_go("column")

func _start_patch() -> void:
	# onto the patch just past the hydrant, on the road side of it
	_place(36.0, hyd_x - 1.2, -(_s() - hyd_s) + 4.0)
	throttle = 0.3
	patch_s0 = hyd_s
	tracks0 = water.tracks_laid
	tracks_at_100 = -1
	_go("patch")

func _start_lift() -> void:
	# parked with the front-left wheel on the jet's base
	var w: Node3D = p.wheel_array[0]
	var off := w.position
	hold_brake = true
	_place(0.0, hyd_x - off.x, -(_s() - hyd_s) + off.z)
	water.lift_enabled = false
	_gusher()
	var fx = game.get("fx")
	if fx != null and fx.get("dirt") != null:
		fx.dirt.set_level(0.8)
		dirt0 = float(fx.dirt.level)
	base_y = 0.0
	base_n = 0
	peak_y = -INF
	_go("lift_base")

func _start_cap() -> void:
	water.new_night()   # the lane hydrant's water goes; three fresh ones
	var here := p.global_position
	for k in 3:
		var ref := _stand(Harness.lane_x(LANE) + 6.0, 30.0 + float(k) * 12.0)
		if ref.is_empty():
			continue
		var root := _root_of(int(ref[0]))
		var rec: Dictionary = Props.of(root)
		water.burst("cap%d" % k, int(ref[0]), rec.pos[int(ref[1])], rec.road[int(ref[1])], true, breaker._roots)
		water.wet[water.wet.size() - 1].start = water.now() + float(k) * 0.01   # oldest first
	_place(0.0, Harness.lane_x(LANE))
	_go("cap")

func _start_memory() -> void:
	# a real kerb hydrant on the own side, from the chunks ahead
	var s := _s()
	var here := floori(s / Props.CHUNK_LEN)
	for c in [here + 1, here + 2, here + 3, here + 4]:
		var root := _root_of(c)
		if root == null or root.get_meta("rebuilding", false):
			continue
		var rec: Dictionary = Props.of(root)
		for i in rec.kind.size():
			if rec.kind[i] == Props.HYDRANT and rec.side[i] == 1 and rec.slot[i] >= 0 and mem_chunk < 0:
				mem_chunk = c
				mem_index = i
	if mem_chunk < 0:
		_fail("memory: no real hydrant in the four chunks ahead")
		_end()
		return
	var rec: Dictionary = Props.of(_root_of(mem_chunk))
	var hx: float = rec.road[mem_index].x
	var hs: float = float(mem_chunk) * Props.CHUNK_LEN - rec.road[mem_index].y
	# dropped onto the pavement just short of it, rolling
	var u := RoadFrame.unroll(p.global_position)
	p.damage.garage_repair(null)
	TestDriver.place(p, hx, (hs - s) - half.z - 2.0, 0.0, 30.0 / 3.6, u.y + 0.2)
	p.damage.forget_motion()
	hits0 = breaker.hits
	_go("memory")

func _judge_memory() -> void:
	var root := _root_of(mem_chunk)
	var rec: Dictionary = Props.of(root)
	var index := mem_index
	# the chunk is laid afresh, as when the car leaves and comes back
	RoadChunkBuilder.rebuild_chunk(root, mem_chunk, game._section_at(mem_chunk - 1), game._section_at(mem_chunk), game.origin_index)
	breaker.dress_chunk(root, mem_chunk)
	rec = Props.of(root)
	var gone: PackedByteArray = root.get_meta("props_gone")
	var stumps := root.get_node_or_null(^"Stumps") as MultiMeshInstance3D
	var spray_here := 0
	for ch in root.get_children():
		if ch.has_node(^"Card") and ch.visible:
			spray_here += 1
	print("memory: after the chunk is laid afresh: gone %d, stumps %d, water entries %d, spray nodes on the chunk %d" % [
		gone[index], stumps.multimesh.visible_instance_count if stumps != null else 0, water.wet.size(), spray_here])
	if gone[index] != 1:
		_fail("memory: the hydrant is back after the chunk was laid afresh")
	if stumps == null or stumps.multimesh.visible_instance_count < 1:
		_fail("memory: no stump after the chunk was laid afresh")
	if water.spraying() != 1 or spray_here != 1:
		_fail("memory: the water did not come back with the chunk")
	# the next night: whole again, a cone beside it
	breaker.new_night()
	rec = Props.of(root)
	gone = root.get_meta("props_gone")
	var cones := root.get_node_or_null(^"RepairCones") as MultiMeshInstance3D
	var cone_recs := 0
	for i in rec.kind.size():
		if rec.kind[i] == Props.CONE and rec.slot[i] >= PropBreak.REPAIR_SLOT:
			cone_recs += 1
	print("memory: the next night: broken %d, gone %d, repair cones %d (%d in the record), water entries %d" % [
		breaker.broken.size(), gone[index], cones.multimesh.visible_instance_count if cones != null else 0, cone_recs, water.wet.size()])
	if not breaker.broken.is_empty() or gone[index] != 0:
		_fail("memory: the hydrant is still broken the next night")
	# one per thing mended on this chunk (the car may have felled a lamp on its way in)
	if cones == null or cone_recs < 1 or cones.multimesh.visible_instance_count != cone_recs:
		_fail("memory: no repair cone beside it the next night")
	if not water.wet.is_empty():
		_fail("memory: water left over the next night")

func _end() -> bool:
	if cost_n > 0:
		print("breaker tick over the whole test: mean %.1f us (ceiling %.0f)" % [cost_sum / float(cost_n), PropBreak.CEILING_USEC])
		if cost_sum / float(cost_n) > PropBreak.CEILING_USEC:
			_fail("the breaker's mean tick is over the ceiling")
	if not logger.errors.is_empty():
		_fail("%d script errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	print("hydrant_break: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
