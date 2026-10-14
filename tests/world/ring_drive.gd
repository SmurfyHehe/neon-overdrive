extends SceneTree

# The player on the ramps and the ring (ring sites R3), with traffic running.
#
# On the curved, hilly loop, at exit 2's ring:
# 1. A bot leaves the +1 carriageway, drives up, goes round the ring two and a
#    half times and comes down onto the -1 carriageway, heading back the way
#    it came. All the while it is "off the main road" (game.off_main), never
#    going the wrong way; traffic's flow does not turn while it is up there
#    and turns exactly once when it rejoins (flow_flips +1). The save taken on
#    the ring names the ring and the angle. The chunks beside the site stay
#    built while the car is on the ring.
# 2. Put-back: a car last seen on the ring is put back on the ring's lane,
#    facing anticlockwise, standing still.
# 3. Clockwise round the ring is the wrong way (off_main.wrong_way), as
#    driving against the flow is on the highway; the flow still does not turn.
# 4. Saved on the ring, then loaded: the car is on the ring where it was.
#    Stopped there, it leans in with the ring's 4 % (RoadRamps.BANK).
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/world/ring_drive.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")

const L := 50.0
const SITE := 1             # index into RoadMap.rings(): exit 2
const LANE_X := 11.6
const SLIP_X := RoadRamps.X_LANE + RoadRamps.HALF
const RAMP_SPEED := 13.0
const RING_SPEED := 10.0

var game: Node
var ticks := 0
var phase := 0
var phase_ticks := 0
## A car at rest on the ring leans in this much (sine of its tilt toward the
## centre against the road): the deck's 4 % is 0.040; flat would read 0.
const LEAN_LO := 0.03
const LEAN_HI := 0.05
var fails: Array[String] = []
var checks := 0
var path: Array[Vector3] = []   # (x across, w metres past the ring's centre the way the chunks count, speed)
var path_i := 0
var site_s := 0.0
var flips0 := 0
var off_missing := 0
var wrong_ticks := 0
var held_flips := 0
var saved_on_ring := false
var pool_holes := 0
var cw_ticks := 0
var cw_wrong := 0
var saved_place := {}
var saved_u := Vector3.ZERO

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		_fail(msg)

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_ROAD_SEED", "4242")
	SaveStore.root = "user://test_ring_drive"
	SaveStore.slot = 0
	SaveStore.chase_active = false
	SaveDirector.enabled = true
	SaveStore.select_slot(1)
	SaveStore.clear_run()
	SaveStore.load_meta()
	game = Harness.boot(self, 6, 150.0, 7)

func _reboot() -> void:
	root.remove_child(game)
	game.free()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(game)
	ticks = 0

func _z_of(w: float) -> float:
	return float(RoadFrame.origin_index) * L - (site_s + w)

## Up from the +1 carriageway, two and a half times round, down onto the -1 one.
func _line_round() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var w := -260.0
	while w < -RoadRamps.V_GORE - 1.0:
		out.append(Vector3(lerpf(LANE_X, SLIP_X, smoothstep(-250.0, -205.0, w)), w, RAMP_SPEED))
		w += 2.0
	w = -RoadRamps.V_GORE
	while w < 0.0:
		out.append(Vector3(RoadRamps.x_at(-w), w, RING_SPEED if w > -40.0 else RAMP_SPEED))
		w += 2.0
	for i in range(0, 240):
		var a := TAU * float(i) / 96.0
		out.append(Vector3(RoadRamps.X_TOP * cos(a), RoadRamps.X_TOP * sin(a), RING_SPEED))
	var v := 0.0
	while v <= RoadRamps.V_GORE:
		out.append(Vector3(-RoadRamps.x_at(v), -v, RING_SPEED if v < 30.0 else RAMP_SPEED))
		v += 2.0
	while v < 330.0:
		out.append(Vector3(-lerpf(SLIP_X, LANE_X, smoothstep(205.0, 250.0, v)), -v, RAMP_SPEED))
		v += 2.0
	return out

