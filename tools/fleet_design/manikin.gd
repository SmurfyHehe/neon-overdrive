extends RefCounted
# A seated manikin for the cabin space audit (2026-10-09, Roy: "make sure
# that we actually have space in the interior", then "different body types,
# different heights"). Proportions scale with stature the way the standard
# anthropometric tables do (Dreyfuss / SAE J833, 50th percentile man of 1.78 m
# as the reference; every length is a fraction of stature so a 1.55 m or
# 1.95 m body follows). Car space: -z forward, -x the driver's side, the hip
# pivot sits on the seat cushion.
#
# Fractions of stature S (seated, cushion compressed):
#   hip pivot above the cushion      0.05 S   (0.09 m at 1.78)
#   shoulder (acromion) above cushion 0.33 S  (0.59)
#   eye above the cushion            0.44 S   (0.78)
#   top of head above the cushion    0.505 S  (0.90)
#   shoulder breadth (bideltoid)     0.265 S  (0.47)
#   hip breadth, seated              0.21 S   (0.37)
#   thigh, hip to knee               0.265 S  (0.47)
#   shin, knee to ankle              0.25 S   (0.445)
#   arm, shoulder to the grip, comfortable (elbow bent) 0.31 S (0.55)
#   arm, shoulder to the grip, straight                 0.36 S (0.64)
# The torso leans back with the seat (RECLINE_DEG), like DriverModel.

const RECLINE_DEG := 12.0
## Hip pivot ahead of the cushion centre (the backrest is ~0.25 m behind it,
## the hip sits ~0.13 m ahead of the backrest face, so ~0.1 m ahead of centre;
## DriverModel puts its pelvis 0.02 m ahead of centre).
const HIP_AHEAD := 0.08

static func fractions() -> Dictionary:
	return {
		"hip": 0.05, "shoulder": 0.33, "eye": 0.44, "head_top": 0.505,
		"shoulder_breadth": 0.265, "hip_breadth": 0.21,
		"thigh": 0.265, "shin": 0.25, "reach_easy": 0.31, "reach_max": 0.36,
	}

## Every landmark for a body of stature `s` sat on a cushion whose top is at
## `cushion_y`, centred at (seat_x, seat_z). Car space.
static func pose(s: float, seat_x: float, cushion_y: float, seat_z: float) -> Dictionary:
	var f := fractions()
	var hip := Vector3(seat_x, cushion_y + f.hip * s, seat_z + HIP_AHEAD)
	var out := {
		"stature": s,
		"hip": hip,
		"shoulder": _torso(hip, (f.shoulder - f.hip) * s),
		"eye": _torso(hip, (f.eye - f.hip) * s) + Vector3(0.0, 0.0, -0.07),   # the eyes sit ahead of the neck line
		"head_top": _torso(hip, (f.head_top - f.hip) * s),
		"head_half": Vector3(0.08, 0.12, 0.10),   # half size of the head box (a 0.24 m tall head at 1.78; scales below)
		"shoulder_half": f.shoulder_breadth * s * 0.5,
		"hip_half": f.hip_breadth * s * 0.5,
		"thigh": f.thigh * s,
		"shin": f.shin * s,
		"reach_easy": f.reach_easy * s,
		"reach_max": f.reach_max * s,
	}
	out.head_half = Vector3(0.08, 0.12, 0.10) * (s / 1.78)
	out["head_centre"] = out.head_top - Vector3(0.0, out.head_half.y, 0.0)
	return out

## A point `h` up the reclined torso from the hip.
static func _torso(hip: Vector3, h: float) -> Vector3:
	var a := deg_to_rad(RECLINE_DEG)
	return hip + Vector3(0.0, h * cos(a), h * sin(a))

## Two-bone leg from the hip to an ankle target: [knee, ankle_reached, shortfall].
## shortfall > 0 when the leg is too short to reach; the knee bends up and forward.
static func leg(hip: Vector3, ankle: Vector3, thigh: float, shin: float) -> Array:
	var d := ankle - hip
	var dist := d.length()
	var shortfall := maxf(0.0, dist - (thigh + shin))
	var reach := clampf(dist, absf(thigh - shin) + 1e-3, thigh + shin - 1e-3)
	var dir := d / dist
	var cos_a := (thigh * thigh + reach * reach - shin * shin) / (2.0 * thigh * reach)
	var a := acos(clampf(cos_a, -1.0, 1.0))
	var pole := Vector3.UP
	var side := pole - dir * pole.dot(dir)
	if side.length_squared() < 1e-8:
		side = Vector3.FORWARD
	side = side.normalized()
	var knee := hip + (dir * cos(a) + side * sin(a)) * thigh
	return [knee, hip + dir * reach, shortfall]
