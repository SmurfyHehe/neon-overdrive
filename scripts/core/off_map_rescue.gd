class_name OffMapRescue
extends CanvasLayer

# Off-map rescue (2026-10-10, Roy: "driving off the map", step 1). If the car
# ends up somewhere it cannot drive back from, the screen fades to black and
# the car is put back on the road where it last drove, standing still. Free:
# no fee, no damage, the run and the night carry on.
#
# "Somewhere impossible" is read in road space (RoadFrame.unroll: x across,
# y up from the surface, z along), once per physics tick:
# - a number in the car's state is NaN or infinite              -> at once
# - more than BELOW under the road surface (fell off or through) -> at once
# - more than ABOVE over it (thrown by a physics glitch)        -> at once
# - past the inner face of an out-of-bounds wall (in it, on top
#   of it or beyond it)                                         -> after GRACE
# - beside or beyond road that is not built (off either end of
#   the chunk pool: the road is only recycled forward)          -> after GRACE
# The two timed ones wait in case the car is only passing over (a hop along
# the top of the wall) and comes back by itself.
#
# Upside down ON the road is not handled here: that is a crash, not a place
# the map should not have let the car reach.
#
# Game._physics_process already unrolls the player's position each tick and
# RoadFrame memoises it, so the watch itself is a dozen comparisons.

## The car was put back; `reason` is one of the REASON_ strings.
signal rescued(reason: String)

const REASON_NAN := "bad numbers"
const REASON_BELOW := "below the road"
const REASON_ABOVE := "far above the road"
const REASON_OUTSIDE := "outside the walls"
const REASON_NO_ROAD := "off the end of the road"

## Under the road surface, m. The lowest a driving car's origin gets is a few
## cm (springs bottomed out in a dip).
const BELOW := 3.0
## Over the road surface, m: five times the wall height. The biggest crest
## jump clears a few metres.
const ABOVE := 60.0
## The car's centre this far past a wall's INNER face counts as outside, m: in
## the wall, on top of it, or beyond it. A car leaning on the wall keeps its
## centre most of a metre inside the face (half its width), so only a car the
## wall failed to hold reads as past it.
const OUTSIDE := 0.3
## Seconds outside the walls, or off the built road, before the rescue.
const GRACE := 0.5
const FADE_OUT := 0.25
const HOLD := 0.2
const FADE_IN := 0.4
## A spot is remembered as good only this far inside the walls, m ...
const GOOD_INSET := 1.0
## ... with this many wheels on the ground, this upright (basis.y.y) ...
const GOOD_WHEELS := 3
const GOOD_UP := 0.9
## Good spots are looked for every this many ticks (0.1 s at 120 Hz).
const REMEMBER_EVERY := 12
## ... and the car is put back this far inside the built road's ends, m.
const END_INSET := 30.0
## Room the car needs from traffic where it is put back: m along the road
## either way, and m across.
const CLEAR_Z := 14.0
const CLEAR_X := 2.4
## How far back it looks for a clear spot, in steps of CLEAR_Z.
const BACK_STEPS := 6

enum Phase { WATCH, FADE_OUT, HOLD, FADE_IN }

## Tests: false switches the watch off (the car can be left out of bounds).
var enabled := true
## How many times the car has been put back this session.
var count := 0
var last_reason := ""
var phase := Phase.WATCH

var _game: Node
var _player: PlayerCar
var _black: ColorRect
var _t := 0.0
var _out_for := 0.0
var _reason := ""
var _has_good := false
var _good_s := 0.0  # metres along the road (RoadFrame.s_at), origin-proof
var _good_x := 0.0
var _good_y := 0.0
var _chunk := {}  # the chunk_pool entry the car was last in
var _tick := 0

func _init(game: Node, player: PlayerCar) -> void:
	_game = game
	_player = player
	name = "OffMapRescue"
	layer = 8  # over the HUD (5), under the warning lights (9) and the menus (10)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.visible = false
	add_child(_black)

func _physics_process(delta: float) -> void:
	match phase:
		Phase.WATCH:
			_watch(delta)
		Phase.FADE_OUT:
			_t += delta
			_set_black(_t / FADE_OUT)
			if _t >= FADE_OUT:
				_put_back()
				phase = Phase.HOLD
				_t = 0.0
		Phase.HOLD:
			_t += delta
			if _t >= HOLD:
				phase = Phase.FADE_IN
				_t = 0.0
		Phase.FADE_IN:
			_t += delta
			_set_black(1.0 - _t / FADE_IN)
			if _t >= FADE_IN:
				phase = Phase.WATCH
				_out_for = 0.0

func _set_black(a: float) -> void:
	_black.color.a = clampf(a, 0.0, 1.0)
	_black.visible = _black.color.a > 0.0

