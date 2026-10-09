class_name WashScreen
extends CanvasLayer

# Garage wash mini-game (2026-10-09, Roy: "cleaning is a cleaning mini-game at
# the garage, not an automatic wash"). The car from above, caked in grime; you
# push a sponge over it with the arrow keys and the grime comes off where the
# sponge moves (a still sponge cleans nothing: you have to scrub). When almost
# all of it is gone the car reads CLEAN, CarDirt drops to 0 and the screen
# closes by itself. Esc leaves early and keeps whatever grime is left, so a
# half wash is a half-clean car.
#
# Opened from the pause menu ("Wash car") through GameState.open_wash; the
# garage will own the button when it exists. Keys are InputMap actions
# (wash_up and friends, registered here like photo mode's) so the Controls page
# lists them; nothing is written on the screen itself. Palette: navy, amber,
# silver, sodium, and a brown for the grime.

const KEYS := {"wash_up": KEY_UP, "wash_down": KEY_DOWN, "wash_left": KEY_LEFT, "wash_right": KEY_RIGHT}

const NAVY := Color("#0E1424")
const NAVY_LIGHT := Color("#1B2A4A")
const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const GRIME := Color("#4A3F31")
const PAINT := Color("#FF8A1F")

const CLEAN_HOLD_SECS := 0.9

## The scrubbing itself, no nodes, so a headless test can drive it.
class Model:
	const COLS := 24
	const ROWS := 48
	const SPONGE_R := 1.6          # cells
	const SCRUB_PER_CELL := 0.55   # grime removed per cell of sponge travel
	const SPEED := 14.0            # cells per second
	const DONE_AT := 0.03          # mean grime left that counts as clean
	var cells: PackedFloat32Array
	var mask: PackedByteArray      # 1 where the car is
	var start := 0.0               # mean grime at the start, for the progress bar
	var sponge := Vector2(COLS / 2.0, ROWS / 2.0)
	var done := false

	func _init(level: float, seed: int = 1) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		cells.resize(COLS * ROWS)
		mask.resize(COLS * ROWS)
		var n := 0
		var total := 0.0
		for r in ROWS:
			for c in COLS:
				var i := r * COLS + c
				mask[i] = 1 if _inside(c, r) else 0
				if mask[i] == 1:
					cells[i] = clampf(level * rng.randf_range(0.7, 1.0), 0.0, 1.0)
					total += cells[i]
					n += 1
				else:
					cells[i] = 0.0
		start = total / maxf(n, 1.0)
		done = start <= DONE_AT

	## A car outline seen from above: a rounded slab with the nose at the top.
	static func _inside(c: int, r: int) -> bool:
		var x := (c + 0.5) / COLS * 2.0 - 1.0   # -1..1 across
		var y := (r + 0.5) / ROWS                # 0 nose .. 1 tail
		var half_w := 0.72
		if y < 0.12:
			half_w = lerpf(0.42, 0.72, y / 0.12)
		elif y > 0.9:
			half_w = lerpf(0.72, 0.5, (y - 0.9) / 0.1)
		return absf(x) <= half_w

	## Mean grime left on the car, 0..1.
	func remaining() -> float:
		var total := 0.0
		var n := 0
		for i in cells.size():
			if mask[i] == 1:
				total += cells[i]
				n += 1
		return total / maxf(n, 1.0)

	## 0 = untouched, 1 = clean.
	func progress() -> float:
		if start <= 0.0:
			return 1.0
		return clampf(1.0 - remaining() / start, 0.0, 1.0)

	## Move the sponge by dir (unit-ish) for dt seconds; grime under the path comes off.
	func move(dir: Vector2, dt: float) -> void:
		if done or dir == Vector2.ZERO or dt <= 0.0:
			return
		var step := dir.normalized() * SPEED * dt
		var target := sponge + step
		target.x = clampf(target.x, 0.0, COLS)
		target.y = clampf(target.y, 0.0, ROWS)
		var travelled := sponge.distance_to(target)
		sponge = target
		if travelled <= 0.0:
			return
		_scrub(travelled * SCRUB_PER_CELL)
		if remaining() <= DONE_AT:
			done = true

	func _scrub(amount: float) -> void:
		var r0 := maxi(int(sponge.y - SPONGE_R) - 1, 0)
		var r1 := mini(int(sponge.y + SPONGE_R) + 1, ROWS - 1)
		var c0 := maxi(int(sponge.x - SPONGE_R) - 1, 0)
		var c1 := mini(int(sponge.x + SPONGE_R) + 1, COLS - 1)
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				var i := r * COLS + c
				if mask[i] == 0 or cells[i] <= 0.0:
					continue
				var d := Vector2(c + 0.5, r + 0.5).distance_to(sponge)
				if d <= SPONGE_R:
					cells[i] = maxf(cells[i] - amount * (1.0 - 0.5 * d / SPONGE_R), 0.0)

