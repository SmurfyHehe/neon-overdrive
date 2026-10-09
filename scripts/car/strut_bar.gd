class_name StrutBar
extends RefCounted

# The strut bar (interior mods batch 1, 2026-10-09; Roy: no roll cages, strut
# bars instead): a brace between the front strut towers under the hood, fitted
# when CabinMods.strut_bar is on. Looks here, the stiffer front end in
# CabinMods.apply_sim. Its ends are CabinSpots.strut_bar(kind), in car space,
# so it lands in each car's own engine bay (the beater's front trunk).
#
# A child of the player's chassis visual, named "StrutBar", on the car's own
# render layer like the body. Under a shut hood it is out of sight; it shows
# when the hood opens (the car-parts hood work) and in any shot under the skin.
#
# Design: a sodium tube on two silver tower plates with bolt heads, a short
# brace triangle at each end. CockpitKit shapes, under 200 triangles.

const NODE := "StrutBar"
const TUBE_R := 0.015
const SODIUM := Color("#FF8A1F")
const SILVER := Color("#C9CED6")
const INK := Color("#15171C")

## Fits or removes the bar on a built player car to match CabinMods.strut_bar.
static func sync(player: Vehicle) -> void:
	var vis: Node3D = player.get("chassis_visual")
	if vis == null:
		return
	var have := vis.get_node_or_null(NODE) as MeshInstance3D
	if CabinMods.strut_bar == (have != null):
		return
	if have != null:
		vis.remove_child(have)
		have.queue_free()
		return
	var kind := ""
	if player.has_method("chassis_kind"):
		kind = str(player.call("chassis_kind"))
	else:
		kind = str(vis.get_meta("kind", CabinSpots.DEFAULT_KIND))
	var mi := instance(kind)
	# the body's layer: CarFx moves the chassis to the car layer, the cockpit
	# moves it to the mirror-only layer; match whatever the Body has now
	var body := vis.get_node_or_null(^"Body") as VisualInstance3D
	if body != null:
		mi.layers = body.layers
	else:
		mi.layers = 1 << (CarFx.CAR_LAYER - 1)
	vis.add_child(mi)

## The bar as a node, car space, for a car kind.
static func instance(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = NODE
	mi.mesh = mesh(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## The bar mesh between CabinSpots.strut_bar(kind)'s ends.
static func mesh(kind: String) -> ArrayMesh:
	var ends := CabinSpots.strut_bar(kind)
	var l := ends[0]
	var r := ends[1]
	var k := CockpitKit.new()
	var span := r.x - l.x
	var mid := (l + r) * 0.5
	# the tube along x (a cylinder is built along y; turn it onto x)
	var along_x := Basis(Vector3.BACK, -PI / 2.0)
	k.cylinder(TUBE_R, -span * 0.5 + 0.03, span * 0.5 - 0.03, mid, SODIUM, 10, along_x)
	for e in [l, r]:
		var side := 1.0 if e.x > 0.0 else -1.0
		# tower plate: flat on the tower top, a little outboard of the tube's end
		k.box(Vector3(0.11, 0.006, 0.10), e + Vector3(0.0, -0.012, 0.0), SILVER)
		# three bolt heads
		for b in [Vector3(-0.035, 0.0, -0.03), Vector3(-0.035, 0.0, 0.03), Vector3(0.035, 0.0, 0.0)]:
			k.cylinder(0.007, -0.009, -0.001, e + b, INK, 6)
		# the upright from the plate up to the tube, and a brace wedge behind it
		k.box(Vector3(0.028, 0.03, 0.04), e + Vector3(-side * 0.02, 0.003, 0.0), SILVER)
		k.box(Vector3(0.05, 0.012, 0.012), e + Vector3(-side * 0.045, -0.004, 0.035), SILVER, Basis(Vector3.UP, side * 0.5))
	return k.commit(CockpitKit.material(0.45, 0.6, 0.3))

static func tri_count(kind: String) -> int:
	var m := mesh(kind)
	if m.get_surface_count() == 0:
		return 0
	return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
