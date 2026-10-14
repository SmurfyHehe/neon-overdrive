extends SceneTree

# The totalled look, step 2 (Roy 1560 and 1561, 2026-10-14): parts that hang,
# fall off and leak, scripts/car/wreck_parts.gd on the coupe (built from
# parts). Boots Game.tscn, headless and silent, scripted driver.
# - stage 0: the body holds the bumper and the hood, no loose nodes
# - meter 0.60 with a right-side hit: the merged body loses the bumper and
#   the hood (fewer triangles), a LooseBumper and a BuckledHood hang on the
#   body, the bumper's right end lower than its left, the hood's front edge up;
#   two draw calls more than stage 0
# - meter 0.95 at speed: the LooseBumper is gone, a DroppedBumper lies in
#   the world behind the car and is gone after DROP_LIFE seconds; the puddle
#   does not show while moving
# - standing still at 0.95: the puddle decal shows and spreads; driving off
#   shrinks it away
# - garage repair: the body is back to its stage 0 triangles, no loose nodes
# - a station patch from 0.95 to 0.60 keeps the bumper gone (no new one)
# - the FxPack owns the node and shift_world moves a dropped bumper
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --audio-driver Dummy --path . -s res://tests/car/wreck_parts.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const WreckParts := preload("res://scripts/car/wreck_parts.gd")

enum Step { BOOT, HANG, DROP, GONE, STILL, MOVE, REPAIR, PATCH, DONE }

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

var logger := ErrorCounter.new()
var game: Node
var step := Step.BOOT
var t := 0
var tick := 0
var hz := 120
var failures: Array[String] = []
var rest := Transform3D()
var tris0 := 0
var visuals0 := 0
var spread_still := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.add_logger(logger)
	game = Harness.boot(self, 0, 300.0, 4242)

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _wreck() -> Node3D:
	var fx: Variant = game.get("fx")
	return fx.wreck if fx != null else null

func _body(p: PlayerCar) -> MeshInstance3D:
	return CarAssembler.body_of(p.chassis_visual)

