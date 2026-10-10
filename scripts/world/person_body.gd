class_name PersonBody
extends RefCounted

# People pipeline A1 (2026-10-09): ONE low-poly male mesh, skinned to a 17-bone
# skeleton, gives every person in the game. Roy's answers: male only, 7 heights x
# 3 builds from the one mesh by bone scaling, arms both in the cockpit and outside,
# painted faces, no helmets. CPU is the priority, so the normal path is BAKED:
#   bake(variant, pose, outfit, face) -> a static flat-shaded ArrayMesh (one
#   surface, one draw call, no Skeleton3D, nothing to update per frame), cached.
#   Bystanders, clerks and meet crowds use baked meshes (or MultiMesh copies).
#   make_rig() gives a live Skeleton3D rig for the few people who must move every
#   frame (the driver's arms); apply_pose() sets local bone rotations on it.
#
# Space: metres, +y up, the person faces -z (Godot forward, same as car space),
# their left is -x (the driver side). Feet on y = 0 in the rest pose.
# Proportions: 50th-percentile man at REF_S = 1.78 m (Dreyfuss / SAE J833, the
# same reference as tools/fleet_design/manikin.gd). Joint heights are fractions
# of stature; the head is HEAD_H tall at REF_S and grows slower than the body
# (pow(h, HEAD_EXP)), so short men read about 7 heads and tall men about 7.5.
#
# Bone scaling: each bone has an offset scale (where its joint sits relative to
# its parent) and a girth scale (how its own vertices are stretched around the
# joint, not inherited). Height scales lengths; build scales girth and shoulder
# width. The scaled rest mesh is the variant; posing rotates bones about joints.
#
# Faces are painted into a tiny 128x64 atlas (8 faces, 32x32 each, nearest
# filter): grey features multiplied by the vertex colour, so one face works on
# every skin tone. Clothes and hair are vertex colours chosen per outfit.

## The one data file: the body kit numbers, the house style (every colour an
## outfit may use) and the cast. tools/people_pipeline/ checks and draws it.
const DATA_PATH := "res://assets/people/people.json"
static var _data: Dictionary = _load_data()

static var REF_S: float = _data["kit"]["ref_stature"]
static var HEAD_H: float = _data["kit"]["head_height"]       # chin joint to crown at REF_S (a touch big: reads at night)
static var HEAD_EXP: float = _data["kit"]["head_exponent"]   # 0.5: head size grows as sqrt(h)
static var HEIGHTS: Array = _data["kit"]["heights"]
static var BUILDS: Array = (_data["kit"]["builds"] as Dictionary).keys()
const ARM_SPLAY_DEG := 8.0     # rest pose: arms hang 8 deg out from the body
const FACE_COUNT := 8
const ATLAS_W := 128
const ATLAS_H := 64
const FACE_PX := 32

