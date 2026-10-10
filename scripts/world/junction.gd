extends Node3D
class_name Junction

# City lights, steps J0 + J1a (2026-10-09; Roy: yes to lights, solid crossing
# cars, amber flash after ~1 a.m., no red-light cameras). One signalised
# crossing on the main road, CENTRE_S metres from the start, behind the
# "City lights" switch in the pause menu's Traffic section (off by default,
# TrafficSettings.city_lights; NEON_CITY_LIGHTS=1/0 overrides it for a run).
#
# J0, the place: a cross street at right angles (2 lanes each way), the
# roadside buildings, gap walls, delineators and street lamps cleared from its
# mouth (RoadChunkBuilder asks cleared()/in_mouth() while it lays out a chunk),
# no lane dashes or centre barrier inside the box, stop lines and zebra
# crossings on every approach, and a signal mast on each corner. The cross
# street is scenery for now: the out-of-bounds walls still run across its
# mouth like everywhere else along the road.
#
# J1a, the rule: traffic on the main road stops for red. The trick is the
# follower law traffic already has (TrafficCar.follow_accel): a red light is
# an invisible stopped car whose back bumper is the stop line, so a car slows
# for it exactly as it would for a queue, and the cars behind queue behind
# that car as usual. stop_gap() answers "is there such a car in front of me,
# and how far". Nothing is put in the occupancy index, so spawns, lane changes
# and the player never see it.
#   Amber: a car that can stop at B_AMBER or less stops; one that can't goes
#   (the dilemma zone). Red: the same at B_RED, so a car that was already
#   committed when amber began is not made to slam on in the box.
#   Flash (after FLASH_FROM, about 1 a.m.): the main road flashes amber, the
#   cross street red, and main-road traffic does not stop.
# The player is never stopped and nothing watches the player at red.
#
# The 12 s stuck-car check (TrafficCar.STUCK_SECONDS) is shorter than the
# 22 s red: a car at the head of a red queue has nothing ahead of it, so it
# looked stuck and would have been flagged wrecked mid-red. TrafficCar skips
# that check (and obstacle lane changes) while signal_held is set.
#
# Cost: the whole crossing is one static mesh (paint, kerbs, poles, housings)
# plus six lamp meshes, one per lamp colour and group, so 7 draw calls; the
# lamp state is a material change on those six. No lights.

#
# The map (road_map.gd, 2026-10-10): on a loop there is a crossing just inside
# each end of every city area and none on the highway stretches. They are far
# apart (over a kilometre), so there is still one Junction node: it stands at
# the crossing nearest the player (focus_z, set by Game) and every question
# here is answered for the crossing nearest to where it is asked. All of them
# share the one signal cycle.

const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadPaint := preload("res://scripts/world/road_paint.gd")
const RoadSigns := preload("res://scripts/world/road_signs.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")

const L := RoadChunkBuilder.CHUNK_LEN
## Where the crossing's centre is, metres of road from the start (off a loop).
const CENTRE_S := 600.0
## Cross street: 2 lanes each way.
const CROSS_LANES := 2
const CROSS_HALF := RoadChunkBuilder.MEDIAN_GAP + CROSS_LANES * RoadChunkBuilder.LANE_W  # 6.8 m, kerb to centre
const CROSS_KERB := 0.3
const CROSS_WALK_W := 2.2
## Half the opening along the main road: carriageway plus kerb and sidewalk.
const MOUTH_HALF := CROSS_HALF + CROSS_KERB + CROSS_WALK_W  # 9.3 m
## Buildings overlapping this much either side of the centre are cleared, so
## the corner reads as a corner rather than a wall at the kerb.
const CLEAR_HALF := MOUTH_HALF + 2.0
## Zebra crossing, then the stop line, outward from the box.
const ZEBRA_IN := CROSS_HALF + 0.8
const ZEBRA_LEN := 3.0
const STOP_LINE_W := 0.45
## Stop line (its upstream edge) from the centre along the main road.
const STOP_OFF := ZEBRA_IN + ZEBRA_LEN + 0.6 + STOP_LINE_W  # 11.65 m
## How far the cross street is drawn out from the main road's centre line.
const CROSS_REACH := 90.0

