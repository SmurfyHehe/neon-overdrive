extends Node3D

# Gas stations, first slice (Stage C stops, 2026-10-09). Roy: there was no way
# to fill up, so the car ran dry and limped for the rest of the night.
#
# The stops plan wants an exit that leads to a station. Exits are not built yet
# (RoadLayout.exits_live, road lane steps 4-5), so for now a station stands
# right on the road: a pump bay on the own-side shoulder and sidewalk under a
# canopy, every SPACING metres from FIRST_S. When exits land, the station moves
# behind one; the fuel rules below stay the same.
#
# Pull into the bay and stop: after HOLD_S the pump menu opens
# (scripts/ui/pump_panel.gd, GameState.State.STATION). No key hint on screen
# (Roy's UI rule): stopping at the pump is the action.
#
# One station mesh, moved to whichever station is nearest the player: they
# are SPACING apart, far past the draw distance, so two are never in view.
# RoadChunkBuilder asks cleared()/in_bay() so the buildings, lamps and edge
# posts make room, like the crossing does (Junction).
#
# Cost: 3 draw calls (concrete, lit canopy underside, amber sign) plus the
# sign's text and one fake light pool. No real lights. One static body.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const L := RoadChunkBuilder.CHUNK_LEN

## Where the first station is and how far apart they are, metres of road.
## A third of a tank (the start) lasts about 9 km of mixed driving and the
## FUEL light leaves about 3-4 km (FuelTank), so a station is always in reach
## of the light; a dry tank still limps there at LimpMode.FUEL_KMH.
const DEFAULT_FIRST_S := 1500.0
const SPACING := 3000.0
## The bay, relative to the station centre: car centre within BAY_HALF_S
## along the road and between BAY_X.x and BAY_X.y metres out from the own
## road edge (the island starts at 3.0, so a car centred at 2 still clears it).
const BAY_HALF_S := 5.0
const BAY_X := Vector2(0.2, 2.6)
## Stopped means under STOP_SPEED m/s for HOLD_S seconds.
const STOP_SPEED := 1.0
const HOLD_S := 0.6
## How much road the station clears of buildings, lamps and edge posts.
const CLEAR_HALF := 14.0

## Off in benchmark runs (same road every time). Read before the first chunk.
static var enabled := true
## Tests move the first station next to the spawn.
static var first_s := DEFAULT_FIRST_S

signal pulled_up(station_s: float)

var player: Node3D
## The station the mesh stands at (metres of road), and the floating origin it
## was placed for.
var station_s := -1.0
var _origin := -999999
var _held := 0.0
## False after the menu closed until the car leaves the bay, so it does not
## open again the moment the player shuts it.
var armed := true

# ---------- where the stations are (static, no node needed) ----------

## Metres of road of station k (k = 0, 1, ...).
static func s_of(k: int) -> float:
	return first_s + float(k) * SPACING

## The station nearest `s`.
static func nearest(s: float) -> float:
	return s_of(maxi(0, roundi((s - first_s) / SPACING)))

## The next station ahead of `s`; one the car is still in the bay of counts.
static func next_after(s: float) -> float:
	return s_of(maxi(0, ceili((s - BAY_HALF_S - first_s) / SPACING)))

## Distance from the centre line to the own side's road edge at `s`.
static func own_edge(s: float) -> float:
	var lanes := RoadChunkBuilder.MAX_OWN_LANES
	if RoadFrame.layout != null and RoadFrame.layout.lanes_live:
		lanes = RoadFrame.layout.lanes_at(false, s)
	return RoadChunkBuilder.MEDIAN_GAP + float(lanes) * RoadChunkBuilder.LANE_W

## Chunk-local z (0 at the chunk start, -L at its end) of the station nearest
## chunk `chunk_index`.
static func _local(chunk_index: int, z: float) -> float:
	var s := float(chunk_index) * L - z
	return float(chunk_index) * L - nearest(s)

## Whether own-side chunk-local z is within `half` of a station.
static func near(chunk_index: int, z: float, half: float) -> bool:
	return enabled and absf(z - _local(chunk_index, z)) < half

## Whether an own-side building spanning [z0, z1] (chunk-local) has to go.
static func cleared(chunk_index: int, z0: float, z1: float) -> bool:
	if not enabled:
		return false
	var c := _local(chunk_index, (z0 + z1) / 2.0)
	return maxf(z0, z1) > c - CLEAR_HALF and minf(z0, z1) < c + CLEAR_HALF

## No own-side lamp or edge post here.
static func in_bay(chunk_index: int, z: float) -> bool:
	return near(chunk_index, z, CLEAR_HALF)

## Road-space position of a node: x across (own side +), s along.
static func road_pos(n: Node3D) -> Vector2:
	var u := RoadFrame.unroll(n.global_position)
	return Vector2(u.x, RoadFrame.s_at(u.z))

## Whether road position `p` (x, s) is in the bay of the station at `ss`.
static func in_spot(p: Vector2, ss: float) -> bool:
	var x := p.x - own_edge(ss)
	return absf(p.y - ss) <= BAY_HALF_S and x >= BAY_X.x and x <= BAY_X.y

# ---------- the node ----------

func _ready() -> void:
	name = "GasStation"
	visible = enabled
	if not enabled:
		set_physics_process(false)
		return
	_build()
	_place()

