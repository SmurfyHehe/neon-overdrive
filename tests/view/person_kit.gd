extends SceneTree

# The people pipeline's body kit (PersonKit, 2026-10-09), headless, no scene:
# - every option of every row builds, and so does every row varied one at a
#   time from the default look, each under the 1,500-triangle body budget
# - the body stands about 7 heads tall (6.6..7.4), Roy's "realistic fitted
#   to game proportions"
# - the parts are the named rigid segments the DriverModel seats, each with
#   geometry, and a standing figure assembles from them with the feet on the
#   floor and the crown at the measured height
# - a watch only comes with the watch trinket; the chain adds triangles to the
#   torso; unknown choices fall back to the defaults
# - no cyan or magenta in the tables (Amber vs Dusk; tests/core/palette.gd
#   scans the literals, this checks the resolved colours)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/person_kit.gd

const TRI_MAX := 1500
const PARTS := ["torso", "head", "upper_arm_l", "upper_arm_r", "forearm_l", "forearm_r",
	"thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]

var failures: Array[String] = []

func _initialize() -> void:
	_run()
	for f in failures:
		printerr("FAIL: ", f)
	print("person_kit: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _run() -> void:
	var base := PersonKit.build({})
	_check(base.look == PersonKit.DEFAULT_LOOK, "an empty look completes to the defaults (%s)" % [base.look])
	print("default body: %d triangles, %.2f heads tall" % [base.tris, PersonKit.heads_tall(base)])
	var heads := PersonKit.heads_tall(base)
	_check(heads >= 6.8 and heads <= 7.4, "the average body stands %.2f heads tall, want about 7" % heads)
	# the height row: short under, tall over, every one a plausible adult
	var short_m := PersonKit.standing_height(PersonKit.build({"height": "short"}))
	var tall_m := PersonKit.standing_height(PersonKit.build({"height": "tall"}))
	print("heights: short %.2f m, average %.2f m, tall %.2f m" % [short_m, PersonKit.standing_height(base), tall_m])
	_check(short_m < PersonKit.standing_height(base) - 0.08 and tall_m > PersonKit.standing_height(base) + 0.08, "the height row changes the standing height")
	_check(short_m > 1.60 and tall_m < 2.05, "heights stay adult (%.2f .. %.2f m)" % [short_m, tall_m])
	for name in PARTS:
		_check(base.parts.has(name) and (base.parts[name] as PersonKit).tri_count() >= 12, "part %s is built" % name)
	_check(not base.parts.has("watch"), "no watch without the watch trinket")
	# every option of every row, one row at a time from the default
	var worst := 0
	var worst_look := {}
	for row in PersonKit.ROWS:
		var opts := PersonKit.options(row)
		_check(opts.size() >= 3 or row == "trinket", "row %s offers several choices (%d)" % [row, opts.size()])
		for opt in opts:
			var look := {row: opt}
			var b := PersonKit.build(look)
			_check(b.look[row] == opt, "row %s accepts %s" % [row, opt])
			_check(b.tris > 0 and b.tris <= TRI_MAX, "%s=%s builds %d triangles, budget %d" % [row, opt, b.tris, TRI_MAX])
			if b.tris > worst:
				worst = b.tris
				worst_look = b.look
			for name in PARTS:
				_check(b.parts.has(name), "%s=%s: part %s is built" % [row, opt, name])
	print("heaviest single-row look: %d triangles (%s)" % [worst, worst_look])
	# the heaviest plausible combination
	var heavy := PersonKit.build({"body": "heavy", "hair": "beanie", "jacket": "bomber", "trinket": "chain"})
	print("heavy+beanie+bomber+chain: %d triangles" % heavy.tris)
	_check(heavy.tris <= TRI_MAX, "the heaviest look is %d triangles, budget %d" % [heavy.tris, TRI_MAX])
	_check(heavy.parts.torso.tri_count() > base.parts.torso.tri_count(), "the chain adds links to the torso")
	var watch := PersonKit.build({"trinket": "watch"})
	_check(watch.parts.has("watch") and watch.parts.watch.tri_count() > 0, "the watch trinket builds a watch")
	var bad := PersonKit.build({"hair": "mohawk", "jacket": 7, "skin": "green"})
	_check(bad.look == PersonKit.DEFAULT_LOOK, "unknown choices fall back to the defaults (%s)" % [bad.look])
	# the standing figure: feet on the floor, crown at the measured height
	var fig := PersonKit.standing({}, CockpitKit.material())
	var lo := INF
	var hi := -INF
	for n in fig.get_children():
		var mi := n as MeshInstance3D
		var aabb := mi.transform * mi.mesh.get_aabb()
		lo = minf(lo, aabb.position.y)
		hi = maxf(hi, aabb.end.y)
	print("standing figure: y %.3f .. %.3f" % [lo, hi])
	_check(absf(lo) < 0.005, "the standing figure's soles sit on the floor (lowest y %.3f)" % lo)
	_check(absf(hi - heads * PersonKit.HEAD_H) < 0.06, "the standing figure's top (%.3f) matches the measured height (%.3f)" % [hi, heads * PersonKit.HEAD_H])
	_check(fig.get_child_count() == PARTS.size(), "the standing figure has one node per part (%d)" % fig.get_child_count())
	# palette: no cyan, no magenta in any table colour
	var tables := [PersonKit.SKINS.values()]
	for h in PersonKit.HAIRS.values():
		tables.append([h.col])
	for j in PersonKit.JACKETS.values():
		var cols := []
		for key in ["jacket", "trim", "zip", "trousers", "hem", "shoe", "sole", "lace"]:
			cols.append(j[key])
		tables.append(cols)
	for g in PersonKit.GLOVES.values():
		if not g.is_empty():
			tables.append([g.glove, g.cuff])
	for cols in tables:
		for c in cols:
			var col := c as Color
			var cyan := col.b > 0.5 and col.g > 0.5 and col.r < col.g * 0.6
			var magenta := col.r > 0.5 and col.b > 0.5 and col.g < col.r * 0.6
			_check(not cyan and not magenta, "off-palette colour %s" % col.to_html(false))
	fig.free()
