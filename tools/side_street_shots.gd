extends SceneTree

# Side-street mouths and eyes in the headlights, contact sheet (world step 6,
# 2026-10-10): builds chunks with a mouth beside the game's night scene and
# photographs them as the driver sees them (far, from the road), close at
# the mouth, down the side street, and an animal with its eyes lit by a
# headlight-like spot. Needs the real renderer (no --headless). Writes the
# PNGs to user://side_street_shots/ and the sheet to
# docs/design/world/side_streets_<date>.png (or the first user arg).
#
#   <godot> --path . --audio-driver Dummy -s res://tools/side_street_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")
const Districts := preload("res://scripts/world/districts.gd")
const SideStreets := preload("res://scripts/world/side_streets.gd")
const StreetAnimals := preload("res://scripts/world/street_animals.gd")

const W := 480
const H := 270

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var out := "res://docs/design/world/side_streets_2026-10-10.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var dir := "user://side_street_shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var p: Node3D = game.get("player")
	var base := Vector3(400.0, 0.0, p.global_position.z)
	var cfg := {"own_lanes": 2, "onc_lanes": 2, "barrier": false}
	# one mouth per district: the first chunk of each kind with a mouth on
	# the own side (so the driver's view shows it on the right)
	var picks := {}
	for c in range(1, 2000):
		var name := Districts.name_at(c)
		if picks.has(name) or Junction.touches(c - 1) or Junction.touches(c + 1):
			continue
		for m in SideStreets.mouths_at(c):
			if int(m.side) == 1:
				picks[name] = c
				break
		if picks.size() == 4:
			break
	print("side_street_shots: chunks ", picks)
	var x_off := 0.0
	var roots := {}
	var was := Junction.enabled
	Junction.enabled = false
	for name in picks:
		var c: int = picks[name]
		# the chunk before, the chunk with the mouth and the one after, end to end
		var list: Array = []
		for ci in [c - 1, c, c + 1]:
			var ch: Node3D = B.build_chunk(ci, cfg, cfg)
			game.add_child(ch)
			ch.transform = Transform3D(Basis(), base + Vector3(x_off, 0.0, -50.0 * float(ci - (c - 1))))
			list.append(ch)
		roots[name] = list
		x_off += 160.0
	Junction.enabled = was
	for i in 30:
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 55.0
	root.add_child(cam)
	# the HUD and mirrors off: the sheet is about the world
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var views := []
	var eyes_done := false
	for name in picks:
		var ch: Node3D = roots[name][1]
		var placed: Array = ch.get_meta("side_streets")
		var m: Dictionary = {}
		for q in placed:
			if int(q.side) == 1:
				m = q
		if m.is_empty():
			continue
		var kit: Transform3D = m.kit
		var mouth: Vector3 = ch.to_global(kit.origin)
		var z := float(m.z)
		var o := ch.global_position
		# far: the driver's eye in the right lane, 70 m before the mouth
		views.append(["far_" + name, o + Vector3(1.7, 1.1, z + 70.0), o + Vector3(1.7, 0.6, z - 60.0)])
		# near: from the right lane abreast of the mouth, looking into the street
		views.append(["mouth_" + name, o + Vector3(1.7, 1.1, z + 9.0), mouth + Vector3(float(m.len) * 0.5, 0.3, 0.0)])
		# down the street: from the pavement at the mouth, along the lamp side
		views.append(["street_" + name, mouth + Vector3(1.0, 1.4, 1.5), mouth + Vector3(float(m.len), 0.4, 0.0)])
		# eyes: an animal on this chunk (or a neighbour), lit as if by the beam
		if not eyes_done:
			for c in roots[name]:
				var list: Array = (c as Node3D).get_meta("animals")
				if list.is_empty():
					continue
				var a: Dictionary = list[0]
				var mm: MultiMesh = ((c as Node3D).get_node(^"Animals") as MultiMeshInstance3D).multimesh
				mm.set_instance_custom_data(0, Color(1.0, 0.0, 0.0, 0.0))
				var ap: Vector3 = (c as Node3D).to_global(a.pos)
				var nose: Vector3 = (c as Node3D).global_transform.basis * (-(a.basis as Basis).z)
				var spot := SpotLight3D.new()
				spot.spot_range = 40.0
				spot.spot_angle = 30.0
				spot.light_energy = 12.0
				spot.light_color = Color(1.0, 0.94, 0.82)
				root.add_child(spot)
				var from := ap + nose * 12.0 + Vector3(0.0, 0.7, 0.0)
				spot.global_position = from
				spot.look_at(ap + Vector3(0.0, 0.25, 0.0))
				views.append(["eyes_close", ap + nose * 4.0 + Vector3(0.0, 0.8, 0.0), ap + Vector3(0.0, 0.25, 0.0)])
				views.append(["eyes_road", from, ap + Vector3(0.0, 0.25, 0.0)])
				eyes_done = true
				break
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2])
		cam.make_current()
		for i in 10:
			await process_frame
		var path := "%s/%s.png" % [dir, v[0]]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("side_street_shots: ", ProjectSettings.globalize_path(path))
	# the sheet: a row per district (far, mouth, street), then the eyes
	var rows := []
	for name in picks:
		rows.append(["far_" + name, "mouth_" + name, "street_" + name])
	rows.append(["eyes_road", "eyes_close", ""])
	var sheet := Image.create(W * 3, H * rows.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	for r in rows.size():
		for c in 3:
			var n: String = rows[r][c]
			if n == "":
				continue
			var img := Image.load_from_file(ProjectSettings.globalize_path("%s/%s.png" % [dir, n]))
			if img == null:
				continue
			img.resize(W, H, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(c * W, r * H))
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("side_street_shots: wrote ", ProjectSettings.globalize_path(out))
	quit(0)