## Main-road half width to the shoulder's outer edge and to the sidewalk's.
const MAIN_ROAD_HALF := RoadChunkBuilder.MEDIAN_GAP + 4 * RoadChunkBuilder.LANE_W  # 13.2
const MAIN_SHOULDER := MAIN_ROAD_HALF + RoadChunkBuilder.SHOULDER_W
const MAIN_WALK := MAIN_SHOULDER + RoadChunkBuilder.CURB_W + RoadChunkBuilder.SIDEWALK_W

## Signal timing, seconds. Main road: GREEN_S, AMBER_S, then red for
## ALL_RED_S + CROSS_GREEN_S + AMBER_S + ALL_RED_S = 22 s.
const GREEN_S := 30.0
const AMBER_S := 3.0
const ALL_RED_S := 2.0
const CROSS_GREEN_S := 15.0
const CYCLE := GREEN_S + AMBER_S + ALL_RED_S + CROSS_GREEN_S + AMBER_S + ALL_RED_S
const MAIN_RED_S := CYCLE - GREEN_S - AMBER_S
## Flashing amber from 1 a.m. (NightClock minutes since 8 p.m.) to the end
## of the night.
const FLASH_FROM := 300.0
const FLASH_PERIOD := 1.0

## Deceleration a car accepts to stop for amber / for red, m/s^2. Over it, it
## goes. 3.0 is a firm but ordinary stop (TrafficCar.B_COMF is 2.5); 6.0 is
## close to an emergency stop, so red only lets through a car that really
## could not stop when amber began.
const B_AMBER := 3.0
const B_RED := 6.0
## Where the invisible stopped car's back bumper sits, metres short of the
## stop line. The follower creeps up to about 0.7 m inside its standstill gap
## (tests/world/junction_lights.gd: 1.0 here left the queue heads 0.1-0.4 m short),
## so 2.0 puts them about a metre short.
const STOP_SHORT := 2.0
## A car whose front is this far past the line counts as through.
const PAST_LINE := 0.5
## Cars further back than this do not look at the light yet.
const LOOK := 200.0

enum {GREEN, AMBER, RED, FLASH_AMBER, FLASH_RED, DARK}

## Whether the crossing exists this run (set by Game from TrafficSettings
## before the first chunk is built; RoadChunkBuilder reads it).
static var enabled := false

## Seconds into the cycle (0 = main road turns green).
var t := 0.0
## The night clock, for the 1 a.m. flash (null = never flash).
var night_clock: NightClock
## Tests pin the flash on or off: -1 = follow the clock, 0 = off, 1 = on.
var force_flash := -1

var _origin := -999999
var _placed_z := INF
var _main_key := -1
var _cross_key := -1
var _blink := 0.0
var _mats: Array[StandardMaterial3D] = []  # main R, A, G, cross R, A, G

const RED_C := Color(1.0, 0.12, 0.05)
const AMBER_C := Color(1.0, 0.6, 0.1)
## The RPM bar's green (#3FD060, tests/core/palette.gd's allowlist): a signal has
## to say green, and this one is already in the game.
const GREEN_C := Color("#3FD060")
const LAMP_ON := 4.0
const LAMP_OFF := 0.04

## Road-space z the crossing node keeps near: the player's (Game sets it).
static var focus_z := 0.0

## Centre of the crossing nearest to `s` metres along the road, in the same
## metres.
static func centre_s_near(s: float) -> float:
	return RoadMap.junction_near(s) if RoadMap.is_loop() else CENTRE_S

## Road-space z of the crossing nearest to road-space z.
static func centre_z_near(z: float) -> float:
	return float(RoadFrame.origin_index) * L - centre_s_near(RoadFrame.s_at(z))

## Road-space z of the crossing the node stands at (the one nearest the player).
static func centre_z() -> float:
	return centre_z_near(focus_z)

## Chunk-local z of the centre for chunk `chunk_index` (0 at the chunk's
## start, -L at its end; outside that range the centre is in another chunk).
static func local_centre(chunk_index: int) -> float:
	return float(chunk_index) * L - centre_s_near((float(chunk_index) + 0.5) * L)

## Whether chunk-local z (chunk `chunk_index`) is within `half` of the centre.
static func near(chunk_index: int, z: float, half: float) -> bool:
	return enabled and absf(z - local_centre(chunk_index)) < half