func _physics_process(delta: float) -> void:
	_place()
	if player == null:
		return
	var p := road_pos(player)
	var in_bay_now := in_spot(p, station_s)
	if not in_bay_now:
		armed = true
		_held = 0.0
		return
	var v: Vector3 = player.get("linear_velocity") if player.get("linear_velocity") != null else Vector3.ZERO
	if v.length() < STOP_SPEED:
		_held += delta
	else:
		_held = 0.0
	if armed and _held >= HOLD_S:
		armed = false
		pulled_up.emit(station_s)

## Follows the player from station to station and the floating origin.
func _place() -> void:
	var s := nearest(road_pos(player).y) if player != null else first_s
	if s == station_s and RoadFrame.origin_index == _origin:
		return
	station_s = s
	_origin = RoadFrame.origin_index
	var z := float(RoadFrame.origin_index) * L - s
	global_transform = RoadFrame.pose(own_edge(s), 0.0, z, 0.0)
	reset_physics_interpolation()

# Local frame: x = 0 is the own road edge, +x away from the road, -z ahead.
# Shoulder 0..1.4, curb 1.4..1.7, sidewalk 1.7..3.9 (RoadChunkBuilder).
const ISLAND := Rect2(3.0, -3.2, 0.8, 6.4)    # x, z, width, length
const CANOPY_X := Vector2(0.2, 4.6)
const CANOPY_Z := 7.5
const CANOPY_Y := 4.6
const SIDEWALK_Y := 0.15

const CONCRETE := Color(0.42, 0.42, 0.44)
const CANOPY_LIT := Color(1.0, 0.86, 0.62)   # warm sodium-white under the roof
const SIGN_AMBER := Color("#FFC066")
const NAVY := Color("#0E1424")

func _build() -> void:
	var concrete := SurfaceTool.new()
	concrete.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sign := SurfaceTool.new()
	sign.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ix := ISLAND.position.x + ISLAND.size.x / 2.0
	# pump island, two pumps, two canopy pillars on the island
	_box(concrete, Vector3(ix, SIDEWALK_Y + 0.1, 0.0), Vector3(ISLAND.size.x, 0.2, ISLAND.size.y))
	for z in [-1.4, 1.4]:
		_box(concrete, Vector3(ix, SIDEWALK_Y + 0.95, z), Vector3(0.5, 1.5, 0.45))
		_box(sign, Vector3(ix - 0.26, SIDEWALK_Y + 1.35, z), Vector3(0.02, 0.35, 0.3))  # lit pump display
	for z in [-2.9, 2.9]:
		_box(concrete, Vector3(ix, CANOPY_Y / 2.0, z), Vector3(0.35, CANOPY_Y, 0.35))
	# canopy: a concrete slab with a lit underside
	var cx := (CANOPY_X.x + CANOPY_X.y) / 2.0
	var cw := CANOPY_X.y - CANOPY_X.x
	_box(concrete, Vector3(cx, CANOPY_Y + 0.35, 0.0), Vector3(cw, 0.6, CANOPY_Z * 2.0))
	_box(lit, Vector3(cx, CANOPY_Y + 0.03, 0.0), Vector3(cw - 0.3, 0.06, CANOPY_Z * 2.0 - 0.3))
	# amber edge band round the canopy, the station's read from far off
	_box(sign, Vector3(CANOPY_X.x - 0.02, CANOPY_Y + 0.35, 0.0), Vector3(0.04, 0.25, CANOPY_Z * 2.0))
	# price sign before the bay, facing the traffic that comes from +z
	var sz := CANOPY_Z + 8.0
	_box(concrete, Vector3(ix, 3.0, sz), Vector3(0.3, 6.0, 0.3))
	_box(sign, Vector3(ix, 6.4, sz), Vector3(0.3, 1.4, 2.4))
	_add(concrete, _mat(CONCRETE, false), "Concrete")
	_add(lit, _mat(CANOPY_LIT, true, 2.2), "CanopyLight")
	_add(sign, _mat(SIGN_AMBER, true, 1.6), "Sign")
	var label := Label3D.new()
	label.name = "SignText"
	label.text = "FUEL"
	label.font_size = 96
	label.pixel_size = 0.006
	label.modulate = NAVY
	label.outline_size = 0
	label.position = Vector3(ix, 6.4, sz + 0.17)
	add_child(label)
	# the light the canopy throws on the bay (a fake pool, like the street lamps)
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	pool.mesh = RoadChunkBuilder._get_pool_mesh()
	pool.material_override = RoadChunkBuilder._get_pool_mat()
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.transform = Transform3D(Basis.from_scale(Vector3(7.0, 1.0, 14.0)), Vector3(cx, RoadChunkBuilder.POOL_Y + SIDEWALK_Y, 0.0))
	add_child(pool)
	# one body: the island with its pumps and pillars (the canopy is out of reach)
	var body := StaticBody3D.new()
	body.name = "Island"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ISLAND.size.x, 1.8, ISLAND.size.y)
	shape.shape = box
	shape.position = Vector3(ix, SIDEWALK_Y + 0.9, 0.0)
	body.add_child(shape)
	add_child(body)

func _add(st: SurfaceTool, mat: Material, n: String) -> void:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = st.commit()
	mi.material_override = mat
	if n != "Concrete":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

static func _mat(c: Color, emissive: bool, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c if not emissive else c * 0.3
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m

static func _box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size / 2.0
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		st.add_vertex(p[f[0]])
		st.add_vertex(p[f[1]])
		st.add_vertex(p[f[2]])
		st.add_vertex(p[f[0]])
		st.add_vertex(p[f[2]])
		st.add_vertex(p[f[3]])
