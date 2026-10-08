extends Node3D
class_name CockpitFrame

# The inside of the P1 coupe (cockpit milestone, 2026-10-06; replaces the
# Phase C stand-in of a dash slab and a torus). A child of the PlayerCar, in car
# space (origin on the ground between the axles, -z forward, the body drawn
# BODY_LIFT up), laid out from the P1 body's own windshield, roof and door
# lines so it fits the car seen from outside:
#   dashboard with a cluster (tach and speedo needles, warning lamps that mirror
#   PowertrainHealth), the SteeringWheel (LED strip, LCD, paddles) on a column,
#   a centre stack with the radio head unit showing the station, a console with
#   an H-gate gear lever that moves to the gear and a handbrake that lifts,
#   two seats, door cards, sills, A- and B-pillars, roof liner, sun visors,
#   floor and footwell, three pedals that follow the inputs, and the three
#   CockpitMirrors. Dark materials, one dim amber cabin light, backlit trim.
#
# Everything that never moves is baked into two meshes (plastic, backlit) so the
# whole cabin is about 25 draw calls. Render layers: the interior is on
# INTERIOR; in the cockpit view the player's body moves to MIRROR_ONLY (the
# cockpit camera skips it, the mirror cameras draw it) instead of being hidden,
# so the door mirrors show the car's own flank. The driver (next PR) gets DRIVER.

const INTERIOR_LAYER := 3
const DRIVER_LAYER := 4
const MIRROR_ONLY_LAYER := 5
const INTERIOR_BIT := 1 << (INTERIOR_LAYER - 1)
const DRIVER_BIT := 1 << (DRIVER_LAYER - 1)
const MIRROR_ONLY_BIT := 1 << (MIRROR_ONLY_LAYER - 1)
const CAR_BIT := 1 << (CarFx.CAR_LAYER - 1)
## What the mirror cameras draw: the world, every car's layer and the player's own body.
const MIRROR_CULL := 1 | CAR_BIT | MIRROR_ONLY_BIT

## Lock to lock, in turns of the wheel: the rack is quick, like the reference
## wheel's car. Full keyboard lock (steer_fraction 1) is half of this each way.
const LOCK_TO_LOCK_TURNS := 1.5
const WHEEL_LOCK_RAD := LOCK_TO_LOCK_TURNS * TAU / 2.0

const SEAT_X := -0.36
const LIFT := P1CoupeBuilder.BODY_LIFT
## Wheel hub in car space and its tilt about x. Roy (2026-10-06): the wheel
## must point at the driver without blocking the view. Negative tilts the top
## away from the driver so the face normal rises toward the eye like a real
## column (at -25 the face looks 25 degrees up; the eye is 32 degrees up from
## the hub). The hub is set so the rim top, grip included, sits WHEEL_TOP_MIN_DEG
## below the eye: the LED strip and the LCD stay in view, the road band above
## them stays clear (tests/cockpit_interior.gd checks both).
const WHEEL_POS := Vector3(SEAT_X, 0.77, -0.18)
const WHEEL_TILT_DEG := -25.0
const WHEEL_TOP_MIN_DEG := 15.0
## Sightline targets (Roy, 2026-10-06): the dash line (cowl, dash top, outside
## the binnacle and the pillars) at least this far below the eye's horizontal,
## and at least this share of the cockpit view, at the rest FOV, clear glass.
## tests/cockpit_interior.gd measures both with rays from the eye.
const DASH_TOP_MIN_DEG := 14.0
const GLASS_MIN_FRACTION := 0.55
const CLUSTER_Z := -0.349
## Cluster centre height. Roy (2026-10-06): the cluster must not block the road.
## From the eye (1.10 m) the ground 10 m ahead of the bumper is 5 degrees
## down; the binnacle hood tops out at 0.995 (9.3 degrees down at its nearest
## edge), the dial tops at 10.6 degrees, and the dials sit under it, seen over
## and through the top of the rim (centres 1 degree above the rim top).
const CLUSTER_Y := 0.93
const DIAL_R := 0.05
## Everything the cockpit adds is visual only; this switch (and NEON_COCKPIT=0)
## leaves it out, for the isolation test and for A/B frame-cost runs.
static var enabled := true
const DIAL_SWEEP := 270.0   # degrees from empty (lower left) to full (lower right)
const SPEEDO_MAX_KMH := 300.0
const LEVER_LEN := 0.23
const LEVER_ROW_TILT := 16.0   # degrees fore/aft for a gear slot
const LEVER_COL_TILT := 11.0   # degrees left/right per column
const LEVER_SPEED := 12.0      # slot units per second along the gate path
const PEDAL_TRAVEL_DEG := 22.0

# Colours (ROADMAP palette; dark cabin plastics around it)
const PLASTIC := Color("#1C1F26")
const PLASTIC_LIGHT := Color("#2A2E36")
const LEATHER := Color("#121318")
const SEAT := Color("#1D1F26")
const SEAT_PANEL := Color("#2A2D35")
const CARPET := Color("#0E1014")
const TRIM := Color("#2C3038")
const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const RED := Color("#E5262B")
const DIAL_FACE := Color("#0B0E14")
const BACKLIGHT_ENERGY := 1.6

