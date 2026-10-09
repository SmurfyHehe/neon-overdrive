extends Node3D
class_name CockpitFrame

# The inside of the P1 coupe (cockpit milestone, 2026-10-06; replaces the
# Phase C stand-in of a dash slab and a torus). A child of the PlayerCar, in car
# space (origin on the ground between the axles, -z forward, the body drawn
# BODY_LIFT up), laid out from the P1 body's own windshield, roof and door
# lines so it fits the car seen from outside:
#   dashboard with a cluster (tach and speedo needles, warning lamps that mirror
#   PowertrainHealth), the SteeringWheel (LED strip, LCD, paddles) on a column,
#   a centre stack with the touch-screen HeadUnit (station tiles; the driver's
#   hand taps them, the station changes on the tap), a console with a gear
#   lever that follows the gearbox mode (H-gate in MANUAL, sequential stick in
#   SEMI, R-N-D selector in AUTO) and a handbrake that lifts,
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
## them stays clear (tests/view/cockpit_interior.gd checks both).
const WHEEL_POS := Vector3(SEAT_X, 0.77, -0.18)
const WHEEL_TILT_DEG := -25.0
const WHEEL_TOP_MIN_DEG := 15.0
## Sightline targets (Roy, 2026-10-06): the dash line (cowl, dash top, outside
## the binnacle and the pillars) at least this far below the eye's horizontal,
## and at least this share of the cockpit view, at the rest FOV, clear glass.
## tests/view/cockpit_interior.gd measures both with rays from the eye.
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
## SEMI: the tap waits this long, so the driver's hand (DriverModel.REACH_SECS) is on it first.
const SEQ_WAIT := 0.22
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
var head_unit: HeadUnit         # the touch-screen radio on the centre stack
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
var lever_mode := -1             # PlayerCar.Transmission the lever shows
var _lever_heads := {}           # mode -> knob mesh
var _gate_labels := {}           # mode -> pattern label on the console
var _lever_wait := 0.0
var _last_gear := 0
var _static_tris := 0

func _init(car: PlayerCar) -> void:
	player = car
	name = "Cockpit"

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
	set_lever_mode(player.transmission_mode())
	driver = DriverModel.new(self)
	add_child(driver)
	driver.hand_contact.connect(_on_hand_contact)

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

