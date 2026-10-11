## Breakable roadside world (I1): the car hits what it used to drive through.
##
## Props stay copies in a MultiMesh; RoadsideProps holds where they stand.
## Once per physics tick the player's box (nose plus this tick's travel) is
## tested against the props of its own chunk and the next one. On a touch:
##
##  - the copy is hidden (its transform scaled to nothing) or bent in place,
##  - a pooled piece with the same mesh takes the car's velocity plus a kick
##    outward and up, and flies: a scripted arc (cones), or a real body for
##    things that roll (bins),
##  - the car loses the kind's speed (LOSS_KMH, never more than MAX_SHARE of
##    what it has) as one flat push at its centre, and for the heavier kinds
##    its nose is turned a little toward the hit corner (a change in turning
##    speed, flat only, capped at NUDGE_CAP),
##  - breakaway kinds also give the car a FIXED hit (CarDamage.apply_hit) and
##    a crash sound of a chosen size. Chosen, never measured, so a prop can
##    never end a run.
##
## A piece that comes to rest is frozen into a still copy in its chunk's
## "Debris" MultiMesh and its pooled node is free again. Debris and knocked
## cones last until the chunk is recycled; a broken breakaway is remembered
## for the night (`broken`) and put back broken when its chunk returns.
##
## Hard caps (nothing ever spawns more; when a pool is full the oldest
## freezes where it is):
##   real bodies (rollers)   4, 3 s or asleep, on PROP_LAYER: they meet the
##                           road, kerb, walls and each other, never a car or
##                           a wheel (CarSpec leaves the layer out of both masks)
##   scripted flying pieces  16, 2.5 s, bounce at road height only
##   baked animations        8 (a post bending back)
##   settled debris copies   32 per chunk
##
## Cost: `cost_usec` is the time of the last tick, `cost_peak` the worst since
## reset_cost(); tests/world/prop_hit.gd fails over CEILING_USEC in a spree.
##
## No class_name on purpose: preload it, so no class cache refresh is needed.
extends Node3D

const Props := preload("res://scripts/world/roadside_props.gd")

signal prop_hit(kind: int, chunk: int, index: int)

static var enabled := OS.get_environment("NEON_PROPS") != "0"

## Kinds that answer a hit in this build (the rest are still ghosts).
const ACTIVE := [Props.POST, Props.CONE, Props.BIN]

## Per kind, in RoadsideProps order: post, cone, bin, hydrant, lamp, sign, gantry.
const LOSS_KMH := [1.0, 1.0, 2.5, 10.0, 20.0, 5.0, 0.0]
## Share of NUDGE_CAP a full corner hit turns the nose by.
const NUDGE := [0.0, 0.0, 0.0, 0.6, 1.0, 0.3, 0.0]
## The fixed hit handed to CarDamage.apply_hit (m/s; 0 = no damage) and the
## size played by CrashAudio.impact (under 3 a tap, 3 a thud, 7 a crunch).
const DAMAGE_DV := [0.0, 0.0, 0.0, 4.0, 6.0, 4.0, 0.0]
const SOUND_DV := [1.4, 1.2, 2.4, 4.5, 7.5, 4.0, 0.0]
const SURFACE := ["metal", "concrete", "metal", "metal", "metal", "metal", "metal"]
## A hit never takes more than this share of the car's speed.
const MAX_SHARE := 0.6
## Largest change in turning speed a hit may cause (rad/s).
const NUDGE_CAP := 0.35
## The nudge fades with speed above this (m/s): the faster the car, the
## longer its tyres take to cancel a kick, so the same kick would turn it more.
const NUDGE_FULL_BELOW := 14.0
## Slower than this (m/s) the car pushes things over without a hit.
const MIN_SPEED := 1.5

const MAX_ROLLERS := 4
const ROLLER_LIFE := 3.0
const MAX_FLYERS := 16
const FLYER_LIFE := 2.5
const MAX_BENDS := 8
const DEBRIS_PER_CHUNK := 32
const CEILING_USEC := 300.0

const GRAVITY := 9.8
const BOUNCE := 0.35
const POST_H := 1.0
const POST_LEAN := 0.38      # rad the post is left leaning at
const POST_FLAT := 1.4       # rad at the bottom of the bend
const BEND_TIME := 0.9

