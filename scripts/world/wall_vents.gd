extends RefCounted
# Wall vents (street life L4, 2026-10-14): a laundromat's dryer vent, a
# kitchen's extractor, a workshop's flue, puffing steam into the lamp light
# from a building's front wall at head height and a bit. Shops and diners
# in the busy districts, warehouses and sheds in the industrial ones.
#
# ZERO per-frame script work: ONE MultiMesh per chunk ("WallVents") sharing
# lamp life's steam mesh and shader (three rising, fading puffs per vent, the
# "thin" plume), at most VENT_CAP vents a chunk. Which buildings vent is a
# hash of the chunk and the building slot, so a pooled chunk rebuilt later
# matches a fresh one and the road's random sequence is untouched. Nothing
# is placed in a chunk that has no fitting building; the node then shows
# zero instances and costs no draw call.

const LampLife := preload("res://scripts/world/lamp_life.gd")
const RoadChunkBuilder := preload("res://scripts/world/road_chunk_builder.gd")

## Per district: chance (%) that a fitting building vents, and the types
## that fit there. Left out: no vents.
const BY_DISTRICT := {
	"downtown":    {"chance": 30, "types": ["shop", "diner"]},
	"residential": {"chance": 8, "types": ["shop", "diner"]},
	"strip":       {"chance": 55, "types": ["shop", "diner", "garage"]},
	"industrial":  {"chance": 45, "types": ["warehouse", "garage", "shop", "diner"]},
	"old_town":    {"chance": 45, "types": ["shop", "diner"]},
	"lofts":       {"chance": 35, "types": ["shop", "diner", "warehouse"]},
	"docks":       {"chance": 40, "types": ["warehouse", "garage", "shop", "diner"]},
	"hillside":    {"chance": 10, "types": ["shop", "diner"]},
}
## Vents per chunk at most (two draw-call-free puffs of 3 quads each).
const VENT_CAP := 2
## The vent's height on the wall, m, and how far in front of the wall the
## puffs start.
const VENT_H := 2.6
const OFF_WALL := 0.25

static var enabled := true
static var _enabled_read := false

static func _read_enabled() -> void:
	if _enabled_read:
		return
	_enabled_read = true
	if OS.has_environment("NEON_WALL_VENTS"):
		enabled = OS.get_environment("NEON_WALL_VENTS") != "0"

static func new_multimesh() -> MultiMeshInstance3D:
	return LampLife._new_mm("WallVents", LampLife._get_steam_mesh(), LampLife._get_steam_mat(), VENT_CAP, true, LampLife.RANGE_STEAM)

## Which building slots vent in this chunk: a list of
## {x (signed, across), z, side, seed}, from the builder's building infos.
static func plan(chunk_index: int, district: String, infos: Array) -> Array:
	_read_enabled()
	var out := []
	if not enabled or not BY_DISTRICT.has(district):
		return out
	var spec: Dictionary = BY_DISTRICT[district]
	var k := 0
	for info in infos:
		if out.size() >= VENT_CAP:
			break
		k += 1
		if bool(info.get("empty", true)) or not info.has("front_x_abs"):
			continue
		if not (String(info.type) in spec.types):
			continue
		if posmod(hash([chunk_index, "wall vent", k]), 100) >= int(spec.chance):
			continue
		var side := int(info.side)
		var d := float(info.d)
		# along the front, a third of the way in from one end
		var end := 1.0 if posmod(hash([chunk_index, "vent end", k]), 2) == 0 else -1.0
		var z := float(info.z) + end * d / 3.0
		var x := (float(info.front_x_abs) - OFF_WALL) * float(side)
		out.append({"x": x, "z": z, "side": side, "slot": k,
			"seed": float(posmod(hash([chunk_index, "vent seed", k]), 89)) / 89.0})
	return out

static func update(root: Node3D, chunk_index: int, district: String, infos: Array) -> void:
	var mm: MultiMesh = (root.get_node(^"WallVents") as MultiMeshInstance3D).multimesh
	var vents := plan(chunk_index, district, infos)
	for i in vents.size():
		var v: Dictionary = vents[i]
		# the steam shader leans its puffs along local +x with the wind: turn
		# the vent so that is away from the wall, toward the road
		var turn := Basis(Vector3.UP, PI) if int(v.side) == 1 else Basis()
		mm.set_instance_transform(i, RoadChunkBuilder._xf_up(float(v.x), VENT_H, float(v.z), turn))
		mm.set_instance_custom_data(i, Color(float(v.seed), 1.0, 0.0, 0.0))
	mm.visible_instance_count = vents.size()
	root.set_meta("wall_vents", vents)