func _build_static() -> void:
	var k := CockpitKit.new()
	var lit := CockpitKit.new()
	# Dashboard: a top that falls from 0.93 at the driver's edge to 0.83 at the
	# cowl (y 0.83, z -0.69), a face toward the driver, a knee panel, and the
	# cowl lip. Roy (2026-10-06): the dash line sits at least DASH_TOP_MIN_DEG
	# (14) below the eye across the driver's view (to 20 degrees off axis, where
	# the cowl is further away); from the eye the cowl is the top of that line,
	# so it dropped from the body's 0.90 glass base (was 11.4 degrees).
	k.wedge(Vector3(1.74, 0.06, 0.40), Vector3(0.0, 0.80, -0.49), PLASTIC, 0.0, 0.10)   # base 0.77; top 0.83 far, 0.93 near
	k.box(Vector3(1.74, 0.36, 0.12), Vector3(0.0, 0.73, -0.33), PLASTIC_LIGHT)
	k.box(Vector3(1.74, 0.22, 0.32), Vector3(0.0, 0.48, -0.46), PLASTIC)
	k.box(Vector3(1.66, 0.03, 0.06), Vector3(0.0, 0.815, -0.70), TRIM)          # cowl lip, under the glass line
	lit.box(Vector3(1.60, 0.006, 0.01), Vector3(0.0, 0.912, -0.275), Color(AMBER, 0.35))   # dash edge strip
	# Cluster binnacle and its hood in front of the driver.
	k.box(Vector3(0.34, 0.12, 0.10), Vector3(SEAT_X, CLUSTER_Y, -0.40), PLASTIC)
	k.wedge(Vector3(0.38, 0.012, 0.16), Vector3(SEAT_X, CLUSTER_Y + 0.059, -0.42), PLASTIC_LIGHT, 0.0, -0.02)
	# Dial faces (backlit dark), rings and tick marks.
	for dx in [-0.085, 0.085]:
		var c := Vector3(SEAT_X + dx, CLUSTER_Y, CLUSTER_Z)
		lit.cylinder(DIAL_R, -0.004, 0.0, c, Color(DIAL_FACE, 0.15), 16, Basis(Vector3.RIGHT, PI / 2.0))
		k.cylinder(DIAL_R + 0.008, -0.008, -0.002, c + Vector3(0, 0, -0.001), TRIM, 16, Basis(Vector3.RIGHT, PI / 2.0))
		var ticks := 9 if dx < 0.0 else 7
		for i in ticks:
			var a := deg_to_rad(225.0 - DIAL_SWEEP * float(i) / (ticks - 1))
			var p := c + Vector3(cos(a), sin(a), 0.0) * (DIAL_R - 0.012) + Vector3(0, 0, 0.001)
			lit.box(Vector3(0.003, 0.009, 0.002), p, Color(AMBER, 0.6), Basis(Vector3.BACK, a - PI / 2.0))
		if dx < 0.0:
			# red zone on the tach, from the HUD's red band to the end
			var a0 := deg_to_rad(225.0 - DIAL_SWEEP * Hud.RED_FROM)
			var a1 := deg_to_rad(225.0 - DIAL_SWEEP)
			var zone := CockpitKit.new()
			zone.ring_sector(DIAL_R - 0.019, DIAL_R - 0.013, a1, a0, 0.0, 0.0015, Color(RED, 0.5), 4)
			zone.offset(c)
			lit.merge(zone)
	# Centre stack: vents, the radio bezel (the unit itself is built in _build_radio).
	k.box(Vector3(0.30, 0.24, 0.06), Vector3(0.0, 0.79, -0.30), PLASTIC_LIGHT)
	for vx in [-0.09, 0.09]:   # vents under the head unit
		k.box(Vector3(0.09, 0.03, 0.012), Vector3(vx, 0.712, -0.267), PLASTIC)
	# Centre console with the gate plate and its H slots, tunnel, armrest.
	k.box(Vector3(0.26, 0.20, 0.82), Vector3(0.0, 0.52, 0.11), PLASTIC)
	k.box(Vector3(0.30, 0.18, 1.20), Vector3(0.0, 0.33, 0.10), CARPET)             # tunnel
	k.box(Vector3(0.13, 0.012, 0.15), Vector3(0.0, 0.626, -0.02), TRIM)
	for sx in [-0.035, 0.0, 0.035]:
		k.box(Vector3(0.012, 0.004, 0.11), Vector3(sx, 0.633, -0.02), DIAL_FACE)
	k.box(Vector3(0.082, 0.004, 0.012), Vector3(0.0, 0.633, -0.02), DIAL_FACE)
	k.box(Vector3(0.20, 0.05, 0.22), Vector3(0.0, 0.645, 0.38), LEATHER)           # armrest
	lit.box(Vector3(0.006, 0.004, 0.60), Vector3(-0.133, 0.622, 0.05), Color(AMBER, 0.3))
	lit.box(Vector3(0.006, 0.004, 0.60), Vector3(0.133, 0.622, 0.05), Color(AMBER, 0.3))
	# Seats, driver and passenger.
	# Low sports seats: cushion top about 0.48, so a seated eye lands at the
	# cockpit camera's 1.06 (see DriverModel.PELVIS).
	for sx in [SEAT_X, -SEAT_X]:
		k.wedge(Vector3(0.50, 0.10, 0.50), Vector3(sx, 0.43, 0.36), SEAT, 0.03, 0.0)
		k.box(Vector3(0.10, 0.10, 0.46), Vector3(sx - 0.21, 0.50, 0.34), SEAT_PANEL)  # cushion bolsters
		k.box(Vector3(0.10, 0.10, 0.46), Vector3(sx + 0.21, 0.50, 0.34), SEAT_PANEL)
		var recline := Basis(Vector3.RIGHT, deg_to_rad(12.0))
		k.box(Vector3(0.50, 0.58, 0.10), Vector3(sx, 0.76, 0.61), SEAT, recline)
		k.box(Vector3(0.09, 0.50, 0.14), Vector3(sx - 0.22, 0.76, 0.59), SEAT_PANEL, recline)
		k.box(Vector3(0.09, 0.50, 0.14), Vector3(sx + 0.22, 0.76, 0.59), SEAT_PANEL, recline)
		k.box(Vector3(0.22, 0.10, 0.08), Vector3(sx, 1.10, 0.71), SEAT, recline)         # headrest
		k.box(Vector3(0.50, 0.06, 0.30), Vector3(sx, 0.36, 0.39), PLASTIC)              # seat base
	# Door cards, armrests, pulls, sills.
	for side in [-1.0, 1.0]:
		k.box(Vector3(0.06, 0.38, 0.95), Vector3(side * 0.86, 0.72, -0.02), PLASTIC_LIGHT)
		k.box(Vector3(0.06, 0.08, 0.95), Vector3(side * 0.86, 0.92, -0.02), LEATHER)      # belt line pad
		k.box(Vector3(0.12, 0.04, 0.32), Vector3(side * 0.79, 0.76, 0.08), LEATHER)       # armrest
		k.box(Vector3(0.05, 0.03, 0.12), Vector3(side * 0.80, 0.84, -0.22), TRIM)         # door pull
		lit.box(Vector3(0.004, 0.004, 0.70), Vector3(side * 0.828, 0.90, -0.02), Color(AMBER, 0.3))
		k.box(Vector3(0.14, 0.12, 1.30), Vector3(side * 0.80, 0.31, 0.0), PLASTIC)        # sill
		# B-pillar inner face and the rear quarter trim behind the door
		k.box(Vector3(0.06, 0.44, 0.08), Vector3(side * 0.78, 1.12, 0.46), PLASTIC)
		k.box(Vector3(0.08, 0.48, 0.60), Vector3(side * 0.74, 0.70, 0.78), PLASTIC_LIGHT)
	# A-pillars: from the cowl corners to the roof corners (body lines from the data).
	for side in [-1.0, 1.0]:
		_bar(k, Vector3(side * 0.78, 0.83, -0.69), Vector3(side * 0.62, 1.345, -0.03), 0.075, PLASTIC)
	# Roof liner, windshield header, sun visors. The eye is only 0.34 m behind
	# the glass top (y 1.34 at z -0.04), so the header and the liner's front
	# edge sit on that line, not under it: at 1.30 the header's underside hung
	# 25 to 31 degrees above the eye and took the top of the view (Roy's
	# clear-glass target, 2026-10-06). The visors fold flat against the liner.
	k.box(Vector3(1.36, 0.02, 0.80), Vector3(0.0, 1.33, 0.35), PLASTIC_LIGHT)
	k.box(Vector3(1.30, 0.05, 0.08), Vector3(0.0, 1.345, -0.03), PLASTIC)
	for sx in [SEAT_X, -SEAT_X]:   # folded up against the liner, above the view line
		k.box(Vector3(0.42, 0.012, 0.15), Vector3(sx, 1.318, 0.13), LEATHER, Basis(Vector3.RIGHT, deg_to_rad(-2.0)))
	# Rearview mirror housing and stalk (the glass is a CockpitMirrors quad).
	var rb := Basis(Vector3.UP, deg_to_rad(CockpitMirrors.REAR_YAW)) * Basis(Vector3.RIGHT, deg_to_rad(CockpitMirrors.REAR_PITCH))
	k.box(Vector3(0.215, 0.072, 0.022), CockpitMirrors.REAR_POS + rb * Vector3(0, 0, -0.013), PLASTIC, rb)
	k.box(Vector3(0.018, 0.08, 0.018), CockpitMirrors.REAR_POS + Vector3(0.0, 0.07, -0.02), PLASTIC)
	# Floor, footwell and firewall; rear bulkhead. (The door mirror cups are on
	# the body, P1CoupeBuilder; the parcel shelf is its own mesh, see _ready.)
	k.box(Vector3(1.70, 0.04, 1.40), Vector3(0.0, 0.27, 0.15), CARPET)
	k.wedge(Vector3(1.70, 0.04, 0.30), Vector3(0.0, 0.29, -0.60), CARPET, 0.16, 0.0)
	k.box(Vector3(1.74, 0.46, 0.04), Vector3(0.0, 0.50, -0.72), PLASTIC)
	k.box(Vector3(1.40, 0.42, 0.04), Vector3(0.0, 0.76, 0.92), PLASTIC_LIGHT)
	var shelf := CockpitKit.new()
	shelf.box(Vector3(1.40, 0.04, 0.72), Vector3(0.0, 0.98, 1.26), CARPET)
	add_child(shelf.instance(CockpitKit.material(), "Shelf"))
	_static_tris = k.tri_count() + lit.tri_count() + shelf.tri_count()
	add_child(k.instance(CockpitKit.material(0.85, 0.05), "Cabin"))
	add_child(lit.instance(CockpitKit.glow_material(BACKLIGHT_ENERGY), "Backlight"))

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
	wheel_mount.add_child(wheel)
	# A short column stub behind the hub (the long pole down the middle of the
	# view is gone, Roy 2026-10-06); the shroud is on the dash face, under the cluster.
	var k := CockpitKit.new()
	k.cylinder(0.024, -0.09, -0.03, Vector3.ZERO, PLASTIC_LIGHT, 8, Basis(Vector3.RIGHT, -PI / 2.0))
	wheel_mount.add_child(k.instance(CockpitKit.material(), "Column"))