enum { HIPS, SPINE, CHEST, NECK, HEAD, UPPER_L, FORE_L, HAND_L, UPPER_R, FORE_R, HAND_R, THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R }
const BONE_COUNT := 17
const BONE_NAMES := ["hips", "spine", "chest", "neck", "head",
	"upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
const PARENT := [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15]

enum Region { SKIN, TOP, LEGS, SHOES, HAIR, SLEEVE }

## Girth per build. torso/belly are (x, z) widths; limb is the arm and leg girth;
## shoulder scales the shoulder joints' distance from the spine.
static var BUILD_GIRTH: Dictionary = _girths(_data["kit"]["builds"])

# House style (people.json "style"): Amber vs. Dusk plus plain street clothes
# (no magenta, no cyan). Every outfit, random or cast, picks from these lists.
static var SKIN_TONES: Array = _colours(_data["style"]["skin"])
static var HAIR_COLOURS: Array = _colours(_data["style"]["hair"])
static var TOPS: Array = _colours(_data["style"]["tops"])
static var BOTTOMS: Array = _colours(_data["style"]["bottoms"])
static var SHOES: Array = _colours(_data["style"]["shoes"])
static var FACES: Array = _data["style"]["faces"]
const SHAVED := 0.92           # a shaved head is the skin colour, this much darker

class MeshBuf:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var region := PackedInt32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()

static var _base := {}            # the one mesh at REF_S: positions, regions, uvs, bones, weights
static var _bake_cache := {}
static var _material: StandardMaterial3D
static var _atlas: ImageTexture

# --- data (people.json) ------------------------------------------------------

static func _load_data() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		push_error("PersonBody: cannot read %s" % DATA_PATH)
		return {}
	return parsed

static func _colours(list: Array) -> Array:
	return list.map(func(c): return Color(str(c)))

static func _girths(builds: Dictionary) -> Dictionary:
	var out := {}
	for name in builds:
		var b: Dictionary = builds[name]
		out[name] = {"torso": Vector2(b["torso"][0], b["torso"][1]), "belly": Vector2(b["belly"][0], b["belly"][1]),
			"limb": float(b["limb"]), "neck": float(b["neck"]), "shoulder": float(b["shoulder"])}
	return out

## The cast: ids of the people listed in people.json, in file order.
static func cast_ids() -> Array:
	return (_data["people"] as Array).map(func(p): return p["id"])

## One cast member, ready to draw: {"id", "role", "variant", "outfit", "face",
## "pose_name"}. Empty if the id is unknown or the row breaks the kit or the
## house style (check_people.gd says why).
static func person(id: String) -> Dictionary:
	for row in _data["people"]:
		if row["id"] == id and _row_problems(row).is_empty():
			var skin := Color(str(row["skin"]))
			var top := Color(str(row["top"]))
			var o := {"skin": skin, "top": top,
				"hair": skin * SHAVED if row["hair"] == "shaved" else Color(str(row["hair"])),
				"sleeve": skin if row["sleeves"] == "short" else top,
				"legs": Color(str(row["bottoms"])), "shoes": Color(str(row["shoes"]))}
			return {"id": id, "role": row.get("role", ""), "outfit": o, "face": FACES.find(row["face"]),
				"variant": variant(_height_index(row["height"]), BUILDS.find(row["build"])), "pose_name": row["pose"]}
	return {}

## The baked (static, cached) mesh of a cast member in their own pose.
static func bake_person(id: String) -> ArrayMesh:
	var p := person(id)
	if p.is_empty():
		return null
	return bake(p["variant"], pose(p["pose_name"], p["variant"]), p["outfit"], p["face"], p["pose_name"])

static func _height_index(metres) -> int:
	for i in HEIGHTS.size():
		if is_equal_approx(float(HEIGHTS[i]), float(metres)):
			return i
	return -1

static func _in_style(list_name: String, value) -> bool:
	return (_data["style"][list_name] as Array).any(func(c): return str(c).to_upper() == str(value).to_upper())

static func _row_problems(row: Dictionary) -> PackedStringArray:
	var bad := PackedStringArray()
	var id := str(row.get("id", "?"))
	for key in ["id", "height", "build", "face", "skin", "hair", "top", "sleeves", "bottoms", "shoes", "pose"]:
		if not row.has(key):
			bad.append("%s: no '%s'" % [id, key])
	if not bad.is_empty():
		return bad
	if _height_index(row["height"]) < 0:
		bad.append("%s: height %s is not one of the kit's %d heights" % [id, str(row["height"]), HEIGHTS.size()])
	if not BUILDS.has(row["build"]):
		bad.append("%s: build '%s' is not in the kit" % [id, row["build"]])
	if not FACES.has(row["face"]):
		bad.append("%s: face '%s' is not in the style" % [id, row["face"]])
	if not (_data["style"]["poses"] as Array).has(row["pose"]):
		bad.append("%s: pose '%s' is not in the style" % [id, row["pose"]])
	if not ["short", "long"].has(row["sleeves"]):
		bad.append("%s: sleeves must be short or long" % id)
	for pair in [["skin", "skin"], ["top", "tops"], ["bottoms", "bottoms"], ["shoes", "shoes"]]:
		if not _in_style(pair[1], row[pair[0]]):
			bad.append("%s: %s %s is not a house-style colour" % [id, pair[0], row[pair[0]]])
	if row["hair"] != "shaved" and not _in_style("hair", row["hair"]):
		bad.append("%s: hair %s is not a house-style colour" % [id, row["hair"]])
	return bad

## Everything wrong with people.json (empty = good): the kit must give 7
## heights x 3 builds, the style must name one face per atlas tile, and every
## cast row must stay inside the kit and the style.
static func data_problems() -> PackedStringArray:
	if _data.is_empty():
		return PackedStringArray(["cannot read %s" % DATA_PATH])
	var bad := PackedStringArray()
	if HEIGHTS.size() != 7:
		bad.append("kit: %d heights, want 7" % HEIGHTS.size())
	for i in range(1, HEIGHTS.size()):
		if float(HEIGHTS[i]) <= float(HEIGHTS[i - 1]):
			bad.append("kit: heights must rise")
	if BUILDS != ["slim", "average", "heavy"]:
		bad.append("kit: builds must be slim, average, heavy (got %s)" % str(BUILDS))
	if FACES.size() != FACE_COUNT:
		bad.append("style: %d face names, the atlas has %d" % [FACES.size(), FACE_COUNT])
	var seen := {}
	for row in _data["people"]:
		bad.append_array(_row_problems(row))
		if seen.has(row.get("id")):
			bad.append("%s: id used twice" % str(row.get("id")))
		seen[row.get("id")] = true
	return bad

# --- reference skeleton -----------------------------------------------------

## Joint positions at REF_S (metres), rest pose.
static func ref_joints() -> PackedVector3Array:
	var s := REF_S
	var j := PackedVector3Array()
	j.resize(BONE_COUNT)
	var head_y := REF_S - HEAD_H
	j[HIPS] = Vector3(0, 0.530 * s, 0)
	j[SPINE] = Vector3(0, 0.610 * s, 0)
	j[CHEST] = Vector3(0, 0.720 * s, 0)
	j[NECK] = Vector3(0, 0.835 * s, 0)
	j[HEAD] = Vector3(0, head_y, 0)
	for side: float in [-1.0, 1.0]:
		var dir := Vector3(side * sin(deg_to_rad(ARM_SPLAY_DEG)), -cos(deg_to_rad(ARM_SPLAY_DEG)), 0)
		var up := Vector3(side * 0.130 * s, 0.810 * s, 0)
		var fore := up + dir * 0.186 * s
		var hand := fore + dir * 0.146 * s
		var b := UPPER_L if side < 0 else UPPER_R
		j[b] = up
		j[b + 1] = fore
		j[b + 2] = hand
		var t := THIGH_L if side < 0 else THIGH_R
		j[t] = Vector3(side * 0.048 * s, 0.530 * s, 0)
		j[t + 1] = Vector3(side * 0.049 * s, 0.285 * s, 0)
		j[t + 2] = Vector3(side * 0.050 * s, 0.039 * s, 0)
	return j

static func variant_count() -> int:
	return HEIGHTS.size() * BUILDS.size()

## A body variant: height index 0..6 (1.55 to 1.95 m), build index 0..2.
## Holds the scaled joints and the per-bone girth scales; pass it to bake/make_rig.
static func variant(height_idx: int, build_idx: int) -> Dictionary:
	var stature: float = HEIGHTS[clampi(height_idx, 0, HEIGHTS.size() - 1)]
	var build: String = BUILDS[clampi(build_idx, 0, BUILDS.size() - 1)]
	var g: Dictionary = BUILD_GIRTH[build]
	var h := stature / REF_S
	var hs := pow(h, HEAD_EXP)
	var k := (stature - HEAD_H * hs) / (REF_S - HEAD_H)   # vertical scale below the chin
	var rj := ref_joints()
	var offset_scale := []
	var girth := []
	for i in BONE_COUNT:
		var ox := h
		if i == UPPER_L or i == UPPER_R:
			ox = h * float(g["shoulder"])
		elif i == THIGH_L or i == THIGH_R:
			ox = h * sqrt((g["torso"] as Vector2).x)
		offset_scale.append(Vector3(ox, k, h))
		var limb: float = g["limb"]
		var gs: Vector3
		match i:
			HIPS, CHEST:
				var t: Vector2 = g["torso"]
				gs = Vector3(h * t.x, k, h * t.y)
			SPINE:
				var b: Vector2 = g["belly"]
				gs = Vector3(h * b.x, k, h * b.y)
			NECK:
				gs = Vector3(h * float(g["neck"]), k, h * float(g["neck"]))
			HEAD:
				gs = Vector3(hs, hs, hs)
			HAND_L, HAND_R:
				var hl := sqrt(limb)
				gs = Vector3(h * hl, k, h * hl)
			FOOT_L, FOOT_R:
				gs = Vector3(h * (1.0 + (limb - 1.0) * 0.4), k, h)
			_:
				gs = Vector3(h * limb, k, h * limb)
		girth.append(gs)
	var j := PackedVector3Array()
	j.resize(BONE_COUNT)
	for i in BONE_COUNT:
		var p: int = PARENT[i]
		if p < 0:
			j[i] = rj[i] * Vector3(h, k, h)
		else:
			j[i] = j[p] + (rj[i] - rj[p]) * (offset_scale[i] as Vector3)
	return {
		"key": "%d_%d" % [height_idx, build_idx], "stature": stature, "build": build,
		"h": h, "k": k, "hs": hs, "joints": j, "girth": girth, "ref": rj,
	}

# --- poses ------------------------------------------------------------------

static func _q(x_deg: float, y_deg := 0.0, z_deg := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(x_deg), deg_to_rad(y_deg), deg_to_rad(z_deg)))

