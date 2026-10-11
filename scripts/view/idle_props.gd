class_name IdleProps
extends Node3D

# The things the driver's left hand uses on the idle action key (L,
# IdleActions): a vape and a beer can, the pocket on the driver's door they
# live in, and the vape's cloud. Built from code with CockpitKit, no assets.
# A child of the DriverModel (car space), which moves the item with the hand
# through place() and asks for the cloud with exhale().
#
# No cabin has a cup holder, so both items stand in one open pocket low on the
# driver's door card, forward of the armrest, where the left hand reaches down
# for them. Only the chosen item is in the car.
#
# The vape: a small dark stick with a silver band and an amber LED at the far
# end that brightens on the draw. The can: navy with a sodium band and an amber
# mark, a made-up label with no text.
#
# The cloud: at most MAX_PUFFS soft billboards in one MultiMesh with one
# material, pooled (nothing is allocated on a press).
#   window shut: thin, hangs low in the cabin for about SHUT_LIFE seconds;
#   window open: goes out of the gap and the wind takes it back along the car,
#                faster with speed.
# Either way a puff ahead of the driver is held under SIGHT_KEEP_DEG below the
# eye, top edge included, so it never gets into the road view
# (tests/view/idle_actions.gd checks 8 degrees inside 20 degrees of straight ahead).

const VAPE_BODY := Color("#14161B")
const VAPE_TIP := Color("#0C0D10")
const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const NAVY := Color("#1B2A4A")
const POCKET := Color("#16181D")
const POCKET_IN := Color("#0B0C0F")
## Grey-amber: smoke lit by the dash.
const SMOKE := Color(0.78, 0.71, 0.60)

const CAN_R := 0.031
const CAN_HALF := 0.0575
## The hand's origin over the pocket floor when it holds an item standing in it.
const STAND := 0.085
const LED_IDLE := 0.35
const LED_DRAW := 3.2

const MAX_PUFFS := 10
const EXHALE_PUFFS := 8
const EXHALE_GAP := 0.05         # seconds between puffs
const SHUT_LIFE := 2.0
const OPEN_LIFE := 1.4
const SHUT_ALPHA := 0.13
const OPEN_ALPHA := 0.30
const PUFF_R0 := 0.03
const PUFF_R1 := 0.09
const SIGHT_KEEP_DEG := 12.0
const LOW_CABIN := 0.09          # a shut-window puff's top stays this far under the eye
## Where the breath leaves, from the eye.
const MOUTH := Vector3(0.0, -0.10, -0.12)

var driver: DriverModel
var cab: Dictionary
var pocket: MeshInstance3D
var vape: MeshInstance3D
var led: MeshInstance3D
var can: MeshInstance3D
var cloud: MultiMeshInstance3D
var tri_count := 0
var exhales := 0                 # clouds asked for (tests)
var _pocket_floor := Vector3.ZERO
var _led_mat: ShaderMaterial
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _out := PackedByteArray()    # 1 once the puff is past the door line
var _emit_left := 0
var _emit_t := 0.0
var _open := false
var _alive := 0
var _seed := 1

func _init(model: DriverModel) -> void:
	driver = model
	cab = model.frame.cab
	name = "IdleProps"

func _ready() -> void:
	var eye: Vector3 = cab.eye
	var door := minf(float(cab.door_x), float(cab.get("door_x_front", cab.door_x)))
	_pocket_floor = Vector3(-(door - 0.043), float(cab.seat_h) + 0.10, eye.z - 0.47)
	var mat := CockpitKit.material(0.6, 0.0, 0.15)
	var k := CockpitKit.new()
	# open on top: the cup's open face (+z) turned up
	k.cup(Vector3(0.08, 0.075, 0.045), _pocket_floor + Vector3(0.0, 0.0225, 0.0), Basis(Vector3.RIGHT, -PI / 2.0), POCKET, POCKET_IN, 0.037, 0.006)
	pocket = _part(k, mat, "DoorPocket")
	k = CockpitKit.new()
	_vape_mesh(k)
	vape = _part(k, mat, "Vape")
	k = CockpitKit.new()
	_led_mesh(k)
	_led_mat = CockpitKit.glow_material(LED_IDLE)
	tri_count += k.tri_count()
	led = k.instance(_led_mat, "VapeLed")
	vape.add_child(led)
	k = CockpitKit.new()
	_can_mesh(k)
	can = _part(k, mat, "Can")
	_build_cloud()
	place("", Transform3D(), 0.0)

