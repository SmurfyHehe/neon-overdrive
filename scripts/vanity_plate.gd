class_name VanityPlate
extends RefCounted

# Vanity plates (R1, approved by Roy 2026-10-08): type your own plate, short,
# letters and numbers only, and it shows on the car's front and rear plates.
# The text is kept in user://vanity_plate.txt. The plates are built with the
# body (P1CoupeBuilder puts them where its "plates" meta says, clear of the
# four sticker spots) and their text changes live from the Tuner's Sound page.

const MAX_LEN := 8
const DEFAULT := "OVERDRV"
const FILE := "user://vanity_plate.txt"
const SIZE := Vector2(0.52, 0.115)   # metres, a long European-style plate
const PLATE_COLOR := Color("#C9CED6")  # silver
const TEXT_COLOR := Color("#1B2A4A")   # navy

static var _text := ""
## Where the plate is kept; tests point this at a scratch file.
static var file := FILE

## Upper case, A-Z and 0-9 only, at most MAX_LEN.
static func clean(raw: String) -> String:
	var out := ""
	for ch in raw.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
		if out.length() >= MAX_LEN:
			break
	return out

## The saved plate, or the default if there is none yet.
static func current() -> String:
	if _text == "":
		var saved := FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else ""
		_text = clean(saved) if clean(saved) != "" else DEFAULT
	return _text

## Keeps the plate for next time. An empty plate goes back to the default.
static func save(text: String) -> void:
	_text = clean(text) if clean(text) != "" else DEFAULT
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f != null:
		f.store_string(_text)

## One plate: a silver board with the text in navy on its outward face.
## `at` is its centre and `normal` the way it faces, in the car's space.
static func build(text: String, at: Vector3, normal: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Plate"
	var n := normal.normalized()
	root.transform = Transform3D(Basis.looking_at(-n, Vector3.UP), at)  # +Z faces out
	var board := MeshInstance3D.new()
	board.name = "Board"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SIZE.x, SIZE.y, 0.008)
	board.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLATE_COLOR
	mat.emission_enabled = true  # a plate lamp's worth, so it reads at night
	mat.emission = PLATE_COLOR
	mat.emission_energy_multiplier = 0.25
	mat.roughness = 0.6
	board.material_override = mat
	root.add_child(board)
	var label := Label3D.new()
	label.name = "Text"
	label.text = text
	# Heavy strokes: thin ones break up at chase-camera distance.
	label.font = UiTheme.font("strong")
	label.font_size = 64
	label.pixel_size = 0.0013
	label.modulate = TEXT_COLOR
	label.outline_size = 14
	label.outline_modulate = TEXT_COLOR
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.shaded = false
	label.double_sided = false
	label.position = Vector3(0.0, -0.004, 0.0055)
	root.add_child(label)
	return root

## Puts the plates on a body that has a "plates" meta: [{pos, normal}] in the
## car's space. Bodies without it (the test box) get none.
static func attach(visual: Node3D, text := "") -> void:
	if visual == null or not visual.has_meta("plates"):
		return
	var t := text if text != "" else current()
	for p in visual.get_meta("plates"):
		var plate := build(t, p.pos, p.normal)
		plate.name = "Plate_" + ("Rear" if Vector3(p.normal).z > 0.0 else "Front")
		visual.add_child(plate)

## Changes the text on a body's plates, live.
static func set_text(visual: Node3D, text: String) -> void:
	if visual == null:
		return
	var t := clean(text) if clean(text) != "" else DEFAULT
	for c in visual.get_children():
		if c.name.begins_with("Plate_"):
			(c.get_node("Text") as Label3D).text = t

## The text on a body's plates ("" if it has none).
static func shown(visual: Node3D) -> String:
	if visual == null:
		return ""
	for c in visual.get_children():
		if c.name.begins_with("Plate_"):
			return (c.get_node("Text") as Label3D).text
	return ""
