extends Node3D

# The totalled look, step 2 (Roy 1560 and 1561, 2026-10-14): parts that hang,
# fall off and leak as the totalled meter fills. Reads the look stage
# (CarDamage.look_stage, scripts/car/wreck_look.gd) each physics tick and acts
# only when it changes, so a tick costs one int compare.
#
#   stage 2 (60 %)  the front bumper hangs loose, dropped on the side that
#                   took the hit (the dark lamp's side), and the bonnet is
#                   buckled: lifted a few degrees at its hinge with a twist
#   stage 3 (90 %)  the bumper falls off: it drops onto the road as a loose
#                   body with the car's speed, tumbles, and is gone after
#                   DROP_LIFE seconds; a dark puddle spreads under the nose
#                   whenever the car stands still
#   stage 0         (the garage, F6) everything back as the glb has it
#
# Cars built from parts only (CarAssembler): the bumper and the bonnet are
# real parts there, taken out of the merged body with swap_part and drawn
# as their own mesh while loose. A sheet car has no parts: nothing happens
# on it (the smoke and sparks still do, TyreSmoke). The dark lamp's side is
# the hit side: a hit from the right drops the bumper's right end.
#
# Cost: stage 2 adds two draw calls (the loose bumper and the bonnet), stage
# 3 one (the bonnet) plus the dropped bumper for DROP_LIFE seconds and the
# puddle decal while it shows. Meshes come from CarAssembler's cache. The
# re-merge when a part leaves or returns runs once per stage change.
#
# Lives in the FxPack (not on the car) so the dropped bumper, laid in world
# space, gets the floating-origin shift with the skid marks (shift_world).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const BUMPER := "bumper_f"
const HOOD := "hood"
const HOOD_HINGE := "hinge_hood"
## The bumper's loose end drops this far (degrees, about the car's length
## axis) and its bottom swings forward this far (about the width axis).
const HANG_DEG := 14.0
const HANG_TILT_DEG := 6.0
## The bonnet rises this far at its hinge, with this twist toward the hit side.
const BUCKLE_DEG := 7.0
const BUCKLE_TWIST_DEG := 2.5
## The stage the parts start hanging at, and the stage the bumper falls off.
const HANG_STAGE := 2
const DROP_STAGE := 3
## The dropped bumper: a light loose body, gone after DROP_LIFE seconds.
const DROP_MASS := 9.0
const DROP_LIFE := 8.0
## The puddle: grows to PUDDLE_SIZE m across over PUDDLE_GROW_S seconds of
## standing still under PUDDLE_STILL_MS, shrinks PUDDLE_SHRINK x faster on
## the move.
const PUDDLE_STAGE := 3
const PUDDLE_SIZE := 1.3
const PUDDLE_GROW_S := 5.0
const PUDDLE_SHRINK := 4.0
const PUDDLE_STILL_MS := 0.6
const PUDDLE_COLOUR := Color(0.03, 0.025, 0.02, 0.85)   # black oil with a brown edge of sodium in it
const PUDDLE_TEX := 32

var player: PlayerCar
## The stage the parts are showing (what was last applied).
var shown := 0
## Nodes while they exist: the loose bumper and the buckled bonnet on the body,
## the dropped bumper in the world, the puddle on the car.
var loose_bumper: MeshInstance3D
var hood: MeshInstance3D
var dropped: RigidBody3D
var puddle: Decal
## How far the puddle has spread, 0..1.
var puddle_spread := 0.0
var drops := 0   # bumpers that fell off (tests)
var _drop_left := 0.0
static var _puddle_tex: ImageTexture

func _init(p: PlayerCar) -> void:
	player = p
	name = "WreckParts"

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var st: int = player.damage.look_stage()
	if st != shown:
		_apply(st)
	_step_drop(delta)
	_step_puddle(delta, st)

## True when the car driven is built from parts and has a front bumper.
func has_parts() -> bool:
	var body := CarAssembler.body_of(player.chassis_visual)
	return body != null and CarAssembler.part_names(body.get_meta("car_id")).has(BUMPER)

