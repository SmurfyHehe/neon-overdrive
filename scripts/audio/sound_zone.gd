extends Node3D
class_name SoundZone

# A box in the world that changes what you hear (2026-10-08, small sound ideas
# Roy approved: highway joints, radio drops, bridge hum, manholes). Put one
# wherever the road builder makes a tunnel, a bridge or a manhole cover; the
# sound code asks "what am I in?" every frame. Nothing places them yet: the
# road has no bridges, tunnels or covers so far (the buildings and road-shape
# work will), so in game today only the highway joints play (CarAudio).
#
# The box is centred on the node, `size` long in its local axes, and follows
# the node (so a zone parented to a road chunk moves with the floating origin).
# Zones are few, so a plain list is fast enough to search per frame.

enum Kind { TUNNEL, UNDER_BRIDGE, BRIDGE_DECK, MANHOLE, CONCRETE }

## Radio reception inside each kind (1 = clear). Tunnels cut it; the shadow of
## a bridge breaks it up.
const RECEPTION := {Kind.TUNNEL: 0.0, Kind.UNDER_BRIDGE: 0.35}

@export var kind := Kind.TUNNEL
@export var size := Vector3(10.0, 6.0, 20.0)

static var _all: Array[SoundZone] = []

static func make(k: Kind, box: Vector3) -> SoundZone:
	var z := SoundZone.new()
	z.kind = k
	z.size = box
	return z

func _enter_tree() -> void:
	_all.append(self)

func _exit_tree() -> void:
	_all.erase(self)

func contains(world_pos: Vector3) -> bool:
	var p := global_transform.affine_inverse() * world_pos
	return absf(p.x) <= size.x * 0.5 and absf(p.y) <= size.y * 0.5 and absf(p.z) <= size.z * 0.5

## The first zone of this kind around world_pos, or null.
static func find(k: Kind, world_pos: Vector3) -> SoundZone:
	for z in _all:
		if z.kind == k and z.contains(world_pos):
			return z
	return null

## Radio reception at world_pos: the worst of the zones it is in.
static func reception_at(world_pos: Vector3) -> float:
	var r := 1.0
	for z in _all:
		if RECEPTION.has(z.kind) and z.contains(world_pos):
			r = minf(r, RECEPTION[z.kind])
	return r