var player: Node3D
var traffic: Node
var pool: Array = []          # game.chunk_pool: {root, index}
var night_clock: Node:
	set(v):
		night_clock = v
		if v != null and v.has_signal("night_ended"):
			v.night_ended.connect(func(_n): new_night.call_deferred())

## Breakaways broken tonight: key (chunk:kind:side:z in cm) -> true.
var broken := {}
var hits := 0
var hits_by_kind := PackedInt32Array()
var last := {}                # the last hit, for tests: kind, corner, loss, speed
var cost_usec := 0.0
var cost_peak := 0.0
var cost_sum := 0.0
var cost_ticks := 0

var _roots := {}              # chunk index -> root
var _half := {}               # car instance id -> half size
var _out := PackedInt32Array()
var _tick := 0
var _crash: Node

# scripted flyers: parallel arrays over MAX_FLYERS pooled MeshInstance3D
var _fly: Array[MeshInstance3D] = []
var _fly_on := PackedByteArray()
var _fly_vel := PackedVector3Array()
var _fly_axis := PackedVector3Array()
var _fly_spin := PackedFloat32Array()
var _fly_age := PackedFloat32Array()
var _fly_foot := PackedVector3Array()   # where it stood: the ground plane's anchor
var _fly_slope := PackedVector3Array()  # ground rise per metre, flat direction * grade
var _fly_rest := PackedFloat32Array()   # height its origin rests at, lying down
var _fly_kind := PackedInt32Array()
var _fly_chunk := PackedInt32Array()
var _fly_n := 0

var _roll: Array[RigidBody3D] = []
var _roll_on := PackedByteArray()
var _roll_age := PackedFloat32Array()
var _roll_kind := PackedInt32Array()
var _roll_chunk := PackedInt32Array()
var _roll_n := 0

# bends: a post rotating about its foot, written straight into its MultiMesh
var _bends: Array = []        # {mm, slot, foot, axis, t, root}

func _ready() -> void:
	hits_by_kind.resize(Props.NAMES.size())
	for i in MAX_FLYERS:
		var m := MeshInstance3D.new()
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_fly.append(m)
	_fly_on.resize(MAX_FLYERS)
	_fly_vel.resize(MAX_FLYERS)
	_fly_axis.resize(MAX_FLYERS)
	_fly_spin.resize(MAX_FLYERS)
	_fly_age.resize(MAX_FLYERS)
	_fly_foot.resize(MAX_FLYERS)
	_fly_slope.resize(MAX_FLYERS)
	_fly_rest.resize(MAX_FLYERS)
	_fly_kind.resize(MAX_FLYERS)
	_fly_chunk.resize(MAX_FLYERS)
	for i in MAX_ROLLERS:
		var b := RigidBody3D.new()
		b.collision_layer = 0
		b.collision_mask = 0
		b.freeze = true
		b.visible = false
		b.mass = 14.0
		b.can_sleep = true
		b.angular_damp = 0.4
		var col := CollisionShape3D.new()
		col.shape = CylinderShape3D.new()
		b.add_child(col)
		var m := MeshInstance3D.new()
		m.name = "Mesh"
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(m)
		add_child(b)
		_roll.append(b)
	_roll_on.resize(MAX_ROLLERS)
	_roll_age.resize(MAX_ROLLERS)
	_roll_kind.resize(MAX_ROLLERS)
	_roll_chunk.resize(MAX_ROLLERS)

# ---------- chunks ----------

## Called by the chunk pool after it builds or recycles a chunk: the builder
## has just laid every prop afresh, so the knocked cones and the debris of
## whatever stood here before are gone, and tonight's broken things are
## broken again.
func dress_chunk(root: Node3D, chunk: int) -> void:
	for c in _roots.keys():
		if _roots[c] == root:
			_roots.erase(c)
	_roots[chunk] = root
	var rec: Dictionary = Props.of(root)
	var gone := PackedByteArray()
	if not rec.is_empty():
		gone.resize(rec.kind.size())
	root.set_meta("props_gone", gone)
	root.set_meta("debris_n", 0)
	for child in root.get_children():
		if child is MultiMeshInstance3D and String(child.name).begins_with("Debris_"):
			(child as MultiMeshInstance3D).multimesh.visible_instance_count = 0
			(child as MultiMeshInstance3D).visible = false
	for i in range(_bends.size() - 1, -1, -1):
		if _bends[i].root == root:
			_bends.remove_at(i)
	if rec.is_empty() or broken.is_empty():
		return
	for i in rec.kind.size():
		if broken.has(_key(chunk, rec, i)):
			gone[i] = 1
			_show_broken(root, rec, i)
	root.set_meta("props_gone", gone)

