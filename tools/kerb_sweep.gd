extends SceneTree

# Kerb physics sweep (pavements step 3, 2026-10-10): the player's coupe is
# put on the road beside the own-side kerb and coasts into it, at a grid of
# speeds and approach angles, and the sweep prints what the kerb did to it.
# A second table drives a full-lock circle on a flat pad of each surface group
# (Road, Kerb, Grass): the grip groups side by side. (Braking on the pavement
# itself shows nothing: the brakes, not the tyres, are the limit.) Read it before tuning KERB_SURFACE /
# GRASS_SURFACE in car_spec.gd, KERB_FREE_MS / KERB_DAMAGE_PER_MS in
# car_damage.gd, or a kerb height in Districts.CROSS.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tools/kerb_sweep.gd
#
# Environment (all optional, comma lists): SWEEP_SPEEDS (km/h), SWEEP_ANGLES
# (degrees), SWEEP_DISTRICTS (downtown, residential, strip, industrial, freeway; the
# default is all four plus the freeway). The car
# is built in the air for each, so nothing is driven to.
#
# Per row: strike = the speed into the kerb the damage model measured (m/s,
# 0 = none), steer = the worse front steering arm's damage 0..1, body = the
# repair cost share, roll / pitch = the peak lean in degrees, up = the peak
# upward speed the kerb gave (m/s), lost = speed lost over the run, end =
# how the run ended (road = never reached the kerb, kerb = still on the
# pavement, across = over it to its back edge, rolled), flip = rolled
# past 70 degrees. The run stops at the pavement's back edge, so a wall
# behind it never counts.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Districts := preload("res://scripts/world/districts.gd")

const RUN_S := 2.0
const STAGE_Y := 5000.0
const STANDOFF := 1.0  ## the car's right side starts this far from the kerb face, plus 0.25 s of the sideways speed

var game: Node
var speeds: Array = [40, 70, 100, 130]
var angles: Array = [5, 10, 20, 30, 45]
var districts: Array = ["downtown", "residential", "strip", "industrial", "freeway"]

func _initialize() -> void:
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_ROAD_SEED", "37")
	var sp := OS.get_environment("SWEEP_SPEEDS").strip_edges()
	if sp != "":
		speeds = Array(sp.split(",")).map(func(x): return float(x))
	var an := OS.get_environment("SWEEP_ANGLES").strip_edges()
	if an != "":
		angles = Array(an.split(",")).map(func(x): return float(x))
	var ds := OS.get_environment("SWEEP_DISTRICTS").strip_edges()
	if ds == "-":
		districts = []
	elif ds != "":
		districts = Array(ds.split(","))
	game = Harness.boot(self, 0, 300.0, 777, 1.0e6)
	_run.call_deferred()

func _run() -> void:
	for i in 120:
		await physics_frame
	var p: PlayerCar = game.get("player")
	p.contact_monitor = true
	p.max_contacts_reported = 8
	_coast(p)
	var first := true
	for name in districts:
		var c := _chunk_of(String(name))
		await _stage(c)
		var kerb_x := RoadChunkBuilder._lane_w(4) + Districts.shoulder_at(c)
		var walk := Districts.walk_at(c)
		print("")
		print("kerb_sweep: %s, chunk %d: kerb face at x=%.2f, kerb %.2f m high, pavement %.1f m wide, shoulder %.1f m, kerb %s" % [
			name, c, kerb_x, Districts.kerb_h_at(c), walk, Districts.shoulder_at(c), "yes" if Districts.cross_at(c).kerb else "no (verge)"])
		if first:
			_print_grip(p)
			first = false
		print("%6s %6s | %6s %6s %6s %6s %6s %6s %6s %7s %5s  %s" % ["km/h", "deg", "strike", "steer", "body", "roll", "pitch", "up", "lost", "end", "flip", "touched"])
		for v in speeds:
			for a in angles:
				var r := await _hit(p, float(v), float(a), kerb_x, walk)
				print("%6d %6d | %6.1f %6.2f %6.2f %6.1f %6.1f %6.1f %6.1f %7s %5s  %s" % [
					v, a, r.strike, r.steer, r.body, r.roll, r.pitch, r.up, r.lost, r.end, "YES" if r.flip else "-", r.touched])
		_unstage()
	print("")
	print("skid pad: full steering lock from 50 km/h, coasting, on a flat pad of each surface group")
	print("(mean lateral g, speed x yaw rate, over seconds 1 to 3)")
	var base := 0.0
	var w0: Wheel = p.wheel_array[0]
	var kerb_stiff: float = w0.tire_stiffnesses["Kerb"]
	for variant in [["Road", 1.0], ["Kerb", 1.0], ["Grass", 1.0]]:
		var group: String = variant[0]
		var mult: float = variant[1]
		for w in p.wheel_array:
			w.tire_stiffnesses[group] = (kerb_stiff if group == "Kerb" else float(w0.tire_stiffnesses.get(group, 3.0))) * mult
		var g := await _skidpad(p, group)
		if group == "Road":
			base = g
		print("  %-6s %5.2f g   %3.0f%% of the road" % [group, g, 100.0 * g / maxf(base, 0.01)])
		for w in p.wheel_array:
			w.tire_stiffnesses[group] = (kerb_stiff if group == "Kerb" else float(w0.tire_stiffnesses.get(group, 3.0)))
	quit(0)

