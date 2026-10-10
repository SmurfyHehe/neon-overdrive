class_name RaceController
extends Node

# Race core (RC1, docs/planning/races-rivals-plan-2026-10-09.md section 8).
#
# A race is the player against one rival car on the same endless road, in the
# same traffic, first to a finish line a fixed distance down the road. The
# rival is a full-sim TrafficCar pinned by the TrafficManager (never recycled,
# never frozen into the kinematic cruise). In RC1 it is a scripted dummy: the
# ordinary traffic controller at a fixed cruise speed. RC2 swaps in the racing
# driver; nothing here reads the gap to drive the rival (no rubber-banding).
#
# Endings (plan section 3):
#   WIN     the player crosses the line first
#   LOSE    the rival crosses first (also how "let them go" ends a race)
#   GAVE_UP pause menu "Give up race"
#   BUSTED  busted mid-race (hook for the police stage; nothing calls it yet)
# A wreck ends nothing: a wrecked player must still cross the line, and a
# rival that is wrecked for good is simply out, so the player drives to the
# line alone (plan 3, Roy 87). Rival recovery (backing out, rejoining) is RC2.
#
# After any ending: a short caption, +15 min on the night clock, the rival is
# released back to traffic and drives off. Pay goes into a stub counter until
# cash exists (stops S0 / run structure R1).
#
# The phase is kept here, not as a GameState state: the game must stay
# PLAYING during a race (pause, photo mode and every PLAYING check keep
# working). GameState.race_active only blocks the Tuner mid-race.

enum Phase { IDLE, RACING, FINISHED }
enum Result { NONE, WIN, LOSE, GAVE_UP, BUSTED }

signal race_started(distance: float)
signal race_ended(result: Result)

const DEFAULT_DISTANCE := 1500.0   # m: a 60-120 s sprint at 50-90 km/h average
const DUMMY_KIND := "n2_cityhatch"
const DUMMY_SPEED := 30.0          # m/s, ~108 km/h: the scripted rival's cruise
const DUMMY_PAINT := Color("#C9CED6")  # silver
const NIGHT_MINUTES_PER_RACE := 15.0   # living-world rule: a race = +15 min
const CAPTION_SECONDS := 4.0
## Placeholder pay into the stub, in "nights of wages" (plan section 6: a
## sprint win ~0.3 night). No currency exists yet.
const PAY_WIN_NIGHTS := 0.3

const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")
const NAVY := Color("#0E1424")

var player: Node3D
var traffic: TrafficManager
var night_clock: NightClock
var game_state: GameState

var phase := Phase.IDLE
var result := Result.NONE
var distance := DEFAULT_DISTANCE
var rival: TrafficCar
## Absolute road distance (m) where the race started and where the line is.
var start_d := 0.0
var finish_d := 0.0
var race_time := 0.0
var rival_finished := false
## Stub wallet: total placeholder pay won, in nights of wages.
var stub_pay := 0.0
var races_run := 0

var _layer: CanvasLayer
var _readout: Label
var _caption: Label
var _caption_t := 0.0

func _init(p: Node3D = null, t: TrafficManager = null, clock: NightClock = null, state: GameState = null) -> void:
	player = p
	traffic = t
	night_clock = clock
	game_state = state

func _ready() -> void:
	_build_ui()
	# NEON_RACE=<metres> starts a race at once (tests, quick manual checks).
	var env := OS.get_environment("NEON_RACE")
	if env.is_valid_float() and float(env) > 0.0:
		start_race.call_deferred(float(env))

# ---------- pure helpers (tests use these) ----------

## Absolute distance down the road (m, grows as you drive -Z) of a world
## point. Survives floating-origin shifts: the chunk index counts the metres
## the world was moved back.
static func road_distance(world_pos: Vector3) -> float:
	return float(RoadFrame.origin_index) * RoadFrame.L - RoadFrame.unroll(world_pos).z

## Who wins from the two progress values (m past the start). The player wins a
## dead heat: they took the risk of racing.
static func decide(player_m: float, rival_m: float, dist: float) -> Result:
	if player_m >= dist:
		return Result.WIN
	if rival_m >= dist:
		return Result.LOSE
	return Result.NONE

static func result_text(r: Result) -> String:
	match r:
		Result.WIN: return "YOU WIN"
		Result.LOSE: return "THEY TOOK IT"
		Result.GAVE_UP: return "YOU GAVE UP"
		Result.BUSTED: return "BUSTED"
	return ""

# ---------- race flow ----------

func is_racing() -> bool:
	return phase == Phase.RACING

