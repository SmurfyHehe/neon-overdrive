extends Control

# The garage's mod tree panel (garage step G3a, 2026-10-11): one car's whole
# tree on a pegboard, drawn in 2D in a single _draw pass. Left 40% is the
# board (the tree, the chassis columns, the Bolt-on rail along the bottom);
# the right 60% is kept for the car on the lift (a placeholder until the
# garage room exists) with the part's card under it.
#
#   var panel := ModTreePanel.new()     # preload("res://scripts/ui/mod_tree_panel.gd")
#   add_child(panel)
#   panel.open("p1_coupe", wallet)      # false: the car has no tree (special vehicles)
#
# Keyboard only, no on-screen key hints: arrows move along the wires, Enter
# asks with a work-order ticket and then buys, or swaps to an owned engine
# branch for free, Escape backs out. The rules are GarageMods'; this file
# draws them. Stands on its own: nothing in the game opens it yet.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const GarageMods := preload("res://scripts/car/garage_mods.gd")

signal closed
signal bought(id: String, price: int)
signal swapped(id: String)

const BOARD := Color("#10141F")
const BOARD_HOLE := Color("#070A12")
const STEEL := Color("#7D8490")
const STEEL_DARK := Color("#4A505C")
const LOCK_FILL := Color("#161B28")
const LOCK_LINE := Color("#353C4C")
const WIRE_LOCKED := Color("#2A2F3B")
const HOT := Color("#FFA94D")        # the fitted branch: sodium, a step brighter
const GOOD := Color("#6FBF5A")
const TAPE := Color("#D9C58A")
const INK := Color("#1A1408")
const PEG_STEP := 22

var model := GarageMods.new()
var selected := ""
## The part a work-order ticket is asking about, "" when none is up.
var ticket := ""
## Walt's last word on a refused press (shown on tape for a moment).
var note := ""

var _note_left := 0.0
var _time := 0.0
var _peg: ImageTexture
var _board := Rect2()
var _lift := Rect2()
var _card := Rect2()

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func open(car_id: String, wallet: Object) -> bool:
	ticket = ""
	note = ""
	if not model.open(car_id, wallet):
		selected = ""
		visible = false
		return false
	selected = model.root
	visible = true
	queue_redraw()
	return true

## Opens one of the player's king crates on this car: the next deep step or
## keystone fitted is free.
func open_king_crate() -> bool:
	ticket = ""
	return model.open_king_crate()

# ---- Keys --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible or selected == "":
		return
	var dir := Vector2i.ZERO
	if event.is_action_pressed("ui_up", true):
		dir = Vector2i.UP
	elif event.is_action_pressed("ui_down", true):
		dir = Vector2i.DOWN
	elif event.is_action_pressed("ui_left", true):
		dir = Vector2i.LEFT
	elif event.is_action_pressed("ui_right", true):
		dir = Vector2i.RIGHT
	elif event.is_action_pressed("ui_accept"):
		accept()
	elif event.is_action_pressed("ui_cancel"):
		cancel()
	else:
		return
	if dir != Vector2i.ZERO:
		move(dir)
	get_viewport().set_input_as_handled()

func move(dir: Vector2i) -> void:
	if ticket != "":
		return
	selected = model.move(selected, dir)
	note = ""

func accept() -> void:
	if ticket != "":
		var id := ticket
		ticket = ""
		var r: Dictionary = model.buy(id)
		if r.ok:
			bought.emit(id, int(r.price))
		else:
			_say(String(r.reason))
		return
	match model.state(selected):
		GarageMods.BUYABLE:
			if model.crate_open and not model.crate_fits(selected):
				_say("The crate's for the deep stuff.")
			elif model.short_by(selected) > 0:
				_say("Short %s" % GarageMods.money(model.short_by(selected)))
			else:
				ticket = selected
		GarageMods.OWNED:
			if model.swap_to(selected):
				swapped.emit(selected)
		GarageMods.LOCKED:
			_say(model.lock_reason(selected))

func cancel() -> void:
	if ticket != "":
		ticket = ""
	elif model.crate_open:
		model.close_king_crate()
	else:
		closed.emit()