var player: PlayerCar
var radio: RadioManager          # found lazily; the game adds it after the camera
var wheel: SteeringWheel
var wheel_mount: Node3D          # tilt and place; the wheel turns inside it
var mirrors: CockpitMirrors
var tach_needle: Node3D
var speedo_needle: Node3D
var lamps: MultiMeshInstance3D
var lamp_text: Label3D
var radio_label: Label3D
var lever: Node3D
var lever_knob: Node3D
var handbrake: Node3D
var pedals := {}                 # "throttle" / "brake" / "clutch" -> pivot Node3D
var cabin_light: OmniLight3D
var driver: DriverModel
var steering := 0.0              # -1..1 from the car, set by the camera (tests set it too)
var cockpit := false
var lever_moving := false
var _lever_gear := 0
var _lever_pos := Vector2.ZERO   # (col, row) in slot units, row -1 forward, +1 back
var _lever_path: Array[Vector2] = []
var _last_gear := 0
var _static_tris := 0
## Interiors pass (2026-10-08): this car's look (InteriorStyle), the cluster
## (ClusterFace in a SubViewport on one quad, 3D needles per gauge), the
## shift-light bar when the wheel has no LEDs, the boost pod, the amber spill.
var style: Dictionary
var cluster_face: ClusterFace
var cluster_vp: SubViewport
var needles := {}                # gauge id -> needle pivot
var scales := {}                 # ClusterFace.scales_for(player), refreshed when a tune changes them
var shift_bar: MultiMeshInstance3D
var shift_colours := PackedColorArray()   # per LED as given to the MultiMesh (headless can't read it back)
var pod: Node3D
var pod_face: ClusterFace
var pod_vp: SubViewport
var spill: SpotLight3D
var _kits := {}
var cluster_y := CLUSTER_Y         # dial plate centre height, from the style
var _stack_xf := Transform3D(Basis(Vector3.UP, deg_to_rad(-8.0)), Vector3(0.0, 0.79, -0.30))

func _init(car: PlayerCar) -> void:
	player = car
	name = "Cockpit"
	style = InteriorStyle.for_car(PlayerCar.chassis_kind())
	cluster_y = style.cluster.get("y", CLUSTER_Y)

func _ready() -> void:
	# Always drawn: in the chase view the cabin and driver show through the glass.
	visible = true
	_build_static()
	_build_wheel()
	_build_cluster()
	_build_radio()
	_build_lever()
	_build_handbrake()
	_build_pedals()
	_build_light()
	mirrors = CockpitMirrors.new()
	mirrors.name = "Mirrors"
	mirrors.cull_mask = MIRROR_CULL
	add_child(mirrors)
	_set_layers(self, INTERIOR_BIT)
	# Visual only: nothing in here casts a shadow onto the car or the road.
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the shelf is also what the rearview camera sees under the rear glass
	(get_node("Shelf") as VisualInstance3D).layers = INTERIOR_BIT | MIRROR_ONLY_BIT
	_last_gear = player.gear
	_lever_gear = player.gear
	_lever_pos = _slot_of(player.gear)
	_apply_lever(_lever_pos)
	driver = DriverModel.new(self)
	add_child(driver)

## Cockpit view on or off: starts or stops the mirrors, hides the driver's head
## and torso (the camera is the head) and moves the car's own body and wheels
## to the mirror-only layer (back to the car layer when leaving), so the
## cockpit camera does not draw them but the mirrors do.
func set_cockpit(on: bool) -> void:
	cockpit = on
	mirrors.set_active(on)
	driver.set_cockpit(on)
	var bit := MIRROR_ONLY_BIT if on else CAR_BIT
	if player.chassis_visual != null:
		_set_layers(player.chassis_visual, bit)
	for w in player.wheel_array:
		if w.wheel_node != null:
			_set_layers(w.wheel_node, bit)

## True while the player's body is kept off the cockpit camera (tests).
func body_hidden_from_camera() -> bool:
	if player.chassis_visual == null:
		return true
	for n in player.chassis_visual.find_children("*", "VisualInstance3D", true, false):
		if n is Light3D:
			continue
		if (n as VisualInstance3D).layers != MIRROR_ONLY_BIT:
			return false
	return true

static func _set_layers(root: Node, bit: int) -> void:
	if root is VisualInstance3D and not root is Light3D:
		(root as VisualInstance3D).layers = bit
	for n in root.find_children("*", "VisualInstance3D", true, false):
		if n is Light3D:
			continue   # a light's layers decide whether it lights at all
		(n as VisualInstance3D).layers = bit

# ---------- static cabin ----------

## The kit for one surface kind (CockpitKit.SURFACES); each becomes one mesh.
func _k(kind: String) -> CockpitKit:
	if not _kits.has(kind):
		_kits[kind] = CockpitKit.new()
	return _kits[kind]

func _c(key: String) -> Color:
	return style.colors.get(key, PLASTIC)

