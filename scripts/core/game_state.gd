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
# WRECKED (ending a run, 2026-10-10): a hard hit ended the run and the crash
# screen is playing (scripts/core/run_end.gd). The tree is NOT paused, so the
# car, the camera shake and the sounds carry on in real time; no menu opens
# from it, and it only ends in a restart.
# STATION: stopped at a gas station pump (scripts/world/gas_station.gd); paused
# while the pump menu (scripts/ui/pump_panel.gd) is up, Esc drives off.
# WASH (2026-10-09): the garage wash mini-game (scripts/wash_screen.gd), opened
# from the garage; paused like the rest, Esc leaves it.
# DAWN and GARAGE (garage G0, 2026-10-11): the dawn card after a night (or at
# boot) and the garage behind it. Both are paused, neither is ever auto-paused
# (a slow frame in the garage never opens the pause screen) and Esc does nothing
# in them: "Go out" is the way back to the road (scripts/ui/garage_screen.gd).
# WORKBOARD (work board W2, 2026-10-11): Walt's board, between the dawn card
# and the garage. Paused, never auto-paused, Esc does nothing (like DAWN and
# GARAGE); it reports as the garage (in_garage) for the frame cap and the rest.
enum State { PLAYING, PAUSED, TUNING, AUTOTUNE, PHOTO, TITLE, WRECKED, STATION, WASH, DAWN, GARAGE, WORKBOARD }

const SaveStore := preload("res://scripts/save/save_store.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")

signal state_changed(new_state: State, old_state: State)
## The garage is about to take over, before the state changes, so the world is
## still on screen: the save and the Polaroid happen on this. `entry` is one of
## the ENTRY_ names below. Not sent again for dawn card -> garage.
signal garage_entering(entry: String)
## "Go out" was pressed: the car waits outside with the engine off (GarageFlow).
signal garage_left
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
const REASON_STALL := "Your PC fell behind, so the game paused. Lower the look to keep it smooth."
const REASON_FOCUS := "The game paused because the window lost focus."
var pause_notice := ""

## Garage entries (G0): how the player got there.
const ENTRY_BOOT := "boot"            # first drive of a session, after the title
const ENTRY_DAWN := "dawn"            # 6 a.m.: the night ended
const ENTRY_FORECOURT := "forecourt"  # pulled in at the garage mid-night

## Garage plumbing is live only in a real play session (like the title), or when
## a test or shell run sets NEON_GARAGE=1 (NEON_GARAGE=0 turns it off). Game
## copies wants_garage() into garage_enabled; tests set it by hand.
var garage_enabled := false
## How the player got to the garage this time (an ENTRY_ name, "" before).
var garage_entry := ""
## The night that just ended (the dawn card reads it); 0 at boot.
var dawn_night := 0
## 6 a.m. came while a cop had eyes on the player or a race was on: the dawn
## card waits until that is over.
var dawn_pending := false
## Set once the player has gone out of the garage for the first time this
## session; a static like title_seen, so Restart (instant retry) skips it.
static var garage_seen := false
var _wash_from_garage := false
var _garage_boot_at := -1

static func wants_garage() -> bool:
	var env := OS.get_environment("NEON_GARAGE")
	if env == "0":
		return false
	return env == "1" or DisplaySettings.player_run()

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

## True while a race is live (race_controller.gd). A race is not its own State:
## the game stays PLAYING so pause and photo mode work as usual; only the Tuner
## is shut, so a tune cannot change mid-race.
## Mirrors into in_race above, which the pause screen reads for its "Quit race" row.
var race_active := false:
	set(value):
		race_active = value
		in_race = value

## Special vehicles (S0): kind -> true once unlocked (the story ending sets it;
## both start waiting in the garage). Saved in the slot's special.json.
## Test mode (--test-mode / TestMode.active()) counts every special as unlocked.
var special_unlocked: Dictionary = {}
signal special_unlocked_changed

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

## Opens the pause screen when a frame freezes for STALL_SECS on the wall clock
## (Roy 160). A frame rate that is only low no longer pauses: PerfLadder
## lowers the load step by step instead. Off in headless runs and tests.
var auto_pause_on_low_fps := true
var _fps_watch := LowFpsWatch.new()
var _last_frame_usec := 0