func _say(text: String) -> void:
	note = text
	_note_left = 2.5

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _note_left > 0.0:
		_note_left -= delta
		if _note_left <= 0.0:
			note = ""
	queue_redraw()

# ---- Drawing -----------------------------------------------------------------

func _pt(id: String) -> Vector2:
	return _board.position + model.items[id].pos * _board.size

func _radius(id: String) -> float:
	var it: Dictionary = model.items[id]
	var u := _board.size.x
	if it.kind == "core":
		return u * (0.046 if it.keystone else 0.04)
	return u * (0.017 if it.kind == "bolt" else 0.024)

func _draw() -> void:
	if selected == "" or not model.items.has(selected):
		return
	var pad := size.y * 0.025
	_board = Rect2(0, 0, size.x * 0.4, size.y)
	_lift = Rect2(_board.end.x + pad, pad * 2.6, size.x * 0.6 - pad * 2.0, size.y * 0.55)
	_card = Rect2(_lift.position.x, _lift.end.y + pad, _lift.size.x, size.y - _lift.end.y - pad * 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.DUSK)
	_draw_board()
	_draw_wires()
	for id in model.items:
		_draw_node(id)
	_draw_cursor()
	_draw_lift()
	_draw_card()
	if ticket != "":
		_draw_ticket()

func _text(role: String, pos: Vector2, text: String, px: float, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(UiTheme.font(role), pos, text, align, width, maxi(int(px), 8), col)

func _draw_board() -> void:
	draw_rect(_board, BOARD)
	if _peg == null:
		var img := Image.create(PEG_STEP, PEG_STEP, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in range(-2, 3):
			for x in range(-2, 3):
				if x * x + y * y <= 5:
					img.set_pixel(PEG_STEP / 2 + x, PEG_STEP / 2 + y, BOARD_HOLE)
		_peg = ImageTexture.create_from_image(img)
	draw_texture_rect(_peg, _board, true)
	draw_line(Vector2(_board.end.x, 0), _board.end, UiTheme.NAVY, 3.0)
	var u := _board.size.x
	var info: Dictionary = PlayerCars.info(model.car_id)
	_text("display", _board.position + Vector2(u * 0.04, size.y * 0.045), String(info.name).to_upper(), size.y * 0.04, UiTheme.AMBER)
	if model.crate_open:
		_text("menu_strong", _board.position + Vector2(u * 0.04, size.y * 0.075), "KING CRATE: ONE DEEP STEP OR KEYSTONE, ON THE HOUSE", size.y * 0.02, UiTheme.SODIUM)
	_text("numbers", Vector2(size.x - size.y * 0.42, size.y * 0.045), "BANK " + GarageMods.money(model.bank()), size.y * 0.032, UiTheme.AMBER,
		HORIZONTAL_ALIGNMENT_RIGHT, size.y * 0.4)
	# Chassis column heads, under the bus wire.
	for id in model.items:
		var it: Dictionary = model.items[id]
		if it.kind == "chassis" and it.rung == 1:
			var p := _pt(id)
			var drop := size.y * (0.035 if int(it.part_index) % 2 == 0 else 0.055)
			_text("menu", Vector2(p.x - u * 0.06, _board.position.y + GarageMods.ROOT_Y * size.y + drop), String(it.part_label).to_upper(), size.y * 0.016,
				UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, u * 0.12)
	# The Bolt-on rail.
	for y in GarageMods.RAIL_Y:
		var ry: float = _board.position.y + y * size.y
		draw_line(Vector2(u * 0.025, ry), Vector2(u * 0.975, ry), STEEL_DARK, 3.0)
	var low := false
	var after_narrow := false
	for g in model.bolt_groups:
		# Two one-column groups side by side: the second label goes under the rail.
		low = g.narrow and after_narrow and not low
		after_narrow = g.narrow
		var gy: float = GarageMods.RAIL_Y[1] + 0.04 if low else GarageMods.RAIL_Y[0] - 0.035
		_text("menu", Vector2(_board.position.x + g.x * u - u * 0.015, size.y * gy), String(g.name).to_upper(), size.y * 0.016, UiTheme.DIM)

## A small tag behind a node's label, so wires do not run through the words.
func _tag(role: String, centre: Vector2, text: String, px: float, col: Color) -> void:
	var w := UiTheme.font(role).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(px), 8)).x
	draw_rect(Rect2(centre.x - w * 0.5 - 3.0, centre.y - px * 0.95, w + 6.0, px * 1.25), Color(BOARD, 0.92))
	_text(role, Vector2(centre.x - w * 0.5, centre.y), text, px, col)

