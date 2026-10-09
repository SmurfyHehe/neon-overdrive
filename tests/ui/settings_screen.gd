extends SceneTree

# Settings screen (pause menu and title screen), headless:
# - the pause column is short: no sliders left on it, a Settings button instead
# - four pages (Sound, Picture, Driving, Controls) behind the tab row; sliders there
#   change and save their settings, including the Turbo hook
# - Picture: graphics Low / Medium / High applies and Custom shows when a slider moves
# - Controls: click a key, press a new one, Save keeps it; Back without Save drops it;
#   Reset + Save puts the defaults back and photo mode still works afterwards
# - Esc closes Settings and does NOT resume the game
# - a SettingsScreen with no GameState (the title screen) opens and closes by itself
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/ui/settings_screen.gd

var failures: Array[String] = []
var step := 0
var wait := 0
var state: GameState
var menu: PauseMenu
var standalone: SettingsScreen
var standalone_closed := false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.pressed = true
	return e

func _initialize() -> void:
	AudioSettings.path = "user://settings_screen_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	KeyBindings.load_settings()

func _finish() -> bool:
	DirAccess.remove_absolute(AudioSettings.path)
	KeyBindings.reset_defaults()
	print("settings_screen: ", "PASS" if failures.is_empty() else "FAIL")
	for f in failures:
		print("  - ", f)
	quit(0 if failures.is_empty() else 1)
	return true

func _key_button(action: StringName, slot: int) -> Button:
	for b in menu.settings.controls_scroll.find_children("*", "Button", true, false):
		if b.has_meta("bind") and b.get_meta("bind") == [action, slot]:
			return b
	return null

