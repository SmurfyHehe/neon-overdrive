class_name CockpitMirrors
extends Node3D

# Live mirrors for the cockpit view (2026-10-06): a rearview mirror and the two
# door mirrors, each a SubViewport with its own Camera3D drawn onto a quad,
# flipped left-to-right like glass. Budgeted for the i5-1235U:
#   - they only render in the cockpit view (UPDATE_DISABLED otherwise);
#   - small render targets (rear 320x96, sides 160x112 at medium quality;
#     FxSettings.mirror_quality halves or doubles them);
#   - the rearview renders on even frames, both door mirrors on odd frames;
#   - the cameras see the world, traffic and the player's own body (the layer
#     the cockpit camera does not draw), never the interior or the driver, with
#     a 250 m far clip and no glow pass.
# FxSettings "mirrors" off leaves dark glass and never renders.
# A mirror whose glass is outside the cockpit camera's view is not rendered
# at all (2026-10-07: on the P1 the right door mirror sits 58 degrees right of
# the eye, off screen at every FOV unless the driver looks round to it). The
# mirror the driver has turned to (ChaseCamera look around) renders every frame at
# twice the resolution.
# Blind-spot dots (2026-10-07): each door mirror has a small amber dot in its
# outer top corner that lights while a same-direction car is alongside or
# just behind on that side (Hud.side_threat drives it, 0..1). The dot shows
# even with mirrors off.
# The HUD's rear strip (chase view) reuses the rearview render: with `strip`
# on and the cockpit off, only the rear camera renders, every other frame.
#
# Car space, like the rest of the cockpit. The glass is angled so the camera's
# straight-back view is what the driver's eye would see reflected.

const FAR := 250.0
const NEAR := 0.25
const REAR_SIZE := Vector2i(320, 96)
const SIDE_SIZE := Vector2i(160, 112)
const REAR_FOV := 18.0      # vertical; with the 10:3 glass that is ~56 deg wide
const SIDE_FOV := 30.0      # ~42 deg wide on the 10:7 door glass
const SIDE_YAW := 8.0       # degrees outward from straight back
const SIDE_PITCH := -2.0
const GLASS_TINT := Color(0.86, 0.87, 0.92)
## Proximity cue (2026-10-06): the rearview glass warms toward sodium as a
## car closes in behind (Hud.rear_threat drives it, 0..1).
const CUE_TINT := Color(1.0, 0.72, 0.38)
var rear_cue := 0.0
const DOT_COLOUR := Color("#FFC066")   # amber
const DOT_RADIUS := 0.0075
const DOT_ON := 0.35                   # side cue level that lights the dot
var side_cue := [0.0, 0.0]             # left, right
const DARK_GLASS := Color("#171A20")

## Rearview glass: centre, size, and the angle that reflects straight back for the eye.
## Rearview glass: top centre of the windscreen (the glass top is y 1.34 at
## z -0.04), hanging a hand below it, small; angled to reflect straight back.
const REAR_POS := Vector3(0.0, 1.22, -0.13)
const REAR_SIZE_M := Vector2(0.19, 0.056)
const REAR_YAW := -23.0
const REAR_PITCH := -8.0
## Door glass angles (yaw about +y, same sense as the housings in P1CoupeBuilder).
const SIDE_GLASS_YAW := [17.0, -26.0]
const SIDE_SIZE_M := Vector2(0.175, 0.098)
## The glass sits this far inside the housing's open face.
const SIDE_INSET := 0.02

var active := false        # the cockpit view is on
var strip := false         # the HUD rear strip wants the rear render (chase view)
var enabled := true        # FxSettings "mirrors"
var views := []            # [{vp, cam, quad, mat}] rear, left, right
var _frame := 0
var focus := 0             # -1 left door mirror, +1 right, 0 none (ChaseCamera look around)
var dots := []             # [left, right] MeshInstance3D
var cull_mask := 0

