class_name CarWipers
extends Node

# Windscreen wipers that sweep when it rains (car-parts-every-vehicle plan,
# Roy 1175), and never break (Roy 1180: a broken wiper in the rain would take
# the view away, so nothing in CarDamage touches them).
#
# Two blades on the windscreen's lower edge, one MultiMesh (one draw call),
# parked flat along the glass and swept up by about 68 degrees. The frame
# comes from CarFittings (the glass at the car's centre line, found by ray
# from the sheet's own triangles), so each car's blades lie on its own glass.
# Seen from the cockpit through the windscreen like the outside bodywork.
#
# Rain: reads Weather.wetness (scripts/world/weather.gd, the water PR) when
# that script exists, so nothing here depends on it being merged; tests and
# tools can pin it with CarWipers.rain_override (0..1; -1 = off).
# Dry: parked, no work. Rain: sweeps; when the rain stops the blades finish
# the stroke and park.

const BLADES := 2
const MAX_ANGLE := 1.19            # 68 degrees
## Pivot x and blade length as a share of the body's half width.
const PIVOT_X := [-0.55, 0.05]
const BLADE_LEN := 0.52
const BLADE_LIFT := 0.012          # blade sits this far off the glass
const RAIN_ON := 0.05
const RATE_LIGHT := 0.85           # strokes per second, steady rain
const RATE_HEAVY := 1.5            # downpour
const WEATHER_PATH := "res://scripts/world/weather.gd"

static var rain_override := -1.0
static var _weather: Script

var visual: Node3D
## Sweep phase 0..1 (0 = parked) and the blade angle it gives, radians.
var phase := 0.0
var angle := 0.0
var _mm: MultiMeshInstance3D
var _frame := Basis()
var _base := Vector3.ZERO
var _hw := 1.0
## The transforms last written to the MultiMesh (the server does not read
## them back headless; tests and debugging do).
var blade_xf: Array[Transform3D] = [Transform3D(), Transform3D()]

## Hangs wipers on a car with a windscreen frame; null when its body has none.
static func attach(vehicle: Node) -> CarWipers:
	var vis := vehicle.get("chassis_visual") as Node3D
	if vis == null:
		return null
	var scr: Dictionary = vis.get_meta("windscreen", {})
	var body := vis.get_node_or_null("Body") as Node3D
	if scr.is_empty() or body == null:
		return null
	var w := CarWipers.new()
	w.name = "CarWipers"
	w.visual = vis
	w._build(scr, body)
	vehicle.add_child(w)
	return w

func blade_count() -> int:
	return _mm.multimesh.instance_count if _mm != null else 0

## 0 dry .. 1 downpour.
static func rain_amount() -> float:
	if rain_override >= 0.0:
		return clampf(rain_override, 0.0, 1.0)
	if _weather == null and ResourceLoader.exists(WEATHER_PATH):
		_weather = load(WEATHER_PATH)
	if _weather == null:
		return 0.0
	return clampf(read_static(_weather, "wetness"), 0.0, 1.0)

## A static var of a script, as a float (0 when it is not there).
static func read_static(script: Script, prop: String) -> float:
	var v: Variant = script.get(prop)
	return float(v) if v != null else 0.0

func _build(scr: Dictionary, body: Node3D) -> void:
	var n: Vector3 = scr.normal
	var u := (Vector3.RIGHT - n * Vector3.RIGHT.dot(n)).normalized()
	var up := u.cross(n).normalized()
	_frame = Basis(u, up, n)
	_base = scr.base
	_hw = float(scr.half_w)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.012, 0.014)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#15171C")
	mat.roughness = 0.8
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = BLADES
	_mm = MultiMeshInstance3D.new()
	_mm.name = "Wipers"
	_mm.multimesh = mm
	body.add_child(_mm)
	_update()

func _process(delta: float) -> void:
	advance(delta)

## One step of the sweep. Called every frame; tests call it with their own dt.
func advance(delta: float) -> void:
	var rain := rain_amount()
	var raining := rain > RAIN_ON
	if raining or phase > 0.0:
		var rate := lerpf(RATE_LIGHT, RATE_HEAVY, rain) if raining else RATE_LIGHT
		phase += rate * delta
		if phase >= 1.0:
			phase = fposmod(phase, 1.0) if raining else 0.0
		angle = MAX_ANGLE * 0.5 * (1.0 - cos(TAU * phase))
		_update()

func _update() -> void:
	var b := _frame * Basis(Vector3.BACK, angle)
	var dir := b * Vector3.RIGHT
	var length := BLADE_LEN * _hw
	for i in BLADES:
		var pivot: Vector3 = _base + _frame * Vector3(float(PIVOT_X[i]) * _hw, 0.0, BLADE_LIFT)
		var xf := Transform3D(b.scaled_local(Vector3(length, 1.0, 1.0)), pivot + dir * (length * 0.5))
		blade_xf[i] = xf
		_mm.multimesh.set_instance_transform(i, xf)

## The blade's tip (design coordinates of the body), for tests.
func tip(i: int) -> Vector3:
	var xf := blade_xf[i]
	return xf.origin + (xf.basis * Vector3.RIGHT) * 0.5