func _build_static() -> void:
	var lit := CockpitKit.new()
	var hard := _k("hard")
	var soft := _k("soft")
	var cloth := _k("cloth")
	var leather := _k("leather")
	var metal := _k("metal")
	# Dashboard: a top that falls from 0.93 at the driver's edge to 0.83 at the
	# cowl (y 0.83, z -0.69), a face toward the driver, a knee panel, and the
	# cowl lip. Roy (2026-10-06): the dash line sits at least DASH_TOP_MIN_DEG
	# (14) below the eye across the driver's view (to 20 degrees off axis, where
	# the cowl is further away); from the eye the cowl is the top of that line,
	# so it dropped from the body's 0.90 glass base (was 11.4 degrees).
	# Interiors pass: the top is a soft, glare-free pad, the face and the knee
	# panel hard plastic a step apart in value, with a seam strip between them.
	_build_dash(hard, soft)
	hard.box(Vector3(1.74, 0.012, 0.004), Vector3(0.0, 0.62, -0.268), _c("lower"))                 # seam line
	hard.box(Vector3(1.74, 0.22, 0.32), Vector3(0.0, 0.48, -0.46), _c("lower"))
	hard.box(Vector3(1.66, 0.03, 0.06), Vector3(0.0, 0.815, -0.70), _c("lower"))                    # cowl lip, under the glass line
	# passenger-side vent and glovebox lines on the dash face
	hard.box(Vector3(0.12, 0.035, 0.012), Vector3(0.62, 0.86, -0.268), _c("trim"))
	hard.box(Vector3(0.40, 0.006, 0.004), Vector3(0.40, 0.72, -0.268), _c("lower"))
	hard.box(Vector3(0.006, 0.14, 0.004), Vector3(0.20, 0.65, -0.268), _c("lower"))
	hard.box(Vector3(0.006, 0.14, 0.004), Vector3(0.60, 0.65, -0.268), _c("lower"))
	if style.get("ambient_line", false):
		lit.box(Vector3(1.60, 0.006, 0.01), Vector3(0.0, 0.912, -0.275), Color(AMBER, 0.35))   # dash edge strip
	# Centre stack, turned toward the driver (the unit itself is _build_radio).
	var stack := CockpitKit.new()
	stack.box(Vector3(0.30, 0.24, 0.06), Vector3(0.0, 0.0, 0.0), _c("dash"))
	for vx in [-0.09, 0.09]:
		stack.box(Vector3(0.10, 0.042, 0.010), Vector3(vx, 0.085, 0.032), _c("trim"))
		for i in 3:
			stack.box(Vector3(0.09, 0.004, 0.006), Vector3(vx, 0.072 + 0.013 * i, 0.038), _c("lower"))   # vent vanes
	# heater controls: three knobs under the head unit
	for i in 3:
		stack.cylinder(0.014, 0.0, 0.010, Vector3(-0.08 + 0.08 * i, -0.085, 0.032), _c("trim"), 10, Basis(Vector3.RIGHT, -PI / 2.0))
	stack.transform(_stack_xf)
	hard.merge(stack)
	# Centre console with the gate plate and its H slots, tunnel, armrest.
	hard.box(Vector3(0.26, 0.20, 0.82), Vector3(0.0, 0.52, 0.11), _c("lower"))
	cloth.box(Vector3(0.30, 0.18, 1.20), Vector3(0.0, 0.33, 0.10), _c("floor"))             # tunnel
	metal.box(Vector3(0.13, 0.012, 0.15), Vector3(0.0, 0.626, -0.02), _c("silver"))
	for sx in [-0.035, 0.0, 0.035]:
		hard.box(Vector3(0.012, 0.004, 0.11), Vector3(sx, 0.633, -0.02), _c("floor"))
	hard.box(Vector3(0.082, 0.004, 0.012), Vector3(0.0, 0.633, -0.02), _c("floor"))
	leather.box(Vector3(0.20, 0.05, 0.22), Vector3(0.0, 0.645, 0.38), _c("boot"))            # armrest
	if style.get("ambient_line", false):
		lit.box(Vector3(0.006, 0.004, 0.60), Vector3(-0.133, 0.622, 0.05), Color(AMBER, 0.3))
		lit.box(Vector3(0.006, 0.004, 0.60), Vector3(0.133, 0.622, 0.05), Color(AMBER, 0.3))
	# Seats, driver and passenger: low sports buckets, cushion top about 0.48,
	# so a seated eye lands at the cockpit camera's 1.06 (DriverModel.PELVIS).
	# Interiors pass: darker cloth bolsters, a lighter cloth centre with silver
	# piping, and one thin accent stripe down the middle.
	for sx in [SEAT_X, -SEAT_X]:
		cloth.wedge(Vector3(0.50, 0.10, 0.50), Vector3(sx, 0.43, 0.36), _c("seat"), 0.03, 0.0)
		cloth.wedge(Vector3(0.30, 0.012, 0.44), Vector3(sx, 0.486, 0.36), _c("seat_insert"), 0.03, 0.0)
		cloth.box(Vector3(0.10, 0.10, 0.46), Vector3(sx - 0.21, 0.50, 0.34), _c("seat"))  # cushion bolsters
		cloth.box(Vector3(0.10, 0.10, 0.46), Vector3(sx + 0.21, 0.50, 0.34), _c("seat"))
		var recline := Basis(Vector3.RIGHT, deg_to_rad(12.0))
		var back := Vector3(sx, 0.76, 0.61)
		cloth.box(Vector3(0.50, 0.58, 0.10), back, _c("seat"), recline)
		cloth.box(Vector3(0.30, 0.50, 0.012), back + recline * Vector3(0, -0.01, -0.052), _c("seat_insert"), recline)
		for px in [-0.152, 0.152]:
			cloth.box(Vector3(0.006, 0.50, 0.008), back + recline * Vector3(px, -0.01, -0.058), _c("piping"), recline)
		cloth.box(Vector3(0.022, 0.50, 0.006), back + recline * Vector3(0.0, -0.01, -0.059), _c("accent"), recline)
		cloth.box(Vector3(0.09, 0.50, 0.14), Vector3(sx - 0.22, 0.76, 0.59), _c("seat"), recline)
		cloth.box(Vector3(0.09, 0.50, 0.14), Vector3(sx + 0.22, 0.76, 0.59), _c("seat"), recline)
		cloth.box(Vector3(0.22, 0.10, 0.08), Vector3(sx, 1.10, 0.71), _c("seat"), recline)         # headrest
		hard.box(Vector3(0.50, 0.06, 0.30), Vector3(sx, 0.36, 0.39), _c("lower"))              # seat base
	# Door cards: hard plastic, a cloth insert, a soft belt-line pad, an
	# armrest, a metal pull; sills.
	for side in [-1.0, 1.0]:
		hard.box(Vector3(0.06, 0.38, 0.95), Vector3(side * 0.86, 0.72, -0.02), _c("door"))
		cloth.box(Vector3(0.012, 0.16, 0.60), Vector3(side * 0.826, 0.70, 0.02), _c("door_insert"))
		soft.box(Vector3(0.06, 0.08, 0.95), Vector3(side * 0.86, 0.92, -0.02), _c("dash_top"))      # belt line pad
		leather.box(Vector3(0.12, 0.04, 0.32), Vector3(side * 0.79, 0.76, 0.08), _c("boot"))       # armrest
		metal.box(Vector3(0.05, 0.03, 0.12), Vector3(side * 0.80, 0.84, -0.22), _c("silver"))      # door pull
		hard.box(Vector3(0.14, 0.12, 1.30), Vector3(side * 0.80, 0.31, 0.0), _c("lower"))           # sill
		metal.box(Vector3(0.10, 0.004, 0.60), Vector3(side * 0.80, 0.372, -0.05), _c("silver"))   # scuff plate
		# B-pillar inner face and the rear quarter trim behind the door
		cloth.box(Vector3(0.06, 0.44, 0.08), Vector3(side * 0.78, 1.12, 0.46), _c("pillar"))
		hard.box(Vector3(0.08, 0.48, 0.60), Vector3(side * 0.74, 0.70, 0.78), _c("door"))
	# A-pillars: from the cowl corners to the roof corners (body lines from the
	# data), wrapped in the headliner cloth so they read as trim, not a hole.
	for side in [-1.0, 1.0]:
		_bar(cloth, Vector3(side * 0.78, 0.83, -0.69), Vector3(side * 0.62, 1.345, -0.03), 0.075, _c("pillar"))
	# Roof liner, windshield header, sun visors. The eye is only 0.34 m behind
	# the glass top (y 1.34 at z -0.04), so the header and the liner's front
	# edge sit on that line, not under it: at 1.30 the header's underside hung
	# 25 to 31 degrees above the eye and took the top of the view (Roy's
	# clear-glass target, 2026-10-06). The visors fold flat against the liner.
	cloth.box(Vector3(1.36, 0.02, 0.80), Vector3(0.0, 1.33, 0.35), _c("headliner"))
	cloth.box(Vector3(1.30, 0.05, 0.08), Vector3(0.0, 1.345, -0.03), _c("headliner"))
	for sx in [SEAT_X, -SEAT_X]:   # folded up against the liner, above the view line
		cloth.box(Vector3(0.42, 0.012, 0.15), Vector3(sx, 1.318, 0.13), _c("headliner").lightened(0.06), Basis(Vector3.RIGHT, deg_to_rad(-2.0)))
	# Rearview mirror housing and stalk (the glass is a CockpitMirrors quad).
	var rb := Basis(Vector3.UP, deg_to_rad(CockpitMirrors.REAR_YAW)) * Basis(Vector3.RIGHT, deg_to_rad(CockpitMirrors.REAR_PITCH))
	hard.box(Vector3(0.215, 0.072, 0.022), CockpitMirrors.REAR_POS + rb * Vector3(0, 0, -0.013), _c("lower"), rb)
	hard.box(Vector3(0.018, 0.08, 0.018), CockpitMirrors.REAR_POS + Vector3(0.0, 0.07, -0.02), _c("lower"))
	# Floor, footwell and firewall; rear bulkhead. (The door mirror cups are on
	# the body, P1CoupeBuilder; the parcel shelf is its own mesh, see _ready.)
	cloth.box(Vector3(1.70, 0.04, 1.40), Vector3(0.0, 0.27, 0.15), _c("floor"))
	cloth.wedge(Vector3(1.70, 0.04, 0.30), Vector3(0.0, 0.29, -0.60), _c("floor"), 0.16, 0.0)
	_k("rubber").box(Vector3(0.46, 0.012, 0.50), Vector3(SEAT_X, 0.296, -0.20), _c("rubber"))   # floor mats
	_k("rubber").box(Vector3(0.46, 0.012, 0.50), Vector3(-SEAT_X, 0.296, -0.20), _c("rubber"))
	hard.box(Vector3(1.74, 0.46, 0.04), Vector3(0.0, 0.50, -0.72), _c("lower"))
	hard.box(Vector3(1.40, 0.42, 0.04), Vector3(0.0, 0.76, 0.92), _c("door"))
	var shelf := CockpitKit.new()
	shelf.box(Vector3(1.40, 0.04, 0.72), Vector3(0.0, 0.98, 1.26), _c("floor"))
	add_child(shelf.instance(CockpitKit.surface_material("cloth"), "Shelf"))
	_static_tris = lit.tri_count() + shelf.tri_count()
	# One mesh per surface kind; "Cabin" (hard plastic) keeps its old name.
	for kind in _kits:
		var kit: CockpitKit = _kits[kind]
		if kit.is_empty():
			continue
		kit.bake(0.27, 1.0)
		_static_tris += kit.tri_count()
		var node_name := "Cabin" if kind == "hard" else "Cabin" + String(kind).capitalize()
		add_child(kit.instance(CockpitKit.surface_material(kind), node_name))
	if not lit.is_empty():
		add_child(lit.instance(CockpitKit.glow_material(BACKLIGHT_ENERGY), "Backlight"))