## Whether a building spanning [z0, z1] (chunk-local, either order) has to go.
static func cleared(chunk_index: int, z0: float, z1: float) -> bool:
	if not enabled:
		return false
	var c := local_centre(chunk_index)
	return maxf(z0, z1) > c - CLEAR_HALF and minf(z0, z1) < c + CLEAR_HALF

static func in_mouth(chunk_index: int, z: float) -> bool:
	return near(chunk_index, z, MOUTH_HALF + 0.5)

## No lane dashes between the stop lines.
static func in_box(chunk_index: int, z: float) -> bool:
	return near(chunk_index, z, STOP_OFF - STOP_LINE_W)

## Whether chunk `chunk_index` has any part of the crossing in it.
static func touches(chunk_index: int) -> bool:
	var c := local_centre(chunk_index)
	return enabled and c < CLEAR_HALF and c > -L - CLEAR_HALF

## Light for main-road traffic at cycle time `tt` (no flash).
static func main_state_at(tt: float) -> int:
	var x := fposmod(tt, CYCLE)
	if x < GREEN_S:
		return GREEN
	if x < GREEN_S + AMBER_S:
		return AMBER
	return RED

static func cross_state_at(tt: float) -> int:
	var x := fposmod(tt, CYCLE) - GREEN_S - AMBER_S - ALL_RED_S
	if x >= 0.0 and x < CROSS_GREEN_S:
		return GREEN
	if x >= CROSS_GREEN_S and x < CROSS_GREEN_S + AMBER_S:
		return AMBER
	return RED

func flashing() -> bool:
	if force_flash >= 0:
		return force_flash == 1
	return night_clock != null and night_clock.minutes >= FLASH_FROM

func main_state() -> int:
	return FLASH_AMBER if flashing() else main_state_at(t)

func cross_state() -> int:
	return FLASH_RED if flashing() else cross_state_at(t)

## The invisible stopped car (see the header): for a main-road car whose
## centre is at road-space z, driving along `dir` (-1 own, +1 oncoming) at v
## m/s with half length half_l, the distance from its front bumper to the
## stop line if it must stop for the light, else INF.
func stop_gap(z: float, dir: float, half_l: float, v: float) -> float:
	if not enabled:
		return INF
	var st := main_state()
	if st == GREEN or st == FLASH_AMBER:
		return INF
	var line := centre_z_near(z) - dir * STOP_OFF
	var d := (line - z) * dir - half_l
	if d < -PAST_LINE or d > LOOK:
		return INF
	var need := v * v / (2.0 * maxf(d, 0.1))
	if need > (B_AMBER if st == AMBER else B_RED):
		return INF
	return d

func _ready() -> void:
	name = "Junction"
	visible = enabled
	if not enabled:
		set_physics_process(false)
		return
	for i in 6:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.02, 0.02, 0.02)
		m.emission_enabled = true
		m.emission = [RED_C, AMBER_C, GREEN_C][i % 3]
		m.emission_energy_multiplier = LAMP_OFF
		_mats.append(m)
	_build()
	_place()
	_show()

func _physics_process(delta: float) -> void:
	t = fposmod(t + delta, CYCLE)
	_blink = fposmod(_blink + delta, FLASH_PERIOD)
	_place()
	_show()

## Follows the floating origin (game.gd moves the world back by whole chunks).
func _place() -> void:
	var cz := centre_z()
	if RoadFrame.origin_index == _origin and cz == _placed_z:
		return
	_origin = RoadFrame.origin_index
	_placed_z = cz
	global_transform = RoadFrame.pose(0.0, 0.0, cz, 0.0)
	reset_physics_interpolation()

func _show() -> void:
	var on := _blink < FLASH_PERIOD * 0.5
	var mk := main_state()
	var ck := cross_state()
	var key_m := mk * 2 + (1 if on else 0)
	var key_c := ck * 2 + (1 if on else 0)
	if key_m != _main_key:
		_main_key = key_m
		_light(0, mk, on)
	if key_c != _cross_key:
		_cross_key = key_c
		_light(3, ck, on)