func _part(kit: CockpitKit, mat: Material, node_name: String) -> MeshInstance3D:
	tri_count += kit.tri_count()
	var mi := kit.instance(mat, node_name)
	add_child(mi)
	return mi

## Hand space (DriverModel._hold_mesh): the stick runs along local y through
## the grip, the mouthpiece at +y, the LED at the far end.
static func _vape_mesh(k: CockpitKit) -> void:
	k.box(Vector3(0.024, 0.105, 0.014), Vector3(0.0, -0.0225, 0.0), VAPE_BODY)   # the far 4 cm stand clear of the fingers
	k.box(Vector3(0.025, 0.006, 0.015), Vector3(0.0, 0.03, 0.0), SILVER)
	k.box(Vector3(0.012, 0.02, 0.009), Vector3(0.0, 0.044, 0.0), VAPE_TIP)

static func _led_mesh(k: CockpitKit) -> void:
	k.box(Vector3(0.012, 0.003, 0.008), Vector3(0.0, -0.0765, 0.0), AMBER)        # the end cap
	k.box(Vector3(0.006, 0.024, 0.002), Vector3(0.0, -0.058, -0.0078), AMBER)     # a strip on the face that looks up at the driver

## The can stands along local y, centred on the grip.
static func _can_mesh(k: CockpitKit) -> void:
	k.cylinder(CAN_R, -CAN_HALF, CAN_HALF, Vector3.ZERO, NAVY, 8)
	k.cylinder(CAN_R + 0.0006, -0.03, 0.022, Vector3.ZERO, SODIUM, 8)             # the label band
	k.box(Vector3(0.012, 0.02, 0.002), Vector3(0.0, -0.004, -(CAN_R + 0.0006)), AMBER, Basis(Vector3.BACK, PI / 4.0))   # its mark
	var h := 0.018
	var y := CAN_HALF + 0.0004
	k.quad(Vector3(-h, y, -h), Vector3(-h, y, h), Vector3(h, y, h), Vector3(h, y, -h), SILVER)   # the lid

func _build_cloud() -> void:
	_pos.resize(MAX_PUFFS)
	_vel.resize(MAX_PUFFS)
	_age.resize(MAX_PUFFS)
	_life.resize(MAX_PUFFS)
	_out.resize(MAX_PUFFS)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX_PUFFS
	mm.visible_instance_count = 0
	cloud = MultiMeshInstance3D.new()
	cloud.name = "VapeCloud"
	cloud.multimesh = mm
	cloud.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every drawn frame, in car space
	cloud.custom_aabb = AABB(Vector3(-4.0, -1.0, -3.0), Vector3(8.0, 4.0, 45.0))   # it trails back along the car
	add_child(cloud)

## The hand's transform when it holds an item standing in the pocket (car space).
func holder_xf() -> Transform3D:
	return Transform3D(Basis.IDENTITY, _pocket_floor + Vector3(0.0, STAND, 0.0))

## Each frame from the driver: `held` is the item in the hand ("" for none) at
## `hand`; `draw` 0..1 is how hard the vape is being drawn on.
func place(held: String, hand: Transform3D, draw: float) -> void:
	var item := IdleActions.item
	var rest := holder_xf()
	vape.visible = held == IdleActions.VAPE or (held == "" and item == IdleActions.VAPE)
	vape.transform = hand if held == IdleActions.VAPE else rest
	can.visible = held == IdleActions.BEER or (held == "" and item == IdleActions.BEER)
	can.transform = hand if held == IdleActions.BEER else rest
	_led_mat.set_shader_parameter("energy", lerpf(LED_IDLE, LED_DRAW, clampf(draw, 0.0, 1.0)))

