extends SceneTree

# Brake glow shots (Roy, 2026-10-14: discs must not read as one flat cherry
# plate): one wheel on its own in a dark box, lit the way a street lamp
# would, shot at several heats from a chase-camera angle, so the disc's
# heat pattern can be judged by eye. Writes user://brake_glow/<tag>.png and
# checks the peak frame by number: the glowing pixels must be bright (mean
# luminance over PEAK_MEAN) and uneven (their spread over PEAK_SPREAD of the
# mean), so a flat cherry plate fails. Then a vented disc and a drum, shots only.
# Run (real renderer; a window opens briefly):
#   godot --path . --audio-driver Dummy -s res://tests/car/brake_glow_shots.gd
# Env: BRAKE_SHOT_DIR overrides the folder, BRAKE_SHOT_STYLE the rim ("five",
# "mesh", "dish", "steel"), BRAKE_SHOT_VENTED=1 a vented disc.

var frame := 0
var wheel: MeshInstance3D
var cam: Camera3D
var shots: Array = []   # [tag, heat, lag, soak]
var idx := 0
var fails: Array[String] = []
const PEAK_MEAN := 60.0     # 0..255 luminance; PR 695's flat-ish band measured 48
const PEAK_SPREAD := 0.38   # std dev / mean; PR 695's band measured 0.32, this 0.43
const PEAK_PIXELS := 5000   # at 1280x720 the disc is ~22000 glowing pixels
var style := "five"
var vented := false

func _initialize() -> void:
	style = OS.get_environment("BRAKE_SHOT_STYLE")
	if style == "":
		style = "five"
	vented = OS.get_environment("BRAKE_SHOT_VENTED") == "1"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#0E1424")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#1B2A4A")
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var lamp := DirectionalLight3D.new()
	lamp.light_color = Color("#FFC066")
	lamp.light_energy = 0.9
	lamp.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	root.add_child(lamp)
	wheel = MeshInstance3D.new()
	var radius := 0.33
	var rim_r := 17.0 * 0.0254 * 0.5
	wheel.mesh = CarParts.wheel_mesh(radius, 0.245, rim_r, style, false, "disc", vented)
	wheel.set_surface_override_material(0, CarParts._get_wheel_material(Color("#C9CED6")))
	wheel.set_instance_shader_parameter("brake_heat", 0.0)
	wheel.set_instance_shader_parameter("brake_heat_lag", 0.0)
	root.add_child(wheel)
	# The caliper, as CarParts hangs it on the car: on the hub (it steers, it
	# does not spin), level with the disc, behind it toward the car's rear.
	var caliper := MeshInstance3D.new()
	caliper.mesh = CarParts.caliper_mesh(CarParts._disc_radius(rim_r, false), CarParts._disc_thickness(), CarParts.DEFAULT_CFG.caliper_color)
	caliper.set_surface_override_material(0, CarParts._get_part_material())
	caliper.position = Vector3(CarParts._disc_offset(0.245, style), 0.0, 0.0)
	root.add_child(caliper)
	cam = Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	# Outboard (+x), a little ahead and above, as the chase camera sees a front wheel.
	cam.current = true
	shots = [
		["cold", 0.0, 0.0, "disc"],
		["warm", 0.35, 0.15, "disc"],
		["hot", 0.7, 0.4, "disc"],
		["peak", 1.0, 0.7, "disc"],
		["fade", 0.4, 0.9, "disc"],
		["vented_peak", 1.0, 0.7, "vented"],
		["drum_peak", 1.0, 0.7, "drum"],
	]

func _dir() -> String:
	var d := OS.get_environment("BRAKE_SHOT_DIR")
	return d if d != "" else "user://brake_glow"

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		cam.look_at_from_position(Vector3(0.95, 0.25, 0.55), Vector3.ZERO)
	if frame < 10:
		return false
	if idx >= shots.size():
		for f in fails:
			push_error("brake_glow_shots: " + f)
		print("brake_glow_shots: ", "PASS" if fails.is_empty() else "FAIL")
		quit(0 if fails.is_empty() else 1)
		return true
	var s: Array = shots[idx]
	if (frame - 10) % 6 == 0:
		var kind := String(s[3])
		wheel.mesh = CarParts.wheel_mesh(0.33, 0.245, 17.0 * 0.0254 * 0.5, style, false,
			"drum" if kind == "drum" else "disc", vented or kind == "vented")
		wheel.set_instance_shader_parameter("brake_heat", float(s[1]))
		wheel.set_instance_shader_parameter("brake_heat_lag", float(s[2]))
		wheel.rotation.x = 0.4 * float(idx)
	elif (frame - 10) % 6 == 5:
		var img := root.get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir()))
		var path := "%s/%s.png" % [_dir(), s[0]]
		img.save_png(path)
		print("brake_glow_shots: ", ProjectSettings.globalize_path(path))
		if s[0] == "peak":
			_check_pattern(img)
		idx += 1
	return false

## The glowing pixels (red well over green and blue) of the peak frame: bright
## on average, and spread wide round that average, which a flat plate is not.
func _check_pattern(img: Image) -> void:
	var sum := 0.0
	var sum2 := 0.0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var r := c.r * 255.0
			if r > 60.0 and r > c.g * 255.0 * 1.6 and r > c.b * 255.0 * 2.0:
				var l := 0.299 * r + 0.587 * c.g * 255.0 + 0.114 * c.b * 255.0
				sum += l
				sum2 += l * l
				n += 1
	n *= 4   # every other pixel each way
	if n < PEAK_PIXELS:
		fails.append("peak: only %d glowing pixels, wanted %d" % [n, PEAK_PIXELS])
		return
	var mean := sum / float(n / 4)
	var sd := sqrt(maxf(sum2 / float(n / 4) - mean * mean, 0.0))
	print("brake_glow_shots: peak glow %d px, mean %.1f, spread %.3f" % [n, mean, sd / mean])
	if mean < PEAK_MEAN:
		fails.append("peak: glow too dim, mean %.1f under %.1f" % [mean, PEAK_MEAN])
	if sd / mean < PEAK_SPREAD:
		fails.append("peak: glow too even (a flat plate), spread %.3f under %.2f" % [sd / mean, PEAK_SPREAD])
