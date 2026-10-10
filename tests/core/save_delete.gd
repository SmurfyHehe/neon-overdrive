extends SceneTree

# Delete a save (2026-10-10, Roy: "need the option to delete saves").
# Works on its own save folder (user://test_saves_delete), never the real one.
#
# The store: SaveStore.delete_slot empties the slot for the game, leaves the
# other slots alone, keeps the deleted folder (with its backups) under
# deleted/, refuses during a chase and for a slot that does not exist.
# The title: LOAD > DELETE A SAVE lists only saves that hold something; a row
# asks first, in plain words (which save, what it holds), with the focus on
# No; No and Esc delete nothing; Yes deletes and the lists follow. Deleting
# the save in use loads the game again, empty, on the title.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/core/save_delete.gd

const SaveStore := preload("res://scripts/save/save_store.gd")
const AtomicJson := preload("res://scripts/save/atomic_json.gd")

const ROOT := "user://test_saves_delete"
const TIMEOUT_FRAMES := 900

var failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_TITLE", "1")
	GameState.title_seen = false
	AudioSettings.path = "user://save_delete_test.cfg"
	_wipe(ROOT)
	SaveStore.root = ROOT
	SaveStore.slot = 0
	SaveStore.chase_active = false
	_seed(1, 120, 900)
	_seed(2, 40, 1250)
	_seed(2, 55, 1250)  # a second write: slot 2 now has a .bak1 too
	_seed(3, 0, 77)
	SaveStore.select_slot(1)
	_store()
	change_scene_to_file("res://Game.tscn")
	_run.call_deferred()

func _seed(n: int, cash: int, bank: int) -> void:
	AtomicJson.write(SaveStore.file("wallet", n), {"cash": cash, "bank": bank})
	AtomicJson.write(SaveStore.file("meta", n), {"saved_at": 1791590400})

func _store() -> void:
	_check(not SaveStore.summary(2).empty and int(SaveStore.summary(2).cash) == 55, "seeded slot 2 reads back")
	_check(FileAccess.file_exists(SaveStore.file("wallet", 2) + ".bak1"), "slot 2 has a backup file")
	SaveStore.chase_active = true
	_check(not SaveStore.delete_slot(2) and not SaveStore.summary(2).empty, "a delete is refused during a chase")
	SaveStore.chase_active = false
	_check(not SaveStore.delete_slot(0) and not SaveStore.delete_slot(4), "a slot that does not exist is refused")
	_check(SaveStore.delete_slot(3), "delete_slot(3)")
	_check(SaveStore.summary(3).empty, "slot 3 is empty after the delete")
	_check(not DirAccess.dir_exists_absolute(SaveStore.slot_dir(3)), "slot 3's folder is gone from the saves")
	_check(not SaveStore.summary(1).empty and not SaveStore.summary(2).empty, "the other slots are untouched")
	var kept := DirAccess.get_directories_at(ROOT.path_join("deleted"))
	_check(kept.size() == 1 and FileAccess.file_exists(ROOT.path_join("deleted").path_join(kept[0]).path_join("wallet.json")),
		"the deleted save is kept under deleted/")
	_check(SaveStore.delete_slot(3), "deleting an empty slot is fine")
	_check(SaveStore.active_slot() == 1, "the slot in use did not change")