func new_night() -> void:
	broken.clear()

static func _key(chunk: int, rec: Dictionary, i: int) -> String:
	return "%d:%d:%d:%d" % [chunk, rec.kind[i], rec.side[i], roundi(rec.road[i].y * 100.0)]

func is_broken(chunk: int, rec: Dictionary, i: int) -> bool:
	return broken.has(_key(chunk, rec, i))

## The floating origin moved the world by `offset`.
func shift_world(offset: Vector3) -> void:
	for i in MAX_FLYERS:
		if _fly_on[i] != 0:
			_fly[i].global_position += offset
			_fly_foot[i] += offset
			_fly[i].reset_physics_interpolation()
	for i in MAX_ROLLERS:
		if _roll_on[i] != 0:
			_roll[i].global_position += offset
			_roll[i].reset_physics_interpolation()

func reset_cost() -> void:
	cost_peak = 0.0
	cost_sum = 0.0
	cost_ticks = 0

# ---------- the tick ----------

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	_tick += 1
	if player != null and is_instance_valid(player):
		_check(player as RigidBody3D, true, delta)
	if traffic != null and is_instance_valid(traffic):
		# the near-band cars (full physics), a quarter of the list each tick
		var cars: Array = traffic.get("cars")
		var i := _tick & 3
		while i < cars.size():
			var car = cars[i]
			if car.detailed:
				_check(car as RigidBody3D, false, delta * 4.0)
			i += 4
	if _fly_n > 0:
		_step_flyers(delta)
	if _roll_n > 0:
		_step_rollers(delta)
	if not _bends.is_empty():
		_step_bends(delta)
	cost_usec = float(Time.get_ticks_usec() - t0)
	cost_peak = maxf(cost_peak, cost_usec)
	cost_sum += cost_usec
	cost_ticks += 1

func _half_of(car: Node3D) -> Vector3:
	var id := car.get_instance_id()
	if _half.has(id):
		return _half[id]
	var h := Vector3(0.9, 0.7, 2.2)
	for ch in car.get_children():
		if ch is CollisionShape3D and ch.shape is ConvexPolygonShape3D:
			var m := Vector3.ZERO
			for pt in (ch.shape as ConvexPolygonShape3D).points:
				m = m.max(pt.abs())
			h = m
			break
	_half[id] = h
	return h

func _check(car: RigidBody3D, is_player: bool, dt: float) -> void:
	if car == null:
		return
	var vel := car.linear_velocity
	var speed := vel.length()
	if speed < MIN_SPEED:
		return
	var u := RoadFrame.unroll(car.global_position)
	var s := RoadFrame.s_at(u.z)
	var here := floori(s / Props.CHUNK_LEN)
	var half := _half_of(car)
	var car_xf := car.global_transform
	var car_inv := car_xf.affine_inverse()
	# forward is -z; a reversing car sweeps behind itself instead
	var fwd_speed := -(car_inv.basis * vel).z
	var front := half.z + maxf(fwd_speed, 0.0) * dt
	var back := half.z + maxf(-fwd_speed, 0.0) * dt
	for c in [here, here + 1, here - 1]:
		var local_z := -(s - float(c) * Props.CHUNK_LEN)
		if local_z > front + 1.0 or local_z < -Props.CHUNK_LEN - back - 1.0:
			continue
		var root: Node3D = _roots.get(c)
		if root == null or not is_instance_valid(root) or root.get_meta("rebuilding", false):
			continue
		var rec: Dictionary = Props.of(root)
		if rec.is_empty():
			continue
		var gone: PackedByteArray = root.get_meta("props_gone", PackedByteArray())
		if gone.size() != rec.kind.size():
			continue
		_out.clear()
		var to_car := car_inv * root.global_transform
		Props.near(rec, to_car, local_z, half.x, front, back, gone, _out)
		if _out.is_empty():
			continue
		var changed := false
		for i in _out:
			var kind: int = rec.kind[i]
			if not (kind in ACTIVE):
				continue
			if not is_player and Props.CLASS[kind] != Props.GIVES:
				continue
			gone[i] = 1
			changed = true
			_hit(car, is_player, root, c, rec, i, (to_car * (rec.pos[i] as Vector3)).x / half.x)
		if changed:
			root.set_meta("props_gone", gone)