var game_state: GameState
var model: Model
var active := false
var _dirt: CarDirt
var _clean_t := -1.0
var _view: Control

static func ensure_actions() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.keycode = KEYS[action]
		InputMap.action_add_event(action, ev)

func _init(state: GameState) -> void:
	game_state = state
	name = "WashScreen"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11  # above the pause menu it was opened from
	visible = false
	ensure_actions()
	_view = View.new(self)
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	game_state.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: GameState.State, _old: GameState.State) -> void:
	var open := new_state == GameState.State.WASH
	if open and not active:
		_open()
	elif not open and active:
		_close()
	visible = open

func _find_dirt() -> CarDirt:
	var fx: Variant = get_parent().get("fx") if get_parent() != null else null
	if fx != null and fx.get("dirt") is CarDirt:
		return fx.dirt
	return null

func _open() -> void:
	_dirt = _find_dirt()
	var level := _dirt.level if _dirt != null else 0.0
	model = Model.new(level, int(Time.get_ticks_msec()))
	active = true
	_clean_t = -1.0
	if model.done:
		_finish()

## Esc (GameState.close_wash) or the car coming up clean: keep what is left.
func _close() -> void:
	if _dirt != null and model != null:
		_dirt.set_level(0.0 if model.done else model.remaining())
		_dirt.save_state()
	active = false

func _finish() -> void:
	model.done = true
	if _dirt != null:
		_dirt.set_level(0.0)
		_dirt.save_state()
	_clean_t = CLEAN_HOLD_SECS

func _process(delta: float) -> void:
	if not active or model == null:
		return
	if _clean_t >= 0.0:
		_clean_t -= delta
		if _clean_t < 0.0:
			game_state.close_wash()
		_view.queue_redraw()
		return
	var dir := Vector2(
		Input.get_action_strength("wash_right") - Input.get_action_strength("wash_left"),
		Input.get_action_strength("wash_down") - Input.get_action_strength("wash_up"))
	if dir != Vector2.ZERO:
		scrub(dir, delta)
	_view.queue_redraw()

## One sponge move; tests call this instead of pressing keys.
func scrub(dir: Vector2, dt: float) -> void:
	if not active or model == null or model.done:
		return
	model.move(dir, dt)
	if model.done:
		_finish()

## The picture: navy, the car from above, grime cells, the sponge, a progress bar.
class View:
	extends Control
	var screen: WashScreen

	func _init(s: WashScreen) -> void:
		screen = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var m := screen.model
		if m == null:
			return
		var vp := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vp), NAVY)
		var font := ThemeDB.fallback_font
		var title := "GARAGE WASH"
		draw_string(font, Vector2(vp.x / 2.0 - font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x / 2.0, 54.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, AMBER)

		var cell := minf((vp.y - 160.0) / Model.ROWS, (vp.x * 0.6) / Model.COLS)
		var origin := Vector2(vp.x / 2.0 - Model.COLS * cell / 2.0, 80.0)
		# Floor slab under the car.
		draw_rect(Rect2(origin - Vector2(cell * 2.0, cell * 2.0), Vector2((Model.COLS + 4) * cell, (Model.ROWS + 4) * cell)), NAVY_LIGHT)
		for r in Model.ROWS:
			for c in Model.COLS:
				var i := r * Model.COLS + c
				if m.mask[i] == 0:
					continue
				var p := origin + Vector2(c, r) * cell
				draw_rect(Rect2(p, Vector2(cell, cell)), PAINT)
				var g: float = m.cells[i]
				if g > 0.003:
					draw_rect(Rect2(p, Vector2(cell, cell)), Color(GRIME.r, GRIME.g, GRIME.b, clampf(g * 0.95, 0.0, 0.95)))
		# Windscreen and rear glass, so it reads as a car.
		var glass := Color(SILVER.r, SILVER.g, SILVER.b, 0.35)
		draw_rect(Rect2(origin + Vector2(4.0, 13.0) * cell, Vector2(Model.COLS - 8.0, 5.0) * cell), glass)
		draw_rect(Rect2(origin + Vector2(5.0, 30.0) * cell, Vector2(Model.COLS - 10.0, 4.0) * cell), glass)
		# Sponge.
		var sp := origin + m.sponge * cell
		var sr := Model.SPONGE_R * cell
		draw_rect(Rect2(sp - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0)), AMBER)
		draw_rect(Rect2(sp - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0)), SILVER, false, 2.0)
		# Progress bar.
		var bar := Rect2(Vector2(vp.x / 2.0 - 160.0, vp.y - 56.0), Vector2(320.0, 14.0))
		draw_rect(bar, NAVY_LIGHT)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * m.progress(), bar.size.y)), SODIUM)
		draw_rect(bar, SILVER, false, 1.0)
		if m.done:
			var t := "CLEAN"
			draw_string(font, Vector2(vp.x / 2.0 - font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x / 2.0, vp.y - 72.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, AMBER)