func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)
	enabled = FxSettings.is_on("mirrors")
	var env: Environment = null
	var world := get_viewport().find_world_3d()
	if world != null and world.environment != null:
		env = world.environment.duplicate()
		env.glow_enabled = false
	_add_mirror("Rear", REAR_POS, REAR_SIZE_M, REAR_YAW, REAR_PITCH, REAR_SIZE, REAR_FOV, 0.0, env)
	for i in 2:
		var h: Dictionary = P1CoupeBuilder.MIRRORS[i]
		var pos: Vector3 = h.pos + Vector3(0.0, P1CoupeBuilder.BODY_LIFT, 0.0)
		var hb := Basis(Vector3.UP, deg_to_rad(float(h.yaw)))
		var glass_pos := pos + hb * Vector3(0.0, 0.0, P1CoupeBuilder.MIRROR_SIZE.z * 0.5 - SIDE_INSET)
		var out := -1.0 if i == 0 else 1.0
		_add_mirror("Left" if i == 0 else "Right", glass_pos, SIDE_SIZE_M, float(SIDE_GLASS_YAW[i]), 0.0,
			SIDE_SIZE, SIDE_FOV, out * SIDE_YAW, env)
		_add_dot(views[i + 1].quad, out)
	_apply_enabled()

## The blind-spot dot: a small amber bead just proud of the glass in its
## outer top corner (glass-local +x is the car's +x, so outer is `out`).
func _add_dot(glass: MeshInstance3D, out: float) -> void:
	var dot := MeshInstance3D.new()
	dot.name = "BlindSpotDot"
	var sm := SphereMesh.new()
	sm.radius = DOT_RADIUS
	sm.height = DOT_RADIUS * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	dot.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = DOT_COLOUR
	dot.material_override = mat
	dot.position = Vector3(out * (SIDE_SIZE_M.x * 0.5 - 0.02), SIDE_SIZE_M.y * 0.5 - 0.018, 0.004)
	dot.layers = CockpitFrame.INTERIOR_BIT
	dot.visible = false
	glass.add_child(dot)
	dots.append(dot)

static func _scaled(base: Vector2i) -> Vector2i:
	var k := FxSettings.mirror_scale()
	return Vector2i(maxi(16, int(base.x * k)), maxi(16, int(base.y * k)))

func _add_mirror(mirror_name: String, pos: Vector3, size_m: Vector2, yaw_deg: float, pitch_deg: float,
		base_px: Vector2i, fov: float, cam_yaw_out: float, env: Environment) -> void:
	var vp := SubViewport.new()
	vp.name = mirror_name + "View"
	vp.size = _scaled(base_px)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = 0
	vp.transparent_bg = false
	add_child(vp)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = fov
	cam.near = NEAR
	cam.far = FAR
	cam.cull_mask = cull_mask
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if env != null:
		cam.environment = env
	vp.add_child(cam)
	# The camera sits in car space at the glass, looking straight back (+z is
	# the car's rear), yawed outward for the door mirrors. A SubViewport is not
	# a Node3D, so its camera does not inherit this node's transform: the
	# car-local transform is kept and applied every frame in _process.
	var local := Transform3D(Basis.from_euler(Vector3(deg_to_rad(SIDE_PITCH if cam_yaw_out != 0.0 else 0.0), deg_to_rad(180.0 - cam_yaw_out), 0.0)), pos)
	cam.current = true

	var quad := MeshInstance3D.new()
	quad.name = mirror_name + "Glass"
	var qm := QuadMesh.new()
	qm.size = size_m
	quad.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = vp.get_texture()
	mat.albedo_color = GLASS_TINT
	mat.uv1_scale = Vector3(-1.0, 1.0, 1.0)   # a mirror: left is right
	mat.uv1_offset = Vector3(1.0, 0.0, 0.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material_override = mat
	quad.position = pos
	quad.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0.0)
	quad.layers = CockpitFrame.INTERIOR_BIT
	add_child(quad)
	views.append({"vp": vp, "cam": cam, "quad": quad, "mat": mat, "local": local, "base_px": base_px})
	cam.global_transform = global_transform * local

