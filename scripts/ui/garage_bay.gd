class_name GarageBay
extends Node3D

# The garage's room (garage look step 1, 2026-10-14): what the garage screen
# shows behind its buttons. Built the way the title's Kerbside set is: a small
# set of its own far below the road (SITE), so the camera sees only this.
# One bay of Dunmore Auto at night: a concrete floor with an oil stain, the
# back wall with a pegboard and a bench, the roller door half up at the front
# with the sodium street showing under it, one hanging work lamp over the
# player's own car (a copy of its body and wheels, no physics), and the
# night's cool air coming in the door as a dim blue fill. The lamp is the one
# light with a shadow (off on Low, as on the title); the street glow and the
# door fill never shadow.
#
# Lives while the garage is open (GarageScreen builds it on the way in and
# frees it on the way out), so the room costs nothing on the road.

const SITE := Vector3(0.0, -650.0, 0.0)
const ROOM_W := 9.0
const ROOM_D := 11.0
const ROOM_H := 4.2
## The front wall (the door) is at -Z, the car's nose toward it.
const DOOR_Z := -ROOM_D * 0.5
const DOOR_W := 4.6
const DOOR_H := 3.3
## How far up the roller door is: the slab hangs from the lintel down to this
## height above the floor.
const DOOR_OPEN := 1.75
const CAM_FOV := 44.0
const LAMP_LIGHT := Color(1.0, 0.9, 0.74)
const LAMP_ENERGY := 11.0
const LAMP_CONE := 60.0
const LAMP_H := 3.5
const SODIUM := Color(1.0, 0.62, 0.3)
const DOOR_FILL := Color(0.4, 0.5, 0.78)
## The camera breathes a little, as on the title.
const SWAY_M := 0.12
const SWAY_SECS := 15.0

var kind := ""
var camera: Camera3D
var car: Node3D
var lamp_light: SpotLight3D
var street_light: OmniLight3D
var fill_light: OmniLight3D
var _t := 0.0
var _cam_home := Vector3.ZERO
var _look := Vector3.ZERO

func _init(car_kind: String) -> void:
	name = "GarageBay"
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = SITE
	add_to_group(GraphicsSettings.GROUP)
	_build_room()
	_build_lights()
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	camera.near = 0.2
	camera.far = 60.0
	add_child(camera)
	set_car(car_kind)

func _ready() -> void:
	_place_camera()

## Rolls a copy of this car into the bay, nose to the door, a little right of
## the room's middle so the buttons have the left of the picture.
func set_car(car_kind: String) -> void:
	if car != null:
		car.queue_free()
	kind = car_kind
	car = TitleKerbside.build_car(car_kind)
	# screen right is the room's -X from where the camera stands
	car.position = Vector3(-0.9, 0.0, 0.6)
	car.rotation.y = -0.18   # a touch across the bay, so both flanks read
	add_child(car)
	var half_w: float = car.get_meta("half_w")
	var half_l: float = car.get_meta("half_l")
	car.add_child(TitleKerbside._ground_shadow(half_w, half_l))
	lamp_light.position = Vector3(car.position.x, LAMP_H, car.position.z - 0.6)
	var shade := get_node_or_null(^"LampShade") as Node3D
	if shade != null:
		shade.position = lamp_light.position + Vector3(0.0, 0.12, 0.0)
	if is_inside_tree():
		_place_camera()

## From the door's left corner, low, looking in past the nose: the car is
## three-quarter front, right of centre, the bench and the pegboard behind it.
func _place_camera() -> void:
	var half_l: float = car.get_meta("half_l")
	# inside the door line: the camera never steps out of the room
	_cam_home = Vector3(3.4, 1.5, maxf(car.position.z - half_l - 3.4, DOOR_Z + 0.6))
	_look = Vector3(car.position.x + 0.9, 0.8, car.position.z + 0.6)
	_aim()

func _aim() -> void:
	var sway := sin(_t * TAU / SWAY_SECS)
	camera.position = _cam_home + Vector3(sway * SWAY_M, 0.02 * sin(_t * TAU / (SWAY_SECS * 0.7)), 0.0)
	camera.look_at(to_global(_look), Vector3.UP)

func _process(delta: float) -> void:
	if not visible or camera == null or not camera.current:
		return
	_t += delta
	_aim()

## GraphicsSettings.apply calls this on a preset change while the garage is up.
func apply_graphics() -> void:
	if lamp_light != null:
		lamp_light.shadow_enabled = TitleKerbside.lamp_shadow_for(GraphicsSettings.preset)