## Named poses: Dictionary bone -> local rotation. "stand", "smoke",
## "hands_on_hips" and "sit" (legs only; sit_pose adds the arms). The IK poses
## fit the variant `v` (default: average build, 1.75 m). Positive x rotation
## swings a hanging limb forward (-z); positive x on the spine leans it back.
static func pose(name: String, v := {}) -> Dictionary:
	match name:
		"stand":
			return {FORE_L: _q(10), FORE_R: _q(10), UPPER_L: _q(2, 0, 2), UPPER_R: _q(2, 0, -2)}
		"smoke":
			return smoke(v if not v.is_empty() else variant(3, 1))
		"hands_on_hips":
			return hands_on_hips(v if not v.is_empty() else variant(3, 1))
		"sit":
			return sit_legs()
	return {}

## Seated legs and a reclined back; arms are added by sit_pose().
static func sit_legs(recline_deg := 12.0) -> Dictionary:
	return {SPINE: _q(recline_deg), NECK: _q(-recline_deg * 0.6), HEAD: _q(-recline_deg * 0.4),
		THIGH_L: _q(84, 0, -3), SHIN_L: _q(-74), FOOT_L: _q(-6),
		THIGH_R: _q(84, 0, 3), SHIN_R: _q(-74), FOOT_R: _q(-6)}