## Breathe out one cloud; `open` sends it out of the side window.
func exhale(open: bool) -> void:
	exhales += 1
	_open = open
	_emit_left = EXHALE_PUFFS
	_emit_t = 0.0

func puff_count() -> int:
	return _alive

## Live puffs for tests: [position (car space), radius] each.
func puffs() -> Array:
	var list := []
	for i in MAX_PUFFS:
		if _life[i] > 0.0:
			list.append([_pos[i], _radius(i)])
	return list

func _radius(i: int) -> float:
	return lerpf(PUFF_R0, PUFF_R1, clampf(_age[i] / _life[i], 0.0, 1.0))

## A cheap repeatable 0..1 (no allocation, same cloud every time).
func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed % 10007) / 10006.0

func _emit() -> void:
	for i in MAX_PUFFS:
		if _life[i] > 0.0:
			continue
		var eye: Vector3 = cab.eye
		var jitter := Vector3(_rand() - 0.5, _rand() - 0.5, _rand() - 0.5)
		_pos[i] = eye + MOUTH + jitter * 0.02
		_vel[i] = (Vector3(-1.1, -0.1, -0.25) if _open else Vector3(0.0, -0.12, -0.75)) + jitter * 0.3
		_age[i] = 0.0
		_life[i] = (OPEN_LIFE if _open else SHUT_LIFE) * (0.85 + 0.15 * _rand())
		_out[i] = 0
		return

func _process(delta: float) -> void:
	if _emit_left > 0:
		_emit_t -= delta
		if _emit_t <= 0.0:
			_emit_t = EXHALE_GAP
			_emit_left -= 1
			_emit()
	elif _alive == 0:
		return
	var eye: Vector3 = cab.eye
	var door := driver.door_line()
	var speed := maxf(driver.player.current_speed(), 0.0)
	var gap := Vector3(-(door + 0.10), maxf(driver.frame.glass_bottom + 0.08, eye.y - 0.14), eye.z - 0.08)
	var keep := tan(deg_to_rad(SIGHT_KEEP_DEG))
	var mm := cloud.multimesh
	var n := 0
	for i in MAX_PUFFS:
		if _life[i] <= 0.0:
			continue
		_age[i] += delta
		if _age[i] >= _life[i]:
			_life[i] = 0.0
			continue
		var p := _pos[i]
		var v := _vel[i]
		var r := _radius(i)
		if _open:
			if _out[i] == 0 and p.x < -door:
				_out[i] = 1
			if _out[i] == 1:
				v = v.lerp(Vector3(-0.3, 0.15, 0.2 + speed * 0.9), 1.0 - exp(-6.0 * delta))   # the wind has it
			else:
				v = v.lerp((gap - p).normalized() * 1.6, 1.0 - exp(-8.0 * delta))
		else:
			v *= exp(-2.2 * delta)
		p += v * delta
		if _out[i] == 0:
			# inside: under the sight line ahead of the driver, and with the window shut low in the cabin
			var rel := p - eye
			if rel.z < 0.05:
				p.y = minf(p.y, eye.y - keep * Vector2(rel.x, rel.z).length() - r)
			if not _open:
				p.y = minf(p.y, eye.y - LOW_CABIN - r)
				p.x = clampf(p.x, -(door - r), door - r)
				p.z = maxf(p.z, float(cab.dash_face_z) + r)
		_pos[i] = p
		_vel[i] = v
		var t := _age[i] / _life[i]
		var a := minf(_age[i] / 0.15, 1.0) * clampf((1.0 - t) * 2.0, 0.0, 1.0) * (OPEN_ALPHA if _open else SHUT_ALPHA)
		mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * r * 2.0), p))
		mm.set_instance_color(n, Color(SMOKE, a))
		n += 1
	_alive = n
	mm.visible_instance_count = n
