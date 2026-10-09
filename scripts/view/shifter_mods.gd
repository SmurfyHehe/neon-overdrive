extends Node
class_name ShifterMods

# Shift knobs and the short shifter (interior mods batch 1, 2026-10-09): the
# cabin parts of CabinMods.shift_knob and CabinMods.short_shifter. A child of
# the CockpitFrame that swaps meshes on nodes the frame already owns, so the
# lever's animation, the hand's target (lever_knob) and the view test see the
# fitted part with nothing else changed:
#
# - knob: the MANUAL head ("Lever/Knob/KnobH") gets the chosen design's mesh.
#   The sequential and automatic grips are not knobs you unscrew, so they keep
#   their stock shape.
# - short shifter: the stick is CabinMods.SHORT_LEVER_SCALE of the stock
#   length, so the knob sits lower and travels less for the same gate angle
#   (the quicker shift itself is on the Vehicle, CabinMods.apply_sim).
#
# Polls CabinMods.version each physics tick (an int compare) and re-applies
# on a change, so a pause-menu pick shows at once.
#
# Designs are original, CockpitKit shapes in the cabin palette.

const LEATHER := Color("#121318")
const SILVER := Color("#C9CED6")
const INK := Color("#15171C")
const GRAPHITE := Color("#2A2E36")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")

var frame: CockpitFrame
var knob_id := ""
var short := false
var _version := -1
var _shaft: MeshInstance3D
var _mat: Material

func _init(cockpit: CockpitFrame) -> void:
	frame = cockpit
	name = "ShifterMods"

func _ready() -> void:
	_mat = CockpitKit.material(0.6, 0.2)
	for c in frame.lever.get_children():
		if c is MeshInstance3D:
			_shaft = c   # the stick (CockpitFrame._build_lever adds one shaft mesh)
	apply()

func _physics_process(_delta: float) -> void:
	if CabinMods.version != _version:
		apply()

## The lever's length now (m), stock or short.
func lever_length() -> float:
	return CockpitFrame.LEVER_LEN * (CabinMods.SHORT_LEVER_SCALE if short else 1.0)

## Fits the current CabinMods picks.
func apply() -> void:
	_version = CabinMods.version
	knob_id = CabinMods.shift_knob
	short = CabinMods.short_shifter
	var len := lever_length()
	frame.lever_knob.position = Vector3(0.0, len, 0.0)
	if _shaft != null:
		_shaft.mesh = shaft_mesh(len, _shaft.mesh.surface_get_material(0) if _shaft.mesh is ArrayMesh and (_shaft.mesh as ArrayMesh).get_surface_count() > 0 else null)
	var head := frame.get_node_or_null(^"Lever/Knob/KnobH") as MeshInstance3D
	if head != null:
		head.mesh = knob_mesh(knob_id, _mat)

## The stick: a silver rod up to the knob and a leather boot collar.
static func shaft_mesh(len: float, mat: Material) -> ArrayMesh:
	var k := CockpitKit.new()
	k.cylinder(0.008, 0.0, len - 0.02, Vector3.ZERO, SILVER, 8)
	k.cylinder(0.02, 0.0, 0.02, Vector3.ZERO, LEATHER, 8)
	return k.commit(mat)

## A knob head mesh, built about the knob point (an unknown id is stock).
static func knob_mesh(id: String, mat: Material) -> ArrayMesh:
	var k := CockpitKit.new()
	match id:
		"ball":
			_build_ball(k)
		"weighted":
			_build_weighted(k)
		"amber":
			_build_amber(k)
		_:
			_build_stock(k)
	return k.commit(mat)

## Stock (CockpitFrame._build_lever): leather block, silver top.
static func _build_stock(k: CockpitKit) -> void:
	k.box(Vector3(0.040, 0.046, 0.040), Vector3.ZERO, LEATHER)
	k.box(Vector3(0.028, 0.004, 0.028), Vector3(0.0, 0.025, 0.0), SILVER)

## A faceted alloy ball on a short collar: stacked rings, like a turned sphere.
static func _build_ball(k: CockpitKit) -> void:
	k.cylinder(0.010, -0.012, 0.0, Vector3.ZERO, INK, 8)   # collar
	var r := 0.023
	var steps := 5
	var y0 := -r * 0.7
	for i in steps:
		var a := y0 + (2.0 * r * 0.85) * float(i) / steps
		var b := y0 + (2.0 * r * 0.85) * float(i + 1) / steps
		var ym := (a + b) * 0.5
		var rr := sqrt(maxf(r * r - ym * ym, 0.0001))
		k.cylinder(rr, a, b, Vector3(0.0, r * 0.3, 0.0), SILVER, 12)

## A tall weighted knob: graphite cylinder, a silver band, a flat top.
static func _build_weighted(k: CockpitKit) -> void:
	k.cylinder(0.014, -0.012, 0.0, Vector3.ZERO, INK, 10)      # collar
	k.cylinder(0.018, 0.0, 0.052, Vector3.ZERO, GRAPHITE, 12)   # the weight
	k.cylinder(0.0185, 0.018, 0.024, Vector3.ZERO, SILVER, 12)  # band
	k.cylinder(0.015, 0.052, 0.058, Vector3.ZERO, SILVER, 12)   # cap
	k.box(Vector3(0.010, 0.002, 0.010), Vector3(0.0, 0.059, 0.0), SODIUM)   # the shift pattern badge

## An amber acrylic ball, faceted: a bipyramid of six, sodium on alternate faces.
static func _build_amber(k: CockpitKit) -> void:
	k.cylinder(0.010, -0.012, 0.004, Vector3.ZERO, SILVER, 8)   # collar
	var top := Vector3(0.0, 0.056, 0.0)
	var bot := Vector3(0.0, 0.004, 0.0)
	var mid_y := 0.028
	var r := 0.024
	var n := 6
	var ring := []
	for i in n:
		var a := TAU * float(i) / n
		ring.append(Vector3(cos(a) * r, mid_y, sin(a) * r))
	for i in n:
		var j := (i + 1) % n
		var shade := AMBER if i % 2 == 0 else SODIUM
		k.tri(top, ring[j], ring[i], shade)
		k.tri(bot, ring[i], ring[j], shade)
