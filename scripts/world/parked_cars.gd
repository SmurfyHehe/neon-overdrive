extends RefCounted
# Parked cars at the kerb (street life L5, 2026-10-14): rows of dark cars
# asleep on the shoulder in the districts whose shoulder is wide enough
# (downtown, residential, old town, lofts). Among them, now and then: one
# with its alarm LED blinking red in the windscreen, one with its dome
# light on, one left on hazards (double-parked, nobody in it).
#
# ZERO per-frame script work. Which slots hold a car, its colour and its
# mode come from the roadside kit's chunk-seeded RNG (roadside_kit.gd lays
# them out beside its cones and bins, so a parked car never sits in a work
# zone, a crossing, a side-street mouth or a hydrant's painted kerb). One
# MultiMesh per chunk ("KitCars", one draw call, none on a chunk with no
# car); the blinks are the shader reading TIME. Every car is solid: a box
# on the kit's metal wall body, like the dumpsters.

const SIZE := Vector3(1.7, 1.45, 4.3)        # across, high, long
const ON_SHOULDER := 0.95                    # centre inside the kerb's inner edge
const MIN_SHOULDER := 2.0                    # m, no parking on a narrower shoulder
const SLOT := 6.2                            # m of kerb per parking slot
const CAP := 6                               # per chunk (the triangle budget)
## Per district: expected cars per side per 50 m chunk. Narrow-shoulder
## districts get none (the car would stand in the lane).
const BY_DISTRICT := {
	"downtown": 1.6, "residential": 2.6, "strip": 0.0, "industrial": 0.0,
	"old_town": 3.0, "lofts": 2.2, "hillside": 0.0, "airport": 0.0,
	"docks": 0.0, "freeway": 0.0, "canyon": 0.0,
}
## Modes, in per cent of the parked cars.
const MODE_PLAIN := 0
const MODE_ALARM := 1    # red LED blinking on the dash
const MODE_DOME := 2     # dome light on, warm glass
const MODE_HAZARD := 3   # hazards blinking
const SHARE_ALARM := 12
const SHARE_DOME := 6
const SHARE_HAZARD := 4
## Muted paints: cars asleep under a lamp, not heroes.
const TINTS := [
	Color(0.35, 0.35, 0.37), Color(0.22, 0.20, 0.19), Color(0.30, 0.12, 0.10),
	Color(0.42, 0.42, 0.40), Color(0.14, 0.17, 0.26), Color(0.26, 0.24, 0.16),
]
## Mesh part tags (UV2.x): what the shader lights per mode.
const TAG_BODY := 0.0
const TAG_LED := 1.0
const TAG_GLASS := 2.0
const TAG_HAZARD := 3.0

static var enabled := true
static var _enabled_read := false
static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

static func _read_enabled() -> void:
	if _enabled_read:
		return
	_enabled_read = true
	if OS.has_environment("NEON_PARKED_CARS"):
		enabled = OS.get_environment("NEON_PARKED_CARS") != "0"

static func expected(district: String, shoulder: float) -> float:
	_read_enabled()
	if not enabled or shoulder < MIN_SHOULDER:
		return 0.0
	return float(BY_DISTRICT.get(district, 0.0))

## The mode of one car from a 0..99 roll.
static func mode_of(roll: int) -> int:
	if roll < SHARE_ALARM:
		return MODE_ALARM
	if roll < SHARE_ALARM + SHARE_DOME:
		return MODE_DOME
	if roll < SHARE_ALARM + SHARE_DOME + SHARE_HAZARD:
		return MODE_HAZARD
	return MODE_PLAIN

## Per-instance custom data: r tint index, g mode, b blink phase.
static func custom(tint: int, mode: int, phase: float) -> Color:
	return Color(float(tint), float(mode), phase, 0.0)

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 tints[6];
varying vec3 tint;
varying float tag;
varying float mode;
varying float phase;
void vertex() {
	tint = tints[int(INSTANCE_CUSTOM.r)];
	mode = INSTANCE_CUSTOM.g;
	phase = INSTANCE_CUSTOM.b;
	tag = UV2.x;
}
void fragment() {
	vec3 c = COLOR.rgb;
	if (tag < 0.5) { c *= tint; }
	ALBEDO = c;
	ROUGHNESS = 0.6;
	vec3 e = vec3(0.0);
	if (tag > 0.5 && tag < 1.5 && mode > 0.5 && mode < 1.5) {
		// alarm LED: a short red blink every 1.4 s
		e = vec3(1.0, 0.08, 0.04) * 2.5 * step(0.93, fract(TIME * 0.7 + phase));
	} else if (tag > 1.5 && tag < 2.5 && mode > 1.5 && mode < 2.5) {
		// dome light: warm glass, under the glow threshold
		e = vec3(1.0, 0.72, 0.42) * 0.32;
	} else if (tag > 2.5 && mode > 2.5) {
		// hazards: amber corners blinking together
		e = vec3(1.0, 0.55, 0.12) * 2.0 * step(0.5, fract(TIME * 1.3 + phase));
	}
	EMISSION = e;
}
"""

static func _box(st: SurfaceTool, color: Color, tag: float, center: Vector3, size: Vector3, bottom: bool = false) -> void:
	var h := size / 2.0
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.FORWARD, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
	]
	for f in faces:
		if f[0] == Vector3.DOWN and not bottom:
			continue  # nobody sees under a parked car: 10 triangles a box, not 12
		st.set_normal(f[0])
		st.set_color(color)
		st.set_uv2(Vector2(tag, 0.0))
		for i in [1, 2, 3, 1, 3, 4]:
			st.add_vertex(center + f[i])

## A car 4.3 x 1.7 m, nose along -Z, in its own space (foot at the origin).
static func mesh() -> ArrayMesh:
	if _mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var white := Color(1.0, 1.0, 1.0)
		# eight five-sided boxes, 80 triangles: the chunk's triangle budget
		# (chunk_builder_equivalence.gd) counts every parked car
		# wheels and sill: one dark block under the body
		_box(st, Color(0.12, 0.12, 0.12), TAG_BODY, Vector3(0.0, 0.2, 0.0), Vector3(1.6, 0.4, 3.6))
		_box(st, white, TAG_BODY, Vector3(0.0, 0.58, 0.0), Vector3(1.7, 0.44, 4.3))
		_box(st, Color(0.25, 0.27, 0.3), TAG_GLASS, Vector3(0.0, 1.05, 0.2), Vector3(1.5, 0.5, 2.2))
		# tail lamps (dark red) and head lamps (dark glass), plain parts
		_box(st, Color(0.3, 0.06, 0.05), TAG_BODY, Vector3(0.0, 0.72, 2.16), Vector3(1.5, 0.12, 0.04))
		_box(st, Color(0.3, 0.3, 0.3), TAG_BODY, Vector3(0.0, 0.72, -2.16), Vector3(1.5, 0.12, 0.04))
		# hazard strips over the lamps, both ends
		for sz in [-2.16, 2.16]:
			_box(st, Color(0.45, 0.28, 0.08), TAG_HAZARD, Vector3(0.0, 0.86, sz), Vector3(1.5, 0.08, 0.04))
		# the alarm LED on the dash, behind the windscreen
		_box(st, Color(0.3, 0.05, 0.04), TAG_LED, Vector3(-0.45, 0.86, -0.95), Vector3(0.05, 0.05, 0.05))
		_mesh = st.commit()
	return _mesh

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		var arr := PackedVector3Array()
		for t in TINTS:
			arr.append(Vector3(t.r, t.g, t.b))
		_mat.set_shader_parameter("tints", arr)
	return _mat
