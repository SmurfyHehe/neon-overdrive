class_name PoliceHelicopter
extends Node3D

# The police helicopter (heat 5; police spec 3.1 and P12, issue #631). Not a
# car and not one of the driving-cop slots: it is counted on its own (Roy
# 2026-10-13, "1490 yes"). PolicePatrol puts one up when the heat reaches 5
# and sends it home when the heat drops.
#
#   coming   it starts high up, well behind you and out of view, and flies to
#            its spot HOVER_UP over the road HOVER_BACK behind you, never
#            faster than TOP_SPEED (a car going flat out leaves it behind).
#   over you it holds that spot and its searchlight is on you.
#   leaving  heat under 5: it climbs away from you and is gone once nobody
#            can see it.
#
# Sight (LOOK_HZ, one ray): it sees you from anywhere inside REACH unless
# something solid is in between: a tunnel, a bridge or deck over you, a
# covered pocket. Cars are looked through. What it sees goes into
# PoliceHeat.helicopter_sees: heat 5 does not cool while it has you, and the
# cops on the road know where you are (CopBrain).
#
# The look is a stand-in until the art stage: a dark body, tail boom and a
# spinning rotor disc in the Amber vs Dusk navy, a red and a police-blue
# lamp, and one SpotLight3D without shadows (the spec's "one shared
# SpotLight3D").
#
# Cost: one ray LOOK_HZ times a second and a few vector sums a tick; the
# spotlight is one light on the GPU.

const HOVER_UP := 60.0          # m above the road
const HOVER_BACK := 25.0        # m behind you along your way
const TOP_SPEED := 70.0         # m/s (252 km/h)
const ACCEL := 9.0              # m/s^2
const START_BACK := 420.0       # m behind you where it starts (out of view)
const START_UP := 140.0
const LEAVE_UP := 18.0          # m/s it climbs at when leaving
const REACH := 450.0            # m it sees you from, straight line
const LOOK_HZ := 4.0
const SKIPS := 3                # cars between it and you are looked through
const LIGHT_RANGE := 160.0
const LIGHT_ANGLE := 9.0        # degrees, half angle
const ROTOR_RPS := 6.0
const AIM_HZ := 30.0            # body heading and searchlight aim

enum Phase { COMING, OVER, LEAVING }

var player: Node3D
var heat: PoliceHeat
var traffic: TrafficManager
var phase := Phase.COMING
var vel := Vector3.ZERO
var sees := false
## True once it has been over you (tests).
var arrived := false
var looks := 0
## Cost (tests): microseconds spent in its own tick, and ticks.
var step_us := 0
var step_runs := 0
var _look_acc := 0.0
var _aim_acc := INF
var _goal := Vector3.ZERO
var _pv := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()
var _rotor: Node3D
var light: SpotLight3D

## Where it starts: START_BACK behind the player along its way, START_UP up.
func start_at(back_dir: float) -> void:
	var pu := RoadFrame.unroll(player.global_position)
	global_position = RoadFrame.roll(Vector3(pu.x, START_UP, pu.z - back_dir * START_BACK))

func _ready() -> void:
	_build()

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var t0 := Time.get_ticks_usec()
	_rotor.rotate_y(TAU * ROTOR_RPS * delta)
	# the spot and your velocity are read AIM_HZ times a second and carried
	# along in between (unrolling the road every tick was most of its cost)
	_aim_acc += delta
	var aim := _aim_acc >= 1.0 / AIM_HZ
	if aim:
		_aim_acc = 0.0
		_goal = _spot()
		_pv = player.get("linear_velocity") if player.get("linear_velocity") is Vector3 else Vector3.ZERO
	else:
		_goal += _pv * delta
	var goal := _goal
	if phase == Phase.LEAVING:
		vel = vel.move_toward(Vector3(vel.x, LEAVE_UP, vel.z), ACCEL * delta)
	else:
		# fly to the spot (which moves with you), braking in time to arrive at
		# your pace; never faster than TOP_SPEED over the ground
		var to := goal - global_position
		var d := to.length()
		var want := _pv + to / maxf(d, 0.001) * minf(TOP_SPEED, sqrt(2.0 * ACCEL * d))
		vel = vel.move_toward(want.limit_length(TOP_SPEED), ACCEL * 2.0 * delta)
		if d < 20.0:
			phase = Phase.OVER
			arrived = true
		elif phase == Phase.OVER and d > 60.0:
			phase = Phase.COMING
	global_position += vel * delta
	# nose along its way, searchlight on you (AIM_HZ is plenty for both)
	if aim:
		var flat := Vector3(vel.x, 0.0, vel.z)
		if flat.length() > 1.0:
			basis = Basis.looking_at(flat.normalized(), Vector3.UP)
		if light != null:
			light.visible = phase != Phase.LEAVING and sees
			if light.visible:
				light.look_at(player.global_position, Vector3.UP)
	_look_acc += delta
	if _look_acc >= 1.0 / LOOK_HZ:
		_look_acc = 0.0
		sees = phase != Phase.LEAVING and _can_see()
		looks += 1
		if heat != null:
			heat.helicopter_sees = sees
	step_us += Time.get_ticks_usec() - t0
	step_runs += 1