func _ready() -> void:
	PhotoMode.ensure_actions()
	SpecialKeys.ensure_actions()
	special_unlocked = SaveStore.load_special().unlocked
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Not in test mode either: windowed tests and shot tools on a busy machine
	# were being paused mid-run (the stall guard next to it is play-only too).
	auto_pause_on_low_fps = auto_pause_on_low_fps and DisplayServer.get_name() != "headless" and not TestMode.active() and not Benchmark.requested()
	_fps_watch.slow_pauses = false
	_fps_watch.freeze_seconds = STALL_SECS
	state_changed.connect(func(_n, _o): _fps_watch.reset())

## Low fps watch (#309): sustained slow frames on the wall clock, which is
## unaffected by time scale and by get_tree().paused. Called from _process.
func _watch_low_fps() -> void:
	var now := Time.get_ticks_usec()
	var frame_seconds := (now - _last_frame_usec) / 1000000.0 if _last_frame_usec > 0 else 0.0
	_last_frame_usec = now
	feed_frame(frame_seconds)

## One frame's real duration into the low-fps watch. Only while PLAYING: the
## dawn card and the garage (and every other screen) never pause themselves.
func feed_frame(frame_seconds: float) -> void:
	if not auto_pause_on_low_fps or state != State.PLAYING:
		return
	if _fps_watch.feed(frame_seconds):
		pause(REASON_STALL)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and state == State.PLAYING:
		pause(REASON_FOCUS)

## Stall guard: a frame the real clock says took too long while the game runs.
## It stands down for STALL_GRACE seconds after play starts or resumes: the
## first frames after a scene load or an unpause are always slow.
const STALL_GRACE := 2.0
var _grace := STALL_GRACE

func _process(delta: float) -> void:
	_watch_low_fps()
	if stall_secs <= 0.0 or state != State.PLAYING:
		return
	if _grace > 0.0:
		_grace -= delta
	elif delta >= stall_secs:
		pause(REASON_STALL)

## True while a chase is open: the pause key is refused.
static func chase_locked() -> bool:
	return SaveStore.chase_active

func is_special_unlocked(kind: String) -> bool:
	return TestMode.active() or special_unlocked.get(kind, false) == true

## Unlocks one special vehicle (or every one, with ""), and saves it.
func unlock_special(kind: String = "") -> void:
	for k in PlayerCars.SPECIAL_DATA:
		if kind == "" or kind == k:
			special_unlocked[k] = true
	SaveStore.save_special(special_unlocked)
	special_unlocked_changed.emit()

## The cars the garage and free roam list right now.
func garage_cars() -> Array[String]:
	var all := {}
	for k in PlayerCars.SPECIAL_DATA:
		all[k] = is_special_unlocked(k)
	return PlayerCars.garage_ids(all)

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
	if _garage_boot_at >= 0 and Engine.get_physics_frames() >= _garage_boot_at:
		_garage_boot_at = -1
		if state == State.PLAYING:
			_enter_dawn(ENTRY_BOOT)
	if dawn_pending and state == State.PLAYING and not chase_locked() and not race_active:
		dawn_pending = false
		_enter_dawn(ENTRY_DAWN)
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

## Garage wash: from the garage (Esc or a clean car goes back to it), or from
## the pause menu / straight from the road (tests, the old stand-in).
func open_wash() -> void:
	if state == State.PAUSED or state == State.PLAYING or state == State.GARAGE:
		_wash_from_garage = state == State.GARAGE
		get_tree().paused = true
		_set_state(State.WASH)

func close_wash() -> void:
	if state != State.WASH:
		return
	if _wash_from_garage:
		_wash_from_garage = false
		_set_state(State.GARAGE)   # still paused, still in the garage
		return
	get_tree().paused = false
	_set_state(State.PLAYING)

# ---------- dawn card and garage (G0) ----------

## 6 a.m. (Game wires night_clock.night_ended here). The dawn card opens at once,
## or waits while a cop sees the player or a race is on. Does nothing when the
## garage is off (tests, the benchmark).
func request_dawn(night_ended: int) -> void:
	if not garage_enabled:
		return
	dawn_night = night_ended
	if state == State.PLAYING and not chase_locked() and not race_active:
		_enter_dawn(ENTRY_DAWN)
	else:
		dawn_pending = true

## First drive of a session in a no-title boot: the dawn card opens after the
## car has settled on its springs, like the title freeze.
func enter_garage_boot() -> void:
	if not garage_enabled or garage_seen or state != State.PLAYING:
		return
	_garage_boot_at = Engine.get_physics_frames() + TITLE_SETTLE_TICKS

