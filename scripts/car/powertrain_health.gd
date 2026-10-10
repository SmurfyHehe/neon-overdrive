class_name PowertrainHealth
extends RefCounted

# Heat and wear, v1 (Phase B, 2026-10-05). Warn first, then derate; NEVER end the
# run (Roy's rule: damage-ends-the-run waits for the garage stage). Two systems:
#
# - ENGINE temperature: heats with engine load and especially on the rev limiter,
#   cools with airspeed and a thermostat that cools harder when hot. Above
#   WARN_C the ENG light is amber, above DERATE_C torque falls toward
#   TORQUE_FLOOR (limp mode). Cooling off (lift, slow down) restores it.
# - BRAKE temperature: heats with braking power (force x speed), cools with
#   airspeed. Above FADE_START_C the brakes fade toward BRAKE_FLOOR; they never
#   fail. The BRK light shows from WARN_BRAKE_C.
#
# The vehicle only reads two multipliers, torque_mult and brake_mult (GEVP hooks,
# DEVIATIONs in gevp_vehicle.gd). All numbers are a feel call for Roy and live in
# the constants below. Off (enabled = false) in TuneTrack and any sim_only car, so
# Auto-Tune measurements stay clean.
#
# The state is plain numbers so the garage can save and repair it later.

const AMBIENT_C := 40.0           # engine bay / brake air temperature
const ENGINE_TAU := 35.0           # seconds for the engine to move 63% toward its balance temperature
const Q_IDLE := 45.0              # heat balance at idle: ambient + Q_IDLE / K_STILL = 85 degC
const Q_LOAD := 450.0             # extra heat at full engine load (scales with load squared)
const Q_LIMITER := 300.0          # extra heat while the fuel is cut at the limiter
const K_STILL := 1.0              # cooling standing still
const K_SPEED := 0.03             # more per m/s of airspeed
const THERMOSTAT_C := 95.0        # above this the cooling ramps up
const THERMOSTAT_GAIN := 0.08     # extra cooling factor per degC above it
const WARN_C := 100.0
const DERATE_C := 105.0
const LIMP_C := 120.0             # torque is at its floor from here
const TORQUE_FLOOR := 0.5

const BRAKE_C := 1400.0           # J per degC (4 brakes, effective)
const BRAKE_SHARE := 0.6          # fraction of braking energy that heats the discs
const BRAKE_COOL_BASE := 20.0     # W per degC, standing still
const BRAKE_COOL_SPEED := 3.0     # more per m/s
const WARN_BRAKE_C := 300.0
const FADE_START_C := 350.0
const FADE_END_C := 650.0
const BRAKE_FLOOR := 0.6

# Tyres (Phase C): temperature heats with slip power (load x slip x speed) and cools
# with airspeed; grip follows a window (cold and overheated both lose grip) and a
# slow wear loss. Per tyre, floors keep every tyre above TYRE_FLOOR of full grip.
const TYRE_HEAT_K := 0.0026
const TYRE_COOL_BASE := 0.05
const TYRE_COOL_SPEED := 0.004
const TYRE_TAU := 25.0
const TYRE_REF_LOAD := 3200.0       # N, a typical tyre load
const TYRE_WEAR_SLIP := 0.08        # slip beyond this wears the tyre
const TYRE_WEAR_K := 0.0002         # wear per (excess slip x load ratio x (speed + 6)) second
const TYRE_WEAR_LOSS := 0.15        # grip lost at full wear
const TYRE_FLOOR := 0.78
const WARN_TYRE_C := 120.0
const WARN_TYRE_WEAR := 0.8

# Clutch wear (Phase C): slipping power eats the clutch; a worn clutch holds less torque.
const CLUTCH_FREE_W := 500.0        # slip power below this is free (a closed clutch)
const CLUTCH_LIFE_J := 2.0e6
const CLUTCH_CAP_LOSS := 0.45       # fraction of grip lost at full wear
const WARN_CLUTCH_WEAR := 0.7

enum Warn { NONE = 0, ENG = 1, ENG_DERATE = 2, BRK = 4, BRK_FADE = 8, TYRE = 16, CLUTCH = 32 }