## The speed (km/h) a hit on `kind` takes from a car doing `speed_kmh`.
static func loss_for(kind: int, speed_kmh: float) -> float:
	return minf(float(LOSS_KMH[kind]), speed_kmh * MAX_SHARE)

## The change in turning speed (rad/s, + = nose to the left) for a hit on
## `kind` at `corner` (-1 the left corner .. 1 the right) at `speed` m/s.
static func nudge_for(kind: int, corner: float, speed: float) -> float:
	var fade := minf(1.0, NUDGE_FULL_BELOW / maxf(speed, 0.1))
	return -clampf(corner, -1.0, 1.0) * NUDGE_CAP * float(NUDGE[kind]) * fade

func _hit(car: RigidBody3D, is_player: bool, root: Node3D, chunk: int, rec: Dictionary, i: int, corner: float) -> void:
	var kind: int = rec.kind[i]
	var vel := car.linear_velocity
	var speed := vel.length()
	var flat := Vector3(vel.x, 0.0, vel.z)
	var dir := flat.normalized() if flat.length() > 0.1 else -car.global_transform.basis.z
	var right := car.global_transform.basis.x
	corner = clampf(corner, -1.0, 1.0)
	var foot: Vector3 = root.global_transform * (rec.pos[i] as Vector3)
	hits += 1
	hits_by_kind[kind] += 1
	if is_player:
		var loss := loss_for(kind, speed * 3.6) / 3.6
		# one flat push through the centre: no pitch, no roll, no lift
		car.linear_velocity = vel - dir * loss
		var dw := nudge_for(kind, corner, speed)
		if dw != 0.0:
			car.angular_velocity += Vector3.UP * dw
		last = {"kind": kind, "corner": corner, "loss_kmh": loss * 3.6, "speed_kmh": speed * 3.6, "nudge": dw, "chunk": chunk, "index": i}
		_sound(car, float(SOUND_DV[kind]), SURFACE[kind])
		if Props.CLASS[kind] == Props.BREAKAWAY:
			broken[_key(chunk, rec, i)] = true
			var dmg = car.get("damage")
			if dmg != null and float(DAMAGE_DV[kind]) > 0.0:
				# from the front, at the corner that met it (x right, z back)
				dmg.apply_hit(Vector3(-corner * 0.6, 0.0, 1.0).normalized() * float(DAMAGE_DV[kind]))
	match kind:
		Props.POST:
			_bend(root, rec, i, dir)
		Props.BIN:
			_hide(root, rec, i)
			_launch_roller(root, chunk, rec, i, foot, vel, right * signf(corner if absf(corner) > 0.05 else 1.0), speed)
		_:
			_hide(root, rec, i)
			_launch_flyer(root, chunk, rec, i, foot, vel, right * corner, speed, car.global_transform.basis)
	prop_hit.emit(kind, chunk, i)

func _sound(car: Node, dv: float, surface: String) -> void:
	if _crash == null or not is_instance_valid(_crash) or _crash.get_parent() != car:
		_crash = null
		for ch in car.get_children():
			if ch is CrashAudio:
				_crash = ch
				break
	if _crash != null:
		_crash.impact(dv, surface)

# ---------- the copies ----------

## The MultiMesh node a kind's copies live in on this chunk.
static func _node_name(kind: int, side: int, slot: int) -> String:
	match kind:
		Props.POST:
			return "PylonsOwn" if side > 0 else "PylonsOnc"
		Props.CONE:
			return "Kit_cone"
		Props.BIN:
			return "Kit_bin"
		Props.HYDRANT:
			return "Kit_hydrant" if slot >= RoadChunkBuilder.KIT_SLOT else "Hydrants"
		Props.LAMP:
			return "Lamps"
	return ""

static func _mmi(root: Node3D, rec: Dictionary, i: int) -> MultiMeshInstance3D:
	var n := _node_name(rec.kind[i], rec.side[i], rec.slot[i])
	return root.get_node_or_null(NodePath(n)) as MultiMeshInstance3D if n != "" else null

static func _slot(rec: Dictionary, i: int) -> int:
	var s: int = rec.slot[i]
	return s - RoadChunkBuilder.KIT_SLOT if s >= RoadChunkBuilder.KIT_SLOT else s