## A rolling start: the rival appears in the next lane level with the player,
## at the player's speed (the staged and flash starts are RC3/RC4).
func start_race(dist: float = DEFAULT_DISTANCE) -> bool:
	if phase == Phase.RACING or player == null or traffic == null:
		return false
	distance = dist
	start_d = road_distance(player.global_position)
	finish_d = start_d + distance
	race_time = 0.0
	rival_finished = false
	result = Result.NONE
	var u := RoadFrame.unroll(player.global_position)
	var v := 0.0
	if player is RigidBody3D:
		v = maxf(-RoadFrame.dir_to_road(u.z, (player as RigidBody3D).linear_velocity).z, 0.0)
	rival = traffic.add_rival(DUMMY_KIND, rival_lane_x(u.x, traffic.own_lanes), u.z, maxf(v, 1.0), DUMMY_PAINT)
	rival.target_speed = DUMMY_SPEED
	phase = Phase.RACING
	races_run += 1
	if game_state != null:
		game_state.race_active = true
	_show_caption("RACE  %.1f km" % (distance / 1000.0))
	race_started.emit(distance)
	return true

## The lane beside the player's (to the left when there is one, so the rival
## is never squeezed onto the shoulder).
static func rival_lane_x(player_x: float, own_lanes: int) -> float:
	var best := 0
	var best_d := INF
	for i in own_lanes:
		var d := absf(TrafficManager.lane_centre(i, false) - player_x)
		if d < best_d:
			best_d = d
			best = i
	var other := best - 1 if best > 0 else best + 1
	return TrafficManager.lane_centre(clampi(other, 0, own_lanes - 1), false)

func give_up() -> void:
	if phase == Phase.RACING:
		end_race(Result.GAVE_UP)

## Police stage hook: busted mid-race is a loss plus the normal bust rules.
func busted() -> void:
	if phase == Phase.RACING:
		end_race(Result.BUSTED)

func end_race(r: Result) -> void:
	if phase != Phase.RACING:
		return
	result = r
	phase = Phase.FINISHED
	if r == Result.WIN:
		stub_pay += PAY_WIN_NIGHTS
	if night_clock != null:
		night_clock.add_minutes(NIGHT_MINUTES_PER_RACE)
	traffic.release_rival(rival)
	rival = null
	if game_state != null:
		game_state.race_active = false
	_show_caption("%s   +%d min" % [result_text(r), int(NIGHT_MINUTES_PER_RACE)])
	race_ended.emit(r)

func player_progress() -> float:
	return road_distance(player.global_position) - start_d

func rival_progress() -> float:
	if rival == null or not is_instance_valid(rival):
		return -INF
	return road_distance(rival.global_position) - start_d

## Rival progress minus the player's: positive when the rival is ahead.
func gap() -> float:
	return rival_progress() - player_progress()

func rival_out() -> bool:
	return rival != null and is_instance_valid(rival) and rival.wrecked

func _physics_process(delta: float) -> void:
	if phase != Phase.RACING:
		return
	race_time += delta
	# A rival wrecked for good stops counting: the player drives to the line.
	var rm := rival_progress() if not rival_out() else -INF
	var r := decide(player_progress(), rm, distance)
	if r != Result.NONE:
		end_race(r)

func _process(delta: float) -> void:
	if _caption_t > 0.0:
		_caption_t -= delta
		if _caption_t <= 0.0:
			_caption.visible = false
			if phase == Phase.FINISHED:
				phase = Phase.IDLE
	_readout.visible = phase == Phase.RACING
	if phase == Phase.RACING:
		_readout.text = readout_text(distance - player_progress(), gap(), rival_out())

static func readout_text(to_go: float, g: float, out: bool) -> String:
	var line := "%d m to go" % int(maxf(to_go, 0.0))
	if out:
		return line + "    rival out"
	if g >= 0.0:
		return line + "    rival +%d m" % int(roundf(g))
	return line + "    you +%d m" % int(roundf(-g))

# ---------- UI: a small readout up top and a result caption ----------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6  # above the HUD (5), below warning lights (9) and pause (10)
	add_child(_layer)
	_readout = _label(18, SILVER)
	_readout.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_readout.position.y = 16.0
	_readout.visible = false
	_caption = _label(34, AMBER)
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.position.y = 70.0
	_caption.visible = false

func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", NAVY)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_layer.add_child(l)
	return l

func _show_caption(text: String) -> void:
	_caption.text = text
	_caption.visible = true
	_caption_t = CAPTION_SECONDS
