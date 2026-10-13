extends SceneTree

# Damaged, cut-short and missing save files (stress layer D, 2026-10-13).
# The kills in tests/save/save_chaos.py leave only what the game itself
# writes; this breaks the files by hand, the way a disk, an antivirus or a
# hand edit can. A slot is built with a few commits (a part bought, a dawn
# banked, a shop pay, tonight's cash), then ONE file is damaged one way, and
# everything the game reads at boot runs on it: the title's slot plates, the
# director's run read, the wallet, the garage, the clock, the car's state.
# Checks, for every file x damage:
# - nothing stops the boot, and the slot either loads or is cleanly empty
# - money is never more than the slot really had (bank + cash <= the newest
#   total), and the bank is the newest or the commit before it
# - a broken meta.json or night.json never touches the career (bank, parts,
#   nights closed exactly the newest)
# - a broken career.json falls back one commit (its .bak1), never to nothing
# - a version 1 save whose upgrade was killed while writing career.json.tmp is
#   upgraded again on the next load, not loaded as an empty slot
# - the next commit writes whole files again and keeps the broken copy aside
#   as .bad; a save from a newer build stays byte-identical and is not loaded
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/save/save_damage.gd

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const GarageMods := preload("res://scripts/car/garage_mods.gd")

const ROOT := "user://test_save_damage"
const FILES := ["career", "night", "meta", "active_slot"]
const DAMAGES := ["cut_in_header", "cut_mid", "cut_last_byte", "flipped_byte", "garbage", "empty",
	"main_missing", "all_copies_missing", "bad_money_values", "newer_version", "torn_tmp_beside", "only_tmp"]
## What the slot holds after _build (the newest), and the career one commit before.
const BANK := 1500
const BANK_BEFORE := 1300
const CASH := 520
const PART := "p1_coupe/service"

var failures: Array[String] = []
var cases := 0

class Bank:
	var bank := 0
	func spend_bank(_n: int) -> bool:
		return false