## A third of the way round the ring the wrong way, from 200 degrees.
func _line_clockwise() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in range(0, 40):
		var a := deg_to_rad(200.0 - 3.0 * float(i))
		out.append(Vector3(RoadRamps.X_TOP * cos(a), RoadRamps.X_TOP * sin(a), RING_SPEED))
	return out

func _stand(p: PlayerCar, t: Transform3D) -> void:
	game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", RoadFrame.unroll(p.global_position).z)
	game.call("flush_rebuilds")

func _drive(p: PlayerCar) -> void:
	p.driver = func(c: Vehicle) -> void:
		if path.is_empty() or path_i >= path.size() - 1:
			c.throttle_input = 0.0
			c.brake_input = 1.0
			return
		var u := RoadFrame.unroll(c.global_position)
		var best := INF
		for i in range(path_i, mini(path_i + 12, path.size())):
			var d := Vector2(path[i].x - u.x, _z_of(path[i].y) - u.z).length()
			if d < best:
				best = d
				path_i = i
		var speed := c.linear_velocity.length()
		var look := clampf(speed * 0.6, 4.0, 9.0)
		var j := path_i
		var run := 0.0
		while j < path.size() - 1 and run < look:
			run += Vector2(path[j + 1].x - path[j].x, path[j + 1].y - path[j].y).length()
			j += 1
		var target := RoadFrame.roll(Vector3(path[j].x, 0.0, _z_of(path[j].y)))
		var fwd := -c.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP)
		var to := target - c.global_position
		var alpha := atan2(to.dot(right), to.dot(fwd))
		var dist := maxf(Vector2(to.dot(right), to.dot(fwd)).length(), 0.5)
		var want := clampf(atan(2.6 * 2.0 * sin(alpha) / dist) / c.max_steering_angle, -1.0, 1.0)
		c.steering_input = -signf(want) * pow(absf(want), 1.0 / maxf(c.steering_exponent, 0.1))
		var goal := path[path_i].z
		c.throttle_input = clampf((goal - speed) * 0.5, 0.0, 1.0)
		c.brake_input = clampf((speed - goal - 1.0) * 0.4, 0.0, 1.0)
		if c.current_gear < 1:
			c.current_gear = 1

func _next(to_phase: int) -> void:
	phase = to_phase
	phase_ticks = 0