func _hide(root: Node3D, rec: Dictionary, i: int) -> void:
	var mmi := _mmi(root, rec, i)
	var slot := _slot(rec, i)
	if mmi == null or slot < 0 or slot >= mmi.multimesh.instance_count:
		return
	mmi.multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), rec.pos[i]))

## Tonight's broken thing, on a chunk that has just been laid afresh.
func _show_broken(root: Node3D, rec: Dictionary, i: int) -> void:
	_hide(root, rec, i)

# ---------- bends ----------

func _bend(root: Node3D, rec: Dictionary, i: int, dir: Vector3) -> void:
	var mmi := _mmi(root, rec, i)
	var slot := _slot(rec, i)
	if mmi == null or slot < 0:
		return
	if _bends.size() >= MAX_BENDS:
		_bend_write(_bends[0], BEND_TIME)   # the oldest finishes where it ends
		_bends.remove_at(0)
	# falls away from the car: about the flat axis square to its travel
	var local_dir: Vector3 = root.global_transform.basis.inverse() * dir
	local_dir.y = 0.0
	local_dir = local_dir.normalized()
	var b := {"mm": mmi.multimesh, "slot": slot, "foot": rec.pos[i], "axis": Vector3.UP.cross(local_dir).normalized(), "t": 0.0, "root": root}
	_bends.append(b)
	_bend_write(b, 0.0)

## The lean (rad) t seconds into a bend: down flat in a blink, then up to a
## lean with a wobble that dies out.
static func bend_angle(t: float) -> float:
	if t < 0.08:
		return POST_FLAT * t / 0.08
	var k := (t - 0.08) / (BEND_TIME - 0.08)
	if k >= 1.0:
		return POST_LEAN
	return POST_LEAN + (POST_FLAT - POST_LEAN) * exp(-5.0 * k) * cos(k * 14.0)

func _bend_write(b: Dictionary, t: float) -> void:
	var rot := Basis(b.axis, bend_angle(t))
	(b.mm as MultiMesh).set_instance_transform(b.slot, Transform3D(rot, (b.foot as Vector3) + rot * Vector3(0.0, POST_H * 0.5, 0.0)))

func _step_bends(delta: float) -> void:
	for k in range(_bends.size() - 1, -1, -1):
		var b: Dictionary = _bends[k]
		b.t += delta
		_bend_write(b, b.t)
		if b.t >= BEND_TIME:
			_bends.remove_at(k)

# ---------- scripted flyers ----------

func _launch_flyer(root: Node3D, chunk: int, rec: Dictionary, i: int, foot: Vector3, vel: Vector3, side_push: Vector3, speed: float, car_basis: Basis) -> void:
	var mmi := _mmi(root, rec, i)
	if mmi == null:
		return
	var k := -1
	var oldest := 0
	for j in MAX_FLYERS:
		if _fly_on[j] == 0:
			k = j
			break
		if _fly_age[j] > _fly_age[oldest]:
			oldest = j
	if k < 0:
		_freeze_flyer(oldest)
		k = oldest
	var m := _fly[k]
	m.mesh = mmi.multimesh.mesh
	m.material_override = mmi.material_override
	var yaw := Basis(Vector3.UP, float(posmod(hash([chunk, i]), 628)) * 0.01)
	m.global_transform = Transform3D(yaw, foot)
	m.reset_physics_interpolation()
	m.visible = true
	# the car's speed, a kick out to the side it was hit on, and up
	var out := Vector3(side_push.x, 0.0, side_push.z)
	_fly_vel[k] = vel * 0.85 + out * (1.5 + speed * 0.06) + Vector3.UP * clampf(2.0 + speed * 0.07, 2.0, 6.5)
	var axis := Vector3(vel.z, 0.0, -vel.x)
	_fly_axis[k] = axis.normalized() if axis.length() > 0.01 else Vector3.RIGHT
	_fly_spin[k] = clampf(speed * 0.5, 3.0, 14.0)
	_fly_age[k] = 0.0
	_fly_foot[k] = foot
	# the ground under the piece: the plane through the foot with the car's grade
	var fwd := -car_basis.z
	var fh := Vector3(fwd.x, 0.0, fwd.z)
	var run := fh.length()
	_fly_slope[k] = fh / run * (fwd.y / run) if run > 0.3 else Vector3.ZERO
	_fly_rest[k] = float(Props.RADIUS[rec.kind[i]])
	_fly_kind[k] = rec.kind[i]
	_fly_chunk[k] = chunk
	if _fly_on[k] == 0:
		_fly_on[k] = 1
		_fly_n += 1

