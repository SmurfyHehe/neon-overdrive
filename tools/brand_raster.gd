extends SceneTree

# Step 2 of tools/build_brand.py: draws the brand SVGs to PNG with Godot's own
# SVG renderer, each icon size at its own size (never scaled down from a big
# one, which is what made the old 16 and 32 px icons mushy).
#
#   godot --headless --path . -s tools/brand_raster.gd

const BRAND := "res://assets/brand/"
const OUT := "res://assets/brand/raster/"
const ICO_SIZES := [16, 20, 24, 32, 40, 48, 64, 128, 256]
const SMALL_MAX := 40
const TINY_MAX := 24

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for s: int in ICO_SIZES:
		var src := "logo_B4_combined_centred.svg"
		if s <= TINY_MAX:
			src = "logo_B4_tiny.svg"
		elif s <= SMALL_MAX:
			src = "logo_B4_small.svg"
		_draw(src, s, "icon_%d.png" % s)
	_draw("logo_B4_combined_centred.svg", 184, "icon_full_184.png")
	_draw("logo_B4_mark.svg", 1024, "mark_1024.png")
	quit()

func _draw(svg_name: String, size: int, out_name: String) -> void:
	var svg := FileAccess.get_file_as_string(BRAND + svg_name)
	var img := Image.new()
	var err := img.load_svg_from_string(svg, size / 256.0)
	if err != OK:
		push_error("could not draw %s" % svg_name)
		return
	img.save_png(OUT + out_name)
	print("drew %s at %d px" % [svg_name, size])