## A wire's corners: the chassis bus runs along Service's height and up; every
## other wire leaves upward, crosses over halfway and carries on up.
func _route(w: Dictionary) -> PackedVector2Array:
	var a := _pt(w.a)
	var b := _pt(w.b)
	if w.bus or is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y):
		return PackedVector2Array([a, Vector2(b.x, a.y), b])
	var mid := (a.y + b.y) * 0.5
	return PackedVector2Array([a, Vector2(a.x, mid), Vector2(b.x, mid), b])

## 0 locked, 1 next (buyable), 2 owned but swapped out, 3 lit, 4 the fitted branch.
func _wire_state(w: Dictionary) -> int:
	var sa: int = model.state(w.a)
	var sb: int = model.state(w.b)
	if sa == GarageMods.FITTED and sb == GarageMods.FITTED:
		var core: bool = model.items[w.a].kind == "core" and model.items[w.b].kind == "core"
		if core and not (w.a in model.chain and w.b in model.chain and model.chain.find(w.b) == model.chain.find(w.a) + 1):
			return 2
		return 4 if core else 3
	if sa >= GarageMods.OWNED and sb >= GarageMods.OWNED:
		return 2
	if sa >= GarageMods.OWNED and sb == GarageMods.BUYABLE:
		return 1
	# A keystone waiting on its other wire still shows the wire it has.
	if sa >= GarageMods.OWNED and model.items[w.b].get("keystone", false) and not model.owned.has(w.b):
		return 1
	return 0

func _draw_wires() -> void:
	var u := _board.size.x
	var look := [[WIRE_LOCKED, 0.008], [UiTheme.SILVER, 0.008], [UiTheme.AMBER.darkened(0.25), 0.009], [UiTheme.SODIUM, 0.011], [HOT, 0.016]]
	for pass_state in look.size():
		for i in model.wires.size():
			var w: Dictionary = model.wires[i]
			if _wire_state(w) != pass_state:
				continue
			var pts := _route(w)
			var width: float = u * look[pass_state][1]
			draw_polyline(pts, look[pass_state][0], width, true)
			if pass_state >= 3:
				# The slow pulse, travelling up the wire.
				var at := _along(pts, fmod(_time * 0.3 + i * 0.137, 1.0))
				draw_circle(at, width * 0.9, Color(1.0, 0.93, 0.75, 0.9))

static func _along(pts: PackedVector2Array, t: float) -> Vector2:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var left := total * t
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if left <= seg and seg > 0.0:
			return pts[i - 1].lerp(pts[i], left / seg)
		left -= seg
	return pts[pts.size() - 1]

func _draw_node(id: String) -> void:
	var it: Dictionary = model.items[id]
	var p := _pt(id)
	var r := _radius(id)
	var st: int = model.state(id)
	var ring: Color = [LOCK_LINE, UiTheme.SILVER, UiTheme.AMBER, UiTheme.SODIUM][st]
	draw_circle(p + Vector2(1, 2), r + 1.0, Color(0, 0, 0, 0.55))
	if st == GarageMods.BUYABLE:
		draw_circle(p, r * (1.35 + 0.12 * sin(_time * 3.0)), Color(UiTheme.SILVER, 0.16))
	if st == GarageMods.LOCKED:
		draw_circle(p, r, LOCK_FILL)
		if it.big:
			_hazard(p, r * 0.92)
	else:
		# A steel disc plate with four bolts.
		draw_circle(p, r, STEEL_DARK)
		draw_circle(p, r * 0.84, STEEL)
		if it.kind != "bolt":
			for k in 4:
				draw_circle(p + Vector2.from_angle(PI * 0.25 + k * PI * 0.5) * r * 0.62, r * 0.1, BOARD_HOLE)
		if st >= GarageMods.OWNED:
			draw_circle(p, r * (0.62 if it.kind == "bolt" else 0.42), ring)
		elif it.kind == "bolt":
			draw_circle(p, r * 0.3, STEEL_DARK)
	draw_arc(p, r, 0.0, TAU, 28, ring, maxf(r * (0.2 if st == GarageMods.FITTED else 0.13), 1.5), true)
	if it.kind == "bolt":
		return
	var px := size.y * 0.0165
	var row := 0.0
	if it.kind == "core":
		row = 2.5 * int(it.stagger)
		_tag("menu_strong" if st == GarageMods.FITTED else "menu", Vector2(p.x, p.y + r + px * (1.3 + row)), String(it.name), px,
			UiTheme.DIM if st == GarageMods.LOCKED else ring)
		row += 1.25
	if st == GarageMods.BUYABLE and it.kind != "chassis":
		_tag("numbers", Vector2(p.x, p.y + r + px * (1.3 + row)), GarageMods.money(model.price(id)), px, UiTheme.SILVER)