var enabled := true
var engine_temp := 85.0
var brake_temp := AMBIENT_C
var torque_mult := 1.0
var brake_mult := 1.0
var warnings := 0
## Engine cooling multiplier, set by CarDamage (a broken radiator cools worse).
var cooling_mult := 1.0
## Engine load 0..1 from the last step(), for FuelTank.
var engine_load := 0.0
var tyre_temp: Array[float] = [AMBIENT_C, AMBIENT_C, AMBIENT_C, AMBIENT_C]
var tyre_wear: Array[float] = [0.0, 0.0, 0.0, 0.0]
var tyre_grip: Array[float] = [1.0, 1.0, 1.0, 1.0]
var clutch_wear := 0.0
var clutch_cap := 1.0

## One physics step from raw numbers, so tests can drive it without a car.
## load 0..1 (engine power fraction), on_limiter, speed m/s, brake_power W.
func step_values(dt: float, load: float, on_limiter: bool, speed: float, brake_power: float) -> void:
	# engine: relax toward the balance of heat in and cooling out
	var heat := Q_IDLE + Q_LOAD * load * load + (Q_LIMITER if on_limiter else 0.0)
	var cool := (K_STILL + K_SPEED * speed) * (1.0 + THERMOSTAT_GAIN * maxf(engine_temp - THERMOSTAT_C, 0.0)) * cooling_mult
	var balance := AMBIENT_C + heat / cool
	engine_temp += (balance - engine_temp) * (1.0 - exp(-dt / ENGINE_TAU))
	engine_temp = clampf(engine_temp, AMBIENT_C, 200.0)
	torque_mult = clampf(1.0 - (engine_temp - DERATE_C) / (LIMP_C - DERATE_C) * (1.0 - TORQUE_FLOOR), TORQUE_FLOOR, 1.0)
	# brakes
	var bcool := (BRAKE_COOL_BASE + BRAKE_COOL_SPEED * speed) * (brake_temp - AMBIENT_C)
	brake_temp += (brake_power * BRAKE_SHARE - bcool) / BRAKE_C * dt
	brake_temp = clampf(brake_temp, AMBIENT_C, 1000.0)
	brake_mult = clampf(1.0 - (brake_temp - FADE_START_C) / (FADE_END_C - FADE_START_C) * (1.0 - BRAKE_FLOOR), BRAKE_FLOOR, 1.0)
	# lights
	warnings = Warn.NONE
	if engine_temp >= DERATE_C:
		warnings |= Warn.ENG | Warn.ENG_DERATE
	elif engine_temp >= WARN_C:
		warnings |= Warn.ENG
	if brake_temp >= FADE_START_C:
		warnings |= Warn.BRK | Warn.BRK_FADE
	elif brake_temp >= WARN_BRAKE_C:
		warnings |= Warn.BRK

## Grip multiplier for a tyre temperature: cold and overheated both lose grip.
static func temp_grip(t: float) -> float:
	if t < 40.0:
		return 0.88
	if t < 80.0:
		return lerpf(0.88, 1.0, (t - 40.0) / 40.0)
	if t <= 100.0:
		return 1.0
	return maxf(lerpf(1.0, 0.86, (t - 100.0) / 50.0), 0.80)

## One tyre for one step, from raw numbers (testable without a car).
## slip is the larger of slide angle and slip ratio, force the tyre's load in N.
func step_tyre(i: int, dt: float, speed: float, slip: float, force: float) -> void:
	var heat := TYRE_HEAT_K * force * slip * (speed + 2.0)
	var cool := TYRE_COOL_BASE + TYRE_COOL_SPEED * speed
	var balance := AMBIENT_C + heat / cool
	tyre_temp[i] += (balance - tyre_temp[i]) * (1.0 - exp(-dt / TYRE_TAU))
	tyre_temp[i] = clampf(tyre_temp[i], AMBIENT_C, 260.0)
	var excess := maxf(slip - TYRE_WEAR_SLIP, 0.0)
	tyre_wear[i] = clampf(tyre_wear[i] + excess * (force / TYRE_REF_LOAD) * (speed + 6.0) * TYRE_WEAR_K * dt, 0.0, 1.0)
	tyre_grip[i] = maxf(temp_grip(tyre_temp[i]) * (1.0 - TYRE_WEAR_LOSS * tyre_wear[i]), TYRE_FLOOR)
	if tyre_temp[i] >= WARN_TYRE_C or tyre_wear[i] >= WARN_TYRE_WEAR:
		warnings |= Warn.TYRE

