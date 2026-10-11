extends SceneTree

# Work board W4 (2026-10-11): lint for data/work_orders.json.
# - unique ids; every field present (WorkOrders.validate)
# - giver is one of the cast or crew:<key>; kind is bench or scrap
# - 1-6 steps (scrap 2-4); zone 0.08-0.30, speed 0.8-1.6, one of the four styles
# - 0.10 <= pay.min <= pay.max <= 0.45
# - every line is <= 90 characters and names no key
# - weight 1-5; the car and any donor car exist; a scrap order has a donor
#   whose wanted car is not also a decoy
# - the three Walt regulars the board falls back on are there
#   <godot> --headless --path . -s res://tests/core/work_orders_data.gd

const WorkOrders := preload("res://scripts/core/work_orders.gd")
const NpcCarBuilder := preload("res://scripts/traffic/npc_car_builder.gd")

const KEY_WORDS := ["enter", "space", "esc", "escape", "shift", "ctrl", "arrow", "press", "hold", "key", "keys"]
const LINE_MAX := 90

var failures: Array[String] = []

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WorkOrders.DATA_PATH))
	_check(parsed is Array and parsed.size() > 0, "work_orders.json is not a list")
	var seen := {}
	var car_ids: Array = NpcCarBuilder.KINDS.keys() + ["p1_coupe"]
	var scrap := 0
	for o in parsed:
		var id := str(o.get("id", "?"))
		_check(not seen.has(id), "%s: duplicate id" % id)
		seen[id] = true
		for e in WorkOrders.validate(o):
			failures.append("%s: %s" % [id, e])
		if not o.has("steps"):
			continue
		var n: int = o.steps.size()
		if o.get("kind", "") == "scrap":
			scrap += 1
			_check(n >= 2 and n <= 4, "%s: a scrap order has %d steps, expected 2-4" % [id, n])
			var d: Variant = o.get("donor", null)
			_check(d is Dictionary and d.has("want") and d.get("decoys", []).size() == 2, "%s: scrap order needs a donor with 2 decoys" % id)
			if d is Dictionary:
				_check(d.want in car_ids, "%s: donor car %s does not exist" % [id, d.want])
				for c in d.get("decoys", []):
					_check(c in car_ids and c != d.want, "%s: decoy %s is missing or the wanted car" % [id, c])
		_check(str(o.get("car", "")) in car_ids, "%s: car %s does not exist" % [id, o.get("car", "")])
		var w: float = float(o.get("weight", 0))
		_check(w >= 1.0 and w <= 5.0, "%s: weight %s outside 1-5" % [id, w])
		var lines: Dictionary = o.get("lines", {})
		for k in ["card", "start", "miss", "done"]:
			_check(lines.has(k), "%s: no lines.%s" % [id, k])
		for k in lines:
			var text := str(lines[k])
			_check(text.length() <= LINE_MAX, "%s: lines.%s is %d characters (max %d)" % [id, k, text.length(), LINE_MAX])
			for word in text.to_lower().split(" ", false):
				var bare := word.strip_edges().trim_suffix(".").trim_suffix(",").trim_suffix("!").trim_suffix("?")
				_check(not bare in KEY_WORDS, "%s: lines.%s names a key ('%s')" % [id, k, word])
		_check(str(o.get("problem", "")).length() <= LINE_MAX, "%s: problem is longer than %d" % [id, LINE_MAX])
	_check(scrap >= 1, "no scrap order in the data")
	for i in range(1, 4):
		_check(seen.has("walt_regular_%d" % i), "walt_regular_%d is missing: the board has no fill" % i)
	_check(seen.has(WorkOrders.FIRST_DAY_CARD), "%s is missing" % WorkOrders.FIRST_DAY_CARD)
	for m in failures:
		printerr("FAIL: ", m)
	print("work_orders_data: %d orders, %s" % [seen.size(), "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
