extends Node
class_name CarLampSweep

# Street-lamp light on car paint (look pass, 2026-10-10). The lamps are not
# lights (their pools are painted quads), so nothing lit a car as it passed
# under one. On Medium and High (Medium since 2026-10-14, Roy 1526) the car
# shaders (CarPaint, LAMPS) light the body from the two nearest lamps of the
# row and slide their highlights across it. This node, a child of the player
# car, tells them where the row is: four global uniforms once a frame, no
# lights, no per-car work.
#
#   car_lamp_origin  the player's world position
#   car_lamp_fwd     the road's direction there
#   car_lamp_grid    x = metres between lamps on one side, y / z = metres
#                    ahead of the player to a lamp on the right / left side,
#                    w = the player's distance right of the centre line
#   car_lamp_light   rgb = the district's lamp colour times strength (0 on a
#                    dark road), w = how far the lamp heads sit from the
#                    centre line. Low reads none of these; its paint has no
#                    city and no lamps.
#
# The row follows RoadChunkBuilder's placement (25 m apart a side, the sides
# staggered, thinned by the district's `every`); junction and gas-station
# gaps are not followed, and the heads are taken at one fixed distance from
# the centre line.

const Districts := preload("res://scripts/world/districts.gd")

const HEAD_X := 13.2
const STRENGTH := 1.0

func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)
	apply_graphics()

func apply_graphics() -> void:
	set_process(CarPaint.tier() >= CarPaint.TIER_MEDIUM)

func _process(_delta: float) -> void:
	var car := get_parent() as Node3D
	if car == null:
		return
	var pos := car.global_position
	var u := RoadFrame.unroll(pos)
	var s := RoadFrame.s_at(u.z)
	var chunk := floori(s / RoadFrame.L)
	var street: Dictionary = Districts.street_at(chunk)
	var every := int(street.every)
	var spacing := RoadChunkBuilder.LAMP_SPACING
	var period := spacing
	var first := float(chunk) * RoadFrame.L   # where the pattern starts
	var right_at := spacing * 0.25
	var left_at := spacing * 0.75
	match every:
		2:
			period = RoadFrame.L
			left_at = spacing * 1.75
		4:
			period = RoadFrame.L * 2.0
			first = float(chunk - posmod(chunk, 2)) * RoadFrame.L
			left_at = RoadFrame.L + spacing * 0.75
	var into := s - first
	var light: Color = Districts.LIGHTS[street.light].color
	var k := 0.0 if every == 0 else STRENGTH
	RenderingServer.global_shader_parameter_set(&"car_lamp_origin", pos)
	RenderingServer.global_shader_parameter_set(&"car_lamp_fwd", RoadFrame.basis_at(u.z) * Vector3.FORWARD)
	RenderingServer.global_shader_parameter_set(&"car_lamp_grid", Vector4(period, right_at - into, left_at - into, u.x))
	RenderingServer.global_shader_parameter_set(&"car_lamp_light", Vector4(light.r * k, light.g * k, light.b * k, HEAD_X))
