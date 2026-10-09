class_name Wallet
extends RefCounted

# The player's banked Cred (Stage C proposal, PR #157: Cred, pot and bank in
# user://wallet.json). Minimal v1 for the garage: only the bank, which is what
# garage purchases are paid from. Stage C adds the night's pot and banking it;
# it extends this file rather than replacing it.
#
# A purchase goes through spend_bank(): it refuses (and changes nothing) when
# the bank cannot cover the price. A file that will not parse reads as an empty
# bank and is left untouched until the next save.

const DEFAULT_PATH := "user://wallet.json"
const TestMode := preload("res://scripts/test_mode.gd")

var path: String
var bank := 0

func _init(file_path := "") -> void:
	path = file_path if file_path != "" else TestMode.path(DEFAULT_PATH)
	_load_file()

func can_afford(amount: int) -> bool:
	return amount >= 0 and bank >= amount

## Takes `amount` from the bank and saves. False, with nothing taken, if the bank
## is short or the amount is negative.
func spend_bank(amount: int) -> bool:
	if not can_afford(amount):
		return false
	bank -= amount
	save()
	return true

func deposit_bank(amount: int) -> void:
	if amount > 0:
		bank += amount
		save()

func save() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Wallet: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": 1, "bank": bank}, "\t"))
	return true

func _load_file() -> void:
	bank = 0
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return
	var b: Variant = json.data.get("bank", 0)
	if (b is float or b is int) and is_finite(float(b)):
		bank = maxi(int(b), 0)