## Seated pose with both wrists placed on targets (person space: the variant's
## rest hip joint is where it stands; targets are absolute in that space).
## Two-bone IK per arm, elbows down and out. Unreachable targets are reached as
## far as the arm goes (straight arm towards the target).
static func sit_pose(v: Dictionary, wrist_l: Vector3, wrist_r: Vector3, recline_deg := 12.0) -> Dictionary:
	var p := sit_legs(recline_deg)
	reach(v, p, -1.0, wrist_l)
	reach(v, p, 1.0, wrist_r)
	return p

## Weight on the left leg, right hand up at the mouth (diner smokers).
static func smoke(v: Dictionary) -> Dictionary:
	var p := {HIPS: _q(0, 0, 3), SPINE: _q(-2, 0, -3), NECK: _q(4, 0, 0), HEAD: _q(-6, 8, 0),
		THIGH_L: _q(0, 0, -2), THIGH_R: _q(6, -8, 5), SHIN_R: _q(-12),
		UPPER_L: _q(4, 0, 6), FORE_L: _q(18), HAND_R: _q(-60, 0, 0)}
	var fk := fk_globals(v, p)
	var head: Vector3 = fk[0][HEAD]
	var hq: Quaternion = fk[1][HEAD]
	var hs: float = v["hs"]
	var mouth := head + hq * (Vector3(0, 0.05, -0.10) * hs * HEAD_H / 0.226)
	reach(v, p, 1.0, mouth + Vector3(0.05, -0.10, -0.02) * float(v["h"]), Vector3(1.0, -1.0, 0.1))
	return p

## Standing with both hands on the hips, elbows out (arms by IK, so it fits every build).
static func hands_on_hips(v: Dictionary) -> Dictionary:
	var p := {}
	var j: PackedVector3Array = v["joints"]
	var hip_w: float = absf(j[UPPER_L].x) * 0.95
	for side: float in [-1.0, 1.0]:
		var target := Vector3(side * hip_w, j[HIPS].y + 0.07 * float(v["k"]), 0.02)
		reach(v, p, side, target, Vector3(side, 0.0, 0.35))
		aim_hand(v, p, side, Vector3(-side * 0.25, -0.55, -0.8))   # fingers forward over the hip bone
	return p

## Turns one hand so its fingers point along `dir` (person space).
static func aim_hand(v: Dictionary, p: Dictionary, side: float, dir: Vector3) -> void:
	var hand := HAND_L if side < 0 else HAND_R
	var j: PackedVector3Array = v["joints"]
	var rest := (j[hand] - j[hand - 1]).normalized()   # the hand hangs along the forearm at rest
	p.erase(hand)
	var fore_rot: Quaternion = fk_globals(v, p)[1][hand - 1]
	p[hand] = fore_rot.inverse() * Quaternion(rest, dir.normalized())

## Two-bone IK: puts one wrist (side -1 left, +1 right) on `target` in person
## space, writing upper arm and forearm rotations into `p` (other bones as
## already posed). `pole` is where the elbow points (default down and out).
## Out of reach: the arm points straight at the target.
static func reach(v: Dictionary, p: Dictionary, side: float, target: Vector3, pole := Vector3.ZERO) -> void:
	var up := UPPER_L if side < 0 else UPPER_R
	p.erase(up)
	p.erase(up + 1)
	var fk := fk_globals(v, p)
	var gpos: PackedVector3Array = fk[0]
	var grot: Array = fk[1]
	var j: PackedVector3Array = v["joints"]
	var shoulder := gpos[up]
	var l1 := (j[up + 1] - j[up]).length()
	var l2 := (j[up + 2] - j[up + 1]).length()
	var to := target - shoulder
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.0005)
	var dir := to.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var hgt := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pl := pole if pole != Vector3.ZERO else Vector3(side * 0.7, -1.0, 0.25)
	pl = (pl - dir * pl.dot(dir)).normalized()
	var elbow := shoulder + dir * a + pl * hgt
	var wrist := shoulder + dir * d
	var rest_u := (j[up + 1] - j[up]).normalized()
	var rest_f := (j[up + 2] - j[up + 1]).normalized()
	var chest_rot: Quaternion = grot[CHEST]
	var g_upper := Quaternion(rest_u, (elbow - shoulder).normalized())
	var g_fore := Quaternion(rest_f, (wrist - elbow).normalized())
	p[up] = chest_rot.inverse() * g_upper
	p[up + 1] = g_upper.inverse() * g_fore
	if not p.has(up + 2):
		p[up + 2] = _q(0, 0, -side * 10.0)

