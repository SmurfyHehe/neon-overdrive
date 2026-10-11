extends SceneTree

# Graffiti test (M10, 2026-10-11): the atlas, the cells file and the
# MultiMesh helper (scripts/world/graffiti.gd).
#
# Asserts (exit code 1 on failure):
# - the atlas PNG loads at 1024 x 1024 and the cells file parses
# - 36 cells with unique ids, every rect inside the atlas, sizes in metres
#   positive, kinds and counts as the set says (12 tags, 4 stencils, 4
#   stickers, 4 posters, 4 rollers, 4 spare, 4 wide pieces)
# - the paint list in the cells file is exactly the helper's palette, and
#   nothing in it is a bright magenta/cyan/neon
# - plan(seed) is a pure function of the seed: same seed, same items; another
#   seed differs; every item is on the wall, never a spare cell, and its tint
#   is a palette entry
# - tints: only palette names are accepted; "magenta" and "cyan" are not
# - nodes: create() adds one MultiMeshInstance3D sharing one material across
#   roots; place() clamps to capacity and keeps a bad tint on the palette;
#   Graffiti.enabled = false leaves the root empty
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/graffiti.gd

const G := preload("res://scripts/world/graffiti.gd")
const KINDS := {"tag": 12, "stencil": 4, "sticker": 4, "poster": 4, "roller": 4, "spare": 4, "piece": 4}

var failures: Array[String] = []

