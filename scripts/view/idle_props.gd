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

## The cigarette (IdleActions.CIGARETTE): a white stick with a tan filter at the
## mouth end and a tip that glows brighter on every drag; the lighter's flame
## and its small light show for FLAME_SECS while it is lit.
const CIG_PAPER := Color("#D9D2C3")
const CIG_FILTER := Color("#B9782F")
const LIGHTER_BODY := Color(0.18, 0.2, 0.24, 0.05)   # in the glow material: a low alpha reads lit, not bright
const CIG_R := 0.004
const CIG_HALF := 0.04
const PAPER_TOP := 0.014         # where the filter ends and the paper starts (hand space y)
const PAPER_LEN := 0.054         # a whole cigarette's paper
const BURN_END := 0.25           # the butt, as a share of the paper
const FLAME_SECS := 0.4
const FLAME_LIGHT := 0.9         # the one extra light, energy
const TIP_UNLIT := 0.0
const TIP_LIT := 0.9
const TIP_DRAG := 3.6
const CIG_PUFFS := 3             # puffs per drag
const CIG_FLICK_LOCAL_Y := -0.14  # the window gap, below the eye

## The pocket's centre at least this far behind the dash face's centre line
## (the face is 12 cm deep; the pocket 7.5 cm long).
const POCKET_FROM_DASH := 0.10
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
## A shut-window puff stays this far behind the wheel's centre (the rim's tube and its tilt).
const WHEEL_CLEAR := 0.06
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
var cig: MeshInstance3D
var lighter: MeshInstance3D      # a child of cig, shown while the flame is up
var flame_light: OmniLight3D
var tri_count := 0
var exhales := 0                 # clouds asked for (tests)
var lighter_clicks := 0          # times the lighter was struck (tests)
var butts_flicked := 0           # ends thrown out of an open window (tests)
var paper: MeshInstance3D        # the cigarette's paper, scaled with how much is left
var tip: MeshInstance3D          # the burning end, riding on the paper's far end
var _burn := 1.0
var _tip_mat: ShaderMaterial
var _click: AudioStreamPlayer
var _flame_t := 0.0
var _lit := false
var _butt_gone := false
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
	# behind the dash's lower face (on the truck and the drift coupe it reached into it)
	_pocket_floor = Vector3(-(door - 0.043), float(cab.seat_h) + float(cab.get("pocket_h", 0.10)), maxf(float(cab.get("pocket_z", eye.z - 0.47)), float(cab.dash_face_z) + POCKET_FROM_DASH))
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
	k = CockpitKit.new()
	_cig_mesh(k)
	cig = _part(k, mat, "Cigarette")
	# the paper is one unit-long box scaled to the cigarette's length, hung from
	# the filter; the tip rides on its far end, so the burn eats toward the mouth
	k = CockpitKit.new()
	k.box(Vector3(2.0 * CIG_R, 1.0, 2.0 * CIG_R), Vector3(0.0, -0.5, 0.0), CIG_PAPER)
	tri_count += k.tri_count()
	paper = k.instance(mat, "CigarettePaper")
	paper.position = Vector3(0.0, PAPER_TOP, 0.0)
	cig.add_child(paper)
	k = CockpitKit.new()
	_tip_mesh(k)
	_tip_mat = CockpitKit.glow_material(TIP_UNLIT)
	tri_count += k.tri_count()
	tip = k.instance(_tip_mat, "CigaretteTip")
	cig.add_child(tip)
	set_burn(1.0)
	k = CockpitKit.new()
	_lighter_mesh(k)
	tri_count += k.tri_count()
	lighter = k.instance(CockpitKit.glow_material(1.6), "Lighter")
	lighter.visible = false
	tip.add_child(lighter)
	flame_light = OmniLight3D.new()
	flame_light.name = "FlameLight"
	flame_light.light_color = AMBER
	flame_light.light_energy = FLAME_LIGHT
	flame_light.omni_range = 0.8
	flame_light.shadow_enabled = false
	flame_light.position = Vector3(0.0, -0.02, 0.012)
	flame_light.visible = false
	tip.add_child(flame_light)
	_click = AudioStreamPlayer.new()
	_click.name = "LighterClick"
	_click.stream = _lighter_stream()
	_click.volume_db = -14.0
	add_child(_click)
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

## Hand space like the vape: the filter at +y (the mouth), the tip at -y.
static func _cig_mesh(k: CockpitKit) -> void:
	k.box(Vector3(2.0 * CIG_R + 0.0006, 0.026, 2.0 * CIG_R + 0.0006), Vector3(0.0, CIG_HALF - 0.013, 0.0), CIG_FILTER)

## The burning end, in the tip node's own space (its origin is the paper's far
## end): its face alpha is the glow, lit by the material's energy.
static func _tip_mesh(k: CockpitKit) -> void:
	k.box(Vector3(2.0 * CIG_R - 0.0004, 0.004, 2.0 * CIG_R - 0.0004), Vector3(0.0, -0.002, 0.0), AMBER)

## A lighter held end-on to the tip (tip space): a small body and the flame above it.
static func _lighter_mesh(k: CockpitKit) -> void:
	k.box(Vector3(0.016, 0.03, 0.009), Vector3(0.0, -0.053, 0.0), LIGHTER_BODY)
	k.box(Vector3(0.005, 0.016, 0.005), Vector3(0.0, -0.03, 0.0), AMBER)