## Its spot over the road: HOVER_UP up, HOVER_BACK behind the player along
## the way the player is going.
func _spot() -> Vector3:
	var pu := RoadFrame.unroll(player.global_position)
	var pv: Vector3 = player.get("linear_velocity") if player.get("linear_velocity") is Vector3 else Vector3.ZERO
	var vz := RoadFrame.dir_to_road(pu.z, pv).z
	var dir := signf(vz) if absf(vz) > 2.0 else -1.0
	return RoadFrame.roll(Vector3(pu.x, pu.y + HOVER_UP, pu.z - dir * HOVER_BACK))

## One ray to the player: anything solid in between that is not a car hides it.
func _can_see() -> bool:
	if global_position.distance_to(player.global_position) > REACH:
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	_ray.from = global_position
	_ray.to = player.global_position + Vector3.UP * PoliceRules.TARGET_HEIGHT
	var ex: Array[RID] = []
	if player is CollisionObject3D:
		ex.append((player as CollisionObject3D).get_rid())
	for i in SKIPS + 1:
		_ray.exclude = ex
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			return true
		if not (hit.collider is RigidBody3D) or i == SKIPS:
			return false
		ex.append((hit.collider as CollisionObject3D).get_rid())
	return false

## Gone when it is leaving and no camera can see it (or it is far off).
func can_go() -> bool:
	if phase != Phase.LEAVING:
		return false
	if global_position.distance_to(player.global_position) > 600.0:
		return true
	return traffic != null and not traffic.in_view(global_position)

## Floating origin (PolicePatrol.shift_world).
func shift_world(offset: Vector3) -> void:
	global_position += offset
	_goal += offset
	reset_physics_interpolation()

func leave() -> void:
	if phase != Phase.LEAVING:
		phase = Phase.LEAVING
		sees = false
		if heat != null:
			heat.helicopter_sees = false

func _exit_tree() -> void:
	if heat != null:
		heat.helicopter_sees = false

## The stand-in look (header).
func _build() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color("#1B2A4A")
	body_mat.roughness = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#0E1424")
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 1.1
	bm.height = 4.4
	body.mesh = bm
	body.rotation_degrees = Vector3(90, 0, 0)
	body.material_override = body_mat
	add_child(body)
	var boom := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.35, 0.4, 5.0)
	boom.mesh = tm
	boom.position = Vector3(0, 0.3, 4.2)
	boom.material_override = body_mat
	add_child(boom)
	var fin := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.1, 1.2, 0.7)
	fin.mesh = fm
	fin.position = Vector3(0, 0.8, 6.5)
	fin.material_override = body_mat
	add_child(fin)
	for sx in [-0.8, 0.8]:
		var skid := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.12, 0.12, 3.6)
		skid.mesh = sm
		skid.position = Vector3(sx, -1.5, 0)
		skid.material_override = dark
		add_child(skid)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 1.35, 0)
	add_child(_rotor)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 5.5
	dm.bottom_radius = 5.5
	dm.height = 0.04
	dm.radial_segments = 24
	disc.mesh = dm
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.05, 0.06, 0.09, 0.35)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = disc_mat
	_rotor.add_child(disc)
	var blade := MeshInstance3D.new()
	var blm := BoxMesh.new()
	blm.size = Vector3(11.0, 0.05, 0.3)
	blade.mesh = blm
	blade.material_override = dark
	_rotor.add_child(blade)
	# a red lamp on the tail, police blue under the nose
	for lamp in [[Vector3(0, 1.0, 6.9), Color("#C0281E")], [Vector3(0, -1.0, -1.8), Color("#2E4FD8")]]:
		var m := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.15
		sp.height = 0.3
		m.mesh = sp
		var lm := StandardMaterial3D.new()
		lm.albedo_color = lamp[1]
		lm.emission_enabled = true
		lm.emission = lamp[1]
		lm.emission_energy_multiplier = 3.0
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = lm
		m.position = lamp[0]
		add_child(m)
	light = SpotLight3D.new()
	light.name = "Searchlight"
	light.position = Vector3(0, -1.3, -1.5)
	light.spot_range = LIGHT_RANGE
	light.spot_angle = LIGHT_ANGLE
	light.light_energy = 6.0
	light.light_color = Color("#FFF1D8")
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
