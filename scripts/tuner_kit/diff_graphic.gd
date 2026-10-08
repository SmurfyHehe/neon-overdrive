class_name DiffGraphic
extends PageGraphic

# Differential page: the rear axle from above, two wheels with spin arrows. An
# open diff lets the inside wheel spin up on its own (short arrow, long arrow);
# as it locks the two arrows match. A lock ring gauge beside it, stock as its
# steel-blue tick.

const FULL := 1000.0  # engage torque at which the diff reads fully open

var ring: RotaryDial

func _ready() -> void:
	ring = RotaryDial.new()
	ring.title = "LOCK"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if ring == null:
		return
	var gw := minf(120.0, size.x * 0.36)
	ring.position = Vector2(size.x - gw, (size.y - gw) * 0.35)
	ring.size = Vector2(gw, gw)

static func lock_of(s: Dictionary) -> float:
	return 1.0 - clampf(float(s.get("rear_locking_differential_engage_torque", FULL)) / FULL, 0.0, 1.0)

func show_setup(s: Dictionary, st: Dictionary, c := {}) -> void:
	super.show_setup(s, st, c)
	if ring != null and not s.is_empty():
		ring.set_values(lock_of(s), lock_of(st), "%d%%" % roundi(100.0 * lock_of(s)))

func _draw() -> void:
	if spec.is_empty():
		return
	var aw := size.x - minf(120.0, size.x * 0.36) - 12.0
	var c := Vector2(aw * 0.5, size.y * 0.45)
	text("REAR AXLE, CORNER EXIT", Vector2(6, 14))
	var half := aw * 0.36
	# axle and diff housing
	draw_line(c - Vector2(half, 0), c + Vector2(half, 0), TunerColours.DIM, 4.0)
	draw_rect(Rect2(c - Vector2(14, 12), Vector2(28, 24)), TunerColours.PLOT)
	draw_rect(Rect2(c - Vector2(14, 12), Vector2(28, 24)), TunerColours.YOURS, false, 2.0)
	var lock := lock_of(spec)
	var lock_s := lock_of(stock)
	for side in [-1.0, 1.0]:
		var wc := c + Vector2(side * half, 0)
		draw_rect(Rect2(wc - Vector2(10, 26), Vector2(20, 52)), TunerColours.PLOT)
		draw_rect(Rect2(wc - Vector2(10, 26), Vector2(20, 52)), TunerColours.LABEL, false, 1.5)
		# inside wheel (left here) spins up when the diff is open
		var spin := 1.0 if side > 0.0 else lerpf(2.0, 1.0, lock)
		var spin_s := 1.0 if side > 0.0 else lerpf(2.0, 1.0, lock_s)
		var x: float = wc.x + side * 26.0
		draw_line(Vector2(x + side * 4.0, wc.y + 30), Vector2(x + side * 4.0, wc.y + 30 - 28.0 * spin_s), TunerColours.STOCK, 2.0)
		arrow(Vector2(x, wc.y + 30), Vector2(x, wc.y + 30 - 28.0 * spin), TunerColours.YOURS, 3.0)
	var word := "Open: the inside wheel spins away" if lock < 0.3 else ("Locked: both wheels drive together" if lock > 0.7 else "Part locked")
	text(word, Vector2(6, size.y - 6.0), 13, TunerColours.LABEL)