## A lighter strike: a flint scrape and click, then a short soft whoosh, made
## in code (nothing downloaded), once and shared; through the disk cache (#524).
static var _lighter_wav: AudioStreamWAV
static func _lighter_stream() -> AudioStreamWAV:
	if _lighter_wav == null:
		_lighter_wav = AudioDsp.cached("res://scripts/view/idle_props.gd", "lighter", _make_lighter) as AudioStreamWAV
	return _lighter_wav

static func _make_lighter() -> AudioStreamWAV:
	var r := 44100.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 41017
	var n := int(0.32 * r)
	var hi := AudioDsp.bp(r, 3600.0, 3.0)
	var mid := AudioDsp.bp(r, 1500.0, 4.0)
	var low := AudioDsp.bp(r, 380.0, 1.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / r
		var w := rng.randf_range(-1.0, 1.0)
		var scrape := (hi.step(w) * 5.0) * exp(-pow((t - 0.02) / 0.012, 2.0))
		var click := (mid.step(w) * 7.0) * exp(-t * 700.0) + (hi.step(w) * 6.0) * exp(-pow((t - 0.075) / 0.002, 2.0))
		var whoosh := (low.step(w) * 2.2) * exp(-pow((t - 0.15) / 0.07, 2.0))
		s[i] = scrape + click + whoosh
	return AudioDsp.to_wav(AudioDsp.normalise(s, 0.8), int(r), false)

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

## Moves the pocket (and where the items stand in it) by `by`, car space: the
## driver's hand fit (DriverModel._fit_cabin) needs room for the hand above it.
func move_pocket(by: Vector3) -> void:
	_pocket_floor += by
	pocket.position += by

## The item's mesh (VAPE, BEER or CIGARETTE).
func item_mesh(item: String) -> MeshInstance3D:
	return {IdleActions.VAPE: vape, IdleActions.BEER: can, IdleActions.CIGARETTE: cig}[item]

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
	if held == "" and (_burn < 1.0 or _butt_gone):
		cigarette_reset()   # the hand is empty: the next cigarette waits whole in the pocket
	cig.visible = (held == IdleActions.CIGARETTE and not _butt_gone) or (held == "" and item == IdleActions.CIGARETTE)
	cig.transform = hand if held == IdleActions.CIGARETTE else rest
	var d := clampf(draw, 0.0, 1.0)
	_led_mat.set_shader_parameter("energy", lerpf(LED_IDLE, LED_DRAW, d))
	_tip_mat.set_shader_parameter("energy", lerpf(TIP_LIT, TIP_DRAG, d) if _lit and held == IdleActions.CIGARETTE else TIP_UNLIT)

## Breathe out one cloud; `open` sends it out of the side window.
func exhale(open: bool, puffs := EXHALE_PUFFS) -> void:
	exhales += 1
	_open = open
	_emit_left = puffs
	_emit_t = 0.0

## A fresh cigarette is in the hand: unlit, and the end is back.
func cigarette_reset() -> void:
	_lit = false
	_butt_gone = false
	_flame_t = 0.0
	_show_flame(false)
	set_burn(1.0)

## How much cigarette is left, 1 whole .. BURN_END the butt. It is the only
## "health bar" there is: the paper's visible length, the tip riding on its end.
func set_burn(left: float) -> void:
	_burn = clampf(left, BURN_END, 1.0)
	var len := PAPER_LEN * _burn
	paper.scale = Vector3(1.0, len, 1.0)
	tip.position = Vector3(0.0, PAPER_TOP - len, 0.0)

func burn_left() -> float:
	return _burn

## The lighter: a click, a small flame for FLAME_SECS, and the tip catches.
func light_up() -> void:
	lighter_clicks += 1
	_lit = true
	_flame_t = FLAME_SECS
	_show_flame(true)
	if _click.is_inside_tree():
		_click.play()

## The butt goes out of the window, always (the driver rolled it down for the
## cigarette): the same ember as the traffic flick, from the same burst.
func flick_butt() -> void:
	_butt_gone = true
	_lit = false
	_show_flame(false)
	butts_flicked += 1
	var eye: Vector3 = cab.eye
	var local := Vector3(-(driver.door_line() + 0.10), eye.y + CIG_FLICK_LOCAL_Y, eye.z - 0.08)
	if EmberFlick.current != null and is_instance_valid(EmberFlick.current):
		EmberFlick.current.flick_from_player(driver.player, local, driver.player.linear_velocity)

func is_lit() -> bool:
	return _lit

func flame_up() -> bool:
	return _flame_t > 0.0

func _show_flame(on: bool) -> void:
	lighter.visible = on
	flame_light.visible = on

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
	if _flame_t > 0.0:
		_flame_t = maxf(_flame_t - delta, 0.0)
		if _flame_t <= 0.0:
			_show_flame(false)
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
				p.z = maxf(p.z, maxf(float(cab.dash_face_z), (cab.wheel as Vector3).z + WHEEL_CLEAR) + r)   # and behind the wheel, not through its rim
		_pos[i] = p
		_vel[i] = v
		var t := _age[i] / _life[i]
		var a := minf(_age[i] / 0.15, 1.0) * clampf((1.0 - t) * 2.0, 0.0, 1.0) * (OPEN_ALPHA if _open else SHUT_ALPHA)
		mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * r * 2.0), p))
		mm.set_instance_color(n, Color(SMOKE, a))
		n += 1
	_alive = n
	mm.visible_instance_count = n

## The cigarette tip's current glow energy (tests).
func tip_energy() -> float:
	return float(_tip_mat.get_shader_parameter("energy"))
