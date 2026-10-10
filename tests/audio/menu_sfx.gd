extends SceneTree

# Menu sounds and slide (menus A-list, 2026-10-08):
# - every synthesised sound is non-empty, short and never clips
# - buttons, Back buttons, toggles and sliders added to the tree get their sound
# - sliders tick at most once per 45 ms
# - a programmatic grab_focus is silent (only arrow / Tab moves click)
# - MenuMotion slides a control home and fades it up while the tree is paused
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/audio/menu_sfx.gd

var failures: Array[String] = []
var sfx: MenuSfx
var box: Control
var step := 0
var t0 := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	for name in MenuSfx.NAMES:
		var s := MenuSfx.synth(name)
		_check(s.size() > 100, "%s should have samples" % name)
		_check(s.size() < MenuSfx.MIX_RATE * 0.5, "%s should be under half a second" % name)
		var peak := 0.0
		for v in s:
			peak = maxf(peak, absf(v))
		_check(peak <= 1.0 and peak > 0.05, "%s peak should be audible and not clip, got %.2f" % [name, peak])
		_check(MenuSfx.stream(name) is AudioStreamWAV, "%s should fall back to the synthesised WAV" % name)

func _process(_delta: float) -> bool:
	step += 1
	match step:
		1:
			sfx = MenuSfx.new()
			root.add_child(sfx)
			box = Control.new()
			root.add_child(box)
		2:
			var b := Button.new()
			b.text = "Restart"
			box.add_child(b)
			var back := Button.new()
			back.text = "Back"
			box.add_child(back)
			var chk := CheckButton.new()
			box.add_child(chk)
			var sl := HSlider.new()
			sl.max_value = 10
			box.add_child(sl)
			b.pressed.emit()
			back.pressed.emit()
			chk.button_pressed = true
			sl.value = 1
			sl.value = 2  # same instant: no second tick
			b.grab_focus()  # not from a key: silent
			_check(sfx.played.get("select", 0) == 1, "a button press should play select")
			_check(sfx.played.get("back", 0) == 1, "Back should play back")
			_check(sfx.played.get("toggle", 0) == 1, "a toggle should click")
			_check(sfx.played.get("tick", 0) == 1, "two slider steps at once should tick once, got %d" % sfx.played.get("tick", 0))
			_check(sfx.played.get("move", 0) == 0, "grab_focus without a key should be silent")
			paused = true
			box.set_anchors_preset(Control.PRESET_FULL_RECT)
			MenuMotion.slide_in(box)
			_check(box.position.x > 1.0 and box.modulate.a < 0.1, "slide should start off to the side and clear")
			t0 = Time.get_ticks_msec()
		_:
			if Time.get_ticks_msec() - t0 > int(MenuMotion.DURATION * 1000.0) + 300:
				_check(box.position.length() < 0.5, "slide should end home, at %s" % box.position)
				_check(box.modulate.a > 0.99, "slide should end opaque")
				paused = false
				print("menu_sfx: ", "FAIL" if not failures.is_empty() else "PASS")
				for f in failures:
					print("  - ", f)
				quit(1 if not failures.is_empty() else 0)
	return false
