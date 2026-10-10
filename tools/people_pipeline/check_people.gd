extends SceneTree

# People pipeline: checks assets/people/people.json and prints what it makes.
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/people_pipeline/check_people.gd
# Exit code 0 = the kit, the house style and every cast row are good.

func _initialize() -> void:
	var P := PersonBody
	var bad := P.data_problems()
	var pal = load("res://tests/core/palette.gd")
	for list in [P.SKIN_TONES, P.HAIR_COLOURS, P.TOPS, P.BOTTOMS, P.SHOES]:
		for c in list:
			if pal.is_bad(c) != "":
				bad.append("style: %s breaks the game palette (%s)" % [(c as Color).to_html(false), pal.is_bad(c)])
	print("body kit: %d triangles, %d bones, %d heights x %d builds = %d bodies" % [
		P.triangle_count(), P.BONE_COUNT, P.HEIGHTS.size(), P.BUILDS.size(), P.variant_count()])
	print("house style: %d skins, %d hair, %d tops, %d bottoms, %d shoes, %d faces" % [
		P.SKIN_TONES.size(), P.HAIR_COLOURS.size(), P.TOPS.size(), P.BOTTOMS.size(), P.SHOES.size(), P.FACES.size()])
	print("cast:")
	for id in P.cast_ids():
		var p := P.person(id)
		if p.is_empty():
			print("  %-10s BROKEN" % id)
			continue
		var v: Dictionary = p["variant"]
		var t0 := Time.get_ticks_usec()
		var mesh := P.bake_person(id)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("  %-10s %-18s %.2f m %-8s %-12s %-14s %d tris, baked in %.1f ms" % [id, p["role"], v["stature"], v["build"],
			P.FACES[p["face"]], p["pose_name"], mesh.surface_get_array_len(0) / 3, ms])
	for line in bad:
		print("  PROBLEM: ", line)
	print("PASS people.json" if bad.is_empty() else "FAIL people.json: %d problems" % bad.size())
	quit(0 if bad.is_empty() else 1)
