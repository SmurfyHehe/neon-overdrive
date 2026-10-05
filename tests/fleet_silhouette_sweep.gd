extends SceneTree

# 360-degree outline check for the 12 fleet designs (stage B1 audit).
#
# Renders every car's proxy as a flat black outline from 96 orbit cameras
# (24 yaw steps of 15 degrees x pitch 2, 15, 35, 60 degrees: the garage 360
# view) plus the chase cam looking at a car 14 m ahead (how traffic is seen
# in play). Each outline is cropped and scaled to fit a 96 x 96 box, keeping
# its proportions, so size alone can't tell cars apart: only shape counts.
#
# For every view and every pair of cars it measures how far apart the two
# outlines are: for every edge pixel of each outline, the distance to the
# other outline's edge. "Gap" = how far apart the most different 3% of the
# two edges are (97th percentile of those distances), in % of the box. A
# feature one car has and the other lacks (a wing, a light bar, a bed, a
# scoop, wider hips, a lower roof) pushes it up. A car's gap at a view is the
# one to the most similar other car there. A gap of 1 px (1%) means no
# feature of either outline stands out: an "outline twin".
# (Area overlap is reported too, but any two cars that fill the same box
# overlap 90%+, so it says little.)
#
# Pass: no outline twins from any camera up to 35 degrees high or from the
# chase-ahead view. The 60-degree row is reported, not judged: from high up
# every car is a rounded rectangle and identity comes from the roof graphic
# (B1 found the same: top view 1/12 sure).
#
# Writes to user://fleet_audit/ (so a test run never dirties the repo):
#   silhouette_sweep.json   every number
#   outlines/<car>.png      the 97 normalised outlines (4 pitch rows x 24 yaw,
#                           then the chase-ahead view)
# -- --out=res://docs/design/fleet/audit refreshes the committed snapshot.
#
# Needs a real renderer (outlines are rendered), so run with a window:
#   godot --path . -s res://tests/fleet_silhouette_sweep.gd
# User args: -- --builds   also sweep every example build (vs stock cars)
#            -- --out=DIR  write somewhere else (default OUT_DIR)
#            -- --save-views=y270_p02,chase_ahead,...  also save those views
#               at 320 px as views/<car>__<view>.png (for blind tests)

const Proxies := preload("res://tests/fleet_proxies.gd")
const OUT_DIR := "user://fleet_audit"
const RES := 512
const N := 96
const CAP := 8                 # px, distances are capped here
const FOV := 30.0
const DIST := 12.5
const PITCHES := [2.0, 15.0, 35.0, 60.0]
const YAW_STEP := 15.0
const CHASE_EYE_H := 1.85      # stage A chase cam height
const CHASE_AIM := Vector3(0, 0.95, -12.0)
const CHASE_VFOV := 58.0
const AHEAD := 14.0            # B1's traffic-ahead distance: car tail to camera
const MIN_GAP := 0.02         # 2 px of 96: ~9 cm on a 4.4 m car side-on
const GAP_Q := 0.97            # judged on the outline's most different 3%
const JUDGED_MAX_PITCH := 35
# Twins that are known and left open for Roy (B1 audit, 2026-10-05). Listed
# so the check still fails on any NEW twin. Key: "car|other car|view".
const KNOWN_TWINS := {
	"p1_coupe|p3_tuner|y135_p35": "one high front-3/4 angle; by eye the tuner's notchback step still shows",
	"p3_tuner|p1_coupe|y135_p35": "same pair, other way round",
	"p2_hothatch|p6_crossover|y165_p35": "one high front angle: both are hatchbacks; the rack's crossbar tips are the only tell",
	"p6_crossover|p2_hothatch|y165_p35": "same pair, other way round",
	"p5_muscle/street|n1_commuter|y000_p35": "one high rear angle of one build; the hourglass hips still differ by ~1 px",
}
# Builds meant to look plain: the tuner's "Lip (sleeper)" street build.
const SLEEPER_BUILDS := ["p3_tuner/street"]

var vp: SubViewport
var cam: Camera3D
var fails := 0

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	fails += 1

