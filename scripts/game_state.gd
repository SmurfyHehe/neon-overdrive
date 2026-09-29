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

enum State { PLAYING, PAUSED }

signal state_changed(new_state: State, old_state: State)

var state: State = State.PLAYING

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# Polled like all game input (#30), not an event handler.
func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		toggle_pause()

func toggle_pause() -> void:
	if state == State.PAUSED:
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