## The dash top and face with a recessed binnacle in front of the driver
## (interiors pass, 2026-10-08). The dials sit low, at cluster_y, so the driver
## reads them through the upper opening of the wheel (the research band, -17 to
## -28 degrees) instead of over the rim, where the rim hid them; the hood arch
## above them tops out at the dash line. The top and face are split around the
## recess so nothing solid sits in front of the plate.
func _build_dash(hard: CockpitKit, soft: CockpitKit) -> void:
	var plate: Vector2 = style.cluster.get("plate", Vector2(0.34, 0.13))
	var pw := plate.x * 0.5 + 0.015
	var rx0 := SEAT_X - pw
	var rx1 := SEAT_X + pw
	var ry0 := cluster_y - plate.y * 0.5 - 0.012
	# Top: 0.83 at the cowl (z -0.69), 0.93 at the driver's edge (z -0.29);
	# the middle piece stops behind the binnacle (z -0.40).
	soft.wedge(Vector3(rx0 + 0.87, 0.06, 0.40), Vector3((rx0 - 0.87) * 0.5, 0.80, -0.49), _c("dash_top"), 0.0, 0.10)
	soft.wedge(Vector3(0.87 - rx1, 0.06, 0.40), Vector3((rx1 + 0.87) * 0.5, 0.80, -0.49), _c("dash_top"), 0.0, 0.10)
	soft.wedge(Vector3(rx1 - rx0, 0.06, 0.29), Vector3(SEAT_X, 0.80, -0.545), _c("dash_top"), 0.0, 0.0725)
	# Face: left and right of the recess, and the piece under it.
	hard.box(Vector3(rx0 + 0.87, 0.36, 0.12), Vector3((rx0 - 0.87) * 0.5, 0.73, -0.33), _c("dash"))
	hard.box(Vector3(0.87 - rx1, 0.36, 0.12), Vector3((rx1 + 0.87) * 0.5, 0.73, -0.33), _c("dash"))
	hard.box(Vector3(rx1 - rx0, ry0 - 0.55, 0.12), Vector3(SEAT_X, (ry0 + 0.55) * 0.5, -0.33), _c("dash"))
	# Hood: an arch over the dials, wrapping toward the driver, its top at the
	# dash line; a filled half-disc closes the recess behind the plate, the
	# side walls stop where the arch meets them.
	var arch_c := Vector3(SEAT_X, cluster_y - 0.088, -0.36)
	var r1 := pw + 0.01
	var a0 := asin(clampf((ry0 - arch_c.y) / r1, -1.0, 1.0))
	var hood := CockpitKit.new()
	hood.ring_sector(r1 - 0.015, r1, a0, PI - a0, 0.0, 0.11, _c("dash_top"), 16)
	hood.offset(arch_c)
	soft.merge(hood)
	var back := CockpitKit.new()
	back.ring_sector(0.0, r1 - 0.014, a0, PI - a0, -0.02, 0.0, _c("lower"), 16)
	back.offset(arch_c + Vector3(0, 0, -0.002))
	hard.merge(back)
	hard.box(Vector3(rx1 - rx0, 0.012, 0.13), Vector3(SEAT_X, ry0, -0.315), _c("lower"))

