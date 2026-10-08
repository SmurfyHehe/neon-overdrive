class_name MenuMotion
extends RefCounted

# Menu slide (menus A-list, 2026-10-08): a page slides a short way in and fades
# up when it opens. Runs while the tree is paused. The control must not sit
# inside a Container, which would put it back in place at the next sort, so
# callers slide a full-rect wrapper (a CenterContainer or MarginContainer whose
# parent is a CanvasLayer or a plain Control).

const DURATION := 0.18
const DISTANCE := 36.0

## Slides `c` in from `dir` (e.g. Vector2.RIGHT: it arrives moving left).
static func slide_in(c: Control, dir: Vector2 = Vector2.RIGHT) -> void:
	if c == null or not c.is_inside_tree():
		return
	if c.has_meta("menu_motion_tween"):
		var old: Tween = c.get_meta("menu_motion_tween")
		if old != null and old.is_valid():
			old.kill()
	var home := Vector2.ZERO  # full-rect wrappers live at the origin
	c.position = home + dir * DISTANCE
	c.modulate.a = 0.0
	var t := c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "position", home, DURATION)
	t.tween_property(c, "modulate:a", 1.0, DURATION * 0.8)
	c.set_meta("menu_motion_tween", t)