func _step_flyers(delta: float) -> void:
	for k in MAX_FLYERS:
		if _fly_on[k] == 0:
			continue
		var m := _fly[k]
		var v := _fly_vel[k]
		v.y -= GRAVITY * delta
		var p := m.global_position + v * delta
		var ground := _fly_foot[k].y + (p - _fly_foot[k]).dot(_fly_slope[k]) + _fly_rest[k]
		var landed := false
		if p.y <= ground:
			p.y = ground
			if v.y < 0.0:
				v.y = -v.y * BOUNCE
				v.x *= 0.6
				v.z *= 0.6
				_fly_spin[k] *= 0.5
			landed = absf(v.y) < 0.7 and Vector2(v.x, v.z).length() < 1.2
		_fly_vel[k] = v
		_fly_age[k] += delta
		m.global_transform = Transform3D(Basis(_fly_axis[k], _fly_spin[k] * delta) * m.global_transform.basis, p)
		if landed or _fly_age[k] >= FLYER_LIFE:
			_freeze_flyer(k)

## A flyer comes to rest: lying on its side on the ground, as a still copy
## in its chunk's debris, and its pooled node is free again.
func _freeze_flyer(k: int) -> void:
	var m := _fly[k]
	var p := m.global_position
	p.y = _fly_foot[k].y + (p - _fly_foot[k]).dot(_fly_slope[k]) + _fly_rest[k]
	var along := Vector3(_fly_vel[k].x, 0.0, _fly_vel[k].z)
	along = along.normalized() if along.length() > 0.05 else Vector3.FORWARD
	# its own up axis laid along the way it was sliding
	var lying := Basis(along.cross(Vector3.UP).normalized(), along, Vector3.UP).orthonormalized()
	_to_debris(_fly_chunk[k], _fly_kind[k], m.mesh, m.material_override, Transform3D(lying, p))
	m.visible = false
	_fly_on[k] = 0
	_fly_n -= 1

# ---------- rollers ----------

func _launch_roller(root: Node3D, chunk: int, rec: Dictionary, i: int, foot: Vector3, vel: Vector3, side_push: Vector3, speed: float) -> void:
	var mmi := _mmi(root, rec, i)
	if mmi == null:
		return
	var k := -1
	var oldest := 0
	for j in MAX_ROLLERS:
		if _roll_on[j] == 0:
			k = j
			break
		if _roll_age[j] > _roll_age[oldest]:
			oldest = j
	if k < 0:
		_freeze_roller(oldest)
		k = oldest
	var b := _roll[k]
	var aabb := mmi.multimesh.mesh.get_aabb()
	var h := maxf(aabb.size.y, 0.3)
	var shape := (b.get_child(0) as CollisionShape3D).shape as CylinderShape3D
	shape.height = h
	shape.radius = maxf(aabb.size.x, aabb.size.z) * 0.5
	var mesh := b.get_node(^"Mesh") as MeshInstance3D
	mesh.mesh = mmi.multimesh.mesh
	mesh.material_override = mmi.material_override
	mesh.position = Vector3(0.0, -h * 0.5, 0.0)   # the kit's meshes stand on their origin
	b.freeze = false
	b.global_transform = Transform3D(Basis(), foot + Vector3(0.0, h * 0.5 + 0.02, 0.0))
	b.reset_physics_interpolation()
	b.collision_layer = 1 << (CarSpec.PROP_LAYER - 1)
	b.collision_mask = (1 << (CarSpec.WORLD_LAYER - 1)) | (1 << (CarSpec.WALL_LAYER - 1)) | (1 << (CarSpec.KERB_LAYER - 1)) | (1 << (CarSpec.PROP_LAYER - 1))
	var out := Vector3(side_push.x, 0.0, side_push.z)
	b.linear_velocity = vel * 0.7 + out * (1.0 + speed * 0.04) + Vector3.UP * clampf(1.0 + speed * 0.03, 1.0, 3.5)
	b.angular_velocity = Vector3(vel.z, 0.0, -vel.x).normalized() * clampf(speed * 0.3, 2.0, 9.0)
	b.sleeping = false
	b.visible = true
	_roll_age[k] = 0.0
	_roll_kind[k] = rec.kind[i]
	_roll_chunk[k] = chunk
	if _roll_on[k] == 0:
		_roll_on[k] = 1
		_roll_n += 1

