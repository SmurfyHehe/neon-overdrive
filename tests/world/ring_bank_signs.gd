extends SceneTree

# The ring's lean and the bridge lettering (ramps doc steps 1, 3 and 4:
# notes/better-ramps-and-destinations-2026-10-13.md; Roy 1502-1504).
#
# 1. Signs, every act: one exit gantry per exit, 400 m before its gore, and
#    none at 1 km (#645). The last exit gantry before an exit's gore names
#    that exit, not the next one.
# 2. The bridges, every ring site of every act: each bridge's outside face
#    shows the exit's number over the carriageway that drives at it, facing
#    that traffic, inside the parapet's face; beside it, to the reader's right,
#    a plate naming the next exit along and how far its gore is (within 50 m
#    of the true distance). Every word is in the sign atlas, which stays at
#    56 layers or fewer (48 before the pockets).
# 3. The lean: the ring's lane leans in 4 % (inside edge 28 cm low, outside at
#    RAMP_H); every drivable triangle of every look tilts in by 4 % +- 0.1 %.
#    Where a ramp's deck runs over the lane it lies LIFT above it (within
#    1 cm), so there is no step onto the ring; nowhere does the ramp's deck
#    get steeper across than the lean. The put-back pose on the ring is
#    tipped in by the lean.
# 4. Cost: the ring node is 3 draw calls (mesh, pools, lettering), 4 where
#    the piers carry graffiti, and 8 lettering instances at every site.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/world/ring_bank_signs.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const RingSite := preload("res://scripts/world/ring_site.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")
const RoadSigns := preload("res://scripts/world/road_signs.gd")
const WordAtlas := preload("res://scripts/world/word_atlas.gd")

const L := 50.0
const OUTSIDE_LANE_EDGE := 13.2   # RoadRamps.X_LANE: the carriageway's outer edge
const BANK_TOL := 0.001
const SEAM_TOL := 0.01
const DIST_TOL := 50.0
const ATLAS_MAX := 60   # 48 plus a layer per pocket and street word (ramps doc steps 7, 8, 9, 11, 12)

var fails: Array[String] = []
var checks := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		_fail(msg)

func _initialize() -> void:
	RoadFrame.align = null
	RoadFrame.layout = null
	RoadFrame.origin_index = 0
	_check(WordAtlas.layer_count() <= ATLAS_MAX, "the sign atlas has %d layers (%d max)" % [WordAtlas.layer_count(), ATLAS_MAX])
	for act in range(1, RoadMap.MAX_ACT + 1):
		RoadMap.use(0, act)
		if RoadMap.rings().is_empty():
			continue
		_signs(act)
		_bridges(act)
	RoadMap.use(0, 1)
	_lean()
	# the node needs a tree that is up and running
	_cost.call_deferred()

func _finish() -> void:
	RoadMap.use(RoadMap.ENDLESS)
	print("ring_bank_signs: %d checks, %d failed" % [checks, fails.size()])
	quit(1 if not fails.is_empty() else 0)

# ---------- 1. the gantries ----------

func _signs(act: int) -> void:
	var rings := RoadMap.rings()
	var lap := RoadMap.length()
	var gantries: Array = []   # [side, metres along at the sign, ring index]
	for c in RoadMap.period:
		for sg in RoadMap.exit_signs(c):
			_check(not (sg as Dictionary).has("far"), "act %d: an exit sign is still a far (1 km) one" % act)
			var at := (float(c) * L + 2.5) if int(sg.side) > 0 else (float(c) * L + 47.5)
			gantries.append([int(sg.side), at, int(sg.ring)])
	_check(gantries.size() == rings.size() * 2, "act %d: %d exit gantries for %d ring sites (expected 2 each)" % [act, gantries.size(), rings.size()])
	for e in RoadMap.exits():
		var sd := int(e.side)
		var gore := float(e.s)
		# the nearest gantry before this gore on its carriageway
		var best := INF
		var names := -1
		for g in gantries:
			if int(g[0]) != sd:
				continue
			var before := fposmod((gore - float(g[1])) * float(sd), lap)
			if before < best:
				best = before
				names = int(g[2])
		_check(names >= 0 and String(rings[names].id) == String(e.ring), "act %d: the last exit sign before exit %s names exit %s" % [act, e.id, rings[names].id if names >= 0 else "none"])
		_check(absf(best - 400.0) < 3.0, "act %d: the last exit sign before exit %s is %.0f m before it" % [act, e.id, best])

# ---------- 2. the bridges ----------

