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

enum Warn { NONE = 0, ENG = 1, ENG_DERATE = 2, BRK = 4, BRK_FADE = 8 }

var enabled := true
var engine_temp := 85.0
var brake_temp := AMBIENT_C
var torque_mult := 1.0
var brake_mult := 1.0
var warnings := 0

## One physics step from raw numbers, so tests can drive it without a car.
## load 0..1 (engine power fraction), on_limiter, speed m/s, brake_power W.
func step_values(dt: float, load: float, on_limiter: bool, speed: float, brake_power: float) -> void:
	# engine: relax toward the balance of heat in and cooling out
	var heat := Q_IDLE + Q_LOAD * load * load + (Q_LIMITER if on_limiter else 0.0)
	var cool := (K_STILL + K_SPEED * speed) * (1.0 + THERMOSTAT_GAIN * maxf(engine_temp - THERMOSTAT_C, 0.0))
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

## One step from the car. Writes the two multipliers back onto it.
func step(v: Vehicle, dt: float) -> void:
	if not enabled:
		torque_mult = 1.0
		brake_mult = 1.0
		warnings = Warn.NONE
		v.torque_mult = 1.0
		v.brake_mult = 1.0
		return
	var peak_power := v.max_torque * v.max_rpm / 9.5488 * 0.7  # rough W at the power peak
	var power := maxf(v.torque_output, 0.0) * v.motor_rpm / 9.5488
	var load := clampf(power / maxf(peak_power, 1.0), 0.0, 1.0)
	var brake_power := v.brake_force * v.speed
	step_values(dt, load, v.limiter_cut, v.speed, brake_power)
	v.torque_mult = torque_mult
	v.brake_mult = brake_mult

func is_warning(flag: int) -> bool:
	return (warnings & flag) != 0

## Only the wear numbers; temperatures reset on load. For the garage later.
func to_dict() -> Dictionary:
	return {"engine_temp": engine_temp, "brake_temp": brake_temp}

func from_dict(d: Dictionary) -> void:
	engine_temp = float(d.get("engine_temp", 85.0))
	brake_temp = float(d.get("brake_temp", AMBIENT_C))
