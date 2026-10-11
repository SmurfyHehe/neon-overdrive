class_name CarSimSwitch
extends RefCounted

# Switch for the C++ car physics (native/neon_sim, class CarSim), step 1: the
# per-wheel half of a GEVP tick (ray cast, surface, suspension, tyres, summed
# force). Off by default: every car runs the vendored GDScript, which stays the
# reference and the fallback.
#
# On when project setting neon/sim/native is true, or environment variable
# NEON_SIM_NATIVE=1 (tests), read once before the first car is built. If it is
# on but the library did not load (class CarSim missing), one warning is
# logged and every car runs the GDScript.
#
# This file must parse without the library, so it never names CarSim as a type;
# the two scripts that do are loaded by path, only when the class exists.

const SETTING := "neon/sim/native"
const WHEEL_SCRIPT := "res://scripts/car/car_sim_wheel.gd"
const BRIDGE_SCRIPT := "res://scripts/car/car_sim_bridge.gd"

static var enabled := OS.get_environment("NEON_SIM_NATIVE") == "1" \
		or bool(ProjectSettings.get_setting(SETTING, false))

static var _warned := false
static var _sim: Node = null
static var _wheel_script: GDScript = null
static var _bridge_script: GDScript = null

static func available() -> bool:
	return ClassDB.class_exists(&"CarSim")

static func active() -> bool:
	if not enabled:
		return false
	if available():
		return true
	if not _warned:
		_warned = true
		push_warning("neon/sim/native is on but the neon_sim library did not load (no class CarSim): cars use the GDScript physics.")
	return false

## The one CarSim node (C++), made on first use and parked under the root.
static func sim() -> Node:
	if _sim == null or not is_instance_valid(_sim):
		_sim = ClassDB.instantiate(&"CarSim")
		_sim.name = "CarSim"
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child.call_deferred(_sim)
	return _sim

## A wheel for a new car: the packing wheel when the C++ path is on, otherwise
## whatever the car would get anyway.
static func new_wheel() -> Wheel:
	if active():
		if _wheel_script == null:
			_wheel_script = load(WHEEL_SCRIPT)
		return _wheel_script.new()
	return NativeTyres.new_wheel()

## Gives a freshly built car its bridge to CarSim, if the C++ path is on and all
## four wheels are packing wheels. Otherwise the car is left on the GDScript.
static func attach(v: Vehicle) -> void:
	if not active():
		return
	if _wheel_script == null:
		_wheel_script = load(WHEEL_SCRIPT)
	for w in [v.front_left_wheel, v.front_right_wheel, v.rear_left_wheel, v.rear_right_wheel]:
		if w == null or w.get_script() != _wheel_script:
			return
	if _bridge_script == null:
		_bridge_script = load(BRIDGE_SCRIPT)
	v.sim_bridge = _bridge_script.new()

## Ground builders call this where they give a body its surface group, so the
## first wheel to touch it does not have to ask for its groups. Optional: an
## unknown collider is looked up once anyway. No-op while the switch is off.
static func note_ground(body: Node) -> void:
	if not active():
		return
	var groups := body.get_groups()
	if groups.size() > 0:
		sim().call(&"set_surface", body.get_instance_id(), groups[0])