func _bridges(act: int) -> void:
	var rings := RoadMap.rings()
	var lap := RoadMap.length()
	var face := RoadRamps.RING_OUT + RoadRamps.BARRIER_W
	var lo := RoadRamps.RAMP_H - RingSite.SLAB
	var hi := RoadRamps.RAMP_H + RoadRamps.BARRIER_H
	for ri in rings.size():
		var r: Dictionary = rings[ri]
		var items := RingSite.bridge_signs(ri)
		_check(items.size() == 8, "act %d ring %s: %d lettering parts on the bridges (expected 8)" % [act, r.id, items.size()])
		for it in items:
			var cd: Color = it.cd
			if int(cd.a) == RoadSigns.TEXT or int(cd.a) == RoadSigns.OVERLAY:
				_check(int(cd.r) >= 0, "act %d ring %s: a bridge plate's word has no atlas layer" % [act, r.id])
			var xf: Transform3D = it.xf
			var h := xf.basis.y.length()
			_check(xf.origin.y - h * 0.5 > lo - 0.01 and xf.origin.y + h * 0.5 < hi + 0.01, "act %d ring %s: a bridge plate runs off the parapet (%.2f to %.2f m, face %.2f to %.2f)" % [act, r.id, xf.origin.y - h * 0.5, xf.origin.y + h * 0.5, lo, hi])
			var out := Vector2(xf.origin.x, xf.origin.z).length()
			_check(out > face and out < face + 0.4, "act %d ring %s: a bridge plate stands %.2f m from the centre (face at %.2f)" % [act, r.id, out, face])
		for k in 2:
			var sd := 1 if k == 0 else -1
			var number: Dictionary = items[k * 4]
			var nxf: Transform3D = number.xf
			var n := -nxf.basis.x.normalized()    # RoadSigns.face_basis: x = -n
			# side +1 drives toward -z in the ring's flat space, so it reads a face toward +z
			_check(n.z * float(sd) > 0.95, "act %d ring %s: the number for carriageway %d faces %s" % [act, r.id, sd, n])
			_check(nxf.origin.x * float(sd) > 1.0 and nxf.origin.x * float(sd) < OUTSIDE_LANE_EDGE, "act %d ring %s: the number for carriageway %d is %.1f m across, not over it" % [act, r.id, sd, nxf.origin.x])
			_check(int(number.cd.r) == WordAtlas.layer(PlaceNames.exit_word(int(r.number))) and int(number.cd.b) == RoadSigns.AMBER, "act %d ring %s: the bridge does not show %s in amber" % [act, r.id, PlaceNames.exit_word(int(r.number))])
			_check(nxf.basis.y.length() >= 1.2 - 1e-4, "act %d ring %s: the number is %.2f m tall (1.2 wanted)" % [act, r.id, nxf.basis.y.length()])
			var line: Dictionary = items[k * 4 + 2]
			var dist: Dictionary = items[k * 4 + 3]
			var there: Dictionary = rings[posmod(ri + sd, rings.size())]
			var true_gore := float(there.s) - float(sd) * RoadMap.RING_GORE
			var face_s := float(r.s) - float(sd) * face
			var metres := fposmod((true_gore - face_s) * float(sd), lap)
			_check(int(line.cd.r) == WordAtlas.layer(PlaceNames.exit_word(int(there.number))), "act %d ring %s: the next-exit plate for carriageway %d does not name %s" % [act, r.id, sd, PlaceNames.exit_word(int(there.number))])
			var shown := int(RingSite.next_exit(ri, sd).metres)
			_check(int(dist.cd.r) == WordAtlas.layer(PlaceNames.metres_word(shown)), "act %d ring %s: the next-exit plate does not show %s" % [act, r.id, PlaceNames.metres_word(shown)])
			_check(absf(float(shown) - metres) <= DIST_TOL, "act %d ring %s: the plate says %d m to %s, it is %.0f m" % [act, r.id, shown, there.id, metres])
			# to the reader's right of the number (face_basis z = the reader's right)
			var right := nxf.basis.z.normalized()
			var plate_xf: Transform3D = (items[k * 4 + 1] as Dictionary).xf
			_check((plate_xf.origin - nxf.origin).dot(right) > 2.0, "act %d ring %s: the next-exit plate is not to the right of the number" % [act, r.id])
			_check(plate_xf.origin.x * float(sd) < RingSite.BRIDGE_HALF - 2.0, "act %d ring %s: the next-exit plate is off the bridge (%.1f m)" % [act, r.id, plate_xf.origin.x])

# ---------- 3. the lean ----------

