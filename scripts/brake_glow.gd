class_name BrakeGlow
extends Node

# Glowing brake discs (2026-10-09, small-ideas G2): after hard braking from
# speed the discs glow, deep red to orange, and fade as they cool. Driven by
# PowertrainHealth.brake_temp, which already heats with braking power and
# cools with airspeed, so the glow lasts exactly as long as the brakes are
# really hot (and fading brakes are visible before they are felt).
#
# Seen through the spokes: the P1 wheel has no separate disc, so its dark
# spoke-gap faces glow (P1CoupeBuilder BODY_SHADER brake_heat). The wheels'
# shared material is copied per axle for this car only; the fronts run
# hotter (they do most of the stopping).

## Glow from GLOW_START (first dull red) to GLOW_FULL (orange), degC on the
## game's brake model, not real-world disc temperatures: one hard stop from
## 200 km/h reaches ~275 (measured, tests/brake_glow.gd), brake fade starts at
## PowertrainHealth.FADE_START_C (350). So one hard stop glows dull red,
## repeated ones toward orange, and ordinary braking (under ~150) not at all.
const GLOW_START := 150.0
const GLOW_FULL := 450.0
const REAR_SHARE := 0.6

var player: PlayerCar
var front_mat: ShaderMaterial
var rear_mat: ShaderMaterial

func _init(car: PlayerCar) -> void:
	player = car
	name = "BrakeGlow"

func _ready() -> void:
	for w in player.wheel_array:
		if w.wheel_node == null:
			continue
		for n in w.wheel_node.find_children("Mesh", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var m := mi.get_surface_override_material(0) as ShaderMaterial
			if m == null:
				continue
			var front: bool = w.position.z < 0.0   # the car faces -Z
			if front and front_mat == null:
				front_mat = m.duplicate()
			elif not front and rear_mat == null:
				rear_mat = m.duplicate()
			mi.set_surface_override_material(0, front_mat if front else rear_mat)

## 0..1 for a brake temperature.
static func heat_for(temp_c: float) -> float:
	return clampf((temp_c - GLOW_START) / (GLOW_FULL - GLOW_START), 0.0, 1.0)

func _process(_delta: float) -> void:
	var h := heat_for(player.health.brake_temp)
	if front_mat != null:
		front_mat.set_shader_parameter("brake_heat", h)
	if rear_mat != null:
		rear_mat.set_shader_parameter("brake_heat", h * REAR_SHARE)
