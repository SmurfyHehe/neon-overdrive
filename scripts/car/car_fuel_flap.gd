class_name CarFuelFlap
extends Node

# The fuel flap and the pump nozzle (car-parts-every-vehicle plan, Roy 1177,
# and Roy 2026-10-11: "animation for it opening when at the pump and magic
# refuel gun that fills the car up").
#
# The filler sits on the right rear quarter: CarFittings puts a dark recess and
# a cap in the body there, and this node hangs the hinged flap over it. The
# flap and the nozzle follow two flags on the car's FuelTank, which the pump
# menu (pump_panel.gd) sets, so nothing here knows about stations:
#   at_pump  the car stands in the bay with the menu up: the flap opens, then
#            the nozzle floats in from the pump side and plugs into the cap;
#   filling  the gauge is rising: the nozzle shudders with the flow;
#   neither: the nozzle backs out, then the flap closes.
# A fill-up that comes from anywhere else (FuelTank.refuel) opens the flap for
# FuelTank.FLAP_HOLD_MS too, so a station that does not set the flags still
# gets the animation.
#
# Keyboard only, nothing on the HUD. The nodes process while the game is paused
# (the pump menu pauses it), so the show plays under the menu.
#
# Cost: the flap is one draw call; the nozzle and its hose are one MultiMesh
# (10 boxes) and only draw while out.

const OPEN_ANGLE := 1.75           # radians, the flap swings outward
const OPEN_RATE := 2.6             # flap travel per second (0.4 s)
const PLUG_RATE := 1.6             # nozzle travel per second (0.6 s)
const FLAP_W := 0.17               # along the car (z)
const FLAP_H := 0.12
const HOSE_SEGMENTS := 8
const HOVER := Vector3(0.0, 0.25, 0.0)

var vehicle: Node
var fuel: Object
var visual: Node3D
## 0 closed .. 1 open, and 0 nozzle away .. 1 plugged in.
var open := 0.0
var plug := 0.0
var _pivot: Node3D
var _nozzle: MultiMeshInstance3D
var _p := Vector3.ZERO
var _n := Vector3.RIGHT
var _t := 0.0

## Hangs the flap (and the nozzle) on a car whose body has a fuel recess.
## `fuel_tank` is the car's FuelTank, or null for a car that never refuels
## (a cop, a rival): the flap is there but never opens.
static func attach(v: Node, fuel_tank: Object = null) -> CarFuelFlap:
	var vis := v.get("chassis_visual") as Node3D
	if vis == null:
		return null
	var site: Dictionary = vis.get_meta("fuel_flap_site", {})
	var body := vis.get_node_or_null("Body") as Node3D
	if site.is_empty() or body == null:
		return null
	var f := CarFuelFlap.new()
	f.name = "CarFuelFlap"
	f.vehicle = v
	f.fuel = fuel_tank
	f.visual = vis
	f.process_mode = Node.PROCESS_MODE_ALWAYS
	f._build(site, body)
	v.add_child(f)
	return f

func _body_paint(body: Node3D) -> Color:
	var bm: Variant = visual.get_meta("body_mat") if visual.has_meta("body_mat") else null
	if bm is ShaderMaterial:
		var c: Variant = (bm as ShaderMaterial).get_shader_parameter("paint")
		if c is Color:
			return c
	var mi := body as MeshInstance3D
	if mi != null:
		var c2: Variant = mi.get_instance_shader_parameter("paint")
		if c2 is Color:
			return c2
	return Color("#C9CED6")

func _build(site: Dictionary, body: Node3D) -> void:
	_p = site.p
	_n = site.n
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _body_paint(body)
	mat.metallic = 0.45
	mat.roughness = 0.45
	# Hinge on the forward edge of the recess, the flap runs rearward from it.
	_pivot = Node3D.new()
	_pivot.name = "FlapPivot"
	_pivot.position = _p + Vector3(0.0, 0.0, -FLAP_W * 0.5) + _n * 0.010
	body.add_child(_pivot)
	var panel := MeshInstance3D.new()
	panel.name = "Flap"
	var box := BoxMesh.new()
	box.size = Vector3(0.010, FLAP_H, FLAP_W)
	box.material = mat
	panel.mesh = box
	panel.position = Vector3(0.0, 0.0, FLAP_W * 0.5)
	_pivot.add_child(panel)
	# The nozzle: spout, handle and hose as unit boxes in one MultiMesh.
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color("#3A3E46")
	nm.roughness = 0.6
	unit.material = nm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = unit
	mm.instance_count = 2 + HOSE_SEGMENTS
	_nozzle = MultiMeshInstance3D.new()
	_nozzle.name = "Nozzle"
	_nozzle.multimesh = mm
	_nozzle.visible = false
	body.add_child(_nozzle)

## Where the car is parked relative to the pump: flap wanted open.
func _wants_open() -> bool:
	if fuel == null:
		return false
	return bool(fuel.get("at_pump")) or bool(fuel.call("is_filling"))

func _process(delta: float) -> void:
	advance(delta)

## One step of the animation (tests call it with their own dt).
func advance(delta: float) -> void:
	_t += delta
	var want := _wants_open()
	# The flap stays open while the nozzle is still out.
	var flap_target := 1.0 if (want or plug > 0.001) else 0.0
	open = move_toward(open, flap_target, OPEN_RATE * delta)
	var plug_target := 1.0 if (want and open >= 0.999) else 0.0
	plug = move_toward(plug, plug_target, PLUG_RATE * delta)
	_pivot.rotation.y = open * OPEN_ANGLE
	_nozzle.visible = plug > 0.001
	if _nozzle.visible:
		_place_nozzle()

func is_open() -> bool:
	return open > 0.999

func is_plugged() -> bool:
	return plug > 0.999

func _unit_xf(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var d := b - a
	var dist := maxf(d.length(), 0.001)
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var bs := Basis.looking_at(d / dist, up).scaled_local(Vector3(thick, thick, dist))
	return Transform3D(bs, (a + b) * 0.5)

func _place_nozzle() -> void:
	var cap := _p + _n * 0.010
	var ease_t := plug * plug * (3.0 - 2.0 * plug)
	var hover := cap + _n * 0.9 + HOVER
	var tip := hover.lerp(cap, ease_t)
	# While filling the gun shudders with the flow.
	if fuel != null and bool(fuel.call("is_filling")) and plug > 0.999:
		tip += Vector3(0.0, sin(_t * 170.0), 0.0) * 0.004 + _n * (sin(_t * 90.0) * 0.003)
	var spout_end := tip + _n * 0.16
	var handle_end := spout_end + _n * 0.14 + Vector3(0.0, 0.16, 0.0)
	var mm := _nozzle.multimesh
	mm.set_instance_transform(0, _unit_xf(tip, spout_end, 0.028))
	mm.set_instance_transform(1, _unit_xf(spout_end, handle_end, 0.05))
	# The hose runs from the handle to the pump, in a sagging curve.
	# The pump stands a couple of metres out at hose height (the bay is on the
	# car's right, gas_station.gd BAY_X).
	var anchor := Vector3(_p.x + _n.x * 1.9, 0.9, _p.z + 0.2)
	var ctrl := (handle_end + anchor) * 0.5 + Vector3(0.0, -0.4, 0.0)
	var prev := handle_end
	for i in HOSE_SEGMENTS:
		var t := float(i + 1) / float(HOSE_SEGMENTS)
		var a := handle_end.lerp(ctrl, t)
		var b := ctrl.lerp(anchor, t)
		var pt := a.lerp(b, t)
		mm.set_instance_transform(2 + i, _unit_xf(prev, pt, 0.032))
		prev = pt