## The hit side the bumper hangs from: +1 right, -1 left (the dark lamp's side).
func hit_side() -> float:
	return 1.0 if player.damage.head_lamp_dark(1) and not player.damage.head_lamp_dark(0) else -1.0

func _apply(st: int) -> void:
	shown = st
	var body := CarAssembler.body_of(player.chassis_visual)
	if body == null:
		return
	if st < HANG_STAGE:
		# back as the glb has it (the garage, F6, a new car)
		_free_node(loose_bumper)
		loose_bumper = null
		_free_node(hood)
		hood = null
		CarAssembler.restore_part(body, BUMPER)
		CarAssembler.restore_part(body, HOOD)
		return
	if st >= HANG_STAGE and hood == null:
		_hang_bumper(body)
		_buckle_hood(body)
	# (a station patch taking a stage-3 car back to 2 leaves the bumper gone)
	if st >= DROP_STAGE and loose_bumper != null:
		_drop_bumper(body)

## The bumper leaves the body and hangs from its far end, dropped on the hit side.
func _hang_bumper(body: MeshInstance3D) -> void:
	var car_id: String = body.get_meta("car_id")
	var box := CarAssembler.part_aabb(car_id, BUMPER)
	if box.size == Vector3.ZERO:
		return
	var side := hit_side()
	var pivot := _pivot_of(box)
	var mesh := CarAssembler.part_mesh(car_id, BUMPER, pivot)
	if mesh == null:
		return
	CarAssembler.swap_part(body, BUMPER, null)
	loose_bumper = _loose(body, mesh, "LooseBumper")
	loose_bumper.position = pivot
	# the hit end drops: about +Z a point at +x rises, so the sign is the other way
	loose_bumper.rotation = Vector3(deg_to_rad(HANG_TILT_DEG), 0.0, deg_to_rad(-side * HANG_DEG))

## The bonnet lifts a few degrees at its hinge and twists toward the hit side.
func _buckle_hood(body: MeshInstance3D) -> void:
	var car_id: String = body.get_meta("car_id")
	var hinges := CarAssembler.hinges(car_id)
	if not hinges.has(HOOD_HINGE) or not CarAssembler.part_names(car_id).has(HOOD):
		return
	var h: Dictionary = hinges[HOOD_HINGE]
	var mesh := CarAssembler.part_mesh(car_id, HOOD, h.origin)
	if mesh == null:
		return
	CarAssembler.swap_part(body, HOOD, null)
	hood = _loose(body, mesh, "BuckledHood")
	hood.position = h.origin
	hood.rotate(h.axis, deg_to_rad(float(h.open_sign) * BUCKLE_DEG))
	hood.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(-hit_side() * BUCKLE_TWIST_DEG))

## One loose part drawn like the body: its paint material, finish and layer.
func _loose(body: MeshInstance3D, mesh: ArrayMesh, nm: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = nm
	m.mesh = mesh
	m.layers = body.layers
	m.cast_shadow = body.cast_shadow
	var paint := body.get_surface_override_material(CarAssembler.surface_index(body.mesh, "body"))
	if paint != null:
		m.set_surface_override_material(0, paint)
	var finish: Variant = body.get_instance_shader_parameter("finish")
	if finish != null:
		m.set_instance_shader_parameter("finish", finish)
	body.add_child(m)
	return m

## The hanging bumper lets go: a loose body in the world with the car's
## speed, falling and tumbling behind.
func _drop_bumper(body: MeshInstance3D) -> void:
	var xf := loose_bumper.global_transform
	var mesh := loose_bumper.mesh as ArrayMesh
	var car_id: String = body.get_meta("car_id")
	var box := CarAssembler.part_aabb(car_id, BUMPER)
	_free_node(loose_bumper)
	loose_bumper = null
	_free_node(dropped)
	dropped = RigidBody3D.new()
	dropped.name = "DroppedBumper"
	dropped.mass = DROP_MASS
	dropped.collision_layer = 0
	dropped.collision_mask = 1 << (CarSpec.WORLD_LAYER - 1)
	dropped.continuous_cd = true
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(box.size.x, maxf(box.size.y, 0.08), maxf(box.size.z, 0.08))
	shape.shape = bs
	# the mesh is pivoted on the bumper's top edge at one end: put the shape on the part
	shape.position = box.get_center() - _pivot_of(box)
	dropped.add_child(shape)
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.layers = body.layers
	var paint := body.get_surface_override_material(CarAssembler.surface_index(body.mesh, "body"))
	if paint != null:
		m.set_surface_override_material(0, paint)
	dropped.add_child(m)
	add_child(dropped)
	dropped.global_transform = xf
	dropped.linear_velocity = player.linear_velocity * 0.85
	dropped.angular_velocity = Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-1.0, 1.0))
	_drop_left = DROP_LIFE
	drops += 1