## A box from a to b, `w` across, for pillars.
static func _bar(k: CockpitKit, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	var y := d / len
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.5:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	k.box(Vector3(w, len, w * 1.2), (a + b) * 0.5, col, Basis(x, y, z))

# ---------- wheel and column ----------

func _build_wheel() -> void:
	wheel_mount = Node3D.new()
	wheel_mount.name = "WheelMount"
	wheel_mount.position = WHEEL_POS
	wheel_mount.rotation_degrees = Vector3(WHEEL_TILT_DEG, 0.0, 0.0)
	add_child(wheel_mount)
	wheel = SteeringWheel.new()
	wheel.name = "Wheel"
	wheel.style = style.get("wheel", {})
	wheel_mount.add_child(wheel)
	# A short column stub behind the hub (the long pole down the middle of the
	# view is gone, Roy 2026-10-06); the shroud is on the dash face, under the cluster.
	var k := CockpitKit.new()
	k.cylinder(0.024, -0.09, -0.03, Vector3.ZERO, _c("lower"), 8, Basis(Vector3.RIGHT, -PI / 2.0))
	wheel_mount.add_child(k.instance(CockpitKit.surface_material("hard"), "Column"))

# ---------- instrument cluster ----------

func _build_cluster() -> void:
	var cl: Dictionary = style.cluster
	var plate: Vector2 = cl.get("plate", Vector2(0.34, 0.13))
	scales = ClusterFace.scales_for(player)
	var centre := Vector3(SEAT_X, cluster_y, CLUSTER_Z)
	var made := _face(plate, cl.gauges, cl.get("look", {}), "Cluster")
	cluster_vp = made[0]
	cluster_face = made[1]
	_face_quad(cluster_vp, plate, Transform3D(Basis.IDENTITY, centre), "ClusterFace")
	var needle_col: Color = cl.get("needle", RED)
	for g in cl.gauges:
		needles[g.id] = _needle(centre + Vector3(g.at.x, g.at.y, 0.004), "Needle" + String(g.id).capitalize(), g.r, needle_col)
	tach_needle = needles.get("tach")
	speedo_needle = needles.get("speedo")
	if tach_needle != null:
		tach_needle.name = "TachNeedle"
	if speedo_needle != null:
		speedo_needle.name = "SpeedoNeedle"
	# Warning lamps in the tach's lower gap (between empty and full), mirroring
	# PowertrainHealth: ENG BRK TYR CLT.
	var tach_at := Vector2(0.0, 0.0)
	var tach_r := 0.05
	for g in cl.gauges:
		if g.kind == "tach":
			tach_at = g.at
			tach_r = g.r
	var lamp_y := cluster_y + tach_at.y - tach_r * 0.70
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.014, 0.007, 0.003)
	mm.mesh = box
	mm.instance_count = 4
	for i in 4:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(SEAT_X + tach_at.x - 0.024 + 0.016 * i, lamp_y, CLUSTER_Z + 0.002)))
		mm.set_instance_color(i, Color(AMBER, 0.0))
	lamps = MultiMeshInstance3D.new()
	lamps.name = "Lamps"
	lamps.multimesh = mm
	lamps.material_override = CockpitKit.glow_material(SteeringWheel.LED_ENERGY)
	add_child(lamps)
	lamp_text = _label("ENG BRK TYR CLT", 9, Vector3(SEAT_X + tach_at.x, lamp_y - 0.008, CLUSTER_Z + 0.002), _c("silver"), 0.0004)
	lamp_text.name = "LampText"
	# Shift lights: on the wheel when it has LEDs, else a bar of the same 15
	# LEDs (same fill rule) along the top of the cluster, under the hood.
	if not style.wheel.get("leds", true) and cl.get("shift_bar", true):
		_build_shift_bar(centre + Vector3(0.0, plate.y * 0.5 - 0.008, 0.003), plate.x * 0.62)
	_build_pod()

## A SubViewport with a ClusterFace drawing `gauges`, drawn once.
func _face(plate: Vector2, gauges: Array, look: Dictionary, node_name: String) -> Array:
	var vp := SubViewport.new()
	vp.name = node_name + "View"
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var face := ClusterFace.new()
	face.plate = plate
	face.gauges = gauges
	face.look = look
	face.scales = scales
	vp.size = face.image_size()
	vp.add_child(face)
	add_child(vp)
	return [vp, face]

## The quad that shows a face, self-lit (the printed faces are backlit).
func _face_quad(vp: SubViewport, plate: Vector2, xf: Transform3D, node_name: String) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = plate
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = q
	mi.material_override = m
	mi.transform = xf
	add_child(mi)
	return mi

func _build_shift_bar(at: Vector3, width: float) -> void:
	var n := SteeringWheel.LED_COUNT
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(width / n * 0.7, 0.006, 0.003)
	mm.mesh = box
	mm.instance_count = n
	shift_colours.resize(n)
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(), at + Vector3(lerpf(-width * 0.5, width * 0.5, float(i) / (n - 1)), 0.0, 0.0)))
		var c := SteeringWheel.led_base_colour(i)
		shift_colours[i] = Color(c, 0.0)
		mm.set_instance_color(i, shift_colours[i])
	shift_bar = MultiMeshInstance3D.new()
	shift_bar.name = "ShiftBar"
	shift_bar.multimesh = mm
	shift_bar.material_override = CockpitKit.glow_material(SteeringWheel.LED_ENERGY)
	add_child(shift_bar)