## A chunk to test beside: run 1 on (run 0 holds the crossing), three chunks
## in, of the district called `name`; "freeway" is a stretch of the layout's
## outskirts.
func _chunk_of(name: String) -> int:
	if name == "freeway":
		for c in range(4, 4000):
			if Districts.is_freeway(c - 1) and Districts.is_freeway(c) and Districts.is_freeway(c + 1) and Districts.is_freeway(c + 2):
				return c
		return 4
	for run in range(1, 200):
		var c := run * Districts.RUN + 3
		if Districts.name_of_run(run) == name and not Districts.is_freeway(c - 1) and not Districts.is_freeway(c + 3):
			return c
	return 4

var _staged: Array = []

## Builds chunks c..c+2 high in the air (y=5000) with a plain road surface
## under them (the chunk's own road collision is off; the game's ground is
## 5 km down), so the sweep needs no driving to a district.
func _stage(c: int) -> void:
	var cfg := {"own_lanes": 4, "onc_lanes": 4, "barrier": false}
	var road := StaticBody3D.new()
	road.add_to_group("Road")
	road.collision_layer = 1 << (CarSpec.WORLD_LAYER - 1)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 2.0, 200.0)
	cs.shape = box
	road.add_child(cs)
	root.add_child(road)
	road.global_position = Vector3(0.0, STAGE_Y - 1.0, -90.0)
	_staged.append(road)
	for k in 3:
		var chunk := RoadChunkBuilder.build_chunk(c + k, cfg, cfg)
		root.add_child(chunk)
		chunk.transform = Transform3D(Basis(), Vector3(0.0, STAGE_Y, -RoadChunkBuilder.CHUNK_LEN * float(k)))
		RoadChunkBuilder.sync_collision(chunk)
		_staged.append(chunk)
	for i in 4:
		await physics_frame

func _unstage() -> void:
	for n in _staged:
		(n as Node).queue_free()
	_staged.clear()

func _coast(p: PlayerCar) -> void:
	p.driver = func(c: Vehicle) -> void:
		c.steering_input = 0.0
		c.throttle_input = 0.0
		c.brake_input = 0.0
		c.handbrake_input = 0.0

func _print_grip(p: PlayerCar) -> void:
	var w: Wheel = p.wheel_array[0]
	for key in CarSpec.SURFACE_KEYS:
		var d: Dictionary = w.get(key)
		print("  %-26s Road %5.2f  Kerb %5.2f  Grass %5.2f  Dirt %5.2f" % [key, d.get("Road", NAN), d.get("Kerb", NAN), d.get("Grass", NAN), d.get("Dirt", NAN)])

func _place(p: PlayerCar, x: float, yaw: float, speed_ms: float, z: float) -> void:
	p.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, STAGE_Y + 0.45, z))
	p.previous_global_position = p.global_position
	for w in p.wheel_array:
		w.previous_global_position = w.global_position
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	Harness.launch_player(p, speed_ms)

## Clears the damage the placement itself caused: teleporting to speed is a
## big velocity change in the damage model's eyes, so it is wiped once the
## car has settled and before the timed run.
func _clear_damage(p: PlayerCar) -> void:
	for i in p.damage.parts.size():
		p.damage.parts[i] = 0.0
	p.damage.kerb_strikes = 0
	p.damage.last_kerb_strike = 0.0
	p.damage.hits = 0
	p.damage._hit_left = -1.0
	p.damage._hit_dv = Vector3.ZERO

