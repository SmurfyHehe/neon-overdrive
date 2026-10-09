class_name GameState
extends Node

# Game-state machine (issue #27, ISSUES C2). Owns the run's top-level state
# and the actions that change it: pause, resume, restart, quit.
#
# Today there are only two states. Later milestones add theirs here (a run
# ending on damage, fuel running dry, a garage stop) rather than inventing a
# parallel flag somewhere else. Anything that cares listens to state_changed.
#
# Pausing uses the SceneTree's own pause, so physics (the GEVP vehicle) and
# every other default-mode node freeze. This node runs with
# PROCESS_MODE_ALWAYS so it still polls the pause action (Esc) while paused.
# The physics tick rate is 120 Hz (GEVP recommends at least 120 and breaks at
# 30 Hz); see tick_rate.gd.

# TUNING (#62) and AUTOTUNE are the two ways of opening the one Tuner screen
# (scripts/ui/tuner_screen.gd): paused like PAUSED, but the screen shows instead of
# the pause menu. TUNING shows it with the Auto-Tune section collapsed (T),
# AUTOTUNE with it expanded (Y). The Auto-Tune search runs in a
# separate headless Godot process (scripts/tuning/auto_tune_job.gd), because the game's
# physics can neither run faster than real time nor be stepped by hand.
# STATION: stopped at a gas station pump (scripts/world/gas_station.gd); paused
# while the pump menu (scripts/ui/pump_panel.gd) is up, Esc drives off.
enum State { PLAYING, PAUSED, TUNING, AUTOTUNE, PHOTO, STATION }

signal state_changed(new_state: State, old_state: State)
## Just before a restart reloads the scene / before the game quits (the save
## system: a restart starts a fresh run, a quit saves it).
signal restarting
signal quitting

var state: State = State.PLAYING

# T, Y and Esc are polled, which means a key typed into a text field (a tune slot
# name) would also switch tabs or close the tuner. _input() runs before the GUI
# sees the key, so it can tell whether a text control had focus when the key went
# down; the poll then skips that press.
const TEXT_GUARDED := [&"pause", &"tuning_panel", &"autotune_panel", &"photo_mode"]
var _typed_into_text: Dictionary = {}

## True for the two states that show the Tuner screen.
static func is_tuner(s: State) -> bool:
	return s == State.TUNING or s == State.AUTOTUNE

func _ready() -> void:
	PhotoMode.ensure_actions()
	process_mode = Node.PROCESS_MODE_ALWAYS

## True while a text control (LineEdit, TextEdit) has keyboard focus.
func typing_in_text() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and typing_in_text():
		for action in TEXT_GUARDED:
			if event.is_action(action):
				_typed_into_text[action] = true

# Polled like all game input (#30), not an event handler.
func _physics_process(_delta: float) -> void:
	var blocked := _typed_into_text
	_typed_into_text = {}
	if Input.is_action_just_pressed("pause") and not blocked.has(&"pause"):
		toggle_pause()
	elif Input.is_action_just_pressed("tuning_panel") and not blocked.has(&"tuning_panel"):
		toggle_tuning()
	elif Input.is_action_just_pressed("photo_mode") and not blocked.has(&"photo_mode"):
		toggle_photo()
	elif Input.is_action_just_pressed("autotune_panel") and not blocked.has(&"autotune_panel"):
		toggle_autotune()

## P: free-camera photo mode (scripts/ui/photo_mode.gd). Paused like the other screens.
func toggle_photo() -> void:
	if state == State.PHOTO:
		close_photo()
	elif state == State.PLAYING:
		get_tree().paused = true
		_set_state(State.PHOTO)

func close_photo() -> void:
	if state == State.PHOTO:
		get_tree().paused = false
		_set_state(State.PLAYING)

func toggle_pause() -> void:
	if state == State.TUNING:
		close_tuning()  # Esc backs out of the tuning panel
	elif state == State.AUTOTUNE:
		close_autotune()  # Esc backs out of Auto-Tune too
	elif state == State.PHOTO:
		close_photo()  # Esc leaves photo mode
	elif state == State.STATION:
		close_station()  # Esc drives off from the pump
	elif state == State.PAUSED:
		resume()
	elif state == State.PLAYING:
		pause()

func pause() -> void:
	if state != State.PLAYING:
		return
	get_tree().paused = true
	_set_state(State.PAUSED)

func resume() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	_set_state(State.PLAYING)

## The car stopped at a pump: the pump menu opens, the game pauses.
func open_station() -> void:
	if state != State.PLAYING:
		return
	get_tree().paused = true
	_set_state(State.STATION)

func close_station() -> void:
	if state == State.STATION:
		get_tree().paused = false
		_set_state(State.PLAYING)

## One tuner menu with two tabs (manual T, Auto-Tune Y): switching tab keeps the
## game paused. Does nothing outside the tuner.
func switch_tuner(to: State) -> void:
	if (to == State.TUNING or to == State.AUTOTUNE) and (state == State.TUNING or state == State.AUTOTUNE) and state != to:
		_set_state(to)

func toggle_tuning() -> void:
	if state == State.TUNING:
		close_tuning()
	elif state == State.AUTOTUNE:
		switch_tuner(State.TUNING)  # T from the Auto-Tune tab opens the manual tab
	elif state == State.PLAYING:
		get_tree().paused = true
		_set_state(State.TUNING)

func close_tuning() -> void:
	if state != State.TUNING:
		return
	get_tree().paused = false
	_set_state(State.PLAYING)

func toggle_autotune() -> void:
	if state == State.AUTOTUNE:
		close_autotune()
	elif state == State.TUNING:
		switch_tuner(State.AUTOTUNE)  # Y from the manual tab opens the Auto-Tune tab
	elif state == State.PLAYING:
		get_tree().paused = true
		_set_state(State.AUTOTUNE)

func close_autotune() -> void:
	if state == State.AUTOTUNE:
		get_tree().paused = false
		_set_state(State.PLAYING)

# Fresh run: reload the whole scene. Cheapest correct reset -- no per-system
# reset code to keep in sync as systems are added.
func restart() -> void:
	restarting.emit()
	get_tree().paused = false
	get_tree().reload_current_scene()

func quit() -> void:
	quitting.emit()
	get_tree().quit()

func _set_state(new_state: State) -> void:
	var old := state
	state = new_state
	# The engine sound is a generator pushed from _process, which stops while the
	# tree is paused; the buffer then underruns and clicks. Mute its bus for the
	# pause, unmute on the way back (Phase A, 2026-10-05).
	for bus_name in [&"Engine", &"Music"]:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus >= 0:
			AudioServer.set_bus_mute(bus, new_state != State.PLAYING)
	state_changed.emit(new_state, old)