## The clutch for one step: slip power (W) wears it, wear weakens it.
func step_clutch(dt: float, slip_power: float) -> void:
	clutch_wear = clampf(clutch_wear + maxf(slip_power - CLUTCH_FREE_W, 0.0) * dt / CLUTCH_LIFE_J, 0.0, 1.0)
	clutch_cap = clampf(1.0 - CLUTCH_CAP_LOSS * smoothstep(0.5, 1.0, clutch_wear), 1.0 - CLUTCH_CAP_LOSS, 1.0)
	if clutch_wear >= WARN_CLUTCH_WEAR:
		warnings |= Warn.CLUTCH

## Service: the garage will call this; for now the pause menu has a button.
func repair() -> void:
	engine_temp = 85.0
	brake_temp = AMBIENT_C
	for i in 4:
		tyre_temp[i] = AMBIENT_C
		tyre_wear[i] = 0.0
		tyre_grip[i] = 1.0
	clutch_wear = 0.0
	clutch_cap = 1.0

## One step from the car. Writes the two multipliers back onto it.
func step(v: Vehicle, dt: float) -> void:
	if not enabled:
		torque_mult = 1.0
		brake_mult = 1.0
		warnings = Warn.NONE
		v.torque_mult = 1.0
		v.brake_mult = 1.0
		v.clutch_cap_mult = 1.0
		for w in v.wheel_array:
			w.grip_mult = 1.0
		return
	var peak_power := v.max_torque * v.max_rpm / 9.5488 * 0.7  # rough W at the power peak
	var power := maxf(v.torque_output, 0.0) * v.motor_rpm / 9.5488
	engine_load = clampf(power / maxf(peak_power, 1.0), 0.0, 1.0)
	var brake_power := v.brake_force * v.speed
	step_values(dt, engine_load, v.limiter_cut, v.speed, brake_power)
	v.torque_mult = torque_mult
	v.brake_mult = brake_mult
	# tyres: the wheels are FL, FR, RL, RR
	for i in mini(4, v.wheel_array.size()):
		var w: Wheel = v.wheel_array[i]
		var slip := 0.0
		var force := 0.0
		if w.is_colliding():
			slip = maxf(absf(w.slip_vector.x), absf(w.slip_vector.y))
			force = w.spring_force
		step_tyre(i, dt, v.speed, slip, force)
		w.grip_mult = tyre_grip[i]
	# clutch: slip power = torque x speed difference across the plates
	var clutch_slip := 0.0
	if v.current_gear != 0 and v.clutch_amount < 0.95 and not v.auto_box_on:  # a torque converter slips in oil: no wear
		var engine_w := v.motor_rpm / 9.5488
		var input_w := v.get_drivetrain_spin() * v.get_gear_ratio(v.current_gear)
		clutch_slip = absf(v.clutch_torque) * absf(engine_w - input_w)
	step_clutch(dt, clutch_slip)
	v.clutch_cap_mult = clutch_cap

func is_warning(flag: int) -> bool:
	return (warnings & flag) != 0

## Only the wear numbers; temperatures reset on load. For the garage later.
func to_dict() -> Dictionary:
	return {"engine_temp": engine_temp, "brake_temp": brake_temp, "clutch_wear": clutch_wear, "tyre_wear": tyre_wear.duplicate()}

func from_dict(d: Dictionary) -> void:
	engine_temp = float(d.get("engine_temp", 85.0))
	clutch_wear = float(d.get("clutch_wear", 0.0))
	var tw: Array = d.get("tyre_wear", [0.0, 0.0, 0.0, 0.0])
	for i in 4:
		tyre_wear[i] = float(tw[i]) if i < tw.size() else 0.0
	brake_temp = float(d.get("brake_temp", AMBIENT_C))