func _light(base: int, st: int, blink_on: bool) -> void:
	var r := st == RED or (st == FLASH_RED and blink_on)
	var a := st == AMBER or (st == FLASH_AMBER and blink_on)
	var g := st == GREEN
	_mats[base].emission_energy_multiplier = LAMP_ON if r else LAMP_OFF
	_mats[base + 1].emission_energy_multiplier = LAMP_ON if a else LAMP_OFF
	_mats[base + 2].emission_energy_multiplier = LAMP_ON if g else LAMP_OFF

## Lamp currently lit for main / cross traffic (tests, the HUD later):
## "red", "amber", "green" or "" (dark, e.g. the off half of a flash).
func lit(cross: bool) -> String:
	var base := 3 if cross else 0
	for i in 3:
		if _mats.size() > base + i and _mats[base + i].emission_energy_multiplier > 1.0:
			return ["red", "amber", "green"][i]
	return ""

# ---------- geometry (J0) ----------

func _build() -> void:
	var paint := RoadChunkBuilder._flat_mat(RoadChunkBuilder.LANE_DASH_COLOR, true, RoadChunkBuilder.PAINT_ENERGY)
	var yellow := RoadChunkBuilder._flat_mat(RoadChunkBuilder.CENTER_COLOR, true, RoadChunkBuilder.PAINT_ENERGY)
	var metal := RoadChunkBuilder._flat_mat(Color(0.13, 0.13, 0.14))
	metal.roughness = 0.6
	var housing := RoadChunkBuilder._flat_mat(Color(0.05, 0.05, 0.05))

	# Asphalt and kerbs: the cross street out to CROSS_REACH each way, and an
	# apron over the main road's kerb and sidewalk in the mouth.
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cw := CROSS_HALF + RoadChunkBuilder.SHOULDER_W
	for s: float in [1.0, -1.0]:
		_quad(road, Vector3(s * MAIN_SHOULDER, 0.012, -cw), Vector3(s * CROSS_REACH, 0.012, cw))
		_quad(road, Vector3(s * MAIN_SHOULDER, 0.105, -cw), Vector3(s * (MAIN_WALK + 0.6), 0.105, cw))
	var walk := SurfaceTool.new()
	walk.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: float in [1.0, -1.0]:
		for zs: float in [1.0, -1.0]:
			# the cross street's own sidewalks
			_quad(walk, Vector3(s * (MAIN_WALK + 0.6), 0.1, zs * cw), Vector3(s * CROSS_REACH, 0.1, zs * (cw + CROSS_KERB + CROSS_WALK_W)))

	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := SurfaceTool.new()
	mid.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Main road: stop lines across the approach lanes, zebras across the whole road.
	var line_z := STOP_OFF - STOP_LINE_W / 2.0
	_quad(lines, Vector3(0.2, 0.02, line_z - STOP_LINE_W / 2.0), Vector3(MAIN_ROAD_HALF, 0.02, line_z + STOP_LINE_W / 2.0))
	_quad(lines, Vector3(-MAIN_ROAD_HALF, 0.02, -line_z - STOP_LINE_W / 2.0), Vector3(-0.2, 0.02, -line_z + STOP_LINE_W / 2.0))
	for zs: float in [1.0, -1.0]:
		var x := -MAIN_ROAD_HALF + 0.3
		while x < MAIN_ROAD_HALF - 0.3:
			_quad(lines, Vector3(x, 0.02, zs * ZEBRA_IN), Vector3(x + 0.5, 0.02, zs * (ZEBRA_IN + ZEBRA_LEN)))
			x += 1.0
	# Cross street: centre line, lane dashes, stop lines, zebras.
	# past the apron over the main road's sidewalk
	var x0 := MAIN_WALK + 1.0
	var cross_stop := x0 + ZEBRA_LEN + 0.6
	for s: float in [1.0, -1.0]:
		_quad(mid, Vector3(s * cross_stop, 0.02, -0.18), Vector3(s * CROSS_REACH, 0.02, -0.06))
		_quad(mid, Vector3(s * cross_stop, 0.02, 0.06), Vector3(s * CROSS_REACH, 0.02, 0.18))
		var dx := cross_stop + 1.0
		while dx < CROSS_REACH - 2.4:
			for zs: float in [1.0, -1.0]:
				var lz: float = zs * (RoadChunkBuilder.MEDIAN_GAP + RoadChunkBuilder.LANE_W)
				_quad(lines, Vector3(s * dx, 0.02, lz - 0.1), Vector3(s * (dx + 2.4), 0.02, lz + 0.1))
			dx += 4.0
		# stop line on the lanes that approach from this side (right-hand
		# traffic: coming in toward the centre from +x, the lanes at -z)
		var zl := -s * 0.2
		var zr := -s * CROSS_HALF
		_quad(lines, Vector3(s * cross_stop, 0.02, minf(zl, zr)), Vector3(s * (cross_stop + STOP_LINE_W), 0.02, maxf(zl, zr)))
		var z := -CROSS_HALF + 0.3
		while z < CROSS_HALF - 0.3:
			_quad(lines, Vector3(s * x0 + (0.0 if s > 0 else -ZEBRA_LEN), 0.02, z), Vector3(s * x0 + (ZEBRA_LEN if s > 0 else 0.0), 0.02, z + 0.5))
			z += 1.0

	# Signal masts, one on each corner (far side for the traffic it faces).
	var poles := SurfaceTool.new()
	poles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heads := SurfaceTool.new()
	heads.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lamps: Array[SurfaceTool] = []
	for i in 6:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		lamps.append(st)
	var corner := MAIN_SHOULDER + 0.7
	var corner_z := cw + 0.9
	# Main road, own direction (driving -z): far-right corner (+x, -z), heads face +z.
	_mast(poles, heads, lamps, 0, Vector3(corner, 0.0, -corner_z), 0.0, [4.0, 10.4])
	# Oncoming (driving +z): far-right corner (-x, +z), heads face -z.
	_mast(poles, heads, lamps, 0, Vector3(-corner, 0.0, corner_z), PI, [4.0, 10.4])
	# Cross street, from +x (driving -x): far-right corner (-x, -z), faces +x.
	_mast(poles, heads, lamps, 3, Vector3(-corner, 0.0, -corner_z), PI / 2.0, [])
	# From -x (driving +x): far-right corner (+x, +z), faces -x.
	_mast(poles, heads, lamps, 3, Vector3(corner, 0.0, corner_z), -PI / 2.0, [])

	_build_names(corner, corner_z, cross_stop)

	_add_mesh("CrossRoad", road, RoadChunkBuilder._get_own_mat())
	_add_mesh("CrossWalks", walk, RoadChunkBuilder._get_sidewalk_mat())
	_add_mesh("Paint", lines, paint)
	_add_mesh("CentreLine", mid, yellow)
	_add_mesh("Poles", poles, metal)
	_add_mesh("Heads", heads, housing)
	for i in 6:
		_add_mesh("Lamps%d" % i, lamps[i], _mats[i])

