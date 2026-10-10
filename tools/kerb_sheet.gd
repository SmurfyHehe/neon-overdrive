extends SceneTree

# Contact sheet for the kerb PRs: tools/kerb_shots.gd's before/after PNGs side
# by side (user://kerb_shots/before and /after), plus the new views of the
# after set. Writes docs/design/world/kerbs_cross_section_<date>.png.
#
#   <godot> --headless --path . -s res://tools/kerb_sheet.gd -- <out.png>

const ROWS := [["kerb_close", "kerb_close"], ["pavement_along", "pavement_along"], ["road_wide", "road_wide"], ["strip_drop", "strip_drop"], ["", "freeway_wide"], ["freeway_verge", "drain_downtown"]]
const W := 480
const H := 270

func _initialize() -> void:
	var out := "res://docs/design/world/kerbs_cross_section_2026-10-10.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var base := ProjectSettings.globalize_path("user://kerb_shots")
	var sheet := Image.create(W * 2, H * ROWS.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	for r in ROWS.size():
		for c in 2:
			var name: String = ROWS[r][c]
			if name == "":
				continue
			var path := "%s/%s/%s.png" % [base, "before" if (c == 0 and r < 4) else "after", name]
			if r == 5 and c == 0:
				path = "%s/after/%s.png" % [base, name]
			var img := Image.load_from_file(path)
			if img == null:
				print("missing ", path)
				continue
			img.resize(W, H, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(c * W, r * H))
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("wrote ", ProjectSettings.globalize_path(out))
	quit(0)