func _lean() -> void:
	_check(absf(RoadRamps.ring_drop(RoadRamps.RING_IN) - 0.28) < 1e-4 and RoadRamps.ring_drop(RoadRamps.RING_OUT) == 0.0, "the ring's inside edge is %.3f m low (0.28 wanted), outside %.3f" % [RoadRamps.ring_drop(RoadRamps.RING_IN), RoadRamps.ring_drop(RoadRamps.RING_OUT)])
	for ri in RoadMap.rings().size():
		var made := RingSite.build(RingSite.look_of(ri))
		var faces: PackedVector3Array = made.faces
		var lane := 0
		var worst := 0.0
		for t in range(0, faces.size(), 3):
			var a := faces[t]
			var b := faces[t + 1]
			var c := faces[t + 2]
			var mid := (a + b + c) / 3.0
			var r := Vector2(mid.x, mid.z).length()
			if r < RoadRamps.RING_IN or r > RoadRamps.RING_OUT:
				continue   # the spur
			var nrm := (b - a).cross(c - a).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			var inward := -(nrm.x * mid.x + nrm.z * mid.z) / r / nrm.y   # rise per metre outward
			worst = maxf(worst, absf(inward - RoadRamps.BANK))
			lane += 1
		_check(lane >= RingSite.SEGS * 2, "ring %s: %d lane triangles" % [RoadMap.rings()[ri].id, lane])
		_check(worst < BANK_TOL, "ring %s: the lane's lean is off 4 %% by up to %.4f" % [RoadMap.rings()[ri].id, worst])
	# where a ramp's deck runs over the lane it lies LIFT above it: no step
	var worst_seam := 0.0
	var worst_cross := 0.0
	var v := RoadRamps.V_RING_OUT
	while v < RoadRamps.V_RING_IN + 6.0:
		var x := RoadRamps.x_at(v) - RoadRamps.HALF
		while x <= RoadRamps.x_at(v) + RoadRamps.HALF + 1e-4:
			var r := Vector2(x, v).length()
			if r < RoadRamps.RING_OUT:
				var ring_y := RoadRamps.RAMP_H - RoadRamps.ring_drop(r)
				worst_seam = maxf(worst_seam, absf(RoadRamps.deck_y(x, v) - RoadRamps.LIFT - ring_y))
			worst_cross = maxf(worst_cross, absf(RoadRamps.deck_y(x + 0.5, v) - RoadRamps.deck_y(x, v)) / 0.5)
			x += 0.5
		v += 0.5
	_check(worst_seam < SEAM_TOL, "a ramp's deck over the ring is off the ring's deck by %.3f m" % worst_seam)
	_check(worst_cross <= RoadRamps.BANK + 1e-3, "a ramp's deck leans %.3f across (the ring's lean is %.2f)" % [worst_cross, RoadRamps.BANK])
	# the put-back pose: tipped in by the lean, on the lane's centre line
	for deg in [0.0, 90.0, 200.0, 300.0]:
		var a := deg_to_rad(deg)
		var site_s := float(RoadMap.rings()[1].s)
		var t := RoadRamps.pose_of({"site": 1, "id": "x2", "s": site_s, "part": "ring", "side": 1, "leg": 1, "v": 0.0, "angle": a})
		var up := t.basis.y.normalized()
		var inward := Vector2(-cos(a), sin(a))   # toward the centre in (x, z)
		var lean := up.x * inward.x + up.z * inward.y
		_check(absf(lean - sin(atan(RoadRamps.BANK))) < 0.002, "put back on the ring at %.0f deg, the car leans in %.4f" % [deg, lean])
		var fwd := -t.basis.z.normalized()
		_check(absf(fwd.dot(up)) < 1e-4, "the put-back pose at %.0f deg is not square" % deg)
	print("ring_bank_signs: lean %.2f %%, ramp seam %.4f m, steepest across %.3f" % [RoadRamps.BANK * 100.0, worst_seam, worst_cross])

# ---------- 4. cost ----------

func _cost() -> void:
	var node: Node3D = RingSite.new()
	root.add_child(node)
	_check(node.is_inside_tree(), "the ring node is not in the tree")
	var first := {}
	for ri in RoadMap.rings().size():
		RingSite.focus_s = float(RoadMap.rings()[ri].s)
		node.call("_place")
		var c: Dictionary = node.counts()
		_check(c.has("draws") and c.has("signs"), "the ring node's counts are %s" % [c])
		if not c.has("draws") or not c.has("signs"):
			break
		# mesh, pools, lettering; and the piers' graffiti where there is some
		var want := 4 if int(c.get("tags", 0)) > 0 else 3
		_check(int(c.draws) == want and int(c.signs) == 8, "ring %s: the ring node is %d draw calls and %d lettering parts (%d and 8 wanted)" % [RoadMap.rings()[ri].id, c.draws, c.signs, want])
		if first.is_empty():
			first = c
	print("ring_bank_signs: the ring node %s" % [first])
	node.free()
	_finish()