func _enter_dawn(entry: String) -> void:
	garage_entry = entry
	if entry != ENTRY_DAWN:
		dawn_night = 0   # (request_dawn sets it for a real dawn)
	# From the title the world is hidden behind it: nothing to photograph.
	if state == State.PLAYING:
		garage_entering.emit(entry)
	get_tree().paused = true
	_set_state(State.DAWN)

## The dawn card is dismissed: on into the garage (no second entering signal).
func dawn_continue() -> void:
	if state == State.DAWN:
		# A real dawn goes through Walt's board first, when the shop is on and
		# today is not settled (workboard_gate is set by Game; unset = no board).
		if garage_entry == ENTRY_DAWN and workboard_gate.is_valid() and workboard_gate.call(dawn_night):
			_set_state(State.WORKBOARD)
		else:
			_set_state(State.GARAGE)

## Asked on the dawn card's Continue: should the work board open? Takes the
## night that just ended, returns a bool. Set by Game (ShopDay.want_board).
var workboard_gate: Callable = Callable()

## The garage's "Walt's board" row: back onto the board.
func open_workboard() -> void:
	if state == State.GARAGE:
		_set_state(State.WORKBOARD)

## The board is done (Head out, or the garage tag): on into the garage.
func close_workboard() -> void:
	if state == State.WORKBOARD:
		_set_state(State.GARAGE)

## A mid-night visit: the car is stopped at the garage forecourt. Refused while
## a cop has eyes on the player (the same toast as the pause key), in a race, or
## with the garage off. True when the garage opened.
func open_garage(entry: String = ENTRY_FORECOURT) -> bool:
	if state != State.PLAYING or not garage_enabled:
		return false
	if chase_locked():
		pause_refused.emit()
		return false
	if race_active:
		return false
	garage_entry = entry
	dawn_night = 0
	garage_entering.emit(entry)
	get_tree().paused = true
	_set_state(State.GARAGE)
	return true

## True on the dawn card, in the garage, and in the wash opened from it.
func in_garage() -> bool:
	return state == State.DAWN or state == State.GARAGE or state == State.WORKBOARD \
			or (state == State.WASH and _wash_from_garage)

## "Go out": back to the road, the car parked outside with the engine off.
func leave_garage() -> void:
	if state != State.GARAGE:
		return
	garage_seen = true
	get_tree().paused = false
	_set_state(State.PLAYING)
	garage_left.emit()

func toggle_pause() -> void:
	if state == State.WASH:
		close_wash()  # Esc leaves the wash
	elif state == State.DAWN or state == State.GARAGE or state == State.WORKBOARD:
		pass          # no pause screen here: Continue and Go out are the way on
	elif state == State.TUNING:
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
	elif state == State.PLAYING and not race_active:  # no tuning mid-race
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
	elif state == State.PLAYING and not race_active:
		get_tree().paused = true
		_set_state(State.AUTOTUNE)

func close_autotune() -> void:
	if state == State.AUTOTUNE:
		get_tree().paused = false
		_set_state(State.PLAYING)

## A hard hit ended the run. True when the state changed (false from a menu).
func wreck() -> bool:
	if state != State.PLAYING:
		return false
	_set_state(State.WRECKED)
	return true

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
	garage_seen = false   # coming back from the title means the garage again
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
	if garage_enabled and not garage_seen:
		_enter_dawn(ENTRY_BOOT)   # dawn card, then the garage; stays paused
		return
	get_tree().paused = false
	_set_state(State.PLAYING)

func _set_state(new_state: State) -> void:
	var old := state
	state = new_state
	if new_state == State.PLAYING:
		_grace = STALL_GRACE
	# The engine sound is a generator pushed from _process, which stops while the
	# tree is paused; the buffer then underruns and clicks. Mute its bus for the
	# pause, unmute on the way back (Phase A, 2026-10-05). A wreck does not
	# pause, so nothing is muted for it here: run_end.gd cuts the sound itself.
	# The radio plays on, muffled, on the pause screen and the title (PauseLook);
	# only the Tuner and photo mode still mute it.
	var muted := new_state != State.PLAYING and new_state != State.WRECKED
	for bus_name in [&"Engine", &"Turbo"]:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus >= 0:
			AudioServer.set_bus_mute(bus, muted)
	var music_bus := AudioServer.get_bus_index(&"Music")
	if music_bus >= 0:
		var radio_plays := new_state == State.PAUSED or new_state == State.TITLE \
				or new_state == State.DAWN or new_state == State.GARAGE
		AudioServer.set_bus_mute(music_bus, muted and not radio_plays)
	state_changed.emit(new_state, old)
