class_name TitleKerbside
extends Node3D

# The title screen's scene ("Kerbside", 2026-10-10): the player's own car parked
# at the kerb under one sodium street lamp, at night, seen from the road.
#
# It is a small set of its own, built far below the road (SITE), so while the
# title is up the camera sees only this: a strip of asphalt, the kerb, the
# sidewalk, a wall, one lamp and one car. The loaded world is out of the
# camera's range and is not drawn, which is what keeps the title cheap. The car
# is a copy of the player's car body and wheels with no physics and no script.
# One real light (the lamp, no shadows); the shadow under the car is a dark
# quad. The title screen frees the whole set when the drive starts.

const SITE := Vector3(0.0, -600.0, 0.0)
const SODIUM_LIGHT := Color(1.0, 0.62, 0.3)
const STREET_LEN := 90.0
const ROAD_W := 30.0
const WALL_H := 7.0
const CAM_FAR := 110.0
const CAM_FOV := 48.0
## The camera breathes a little so the picture is not a still.
const SWAY_M := 0.18
const SWAY_SECS := 17.0

var kind := ""
var camera: Camera3D
var car: Node3D
var lamp_light: SpotLight3D
var _t := 0.0
var _cam_home := Vector3.ZERO
var _look := Vector3.ZERO

func _init(car_kind: String) -> void:
	name = "TitleKerbside"
	kind = car_kind
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = SITE
	_build_street()
	_build_lamp()
	set_car(car_kind)
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	camera.near = 0.2
	camera.far = CAM_FAR
	add_child(camera)

func _ready() -> void:
	_place_camera()