func _hit(p: PlayerCar, kmh: float, deg: float, kerb_x: float, walk: float) -> Dictionary:
	var yaw := -deg_to_rad(deg)
	var lateral := kmh / 3.6 * sin(deg_to_rad(deg))
	# Start so the right-hand wheels reach the kerb after STANDOFF across,
	# plus a quarter second of the car's sideways speed (it settles on its
	# springs and picks up its heading before the kerb comes).
	var x0 := kerb_x - 0.88 - STANDOFF - 0.25 * lateral
	_place(p, x0, yaw, kmh / 3.6, -2.0)
	for i in 6:
		await physics_frame
	_clear_damage(p)
	var v0 := p.linear_velocity.length()
	var roll := 0.0
	var pitch := 0.0
	var up := 0.0
	var flip := false
	var ticks := int(RUN_S * Engine.physics_ticks_per_second)
	var back := kerb_x + RoadChunkBuilder.CURB_W + walk - 1.0  # centre x: right wheels at the pavement's back edge
	var end := "road"
	var touched := {}
	var last_hits := 0
	for i in ticks:
		await physics_frame
		if OS.get_environment("SWEEP_DEBUG") == "1" and p.damage.hits != last_hits:
			last_hits = p.damage.hits
			var st := PhysicsServer3D.body_get_direct_state(p.get_rid())
			for ci in st.get_contact_count():
				var o := st.get_contact_collider_object(ci)
				print("    hit %d at tick %d: %s normal %s" % [last_hits, i, str(o.name) if o != null else "?", str(st.get_contact_local_normal(ci))])
		for body in p.get_colliding_bodies():
			var n := String(body.name)
			if not n.begins_with("@"):  # the unnamed ground plane is always there
				touched[n] = true
		var b := p.global_transform.basis
		roll = maxf(roll, absf(rad_to_deg(asin(clampf(b.x.y, -1.0, 1.0)))))
		pitch = maxf(pitch, absf(rad_to_deg(asin(clampf(b.z.y, -1.0, 1.0)))))
		up = maxf(up, p.linear_velocity.y)
		if b.y.y < 0.34:  # past 70 degrees
			flip = true
			end = "rolled"
			break
		if p.global_position.x >= back:
			end = "across"  # over the pavement; the wall stands just behind it
			break
		if p.global_position.x >= kerb_x:
			end = "kerb"
	var d := p.damage
	return {"strike": d.last_kerb_strike, "steer": maxf(d.parts[CarDamage.Part.STEER_FL], d.parts[CarDamage.Part.STEER_FR]),
		"body": d.parts[CarDamage.Part.BODY], "roll": roll, "pitch": pitch, "up": up,
		"lost": (v0 - p.linear_velocity.length()) * 3.6, "end": end, "flip": flip, "touched": ",".join(PackedStringArray(touched.keys()))}

## A big flat pad of one surface group high in the air (nothing else is
## there), the car on it with full steering lock at 50 km/h, coasting. Returns the mean
## lateral g (speed x yaw rate) over seconds 1 to 3 of a coasting run.
func _skidpad(p: PlayerCar, group: String) -> float:
	var pad := StaticBody3D.new()
	pad.add_to_group(group)
	pad.collision_layer = 1 << (CarSpec.KERB_LAYER - 1)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500.0, 2.0, 500.0)
	cs.shape = box
	pad.add_child(cs)
	game.add_child(pad)
	pad.global_position = Vector3(0.0, 8999.0, 0.0)  # top face at y=9000
	_place(p, 0.0, 0.0, 50.0 / 3.6, 0.0)
	p.global_position = Vector3(0.0, 9000.45, 0.0)
	p.previous_global_position = p.global_position
	for w in p.wheel_array:
		w.previous_global_position = w.global_position
	p.driver = func(c: Vehicle) -> void:
		c.steering_input = 1.0
		c.throttle_input = 0.0
		c.brake_input = 0.0
		c.handbrake_input = 0.0
	var sum := 0.0
	var n := 0
	var rate := Engine.physics_ticks_per_second
	for i in 3 * rate:
		await physics_frame
		if i >= rate:  # the first second is the turn-in; the circle is what is left
			sum += p.linear_velocity.length() * absf(p.angular_velocity.y) / 9.81
			n += 1
	var peak := sum / float(maxi(n, 1))
	_coast(p)
	pad.queue_free()
	return peak