func _initialize() -> void:
	_run()
	print("graffiti: ", "PASS" if failures.is_empty() else "FAIL")
	for f in failures:
		print("  FAIL ", f)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	# ---------- atlas and cells ----------
	var tex := load(G.ATLAS_PATH) as Texture2D
	_check(tex != null, "the atlas loads")
	if tex != null:
		_check(tex.get_width() == 1024 and tex.get_height() == 1024, "the atlas is 1024 x 1024, got %d x %d" % [tex.get_width(), tex.get_height()])
	var cells: Array = G.cells()
	_check(cells.size() == 36, "36 cells, got %d" % cells.size())
	var ids := {}
	var counts := {}
	for c in cells:
		ids[c.id] = true
		counts[c.kind] = int(counts.get(c.kind, 0)) + 1
		var r: Array = c.rect
		_check(r[0] >= 0 and r[1] >= 0 and r[0] + r[2] <= 1024 and r[1] + r[3] <= 1024 and r[2] > 0 and r[3] > 0, "cell %s is inside the atlas" % c.id)
		_check(float(c.metres[0]) > 0.0 and float(c.metres[1]) > 0.0, "cell %s has a size in metres" % c.id)
		_check(KINDS.has(c.kind), "cell %s has a known kind (%s)" % [c.id, c.kind])
	_check(ids.size() == cells.size(), "cell ids are unique")
	for k in KINDS:
		_check(int(counts.get(k, 0)) == KINDS[k], "%d %s cells, got %d" % [KINDS[k], k, int(counts.get(k, 0))])
	_check(G.cell_index("tag_kemr") >= 0 and G.cell_index("stencil_dunmore") >= 0 and G.cell_index("piece_pike_speed") >= 0, "the named cells exist")
	_check(G.cell_index("nope") == -1 and G.cell_index(99) == -1, "unknown cells are -1")
	# the wide pieces are 4x the small cells
	for c in cells:
		if c.kind == "piece":
			_check(int(c.rect[2]) == 512 and int(c.rect[3]) == 128, "piece %s is 512 x 128" % c.id)
	# ---------- palette ----------
	var f := FileAccess.open(G.CELLS_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var file_pal: Array = data.get("palette", [])
	var pal := G.PALETTE_NAMES.duplicate()
	pal.sort()
	_check(file_pal == pal, "the cells file's paint list is the helper's palette, got %s" % [file_pal])
	for name in G.PALETTE_NAMES:
		var col: Color = G.PALETTE[name]
		var neon := col.h > 150.0 / 360.0 and col.h < 330.0 / 360.0 and col.s > 0.5 and col.v > 0.5
		_check(not neon, "palette %s is not magenta/cyan/neon" % name)
	# ---------- placement ----------
	var a: Array = G.plan(7, 20.0, 4.0, 12)
	var b: Array = G.plan(7, 20.0, 4.0, 12)
	var c2: Array = G.plan(8, 20.0, 4.0, 12)
	_check(a.size() == 12, "plan gives the asked count, got %d" % a.size())
	_check(_same(a, b), "plan is the same for the same seed")
	_check(not _same(a, c2), "plan differs for another seed")
	for it in a:
		var cell: Dictionary = G.cell(it.cell)
		var w: float = cell.metres[0]
		var h: float = cell.metres[1]
		var o: Vector3 = it.xf.origin
		_check(cell.kind != "spare", "plan never places a spare cell")
		_check(o.x - w * 0.5 >= -0.01 and o.x + w * 0.5 <= 20.01, "plan keeps %s along the wall (x %.2f)" % [cell.id, o.x])
		_check(o.y - h * 0.5 >= 0.0 and o.y + h * 0.5 <= 4.01, "plan keeps %s on the wall (y %.2f)" % [cell.id, o.y])
		_check(G.tint_index(it.tint) >= 0, "plan tints %s from the palette" % cell.id)
		_check(float(it.fade) > 0.5 and float(it.fade) <= 1.0, "plan fade is 0.55..1")
	var only_tags: Array = G.plan(3, 20.0, 4.0, 8, ["tag"])
	for it in only_tags:
		_check(G.cell(it.cell).kind == "tag", "plan honours the kinds filter")
	_check(G.plan(3, 20.0, 4.0, 4, ["spare"]).is_empty(), "plan with only spare kinds gives nothing")
	# ---------- tints ----------
	_check(G.tint_index("amber") >= 0 and G.tint_index("white") == 0, "palette names index")
	_check(G.tint_index("magenta") == -1 and G.tint_index("cyan") == -1 and G.tint_index("neon") == -1, "off-palette tints are refused")
	_check(G.tint_index(G.PALETTE_NAMES.size()) == -1, "tint index past the palette is refused")
	# ---------- nodes ----------
	var r1 := Node3D.new()
	var r2 := Node3D.new()
	root.add_child(r1)
	root.add_child(r2)
	var mmi := G.create(r1, 4)
	G.create(r2, 2)
	_check(mmi != null and mmi.get_parent() == r1 and mmi.name == "Graffiti", "create adds the Graffiti node")
	_check(mmi.multimesh.instance_count == 4 and mmi.multimesh.use_custom_data, "capacity and custom data")
	_check(mmi.material_override == (r2.get_node(^"Graffiti") as MultiMeshInstance3D).material_override, "one shared material across roots")
	_check((mmi.material_override as ShaderMaterial).get_shader_parameter("atlas") is Texture2D, "the material holds the atlas")
	var n := G.place(r1, G.plan(1, 10.0, 3.0, 6))
	_check(n == 4 and mmi.multimesh.visible_instance_count == 4, "place clamps to capacity, got %d" % n)
	var items := [{"xf": Transform3D.IDENTITY, "cell": "tag_kemr", "fade": 1.0, "tint": "magenta"}]
	_check(G.place(r1, items) == 1, "a bad tint still places (untinted)")
	_check(G.place(r1, []) == 0 and mmi.multimesh.visible_instance_count == 0, "place with nothing empties the root")
	G.enabled = false
	_check(G.place(r1, G.plan(1, 10.0, 3.0, 2)) == 0 and mmi.multimesh.visible_instance_count == 0, "Graffiti.enabled = false leaves the root empty")
	G.enabled = true
	_check(G.place(r1, G.plan(1, 10.0, 3.0, 2)) == 2, "and back on it places again")
	# wind
	G.set_wind(2.5)
	_check(is_equal_approx(G.wind(), 2.0), "wind clamps to 0..2")
	_check(is_equal_approx(float((mmi.material_override as ShaderMaterial).get_shader_parameter("wind")), 2.0), "wind reaches the shader")
	G.set_wind(0.6)
	r1.free()
	r2.free()

func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i].cell != b[i].cell or not a[i].xf.is_equal_approx(b[i].xf) or not is_equal_approx(a[i].fade, b[i].fade):
			return false
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