## Global (person space) joint positions and rotations of a posed variant.
## Returns [PackedVector3Array positions, Array[Quaternion] rotations].
static func fk_globals(v: Dictionary, p: Dictionary) -> Array:
	var j: PackedVector3Array = v["joints"]
	var gpos := PackedVector3Array()
	gpos.resize(BONE_COUNT)
	var grot := []
	grot.resize(BONE_COUNT)
	for i in BONE_COUNT:
		var q: Quaternion = p.get(i, Quaternion.IDENTITY)
		var par: int = PARENT[i]
		if par < 0:
			grot[i] = q
			gpos[i] = j[i]
		else:
			grot[i] = (grot[par] as Quaternion) * q
			gpos[i] = gpos[par] + (grot[par] as Quaternion) * (j[i] - j[par])
	return [gpos, grot]

# --- outfits and faces ------------------------------------------------------

## A deterministic outfit from a seed: skin, hair, top, sleeves, trousers, shoes.
static func outfit(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var skin: Color = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	var hair: Color = HAIR_COLOURS[rng.randi() % HAIR_COLOURS.size()]
	if rng.randf() < 0.15:
		hair = skin * SHAVED
	var top: Color = TOPS[rng.randi() % TOPS.size()]
	return {"skin": skin, "hair": hair, "top": top,
		"sleeve": skin if rng.randf() < 0.3 else top,   # short sleeves show forearms
		"legs": BOTTOMS[rng.randi() % BOTTOMS.size()], "shoes": SHOES[rng.randi() % SHOES.size()]}

static func _region_colour(region: int, o: Dictionary) -> Color:
	match region:
		Region.SKIN: return o["skin"]
		Region.TOP: return o["top"]
		Region.LEGS: return o["legs"]
		Region.SHOES: return o["shoes"]
		Region.HAIR: return o["hair"]
		Region.SLEEVE: return o["sleeve"]
	return Color.WHITE

## The painted-face atlas: 4 x 2 faces of 32 x 32 px, white elsewhere, features
## in grey (multiplied by the skin vertex colour). Faces: 0 plain, 1 heavy brows,
## 2 moustache, 3 stubble, 4 full beard, 5 glasses, 6 tired (eye bags), 7 goatee + scar.
static func face_image() -> Image:
	var img := Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for f in FACE_COUNT:
		var ox := (f % 4) * FACE_PX
		var oy := (f / 4) * FACE_PX
		var put := func(x: int, y: int, w: int, hh: int, c: Color) -> void:
			for yy in range(y, y + hh):
				for xx in range(x, x + w):
					if xx >= 1 and xx < FACE_PX - 1 and yy >= 1 and yy < FACE_PX - 1:
						img.set_pixel(ox + xx, oy + yy, c)
		var dark := Color(0.16, 0.14, 0.13)
		var brow := Color(0.30, 0.26, 0.24)
		var lips := Color(0.78, 0.56, 0.52)
		var shade := Color(0.82, 0.78, 0.76)
		var hairy := Color(0.40, 0.36, 0.34)
		var stub := Color(0.70, 0.67, 0.66)
		# stubble and beards first, features on top
		if f == 3:
			put.call(7, 21, 18, 10, stub)
		if f == 4:
			put.call(6, 20, 20, 11, hairy)
		if f == 7:
			put.call(13, 26, 6, 5, hairy)
		# eyes
		put.call(8, 15, 3, 2, dark)
		put.call(21, 15, 3, 2, dark)
		# brows
		var bh := 2 if f == 1 else 1
		put.call(7, 12 - (bh - 1), 5, bh, brow)
		put.call(20, 12 - (bh - 1), 5, bh, brow)
		# nose shadow and the line under it
		put.call(15, 16, 2, 4, shade)
		put.call(14, 20, 4, 1, shade)
		# mouth
		put.call(13, 24, 6, 1, lips if f != 4 else hairy * 0.8)
		if f == 2 or f == 7:
			put.call(12, 22, 8, 1, hairy)
		if f == 5:
			for ex in [6, 19]:
				put.call(ex, 13, 7, 1, dark)
				put.call(ex, 18, 7, 1, dark)
				put.call(ex, 13, 1, 6, dark)
				put.call(ex + 6, 13, 1, 6, dark)
			put.call(13, 15, 6, 1, dark)
		if f == 6:
			put.call(8, 17, 4, 1, shade)
			put.call(20, 17, 4, 1, shade)
		if f == 7:
			put.call(23, 10, 1, 8, shade)
	return img

static func face_texture() -> ImageTexture:
	if _atlas == null:
		_atlas = ImageTexture.create_from_image(face_image())
	return _atlas

## The one material every person shares (vertex colour x face atlas).
static func material() -> StandardMaterial3D:
	if _material == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = face_texture()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.roughness = 0.9
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_material = m
	return _material

# --- the base mesh ----------------------------------------------------------

static func _ring(c: Vector3, rx: float, rz: float, sides: int, phase_deg := 0.0) -> Array:
	var pts := []
	for i in sides:
		var t := deg_to_rad(phase_deg + 360.0 * i / sides)
		pts.append(c + Vector3(rx * sin(t), 0, -rz * cos(t)))
	return pts

static func _add_tri(b: MeshBuf, pts: Array, ws: Array, uvs: Array, region: int, outward: Vector3) -> void:
	var p0: Vector3 = pts[0]
	var n: Vector3 = ((pts[1] as Vector3) - p0).cross((pts[2] as Vector3) - p0)
	var order := [0, 2, 1] if n.dot(outward) >= 0.0 else [0, 1, 2]   # stored clockwise (Godot front)
	for o in order:
		b.pos.append(pts[o])
		b.uv.append(uvs[o])
		b.region.append(region)
		var w: Dictionary = ws[o]
		var keys := w.keys()
		for slot in 4:
			b.bones.append(int(keys[slot]) if slot < keys.size() else 0)
			b.weights.append(float(w[keys[slot]]) if slot < keys.size() else 0.0)

static func _add_quad(b: MeshBuf, p: Array, w: Array, region: int, outward: Vector3, uv := []) -> void:
	var u := uv if uv.size() == 4 else [Vector2(-1, -1), Vector2(-1, -1), Vector2(-1, -1), Vector2(-1, -1)]
	_add_tri(b, [p[0], p[1], p[2]], [w[0], w[1], w[2]], [u[0], u[1], u[2]], region, outward)
	_add_tri(b, [p[0], p[2], p[3]], [w[0], w[2], w[3]], [u[0], u[2], u[3]], region, outward)

## Rings: Array of [centre, rx, rz, weights]; regions: one per segment (or a
## Callable(seg, side_angle_deg) -> region). Caps: "bottom"/"top".
static func _tube(b: MeshBuf, rings: Array, sides: int, regions, phase := 0.0, caps := [], uv_fn = null) -> void:
	var pts := []
	for r in rings:
		pts.append(_ring(r[0], r[1], r[2], sides, phase))
	for s in rings.size() - 1:
		var axis_mid: Vector3 = ((rings[s][0] as Vector3) + rings[s + 1][0]) * 0.5
		for i in sides:
			var i2 := (i + 1) % sides
			var quad := [pts[s][i], pts[s][i2], pts[s + 1][i2], pts[s + 1][i]]
			var mid: Vector3 = (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25
			var ang := wrapf(phase + 360.0 * (i + 0.5) / sides, -180.0, 180.0)
			var region: int = regions.call(s, ang) if regions is Callable else regions[s]
			var uv := []
			if uv_fn != null and region == -1:
				region = Region.SKIN
				for q in quad:
					uv.append(uv_fn.call(q))
			var w := [rings[s][3], rings[s][3], rings[s + 1][3], rings[s + 1][3]]
			_add_quad(b, quad, w, region, mid - axis_mid, uv)
	for cap in caps:
		var idx := 0 if cap[0] == "bottom" else rings.size() - 1
		var c: Vector3 = rings[idx][0]
		var outward := Vector3.DOWN if cap[0] == "bottom" else Vector3.UP
		var ring: Array = pts[idx]
		for i in sides:
			var w: Dictionary = rings[idx][3]
			_add_tri(b, [c, ring[i], ring[(i + 1) % sides]], [w, w, w],
				[Vector2(-1, -1), Vector2(-1, -1), Vector2(-1, -1)], cap[1], outward)

static func _box(b: MeshBuf, size: Vector3, center: Vector3, basis: Basis, w: Dictionary, region: int) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var fc := n * h
		var hu := u * h
		var hv := v * h
		var quad := [fc - hu - hv, fc + hu - hv, fc + hu + hv, fc - hu + hv]
		var world := []
		for q in quad:
			world.append(center + basis * (q as Vector3))
		_add_quad(b, world, [w, w, w, w], region, basis * n)

## The one mesh, built at REF_S in the rest pose. Triangle list (3 entries per
## triangle, flat shaded), each vertex with a region, a face uv (-1 = no face)
## and up to 4 bone weights.
static func base() -> Dictionary:
	if not _base.is_empty():
		return _base
	var b := MeshBuf.new()
	var s := REF_S
	var j := ref_joints()
	var T := Region.TOP
	var L := Region.LEGS
	# torso: crotch to neck, 8 sides
	var torso := [
		[Vector3(0, 0.470 * s, 0.004), 0.075 * s, 0.058 * s, {HIPS: 1.0}],
		[Vector3(0, 0.530 * s, 0.006), 0.098 * s, 0.064 * s, {HIPS: 1.0}],
		[Vector3(0, 0.610 * s, 0.004), 0.087 * s, 0.058 * s, {HIPS: 0.4, SPINE: 0.6}],
		[Vector3(0, 0.665 * s, 0.000), 0.091 * s, 0.062 * s, {SPINE: 1.0}],
		[Vector3(0, 0.720 * s, 0.002), 0.100 * s, 0.068 * s, {SPINE: 0.3, CHEST: 0.7}],
		[Vector3(0, 0.780 * s, 0.006), 0.106 * s, 0.064 * s, {CHEST: 1.0}],
		[Vector3(0, 0.822 * s, 0.010), 0.088 * s, 0.054 * s, {CHEST: 1.0}],
		[Vector3(0, 0.838 * s, 0.012), 0.034 * s, 0.032 * s, {CHEST: 0.5, NECK: 0.5}],
		[Vector3(0, 0.872 * s, 0.006), 0.031 * s, 0.031 * s, {NECK: 0.5, HEAD: 0.5}],
	]
	_tube(b, torso, 8, [L, L, T, T, T, T, T, Region.SKIN], 22.5, [["bottom", L]])
	# head: 8 sides, front faces (|angle| < 70) painted, hair on top and behind
	var hj := j[HEAD]
	var hk := HEAD_H / 0.226   # head rings drawn at a 0.226 m crown, scaled to HEAD_H
	var head := []
	for r in [[-0.004, -0.030, 0.040, 0.040], [0.045, -0.010, 0.066, 0.084], [0.100, 0.000, 0.077, 0.094],
			[0.145, 0.002, 0.079, 0.097], [0.192, 0.006, 0.067, 0.084], [0.226, 0.010, 0.034, 0.043]]:
		head.append([hj + Vector3(0, r[0], r[1]) * hk, r[2] * hk, r[3] * hk, {HEAD: 1.0}])
	var head_region := func(seg: int, ang: float) -> int:
		var a := absf(ang)
		match seg:
			0, 1:
				return -1 if a < 70.0 else Region.SKIN
			2:
				if a < 70.0:
					return -1
				return Region.HAIR if a > 100.0 else Region.SKIN
			3:
				return -1 if a < 46.0 else Region.HAIR
		return Region.HAIR
	var face_uv := func(p: Vector3) -> Vector2:
		var lp := (p - hj) / hk
		return Vector2(clampf(0.5 + lp.x / 0.16, 0.03, 0.97), clampf(1.0 - lp.y / 0.19, 0.03, 0.97))
	_tube(b, head, 8, head_region, 22.5, [["bottom", Region.SKIN], ["top", Region.HAIR]], face_uv)
	# legs: 6 sides, hip to ankle; shoes as boxes
	for side: float in [-1.0, 1.0]:
		var t := THIGH_L if side < 0 else THIGH_R
		var x0 := side * 0.048 * s
		var leg := [
			[Vector3(x0, 0.556 * s, 0.004), 0.047 * s, 0.050 * s, {t: 1.0}],
			[Vector3(x0, 0.420 * s, 0.002), 0.044 * s, 0.046 * s, {t: 1.0}],
			[Vector3(side * 0.049 * s, 0.285 * s, 0.0), 0.031 * s, 0.032 * s, {t: 0.5, t + 1: 0.5}],
			[Vector3(side * 0.049 * s, 0.200 * s, 0.004), 0.032 * s, 0.035 * s, {t + 1: 1.0}],
			[Vector3(side * 0.050 * s, 0.042 * s, 0.002), 0.022 * s, 0.022 * s, {t + 1: 0.5, t + 2: 0.5}],
		]
		_tube(b, leg, 6, [L, L, L, L], 0.0)
		_box(b, Vector3(0.056 * s, 0.045 * s, 0.150 * s), Vector3(side * 0.050 * s, 0.0225 * s, -0.045 * s),
			Basis.IDENTITY, {t + 2: 1.0}, Region.SHOES)
	# arms: 6 sides along the splayed rest line, sleeve on the forearm, mitten hands
	for side: float in [-1.0, 1.0]:
		var up := UPPER_L if side < 0 else UPPER_R
		var a0 := j[up]
		var dir := (j[up + 1] - j[up]).normalized()
		var at := func(t: float) -> Vector3: return a0 + dir * t * s
		var arm := [
			[at.call(-0.022), 0.028 * s, 0.030 * s, {CHEST: 0.5, up: 0.5}],
			[at.call(0.010), 0.030 * s, 0.031 * s, {up: 1.0}],
			[at.call(0.100), 0.026 * s, 0.027 * s, {up: 1.0}],
			[at.call(0.186), 0.020 * s, 0.021 * s, {up: 0.5, up + 1: 0.5}],
			[at.call(0.250), 0.021 * s, 0.022 * s, {up + 1: 1.0}],
			[at.call(0.330), 0.015 * s, 0.017 * s, {up + 1: 0.5, up + 2: 0.5}],
		]
		_tube(b, arm, 6, [T, T, T, Region.SLEEVE, Region.SLEEVE], 0.0, [["top", T]])
		var hb := Basis(Vector3(0, 0, 1), -side * deg_to_rad(ARM_SPLAY_DEG))
		var hand_c := j[up + 2] + dir * 0.050 * s
		_box(b, Vector3(0.020 * s, 0.100 * s, 0.050 * s), hand_c, hb, {up + 2: 1.0}, Region.SKIN)
		_box(b, Vector3(0.016 * s, 0.040 * s, 0.016 * s), j[up + 2] + dir * 0.030 * s + Vector3(-side * 0.004 * s, 0, -0.026 * s),
			hb, {up + 2: 1.0}, Region.SKIN)
	_base = {"pos": b.pos, "uv": b.uv, "region": b.region, "bones": b.bones, "weights": b.weights}
	return _base

static func triangle_count() -> int:
	return (base()["pos"] as PackedVector3Array).size() / 3

# --- variants -> meshes -----------------------------------------------------

## Rest-pose positions of a variant: each vertex stretched around its bones'
## joints by the girth scales and moved with the scaled joints.
static func _variant_positions(v: Dictionary, p: Dictionary) -> PackedVector3Array:
	var b := base()
	var src: PackedVector3Array = b["pos"]
	var bones: PackedInt32Array = b["bones"]
	var weights: PackedFloat32Array = b["weights"]
	var rj: PackedVector3Array = v["ref"]
	var girth: Array = v["girth"]
	var fk := fk_globals(v, p)
	var gpos: PackedVector3Array = fk[0]
	var grot: Array = fk[1]
	var out := PackedVector3Array()
	out.resize(src.size())
	for vi in src.size():
		var acc := Vector3.ZERO
		for slot in 4:
			var w := weights[vi * 4 + slot]
			if w <= 0.0:
				continue
			var bi := bones[vi * 4 + slot]
			var d := (src[vi] - rj[bi]) * (girth[bi] as Vector3)
			acc += (gpos[bi] + (grot[bi] as Quaternion) * d) * w
		out[vi] = acc
	return out

static func _arrays(v: Dictionary, p: Dictionary, o: Dictionary, face: int, skinned: bool) -> Array:
	var b := base()
	var pos := _variant_positions(v, p)
	var regions: PackedInt32Array = b["region"]
	var fuv: PackedVector2Array = b["uv"]
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	var col := PackedColorArray()
	col.resize(pos.size())
	var uv := PackedVector2Array()
	uv.resize(pos.size())
	var tile := Vector2((face % 4) * FACE_PX, ((face / 4) % 2) * FACE_PX)
	var white := Vector2(0.5 / ATLAS_W, 0.5 / ATLAS_H)
	for t in pos.size() / 3:
		var i := t * 3
		var n := (pos[i + 2] - pos[i]).cross(pos[i + 1] - pos[i])
		n = n.normalized() if n.length_squared() > 1e-16 else Vector3.UP
		for k in 3:
			nrm[i + k] = n
			col[i + k] = _region_colour(regions[i + k], o).srgb_to_linear()
			var f := fuv[i + k]
			uv[i + k] = white if f.x < 0.0 else Vector2((tile.x + f.x * FACE_PX) / ATLAS_W, (tile.y + f.y * FACE_PX) / ATLAS_H)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV] = uv
	if skinned:
		arr[Mesh.ARRAY_BONES] = b["bones"]
		arr[Mesh.ARRAY_WEIGHTS] = b["weights"]
	return arr

static func _outfit_key(o: Dictionary) -> String:
	var parts := []
	for key in ["skin", "hair", "top", "sleeve", "legs", "shoes"]:
		parts.append((o[key] as Color).to_html(false))
	return "-".join(parts)

## A static mesh of a posed person: one surface, flat shaded, the shared
## material. Cached on (variant, pose name, outfit, face) when pose_name is given.
static func bake(v: Dictionary, p: Dictionary, o: Dictionary, face := 0, pose_name := "") -> ArrayMesh:
	var key := ""
	if pose_name != "":
		key = "%s|%s|%s|%d" % [v["key"], pose_name, _outfit_key(o), face]
		if _bake_cache.has(key):
			return _bake_cache[key]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(v, p, o, face, false))
	m.surface_set_material(0, material())
	if key != "":
		_bake_cache[key] = m
	return m

