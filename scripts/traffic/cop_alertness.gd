class_name CopAlertness
extends RefCounted

# What a parked cop is doing while it waits (more-alive MA4, K1). Each parked
# cop draws one look when it is placed. The look shows on the car and makes
# the cop slower to notice you; it never gives a cop a new reason to react.
#
#   reading      pale laptop glow on the windows     notices 1.6x slower
#   on break     dome lamp on, a cup on the roof     1.3x slower
#   bored        arm on the driver's door            normal; hears 1.3x as far
#   half asleep  head against the window, 3 a.m. on  2.0x slower
#
# About one cop in MISMATCH_ONE_IN is sharp whatever it looks like (`sharp`):
# it uses the normal numbers. So the look is a hint, not a promise.
#
# The numbers are read by PoliceRules.judge_secs / notice_secs (PoliceHeat for
# a registered cop, MomentSpots for the speed trap) from the metas `tag` sets.
# `hear` is stored for the stage that gives cops ears: nothing listens yet, so
# today it changes nothing.
#
# The patrol sedan's glass is opaque (NpcCarBuilder), so nothing inside the
# cabin can be seen: every look is drawn on or just outside the body.

enum { SHARP = -1, READING, ON_BREAK, BORED, HALF_ASLEEP }

const STATES := {
	READING: {"name": "reading", "delay": 1.6, "hear": 1.0},
	ON_BREAK: {"name": "on break", "delay": 1.3, "hear": 1.0},
	BORED: {"name": "bored", "delay": 1.0, "hear": 1.3},
	HALF_ASLEEP: {"name": "half asleep", "delay": 2.0, "hear": 1.0},
}
const MISMATCH_ONE_IN := 5
## Half asleep is only drawn from this hour to dawn (NightClock.END_HOUR).
const ASLEEP_FROM_HOUR := 3
const ASLEEP_TO_HOUR := 6

const META_LOOK := &"alert_look"
const META_DELAY := &"alert_delay"
const META_HEAR := &"alert_hear"
const LOOK_NODE := ^"AlertLook"

const LAPTOP := Color("cfd8e6")
const DOME := Color("ffc066")
const CUP := Color("d8d2c4")
const SLEEVE := Color("1b2a4a")
const HEAD := Color("3a4258")

## Whether half asleep can be drawn at this clock hour (0..23).
static func asleep_hour(hour: int) -> bool:
	return hour >= ASLEEP_FROM_HOUR and hour < ASLEEP_TO_HOUR

## One parked cop's draw, the same for the same `key`: {look, sharp}.
static func pick(key: int, hour: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key, "alert"])
	var looks := [READING, ON_BREAK, BORED]
	if asleep_hour(hour):
		looks.append(HALF_ASLEEP)
	var look: int = looks[rng.randi_range(0, looks.size() - 1)]
	return {"look": look, "sharp": rng.randi_range(1, MISMATCH_ONE_IN) == 1}

## How many times longer this cop takes to notice (1.0 = the rulebook's time).
static func delay_factor(look: int, sharp: bool) -> float:
	return 1.0 if sharp or not STATES.has(look) else float(STATES[look].delay)

## How many times as far it hears (nothing listens yet).
static func hear_factor(look: int, sharp: bool) -> float:
	return 1.0 if sharp or not STATES.has(look) else float(STATES[look].hear)

## Marks a cop as parked with this look. PoliceHeat reads `parked` (no
## mirrors) and `alert_delay`.
static func tag(cop: Node, look: int, sharp: bool) -> void:
	cop.set_meta(&"parked", true)
	cop.set_meta(META_LOOK, look)
	cop.set_meta(META_DELAY, delay_factor(look, sharp))
	cop.set_meta(META_HEAR, hear_factor(look, sharp))

## The delay factor a cop carries: 1.0 unless it is parked and tagged.
static func delay_of(cop: Node) -> float:
	if cop == null or not cop.get_meta(&"parked", false):
		return 1.0
	return float(cop.get_meta(META_DELAY, 1.0))

