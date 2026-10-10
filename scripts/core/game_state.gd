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
# TITLE is the title screen before the first drive (title_screen.gd): paused
# like PAUSED, but the title shows instead of the pause menu. Only the first boot
# of a session shows it; Restart goes straight back to the road.
enum State { PLAYING, PAUSED, TUNING, AUTOTUNE, PHOTO, TITLE }

const SaveStore := preload("res://scripts/save/save_store.gd")

signal state_changed(new_state: State, old_state: State)
## Just before a restart reloads the scene / before the game quits (the save
## system: a restart starts a fresh run, a quit saves it).
signal restarting
signal quitting

var state: State = State.PLAYING

## Pause when the window loses focus (alt-tab). Game turns it on for real play
## sessions only, so a test window that loses focus keeps running.
var pause_on_focus_loss := false

## A real frame this long (seconds) while playing means the machine fell behind;
## the game pauses itself instead of letting the car drive on unseen. 0 = off
## (Game turns it on for real play sessions; the benchmark and tests leave it off).
var stall_secs := 0.0
const STALL_SECS := 0.75   # what Game sets it to

## Why the game paused itself ("" = the player did): shown as one amber line on
## the pause screen (pause_menu.gd), cleared on resume.
const REASON_STALL := "The game paused itself because it fell behind. Try a lower Picture setting."
const REASON_FOCUS := "The game paused because the window lost focus."
var pause_notice := ""

## Set once the player has left the title screen; a static, so it survives the
## scene reload that Restart does (instant retry, no title in between).
static var title_seen := false

## True while a race is on (the race core sets it). The pause menu then offers
## "Quit race" instead of "Restart night".
var in_race := false
signal race_quit_requested

## Pausing by hand is refused while a cop has eyes on the player (the open chase
## the save system tracks); the pause screen shows this for a second instead.
const CHASE_LOCK_TEXT := "Not while they're on you."
signal pause_refused

## Title screen at boot: in a real play session, or when a test sets NEON_TITLE=1.
static func wants_title() -> bool:
	if title_seen:
		return false
	return OS.get_environment("NEON_TITLE") == "1" or DisplaySettings.player_run()

# T, Y and Esc are polled, which means a key typed into a text field (a tune slot
# name) would also switch tabs or close the tuner. _input() runs before the GUI
# sees the key, so it can tell whether a text control had focus when the key went
# down; the poll then skips that press.
const TEXT_GUARDED := [&"pause", &"tuning_panel", &"autotune_panel", &"photo_mode"]
var _typed_into_text: Dictionary = {}

# The Settings screen (scripts/ui/settings_screen.gd) sits on top of the pause
# menu and takes Esc and every key itself (closing, capturing a new key for a
# binding), so the polled shortcuts below stand down while it is open. Closing
# is delayed by one physics tick, so the Esc that closed it is not also read as
# "resume".
var modal_open := false
var _modal_release := false

func set_modal(on: bool) -> void:
	if on:
		modal_open = true
		_modal_release = false
	else:
		_modal_release = true

## True for the two states that show the Tuner screen.
static func is_tuner(s: State) -> bool:
	return s == State.TUNING or s == State.AUTOTUNE

## Opens the pause screen when fps stays under 30 for about a second or a frame
## freezes for half a second (Roy 160). Off in headless runs and tests.
var auto_pause_on_low_fps := true
var _fps_watch := LowFpsWatch.new()
var _last_frame_usec := 0

func _ready() -> void:
	PhotoMode.ensure_actions()
	process_mode = Node.PROCESS_MODE_ALWAYS
	auto_pause_on_low_fps = auto_pause_on_low_fps and DisplayServer.get_name() != "headless"
	state_changed.connect(func(_n, _o): _fps_watch.reset())

func _process(_delta: float) -> void:
	# Wall-clock frame time: unaffected by time scale and by get_tree().paused.
	var now := Time.get_ticks_usec()
	var frame_seconds := (now - _last_frame_usec) / 1000000.0 if _last_frame_usec > 0 else 0.0
	_last_frame_usec = now
	if not auto_pause_on_low_fps or state != State.PLAYING:
		return
	if _fps_watch.feed(frame_seconds):
		pause()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and state == State.PLAYING:
		pause(REASON_FOCUS)