func _update_shift_bar(frac: float, cue: bool, blink: bool) -> void:
	if shift_bar == null:
		return
	var n := SteeringWheel.LED_COUNT
	var lit_n := SteeringWheel.lit_count_for(frac)
	var flash := cue and blink
	for i in n:
		var k := mini(i, n - 1 - i)
		var lit := lit_n == n if k == 7 else lit_n >= 2 * (k + 1)
		var c := SILVER if (lit and flash) else SteeringWheel.led_base_colour(i)
		shift_colours[i] = Color(c, 1.0 if lit else 0.0)
		shift_bar.multimesh.set_instance_color(i, shift_colours[i])

## An aftermarket gauge pod screwed to the dash face left of the cluster (on
## cars whose style has one). The boost pod shows only while the car has a
## turbo (turbo_boost_max > 0); a tune that adds boost brings it up.
func _build_pod() -> void:
	var pd: Dictionary = style.get("pod", {})
	if pd.is_empty():
		return
	var r: float = pd.get("r", 0.03)
	var at := Vector3(SEAT_X - 0.27, 0.84, -0.245)
	var eye := Vector3(-0.32, 1.10, 0.30)
	var b := Basis.looking_at(at - eye)   # +z of the pod toward the eye
	pod = Node3D.new()
	pod.name = "Pod"
	pod.transform = Transform3D(b, at)
	add_child(pod)
	var k := CockpitKit.new()
	k.cylinder(r * 1.25, -0.05, 0.0, Vector3.ZERO, _c("lower"), 14, Basis(Vector3.RIGHT, PI / 2.0))
	k.cylinder(r * 0.4, -0.08, -0.05, Vector3.ZERO, _c("silver"), 8, Basis(Vector3.RIGHT, PI / 2.0))   # bracket
	pod.add_child(k.instance(CockpitKit.surface_material("hard"), "PodBody"))
	var plate := Vector2(r * 2.2, r * 2.2)
	var g := {"id": "boost", "kind": pd.get("kind", "boost"), "at": Vector2.ZERO, "r": r, "sweep": 270.0}
	var made := _face(plate, [g], style.cluster.get("look", {}), "Pod")
	pod_vp = made[0]
	pod_face = made[1]
	var q := _face_quad(pod_vp, plate, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.001)), "PodFace")
	remove_child(q)
	pod.add_child(q)
	var nd := _needle(Vector3(0, 0, 0.004), "NeedleBoost", r, style.cluster.get("needle", RED))
	remove_child(nd)
	pod.add_child(nd)
	needles["boost"] = nd
	pod.visible = float(scales.boost_max) > 0.0

## Rebuilds the printed scales when the car's numbers change (a tune).
func _refresh_scales() -> void:
	var now := ClusterFace.scales_for(player)
	if now == scales:
		return
	scales = now
	for f in [cluster_face, pod_face]:
		if f != null:
			f.scales = scales
			f.queue_redraw()
	for vp in [cluster_vp, pod_vp]:
		if vp != null:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if pod != null:
		pod.visible = float(scales.boost_max) > 0.0

## The value 0..1 a gauge shows, from the car.
func gauge_value(kind: String) -> float:
	var p := player
	match kind:
		"tach":
			return clampf(p.motor_rpm / maxf(float(scales.tach_max), 1.0), 0.0, 1.0)
		"speedo":
			return clampf(absf(p.current_speed()) * Hud.KMH_PER_MS / maxf(float(scales.speedo_max), 1.0), 0.0, 1.0)
		"water":
			return clampf((p.health.engine_temp - 50.0) / 80.0, 0.0, 1.0)   # C at 50 degC, H at 130
		"fuel":
			var f: Variant = p.get("fuel_level")   # no fuel model yet (stage C): reads a fixed 3/4
			return clampf(float(f), 0.0, 1.0) if f != null else 0.75
		"oil":
			return clampf(0.2 + 0.7 * p.motor_rpm / maxf(p.max_rpm, 1.0), 0.0, 1.0)   # pressure follows revs
		"boost":
			var bm := float(scales.boost_max)
			return clampf((p.boost + 1.0) / (bm + 1.0), 0.0, 1.0) if bm > 0.0 else 0.0
		"volt":
			return 0.62
	return 0.0

## A needle pivot for a dial of radius r: a lit pointer that reaches the
## ticks, a short tail and a dark hub cap.
func _needle(at: Vector3, node_name: String, r := DIAL_R, col := RED) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = at
	var k := CockpitKit.new()
	var len := r * 0.86
	var w := clampf(r * 0.07, 0.0022, 0.0045)
	k.box(Vector3(w, len, 0.002), Vector3(0.0, len * 0.5 - r * 0.05, 0.0), Color(col, 1.0))
	k.box(Vector3(w * 0.9, r * 0.2, 0.002), Vector3(0.0, -r * 0.14, 0.0), Color(col, 0.35))
	k.cylinder(clampf(r * 0.12, 0.003, 0.007), -0.001, 0.003, Vector3.ZERO, Color(_c("lower"), 0.05), 10, Basis(Vector3.RIGHT, PI / 2.0))
	pivot.add_child(k.instance(CockpitKit.glow_material(SteeringWheel.LED_ENERGY)))
	add_child(pivot)
	return pivot