## The pivot the loose bumper hangs from: the top edge at the end that stays
## bolted on, the side away from the hit.
func _pivot_of(box: AABB) -> Vector3:
	var side := hit_side()
	return Vector3(-side * (box.size.x * 0.5 - 0.05) + box.get_center().x, box.end.y, box.get_center().z)

func _step_drop(delta: float) -> void:
	if dropped == null:
		return
	_drop_left -= delta
	if _drop_left <= 0.0 or not is_instance_valid(dropped):
		_free_node(dropped)
		dropped = null

## The puddle: a decal under the nose that spreads while the car stands
## still at stage 3 or over, and is gone again once it drives on (the oil
## that was under the car stays where the car was, in spirit; one decal).
func _step_puddle(delta: float, st: int) -> void:
	var still := st >= PUDDLE_STAGE and player.speed < PUDDLE_STILL_MS
	var target := 1.0 if still else 0.0
	if puddle_spread == target:
		return
	var rate := delta / PUDDLE_GROW_S * (1.0 if still else PUDDLE_SHRINK)
	puddle_spread = move_toward(puddle_spread, target, rate)
	if puddle == null:
		if puddle_spread <= 0.0:
			return
		puddle = Decal.new()
		puddle.name = "WreckPuddle"
		puddle.texture_albedo = _get_puddle_tex()
		puddle.modulate = PUDDLE_COLOUR
		puddle.cull_mask = 1   # the road, not the car
		puddle.albedo_mix = 1.0
		puddle.position = Vector3(0.0, 0.25, 0.0)
		player.add_child(puddle)
	if puddle_spread <= 0.0:
		puddle.visible = false
		return
	var half_l := 2.2
	if player.chassis_visual != null:
		half_l = float(player.chassis_visual.get_meta("half_l", 2.2))
	var across := PUDDLE_SIZE * sqrt(puddle_spread)
	puddle.visible = true
	puddle.size = Vector3(across, 1.4, across * 1.25)
	puddle.position = Vector3(0.0, 0.25, -(half_l * 0.55))
	puddle.modulate = Color(PUDDLE_COLOUR, PUDDLE_COLOUR.a * minf(puddle_spread * 3.0, 1.0))

static func _get_puddle_tex() -> ImageTexture:
	if _puddle_tex == null:
		var img := Image.create(PUDDLE_TEX, PUDDLE_TEX, false, Image.FORMAT_RGBA8)
		for y in PUDDLE_TEX:
			for x in PUDDLE_TEX:
				var u := (float(x) + 0.5) / PUDDLE_TEX * 2.0 - 1.0
				var v := (float(y) + 0.5) / PUDDLE_TEX * 2.0 - 1.0
				# a lopsided blob: fuller to one side, soft edge
				var d := Vector2(u * (1.0 + 0.25 * v), v).length()
				var a := 1.0 - smoothstep(0.55, 1.0, d)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		_puddle_tex = ImageTexture.create_from_image(img)
	return _puddle_tex

## Floating-origin recentre (FxPack.shift_world): the dropped bumper lies in
## world space.
func shift_world(offset: Vector3) -> void:
	if dropped != null and is_instance_valid(dropped):
		dropped.global_position += offset
		dropped.reset_physics_interpolation()

func _free_node(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.get_parent().remove_child(n)
		n.queue_free()