func _initialize() -> void:
	var data := Proxies.load_data()
	if data.is_empty():
		quit(1)
		return
	var out_dir := OUT_DIR
	var save_views := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--save-views="):
			save_views = a.substr(13).split(",")
	vp = SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	cam = Camera3D.new()
	vp.add_child(cam)

	var views := _views()
	var subjects := []   # [car, build name]
	for car in data.cars:
		subjects.append([car, "stock"])
		if "--builds" in OS.get_cmdline_user_args():
			for b in car.builds:
				if b.name != "stock":
					subjects.append([car, b.name])

	var shapes := []     # per subject, per view: [mask, edge pixel list, distance to edge]
	var labels := []
	var t0 := Time.get_ticks_msec()
	for sj in subjects:
		var car: Dictionary = sj[0]
		var node := Proxies.build_car(data, car, sj[1], "silhouette")
		vp.add_child(node)
		var aabb := _aabb(node)
		var per_view := []
		var tiles := []
		for v in views:
			_place_camera(v, aabb)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			if v.name in save_views:
				_save_view(img, out_dir.path_join("views").path_join("%s__%s.png" % [car.id if sj[1] == "stock" else "%s__%s" % [car.id, sj[1]], v.name]))
			var mt := _mask(img)
			per_view.append(_shape(mt[0]))
			tiles.append(mt[1])
		node.queue_free()
		await process_frame
		shapes.append(per_view)
		labels.append(car.id if sj[1] == "stock" else "%s/%s" % [car.id, sj[1]])
		_save_strip(out_dir, labels[-1], tiles)
	print("rendered %d outlines in %.1f s" % [subjects.size() * views.size(), (Time.get_ticks_msec() - t0) / 1000.0])

	var stock_ix := []
	for i in subjects.size():
		if subjects[i][1] == "stock":
			stock_ix.append(i)
	var result := {"views": [], "cars": {}, "min_gap": MIN_GAP, "judged_max_pitch": JUDGED_MAX_PITCH, "mask_px": N,
		"metric": "gap = 90th percentile of edge-to-edge distance to the most similar other car's stock outline, as a fraction of the 96 px box (capped at 8 px)"}
	for v in views:
		result.views.append({"name": v.name, "yaw": v.yaw, "pitch": v.pitch})
	var known := []
	var view_sum := PackedFloat32Array()
	view_sum.resize(views.size())
	for i in subjects.size():
		var rows := []
		var worst := 1.0
		var worst_at := ""
		var worst_vs := ""
		var sum := 0.0
		for vi in views.size():
			var best := 1e9
			var best_j := -1
			for j in stock_ix:
				if subjects[j][0].id == subjects[i][0].id:
					continue
				var g := _gap(shapes[i][vi], shapes[j][vi], GAP_Q)
				if g < best:
					best = g
					best_j = j
			var d := best / N
			var area := _iou(shapes[i][vi][0], shapes[best_j][vi][0])
			sum += d
			if subjects[i][1] == "stock":
				view_sum[vi] += d
			rows.append([snappedf(d, 0.0001), labels[best_j], snappedf(area, 0.001)])
			var judged: bool = views[vi].pitch <= JUDGED_MAX_PITCH
			if judged and d < worst:
				worst = d
				worst_at = views[vi].name
				worst_vs = labels[best_j]
			if judged and d < MIN_GAP:
				var key := "%s|%s|%s" % [labels[i], labels[best_j], views[vi].name]
				if KNOWN_TWINS.has(key):
					known.append("%s (%s)" % [key, KNOWN_TWINS[key]])
				elif labels[i] in SLEEPER_BUILDS:
					known.append("%s (sleeper build, meant to blend in)" % key)
				else:
					_fail("%s: at %s its outline is within %.1f%% of %s's (need %.0f%%)" % [labels[i], views[vi].name, d * 100.0, labels[best_j], MIN_GAP * 100.0])
		result.cars[labels[i]] = {"per_view": rows, "worst": snappedf(worst, 0.001), "worst_view": worst_at,
			"worst_vs": worst_vs, "mean": snappedf(sum / views.size(), 0.001)}
		print("%-28s smallest gap %4.1f%% at %-12s vs %-16s mean %4.1f%%" % [labels[i], worst * 100.0, worst_at, worst_vs, sum / views.size() * 100.0])
	var per_view_mean := {}
	for vi in views.size():
		per_view_mean[views[vi].name] = snappedf(view_sum[vi] / stock_ix.size(), 0.001)
	result["per_view_mean"] = per_view_mean
	result["known_twins"] = known
	for k in known:
		print("known twin: ", k)
	var pitch_line := "mean gap by pitch:"
	for pi in PITCHES.size():
		var s := 0.0
		for k in 24:
			s += view_sum[pi * 24 + k]
		pitch_line += "  %d deg %.1f%%" % [int(PITCHES[pi]), s / (24.0 * stock_ix.size()) * 100.0]
	pitch_line += "  chase-ahead %.1f%%" % (view_sum[views.size() - 1] / stock_ix.size() * 100.0)
	print(pitch_line)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var f := FileAccess.open(out_dir.path_join("silhouette_sweep.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " ", false))
	f.close()
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ views
func _views() -> Array:
	var out := []
	for pitch in PITCHES:
		var yaw := 0.0
		while yaw < 360.0 - 0.01:
			out.append({"name": "y%03d_p%02d" % [int(yaw), int(pitch)], "yaw": int(yaw), "pitch": int(pitch)})
			yaw += YAW_STEP
	out.append({"name": "chase_ahead", "yaw": 0, "pitch": -1})
	return out

func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in node.get_children():
		var mi := c as MeshInstance3D
		var a := mi.transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box

func _place_camera(v: Dictionary, aabb: AABB) -> void:
	if v.pitch < 0:
		# the stage A chase cam of a player AHEAD m behind this car's tail
		cam.fov = CHASE_VFOV
		var eye := Vector3(0, CHASE_EYE_H, aabb.end.z + AHEAD)
		cam.look_at_from_position(eye, eye + (CHASE_AIM - Vector3(0, CHASE_EYE_H, 5.2)), Vector3.UP)
		return
	cam.fov = FOV
	var target := aabb.get_center()
	var a := deg_to_rad(float(v.yaw))
	var e := deg_to_rad(float(v.pitch))
	var eye := target + DIST * Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a))
	cam.look_at_from_position(eye, target, Vector3.UP)