func _initialize() -> void:
	SaveDirector.enabled = true
	SaveCore.persist = true
	var n := 0
	for f in FILES:
		for d in DAMAGES:
			n += 1
			_case(n, f, d)
	_v1_torn_career_tmp()
	print("save_damage: %d cases, %d failures" % [cases, failures.size()])
	for f in failures:
		print("FAIL ", f)
	quit(1 if failures.size() > 0 else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _path(file: String) -> String:
	return SaveCore.root.path_join("active_slot.json") if file == "active_slot" else SaveCore.file(file, 1)

## A slot with history: every file has backups, the career has a .bak1 one commit older.
func _build(name: String) -> void:
	SaveCore.root = ROOT.path_join(name)
	SaveCore.slot = 0
	SaveCore.chase_active = false
	SaveCore.select_slot(1)
	SaveCore.select_slot(1)   # active_slot.json gets a backup too
	SaveCore.commit("buy", {"bank": 1000, "current_car": "p1_coupe"}, func(c: Dictionary) -> void:
		SaveCore.car_entry(c, "p1_coupe").parts_owned = [PART])
	SaveCore.write_night(_run(300))
	SaveCore.commit("dawn", {"close_night": 1})                 # bank 1300, night 2
	SaveCore.write_night(_run(450))
	SaveCore.commit("wallet", {"bank": BANK, "cash": 450})      # a shop pay of 200
	SaveCore.write_night(_run(CASH))

func _run(cash: int) -> Dictionary:
	return {"road": {"seed": 7, "curviness": 0.5, "hilliness": 0.5, "kicker_chance": 0.0, "id": 0, "s": 100.0, "dir": 1, "act": 1},
		"origin_index": 3, "car": {"xform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, 0], "lin_vel": [0, 0, -20], "ang_vel": [0, 0, 0], "gear": 3, "rpm": 4200},
		"cash": cash, "car_live": {"car": "p1_coupe", "fuel": {"litres": 20.0}}}

func _damage(p: String, how: String) -> void:
	var g := ProjectSettings.globalize_path(p)
	var bytes := FileAccess.get_file_as_bytes(p)
	var nl := bytes.find(10)
	match how:
		"cut_in_header":
			_put(g, bytes.slice(0, nl - 5))
		"cut_mid":
			_put(g, bytes.slice(0, bytes.size() / 2))
		"cut_last_byte":
			_put(g, bytes.slice(0, bytes.size() - 1))
		"flipped_byte":
			var b := bytes.duplicate()
			var i := nl + 1 + (b.size() - nl - 1) / 3
			b[i] = b[i] ^ 0x20
			_put(g, b)
		"garbage":
			var b := PackedByteArray()
			for i in 300:
				b.append((i * 73 + 41) % 256)
			_put(g, b)
		"empty":
			_put(g, PackedByteArray())
		"main_missing":
			DirAccess.remove_absolute(g)
		"all_copies_missing":
			for c in AtomicJson.candidates(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(c))
		"bad_money_values":
			# A whole file with a good checksum but nonsense in it (a bad hand edit).
			var d: Dictionary = AtomicJson.decode(bytes.get_string_from_utf8())
			if d.has("wallet"):
				d.wallet.bank = "lots"
			d["cash"] = -5
			d["chase_open"] = "maybe"
			d["slot"] = 9
			d["plate"] = 3
			_put(g, AtomicJson.encode(d).to_utf8_buffer())
		"newer_version":
			var d: Dictionary = AtomicJson.decode(bytes.get_string_from_utf8())
			d.save_version = 99
			_put(g, AtomicJson.encode(d).to_utf8_buffer())
		"torn_tmp_beside":
			_put(g + ".tmp", bytes.slice(0, bytes.size() / 3))
		"only_tmp":
			# Killed between "main to .bak1" and ".tmp to main" (atomic_json.gd step 3).
			DirAccess.rename_absolute(g, g + ".tmp")

static func _put(g: String, b: PackedByteArray) -> void:
	var f := FileAccess.open(g, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()

static func _slot_bytes() -> Dictionary:
	var out := {}
	var d := ProjectSettings.globalize_path(SaveCore.slot_dir(1))
	for f in DirAccess.get_files_at(d):
		out[f] = FileAccess.get_file_as_bytes(d.path_join(f))
	return out

func _case(n: int, file: String, how: String) -> void:
	cases += 1
	var tag := "%s/%s" % [file, how]
	_build("c%02d" % n)
	var total := SaveCore.bank() + SaveCore.cash()
	_check(SaveCore.bank() == BANK and SaveCore.cash() == CASH, "%s: the slot was not built (bank %d cash %d)" % [tag, SaveCore.bank(), SaveCore.cash()])
	_damage(_path(file), how)
	var before := _slot_bytes()
	# A relaunch: what the game reads at boot, in its order.
	SaveCore.forget()
	SaveCore.slot = 0
	SaveCore.chase_active = false
	for s in range(1, SaveCore.SLOTS + 1):
		SaveCore.summary(s)   # the title's plates
	var run := SaveDirector.new(null).read_run()
	var w := Wallet.new()
	var bank: int = w.bank
	var cash: int = w.cash
	w.free()
	var mods := GarageMods.new()
	var b := Bank.new()
	mods.open("p1_coupe", b)
	SaveCore.clock()
	SaveCore.car_state("p1_coupe")
	var career := SaveCore.career()
	var parts: Array = SaveStore.load_garage().owned_parts
	var closed := SaveCore._int(SaveCore._block(career, "story").get("night_closed"))
	_check(SaveCore.active_slot() == 1, "%s: the active slot is %d" % [tag, SaveCore.active_slot()])
	_check(bank + cash <= total, "%s: money grew from %d to %d (bank %d, cash %d)" % [tag, total, bank + cash, bank, cash])
	_check(bank >= 0 and cash >= 0, "%s: negative money (bank %d, cash %d)" % [tag, bank, cash])
	if how == "newer_version":
		if file != "active_slot":
			_check(SaveCore.locked(1) and SaveCore.summary(1).empty, "%s: a save from a newer build was loaded" % tag)
			_check(not SaveCore.commit("quit"), "%s: a save from a newer build was written to" % tag)
			_check(_slot_bytes() == before, "%s: a save from a newer build was changed" % tag)
			return
	match file:
		"career":
			if how in ["torn_tmp_beside", "only_tmp"]:
				_check(bank == BANK and parts.has(PART) and closed == 1, "%s: career not the newest (bank %d, parts %s, closed %d)" % [tag, bank, parts, closed])
			elif how == "all_copies_missing":
				_check(bank == 0 and cash == CASH, "%s: a career with no copy left: bank %d cash %d" % [tag, bank, cash])
			elif how == "bad_money_values":
				_check(bank == BANK_BEFORE and parts.has(PART) and closed == 1, "%s: a bad bank value should come from the commit before (bank %d)" % [tag, bank])
			else:
				_check(bank == BANK_BEFORE and parts.has(PART) and closed == 1, "%s: a broken career should fall back one commit (bank %d, parts %s, closed %d)" % [tag, bank, parts, closed])
			_check(SaveCore.career_damaged(1) == (how not in ["torn_tmp_beside", "only_tmp", "main_missing", "all_copies_missing", "bad_money_values"]), "%s: career_damaged says %s" % [tag, SaveCore.career_damaged(1)])
		"night":
			_check(bank == BANK and parts.has(PART) and closed == 1, "%s: a broken night touched the career (bank %d, parts %s, closed %d)" % [tag, bank, parts, closed])
			var want := [CASH] if how in ["torn_tmp_beside", "only_tmp"] else ([450, 0] if how == "bad_money_values" else [450, 0, CASH])
			_check(cash in want, "%s: tonight's cash %d, expected one of %s" % [tag, cash, want])
			if how in ["torn_tmp_beside", "only_tmp"]:
				_check(not run.is_empty(), "%s: the run was not resumed" % tag)
		_:
			_check(bank == BANK and cash == CASH and parts.has(PART) and closed == 1, "%s: a broken %s changed the slot (bank %d, cash %d, parts %s, closed %d)" % [tag, file, bank, cash, parts, closed])
			_check(not run.is_empty(), "%s: the run was not resumed" % tag)
	# The game goes on: the next commit writes every file whole again.
	_check(SaveCore.commit("quit"), "%s: the next commit failed" % tag)
	for f in ["career", "night", "meta"]:
		_check(AtomicJson.decode(FileAccess.get_file_as_string(SaveCore.file(f, 1))) != null, "%s: %s.json is not whole after the next commit" % [tag, f])
	if how in ["cut_in_header", "cut_mid", "cut_last_byte", "flipped_byte", "garbage", "empty"] and file != "active_slot":
		_check(FileAccess.file_exists(_path(file) + ".bad"), "%s: the broken copy was not kept aside as .bad" % tag)
	_check(SaveCore.bank() + SaveCore.cash() <= total, "%s: money grew after the next commit (%d)" % [tag, SaveCore.bank() + SaveCore.cash()])

## The upgrade from version 1 killed while writing career.json.tmp (found by
## save_chaos.py upgrade mode): the torn .tmp made the slot count as upgraded
## and it loaded empty. It must upgrade again from the untouched old files.
func _v1_torn_career_tmp() -> void:
	cases += 1
	var fx := "res://tests/save/fixtures/v1"
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fx.path_join("expect.json")))
	SaveCore.root = ROOT.path_join("v1_torn/saves")
	SaveCore.legacy_dir = ROOT.path_join("v1_torn/global")
	_copy(fx.path_join("saves"), SaveCore.root)
	_copy(fx.path_join("global"), SaveCore.legacy_dir)
	_put(ProjectSettings.globalize_path(SaveCore.file("career", 1) + ".tmp"), "NEONSAVE1 0123\n{\"gen\": 1, \"wal".to_utf8_buffer())
	SaveCore.slot = 0
	SaveCore.chase_active = false
	SaveCore.forget()
	SaveCore.summary(1)
	_check(SaveCore.bank(1) == int(want.bank) and SaveCore.cash(1) == int(want.cash),
		"v1 + torn career.json.tmp: bank %d cash %d, expected %d and %d" % [SaveCore.bank(1), SaveCore.cash(1), want.bank, want.cash])
	SaveCore.legacy_dir = ""

static func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for d in DirAccess.get_directories_at(from):
		_copy(from.path_join(d), to.path_join(d))
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(from.path_join(f)), ProjectSettings.globalize_path(to.path_join(f)))