func _step_rollers(delta: float) -> void:
	for k in MAX_ROLLERS:
		if _roll_on[k] == 0:
			continue
		_roll_age[k] += delta
		var b := _roll[k]
		if _roll_age[k] >= ROLLER_LIFE or (b.sleeping and _roll_age[k] > 0.3) or b.global_position.y < -200.0:
			_freeze_roller(k)

func _freeze_roller(k: int) -> void:
	var b := _roll[k]
	var mesh := b.get_node(^"Mesh") as MeshInstance3D
	_to_debris(_roll_chunk[k], _roll_kind[k], mesh.mesh, mesh.material_override, mesh.global_transform)
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	b.visible = false
	_roll_on[k] = 0
	_roll_n -= 1

# ---------- debris ----------

## A still copy in the chunk the piece came to rest on (or, if that one is
## not loaded, the one it came from). Gone when that chunk is recycled.
func _to_debris(from_chunk: int, kind: int, mesh: Mesh, mat: Material, world: Transform3D) -> void:
	var at := floori(RoadFrame.s_at(RoadFrame.unroll(world.origin).z) / Props.CHUNK_LEN)
	var root: Node3D = _roots.get(at)
	if root == null or not is_instance_valid(root) or root.get_meta("rebuilding", false):
		root = _roots.get(from_chunk)
		if root == null or not is_instance_valid(root) or root.get_meta("rebuilding", false):
			return
	var n: int = root.get_meta("debris_n", 0)
	var node_name := "Debris_" + Props.NAMES[kind]
	var mmi := root.get_node_or_null(NodePath(node_name)) as MultiMeshInstance3D
	if mmi == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = DEBRIS_PER_CHUNK
		mm.visible_instance_count = 0
		mmi = MultiMeshInstance3D.new()
		mmi.name = node_name
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 120.0
		root.add_child(mmi)
	mmi.material_override = mat
	mmi.multimesh.mesh = mesh
	var used := mmi.multimesh.visible_instance_count
	var slot := used
	if n >= DEBRIS_PER_CHUNK or used >= DEBRIS_PER_CHUNK:
		# the chunk is full: this copy takes the place of this kind's oldest
		slot = int(mmi.get_meta("next", 0)) % maxi(used, 1)
		mmi.set_meta("next", slot + 1)
		if used == 0:
			return
	else:
		mmi.multimesh.visible_instance_count = used + 1
		root.set_meta("debris_n", n + 1)
	mmi.multimesh.set_instance_transform(slot, root.global_transform.affine_inverse() * world)
	mmi.visible = true

func debris_count(chunk: int) -> int:
	var root: Node3D = _roots.get(chunk)
	return int(root.get_meta("debris_n", 0)) if root != null and is_instance_valid(root) else 0

func flying() -> int:
	return _fly_n

func rolling() -> int:
	return _roll_n

func bending() -> int:
	return _bends.size()

# ---------- tests ----------

## Tests and tools: stands one more prop of `kind` on the road at (x across,
## `ahead` metres in front of `from`), on whatever chunk that is. It has no
## copy of its own to hide; the piece that flies takes the kind's mesh.
## Returns [chunk, index], or [] when that chunk is not loaded.
func add_test_prop(kind: int, x: float, from: Vector3, ahead: float) -> Array:
	var u := RoadFrame.unroll(from)
	var z := u.z - ahead
	var s := RoadFrame.s_at(z)
	var chunk := floori(s / Props.CHUNK_LEN)
	var root: Node3D = _roots.get(chunk)
	if root == null or not is_instance_valid(root) or root.get_meta("rebuilding", false):
		return []
	var rec: Dictionary = Props.of(root)
	if rec.is_empty():
		return []
	var world := RoadFrame.roll(Vector3(x, 0.0, z))
	Props.add(rec, kind, root.global_transform.affine_inverse() * world, -1, 1 if x >= 0.0 else -1, x, -(s - float(chunk) * Props.CHUNK_LEN))
	Props.write(root, rec)
	var gone: PackedByteArray = root.get_meta("props_gone", PackedByteArray())
	gone.resize(rec.kind.size())
	root.set_meta("props_gone", gone)
	return [chunk, rec.kind.size() - 1]