## A copy of a player car to look at: body and four wheels, origin on the
## ground, nose toward -Z. No physics and no script.
static func build_car(car_kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "TitleCar"
	var hubs: Array[Vector3] = []
	if NpcCarBuilder.is_npc(car_kind):
		var k: Dictionary = NpcCarBuilder.KINDS[car_kind]
		var vis := NpcCarBuilder.chassis_visual(car_kind, "stock", NpcCarBuilder.sheet_paint(car_kind))
		vis.position.y = float(k.rest_y)
		root.add_child(vis)
		for sx: float in [1.0, -1.0]:
			for sz: float in [-1.0, 1.0]:
				var hub := Vector3(float(k.wheel_x) * sx, float(k.wheel_r), float(k.axle_z) * sz)
				var wheel := NpcCarBuilder.wheel_visual(car_kind, "stock", hub)
				wheel.position = hub
				root.add_child(wheel)
				hubs.append(hub)
	else:
		# The coupe, and anything that wears the coupe's body.
		var vis := P1CoupeBuilder.build_chassis_visual()
		vis.position.y = -P1CoupeBuilder.BODY_LIFT
		root.add_child(vis)
		for sx: float in [1.0, -1.0]:
			for sz: float in [-1.0, 1.0]:
				var hub := Vector3(P1CoupeBuilder.DESIGN_WHEEL_X * sx, P1CoupeBuilder.DESIGN_WHEEL_R, 1.25 * sz)
				var wheel := P1CoupeBuilder.build_wheel_visual(P1CoupeBuilder.DESIGN_WHEEL_R, hub)
				wheel.position = hub
				root.add_child(wheel)
				hubs.append(hub)
	var half_w := 0.9
	var half_l := 2.2
	for h in hubs:
		half_w = maxf(half_w, absf(h.x) + 0.14)
		half_l = maxf(half_l, absf(h.z) + 0.9)
	root.set_meta("half_w", half_w)
	root.set_meta("half_l", half_l)
	return root

## Parks a copy of this car at the kerb (again, when the player picks another).
func set_car(car_kind: String) -> void:
	if car != null:
		car.queue_free()
	kind = car_kind
	car = build_car(car_kind)
	var half_w: float = car.get_meta("half_w")
	var half_l: float = car.get_meta("half_l")
	car.rotation.y = PI * 0.5                  # along the street, nose toward -X
	car.position = Vector3(0.0, 0.0, half_w + 0.3)
	add_child(car)
	car.add_child(_ground_shadow(half_w, half_l))
	if is_inside_tree():
		_place_camera()

func _place_camera() -> void:
	var half_l: float = car.get_meta("half_l")
	var half_w: float = car.get_meta("half_w")
	# From the road, low, three-quarter front. The car sits right of centre so
	# the name and the menu have the left of the picture.
	# Low and looking up a little, so the lamp head is in the picture too.
	_cam_home = Vector3(-(half_l + 6.0), 0.55, car.position.z + half_w + 7.0)
	_look = Vector3(-half_l - 1.5, 3.0, car.position.z - 2.2)
	_aim()

func _aim() -> void:
	var sway := sin(_t * TAU / SWAY_SECS)
	camera.position = _cam_home + Vector3(sway * SWAY_M, 0.03 * sin(_t * TAU / (SWAY_SECS * 0.61)), 0.0)
	camera.look_at(to_global(_look), Vector3.UP)

func _process(delta: float) -> void:
	if not visible or camera == null or not camera.current:
		return
	_t += delta
	_aim()

func _build_street() -> void:
	# Asphalt: the road, from the kerb out past the camera.
	_slab(Vector3(STREET_LEN, 0.2, ROAD_W), Vector3(0.0, -0.1, ROAD_W * 0.5),
		_flat(Color(0.075, 0.075, 0.08), 0.82))
	# Kerb and sidewalk, at the heights the road chunks use.
	var kerb_h := RoadChunkBuilder.KERB_H
	var kerb_w := RoadChunkBuilder.CURB_W
	var walk_w := RoadChunkBuilder.SIDEWALK_W
	_slab(Vector3(STREET_LEN, kerb_h, kerb_w), Vector3(0.0, kerb_h * 0.5, -kerb_w * 0.5),
		_flat(RoadChunkBuilder.KERB_COLOR, 0.9))
	_slab(Vector3(STREET_LEN, kerb_h, walk_w), Vector3(0.0, kerb_h * 0.5, -kerb_w - walk_w * 0.5),
		_flat(Color(0.2, 0.19, 0.18), 0.95))
	# A blank wall closes the picture behind the sidewalk, with one shutter.
	var wall_z := -kerb_w - walk_w
	_slab(Vector3(STREET_LEN, WALL_H, 0.4), Vector3(0.0, WALL_H * 0.5, wall_z - 0.2),
		_flat(Color(0.16, 0.13, 0.115), 0.95))
	_slab(Vector3(3.6, 2.7, 0.1), Vector3(1.9, kerb_h + 1.35, wall_z + 0.03),
		_flat(Color(0.2, 0.21, 0.22), 0.55, 0.6))
	_slab(Vector3(STREET_LEN, 0.25, 0.5), Vector3(0.0, 3.6, wall_z + 0.05),
		_flat(Color(0.11, 0.09, 0.08), 0.95))

func _build_lamp() -> void:
	var post := MeshInstance3D.new()
	post.mesh = RoadChunkBuilder.lamp_mesh()
	# The mesh's arm reaches toward -X; turn it to reach over the road (+Z).
	post.rotation.y = PI * 0.5
	post.position = Vector3(-1.1, RoadChunkBuilder.KERB_H, -RoadChunkBuilder.LAMP_SETBACK - RoadChunkBuilder.CURB_W)
	add_child(post)
	lamp_light = SpotLight3D.new()
	lamp_light.light_color = SODIUM_LIGHT
	lamp_light.light_energy = 14.0
	lamp_light.spot_range = 16.0
	lamp_light.spot_angle = 58.0
	lamp_light.spot_angle_attenuation = 0.7
	lamp_light.spot_attenuation = 0.8
	lamp_light.shadow_enabled = false
	lamp_light.position = post.position + Vector3(0.0, RoadChunkBuilder.LAMP_POLE_H - 0.3, 1.7)
	lamp_light.rotation.x = -PI * 0.5   # straight down
	add_child(lamp_light)

func _slab(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	add_child(mi)

static func _flat(colour: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m

## The car's shadow under the lamp: a soft dark quad just above the asphalt.
static func _ground_shadow(half_w: float, half_l: float) -> MeshInstance3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.9))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	grad.add_point(0.55, Color(0, 0, 0, 0.8))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = Color(0, 0, 0, 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_w * 2.0 + 0.9, half_l * 2.0 + 0.9)
	var mi := MeshInstance3D.new()
	mi.name = "GroundShadow"
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = 0.012
	return mi