func _tris(p: PlayerCar) -> int:
	var b := _body(p)
	var n := 0
	for i in b.mesh.get_surface_count():
		n += (b.mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n

func _visuals(n: Node) -> int:
	var c := 1 if n is VisualInstance3D and (n as VisualInstance3D).visible else 0
	for ch in n.get_children():
		c += _visuals(ch)
	return c

func _hold(throttle: float, brake: float) -> Callable:
	return func(c: Vehicle) -> void:
		c.steering_input = 0.0
		c.throttle_input = throttle
		c.brake_input = brake
		c.handbrake_input = 0.0

func _launch(p: PlayerCar, speed: float) -> void:
	p.global_transform = rest
	p.angular_velocity = Vector3.ZERO
	Harness.move_player_to_lane(p, Harness.lane_x(1))
	Harness.launch_player(p, speed)
	t = 0

func _set_meter(p: PlayerCar, m: float) -> void:
	p.damage.totalled = m
	p.damage.parts[CarDamage.Part.STEER_FR] = 0.5   # the hit was on the right
	p.damage.rebuild_offsets()

func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	hz = Engine.physics_ticks_per_second
	if tick > hz * 240:
		return _end("timed out in %s" % Step.keys()[step])
	var p: PlayerCar = game.get("player") if game != null else null
	if p == null:
		return tick > hz * 10 and _end("Game never became ready")
	if not Harness.finite(p):
		return _end("non-finite car state in %s" % Step.keys()[step])
	var w := _wreck()
	match step:
		Step.BOOT:
			if t >= hz:
				rest = p.global_transform
				print("car: %s" % PlayerCar.chassis_kind())
				if w == null:
					return _end("the FxPack has no WreckParts node")
				if _body(p) == null or not w.has_parts():
					print("not a parts car: nothing to hang (skipped)")
					return _end("")
				tris0 = _tris(p)
				visuals0 = _visuals(p)
				print("stage 0: %d triangles, %d visuals on the car" % [tris0, visuals0])
				_check(w.loose_bumper == null and w.hood == null and w.dropped == null, "stage 0: no loose nodes")
				_set_meter(p, 0.60)
				step = Step.HANG
				t = 0
		Step.HANG:
			if t >= 3:
				var tris := _tris(p)
				print("stage 2: %d triangles, %d visuals" % [tris, _visuals(p)])
				_check(w.shown == 2, "the parts show stage 2 (%d)" % w.shown)
				_check(tris < tris0, "the bumper and hood left the merged body (%d < %d)" % [tris, tris0])
				_check(w.loose_bumper != null and w.hood != null, "a LooseBumper and a BuckledHood hang on the body")
				_check(_visuals(p) == visuals0 + 2, "stage 2 is two draw calls more (%d vs %d)" % [_visuals(p), visuals0])
				if w.loose_bumper != null:
					var lb: MeshInstance3D = w.loose_bumper
					var box := CarAssembler.part_aabb(_body(p).get_meta("car_id"), "bumper_f")
					# the right end (+x) is lower than the left after the hang
					var pivot: Vector3 = lb.position
					var right := lb.to_global(Vector3(box.end.x, box.position.y, box.get_center().z) - pivot).y
					var left := lb.to_global(Vector3(box.position.x, box.position.y, box.get_center().z) - pivot).y
					print("loose bumper bottom: left %.3f right %.3f (world y)" % [left, right])
					_check(right < left - 0.05, "the bumper's right end hangs lower (the hit side)")
					_check(lb.get_parent() == _body(p), "the loose bumper rides on the body")
				if w.hood != null:
					var h: MeshInstance3D = w.hood
					var hb := CarAssembler.part_aabb(_body(p).get_meta("car_id"), "hood")
					var hinge: Vector3 = h.position
					var front := h.to_global(Vector3(0.0, hb.end.y, hb.position.z) - hinge).y
					var back := h.to_global(Vector3(0.0, hb.end.y, hb.end.z) - hinge).y
					print("buckled hood: front %.3f back %.3f (world y)" % [front, back])
					_check(front > back + 0.03, "the hood's front edge is up")
				_set_meter(p, 0.95)
				_launch(p, 20.0)
				p.driver = _hold(0.3, 0.0)
				step = Step.DROP
		Step.DROP:
			if t >= hz * 1:
				print("stage 3: drops %d, %d visuals on the car" % [w.drops, _visuals(p)])
				_check(w.shown == 3 and w.loose_bumper == null, "stage 3: the loose bumper let go")
				_check(w.drops == 1 and w.dropped != null, "a DroppedBumper exists")
				_check(_visuals(p) == visuals0 + 1, "stage 3 is one draw call more on the car (%d vs %d)" % [_visuals(p), visuals0])
				if w.dropped != null:
					var d: RigidBody3D = w.dropped
					_check(d.get_parent() == w, "the dropped bumper lives in the world under WreckParts")
					var behind := (d.global_position - p.global_position).dot(-p.global_transform.basis.z) < 0.0
					print("dropped bumper %.1f m from the car, y %.2f (the car's rest y %.2f)" % [d.global_position.distance_to(p.global_position), d.global_position.y, rest.origin.y])
					_check(behind, "it lies behind the car")
					# its origin is the top edge of one end, so lying on its side it sits under a metre up
					_check(d.global_position.y < rest.origin.y + 1.0 and d.global_position.y > rest.origin.y - 2.0, "it came down to the road, not through it")
					# the floating origin moves it with the world
					var before := d.global_position
					var fx: Variant = game.get("fx")
					fx.shift_world(Vector3(0.0, 0.0, 5.0))
					_check(d.global_position.is_equal_approx(before + Vector3(0.0, 0.0, 5.0)), "shift_world moves the dropped bumper")
					fx.shift_world(Vector3(0.0, 0.0, -5.0))
				_check(w.puddle == null or not w.puddle.visible, "no puddle on the move")
				step = Step.GONE
				t = 0
		Step.GONE:
			if t == hz * 5 and w.dropped != null:
				# settled by now: lying on the road, not sunk in it, not standing in the air
				var road := p.global_position.y - 0.45
				for i in 2:
					var wh: Wheel = p.wheel_array[i]
					if wh.is_colliding():
						road = wh.last_collision_point.y
				var y: float = w.dropped.global_position.y
				print("dropped bumper after 6 s: y %.2f, road y %.2f, speed %.2f m/s" % [y, road, w.dropped.linear_velocity.length()])
				_check(y > road - 0.05 and y < road + 0.6, "it rests on the road (%.2f over it)" % (y - road))
				_check(w.dropped.linear_velocity.length() < 0.5, "and has stopped")
			if t >= int((WreckParts.DROP_LIFE + 0.5) * hz):
				_check(w.dropped == null, "the dropped bumper is gone after DROP_LIFE")
				p.driver = _hold(0.0, 1.0)
				step = Step.STILL
				t = 0
		Step.STILL:
			if t >= int((WreckParts.PUDDLE_GROW_S + 5.0) * hz):
				print("standing %.0f s at stage 3: speed %.2f m/s, puddle spread %.2f, visible %s" % [WreckParts.PUDDLE_GROW_S + 5.0, p.speed, w.puddle_spread, str(w.puddle != null and w.puddle.visible)])
				_check(p.speed < WreckParts.PUDDLE_STILL_MS, "the car stopped (%.2f m/s)" % p.speed)
				_check(w.puddle != null and w.puddle.visible and w.puddle_spread >= 0.99, "the puddle has spread under the nose")
				if w.puddle != null:
					_check(w.puddle.size.x >= WreckParts.PUDDLE_SIZE * 0.99 and w.puddle.cull_mask == 1, "the puddle is full size and paints the road only")
				spread_still = w.puddle_spread
				_launch(p, 15.0)
				p.driver = _hold(0.3, 0.0)
				step = Step.MOVE
		Step.MOVE:
			if t >= hz * 3:
				print("3 s on the move: puddle spread %.2f" % w.puddle_spread)
				_check(w.puddle_spread <= 0.0 and (w.puddle == null or not w.puddle.visible), "driving off, the puddle is gone")
				p.damage.garage_repair(null)
				step = Step.REPAIR
				t = 0
		Step.REPAIR:
			if t >= 3:
				print("after the repair: %d triangles, %d visuals" % [_tris(p), _visuals(p)])
				_check(w.shown == 0 and w.loose_bumper == null and w.hood == null, "the repair takes every loose part away")
				_check(_tris(p) == tris0, "the body is back to its stage 0 triangles (%d vs %d)" % [_tris(p), tris0])
				_check(_visuals(p) == visuals0, "and its stage 0 draw calls")
				_set_meter(p, 0.95)
				step = Step.PATCH
				t = 0
		Step.PATCH:
			if t == 3:
				_check(w.shown == 3 and w.drops == 2 and w.loose_bumper == null, "stage 3 again: the new bumper fell off (drops %d)" % w.drops)
				p.damage.station_patch(7)
			elif t >= 6:
				_check(w.shown == 2 and w.loose_bumper == null and w.hood != null, "a station patch to stage 2 keeps the bumper gone and the hood buckled")
				p.damage.garage_repair(null)
				step = Step.DONE
				t = 0
		Step.DONE:
			if t >= 3:
				_check(logger.errors.is_empty(), "no errors logged (%s)" % ", ".join(logger.errors.slice(0, 3)))
				return _end("")
	return false

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
		print("  FAIL: " + why)
	print("wreck_parts: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
