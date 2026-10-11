class_name RaceController
extends Node

# Race core (RC1, docs/planning/races-rivals-plan-2026-10-09.md section 8).
#
# A race is the player against one rival car on the same endless road, in the
# same traffic, first to a finish line a fixed distance down the road. The
# rival is a full-sim TrafficCar pinned by the TrafficManager (never recycled,
# never frozen into the kinematic cruise) with a racing driver at the wheel
# (RivalDriver, scripts/traffic/rival_driver.gd: racing line, late braking,
# flat out on the straights). Nothing here or there reads the gap to drive the
# rival (no rubber-banding): the driver never sees the player's progress or
# the finish line. The pause menu's "Race a test rival" starts the same race.
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
# Retry (T3, 2026-10-11): after a LOSE or GAVE_UP the pause menu's race button
# reads "Retry race". It fades out, puts both cars back at the start (the
# player's lane and the rival's beside it, at rest, facing down the road),
# parks traffic out of sight within RETRY_CLEAR_M of it, fades in and starts
# the same race again: same distance, same line. The +15 min is taken once
# per race and its retries (at the first ending); a retry adds none.
#
# The phase is kept here, not as a GameState state: the game must stay
# PLAYING during a race (pause, photo mode and every PLAYING check keep
# working). GameState.race_active only blocks the Tuner mid-race.

const RoadMap := preload("res://scripts/world/road_map.gd")

enum Phase { IDLE, RACING, FINISHED }
enum Result { NONE, WIN, LOSE, GAVE_UP, BUSTED }

signal race_started(distance: float)
signal race_ended(result: Result)

const DEFAULT_DISTANCE := 1500.0   # m: a 60-120 s sprint at 50-90 km/h average
const DUMMY_KIND := "n2_cityhatch"   # the RC1 dummy's car; tests still race it
const DUMMY_SPEED := 30.0          # m/s, ~108 km/h: what the rival cruises at once the race is over
## The rival's car until crews have their own: the hot hatch (the AI car
## numbers, CarSpec.npc_spec). Difficulty will change this build, never the
## driving.
const RIVAL_KIND := "p2_hothatch"
## While racing the rival keeps the full sim this far from the player, so it
## races the whole way instead of dropping to the traffic rails (far-mode rails
## are a later step). Only as far as the road is built when the road has hills:
## past the chunk pool there is no ground under a sim car.
const RACE_SIM_DISTANCE := 2000.0
const RACE_SIM_DISTANCE_HILLS := 180.0
const DUMMY_PAINT := Color("#C9CED6")  # silver
const NIGHT_MINUTES_PER_RACE := 15.0   # living-world rule: a race = +15 min
const CAPTION_SECONDS := 4.0
const RETRY_FADE_OUT := 0.25   # s to black before the cars move
const RETRY_FADE_IN := 0.25
## Traffic this close to the start (m, either way) is parked out of sight.
const RETRY_CLEAR_M := 150.0
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
## Which car and crew the next race's rival gets.
var rival_kind := RIVAL_KIND
var rival_crew := RivalPersonality.DOCKS
## Seed of the last race: the rival's one random stream. NEON_RACE_SEED=<n>
## fixes it (tests); otherwise each race rolls its own.
var race_seed := 0
var _pinned_before := TrafficManager.PINNED_DISTANCE_DEFAULT
## Absolute road distance (m) where the race started and where the line is.
var start_d := 0.0
var finish_d := 0.0
var race_time := 0.0
var rival_finished := false
## Stub wallet: total placeholder pay won, in nights of wages.
var stub_pay := 0.0
var races_run := 0
## Retries taken of the current race (0 for a fresh one).
var retries := 0