func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	ticks += 1
	phase_ticks += 1
	if ticks < 3:
		return false
	var p: PlayerCar = game.get("player")
	var tr: TrafficManager = game.get("traffic")
	var hz := Engine.physics_ticks_per_second
	var u := RoadFrame.unroll(p.global_position)
	var w := RoadFrame.s_at(u.z) - site_s
	var place: Dictionary = game.off_main
	if phase_ticks > hz * 240:
		_fail("timed out in phase %d, %.0f m from the ring's centre" % [phase, w])
		_finish()
		return true
	match phase:
		0:
			_check(RoadMap.is_loop() and tr != null, "no loop or no traffic")
			site_s = float(RoadMap.rings()[SITE].s)
			path = _line_round()
			path_i = 0
			_stand(p, RoadFrame.pose(path[0].x, 0.45, _z_of(path[0].y), 0.0))
			_drive(p)
			flips0 = tr.flow_flips
			_check(tr.flow == -1.0, "traffic starts flowing %.0f" % tr.flow)
			_next(1)
		1:
			if phase_ticks < 30:
				return false
			# from the nose to the nose the car is off the main road
			if absf(w) < RoadRamps.V_NOSE - 8.0:
				if place.is_empty():
					off_missing += 1
					if off_missing <= 3:
						_fail("not off the main road %.0f m from the centre (%.1f m out, %.1f m up)" % [w, u.x, u.y])
				else:
					if bool(place.wrong_way):
						wrong_ticks += 1
					if tr.flow_flips != flips0:
						held_flips += 1
					if String(place.part) == "ring":
						var rc := floori(site_s / L)
						for k in range(-RoadMap.RAMP_CHUNKS, RoadMap.RAMP_CHUNKS):
							var have := false
							for c in game.chunk_pool:
								if c.index == rc + k:
									have = true
							if not have:
								pool_holes += 1
			# on the second lap, over the far bridge: what the save would hold
			if not saved_on_ring and path_i > 150 and not place.is_empty() and String(place.part) == "ring":
				saved_on_ring = true
				var run: Dictionary = game.saver.capture()
				var off: Dictionary = run.road.get("off", {})
				_check(off.get("part") == "ring" and off.get("id") == String(RoadMap.rings()[SITE].id), "the save taken on the ring says %s" % [off])
				_check(absf(float(off.get("angle", -9.0)) - float(place.angle)) < 0.01, "the save's ring angle is %s, the car is at %.2f" % [off.get("angle"), place.angle])
				_check(absf(float(run.road.s) - RoadMap.wrap_s(RoadFrame.s_at(u.z))) < 0.5 and int(run.road.id) == 0, "the save's road id and s are %s, %s" % [run.road.id, run.road.s])
				var parsed: Variant = JSON.parse_string(JSON.stringify(run))
				_check(parsed is Dictionary and (parsed as Dictionary).road.off.part == "ring", "the ring place does not survive the save's JSON")
			if path_i >= path.size() - 3:
				_check(off_missing == 0, "off the main road was not set on %d ticks" % off_missing)
				_check(wrong_ticks == 0, "anticlockwise round the ring read as the wrong way on %d ticks" % wrong_ticks)
				_check(held_flips == 0, "the flow turned while the car was off the main road (%d ticks)" % held_flips)
				_check(saved_on_ring, "the bot never got to the save point on the ring")
				_check(pool_holes == 0, "a chunk beside the site was missing on %d checks while on the ring" % pool_holes)
				_check(place.is_empty(), "still off the main road after rejoining: %s" % [place])
				_check(u.x < -0.4 and RoadMap.where(u.z, -p.global_transform.basis.z).dir == -1, "rejoined %.1f m out heading %d, expected the -1 carriageway" % [u.x, RoadMap.where(u.z, -p.global_transform.basis.z).dir])
				_next(2)
		2:
			# a few bookkeeping ticks for traffic to see the rejoin
			if phase_ticks < 20:
				return false
			_check(tr.flow_flips == flips0 + 1 and tr.flow == 1.0, "round twice and back down the other side: %d flow flips (expected 1), flow %.0f" % [tr.flow_flips - flips0, tr.flow])
			print("ring_drive: round 2.5 times and down the other side: %d flow flip, 0 wrong-way ticks" % (tr.flow_flips - flips0))
			# put-back: stand on the ring facing the wrong way, let the rescue see it, then ask
			path = []
			var on_ring := {"site": SITE, "id": "x2", "s": site_s, "part": "ring", "side": 1, "leg": 1, "v": 0.0, "angle": deg_to_rad(200.0), "wrong_way": false}
			var t := RoadRamps.pose_of(on_ring)
			t.basis = t.basis.rotated(Vector3.UP, PI)
			_stand(p, t)
			_next(3)
		3:
			if phase_ticks < 60:
				return false
			if phase_ticks == 60:
				_check(not place.is_empty() and String(place.part) == "ring", "a car stood on the ring is at %s" % [place])
				game.rescue.call("_put_back")
				return false
			if phase_ticks < 90:
				return false
			var r := Vector2(u.x, w).length()
			var fwd := RoadFrame.dir_to_road(u.z, -p.global_transform.basis.z)
			var a := atan2(w, u.x)
			var round_way := fwd.x * -sin(a) + -fwd.z * cos(a)
			_check(not place.is_empty() and String(place.part) == "ring" and absf(r - RoadRamps.X_TOP) < 1.5, "put back %.1f m from the ring's centre, at %s" % [r, place])
			_check(round_way > 0.9, "put back facing %.2f of the way round (1 = anticlockwise)" % round_way)
			_check(p.linear_velocity.length() < 1.0 and absf(u.y - RoadRamps.RAMP_H) < 1.0, "put back moving at %.1f m/s, %.1f m up" % [p.linear_velocity.length(), u.y])
			print("ring_drive: put back on the ring, %.1f m from its centre, facing %.2f anticlockwise" % [r, round_way])
			# clockwise: turned round where it stands
			var t := p.global_transform
			t.basis = t.basis.rotated(Vector3.UP, PI)
			_stand(p, t)
			path = _line_clockwise()
			path_i = 0
			flips0 = tr.flow_flips
			_next(4)
		4:
			if p.linear_velocity.length() > 4.0 and not place.is_empty() and String(place.part) == "ring":
				cw_ticks += 1
				if bool(place.wrong_way):
					cw_wrong += 1
			if path_i >= path.size() - 3:
				_check(cw_ticks > 60 and float(cw_wrong) > float(cw_ticks) * 0.9, "clockwise round the ring: wrong way on %d of %d ticks" % [cw_wrong, cw_ticks])
				_check(tr.flow_flips == flips0, "the flow turned %d times while the car went clockwise round the ring" % (tr.flow_flips - flips0))
				print("ring_drive: clockwise: wrong way on %d of %d ticks" % [cw_wrong, cw_ticks])
				path = []
				_next(5)
		5:
			# stopped on the ring: save, then load
			if p.linear_velocity.length() > 0.3 and phase_ticks < hz * 20:
				return false
			_check(not place.is_empty() and String(place.part) == "ring", "stopped off the ring at %s" % [place])
			# the ring leans in 4 % (RoadRamps.BANK): a car at rest on it leans in with it
			var up_r := RoadFrame.dir_to_road(u.z, p.global_basis.y)
			var rr := Vector2(u.x, w).length()
			var lean_in := -(up_r.x * u.x + up_r.z * -w) / maxf(rr, 0.1)
			_check(lean_in > LEAN_LO and lean_in < LEAN_HI, "a car at rest on the ring leans in %.3f (the deck leans %.3f)" % [lean_in, sin(atan(RoadRamps.BANK))])
			print("ring_drive: at rest on the ring, leaning in %.3f (%.2f deg), deck %.3f" % [lean_in, rad_to_deg(asin(clampf(lean_in, -1.0, 1.0))), sin(atan(RoadRamps.BANK))])
			saved_place = place.duplicate()
			saved_u = Vector3(u.x, u.y, w)
			_check(game.saver.save_now(), "the save on the ring failed")
			_reboot()
			_next(6)
		6:
			if phase_ticks < 45:
				return false
			_check(game.get("resume_place") == true, "the saved run was not resumed")
			site_s = float(RoadMap.ring_near(RoadFrame.s_at(u.z)).s)
			var w2 := RoadFrame.s_at(u.z) - site_s
			_check(not place.is_empty() and String(place.part) == "ring" and String(place.id) == String(saved_place.id), "loaded at %s, saved on the ring at %s" % [place, saved_place])
			_check(Vector2(u.x - saved_u.x, w2 - saved_u.z).length() < 1.5 and absf(u.y - RoadRamps.RAMP_H) < 1.0, "loaded %.1f m from where it was saved, %.1f m up" % [Vector2(u.x - saved_u.x, w2 - saved_u.z).length(), u.y])
			_check(game.ring_site.visible and game.ring_site.site == int(place.get("site", -1)), "the ring is not standing where the car was loaded")
			print("ring_drive: saved on the ring, loaded %.2f m away, %.1f m up" % [Vector2(u.x - saved_u.x, w2 - saved_u.z).length(), u.y])
			_finish()
			return true
	return false

func _finish() -> void:
	SaveStore.clear_run()
	print("ring_drive: %d checks, %d failed" % [checks, fails.size()])
	quit(1 if not fails.is_empty() else 0)
