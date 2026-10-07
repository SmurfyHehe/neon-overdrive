extends RefCounted
class_name RoadFrame

# Road space (#37 curves and elevation, step R1; plan in
# docs/planning/curves-elevation-proposal-2026-10-07.md).
#
# Road space is the road unrolled straight: x is across the road (lane
# offsets, own lanes at +x, RoadChunkBuilder.lane_offset), y is up from the
# road surface, z is along it with forward = -z, in the same units and the
# same floating-origin frame as world z on today's straight road. Everything
# that reasons in lanes and "metres ahead" (traffic, the chunk pool, the
# benchmark bot) reads positions through unroll() and writes poses through
# pose(), so it never assumes the road runs down world -Z.
#
# Step R1: the road is still straight, so every function here is the
# identity and behaviour is bit-for-bit what it was. Step R3 (curves) backs
# them with the chunks' Path3D curves; no caller changes then.

## World position -> road space.
static func unroll(p: Vector3) -> Vector3:
	return p

## Road space -> world position.
static func roll(u: Vector3) -> Vector3:
	return u

## World orientation of the road's axes at road-space z (x across, y up,
## -z forward).
static func basis_at(_z: float) -> Basis:
	return Basis.IDENTITY

## Road heading at road-space z, radians about world up (0 = down world -Z).
static func heading_at(_z: float) -> float:
	return 0.0

## A world-space direction (velocity, a basis axis) -> road space at z.
static func dir_to_road(z: float, v: Vector3) -> Vector3:
	return basis_at(z).transposed() * v

## A world basis -> road space at z.
static func basis_to_road(z: float, b: Basis) -> Basis:
	return basis_at(z).transposed() * b

## World transform of something at road-space (x, y, z), yawed by `yaw`
## relative to the road (0 = pointing down the road, PI = oncoming).
static func pose(x: float, y: float, z: float, yaw: float) -> Transform3D:
	return Transform3D(basis_at(z) * Basis(Vector3.UP, yaw), roll(Vector3(x, y, z)))