## Why the car is off the map at this instant, "" if it is not. `timed` comes
## back true for the reasons that wait GRACE.
func check() -> Array:
	var p := _player.global_position
	if not (p.is_finite() and _player.linear_velocity.is_finite() and _player.angular_velocity.is_finite() and _player.global_transform.basis.is_finite()):
		return [REASON_NAN, false]
	var u := RoadFrame.unroll(p)
	if not u.is_finite():
		return [REASON_NAN, false]
	if u.y < -BELOW:
		return [REASON_BELOW, false]
	if u.y > ABOVE:
		return [REASON_ABOVE, false]
	var b := _bounds_at(u.z)
	if b == Vector2.ZERO:
		return [REASON_NO_ROAD, true]
	if u.x > b.x + OUTSIDE or u.x < -(b.y + OUTSIDE):
		return [REASON_OUTSIDE, true]
	return ["", false]

func _watch(delta: float) -> void:
	if not enabled:
		return
	var c := check()
	var reason: String = c[0]
	if reason == "":
		_out_for = 0.0
		_tick += 1
		if _tick % REMEMBER_EVERY == 0:
			_remember()
		return
	_out_for += delta
	if c[1] and _out_for < GRACE:
		return
	_reason = reason
	phase = Phase.FADE_OUT
	_t = 0.0

## Inner faces of the two walls (own side, oncoming side; both |x|) of the
## built chunk at road-space z; ZERO where no road is built.
func _bounds_at(z: float) -> Vector2:
	var idx: int = _game.origin_index + floori(-z / RoadChunkBuilder.CHUNK_LEN)
	# The car stays in one chunk for many ticks: try the one found last time.
	if _chunk.get("index", -1) == idx:
		return RoadChunkBuilder.bounds(_chunk.root)
	for c: Dictionary in _game.chunk_pool:
		if c.index == idx:
			_chunk = c
			return RoadChunkBuilder.bounds(c.root)
	return Vector2.ZERO

func _remember() -> void:
	if _player.global_transform.basis.y.y < GOOD_UP:
		return
	var down := 0
	for w in _player.wheel_array:
		if (w as Wheel).is_colliding():
			down += 1
	if down < GOOD_WHEELS:
		return
	var u := RoadFrame.unroll(_player.global_position)
	var b := _bounds_at(u.z)
	if b == Vector2.ZERO or u.x > b.x - GOOD_INSET or u.x < -(b.y - GOOD_INSET):
		return
	_has_good = true
	_good_s = RoadFrame.s_at(u.z)
	_good_x = u.x
	_good_y = u.y

## Road-space spot to put the car back on: the last good place along the
## road, kept inside the built road, in the own-direction lane nearest where
## it was, moved to another lane or further back if traffic stands there.
func target() -> Vector3:
	var l := RoadChunkBuilder.CHUNK_LEN
	var lo := INF
	var hi := -INF
	for c: Dictionary in _game.chunk_pool:
		lo = minf(lo, float(c.index) * l)
		hi = maxf(hi, float(c.index + 1) * l)
	var cur := RoadFrame.unroll(_player.global_position)
	var s: float = _good_s if _has_good else RoadFrame.s_at(cur.z)
	if not is_finite(s):
		s = (lo + hi) / 2.0
	s = clampf(s, lo + END_INSET, hi - END_INSET)
	var want_x: float = _good_x if _has_good else TrafficManager.lane_centre(_game.PLAYER_SPAWN_LANE, false)
	for back in BACK_STEPS + 1:
		var sb := maxf(s - float(back) * CLEAR_Z, lo + END_INSET)
		var z := float(RoadFrame.origin_index) * l - sb
		var lanes := _lanes_at(sb)
		lanes.sort_custom(func(a: float, b: float) -> bool: return absf(a - want_x) < absf(b - want_x))
		for x: float in lanes:
			if _clear(x, z):
				return Vector3(x, _good_y, z)
	# Nowhere clear (a jam six car lengths deep): the nearest lane anyway.
	return Vector3(_lanes_at(s)[0], _good_y, float(RoadFrame.origin_index) * l - s)

func _lanes_at(s: float) -> Array[float]:
	var n: int = _game.OWN_LANES
	if RoadFrame.layout != null:
		n = RoadFrame.layout.lanes_at(false, s)
	var xs: Array[float] = []
	for i in maxi(n, 1):
		xs.append(TrafficManager.lane_centre(i, false))
	return xs

func _clear(x: float, z: float) -> bool:
	var traffic: TrafficManager = _game.traffic
	if traffic == null:
		return true
	for car in traffic.cars:
		if car.benched or not car.global_position.is_finite():
			continue
		var u := RoadFrame.unroll(car.global_position)
		if absf(u.z - z) < CLEAR_Z and absf(u.x - x) < CLEAR_X:
			return false
	return true

func _put_back() -> void:
	var u := target()
	_player.global_transform = RoadFrame.pose(u.x, u.y, u.z, 0.0)
	# Standing still, with the sim's saved positions and wheel spin to match
	# (GEVP reads speed off them; see Game._shift_origin).
	TrafficCar.set_moving(_player, 0.0)
	for w in _player.wheel_array:
		w.last_collision_point = w.global_position
	_player.reset_physics_interpolation()
	# The stop is not a crash: no damage and no camera shake from it.
	_player.damage.forget_motion()
	var cam: ChaseCamera = _game.camera
	if cam != null:
		cam.forget_motion()
	count += 1
	last_reason = _reason
	print("OffMapRescue: car put back on the road (%s)" % _reason)
	rescued.emit(_reason)