# ---------- instrument cluster ----------

func _build_cluster() -> void:
	tach_needle = _needle(Vector3(SEAT_X - 0.085, CLUSTER_Y, CLUSTER_Z + 0.004), "TachNeedle")
	speedo_needle = _needle(Vector3(SEAT_X + 0.085, CLUSTER_Y, CLUSTER_Z + 0.004), "SpeedoNeedle")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.018, 0.009, 0.003)
	mm.mesh = box
	mm.instance_count = 4
	for i in 4:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.7, 0.7, 1.0)), Vector3(SEAT_X - 0.027 + 0.018 * i, CLUSTER_Y + 0.03, CLUSTER_Z + 0.002)))
		mm.set_instance_color(i, Color(AMBER, 0.0))
	lamps = MultiMeshInstance3D.new()
	lamps.name = "Lamps"
	lamps.multimesh = mm
	lamps.material_override = CockpitKit.glow_material(SteeringWheel.LED_ENERGY)
	add_child(lamps)
	lamp_text = _label("ENG BRK TYR CLT", 12, Vector3(SEAT_X, CLUSTER_Y + 0.015, CLUSTER_Z + 0.002), SILVER, 0.0004)
	lamp_text.name = "LampText"
	_label("x1000 rpm", 22, Vector3(SEAT_X - 0.085, CLUSTER_Y - 0.03, CLUSTER_Z + 0.002), AMBER, 0.0004)
	_label("km/h", 22, Vector3(SEAT_X + 0.085, CLUSTER_Y - 0.03, CLUSTER_Z + 0.002), AMBER, 0.0004)