func _run() -> void:
	var first := await _wait_game(null)
	if first == null:
		return _finish("Game.tscn never became ready")
	var title: TitleScreen = _node(first, "TitleScreen")
	title.load_button.pressed.emit()
	await _frames(2)
	_check(title.load_list.visible and title.delete_button != null and not title.delete_button.disabled, "LOAD has a DELETE A SAVE row")
	title.delete_button.pressed.emit()
	await _frames(2)
	var rows := _rows(title.delete_list)
	print("save_delete: rows: ", rows.map(func(b: Button) -> String: return b.text))
	_check(title.delete_list.visible and rows.size() == 3, "the delete list has saves 1 and 2 and BACK (%d rows)" % rows.size())
	_check(rows.size() == 3 and rows[1].text.begins_with("DELETE SAVE 2") and rows[1].text.contains("$55"), "the row names the save and what it holds")

	# No, then Esc: nothing is deleted.
	rows[1].pressed.emit()
	await _frames(2)
	print("save_delete: question: ", title.confirm.question.text, " [", title.confirm.yes_button.text, " / ", title.confirm.no_button.text, "]")
	_check(title.confirm.is_open() and title.confirm.no_button.has_focus(), "the row asks first, with No focused")
	_check(title.confirm.question.text.contains("save 2") and title.confirm.question.text.contains("$55"), "the question says which save and what it holds")
	_key(KEY_ENTER, true)
	await _frames(3)
	_key(KEY_ENTER, false)
	await _frames(3)
	_check(not title.confirm.is_open() and not SaveStore.summary(2).empty, "Enter on the question (No) deletes nothing")
	rows[1].pressed.emit()
	await _frames(2)
	_key(KEY_ESCAPE, true)
	await _frames(3)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(not title.confirm.is_open() and not SaveStore.summary(2).empty, "Esc on the question deletes nothing")

	# Yes: slot 2 goes, slot 1 stays, the list follows.
	rows[1].pressed.emit()
	await _frames(2)
	title.confirm.yes_button.pressed.emit()
	await _frames(3)
	_check(SaveStore.summary(2).empty and not SaveStore.summary(1).empty, "Yes deletes save 2 and only save 2")
	rows = _rows(title.delete_list)
	_check(title.delete_list.visible and rows.size() == 2 and rows[0].text.begins_with("DELETE SAVE 1"), "the list now has save 1 and BACK")
	_check(DirAccess.get_directories_at(ROOT.path_join("deleted")).size() == 2, "save 2 is kept under deleted/")

	# The save in use: the question says so, and the game loads again, empty.
	rows[0].pressed.emit()
	await _frames(2)
	_check(title.confirm.question.text.contains("in use"), "deleting the save in use says so")
	title.confirm.yes_button.pressed.emit()
	var second := await _wait_game(first)
	if second == null:
		return _finish("the game did not load again after deleting the save in use")
	await _frames(4)
	var title2: TitleScreen = _node(second, "TitleScreen")
	_check(second.game_state.state == GameState.State.TITLE and title2.visible, "back on the title")
	_check(SaveStore.summary(1).empty, "save 1 is empty (nothing wrote it back)")
	_check(int(second.wallet.cash) == 0 and int(second.wallet.bank) == 0, "the new game has no money from the deleted save")
	_check(title2.drive_button.disabled and not title2.new_game_button.disabled, "CONTINUE is greyed, NEW GAME is not")
	title2.load_button.pressed.emit()
	await _frames(2)
	_check(title2.delete_button.disabled, "DELETE A SAVE is greyed with nothing saved")
	_finish("")

func _rows(list: VBoxContainer) -> Array:
	var out: Array = []
	for c in list.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_game(not_this: Node) -> Node:
	for i in TIMEOUT_FRAMES:
		var game := current_scene
		if game != null and is_instance_valid(game) and game != not_this and game.get("game_state") != null \
				and _node(game, "PauseMenu") != null and _node(game, "TitleScreen") != null:
			return game
		await physics_frame
	return null

func _node(game: Node, cls: String) -> Node:
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

## Removes this test's own folder (never the real saves: ROOT is fixed above).
func _wipe(dir: String) -> void:
	if not dir.begins_with(ROOT) or not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

func _finish(abort: String) -> void:
	if abort != "":
		failures.append(abort)
	_wipe(ROOT)
	DirAccess.remove_absolute(AudioSettings.path)
	for f in failures:
		printerr("FAIL: ", f)
	print("save_delete: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