## Hazard tape across a locked big node.
func _hazard(p: Vector2, r: float) -> void:
	var across := Vector2(1, -1).normalized()
	var side := Vector2(1, 1).normalized()
	for k in range(-2, 3):
		var off := k * r * 0.4
		var half := sqrt(maxf(r * r - off * off, 0.0))
		var c := p + side * off
		draw_line(c - across * half, c + across * half, UiTheme.AMBER.darkened(0.45) if k % 2 == 0 else BOARD_HOLE, r * 0.2)

func _draw_cursor() -> void:
	var p := _pt(selected)
	var r := _radius(selected) * 1.45 + sin(_time * 5.0) * 1.2
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		draw_arc(p, r, a - 0.5, a + 0.5, 8, UiTheme.SODIUM, 3.0, true)
	# Walt's tape note on a locked node, or his answer to a refused press.
	var words: String = note if note != "" else (model.lock_reason(selected) if model.state(selected) == GarageMods.LOCKED else "")
	if words == "":
		return
	var px := size.y * 0.026
	var font := UiTheme.font("hand")
	var w := minf(font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x + px, _board.size.x * 0.9)
	var at := Vector2(clampf(p.x - w * 0.5, _board.position.x + 6.0, _board.end.x - w - 6.0), p.y - r - px * 1.9)
	if at.y < size.y * 0.06:
		at.y = p.y + r + px * 0.6
	draw_set_transform(at, -0.03)
	draw_rect(Rect2(0, 0, w, px * 1.45), TAPE)
	draw_string(font, Vector2(px * 0.5, px * 1.08), words, HORIZONTAL_ALIGNMENT_LEFT, w - px * 0.5, int(px), INK)
	draw_set_transform(Vector2.ZERO)

func _draw_lift() -> void:
	# Placeholder: the car on the lift goes here when the garage room exists.
	draw_rect(_lift, Color(UiTheme.NAVY, 0.35))
	draw_rect(_lift, UiTheme.NAVY, false, 2.0)
	_text("display", _lift.position + Vector2(0, _lift.size.y * 0.52), PlayerCars.title(model.car_id).to_upper(), size.y * 0.035,
		Color(UiTheme.DIM, 0.6), HORIZONTAL_ALIGNMENT_CENTER, _lift.size.x)

