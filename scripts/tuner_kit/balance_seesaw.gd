class_name BalanceSeesaw
extends Control

# Balance on the performance card (Tuner UI overhaul PR 2): a small top-down
# car on a beam that tips toward Understeer (nose pushes wide, left) or
# Oversteer (tail steps out, right). The car turns with the balance: nose out
# for understeer, tail out for oversteer, with an arrow at the end that slides.
# Stock is a steel-blue mark on the beam. Balance runs -1 (understeer) .. +1.

var balance := 0.0
var stock := 0.0

func _init() -> void:
	custom_minimum_size = Vector2(220, 70)

func set_values(now_balance: float, stock_balance: float) -> void:
	balance = clampf(now_balance, -1.0, 1.0)
	stock = clampf(stock_balance, -1.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var font := UiTheme.font("strong")
	var w := size.x
	var beam_y := size.y - 18.0
	var half := w * 0.5 - 12.0
	var tilt := balance * 0.12
	var c := Vector2(w * 0.5, beam_y)
	var d := Vector2(cos(tilt), sin(tilt))
	# pivot and beam
	draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 9), c + Vector2(7, 9), c]), TunerColours.DIM)
	draw_line(c - d * half, c + d * half, TunerColours.PLOT, 4.0, true)
	draw_line(c + d * half * stock + Vector2(0, -6), c + d * half * stock + Vector2(0, 6), TunerColours.STOCK, 3.0)
	# the car, top-down, sat where the balance is
	var at := c + d * half * balance + Vector2(0.0, -22.0)
	var yaw := balance * 0.45  # nose out (left) or tail out (right)
	var body := [Vector2(-7, -16), Vector2(7, -16), Vector2(8, 14), Vector2(-8, 14)]
	var pts := PackedVector2Array()
	for p in body:
		pts.append(at + Vector2(p).rotated(yaw))
	draw_colored_polygon(pts, TunerColours.YOURS)
	draw_line(at + Vector2(-5, -11).rotated(yaw), at + Vector2(5, -11).rotated(yaw), TunerColours.PANEL, 2.0)  # windscreen: the nose is up
	# a slide arrow from the end that lets go
	if absf(balance) > 0.15:
		var end := at + Vector2(signf(balance) * 22.0, -4.0)
		var col := TunerColours.VALUE
		draw_line(end, end + Vector2(signf(balance) * 14.0, 0.0), col, 2.0)
		draw_colored_polygon(PackedVector2Array([end + Vector2(signf(balance) * 20.0, 0), end + Vector2(signf(balance) * 13.0, -4), end + Vector2(signf(balance) * 13.0, 4)]), col)
	draw_string(font, Vector2(2.0, size.y - 2.0), "Understeer", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TunerColours.DIM if balance > -0.15 else TunerColours.VALUE)
	draw_string(font, Vector2(0.0, size.y - 2.0), "Oversteer", HORIZONTAL_ALIGNMENT_RIGHT, w - 2.0, 13, TunerColours.DIM if balance < 0.15 else TunerColours.VALUE)