## Names at the crossing (world step 4): a street-name blade on each signal
## mast (the cross street's name on the main road's masts, the main road's on
## the cross street's), and STOP painted on the cross street's approach
## lanes (it flashes red after 1 a.m.). Two small MultiMeshes, flat in the
## crossing's own frame like the rest of it. The crossing is number 0: there
## is only one on the road, so its cross street is PlaceNames.cross_street(0).
func _build_names(corner: float, corner_z: float, cross_stop: float) -> void:
	var signs := RoadSigns.new_multimesh(8)
	signs.name = "StreetNames"
	# [mast base, yaw, name, on an arm]: the heads (and the blade) face +z at yaw 0
	var masts := [
		[Vector3(corner, 0.0, -corner_z), 0.0, PlaceNames.cross_street(0), true],
		[Vector3(-corner, 0.0, corner_z), PI, PlaceNames.cross_street(0), true],
		[Vector3(-corner, 0.0, -corner_z), PI / 2.0, PlaceNames.MAIN_STREET, false],
		[Vector3(corner, 0.0, corner_z), -PI / 2.0, PlaceNames.MAIN_STREET, false],
	]
	var k := 0
	for m in masts:
		var xf := Transform3D(Basis(Vector3.UP, float(m[1])), m[0])
		var n: Vector3 = xf.basis * Vector3.BACK
		# on top of the arm between the pole and the first head, or on the
		# pole's top where there is no arm
		var local := Vector3(-1.9, 6.13, 0.0) if m[3] else Vector3(0.0, 3.85, 0.14)
		var b := RoadSigns.blade(String(m[2]), xf * local, n)
		signs.multimesh.set_instance_transform(k, b.xf)
		signs.multimesh.set_instance_custom_data(k, b.cd)
		k += 1
	signs.multimesh.visible_instance_count = k
	add_child(signs)

	var paint := RoadPaint.new_multimesh(8, "StopPaint")
	var n_paint := 0
	for s: float in [1.0, -1.0]:
		for i in CROSS_LANES:
			# in the approach lanes, a little upstream of the stop line
			var x := s * (cross_stop + STOP_LINE_W + 5.0)
			var z := -s * (RoadChunkBuilder.MEDIAN_GAP + (float(i) + 0.5) * RoadChunkBuilder.LANE_W)
			var it := RoadPaint.item("STOP", x, z, s * PI / 2.0)
			paint.multimesh.set_instance_transform(n_paint, Transform3D(it.basis, Vector3(x, 0.03, z)))
			paint.multimesh.set_instance_custom_data(n_paint, it.cd)
			n_paint += 1
	paint.multimesh.visible_instance_count = n_paint
	add_child(paint)