static func clear_cache() -> void:
	_bake_cache.clear()

## A live rig: Node3D "Person" with a Skeleton3D (rests = the variant's scaled
## joints, so posing never shears) and the skinned variant mesh. For the few
## people that move every frame; everyone else should be baked.
static func make_rig(v: Dictionary, o: Dictionary, face := 0) -> Node3D:
	var j: PackedVector3Array = v["joints"]
	var root := Node3D.new()
	root.name = "Person"
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	root.add_child(skel)
	var skin := Skin.new()
	for i in BONE_COUNT:
		skel.add_bone(BONE_NAMES[i])
		var par: int = PARENT[i]
		if par >= 0:
			skel.set_bone_parent(i, par)
		skel.set_bone_rest(i, Transform3D(Basis(), j[i] - (j[par] if par >= 0 else Vector3.ZERO)))
		skin.add_bind(i, Transform3D(Basis(), -j[i]))
	skel.reset_bone_poses()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(v, {}, o, face, true))
	mesh.surface_set_material(0, material())
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.skin = skin
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	return root

## Sets local bone rotations on a rig's skeleton (bones not in the pose go back to rest).
static func apply_pose(skel: Skeleton3D, p: Dictionary) -> void:
	for i in BONE_COUNT:
		skel.set_bone_pose_rotation(i, p.get(i, Quaternion.IDENTITY))
