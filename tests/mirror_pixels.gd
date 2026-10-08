extends SceneTree

# Cockpit mirrors draw the world (2026-10-08), real window (headless has no
# renderer, so no pixels): the other mirror tests only check flags.
# - cockpit view at the default FOV, head at rest, a traffic car 12 m straight
#   behind and one alongside-behind in the left lane: all three mirrors' glass
#   is wholly on screen, and after a second each render target holds a real
#   picture (not one flat colour, not black) and is shown on its glass
# - tap V holding left: the left door mirror still renders, and renders every frame
# - the blind-spot dot on the left is lit
# Saves screenshots to user://mirror_pixels/ (or NEON_SHOTS) for the PR.
# Exit code 1 on failure. Run (needs a window):
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tests/mirror_pixels.gd

const TIMEOUT_TICKS := 60 * 40
const SETTLE := 60
const Harness := preload("res://tests/traffic_harness.gd")

enum Step { BOOT, AHEAD, GLANCE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var shots := ""
var tap_release := -1
var key_state := 0   # 0 idle, 1 send V down on the next idle frame, 2 send V up

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_mirror_pixels_exhaust.json"
	shots = OS.get_environment("NEON_SHOTS")
	if shots == "":
		shots = ProjectSettings.globalize_path("user://mirror_pixels")
	DirAccess.make_dir_recursive_absolute(shots)
	game = Harness.boot(self, 2, 300.0, 7)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _put_cars(p: PlayerCar) -> void:
	var tm: TrafficManager = game.traffic
	var behind: TrafficCar = tm.cars[0]
	behind.place(p.global_position.x, -1.0, p.global_position.z + 12.0, TrafficManager.REST_Y, 0.0)
	var side: TrafficCar = tm.cars[1]
	side.place(p.global_position.x - 3.5, -1.0, p.global_position.z + 4.0, TrafficManager.REST_Y, 0.0)

## Spread of the image's luminance: a real picture of a lit road at night
## varies; a never-drawn target is one flat colour (black or the clear colour).
static func _stats(img: Image) -> Dictionary:
	var n := 0
	var sum := 0.0
	var sq := 0.0
	var step_px := maxi(1, img.get_width() / 64)
	for y in range(0, img.get_height(), step_px):
		for x in range(0, img.get_width(), step_px):
			var l := img.get_pixel(x, y).get_luminance()
			sum += l
			sq += l * l
			n += 1
	var mean := sum / maxf(1.0, n)
	return {"mean": mean, "sd": sqrt(maxf(0.0, sq / maxf(1.0, n) - mean * mean))}

## Share of a glass quad's 5x5 sample grid inside the camera's view, 0..1.
static func _on_screen(cam: Camera3D, glass: MeshInstance3D) -> float:
	var half := (glass.mesh as QuadMesh).size * 0.5
	var inside := 0
	for i in 5:
		for j in 5:
			var q := glass.global_transform * Vector3(lerpf(-half.x, half.x, i / 4.0), lerpf(-half.y, half.y, j / 4.0), 0.0)
			if cam.is_position_in_frustum(q):
				inside += 1
	return inside / 25.0

func _save(img: Image, file: String) -> void:
	if img != null:
		img.save_png(shots.path_join(file))

func _check_mirror(m: CockpitMirrors, i: int, label: String) -> void:
	var img: Image = m.views[i].vp.get_texture().get_image()
	_check(img != null and not img.is_empty(), "%s render target has an image" % label)
	if img == null or img.is_empty():
		return
	_save(img, "%s_%s.png" % [Step.keys()[step].to_lower(), label])
	var s := _stats(img)
	print("  %s %dx%d mean %.3f sd %.3f" % [label, img.get_width(), img.get_height(), s.mean, s.sd])
	_check(s.sd > 0.02, "%s shows a picture, not a flat colour (sd %.3f)" % [label, s.sd])

func _physics_process(_delta: float) -> bool:
	tick += 1
	if game == null or game.get("player") == null or game.get("camera") == null or game.get("traffic") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var waited := tick - step_start
	var m: CockpitMirrors = cam.frame.mirrors if cam.frame != null else null
	match step:
		Step.BOOT:
			if waited < 5:
				return false
			_check(m != null, "the cockpit has mirrors")
			if m == null:
				return _end("")
			print("  mirrors enabled %s, FxSettings mirrors %s" % [m.enabled, FxSettings.is_on("mirrors")])
			cam.shake_enabled = false
			root.size = Vector2i(1280, 720)
			ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT)
			_put_cars(p)
			cam.set_view(ChaseCamera.View.COCKPIT)
			_next(Step.AHEAD)
		Step.AHEAD:
			_put_cars(p)
			if waited < SETTLE:
				return false
			_save(root.get_texture().get_image(), "ahead_screen.png")
			_check(m.enabled, "mirrors are on")
			for i in 3:
				var label: String = ["rear", "left", "right"][i]
				var on := _on_screen(root.get_camera_3d(), m.views[i].quad)
				_check(on == 1.0, "the %s mirror's glass is wholly on screen (%.0f%%)" % [label, on * 100])
				_check_mirror(m, i, label)
				_check(m.views[i].mat.albedo_texture != null, "the %s glass shows its render" % label)
			_check(m.dots[0].visible, "a car alongside-behind on the left lights the left dot")
			Input.action_press("steer_left")
			key_state = 1
			_next(Step.GLANCE)
		Step.GLANCE:
			_put_cars(p)
			if waited < SETTLE:
				return false
			_save(root.get_texture().get_image(), "glance_screen.png")
			_check(m.focus == -1, "glancing at the left door mirror (focus %d)" % m.focus)
			_check_mirror(m, 1, "left")
			_next(Step.DONE)
		Step.DONE:
			return _end("")
	return tick > TIMEOUT_TICKS and _end("Timed out at step %s" % Step.keys()[step])

## The V tap goes in as a real key event between frames, the way the OS
## delivers it, not as an action poked from inside the physics tick.
func _process(_delta: float) -> bool:
	if key_state == 1 or key_state == 2:
		var ev := InputEventKey.new()
		ev.keycode = KEY_V
		ev.physical_keycode = KEY_V
		ev.pressed = key_state == 1
		Input.parse_input_event(ev)
		key_state = 2 if key_state == 1 else 0
	return false

func _next(s: Step) -> void:
	step = s
	step_start = tick

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

func _end(reason: String) -> bool:
	if reason != "":
		failures.append(reason)
	print("Screenshots: " + shots)
	if failures.is_empty():
		print("PASS mirror_pixels")
		quit(0)
	else:
		print("FAIL mirror_pixels: %d failure(s)" % failures.size())
		quit(1)
	return true