func _draw_card() -> void:
	var c: Dictionary = model.card(selected)
	var st: int = c.state
	draw_rect(_card, Color("#141C30"))
	draw_rect(_card, STEEL_DARK, false, 2.0)
	for corner in [Vector2(0.02, 0.07), Vector2(0.98, 0.07), Vector2(0.02, 0.93), Vector2(0.98, 0.93)]:
		draw_circle(_card.position + corner * _card.size, 3.0, STEEL)
	var x := _card.position.x + _card.size.x * 0.045
	var right := _card.end.x - _card.size.x * 0.045
	var y := _card.position.y + size.y * 0.058
	var colour: Color = [UiTheme.DIM, UiTheme.SILVER, UiTheme.AMBER, UiTheme.SODIUM][st]
	_text("display", Vector2(x, y), String(c.name).to_upper(), size.y * 0.042, colour)
	# Price or state, top right; the bank being short, in red under it.
	var tag: String = ["LOCKED", GarageMods.money(c.price), "OWNED", "FITTED"][st]
	_text("numbers", Vector2(right - size.y * 0.4, y), tag, size.y * 0.036, colour, HORIZONTAL_ALIGNMENT_RIGHT, size.y * 0.4)
	if st <= GarageMods.BUYABLE and c.short > 0:
		_text("numbers", Vector2(right - size.y * 0.4, y + size.y * 0.036), "Short " + GarageMods.money(c.short), size.y * 0.026, UiTheme.RED,
			HORIZONTAL_ALIGNMENT_RIGHT, size.y * 0.4)
	y += size.y * 0.036
	_text("menu", Vector2(x, y), String(c.feel), size.y * 0.024, UiTheme.SILVER)
	y += size.y * 0.02
	# The real numbers the part changes.
	var px := size.y * 0.024
	for line in c.lines:
		y += px * 1.35
		_text("menu", Vector2(x, y), String(line.label), px, UiTheme.DIM)
		var col: Color = GOOD if line.good > 0 else UiTheme.RED
		var tx := x + size.y * 0.15
		var up: bool = String(line.to).replace(",", "").to_float() > String(line.from).replace(",", "").to_float()
		var tip := Vector2(tx, y - px * (0.75 if up else 0.05))
		var base_y := y - px * (0.05 if up else 0.75)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(px * 0.38, 0), Vector2(tx, base_y), Vector2(tx + px * 0.76, base_y)]), col)
		_text("numbers", Vector2(tx + px * 1.2, y), "%s > %s %s" % [line.from, line.to, line.unit], px, col)
	# A keystone's two wires and which one is missing.
	for wire in c.wires:
		y += px * 1.35
		draw_circle(Vector2(x + px * 0.35, y - px * 0.3), px * 0.3, UiTheme.AMBER if wire.ok else LOCK_LINE)
		_text("menu", Vector2(x + px * 1.1, y), "%s: %s%s" % [wire.label, wire.what, "" if wire.ok else " (missing)"], px,
			UiTheme.AMBER if wire.ok else UiTheme.RED)
	# Four stat bars along the bottom: with the part, and a tick where it is without.
	var bw: float = (right - x) / c.bars.size()
	var by := _card.end.y - size.y * 0.03
	for i in c.bars.size():
		var bar: Dictionary = c.bars[i]
		var bx: float = x + bw * i
		var span := bw * 0.86
		_text("menu", Vector2(bx, by - size.y * 0.014), String(bar.label).to_upper(), size.y * 0.017, UiTheme.DIM)
		draw_rect(Rect2(bx, by, span, size.y * 0.009), BOARD_HOLE)
		draw_rect(Rect2(bx, by, span * bar.now, size.y * 0.009), UiTheme.AMBER)
		draw_rect(Rect2(bx + span * bar.was - 1.0, by - 3.0, 2.0, size.y * 0.009 + 6.0), UiTheme.SILVER)

func _draw_ticket() -> void:
	# A work-order ticket over the lift.
	var w := _lift.size.x * 0.62
	var h := size.y * 0.2
	var at := _lift.position + Vector2((_lift.size.x - w) * 0.5, _lift.size.y * 0.3)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	draw_set_transform(at, -0.015)
	draw_rect(Rect2(4, 5, w, h), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(0, 0, w, h), TAPE)
	draw_rect(Rect2(0, 0, w, h * 0.2), UiTheme.SODIUM.darkened(0.2))
	_text("menu_strong", Vector2(w * 0.04, h * 0.15), "WORK ORDER", size.y * 0.022, INK)
	draw_string(UiTheme.font("hand"), Vector2(w * 0.04, h * 0.5), model.ticket_text(ticket), HORIZONTAL_ALIGNMENT_LEFT, w * 0.92, int(size.y * 0.045), INK)
	draw_line(Vector2(w * 0.04, h * 0.82), Vector2(w * 0.96, h * 0.82), Color(INK, 0.4), 1.0)
	_text("numbers", Vector2(w * 0.04, h * 0.94), "BANK " + GarageMods.money(model.bank()), size.y * 0.02, Color(INK, 0.7))
	draw_set_transform(Vector2.ZERO)