func _process(_delta: float) -> bool:
	if wait > 0:
		wait -= 1
		return false
	step += 1
	match step:
		1:
			state = GameState.new()
			root.add_child(state)
			menu = PauseMenu.new(state)
			root.add_child(menu)
			wait = 2
		2:
			state.pause()
			_check(menu.visible and menu.main_page.visible, "pausing opens the pause menu")
			_check(menu.main_page.find_children("*", "HSlider", true, false).is_empty(), "the pause column has no sliders left")
			_check(menu.main_page.find_children("*", "Button", true, false).size() <= 8, "the pause column is short")
			_check(menu.settings != null and not menu.settings.visible and menu.settings_button != null, "Settings starts closed, with a button")
			menu.settings_button.pressed.emit()
			_check(menu.settings.visible and menu.settings.current_page == 0, "the Settings button opens the Sound page")
			_check(menu.settings.pages.size() == 4 and menu.settings.tab_buttons.size() == 4, "four pages")
			_check(["Sound", "Picture", "Driving", "Controls"] == Array(SettingsScreen.PAGES), "page names")
			_check(state.modal_open, "game shortcuts stand down while Settings is open")
			var s := menu.settings
			# Sound
			s.volume_sliders["Music"].value = 0.4
			_check(is_equal_approx(AudioSettings.volumes["Music"], 0.4), "Music slider sets the volume")
			s.turbo_slider.value = 0.25
			_check(is_equal_approx(AudioSettings.turbo_volume, 0.25), "Turbo slider sets turbo volume")
			_check(is_equal_approx(AudioSettings.turbo_gain(), AudioSettings.volumes["Engine"] * 0.25), "turbo_gain is Engine x Turbo")
			var cfg := ConfigFile.new()
			cfg.load(AudioSettings.path)
			_check(is_equal_approx(float(cfg.get_value("audio", "turbo", -1.0)), 0.25), "turbo volume is saved")
			AudioSettings.turbo_volume = 1.0
			AudioSettings.load_settings()
			_check(is_equal_approx(AudioSettings.turbo_volume, 0.25), "turbo volume loads back")
			# Tabs
			s.show_page(1)
			_check(s.pages[1].visible and not s.pages[0].visible and s.tab_buttons[1].button_pressed, "tab switch shows only that page")
			# Picture
			s.gfx_preset.select(2)
			s.gfx_preset.item_selected.emit(2)
			_check(GraphicsSettings.preset == "high", "Quality High applies")
			s.gfx_preset.select(0)
			s.gfx_preset.item_selected.emit(0)
			_check(GraphicsSettings.preset == "low" and s.gfx_preset.selected == 0, "Quality Low applies")
			s.traffic_cars_slider.value = 35
			_check(GraphicsSettings.preset == "custom" and s.gfx_preset.selected == 3, "a hand-moved traffic slider shows Custom")
			_check(s.fullscreen_check != null and s.resolution_option.item_count >= 1, "Display controls exist")
			# Driving
			s.show_page(2)
			s.fov_slider.value = 70
			_check(is_equal_approx(ViewSettings.cockpit_fov, 70.0), "FOV slider sets the cockpit FOV")
			s.smoke_burnout_slider.value = 1.5
			_check(is_equal_approx(FxSettings.smoke_burnout, 1.5), "Burnout smoke slider")
			# Controls: rebind handbrake slot 0 to K
			s.show_page(3)
			_check(s.controls_save_button != null and s.controls_reset_button != null, "Controls has Save and Reset")
			var b := _key_button(&"handbrake", 0)
			_check(b != null, "a key button for handbrake")
			if b != null:
				b.pressed.emit()
				_check(b.text == "Press a key", "clicking a key waits for one")
				s._input(_key(KEY_K))
			_check(KeyBindings.keys(&"handbrake")[0] == KEY_K and s.keys_dirty, "pressing K binds it, not yet saved")
			s.controls_save_button.pressed.emit()
			var saved := ConfigFile.new()
			saved.load(AudioSettings.path)
			_check(saved.has_section_key("keys", "handbrake") and not s.keys_dirty, "Save writes the binding")
			# Rebind again, leave without Save: the saved K comes back
			b = _key_button(&"handbrake", 0)
			b.pressed.emit()
			s._input(_key(KEY_J))
			_check(KeyBindings.keys(&"handbrake")[0] == KEY_J, "J applies at once")
			s._input(_key(KEY_ESCAPE))   # closes the screen (no capture is waiting)
			_check(not s.visible, "Esc closes Settings")
			_check(KeyBindings.keys(&"handbrake")[0] == KEY_K, "leaving without Save drops J and keeps the saved K")
			wait = 3
		3:
			_check(not state.modal_open, "game shortcuts are back after Settings closes")
			_check(state.state == GameState.State.PAUSED, "closing Settings leaves the game paused")
			# Esc as the game polls it must not resume while Settings is open.
			menu.show_settings("Sound")
			Input.action_press(&"pause")
			wait = 4
		4:
			Input.action_release(&"pause")
			_check(state.state == GameState.State.PAUSED, "the Esc that is read while Settings is open must not resume the game")
			menu.settings.close()
			wait = 4
		5:
			# Reset + Save, then photo mode still has its keys.
			menu.show_settings("Controls")
			menu.settings.controls_reset_button.pressed.emit()
			_check(KeyBindings.keys(&"handbrake")[0] != KEY_K and menu.settings.keys_dirty, "Reset puts the defaults back")
			menu.settings.controls_save_button.pressed.emit()
			var cfg2 := ConfigFile.new()
			cfg2.load(AudioSettings.path)
			_check(not cfg2.has_section("keys") or cfg2.get_section_keys("keys").is_empty(), "Save after Reset leaves no key overrides")
			for action in PhotoMode.KEYS:
				_check(InputMap.has_action(action) and KeyBindings.keys(action)[0] == PhotoMode.KEYS[action], "photo action %s intact after Reset + Save" % action)
			menu.settings.close()
			state.resume()
			_check(not menu.settings.visible, "resuming leaves Settings closed")
			state.toggle_photo()
			_check(state.state == GameState.State.PHOTO, "photo mode still opens after Reset + Save")
			state.close_photo()
			# Title screen path: no GameState.
			standalone = SettingsScreen.new()
			standalone.closed.connect(func() -> void: standalone_closed = true)
			root.add_child(standalone)
			wait = 2
		6:
			standalone.open("Picture")
			_check(standalone.visible and standalone.current_page == 1, "Settings opens by itself on a page")
			standalone._input(_key(KEY_ESCAPE))
			_check(not standalone.visible and standalone_closed, "Esc closes it and says so")
			return _finish()
	return false