## The last race's start, for a retry: absolute road distance d, lateral x,
## height y, the race distance, road id and the save's place (RoadMap.where).
var _start := {}
var _retrying := false
## The +15 min is already on the clock for this race and its retries.
var _chain_paid := false
var _retry_state := 0  # 0 none, 1 fading out, 2 fading in
var _retry_t := 0.0
var _fade: ColorRect

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
	if not _retrying:
		retries = 0
		_chain_paid = false
	race_time = 0.0
	rival_finished = false
	result = Result.NONE
	var u := RoadFrame.unroll(player.global_position)
	var v := 0.0
	if player is RigidBody3D:
		v = maxf(-RoadFrame.dir_to_road(u.z, (player as RigidBody3D).linear_velocity).z, 0.0)
	_start = {"d": start_d, "x": u.x, "y": u.y, "distance": dist, "road_id": RoadMap.road_id,
		"where": RoadMap.where(u.z, -player.global_transform.basis.z)}
	var seed_env := OS.get_environment("NEON_RACE_SEED")
	race_seed = int(seed_env) if seed_env.is_valid_int() else int(randi())
	rival = traffic.add_rival(rival_kind, rival_lane_x(u.x, traffic.own_lanes), u.z, maxf(v, 1.0), DUMMY_PAINT)
	rival.racer = RivalDriver.new(RivalPersonality.row(rival_crew), race_seed)
	rival.racer.setup(rival)
	_pinned_before = traffic.pinned_distance
	traffic.pinned_distance = RACE_SIM_DISTANCE_HILLS if RoadFrame.has_hills() else RACE_SIM_DISTANCE
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
	if night_clock != null and not _chain_paid:
		night_clock.add_minutes(NIGHT_MINUTES_PER_RACE)
	_chain_paid = true
	# The driver gets out: the car drives off as traffic.
	RivalDriver.release(rival, DUMMY_SPEED)
	traffic.pinned_distance = _pinned_before
	traffic.release_rival(rival)
	rival = null
	if game_state != null:
		game_state.race_active = false
	_show_caption("%s   +%d min" % [result_text(r), int(NIGHT_MINUTES_PER_RACE)])
	race_ended.emit(r)

# ---------- retry ----------

## Whether the last race can be run again: it ended LOSE or GAVE_UP, nothing
## is running, and the road is the one it was on.
func can_retry() -> bool:
	if phase == Phase.RACING or _retry_state != 0 or _start.is_empty() or player == null or traffic == null:
		return false
	return (result == Result.LOSE or result == Result.GAVE_UP) and int(_start.road_id) == RoadMap.road_id

## Starts the retry: fade out, then _do_retry() at black. False if not offered.
func request_retry() -> bool:
	if not can_retry():
		return false
	_retry_state = 1
	_retry_t = 0.0
	_fade.visible = true
	_fade.color.a = 0.0
	return true

func retrying() -> bool:
	return _retry_state != 0

## At black: both cars back at the start, traffic parked off, the race on.
func _do_retry() -> void:
	var z := float(RoadFrame.origin_index) * RoadFrame.L - float(_start.d)
	traffic.clear_zone(z, RETRY_CLEAR_M)
	player.global_transform = RoadFrame.pose(float(_start.x), float(_start.y), z, 0.0)
	if player is RigidBody3D:
		var rb := player as RigidBody3D
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	if "previous_global_position" in player:
		player.set("previous_global_position", player.global_position)
	var wheels: Variant = player.get("wheel_array")
	if wheels is Array:
		for w in wheels:
			w.previous_global_position = w.global_position
	if "current_gear" in player:
		player.set("current_gear", 1)
	player.reset_physics_interpolation()
	# the road under the car now, not over the next frames (a retry can be a
	# kilometre back)
	var game := get_parent()
	if game != null and game.has_method("flush_rebuilds") and game.has_method("_update_chunk_pool"):
		game.call("_update_chunk_pool", z)
		game.call("flush_rebuilds")
	_retrying = true
	retries += 1
	start_race(float(_start.distance))
	_retrying = false

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
	if _retry_state != 0:
		_retry_t += delta
		if _retry_state == 1:
			_fade.color.a = clampf(_retry_t / RETRY_FADE_OUT, 0.0, 1.0)
			if _retry_t >= RETRY_FADE_OUT:
				_do_retry()
				_retry_state = 2
				_retry_t = 0.0
		else:
			_fade.color.a = 1.0 - clampf(_retry_t / RETRY_FADE_IN, 0.0, 1.0)
			if _retry_t >= RETRY_FADE_IN:
				_retry_state = 0
				_fade.visible = false
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
	# First, so the readout and caption stay over the black.
	_fade = ColorRect.new()
	_fade.color = Color(NAVY, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	_layer.add_child(_fade)
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
