extends Node3D
class_name CockpitFrame

# What you see from the driver's seat (Phase C, 2026-10-05): a dark dashboard slab,
# two A-pillars, a roof edge and a steering wheel that turns with the steering. A
# stand-in until the real interiors (deferred by Roy); everything is primitive
# meshes, a child of the camera, so it needs no files. Positions are camera-local
# (-z is forward), tuned for FOV about 78.

const DASH := Color(0.05, 0.05, 0.07)
const TRIM := Color(0.10, 0.09, 0.12)

var wheel: MeshInstance3D
var steering := 0.0   # -1..1, set by the camera each frame

func _ready() -> void:
	visible = false
	_box(Vector3(2.2, 0.30, 0.9), Vector3(0.30, -0.62, -0.75), DASH)           # dashboard slab
	_box(Vector3(2.2, 0.07, 0.12), Vector3(0.30, -0.45, -1.15), TRIM)          # lip along the windshield base
	_box(Vector3(0.10, 0.9, 0.12), Vector3(-0.78, 0.0, -0.95), DASH, Vector3(0, 0, -0.35))   # left A-pillar
	_box(Vector3(0.10, 0.9, 0.12), Vector3(1.38, 0.0, -0.95), DASH, Vector3(0, 0, 0.35))     # right A-pillar
	_box(Vector3(2.2, 0.08, 0.5), Vector3(0.30, 0.52, -0.8), DASH)             # roof edge
	var torus := TorusMesh.new()
	torus.inner_radius = 0.155
	torus.outer_radius = 0.185
	wheel = MeshInstance3D.new()
	wheel.mesh = torus
	wheel.material_override = _mat(TRIM)
	wheel.position = Vector3(0.0, -0.26, -0.58)
	wheel.rotation = Vector3(deg_to_rad(65.0), 0.0, 0.0)   # tilted back toward the driver
	add_child(wheel)
	for a in 3:  # three spokes, as thin boxes parented to the wheel
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.17, 0.012, 0.02)
		spoke.mesh = bm
		spoke.material_override = _mat(TRIM)
		spoke.rotation = Vector3(0.0, deg_to_rad(90.0 + 120.0 * a), 0.0)
		wheel.add_child(spoke)

func _process(_delta: float) -> void:
	if visible:
		# turn the wheel about its own axis (the torus's up axis), about 1.5 rad at full lock
		wheel.rotation = Vector3(deg_to_rad(65.0), -steering * 1.5, 0.0)

func _box(size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _mat(color)
	m.position = pos
	m.rotation = rot
	add_child(m)

func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # always readable at night
	return mat