func _needle(at: Vector3, node_name: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = at
	var k := CockpitKit.new()
	k.box(Vector3(0.004, 0.044, 0.002), Vector3(0.0, 0.018, 0.0), Color(RED, 1.0))
	k.box(Vector3(0.0035, 0.010, 0.002), Vector3(0.0, -0.008, 0.0), Color(SILVER, 0.3))
	k.cylinder(0.006, -0.001, 0.0015, Vector3.ZERO, Color(SILVER, 0.2), 8, Basis(Vector3.RIGHT, PI / 2.0))
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

## The head unit is its own builder (HeadUnit, styled per car), so the
## interior redesign can restyle it without touching the hand or the radio.
## On the stack right of the wheel, its bezel just under the dash top (0.91),
## so the tiles show over the wheel from the seat (lower, they were cut off by
## the bottom of the cockpit view).
const HEAD_UNIT_POS := Vector3(0.0, 0.832, -0.254)

func _build_radio() -> void:
	head_unit = HeadUnit.new(PlayerCar.chassis_kind())
	head_unit.position = HEAD_UNIT_POS
	add_child(head_unit)

## Next station: the key only asks; the driver's right hand reaches the screen
## and RadioManager.next_station() runs on the finger's contact
## (_on_hand_contact). Waits for the hand if it is busy (a shift, the handbrake).
func request_radio() -> void:
	driver.request_radio()

## Where the finger lands for the next station, car space, and which contact
## that is: the next tile, or past the last one the knob (radio off).
func radio_touch() -> Dictionary:
	var count := RadioStations.station_count()
	var s := _find_radio().station if _find_radio() != null else -1
	if s + 1 < count:
		return {"pos": head_unit.transform * head_unit.tile_point(s + 1), "contact": DriverModel.CONTACT_RADIO_TILE}
	return {"pos": head_unit.transform * head_unit.off_point(), "contact": DriverModel.CONTACT_RADIO_KNOB}

## The one place a hand touching something has an effect.
func _on_hand_contact(target: StringName) -> void:
	if target == DriverModel.CONTACT_RADIO_TILE or target == DriverModel.CONTACT_RADIO_KNOB:
		var r := _find_radio()
		if r != null:
			r.next_station()
		head_unit.tap(target == DriverModel.CONTACT_RADIO_KNOB and head_unit.has_knob)
		_update_radio(0.0)

# ---------- gear lever and handbrake ----------

func _build_lever() -> void:
	lever = Node3D.new()
	lever.name = "Lever"
	lever.position = Vector3(0.0, 0.615, -0.02)
	var k := CockpitKit.new()
	k.cylinder(0.008, 0.0, LEVER_LEN - 0.02, Vector3.ZERO, SILVER, 8)
	k.cylinder(0.02, 0.0, 0.02, Vector3.ZERO, LEATHER, 8)   # boot collar
	lever.add_child(k.instance(CockpitKit.material(0.35, 0.7)))
	lever_knob = Node3D.new()
	lever_knob.name = "Knob"
	lever_knob.position = Vector3(0.0, LEVER_LEN, 0.0)
	lever.add_child(lever_knob)
	add_child(lever)
	# one head per gearbox mode on the same knob point (the hand's target), and
	# the pattern printed on the console behind the boot; set_lever_mode shows one
	var mat := CockpitKit.material(0.6, 0.2)
	var h := CockpitKit.new()   # MANUAL: leather knob, silver top
	h.box(Vector3(0.040, 0.046, 0.040), Vector3.ZERO, LEATHER)
	h.box(Vector3(0.028, 0.004, 0.028), Vector3(0.0, 0.025, 0.0), SILVER)
	var s := CockpitKit.new()   # SEMI: taller sequential grip, silver collar
	s.cylinder(0.019, -0.03, 0.035, Vector3.ZERO, LEATHER, 10)
	s.cylinder(0.021, -0.034, -0.026, Vector3.ZERO, SILVER, 10)
	var a := CockpitKit.new()   # AUTO: T-handle with the lock button
	a.box(Vector3(0.066, 0.030, 0.034), Vector3(0.0, 0.004, 0.0), LEATHER)
	a.box(Vector3(0.012, 0.006, 0.014), Vector3(-0.02, 0.021, 0.0), SILVER)
	var heads := {
		PlayerCar.Transmission.MANUAL: [h, "KnobH", "1 3 5\n2 4 6 R"],
		PlayerCar.Transmission.SEMI: [s, "KnobSeq", "−\n+"],
		PlayerCar.Transmission.AUTO: [a, "KnobAuto", "R\nN\nD"],
	}
	for m in heads:
		var mi: MeshInstance3D = (heads[m][0] as CockpitKit).instance(mat, heads[m][1])
		lever_knob.add_child(mi)
		_lever_heads[m] = mi
		var l := _label(heads[m][2], 40, lever.position + Vector3(0.05, 0.004, 0.0), SILVER, 0.0005)
		l.name = "Gate" + (heads[m][1] as String).trim_prefix("Knob")
		l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # flat on the console, top line forward
		_gate_labels[m] = l

func _build_handbrake() -> void:
	handbrake = Node3D.new()
	handbrake.name = "Handbrake"
	handbrake.position = Vector3(0.0, 0.615, 0.44)
	var k := CockpitKit.new()
	k.box(Vector3(0.024, 0.024, 0.22), Vector3(0.0, 0.012, -0.11), TRIM)
	k.box(Vector3(0.034, 0.034, 0.08), Vector3(0.0, 0.017, -0.21), LEATHER)
	k.box(Vector3(0.016, 0.010, 0.016), Vector3(0.0, 0.034, -0.24), SILVER)     # release button
	handbrake.add_child(k.instance(CockpitKit.material(0.6, 0.3)))
	add_child(handbrake)

## Shows the lever for a gearbox mode (PlayerCar.Transmission) and puts it in
## that mode's slot for the current gear, with no move.
func set_lever_mode(mode: int) -> void:
	lever_mode = mode
	for m in _lever_heads:
		(_lever_heads[m] as Node3D).visible = m == mode
		(_gate_labels[m] as Node3D).visible = m == mode
	_lever_path.clear()
	_lever_wait = 0.0
	lever_moving = false
	_lever_gear = player.gear
	_lever_pos = _slot_of(player.gear)
	_apply_lever(_lever_pos)

## The slot of a gear as (column, row), row -1 forward and +1 back, in the
## current lever mode. MANUAL, the H-gate: odd gears forward, even gears and
## reverse back, 0 the neutral gate, reverse right of the last column. SEMI:
## the sequential stick rests in the centre in every gear. AUTO: one column,
## R forward, N, D back.
func _slot_of(g: int) -> Vector2:
	if lever_mode == PlayerCar.Transmission.SEMI:
		return Vector2.ZERO
	if lever_mode == PlayerCar.Transmission.AUTO:
		return Vector2(0.0, signf(float(g)))
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
## SEMI: a tap instead, back for an upshift and forward for a downshift, then
## back to the centre, after SEQ_WAIT so the driver's hand is on it first.
func move_lever_to(g: int) -> void:
	var to := _slot_of(g)
	_lever_path.clear()
	if lever_mode == PlayerCar.Transmission.SEMI:
		_lever_path.append(Vector2(0.0, 1.0 if g > _lever_gear else -1.0))
		_lever_path.append(Vector2.ZERO)
		_lever_wait = SEQ_WAIT
		_lever_gear = g
		lever_moving = true
		return
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
	if _lever_wait > 0.0:
		_lever_wait -= delta
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
		k.box(Vector3(0.018, 0.17, 0.012), Vector3(0.0, -0.085, 0.0), TRIM)
		k.box(Vector3(p[2], p[3], 0.012), Vector3(0.0, -0.17, 0.004), PLASTIC_LIGHT)
		pivot.add_child(k.instance(CockpitKit.material(0.7, 0.3)))
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
	cabin_light.light_color = AMBER
	cabin_light.light_energy = 1.1   # a touch more than the interior branch: the driver shows through the glass
	cabin_light.omni_range = 2.2
	cabin_light.omni_attenuation = 1.2
	cabin_light.shadow_enabled = false
	cabin_light.light_cull_mask = INTERIOR_BIT | DRIVER_BIT
	add_child(cabin_light)

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
	tach_needle.rotation = Vector3(0.0, 0.0, deg_to_rad(135.0 - DIAL_SWEEP * frac))
	var kmh := clampf(absf(p.current_speed()) * Hud.KMH_PER_MS / SPEEDO_MAX_KMH, 0.0, 1.0)
	speedo_needle.rotation = Vector3(0.0, 0.0, deg_to_rad(135.0 - DIAL_SWEEP * kmh))
	_update_lamps()
	var inputs := pedal_inputs()
	for key in pedals:
		(pedals[key] as Node3D).rotation_degrees = Vector3(PEDAL_TRAVEL_DEG * float(inputs[key]), 0.0, 0.0)
	handbrake.rotation_degrees = Vector3(28.0 * clampf(p.handbrake_input, 0.0, 1.0), 0.0, 0.0)
	# The lever follows the gearbox mode (G cycles it in the game).
	if p.transmission_mode() != lever_mode:
		set_lever_mode(p.transmission_mode())
	if p.automatic_transmission:
		# the box shifts itself: paddle flicks on the wheel, the selector only
		# moves between R, N and D
		if p.gear != _last_gear:
			wheel.flick(1 if p.gear > _last_gear else -1)
			_last_gear = p.gear
		if not lever_moving and _lever_gear != p.gear:
			if _slot_of(p.gear) != _slot_of(_lever_gear):
				move_lever_to(p.gear)
			else:
				_lever_gear = p.gear
	else:
		# Manual and semi: the lever starts for the requested gear the moment
		# the shift starts (the driver's hand rides it through the shift_time),
		# and is set straight on gear changes that skip is_shifting (out of neutral).
		if p.is_shifting and _lever_gear != p.requested_gear:
			move_lever_to(p.requested_gear)
		if p.gear != _last_gear:
			if _lever_gear != p.gear:
				move_lever_to(p.gear)
			_last_gear = p.gear
		if _lever_gear != p.gear and not lever_moving and not p.is_shifting:
			move_lever_to(p.gear)
	_step_lever(delta)
	_update_radio(delta)

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

func _find_radio() -> RadioManager:
	if radio == null and is_inside_tree():
		var scene := get_tree().current_scene
		if scene != null and scene.get("radio") is RadioManager:
			radio = scene.radio
	return radio

func _update_radio(delta: float) -> void:
	# The car clock (NightClock) is drawn on the head unit's screen.
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene != null and scene.get("night_clock") is NightClock:
		head_unit.show_clock(scene.night_clock.text())
	var r := _find_radio()
	if r == null:
		return
	var bus := AudioServer.get_bus_index(&"Music")
	var lvl := 0.0
	if bus >= 0 and r.station >= 0:
		var db := maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))
		lvl = clampf((db + 36.0) / 36.0, 0.0, 1.0)
	head_unit.show_state(r.station, r.now_playing, lvl, delta)

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