## A pole at `base` with an arm out over the lanes (one head per entry in
## `arm_x`, metres in from the pole) plus one head on the pole itself.
## `yaw` turns the whole mast; at 0 the heads face +z and the arm reaches -x.
func _mast(poles: SurfaceTool, heads: SurfaceTool, lamps: Array[SurfaceTool], group: int, base: Vector3, yaw: float, arm_x: Array) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), base)
	var pole_h := 6.2 if not arm_x.is_empty() else 4.2
	_box(poles, xf * Transform3D(Basis(), Vector3(0.0, pole_h / 2.0, 0.0)), Vector3(0.22, pole_h, 0.22))
	var heads_at: Array = [Vector3(0.0, 2.9, 0.25)]
	if not arm_x.is_empty():
		var reach: float = arm_x.max() + 0.8
		_box(poles, xf * Transform3D(Basis(), Vector3(-reach / 2.0, 5.9, 0.0)), Vector3(reach, 0.16, 0.16))
		for ax in arm_x:
			heads_at.append(Vector3(-float(ax), 5.15, 0.0))
	for h in heads_at:
		var hx := xf * Transform3D(Basis(), h)
		_box(heads, hx * Transform3D(Basis(), Vector3(0.0, 0.0, -0.02)), Vector3(0.62, 1.42, 0.04))  # back plate
		_box(heads, hx * Transform3D(Basis(), Vector3(0.0, 0.0, 0.14)), Vector3(0.38, 1.12, 0.28))   # housing
		for k in 3:
			var ly := 0.36 - 0.36 * float(k)
			_box(heads, hx * Transform3D(Basis(), Vector3(0.0, ly + 0.15, 0.36)), Vector3(0.32, 0.03, 0.18))  # visor
			_box(lamps[group + k], hx * Transform3D(Basis(), Vector3(0.0, ly, 0.29)), Vector3(0.24, 0.24, 0.02))

func _add_mesh(n: String, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	st.generate_normals()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Flat quad between two corners (x0, z0) and (x1, z1) at height a.y, facing up.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var z0 := minf(a.z, b.z)
	var z1 := maxf(a.z, b.z)
	var y := a.y
	var p00 := Vector3(x0, y, z0)
	var p10 := Vector3(x1, y, z0)
	var p01 := Vector3(x0, y, z1)
	var p11 := Vector3(x1, y, z1)
	# Godot's front faces wind clockwise: p00 -> p10 -> p11 is clockwise seen
	# from above (x right, -z up the screen).
	for p in [p00, p10, p11, p00, p11, p01]:
		st.set_uv(Vector2(p.x, p.z) * 0.1)
		st.add_vertex(p)

## Box of `size` centred at xf.origin, oriented by xf.basis.
static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	var h := size / 2.0
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	# Each face wound clockwise seen from outside (Godot's front face).
	var faces := [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [7, 6, 2, 3], [0, 1, 5, 4]]
	for f in faces:
		var q: Array = []
		for i in f:
			q.append(xf * c[i])
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_uv(Vector2.ZERO)
			st.add_vertex(q[i])