# ---------- the look on the car ----------

static var _mats := {}

static func _glow(c: Color, strength: float) -> StandardMaterial3D:
	var key := [c, strength]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(c.r * strength, c.g * strength, c.b * strength)
		_mats[key] = m
	return _mats[key]

static func _solid(c: Color, emit := 0.0) -> StandardMaterial3D:
	var key := [c, emit, "solid"]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		_mats[key] = m
	return _mats[key]

static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

static func _quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

## Where the cabin is on a sheet body, as shares of the kind's height (which
## counts the light bar) and length, measured on the patrol sedan: the belt
## line, the roof, the driver's window and the rear window.
const BELT := 0.66
const ROOF := 0.945
const DOOR_Z := 0.0
const REAR_Z := 0.24
## The side glass leans in by about this much, radians.
const LEAN := 0.3

## A glow on the cabin glass: the driver's window, the passenger's, and the
## rear window (the side a car coming up behind the trap sees).
static func _window_glow(n: Node3D, k: Dictionary, c: Color, side: float, rear: float) -> void:
	var w := float(k.width)
	var h := float(k.height)
	var l := float(k.length)
	var y := h * (BELT + ROOF) * 0.5
	var tall := h * (ROOF - BELT) * 0.8
	for sx in [-1.0, 1.0]:
		var s := side if sx < 0.0 else side * 0.45   # the light is on the driver's side
		_part(n, _quad(l * 0.11, tall), _glow(c, s), Vector3(sx * (w * 0.5 - 0.09), y, l * DOOR_Z), Vector3(-LEAN, sx * PI * 0.5, 0.0))
	_part(n, _quad(w * 0.5, tall), _glow(c, rear), Vector3(0.0, y + 0.03, l * REAR_Z), Vector3(-0.95, 0.0, 0.0))

## Puts the look on a parked car of NpcCarBuilder kind `kind` (its origin on
## the ground, nose to -Z, the driver on -X), replacing any look it had.
## A few small meshes; no lights, no script.
static func dress(cop: Node3D, kind: String, look: int) -> void:
	var old := cop.get_node_or_null(LOOK_NODE)
	if old != null:
		cop.remove_child(old)
		old.free()
	if not STATES.has(look) or not NpcCarBuilder.KINDS.has(kind):
		return
	var k: Dictionary = NpcCarBuilder.KINDS[kind]
	var w := float(k.width)
	var h := float(k.height)
	var l := float(k.length)
	var n := Node3D.new()
	n.name = "AlertLook"
	n.position.y = float(k.rest_y)
	var sill_x := -(w * 0.5 - 0.05)
	match look:
		READING:
			_window_glow(n, k, LAPTOP, 0.6, 0.45)
		ON_BREAK:
			_window_glow(n, k, DOME, 0.55, 0.5)
			var cup := CylinderMesh.new()
			cup.top_radius = 0.045
			cup.bottom_radius = 0.035
			cup.height = 0.13
			cup.radial_segments = 8
			cup.rings = 1
			_part(n, cup, _solid(CUP, 0.3), Vector3(-w * 0.2, h * ROOF + 0.065, l * 0.0))
		BORED:
			# forearm along the sill, the hand hanging over it
			_part(n, _box(Vector3(0.11, 0.09, 0.42)), _solid(SLEEVE, 0.25), Vector3(sill_x, h * BELT + 0.04, l * DOOR_Z))
			_part(n, _box(Vector3(0.07, 0.16, 0.09)), _solid(CUP, 0.25), Vector3(sill_x - 0.04, h * BELT - 0.04, l * DOOR_Z - 0.2))
		HALF_ASLEEP:
			# the head against the glass, low and back: the seat is down
			_part(n, _quad(0.22, 0.22), _solid(HEAD, 0.5), Vector3(-(w * 0.5 - 0.07), h * (BELT + 0.08), l * (DOOR_Z + 0.04)), Vector3(-LEAN, -PI * 0.5, 0.0))
	cop.add_child(n)