## Stall guard: a frame the real clock says took too long while the game runs.
## It stands down for STALL_GRACE seconds after play starts or resumes: the
## first frames after a scene load or an unpause are always slow.
const STALL_GRACE := 2.0
var _grace := STALL_GRACE

func _process(delta: float) -> void:
	if stall_secs <= 0.0 or state != State.PLAYING:
		return
	if _grace > 0.0:
		_grace -= delta
	elif delta >= stall_secs:
		pause(REASON_STALL)

## True while a chase is open: the pause key is refused.
static func chase_locked() -> bool:
	return SaveStore.chase_active

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
	var modal := modal_open
	if _modal_release:
		modal_open = false
		_modal_release = false
	if modal:
		return
	if state == State.TITLE and _title_freeze_at >= 0 and Engine.get_physics_frames() >= _title_freeze_at:
		_title_freeze_at = -1
		get_tree().paused = true
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

## Photo mode from the pause screen; Esc in photo mode comes back to it.
func open_photo_from_pause() -> void:
	if state == State.PAUSED:
		_photo_from_pause = true
		_set_state(State.PHOTO)

var _photo_from_pause := false

func close_photo() -> void:
	if state != State.PHOTO:
		return
	if _photo_from_pause:
		_photo_from_pause = false
		_set_state(State.PAUSED)
		return
	get_tree().paused = false
	_set_state(State.PLAYING)

func toggle_pause() -> void:
	if state == State.TUNING:
		close_tuning()  # Esc backs out of the tuning panel
	elif state == State.AUTOTUNE:
		close_autotune()  # Esc backs out of Auto-Tune too
	elif state == State.PHOTO:
		close_photo()  # Esc leaves photo mode
	elif state == State.PAUSED:
		resume()
	elif state == State.PLAYING:
		if chase_locked():
			pause_refused.emit()   # the menu stays shut while a cop sees you
		else:
			pause()

## `notice` is the amber line the pause screen shows ("" for the player's own Esc).
func pause(notice := "") -> void:
	if state != State.PLAYING:
		return
	pause_notice = notice
	get_tree().paused = true
	_set_state(State.PAUSED)

func resume() -> void:
	if state != State.PAUSED:
		return
	pause_notice = ""
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

## Back to the title screen. The run is saved like a quit (a chase left open
## counts as a bust on the next load); the scene reloads and the title shows.
func quit_to_title() -> void:
	quitting.emit()
	title_seen = false
	get_tree().paused = false
	get_tree().reload_current_scene()

## The world freezes a few ticks after the title appears, so the car settles on
## its springs and the camera reaches its place behind it first.
const TITLE_SETTLE_TICKS := 20
var _title_freeze_at := -1

func enter_title() -> void:
	if state != State.PLAYING:
		return
	_title_freeze_at = Engine.get_physics_frames() + TITLE_SETTLE_TICKS
	_set_state(State.TITLE)

## Drive from the title screen.
func start_drive() -> void:
	if state != State.TITLE:
		return
	title_seen = true
	_title_freeze_at = -1
	get_tree().paused = false
	_set_state(State.PLAYING)

func _set_state(new_state: State) -> void:
	var old := state
	state = new_state
	if new_state == State.PLAYING:
		_grace = STALL_GRACE
	# The engine sound is a generator pushed from _process, which stops while the
	# tree is paused; the buffer then underruns and clicks. Mute its bus for the
	# pause, unmute on the way back (Phase A, 2026-10-05).
	# The radio plays on, muffled, on the pause screen and the title (PauseLook);
	# only the Tuner and photo mode still mute it.
	for bus_name in [&"Engine", &"Turbo"]:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus >= 0:
			AudioServer.set_bus_mute(bus, new_state != State.PLAYING)
	var music_bus := AudioServer.get_bus_index(&"Music")
	if music_bus >= 0:
		AudioServer.set_bus_mute(music_bus, new_state != State.PLAYING and new_state != State.PAUSED and new_state != State.TITLE)
	state_changed.emit(new_state, old)