## Mirror quality changed (a graphics tier, GraphicsSettings.apply): resize
## the renders live.
func apply_graphics() -> void:
	for i in views.size():
		var glanced: bool = i > 0 and focus == (-1 if i == 1 else 1)
		views[i].vp.size = _scaled(views[i].base_px) * (2 if glanced else 1)

## Cockpit view on or off: nothing renders while off, unless the strip asks.
func set_active(on: bool) -> void:
	active = on
	if not on:
		set_focus(0)
		for v in views:
			v.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

## The HUD rear strip on or off (chase view only; the cockpit view has the mirror).
func set_strip(on: bool) -> void:
	strip = on
	if not on and not active:
		views[0].vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

## The door mirror the driver has turned to (-1 left, +1 right, 0 none): it
## renders every frame at twice the resolution until the head turns back.
func set_focus(side: int) -> void:
	if side == focus:
		return
	focus = side
	for i in 2:
		var v: Dictionary = views[i + 1]
		var k := 2 if focus == (-1 if i == 0 else 1) else 1
		v.vp.size = _scaled(SIDE_SIZE) * k

## Lights a door mirror's blind-spot dot: side 0 left, 1 right, level 0..1.
func set_side_cue(side: int, level: float) -> void:
	if side >= 0 and side < side_cue.size():
		side_cue[side] = clampf(level, 0.0, 1.0)
		if side < dots.size():
			dots[side].visible = side_cue[side] >= DOT_ON

## True when some part of a mirror's glass is inside the camera's view.
static func glass_on_screen(cam: Camera3D, glass: MeshInstance3D) -> bool:
	if cam == null:
		return true
	var half := (glass.mesh as QuadMesh).size * 0.5
	var xf := glass.global_transform
	for p in [Vector3.ZERO, Vector3(half.x, half.y, 0.0), Vector3(-half.x, half.y, 0.0),
			Vector3(half.x, -half.y, 0.0), Vector3(-half.x, -half.y, 0.0)]:
		if cam.is_position_in_frustum(xf * p):
			return true
	return false

## The rearview render target, for the HUD strip.
func rear_texture() -> ViewportTexture:
	return views[0].vp.get_texture()

## Warms the rearview glass by `level` (0 = plain glass, 1 = a car right behind).
func set_rear_cue(level: float) -> void:
	rear_cue = clampf(level, 0.0, 1.0)
	if enabled and not views.is_empty():
		views[0].mat.albedo_color = GLASS_TINT.lerp(CUE_TINT, rear_cue)

## The FxSettings flag at runtime (a pause-menu toggle later).
func set_enabled(on: bool) -> void:
	enabled = on
	FxSettings.set_on("mirrors", on)
	_apply_enabled()

func _apply_enabled() -> void:
	for v in views:
		if enabled:
			v.mat.albedo_texture = v.vp.get_texture()
			v.mat.albedo_color = GLASS_TINT
		else:
			v.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			v.mat.albedo_texture = null
			v.mat.albedo_color = DARK_GLASS

## True when a mirror will render on the next draw (tests and the probe).
func is_rendering() -> bool:
	for v in views:
		if v.vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			return true
	return false

## Moves the cameras with the car (drawn on the interpolated transform, like the
## cockpit camera) and queues this frame's mirror.
func _process(_delta: float) -> void:
	if not enabled or views.is_empty() or not (active or strip):
		return
	var xf := get_global_transform_interpolated()
	for v in views:
		v.cam.global_transform = xf * v.local
	_frame += 1
	# UPDATE_ONCE draws on the next frame and drops back to DISABLED by itself.
	# In the cockpit, a mirror off screen is skipped; the door mirror looked at
	# mirror renders every frame.
	var cam := get_viewport().get_camera_3d() if active else null
	if _frame % 2 == 0 and (not active or glass_on_screen(cam, views[0].quad)):
		views[0].vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not active:
		return
	for i in [1, 2]:
		var focused := focus == (-1 if i == 1 else 1)
		if (focused or _frame % 2 == 1) and glass_on_screen(cam, views[i].quad):
			views[i].vp.render_target_update_mode = SubViewport.UPDATE_ONCE