# ------------------------------------------------------------------ outlines
# Returns [mask (N*N bytes, 1 = car), tile (N x N RGBA image for the strip)].
func _mask(img: Image) -> Array:
	img.convert(Image.FORMAT_RGBA8)
	var r := img.get_used_rect()
	var out := PackedByteArray()
	out.resize(N * N)
	if r.size.x == 0 or r.size.y == 0:
		return [out, Image.create(N, N, false, Image.FORMAT_RGBA8)]
	var crop := img.get_region(r)
	var s := float(N) / maxf(r.size.x, r.size.y)
	var w := maxi(1, roundi(r.size.x * s))
	var h := maxi(1, roundi(r.size.y * s))
	crop.generate_mipmaps()
	crop.resize(w, h, Image.INTERPOLATE_TRILINEAR)
	var box := Image.create(N, N, false, Image.FORMAT_RGBA8)
	box.blit_rect(crop, Rect2i(0, 0, w, h), Vector2i((N - w) / 2, (N - h) / 2))
	var raw := box.get_data()
	for p in N * N:
		out[p] = 1 if raw[p * 4 + 3] >= 128 else 0
	return [out, box]

# [mask, edge pixels (indices), distance to the nearest edge pixel (N*N
# bytes, 8-neighbour steps, capped at CAP)]
func _shape(m: PackedByteArray) -> Array:
	var edge := PackedInt32Array()
	var dist := PackedByteArray()
	dist.resize(N * N)
	dist.fill(CAP)
	var frontier := PackedInt32Array()
	for y in N:
		for x in N:
			var p := y * N + x
			if not m[p]:
				continue
			if x == 0 or y == 0 or x == N - 1 or y == N - 1 or not m[p - 1] or not m[p + 1] or not m[p - N] or not m[p + N]:
				edge.append(p)
				dist[p] = 0
				frontier.append(p)
	for step in range(1, CAP):
		var nxt := PackedInt32Array()
		for p in frontier:
			var x := p % N
			var y := p / N
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var xx: int = x + dx
					var yy: int = y + dy
					if xx < 0 or yy < 0 or xx >= N or yy >= N:
						continue
					var q := yy * N + xx
					if dist[q] > step:
						dist[q] = step
						nxt.append(q)
		frontier = nxt
	return [m, edge, dist]

# Percentile Q of the edge-to-edge distances, both ways, in px.
func _gap(a: Array, b: Array, q := 0.9) -> float:
	var ea: PackedInt32Array = a[1]
	var eb: PackedInt32Array = b[1]
	if ea.is_empty() or eb.is_empty():
		return float(CAP)
	var da: PackedByteArray = a[2]
	var db: PackedByteArray = b[2]
	var hist := PackedInt32Array()
	hist.resize(CAP + 1)
	for p in ea:
		hist[db[p]] += 1
	for p in eb:
		hist[da[p]] += 1
	var total := ea.size() + eb.size()
	var want := int(ceil(total * q))
	var acc := 0
	for d in CAP + 1:
		acc += hist[d]
		if acc >= want:
			return float(d)
	return float(CAP)

func _iou(a: PackedByteArray, b: PackedByteArray) -> float:
	var inter := 0
	var uni := 0
	for p in a.size():
		var x := a[p]
		var y := b[p]
		if x or y:
			uni += 1
			if x and y:
				inter += 1
	return float(inter) / maxf(1.0, uni)

func _save_view(src: Image, path: String) -> void:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var r := img.get_used_rect()
	var crop := img.get_region(r)
	var s := 300.0 / maxf(r.size.x, r.size.y)
	crop.generate_mipmaps()
	crop.resize(maxi(1, roundi(r.size.x * s)), maxi(1, roundi(r.size.y * s)), Image.INTERPOLATE_TRILINEAR)
	var canvas := Image.create(320, 320, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.WHITE)
	canvas.blend_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i((320 - crop.get_width()) / 2, (320 - crop.get_height()) / 2))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	canvas.save_png(path)

func _save_strip(out_dir: String, label: String, tiles: Array) -> void:
	var cols := 24
	var rows := PITCHES.size() + 1
	var img := Image.create(cols * N, rows * N, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for vi in tiles.size():
		var t: Image = tiles[vi]
		img.blend_rect(t, Rect2i(0, 0, N, N), Vector2i((vi % cols) * N, (vi / cols) * N))
	img.convert(Image.FORMAT_L8)  # grey keeps the files small
	var dir := out_dir.path_join("outlines")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	img.save_png(dir.path_join(label.replace("/", "__") + ".png"))