func _label(text: String, size: int, at: Vector3, col: Color, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = at
	add_child(l)
	return l

# ---------- radio head unit ----------

## The head unit sits in the centre stack (built in stack space, then turned
## toward the driver with it). Interiors pass: the look follows the car's era
## (InteriorStyle head_unit); "din1" is a period aftermarket single-DIN unit
## with an amber LCD window, a volume and a tune knob and six preset buttons.
## The touch-screen unit for newer cars comes with the touch-radio PR.
func _build_radio() -> void:
	var hu: Dictionary = style.get("head_unit", {})
	var face: Color = hu.get("face", DIAL_FACE)
	var txt: Color = hu.get("text", AMBER)
	var k := CockpitKit.new()
	var lcd := CockpitKit.new()
	k.box(Vector3(0.20, 0.058, 0.014), Vector3(0.0, 0.010, 0.036), face)
	k.box(Vector3(0.206, 0.064, 0.006), Vector3(0.0, 0.010, 0.030), _c("trim"))   # bezel
	lcd.box(Vector3(0.10, 0.022, 0.002), Vector3(0.0, 0.019, 0.044), Color(txt, 0.10))
	for kx in [-0.078, 0.078]:
		k.cylinder(0.011, 0.0, 0.014, Vector3(kx, 0.012, 0.043), _c("silver"), 12, Basis(Vector3.RIGHT, -PI / 2.0))
	for i in 6:
		k.box(Vector3(0.014, 0.007, 0.004), Vector3(-0.0425 + 0.017 * i, -0.008, 0.044), _c("trim"))
	k.transform(_stack_xf)
	lcd.transform(_stack_xf)
	add_child(k.instance(CockpitKit.surface_material("hard"), "Radio"))
	add_child(lcd.instance(CockpitKit.glow_material(1.0), "RadioLcd"))
	radio_label = _label("RADIO OFF", 22, _stack_xf * Vector3(0.0, 0.019, 0.046), txt, 0.00042)
	radio_label.basis = _stack_xf.basis
	radio_label.name = "RadioLabel"

## Where a reaching hand presses, car space (the preset buttons).
func radio_button_position() -> Vector3:
	return _stack_xf * Vector3(0.0, -0.008, 0.046)

# ---------- gear lever and handbrake ----------

func _build_lever() -> void:
	lever = Node3D.new()
	lever.name = "Lever"
	lever.position = Vector3(0.0, 0.615, -0.02)
	var k := CockpitKit.new()
	k.cylinder(0.008, 0.0, LEVER_LEN - 0.02, Vector3.ZERO, _c("silver"), 8)
	var boot := CockpitKit.new()
	boot.cylinder(0.034, 0.0, 0.02, Vector3.ZERO, _c("boot"), 10)   # gaiter, wide at the plate
	boot.cylinder(0.02, 0.02, 0.06, Vector3.ZERO, _c("boot"), 10)
	lever.add_child(k.instance(CockpitKit.surface_material("metal")))
	lever.add_child(boot.instance(CockpitKit.surface_material("leather")))
	lever_knob = Node3D.new()
	lever_knob.name = "Knob"
	lever_knob.position = Vector3(0.0, LEVER_LEN, 0.0)
	var kk := CockpitKit.new()
	kk.cylinder(0.021, -0.023, 0.020, Vector3.ZERO, _c("boot"), 12)
	kk.cylinder(0.016, 0.020, 0.025, Vector3.ZERO, _c("silver"), 12)   # shift pattern cap
	lever_knob.add_child(kk.instance(CockpitKit.surface_material("leather")))
	lever.add_child(lever_knob)
	add_child(lever)

func _build_handbrake() -> void:
	handbrake = Node3D.new()
	handbrake.name = "Handbrake"
	handbrake.position = Vector3(0.0, 0.615, 0.44)
	var k := CockpitKit.new()
	k.box(Vector3(0.024, 0.024, 0.22), Vector3(0.0, 0.012, -0.11), _c("trim"))
	k.box(Vector3(0.034, 0.034, 0.08), Vector3(0.0, 0.017, -0.21), _c("boot"))
	k.box(Vector3(0.016, 0.010, 0.016), Vector3(0.0, 0.034, -0.24), _c("silver"))     # release button
	handbrake.add_child(k.instance(CockpitKit.surface_material("leather")))
	add_child(handbrake)

## The H-gate slot of a gear as (column, row): row -1 forward (odd gears), +1
## back (even gears, reverse), 0 the neutral gate. Reverse is right of the last column.
func _slot_of(g: int) -> Vector2:
	if g == 0:
		return Vector2.ZERO
	var n_cols := int(ceil(float(player.gear_ratios.size()) / 2.0))
	if g < 0:
		return Vector2(float(n_cols) - float(n_cols - 1) / 2.0, 1.0)
	var col := float((g - 1) / 2) - float(n_cols - 1) / 2.0
	return Vector2(col, -1.0 if g % 2 == 1 else 1.0)

## Lever tilt from a slot position (slot units -> degrees).
func _apply_lever(p: Vector2) -> void:
	lever.rotation_degrees = Vector3(p.y * LEVER_ROW_TILT, 0.0, -p.x * LEVER_COL_TILT)

## Start moving the lever to a gear, through the neutral gate like a hand would.
func move_lever_to(g: int) -> void:
	var to := _slot_of(g)
	_lever_path.clear()
	if _lever_pos.y != 0.0:
		_lever_path.append(Vector2(_lever_pos.x, 0.0))
	if to.x != _lever_pos.x:
		_lever_path.append(Vector2(to.x, 0.0))
	_lever_path.append(to)
	_lever_gear = g
	lever_moving = true

func lever_knob_position() -> Vector3:
	return lever_knob.global_position

func _step_lever(delta: float) -> void:
	if _lever_path.is_empty():
		lever_moving = false
		return
	var next := _lever_path[0]
	_lever_pos = _lever_pos.move_toward(next, LEVER_SPEED * delta)
	if _lever_pos.is_equal_approx(next):
		_lever_path.remove_at(0)
	_apply_lever(_lever_pos)

# ---------- pedals ----------

func _build_pedals() -> void:
	for p in [["throttle", -0.26, 0.045, 0.10], ["brake", -0.38, 0.065, 0.075], ["clutch", -0.50, 0.060, 0.075]]:
		var pivot := Node3D.new()
		pivot.name = String(p[0]).capitalize() + "Pedal"
		pivot.position = Vector3(p[1], 0.54, -0.50)
		var k := CockpitKit.new()
		k.box(Vector3(0.018, 0.17, 0.012), Vector3(0.0, -0.085, 0.0), _c("lower"))
		k.box(Vector3(p[2], p[3], 0.012), Vector3(0.0, -0.17, 0.004), _c("silver"))   # drilled alloy pads
		pivot.add_child(k.instance(CockpitKit.surface_material("metal")))
		add_child(pivot)
		pedals[p[0]] = pivot

## Pedal travel 0..1 as it reads from the car.
func pedal_inputs() -> Dictionary:
	var clutch: float
	if player.realistic_clutch:
		clutch = maxf(player.clutch_input, player.clutch_pedal)
	else:
		clutch = player.clutch_amount   # the automatic clutch opens during a shift
	return {"throttle": clampf(player.throttle_amount, 0.0, 1.0), "brake": clampf(player.brake_amount, 0.0, 1.0), "clutch": clampf(clutch, 0.0, 1.0)}

# ---------- cabin light ----------

func _build_light() -> void:
	cabin_light = OmniLight3D.new()
	cabin_light.name = "CabinLight"
	cabin_light.position = Vector3(0.0, 1.0, 0.05)
	# Interiors pass: a dim warm-neutral fill, not amber, so the cabin's value
	# steps and colours read; the amber comes from the gauges (spill below).
	cabin_light.light_color = style.get("cabin_tint", Color("#D9CCB8"))
	cabin_light.light_energy = style.get("cabin_light", 1.1)   # the driver shows through the glass
	cabin_light.omni_range = 2.2
	cabin_light.omni_attenuation = 1.2
	cabin_light.shadow_enabled = false
	cabin_light.light_cull_mask = INTERIOR_BIT | DRIVER_BIT
	add_child(cabin_light)
	# Amber gauge backlight spilling back onto the wheel rim, the spokes and
	# the gloves (interiors pass): a small spot from the cluster face.
	spill = SpotLight3D.new()
	spill.name = "GaugeSpill"
	spill.light_color = AMBER
	spill.light_energy = style.get("spill", 0.8)
	spill.spot_range = 0.75
	spill.spot_angle = 55.0
	spill.spot_attenuation = 1.4
	spill.shadow_enabled = false
	spill.light_cull_mask = INTERIOR_BIT | DRIVER_BIT
	add_child(spill)
	spill.position = Vector3(SEAT_X, cluster_y + 0.04, CLUSTER_Z + 0.06)
	spill.look_at_from_position(spill.position, Vector3(SEAT_X, 0.70, 0.20), Vector3.UP)

# ---------- per frame ----------

func _process(delta: float) -> void:
	if not visible:
		return
	var p := player
	var max_rpm := maxf(p.max_rpm, 1.0)
	var frac := clampf(p.motor_rpm / max_rpm, 0.0, 1.0)
	var cue := Hud.shift_cue(p, frac)
	var blink := Hud.blink()
	wheel.set_angle(steering * WHEEL_LOCK_RAD)
	wheel.update(frac, cue, blink, p.motor_rpm, Hud.kmh(p.current_speed()), Hud.gear_text(p.gear))
	_refresh_scales()
	for g in style.cluster.gauges:
		var n: Node3D = needles[g.id]
		n.rotation = Vector3(0.0, 0.0, ClusterFace.needle_angle(gauge_value(g.kind), g.get("sweep", DIAL_SWEEP), g.get("start", ClusterFace.START_DEG)))
	if pod != null and pod.visible:
		needles.boost.rotation = Vector3(0.0, 0.0, ClusterFace.needle_angle(gauge_value("boost"), DIAL_SWEEP))
	_update_shift_bar(frac, cue, blink)
	_update_lamps()
	var inputs := pedal_inputs()
	for key in pedals:
		(pedals[key] as Node3D).rotation_degrees = Vector3(PEDAL_TRAVEL_DEG * float(inputs[key]), 0.0, 0.0)
	handbrake.rotation_degrees = Vector3(28.0 * clampf(p.handbrake_input, 0.0, 1.0), 0.0, 0.0)
	# Manual: the lever starts for the requested gear the moment the shift
	# starts (the driver's hand rides it through the shift_time), and is set
	# straight on gear changes that skip is_shifting (out of neutral).
	if not p.automatic_transmission and p.is_shifting and _lever_gear != p.requested_gear:
		move_lever_to(p.requested_gear)
	if p.gear != _last_gear:
		if p.automatic_transmission:
			wheel.flick(1 if p.gear > _last_gear else -1)
		elif _lever_gear != p.gear:
			move_lever_to(p.gear)
		_last_gear = p.gear
	if p.automatic_transmission and _lever_gear != 0 and not lever_moving:
		move_lever_to(0)
	elif not p.automatic_transmission and _lever_gear != p.gear and not lever_moving and not p.is_shifting:
		move_lever_to(p.gear)
	_step_lever(delta)
	_update_radio()

func _update_lamps() -> void:
	var h := player.health
	var on := [
		[h.is_warning(PowertrainHealth.Warn.ENG), h.is_warning(PowertrainHealth.Warn.ENG_DERATE)],
		[h.is_warning(PowertrainHealth.Warn.BRK), h.is_warning(PowertrainHealth.Warn.BRK_FADE)],
		[h.is_warning(PowertrainHealth.Warn.TYRE), false],
		[h.is_warning(PowertrainHealth.Warn.CLUTCH), false],
	]
	var slow_blink := int(Time.get_ticks_msec() / 350) % 2 == 0
	for i in 4:
		var lit: bool = on[i][0] and (not on[i][1] or slow_blink)
		var c: Color = RED if on[i][1] else AMBER
		lamps.multimesh.set_instance_color(i, Color(c, 1.0 if lit else 0.0))

func _update_radio() -> void:
	if radio == null:
		var scene := get_tree().current_scene
		if scene != null and scene.get("radio") is RadioManager:
			radio = scene.radio
		else:
			return
	if radio.station < 0:
		radio_label.text = "RADIO OFF"
	else:
		radio_label.text = RadioStations.STATIONS[radio.station].name.to_upper()

## Triangles drawn by the cabin (static meshes, wheel, moving parts, mirrors).
func triangle_count() -> int:
	var n := 0
	for m in find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				n += (mesh as ArrayMesh).surface_get_array_len(s) / 3
		elif mesh is QuadMesh:
			n += 2
	n += 12 * (SteeringWheel.LED_COUNT + 4 + 4)
	return n
