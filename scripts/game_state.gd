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
# The physics tick rate is untouched -- it must stay at 60 Hz (GEVP breaks at
# 30 Hz).

# TUNING (#62) is the debug tuning panel: paused like PAUSED, but the panel
# shows instead of the pause menu.
# AUTOTUNE is the Auto-Tune panel (paused like TUNING). Its search runs in a
# separate headless Godot process (scripts/auto_tune_job.gd), because the game's
# physics can neither run faster than real time nor be stepped by hand.
enum State { PLAYING, PAUSED, TUNING, AUTOTUNE }

signal state_changed(new_state: State, old_state: State)

var state: State = State.PLAYING

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# Polled like all game input (#30), not an event handler.
func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		toggle_pause()
	elif Input.is_action_just_pressed("tuning_panel"):
		toggle_tuning()
	elif Input.is_action_just_pressed("autotune_panel"):
		toggle_autotune()

func toggle_pause() -> void:
	if state == State.TUNING:
		close_tuning()  # Esc backs out of the tuning panel
	elif state == State.AUTOTUNE:
		close_autotune()  # Esc backs out of Auto-Tune too
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

func toggle_tuning() -> void:
	if state == State.TUNING:
		close_tuning()
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
	get_tree().paused = false
	get_tree().reload_current_scene()

func quit() -> void:
	get_tree().quit()

func _set_state(new_state: State) -> void:
	var old := state
	state = new_state
	state_changed.emit(new_state, old)