func _build_room() -> void:
	var concrete := TitleKerbside._flat(Color(0.3, 0.29, 0.27), 0.88)
	var wall := TitleKerbside._flat(Color(0.26, 0.24, 0.21), 0.95)
	var dark := TitleKerbside._flat(Color(0.1, 0.09, 0.08), 0.95)
	# floor and ceiling
	_slab(Vector3(ROOM_W, 0.2, ROOM_D), Vector3(0.0, -0.1, 0.0), concrete)
	_slab(Vector3(ROOM_W, 0.2, ROOM_D), Vector3(0.0, ROOM_H + 0.1, 0.0), dark)
	# back and side walls
	_slab(Vector3(ROOM_W, ROOM_H, 0.2), Vector3(0.0, ROOM_H * 0.5, ROOM_D * 0.5 + 0.1), wall)
	_slab(Vector3(0.2, ROOM_H, ROOM_D), Vector3(-ROOM_W * 0.5 - 0.1, ROOM_H * 0.5, 0.0), wall)
	_slab(Vector3(0.2, ROOM_H, ROOM_D), Vector3(ROOM_W * 0.5 + 0.1, ROOM_H * 0.5, 0.0), wall)
	# the front wall round the door opening, and the roller door half up
	var pier_w := (ROOM_W - DOOR_W) * 0.5
	_slab(Vector3(pier_w, ROOM_H, 0.3), Vector3(-ROOM_W * 0.5 + pier_w * 0.5, ROOM_H * 0.5, DOOR_Z), wall)
	_slab(Vector3(pier_w, ROOM_H, 0.3), Vector3(ROOM_W * 0.5 - pier_w * 0.5, ROOM_H * 0.5, DOOR_Z), wall)
	_slab(Vector3(DOOR_W, ROOM_H - DOOR_H, 0.3), Vector3(0.0, DOOR_H + (ROOM_H - DOOR_H) * 0.5, DOOR_Z), wall)
	var door := TitleKerbside._flat(Color(0.2, 0.21, 0.22), 0.55, 0.6)
	_slab(Vector3(DOOR_W, DOOR_H - DOOR_OPEN, 0.06), Vector3(0.0, DOOR_OPEN + (DOOR_H - DOOR_OPEN) * 0.5, DOOR_Z + 0.2), door)
	# outside: the forecourt and the sidewalk under the sodium lamp, and a
	# dark block of the street beyond so the door never shows the void
	_slab(Vector3(16.0, 0.2, 10.0), Vector3(0.0, -0.1, DOOR_Z - 5.0), TitleKerbside._flat(Color(0.07, 0.07, 0.075), 0.34, 0.12))
	_slab(Vector3(16.0, 5.0, 0.4), Vector3(0.0, 2.5, DOOR_Z - 10.2), TitleKerbside._flat(Color(0.12, 0.1, 0.09), 0.95))
	# the bench along the far wall (screen right) and the pegboard above it
	_slab(Vector3(0.7, 0.9, 3.0), Vector3(-ROOM_W * 0.5 + 0.35, 0.45, 2.0), TitleKerbside._flat(Color(0.33, 0.3, 0.26), 0.8))
	_slab(Vector3(0.05, 1.4, 2.6), Vector3(-ROOM_W * 0.5 + 0.03, 1.9, 2.0), TitleKerbside._flat(Color(0.5, 0.42, 0.28), 0.9))
	# a tool chest and a tyre stack on the back wall
	_slab(Vector3(0.9, 1.3, 0.6), Vector3(3.2, 0.65, ROOM_D * 0.5 - 0.4), TitleKerbside._flat(Color(0.5, 0.12, 0.1), 0.6, 0.3))
	_slab(Vector3(0.7, 0.7, 0.7), Vector3(-2.4, 0.35, ROOM_D * 0.5 - 0.45), TitleKerbside._flat(Color(0.05, 0.05, 0.05), 0.9))
	# the oil stain where the engine drips
	var stain := TitleKerbside._ground_shadow(0.5, 0.35)
	stain.name = "OilStain"
	stain.position = Vector3(-0.9, 0.006, -0.9)
	stain.material_override.albedo_color.a = 0.55
	add_child(stain)
	# the hanging lamp's shade
	var shade := MeshInstance3D.new()
	shade.name = "LampShade"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = 0.42
	cone.height = 0.3
	shade.mesh = cone
	shade.material_override = TitleKerbside._flat(Color(0.2, 0.3, 0.26), 0.5, 0.7)
	add_child(shade)

func _build_lights() -> void:
	lamp_light = SpotLight3D.new()
	lamp_light.name = "WorkLamp"
	lamp_light.light_color = LAMP_LIGHT
	lamp_light.light_energy = LAMP_ENERGY
	lamp_light.spot_range = 9.0
	lamp_light.spot_angle = LAMP_CONE
	lamp_light.spot_angle_attenuation = 0.9
	lamp_light.shadow_enabled = TitleKerbside.lamp_shadow_for(GraphicsSettings.preset)
	lamp_light.shadow_bias = 0.12
	lamp_light.shadow_normal_bias = 2.0
	lamp_light.shadow_blur = 1.5
	lamp_light.rotation.x = -PI * 0.5
	add_child(lamp_light)
	street_light = OmniLight3D.new()
	street_light.name = "StreetGlow"
	street_light.light_color = SODIUM
	street_light.light_energy = 3.0
	street_light.omni_range = 12.0
	street_light.shadow_enabled = false
	street_light.position = Vector3(-1.5, 3.0, DOOR_Z - 4.0)
	add_child(street_light)
	fill_light = OmniLight3D.new()
	fill_light.name = "DoorFill"
	fill_light.light_color = DOOR_FILL
	fill_light.light_energy = 0.9
	fill_light.omni_range = 9.0
	fill_light.shadow_enabled = false
	fill_light.position = Vector3(1.5, 1.4, DOOR_Z + 0.8)
	add_child(fill_light)
	# the room's own dim warm bounce, so the walls and the bench read
	var bounce := OmniLight3D.new()
	bounce.name = "RoomBounce"
	bounce.light_color = Color(0.9, 0.8, 0.65)
	bounce.light_energy = 0.7
	bounce.omni_range = 11.0
	bounce.shadow_enabled = false
	bounce.position = Vector3(0.0, 2.6, 1.5)
	add_child(bounce)

func _slab(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	add_child(mi)
